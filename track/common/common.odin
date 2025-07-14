package common
import "core:os"
import "core:strings"

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
	dir: string,
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

windows_safe_path :: proc(path: string) -> cstring {
	// Convert to UTF-16 first, then back to UTF-8
	wide_path := windows.utf8_to_utf16(path, context.temp_allocator)
	if wide_path == nil {
		// Fallback for invalid UTF-8
		return cstring(raw_data(path))
	}

	// Convert back to UTF-8 (this validates the path)
	utf8_path, err := windows.utf16_to_utf8(wide_path, context.temp_allocator)
	if err != nil {
		fmt.eprintln("Erro converting path: ", err)
	}
	return fmt.ctprint(utf8_path)
}

get_short_path_cstring :: proc(long_path: string) -> cstring {
    wide_long := windows.utf8_to_wstring(long_path)

    // defer delete_slice(&wide_long)
    // utf_u_val, _ :=  windows.wstring_to_utf8(wide_long, len(wide_long[:]))
    // return utf_u_val
	short_path_buf: [windows.MAX_PATH]u16
    short_path_len := windows.GetShortPathNameW(
        wide_long,
        raw_data(short_path_buf[:]),
        len(short_path_buf)
    )
    
    if short_path_len > 0 {
        short_path, _ := windows.wstring_to_utf8(raw_data(short_path_buf[:short_path_len]), 100)
        return fmt.ctprint(short_path) // Don't defer delete this
    }
    return nil
}



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

