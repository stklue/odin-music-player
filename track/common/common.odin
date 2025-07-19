package common
import "core:encoding/xml"
import "core:os"
import "core:strings"
import "core:sync"
import "core:time"

RepeatOption :: enum {
	All,
	One,
	Off,
}


FileEntry :: struct {
	info:            os.File_Info,
	name:            cstring,
	fullpath:        cstring,
	lowercase_name:  string,
	index_all_songs: int,
	metadata:        Metadata,
	valid_metadata:  bool,
	dir:             string,
}

Metadata :: struct {
	filename: cstring,
	title:    cstring,
	artist:   cstring,
	album:    cstring,
	year:     cstring,
	genre:    cstring,
	// duration: cstring,
}

import "core:fmt"
import "core:sys/windows"


SongType :: enum {
	Title,
	Album,
	Artist,
}

ListOrSingle :: union {
	[dynamic]FileEntry,
	FileEntry,
}

SearchItem :: struct {
	kind:  SongType,
	label: cstring, // What to display in UI: e.g. "The Beatles (artist)"
	files: ListOrSingle, // Associated files (empty for artist/album)
}


// App_Messages::enum {
// 	AUDIO_PAUSE_MSG,
// 	AUDIO_PLAY_MSG,
// 	UI_CLICKED_DIFFERENT_SONG_MSG,
// 	UI_
// }


scan_all_files :: proc(
	all_songs_mutex: ^sync.Mutex,
	all_songs: ^[dynamic]FileEntry,
	all_files_scan_done: ^bool,
) {
	stop_watch: time.Stopwatch
	time.stopwatch_start(&stop_watch)
	root := "C:/Users/St.Klue/Music"
	metadata_file := "C:/Users/St.Klue/Music/metadata.txt"

	// Check if metadata file exists first
	if !os.exists(metadata_file) {
		fmt.eprintln("Metadata file does not exist:", metadata_file)
		return
	}

	bytes_read, read_error := os.read_entire_file_from_filename_or_err(metadata_file)
	if read_error != nil {
		fmt.eprintln("Unable to read file", metadata_file, read_error)
		return
	}

	content := string(bytes_read)
	lines := strings.split_lines(content)

	sync.mutex_lock(all_songs_mutex)
	for line in lines {
		// Skip empty lines
		if strings.trim_space(line) == "" do continue

		res, alloc_err := strings.split(line, "=x=")
		if alloc_err != nil {
			fmt.println("Allocator error for string split", alloc_err)
			return
		}

		if len(res) == 1 {
			// end of files reached
			continue
		}
		// Check if we have enough parts
		if len(res) < 2 {
			fmt.println("Invalid line format (not enough parts):", line)
			continue
		}

		// Use filepath.join for proper path construction
		path := strings.join([]string{res[0], res[1]}, "/")

		// Check if file exists before trying to open it
		if !os.exists(path) {
			fmt.println("File does not exist:", path)
			continue
		}

		handler, handler_err := os.open(path, os.O_RDONLY)
		if handler_err != nil {
			fmt.println("Error opening file", path, handler_err)
			continue
		}
		defer os.close(handler) // Important: close the file handle

		file_info, read_err := os.fstat(handler)
		if read_err != nil {
			fmt.println("Error getting file info", path, read_err)
			continue
		}
		new_path, _ := strings.replace_all(path, "/", "\\")
		item := FileEntry {
			info           = file_info,
			name           = strings.clone_to_cstring(res[1]),
			fullpath       = strings.clone_to_cstring(file_info.fullpath),
			lowercase_name = strings.to_lower(res[1]),
			dir            = new_path,
		}

		// Check if we have enough metadata fields
		if len(res) >= 7 {
			item.metadata.title = strings.clone_to_cstring(res[2])
			item.metadata.artist = strings.clone_to_cstring(res[3])
			item.metadata.album = strings.clone_to_cstring(res[4])
			item.metadata.year = strings.clone_to_cstring(res[5])
			item.metadata.genre = strings.clone_to_cstring(res[6])
		} else {
			fmt.println("Warning: incomplete metadata for", path)
		}

		item.valid_metadata = false
		append(all_songs, item)
	}
	all_files_scan_done^ = true
	sync.mutex_unlock(all_songs_mutex)
	time.stopwatch_stop(&stop_watch)
	fmt.printfln(
		"Found %d files in %v",
		len(all_songs),
		stop_watch._accumulation,
	)
}


Playlist_Metadata :: struct {
	total_duration: string,
	item_count:     string,
	generator:      string,
	title:          string,
}

Songs :: [dynamic]FileEntry
Playlist :: struct {
	meta:    Playlist_Metadata,
	entries: Songs,
}


PlaylistTypes :: enum {
	Global,
	Local,
}

scan_zpl_playlist :: proc(path: string) -> (playlist: Playlist, ok: bool) {

	doc, err := xml.load_from_file(path)
	if err != nil {
		fmt.println("Failed to load XML.")
		return Playlist{}, false
	}

	playlist_res: Playlist

	entries: Songs

	root_id: u32 = 0
	smil_id, smil_found := xml.find_child_by_ident(doc, root_id, "smil", 1)

	head_id, head_found := xml.find_child_by_ident(doc, smil_id, "head")
	if !head_found {
		fmt.println("Missing <body> tag.")
		return Playlist{}, false
	}

	playlist_metadata: Playlist_Metadata

	// Loop through <head>'s children
	for val in doc.elements[head_id].value {
		switch value_data in val {
		case string:
			fmt.println("head value was a string")
		case u32:
			{
				elem := &doc.elements[value_data]

				// Look for <meta> tags
				if elem.ident == "meta" {
					name := ""
					content := ""

					for attr in elem.attribs {
						switch attr.key {
						case "name":
							name = attr.val
						case "content":
							content = attr.val
						}
					}

					// Store known meta fields
					switch name {
					case "totalDuration":
						playlist_metadata.total_duration = content
					case "itemCount":
						playlist_metadata.item_count = content
					case "generator":
						playlist_metadata.generator = content
					}
				}

				// Look for <title> tag
				if elem.ident == "title" && len(elem.value) > 0 {
					switch title_data in elem.value[0] {
					case u32:
						fmt.println("val data for title was a u32")
					case string:
						{
							if title_data != "" {
								playlist_metadata.title = title_data
							}
						}
					}

				}
			}}
	}

	//  Playlist entries
	body_id, body_found := xml.find_child_by_ident(doc, smil_id, "body")
	if !body_found {
		fmt.println("Missing <body> tag.")
		return Playlist{}, false
	}

	seq_id, seq_found := xml.find_child_by_ident(doc, body_id, "seq")
	if !seq_found {
		fmt.println("Missing <seq> tag.")
		return Playlist{}, false
	}

	// Iterate all children of <seq>
	for val in doc.elements[seq_id].value {
		switch x in val {
		case string:
			{fmt.println("value was a string")}
		case u32:
			{ 	// assuming u32 == child ID
				child_id := x
				child := &doc.elements[child_id]

				unknown_title: cstring
				if child.ident == "media" {
					entry := FileEntry{}
					for attr in child.attribs {
						if attr.key == "src" {
							entry.fullpath = strings.clone_to_cstring(attr.val)
							res, _ := strings.split(attr.val, "\\")
							unknown_title = strings.clone_to_cstring(res[len(res) - 1])
							// fmt.println("Found srcs: ", attr.val)
						}

						switch attr.key {
						case "src":
							entry.fullpath = strings.clone_to_cstring(attr.val)
						case "albumTitle":
							// entry.metadata.album = len(taglib.tag_album(tag)) > 0 ? strings.clone_from_cstring(taglib.tag_album(tag)) : "Unknown Album"
							entry.metadata.album =
								len(attr.val) > 0 ? strings.clone_to_cstring(attr.val) : "Unknown Album"
						case "albumArtist":
							entry.metadata.artist =
								len(attr.val) > 0 ? strings.clone_to_cstring(attr.val) : "Unknown Artist"
						case "trackTitle":
							entry.metadata.title =
								len(attr.val) > 0 && len(attr.val) < 25 ? strings.clone_to_cstring(attr.val) : strings.clone_to_cstring(fmt.tprintf("%s...", attr.val[:25]))
						// entry.metadata.title =
						// 	len(attr.val) > 0 ? strings.clone_to_cstring(attr.val) : unknown_title
						case "trackArtist":
							entry.metadata.artist =
								len(attr.val) > 0 ? strings.clone_to_cstring(attr.val) : "Unknown Artists"
						case "duration":
						// entry.metadata. = attr.val
						}
					}
					append(&entries, entry)
				}
			}
		}
	}

	playlist_res.meta = playlist_metadata
	playlist_res.entries = entries

	return playlist_res, true
}

scan_all_playlists :: proc(
	all_playlists_mutex: ^sync.Mutex,
	all_playlists: ^[dynamic]Playlist,
	all_playlists_scan_done: ^bool,
) {
	stop_watch: time.Stopwatch
	time.stopwatch_start(&stop_watch)
	folder_path := "C:/Users/St.Klue/Music/Playlists"
	dir_handle, err := os.open(folder_path)
	if err != os.ERROR_NONE {
		fmt.println("Failed to open directory: ", err)
	}
	defer os.close(dir_handle)
	// Get all files in the directory
	files, read_err := os.read_dir(dir_handle, -1)
	if read_err != nil {
		fmt.println("Failed to read directory:", folder_path)
	}
	sync.mutex_lock(all_playlists_mutex)
	for file in files {
		if !file.is_dir && strings.has_suffix(file.name, ".zpl") {
			// full_path := path.join(folder_path, file.name)
			playlist, ok := scan_zpl_playlist(file.fullpath)
			if ok {
				// sync.mutex_lock(all_playlists_mutex)
				append(all_playlists, playlist)
				// sync.mutex_unlock(all_playlists_mutex)
			}
		}
	}
	all_playlists_scan_done^ = true
	sync.mutex_unlock(all_playlists_mutex)
	time.stopwatch_stop(&stop_watch)
	fmt.printfln(
		"Playlists (.zpl) %d/%d scanned in %v",
		len(all_playlists),
		len(files),
		stop_watch._accumulation,
	)
	// fmt.println(all_playlists[0])

}


// load files from playlist
scan_playlist_entries :: proc(
	playlist_mutex: ^sync.Mutex,
	playlist: ^Playlist,
	playlist_entries: ^[dynamic]FileEntry,
	scan_playlist_done: ^bool,
) {
	stop_watch: time.Stopwatch
	time.stopwatch_start(&stop_watch)
	sync.mutex_lock(playlist_mutex)
	clear(playlist_entries)
	sync.mutex_unlock(playlist_mutex)

	// fmt.println("Playlist length: ", playlist.entries[0])
	for &p, i in playlist.entries {
		fmt.println(p.fullpath)
		dir_path := p.fullpath
		// // path := "C:/Users/St.Klue/Music/Songs/Running [Dyalla Flip from 4 Producers 1 Sample].mp3"
		// path := "C:\\Users\\St.Klue\\Music\\Artists\\August Alsina\\August Alsina - Forever and a Day [Official Audio] 2019.mp3"
		dir_handle, err := os.open(strings.clone_from_cstring(dir_path))
		// dir_handle, err := os.open(path)
		if err != nil {
			fmt.eprintln("Failed to open directory: ", dir_path, err)
			continue
		}

		defer os.close(dir_handle)
		file_info, fstat_err := os.fstat(dir_handle)
		if fstat_err != nil {
			fmt.println("Failed to read file: ", fstat_err)
			continue
		}
		// entry := FileEntry {
		// 	info           = file_info,
		// 	name           = strings.clone_to_cstring(file_info.name),
		// 	fullpath       = strings.clone_to_cstring(file_info.fullpath),
		// 	lowercase_name = strings.to_lower(file_info.name),
		// }
		p.info = file_info
		// p.metadata.title = len(p.fullpath) < 20 ? p.fullpath: p.fullpath[:20]
		sync.mutex_lock(playlist_mutex)
		append(playlist_entries, p)
		// // fmt.printf("loaded %d file from playlist of %d songs\n", len(shared), len(playlist.entries))
		sync.mutex_unlock(playlist_mutex)
		// get lock for playlists
	}

	sync.mutex_lock(playlist_mutex)
	shrink(playlist_entries)
	sync.mutex_unlock(playlist_mutex)

	time.stopwatch_stop(&stop_watch)
	fmt.printfln(
		"Scanning %d playlist entries took %v",
		len(playlist.entries),
		stop_watch._accumulation,
	)
}
