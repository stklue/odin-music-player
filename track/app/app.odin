package app

// import fe "../file"
import common "../common"
import pl "../playlist"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"


AppState :: struct {
	views:                      [100]bool,
	current_view_index:         int, // 0 = all songs // 1 = any playlist songs
	mutex:                      sync.Mutex,
	// current_song:
	current_item_playing:       Maybe(FileEntry),
	is_searching:               bool,

	// playlist
	playlists:                  [dynamic]pl.Playlist,
	// playlists_mutex:          sync.Mutex,
	playlist_index:             int,
	playlist_item_index:        int,
	playlist_item_playling:     ^pl.Playlist_Entry,
	// playlist_selection_mutex: sync.Mutex,
	all_songs_item_playling:    FileEntry,
	current_item_playing_index: int,
	all_songs:                  [dynamic]FileEntry,
	clicked_playlist:           [dynamic]FileEntry,
	playlist_item_clicked:      bool,
	repeat_option:              common.RepeatOption,
}

g_app: ^AppState


FileEntry :: struct {
	info:            os.File_Info,
	name:            cstring,
	fullpath:        cstring,
	lowercase_name:  string,
	index_all_songs: int,
}


init_app :: proc() -> ^AppState {
	state := new(AppState)
	state.current_view_index = 0 // display all songs
	state.views[0] = true // default view should display
	state.playlist_index = -1 // -1 = all the songs playlist
	state.repeat_option = .One
	// state.all_songs_item_playling = nil
	return state
}


playlist_click :: proc() {
	g_app.current_view_index = 1

}


// load files from playlist
load_files_from_pl_thread :: proc(
	mutex: ^sync.Mutex,
	shared: ^[dynamic]FileEntry,
	pl_index: int,
	plists: ^[dynamic]pl.Playlist,
) {
	playlist := plists[pl_index]
	sync.mutex_lock(mutex)
	clear(shared)
	sync.mutex_unlock(mutex)
	for p, i in playlist.entries {

		dir_path := p.src
		dir_handle, err := os.open(dir_path)
		if err != os.ERROR_NONE {
			fmt.println("Failed to open directory: ", err)
			fmt.println("File that failed: ", p.src)
			continue
		}
		defer os.close(dir_handle)
		// Read directory entries
		file_info, fstat_err := os.fstat(dir_handle)
		// files, read_err := os.read_ent(dir_handle, 1024) // Read up to 1024 entries
		if fstat_err != os.ERROR_NONE {
			fmt.println("Failed to read file: ", fstat_err)
			continue
		}


		sync.mutex_lock(mutex)
		entry := FileEntry {
			info           = file_info,
			name           = strings.clone_to_cstring(file_info.name),
			fullpath       = strings.clone_to_cstring(file_info.fullpath),
			lowercase_name = strings.to_lower(file_info.name),
		}
		append(shared, entry)
		// fmt.printf("loaded %d file from playlist of %d songs\n", len(shared), len(playlist.entries))
		sync.mutex_unlock(mutex)
		// get lock for playlists
	}

}
load_files_thread_proc :: proc(mutex: ^sync.Mutex, shared: ^[dynamic]FileEntry) {
	sync.mutex_lock(mutex)
	clear(shared)
	sync.mutex_unlock(mutex)
	dir_path := "C:/Users/St.Klue/Music/Songs"
	dir_handle, err := os.open(dir_path)
	if err != os.ERROR_NONE {
		fmt.println("Failed to open directory: ", err)
	}
	defer os.close(dir_handle)
	// Read directory entries
	files, read_err := os.read_dir(dir_handle, 1024) // Read up to 1024 entries
	if read_err != os.ERROR_NONE {
		fmt.println("Failed to read directory: ", read_err)
	}


	sync.mutex_lock(mutex)
	for file in files {
		entry := FileEntry {
			info           = file,
			name           = strings.clone_to_cstring(file.name),
			fullpath       = strings.clone_to_cstring(file.fullpath),
			lowercase_name = strings.to_lower(file.name),
		}
		append(shared, entry)
	}
	sync.mutex_unlock(mutex)
	fmt.printf("loaded %d files\n", len(files))
}


search_song :: proc(
	state: ^AppState,
	s: string,
	files: ^[dynamic]FileEntry,
	search_results: ^[dynamic]FileEntry,
	search_mutex: ^sync.Mutex,
) {
	sync.mutex_lock(search_mutex)
	clear(search_results)
	sync.mutex_unlock(search_mutex)
	sync.mutex_lock(&state.mutex)
	state.is_searching = true
	sync.mutex_unlock(&state.mutex)

	sync.mutex_lock(search_mutex)
	for file in files {
		if strings.contains(file.lowercase_name, strings.to_lower(s)) {
			append(search_results, file)
		}
	}
	sync.mutex_unlock(search_mutex)
}


search_all_files :: proc(all_paths: ^[dynamic]FileEntry, dir: string) {
	handler, handle_err := os.open(dir)
	if handle_err != nil {
		fmt.println("Failed to open dir: ", dir)
		return

	}
	entries, err := os.read_dir(handler, 1024)
	if err != nil {
		fmt.println("Failed to read dir: ", dir)
		return
	}
	// fmt.printfln("Found %d entries", len(entries))
	for entry in entries {
		path := strings.join([]string{dir, entry.name}, "/")
		// fmt.println(path)
		item := FileEntry {
			info           = entry,
			name           = strings.clone_to_cstring(entry.name),
			fullpath       = strings.clone_to_cstring(entry.fullpath),
			lowercase_name = strings.to_lower(entry.name),
		}
		if !entry.is_dir && strings.has_suffix(entry.name, ".mp3") {
			append(all_paths, item)
		}

		if entry.is_dir {
			search_all_files(all_paths, path) // Recursively search
		}
	}
	// fmt.printfln("Recursive search: %d", len(all_paths))
}


PlaybackState :: struct {
	last_song_path:     string,
	last_playlist_path: string,
	volume:             f32,
	playback_seconds:   f32,
}

// save_playback_state :: proc(filename: string, state: PlaybackState) -> bool {
// 	data := json.write_string(state)
// 	return save_to_file(filename, data)
// }

// read_playback_state :: proc(filename: string) -> PlaybackState {
// 	result: PlaybackState

// 	if !os.exists(filename) {
// 		return result
// 	}

// 	content := read_from_file(filename)
// 	success := json.read_string(content, &result)

// 	if !success {
// 		fmt.println("Failed to parse playback state")
// 	}

// 	return result
// }
