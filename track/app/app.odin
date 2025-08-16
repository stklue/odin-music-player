package app

import im "../../odin-imgui"
import taglib "../../taglib-odin"
import media "../media"
import "core:flags"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"


AppState :: struct {
	mutex:                          sync.Mutex,
	is_searching:                   bool,
	search_result_index:            int, // index to what search result is clicked
	total_files:                    int,
	taglib_total_duration:          time.Duration,
	taglib_file_count:              int,
	
	clicked_playlist_entries:       media.Songs, // stores the playlist entries that was clicked on 
	clicked_search_results_entries: media.Songs, // stores the search result entries that was clicked
	play_queue:                     media.Songs, // stores the songs that's currently in line to play
	play_queue_index:               int,
	
	ui_view:                        UI_View, // stores the UI on the right panel to show
	last_view:                      UI_View, // when switching to the visualizer and back
	// library:                        media.MediaLibrary, // manages all the songs
	arena:                          mem.Arena, // for app cstrings allocations
	arena_allocator:                mem.Allocator, // storing cstrings
	has_right_clicked:              bool, // whether the mouse right was click
	last_mouse_click_pos:           [2]f32, // where the user right clicked
	ui_right_click_ctx:             UI_Right_Click_Context,
	ui_layer_interact:              UI_Layer_Interact, // let's us know on which layer we should handle clicks and hover

	// fonts
	header_font:                    ^im.Font,
	base_font:                    ^im.Font,
	icon_font_2xl:                  ^im.Font,
	icon_font_sm:                   ^im.Font,
	icon_font_md:                   ^im.Font,
	icon_font_lg:                   ^im.Font,
	icon_font_xl:                   ^im.Font,


	// manage indices
	playlists_index: int, // the index of the clicked playlist
	playlist_song_index: int, // the index of the song in the clicked playlist
	all_songs_index: int, // index of song all songs 


	// search
	search_buffer_query: [256]u8, 
	search_results: [dynamic]media.SearchItem
}


UI_Right_Click_Context :: enum {
	Edit_Artist,
	Edit_Album,
	Show_Artist,
	Show_Album,
	Edit_Year,
	Edit_Genre,
	Edit_Title,
	Play_Next,
}

UI_Layer_Interact :: enum {
	Base_Layer,
	Right_Click_Layer,
}


UI_View :: enum {
	Search,
	All_Songs,
	Playlist,
	Visualizer,
}

g_app: ^AppState

init_app :: proc() -> ^AppState {
	state := new(AppState)
	state.clicked_playlist_entries = make(media.Songs, 0, 100)
	state.clicked_search_results_entries = make(media.Songs, 0, 3000)
	state.play_queue = make(media.Songs, 0, 3000)
	state.ui_view = .All_Songs
	state.last_view = .All_Songs
	state.ui_layer_interact = .Base_Layer
	// state.search_cstring = cast(cstring)(&state.search_buffer[0])

	arena_mem := make([]byte, 1 * mem.Megabyte)
	mem.arena_init(&state.arena, arena_mem)
	state.arena_allocator = mem.arena_allocator(&state.arena)
	// media.init_library(&state.library)
	return state
}
// cleanup code in track.odin
// could not get it to work through defer cleanup_app()

search_song :: proc(
	state: ^AppState,
	query: string,
	songs: ^media.Songs,
	search_results: ^[dynamic]media.SearchItem,
) {
	clear(search_results) // clear previous search results

	query := strings.to_lower(query)

	// Track which albums and artists we've already added
	found_albums := map[string]bool{}
	found_artists := map[string]bool{}
	// search_time: time.Stopwatch
	// time.stopwatch_start(&search_time)
	// Song matches are kept separate
	
	for song in songs {
		title := strings.to_lower(fmt.tprint(song.metadata.title))
		album := strings.to_lower(fmt.tprint(song.metadata.album))
		artist := strings.to_lower(fmt.tprint(song.metadata.artist))
		filename := song.lowercase_name

		// Check for album match
		if album != "" && strings.contains(album, query) && !found_albums[album] {
			found_albums[album] = true
			item := media.SearchItem {
				kind      = .Album,
				label     = song.metadata.album,
				file_name = song.metadata.album,
			}

			append(search_results, item)
		}

		// Check for artist match
		if artist != "" && strings.contains(artist, query) && !found_artists[artist] {
			found_artists[artist] = true
			item := media.SearchItem {
				kind      = .Artist,
				label     = song.metadata.artist,
				file_name = song.metadata.artist,
			}
			append(search_results, item)
		}

		// Check for title or filename match
		if strings.contains(title, query) || strings.contains(filename, query) {
			item := media.SearchItem {
				kind      = .Title,
				label     = song.metadata.title,
				file_name = song.metadata.title,
			}
			append(search_results, item)
		}
	}
	// time.stopwatch_stop(&search_time)
	// fmt.printfln("Search took: %v", search_time._accumulation)

	state.is_searching = true
}


search_one_song :: proc(all_songs: ^media.Songs, find_song: cstring, song_display: ^media.Songs) {
	search_one_song_time: time.Stopwatch
	time.stopwatch_start(&search_one_song_time)
	for song in all_songs {
		if strings.contains(fmt.tprint(song.metadata.title), fmt.tprint(find_song)) {
			append(song_display, song)
			return
		}
		if strings.contains(fmt.tprint(song.name), fmt.tprint(find_song)) {
			append(song_display, song)
			return
		}
	}
	time.stopwatch_stop(&search_one_song_time)
	fmt.printfln("Search one song took: %v", search_one_song_time._accumulation)
}

search_album :: proc(all_songs: ^media.Songs, album_name: cstring, album: ^media.Songs) {
	search_album_time: time.Stopwatch
	time.stopwatch_start(&search_album_time)
	for song in all_songs {
		if song.metadata.album == album_name {
			append(album, song)
		}
	}
	time.stopwatch_stop(&search_album_time)
	fmt.printfln("Search album took: %v", search_album_time._accumulation)
}

search_artist :: proc(all_songs: ^media.Songs, artist_name: cstring, artist: ^media.Songs) {
	search_artist_time: time.Stopwatch
	time.stopwatch_start(&search_artist_time)
	for song in all_songs {
		if strings.contains(fmt.tprint(song.metadata.artist), fmt.tprint(artist_name)) {
			append(artist, song)
		}
		if strings.contains(fmt.tprint(song.metadata.title), fmt.tprint(artist_name)) {
			append(artist, song)
		}
	}
	time.stopwatch_stop(&search_artist_time)
	fmt.printfln("Search artist took: %v", search_artist_time._accumulation)
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
// search_all_files_archive :: proc(dir: string) {

// 	g_app.total_files += 1
// 	handler, handle_err := os.open(dir)
// 	defer os.close(handler)
// 	if handle_err != nil {
// 		fmt.eprintln("Failed to open dir: ", dir, handle_err)
// 		return
// 	}
// 	entries, err := os.read_dir(handler, -1)
// 	if err != nil {
// 		fmt.eprintln("Failed to read dir: ", dir, err)
// 		return
// 	}
// 	for entry in entries {
// 		path := strings.join([]string{dir, entry.name}, "/")

// 		item := media.Song {
// 			info           = entry,
// 			name           = strings.clone_to_cstring(entry.name),
// 			fullpath       = strings.clone_to_cstring(entry.fullpath),
// 			lowercase_name = strings.to_lower(entry.name),
// 			dir            = dir,
// 		}

// 		if entry.is_dir {
// 			search_all_files_archive(path)
// 		} else {

// 			if strings.has_suffix(item.lowercase_name, ".mp3") {
// 				path_cstr := fmt.ctprint(path)
// 				stop_watch: time.Stopwatch
// 				time.stopwatch_start(&stop_watch)

// 				// Bottleneck

// 				file := taglib.file_new(path_cstr)
// 				defer taglib.file_free(file) // memory sky rockets when not cleaned up

// 				tag := taglib.file_tag(file)
// 				if tag.dummy == 0 {
// 					if len(item.name) > 20 {
// 						truncated := fmt.tprintf("%.20s...", item.info.name[:20])
// 						item.metadata.title = strings.clone_to_cstring(truncated)
// 					} else {
// 						item.metadata.title = item.name
// 					}

// 					item.metadata.artist = "Unknown Artist"
// 					item.metadata.year = ""
// 					item.metadata.album = "Unknown Album"
// 					item.metadata.genre = "Unknown Genre"
// 					item.valid_metadata = false

// 					g_app.taglib_file_count += 1

// 					append(&g_app.all_songs, item)
// 					continue
// 				}

// 				//! CAN FIX: Should be a better way to fix this
// 				title := taglib.tag_title(tag)

// 				// if len(title) > 0 {
// 				// 	if len(title) > 20 {
// 				// 		truncated := fmt.tprintf("%.20s...", title)
// 				// 		item.metadata.title = strings.clone_to_cstring(truncated)

// 				// 	} else {
// 				// 		item.metadata.title = title
// 				// 	}
// 				// } else {
// 				// 	//  use the filename as the title
// 				// 	if len(item.name) > 20 {
// 				// 		truncated := fmt.tprintf("%.20s...", item.name)
// 				// 		item.metadata.title = strings.clone_to_cstring(truncated)
// 				// 	} else {
// 				// 		item.metadata.title = item.name
// 				// 	}
// 				// }
// 				item.metadata.title =
// 					len(title) > 0 ? title : strings.clone_to_cstring(item.info.name)

// 				item.metadata.artist =
// 					len(taglib.tag_artist(tag)) > 0 ? taglib.tag_artist(tag) : "Unknown Artist"
// 				item.metadata.year = strings.clone_to_cstring(
// 					fmt.tprintf("%d", taglib.tag_year(tag)),
// 				)
// 				item.metadata.album =
// 					len(taglib.tag_album(tag)) > 0 ? taglib.tag_album(tag) : "Unknown Album"
// 				item.metadata.genre =
// 					len(taglib.tag_genre(tag)) > 0 ? taglib.tag_genre(tag) : "Unknown Genre"
// 				item.valid_metadata = true

// 				time.stopwatch_stop(&stop_watch)
// 				duration := stop_watch._accumulation

// 				g_app.taglib_total_duration += duration
// 				g_app.taglib_file_count += 1

// 				append(&g_app.all_songs, item)
// 			}
// 		}
// 	}
// }

// Writes the metadata to a textfile and then return the number of files/item written
// path, title, artist, album, genre, year, duration
write_metadata_to_txt :: proc(files: media.Songs) -> os.Error {
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


// Optimized metadata extraction
extract_metadata :: proc(item: ^media.Song, tag: taglib.TagLib_Tag) {
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


ICON_MIN_FA :: 0x0005
ICON_MAX_FA :: 0xFF22
icons_ranges := [3]im.Wchar{ICON_MIN_FA, ICON_MAX_FA, 0}

load_header_font :: proc(font_atlas: ^im.FontAtlas) {
	g_app.header_font = im.FontAtlas_AddFontFromFileTTF(
		font_atlas,
		"C:/Projects/track_player/track/fonts/Roboto/static/Roboto_Condensed-Bold.ttf",
		30,
	)
}
load_base_font :: proc(font_atlas: ^im.FontAtlas) {
	g_app.base_font = im.FontAtlas_AddFontFromFileTTF(
		font_atlas,
		"C:/Projects/track_player/track/fonts/Roboto/static/Roboto_Condensed-Regular.ttf",
		18,
	)
}


load_icon_font_sm :: proc(font_atlas: ^im.FontAtlas) {
	g_app.icon_font_sm = im.FontAtlas_AddFontFromFileTTF(
		font_atlas,
		"C:/Projects/track_player/track/fonts/Font Awesome 7 Free-Solid-900.otf",
		12,
		glyph_ranges = raw_data(icons_ranges[:]),
	)
}
load_icon_font_md :: proc(font_atlas: ^im.FontAtlas) {
	g_app.icon_font_md = im.FontAtlas_AddFontFromFileTTF(
		font_atlas,
		"C:/Projects/track_player/track/fonts/Font Awesome 7 Free-Solid-900.otf",
		14,
		glyph_ranges = raw_data(icons_ranges[:]),
	)
}
load_icon_font_lg :: proc(font_atlas: ^im.FontAtlas) {
	g_app.icon_font_lg = im.FontAtlas_AddFontFromFileTTF(
		font_atlas,
		"C:/Projects/track_player/track/fonts/Font Awesome 7 Free-Solid-900.otf",
		16,
		glyph_ranges = raw_data(icons_ranges[:]),
	)
}
load_icon_font_xl :: proc(font_atlas: ^im.FontAtlas) {
	g_app.icon_font_xl = im.FontAtlas_AddFontFromFileTTF(
		font_atlas,
		"C:/Projects/track_player/track/fonts/Font Awesome 7 Free-Solid-900.otf",
		30,
		glyph_ranges = raw_data(icons_ranges[:]),
	)
}
load_icon_font_2xl :: proc(font_atlas: ^im.FontAtlas) {
	g_app.icon_font_2xl = im.FontAtlas_AddFontFromFileTTF(
		font_atlas,
		"C:/Projects/track_player/track/fonts/Font Awesome 7 Free-Solid-900.otf",
		60,
		glyph_ranges = raw_data(icons_ranges[:]),
	)
}
load_all_fonts :: proc(font: ^im.FontAtlas) {
	load_base_font(font)
	load_header_font(font)
	load_icon_font_2xl(font)
	load_icon_font_sm(font)
	load_icon_font_md(font)
	load_icon_font_lg(font)
	load_icon_font_xl(font)
}

App_Events ::  enum {
	SEARCH_BAR_START , // when the user clicks on the search bar
	SEARCH_BAR_ENTER, // when the user types in the search bar
	SEARCH_BAR_LEAVE,

	LEFT_ALL_SONGS_CLICKED,
	LEFT_PLAYLISTS_ITEM_CLICKED,

	RIGHT_ALL_SONG_ITEM_CLICKED,
	RIGHT_PLAYLIST_ITEM_CLICKED,
	RIGHT_SEARCH_ITEM_CLICKED,

	// PLAYBACK EVENTS
	BOTTOM_PAUSE_CLICKED,
	BOTTOM_PLAY_CLICKED,
	BOTTOM_NEXT_CLICKED,
	BOTTOM_PREV_CLICKED,
	BOTTOM_REPEAT_ONE_CLICKED,
	BOTTOM_REPEAT_ALL_CLICKED,
	BOTTOM_REPEAT_NOTHING_CLICKED,

}
