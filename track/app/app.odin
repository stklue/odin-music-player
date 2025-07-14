package app

import "core:flags"
import "core:sys/windows"
// import fe "../file"
import taglib "../../taglib-odin"
import common "../common"
import pl "../playlist"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"


AppState :: struct {
	mutex:                      sync.Mutex,
	// current_song:
	current_item_playing:       Maybe(common.FileEntry),
	is_searching:               bool,
	current_view_index:         int,
	// playlist
	playlists:                  [dynamic]pl.Playlist,
	playlist_index:             int,
	playlist_item_index:        int,
	playlist_item_playling:     ^common.FileEntry,
	all_songs_item_playling:    common.FileEntry,
	current_item_playing_index: int,
	search_result_index:        int,
	all_songs:                  [dynamic]common.FileEntry,
	clicked_playlist:           [dynamic]common.FileEntry,
	playlist_item_clicked:      bool,
	total_files:                int,
	taglib_total_duration:      time.Duration,
	taglib_file_count:          int,
	all_files_scanned_donr:     bool,
	show_search_results:     bool,
}

g_app: ^AppState

init_app :: proc() -> ^AppState {
	state := new(AppState)
	state.playlist_index = -1 // -1 = all the songs playlist
	return state
}


// load files from playlist
load_files_from_pl_thread :: proc(
	mutex: ^sync.Mutex,
	shared: ^[dynamic]common.FileEntry,
	pl_index: int,
	plists: ^[dynamic]pl.Playlist,
) {
	playlist := plists[pl_index]
	sync.mutex_lock(mutex)
	clear(shared)
	sync.mutex_unlock(mutex)
	for p, i in playlist.entries {

		dir_path := p.fullpath
		dir_handle, err := os.open(strings.clone_from_cstring(dir_path))
		if err != os.ERROR_NONE {
			fmt.println("Failed to open directory: ", err)
			fmt.println("File that failed: ", p.fullpath)
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
		entry := common.FileEntry {
			info           = file_info,
			name           = fmt.ctprint(file_info.name),
			fullpath       = fmt.ctprint(file_info.fullpath),
			lowercase_name = strings.to_lower(file_info.name),
		}
		append(shared, entry)
		// fmt.printf("loaded %d file from playlist of %d songs\n", len(shared), len(playlist.entries))
		sync.mutex_unlock(mutex)
		// get lock for playlists
	}

}
load_files_thread_proc :: proc(mutex: ^sync.Mutex, shared: ^[dynamic]common.FileEntry) {
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
		entry := common.FileEntry {
			info           = file,
			name           = fmt.ctprint(file.name),
			fullpath       = fmt.ctprint(file.fullpath),
			lowercase_name = strings.to_lower(file.name),
		}
		append(shared, entry)
	}
	sync.mutex_unlock(mutex)
	fmt.printf("loaded %d files\n", len(files))
}


search_song_2 :: proc(
	state: ^AppState,
	query: string,
	files: ^[dynamic]common.FileEntry,
	search_results: ^[dynamic]common.SearchItem,
	search_mutex: ^sync.Mutex,
) {
	sync.mutex_lock(search_mutex)
	clear(search_results)
	sync.mutex_unlock(search_mutex)

	query := strings.to_lower(query)

	// Track which albums and artists we've already added
	found_albums := map[string]bool{}
	found_artists := map[string]bool{}

	// Song matches are kept separate
	song_matches: [dynamic]common.FileEntry

	for file in files {
		title := strings.to_lower(fmt.tprint(file.metadata.title))
		album := strings.to_lower(fmt.tprint(file.metadata.album))
		artist := strings.to_lower(fmt.tprint(file.metadata.artist))
		filename := file.lowercase_name

		// Check for album match
		if album != "" && strings.contains(album, query) && !found_albums[album] {
			found_albums[album] = true
			item := common.SearchItem {
				kind  = .Album,
				label = strings.clone_to_cstring(fmt.tprintf("%s (album)", file.metadata.album)),
			}


			album_items : [dynamic]common.FileEntry
			// for file in files {
			// 	if strings.contains(strings.to_lower(strings.clone_from_cstring(file.metadata.album)), query) {
			// 		// sync.mutex_lock(search_mutex)
			// 		append(&album_items, file)
			// 		// sync.mutex_unlock(search_mutex)

			// 	}
			// }
			// item.files = album_items
			
			sync.mutex_lock(search_mutex)
			append(search_results, item)
			sync.mutex_unlock(search_mutex)
		}

		// Check for artist match
		if artist != "" && strings.contains(artist, query) && !found_artists[artist] {
			found_artists[artist] = true
			item := common.SearchItem {
				kind  = .Artist,
				label = strings.clone_to_cstring(fmt.tprintf("%s (artist)", file.metadata.artist)),
			}
			sync.mutex_lock(search_mutex)
			append(search_results, item)
			sync.mutex_unlock(search_mutex)
		}

		// Check for title or filename match
		if strings.contains(title, query) || strings.contains(filename, query) {
			append(&song_matches, file)
		}
	}

	// Add matching songs at the end
	if len(song_matches) > 0 {
		for match in song_matches {
			label := fmt.tprint(match.metadata.title)
			item := common.SearchItem {
				kind  = .Title,
				label = strings.clone_to_cstring(label),
				files = match,
			}
			sync.mutex_lock(search_mutex)
			append(search_results, item)
			sync.mutex_unlock(search_mutex)
		}
	}

	sync.mutex_lock(&state.mutex)
	state.is_searching = true
	sync.mutex_unlock(&state.mutex)
}


// search_album :: proc (&album) {

// }

search_song :: proc(
	state: ^AppState,
	s: string,
	files: ^[dynamic]common.FileEntry,
	search_results: ^[dynamic]common.FileEntry,
	search_mutex: ^sync.Mutex,
) {
	sync.mutex_lock(search_mutex)
	clear(search_results)
	state.is_searching = true
	sync.mutex_unlock(search_mutex)

	for file in files {
		if strings.contains(file.lowercase_name, strings.to_lower(s)) {
			sync.mutex_lock(search_mutex)
			append(search_results, file)
			sync.mutex_unlock(search_mutex)
		}
	}

}

is_valid_path :: proc(path: string) -> bool {
	for r in path {
		if r < 32 || r > 126 {
			// Skip non-ASCII printable characters that might cause issues
			if r != '/' && r != '\\' && r != ':' {
				return false
			}
		}
	}
	return true
}
media_extensions :: []string{".mp3"}
// TODO: To run search_all_files would first have to create the metaadata.txt file and then search that
search_all_files_archive :: proc(dir: string) {

	g_app.total_files += 1
	handler, handle_err := os.open(dir)
	defer os.close(handler)
	if handle_err != nil {
		fmt.eprintln("Failed to open dir: ", dir, handle_err)
		return
	}
	entries, err := os.read_dir(handler, -1)
	if err != nil {
		fmt.eprintln("Failed to read dir: ", dir, err)
		return
	}
	for entry in entries {
		path := strings.join([]string{dir, entry.name}, "/")

		item := common.FileEntry {
			info           = entry,
			name           = strings.clone_to_cstring(entry.name),
			fullpath       = strings.clone_to_cstring(entry.fullpath),
			lowercase_name = strings.to_lower(entry.name),
			dir            = dir,
		}

		if entry.is_dir {
			search_all_files_archive(path)
		} else {

			if strings.has_suffix(item.lowercase_name, ".mp3") {
				path_cstr := fmt.ctprint(path)
				stop_watch: time.Stopwatch
				time.stopwatch_start(&stop_watch)

				// Bottleneck

				file := taglib.file_new(path_cstr)
				defer taglib.file_free(file) // memory sky rockets when not cleaned up

				tag := taglib.file_tag(file)
				if tag.dummy == 0 {
					if len(item.name) > 20 {
						truncated := fmt.tprintf("%.20s...", item.info.name[:20])
						item.metadata.title = strings.clone_to_cstring(truncated)
					} else {
						item.metadata.title = item.name
					}

					item.metadata.artist = "Unknown Artist"
					item.metadata.year = ""
					item.metadata.album = "Unknown Album"
					item.metadata.genre = "Unknown Genre"
					item.valid_metadata = false

					g_app.taglib_file_count += 1

					append(&g_app.all_songs, item)
					continue
				}

				//! CAN FIX: Should be a better way to fix this
				title := taglib.tag_title(tag)

				// if len(title) > 0 {
				// 	if len(title) > 20 {
				// 		truncated := fmt.tprintf("%.20s...", title)
				// 		item.metadata.title = strings.clone_to_cstring(truncated)

				// 	} else {
				// 		item.metadata.title = title
				// 	}
				// } else {
				// 	//  use the filename as the title
				// 	if len(item.name) > 20 {
				// 		truncated := fmt.tprintf("%.20s...", item.name)
				// 		item.metadata.title = strings.clone_to_cstring(truncated)
				// 	} else {
				// 		item.metadata.title = item.name
				// 	}
				// }
				item.metadata.title =
					len(title) > 0 ? title : strings.clone_to_cstring(item.info.name)

				item.metadata.artist =
					len(taglib.tag_artist(tag)) > 0 ? taglib.tag_artist(tag) : "Unknown Artist"
				item.metadata.year = strings.clone_to_cstring(
					fmt.tprintf("%d", taglib.tag_year(tag)),
				)
				item.metadata.album =
					len(taglib.tag_album(tag)) > 0 ? taglib.tag_album(tag) : "Unknown Album"
				item.metadata.genre =
					len(taglib.tag_genre(tag)) > 0 ? taglib.tag_genre(tag) : "Unknown Genre"
				item.valid_metadata = true

				time.stopwatch_stop(&stop_watch)
				duration := stop_watch._accumulation

				g_app.taglib_total_duration += duration
				g_app.taglib_file_count += 1

				append(&g_app.all_songs, item)
			}
		}
	}
}

scan_all_files :: proc(root: string) {
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

	fmt.println("Read so many bytes: ", len(bytes_read))
	content := string(bytes_read)
	lines := strings.split_lines(content)

	for line in lines {
		g_app.total_files += 1
		// Skip empty lines
		if strings.trim_space(line) == "" do continue

		// fmt.println(line)
		res, alloc_err := strings.split(line, "=x=")
		if alloc_err != nil {
			fmt.println("Allocator error for string split", alloc_err)
			return
		}

		// fmt.println("Result: ", res)
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
			continue // Don't return, just skip this file
		}
		defer os.close(handler) // Important: close the file handle

		file_info, read_err := os.fstat(handler)
		if read_err != nil {
			fmt.println("Error getting file info", path, read_err)
			continue
		}
		new_path, _ := strings.replace_all(path, "/", "\\")
		// fmt.println("This is the new path: ", new_path)
		item := common.FileEntry {
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

		g_app.taglib_file_count += 1

		append(&g_app.all_songs, item)
	}
	return
}

// Writes the metadata to a textfile and then return the number of files/item written
// path, title, artist, album, genre, year, duration
write_metadata_to_txt :: proc(files: [dynamic]common.FileEntry) -> os.Error {
	// write to music directory
	path := "C:/Users/St.Klue/Music/metadata.txt"
	handler, handl_err := os.open(path, os.O_WRONLY | os.O_CREATE | os.O_TRUNC)
	defer os.close(handler)
	if handl_err != nil {
		fmt.eprintln("Error opening path: ", path, handl_err)
		return handl_err // nothing was written
	}

	for file in files {
		// Write the string followed by a newline
		str := fmt.tprintf(
			"%s=x=%s=x=%s=x=%s=x=%s=x=%s=x=%s\n",
			file.dir,
			file.info.name,
			file.metadata.title,
			file.metadata.artist,
			file.metadata.album,
			file.metadata.year,
			file.metadata.genre,
		)
		bytes_written, write_err := os.write_string(handler, str)
		if write_err != 0 {
			fmt.eprintf("Failed to write to file: %v\n", write_err)
			return write_err
		}

		// newline_written, nl_err := os.write_string(file, "\n")
		// if nl_err != 0 {
		//     fmt.eprintf("Failed to write newline: %v\n", nl_err)
		//     return -1
		// }
	}


	return os.ERROR_NONE
}


// Work item for threading - represents a file to process
Work_Item :: struct {
	file_path: string,
	file_info: os.File_Info,
	directory: string,
}

// Shared data structure for threads
Shared_Data :: struct {
	work_queue:    [dynamic]Work_Item,
	results:       [dynamic]common.FileEntry,
	queue_mutex:   sync.Mutex,
	results_mutex: sync.Mutex,
	completed:     bool,
}

// Collect all MP3 files recursively first (single-threaded)
collect_mp3_files :: proc(work_queue: ^[dynamic]Work_Item, dir: string) {
	handler, handle_err := os.open(dir)
	if handle_err != nil {
		fmt.printf("Failed to open dir: %s\n", dir)
		return
	}
	defer os.close(handler)

	entries, err := os.read_dir(handler, -1) // Read all entries at once
	if err != nil {
		fmt.printf("Failed to read dir: %s\n", dir)
		return
	}

	for entry in entries {
		if entry.is_dir {
			path := strings.join([]string{dir, entry.name}, "/")
			collect_mp3_files(work_queue, path) // Recursively collect
		} else if strings.has_suffix(strings.to_lower(entry.name), ".mp3") {
			work_item := Work_Item {
				file_path = strings.clone(entry.fullpath),
				file_info = entry,
				directory = strings.clone(dir),
			}
			append(work_queue, work_item)
		}
	}
}

// Thread worker procedure - processes MP3 files
process_mp3_worker :: proc(shared_data: ^Shared_Data, thread_id: int) {
	processed_count := 0

	for {
		// Get work item from queue
		sync.mutex_lock(&shared_data.queue_mutex)
		work_item, has_work := pop_front_safe(&shared_data.work_queue)
		queue_empty := len(shared_data.work_queue) == 0
		sync.mutex_unlock(&shared_data.queue_mutex)

		if !has_work {
			if queue_empty {
				break // No more work to do
			}
			continue
		}

		// Process the MP3 file
		file_entry := process_single_mp3(work_item)


		// Add result to shared results
		sync.mutex_lock(&shared_data.results_mutex)
		append(&shared_data.results, file_entry)
		sync.mutex_unlock(&shared_data.results_mutex)

		processed_count += 1

		// Optional: Print progress
		// if processed_count % 50 == 0 {
		// 	fmt.printf("[THREAD %02d] Processed %d files\n", thread_id, processed_count)
		// }
	}

	// fmt.printf("[THREAD %02d] Finished processing %d files\n", thread_id, processed_count)
}

// Process a single MP3 file (your existing logic cleaned up)
process_single_mp3 :: proc(work_item: Work_Item) -> common.FileEntry {
	entry := work_item.file_info


	item := common.FileEntry {
		info           = entry,
		name           = fmt.ctprint(entry.name),
		fullpath       = fmt.ctprint(entry.fullpath),
		lowercase_name = strings.to_lower(entry.name),
	}


	// check if file path exists
	if !os.exists(work_item.file_path) {
		item.valid_metadata = false
		return item
	}


	// Process with TagLib
	if !entry.is_dir && strings.has_suffix(entry.name, ".mp3") {
		file := taglib.file_new(item.fullpath)

		defer taglib.file_free(file) // memory sky rockets when not cleaned up

		// Get the tag information
		tag := taglib.file_tag(file)
		if tag.dummy == 0 {
			if len(item.name) > 20 {
				truncated := fmt.tprintf("%.20s...", item.info.name[:20])
				item.metadata.title = fmt.ctprint(truncated)
			} else {
				item.metadata.title = item.name
			}

			item.metadata.artist = "Unknown Artist"
			item.metadata.year = ""
			item.metadata.album = "Unknown Album"
			item.metadata.genre = "Unknown Genre"
			item.valid_metadata = false

			// fmt.println("Weird path but good", tag)
			return item
		}

		// Extract metadata efficiently
		extract_metadata(&item, tag)
		// fmt.println("Extract finished: ")

		// taglib.tag_free_strings()
		return item
	}

	// fmt.println("Weird path: ", item.fullpath)
	return item
}

// Main threaded search function
search_all_files_threaded :: proc(
	all_paths: ^[dynamic]common.FileEntry,
	dir: string,
	num_threads: int = 8,
) {
	start_time := time.now()

	// Initialize shared data
	shared_data := Shared_Data {
		work_queue = make([dynamic]Work_Item, 0, 3000), // Pre-allocate for ~3000 files
		results    = make([dynamic]common.FileEntry, 0, 3000),
	}
	defer {
		// Clean up work queue
		for work_item in shared_data.work_queue {
			delete(work_item.file_path)
			delete(work_item.directory)
		}
		delete(shared_data.work_queue)
		delete(shared_data.results)
	}

	// Phase 1: Collect all MP3 files (single-threaded for filesystem safety)
	fmt.println("Phase 1: Collecting MP3 files...")
	collect_start := time.now()
	collect_mp3_files(&shared_data.work_queue, dir)
	collect_time := time.since(collect_start)

	total_files := len(shared_data.work_queue)
	// fmt.printf("Found %d MP3 files in %v\n", total_files, collect_time)

	if total_files == 0 {
		fmt.println("No MP3 files found!")
		return
	}

	// Phase 2: Process files with multiple threads
	fmt.printf("Phase 2: Processing files with %d threads...\n", num_threads)
	process_start := time.now()

	// Create and start threads
	threads := make([]^thread.Thread, num_threads)
	defer delete(threads)

	for i in 0 ..< num_threads {
		thread_id := i + 1
		threads[i] = thread.create_and_start_with_poly_data2(
			&shared_data,
			thread_id,
			process_mp3_worker,
		)
	}

	// Wait for all threads to complete
	thread.join_multiple(..threads[:])

	// Clean up threads
	for t in threads {
		thread.destroy(t)
	}

	process_time := time.since(process_start)

	// Phase 3: Copy results to output
	fmt.println("Phase 3: Copying results...")
	reserve(all_paths, len(all_paths) + len(shared_data.results))
	for result in shared_data.results {
		append(all_paths, result)
	}

	total_time := time.since(start_time)
	fmt.printf(
		"Search completed: %d files processed in %v (collect: %v, process: %v)\n",
		len(shared_data.results),
		total_time,
		collect_time,
		process_time,
	)
	fmt.printf("Average processing time per file: %v\n", process_time / time.Duration(total_files))
}

// Optimized metadata extraction
extract_metadata :: proc(item: ^common.FileEntry, tag: taglib.TagLib_Tag) {
	// Title processing
	title := taglib.tag_title(tag)

	if len(title) > 0 {
		if len(title) > 20 {
			truncated := fmt.tprintf("%.20s...", title)
			item.metadata.title = fmt.ctprint(truncated)

		} else {
			item.metadata.title = title
		}
	} else {
		//  use the filename as the title
		if len(item.name) > 20 {
			truncated := fmt.tprintf("%.20s...", item.name)
			item.metadata.title = fmt.ctprint(truncated)
		} else {
			item.metadata.title = item.name
		}
	}

	item.metadata.artist =
		len(taglib.tag_artist(tag)) > 0 ? taglib.tag_artist(tag) : "Unknown Artist"
	item.metadata.year = fmt.ctprintf("%d", taglib.tag_year(tag))
	item.metadata.album = len(taglib.tag_album(tag)) > 0 ? taglib.tag_album(tag) : "Unknown Album"
	item.metadata.genre = len(taglib.tag_genre(tag)) > 0 ? taglib.tag_genre(tag) : "Unknown Genre"
	item.valid_metadata = true
}
