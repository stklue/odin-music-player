package media
import "core:encoding/xml"
import "core:log"
import "core:os"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import "core:unicode/utf16"
import "core:unicode/utf8"


MediaLibrary :: struct {
	arena:           mem.Arena,
	songs:           Songs,
	playlists:       [dynamic]Playlist,
	playlist_thread: ^thread.Thread,
	search_thread:   ^thread.Thread,
	arena_allocator: mem.Allocator,
}

init_library :: proc(library: ^MediaLibrary) {
	arena_mem := make([]byte, 1 * mem.Megabyte)
	mem.arena_init(&library.arena, arena_mem)
	library.arena_allocator = mem.arena_allocator(&library.arena)
	library.songs = make(Songs, 0, 3000)
}

delete_library :: proc(library: ^MediaLibrary) {
	delete_dynamic_array(library.songs)
	delete(library.arena.data)
	log.info("Deleted media library data")
}

RepeatOption :: enum {
	All,
	One,
	Off,
}


Song :: struct {
	info:            os.File_Info,
	name:            cstring,
	fullpath:        cstring, // c filepath
	lowercase_name:  string, // for searching
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


FilesType :: enum {
	List,
	Single,
}


SearchItem :: struct {
	kind:       SongType,
	label:      cstring, // What to display in UI: e.g. "The Beatles (artist)"
	files_type: FilesType,
	file_name:  cstring, // "The Beatles"
}

Songs :: [dynamic]Song


import "core:text/scanner"

// Loads all songs into all_songs
scan_all_files :: proc(
	library: ^MediaLibrary,
	all_songs_mutex: ^sync.Mutex,
	// all_songs: ^Songs,
	all_files_scan_done: ^bool,
) {
	stop_watch: time.Stopwatch
	time.stopwatch_start(&stop_watch)

	metadata_file := "C:/Users/St.Klue/Music/metadata.txt"

	// Read entire file efficiently
	data, ok := os.read_entire_file(metadata_file, context.temp_allocator)
	defer free_all(context.temp_allocator)
	if !ok {
		fmt.eprintln("Unable to read file", metadata_file)
		return
	}

	// Initialize scanner
	s: scanner.Scanner
	scanner.init(&s, string(data))
	s.flags = {} // We don't need token scanning, just lines
	s.whitespace = {'\n'} // Only treat newlines as whitespace

	// Pre-allocate songs array
	line_count := strings.count(string(data), "\n") + 1
	temp_songs := make([dynamic]Song, 0, line_count)

	scanner_watch: time.Stopwatch
	time.stopwatch_start(&scanner_watch)

	current_line: strings.Builder
	strings.builder_init(&current_line)

	for scanner.peek(&s) != scanner.EOF {
		ch := scanner.next(&s)
		if ch == '\n' {
			// Process complete line
			line := strings.to_string(current_line)
			if line != "" {
				process_line(library, &line, &temp_songs)
			}
			strings.builder_reset(&current_line)
		} else {
			strings.write_rune(&current_line, ch)
		}
	}
	time.stopwatch_stop(&scanner_watch)
	fmt.printfln("Scanning processs took %v", scanner_watch._accumulation)

	// Process last line if it wasn't terminated with newline
	if strings.builder_len(current_line) > 0 {
		line := strings.to_string(current_line)
		process_line(library, &line, &temp_songs)
	}

	strings.builder_destroy(&current_line)

	// Bulk transfer to shared collection
	sync.mutex_lock(all_songs_mutex)
	// reserve(all_songs, len(temp_songs))
	append(&library.songs, ..temp_songs[:])
	all_files_scan_done^ = true
	sync.mutex_unlock(all_songs_mutex)

	time.stopwatch_stop(&stop_watch)
	fmt.printfln("Processed %d files in %v", len(temp_songs), stop_watch._accumulation)
}

time_proc :: proc(message: string, run: proc()) {
	sw: time.Stopwatch
	time.stopwatch_start(&sw)
	run()
	time.stopwatch_stop(&sw)
	fmt.printfln("%s %v", message, sw._accumulation)
}

process_line :: proc(library: ^MediaLibrary, line: ^string, songs: ^[dynamic]Song) {
	// Skip empty lines
	if strings.trim_space(line^) == "" do return

	// Optimized splitting
	parts: [7]string
	count := 0

	for s in strings.split_iterator(line, "=x=") {
		if count >= 7 do break
		parts[count] = s
		count += 1
	}

	if count < 2 do return // Invalid line format

	// Build path efficiently
	path := fmt.tprintf("%s/%s", parts[0], parts[1])

	// TODO: if this is stil needed can scedule in a different thread
	// resulted in 94% of time spend, so approximately 940ms for 1s run
	// // Try to open file directly (skip exists check)
	// os_open_handler_time: time.Stopwatch
	// time.stopwatch_start(&os_open_handler_time)
	// handler, handler_err := os.open(path)
	// if handler_err != os.ERROR_NONE {
	// 	return
	// }
	// time.stopwatch_stop(&os_open_handler_time)
	// // fmt.printfln("Os Open took %v", os_open_handler_time._accumulation)
	// defer os.close(handler)

	// fstat_time: time.Stopwatch
	// time.stopwatch_start(&fstat_time)
	// file_info, read_err := os.fstat(handler)
	// if read_err != os.ERROR_NONE {
	// 	return
	// }
	// time.stopwatch_stop(&fstat_time)
	// fmt.printfln("Fstat took %v", fstat_time._accumulation)

	new_path, was_alloc := strings.replace_all(path, "/", "\\")
	// fmt.printfln("New %s",  windows.utf8_to_wstring(new_path))
	// fmt.println("Os", file_info.fullpath)

	item := Song {
		// info           = file_info,
		name           = strings.clone_to_cstring(parts[1], library.arena_allocator),
		// fullpath       = strings.clone_to_cstring(file_info.fullpath),
		fullpath       = strings.clone_to_cstring(new_path, library.arena_allocator),
		lowercase_name = strings.to_lower(parts[1]),
		dir            = new_path,
		valid_metadata = false,
	}

	if count >= 7 {
		item.metadata.title = strings.clone_to_cstring(parts[2], library.arena_allocator)
		item.metadata.artist = strings.clone_to_cstring(parts[3], library.arena_allocator)
		item.metadata.album = strings.clone_to_cstring(parts[4], library.arena_allocator)
		item.metadata.year = strings.clone_to_cstring(parts[5], library.arena_allocator)
		item.metadata.genre = strings.clone_to_cstring(parts[6], library.arena_allocator)
	}

	append(songs, item)
}
Playlist_Metadata :: struct {
	total_duration: string,
	item_count:     string,
	generator:      string,
	title:          string,
}

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
					entry := Song{}
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
	library: ^MediaLibrary,
	all_playlists_mutex: ^sync.Mutex,
	all_playlists_scan_done: ^bool,
) {
	stop_watch: time.Stopwatch
	time.stopwatch_start(&stop_watch)
	folder_path := "C:/Users/St.Klue/Music/Playlists"
	dir_handle, err := os.open(folder_path)
	if err != os.ERROR_NONE {
		log.error("Failed to open directory: ", err)
	}
	defer os.close(dir_handle)
	// Get all files in the directory
	files, read_err := os.read_dir(dir_handle, -1)
	if read_err != nil {
		log.error("Failed to read directory:", folder_path)
	}
	sync.mutex_lock(all_playlists_mutex)
	for file in files {
		if !file.is_dir && strings.has_suffix(file.name, ".zpl") {
			// full_path := path.join(folder_path, file.name)
			playlist, ok := scan_zpl_playlist(file.fullpath)
			if ok {
				append(&library.playlists, playlist)
			}
		}
	}
	all_playlists_scan_done^ = true
	sync.mutex_unlock(all_playlists_mutex)
	time.stopwatch_stop(&stop_watch)
	fmt.printfln(
		"Playlists (.zpl) %d/%d scanned in %v",
		len(library.playlists),
		len(files),
		stop_watch._accumulation,
	)
}


// load files from playlist
scan_playlist_entries :: proc(
	playlist_mutex: ^sync.Mutex,
	playlist: ^Playlist,
	playlist_entries: ^[dynamic]Song,
	scan_playlist_done: ^bool,
) {
	stop_watch: time.Stopwatch
	time.stopwatch_start(&stop_watch)
	sync.mutex_lock(playlist_mutex)
	clear(playlist_entries)
	sync.mutex_unlock(playlist_mutex)

	found_entries: int
	for &p, i in playlist.entries {
		dir_path := p.fullpath
		dir_handle, err := os.open(strings.clone_from_cstring(dir_path))
		if err != nil {
			log.warn("Failed to open directory: ", dir_path, err)
			continue
		}

		defer os.close(dir_handle)
		file_info, fstat_err := os.fstat(dir_handle)
		if fstat_err != nil {
			log.warn("Failed to read file: ", fstat_err)
			continue
		}
		// entry := Song {
		// 	info           = file_info,
		// 	name           = strings.clone_to_cstring(file_info.name),
		// 	fullpath       = strings.clone_to_cstring(file_info.fullpath),
		// 	lowercase_name = strings.to_lower(file_info.name),
		// }
		p.info = file_info
		sync.mutex_lock(playlist_mutex)
		append(playlist_entries, p)
		sync.mutex_unlock(playlist_mutex)
		found_entries += 1
	}

	time.stopwatch_stop(&stop_watch)
	fmt.printfln(
		"Scanned %d playlist entries. Found %d.  Took %v",
		len(playlist.entries),
		found_entries,
		stop_watch._accumulation,
	)
}


import taglib "../../taglib-odin"
import "core:mem"
import image "vendor:stb/image"
