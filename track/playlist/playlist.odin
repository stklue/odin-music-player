package playlist

import taglib "../../taglib-odin"
import common "../common"
import "base:runtime"
import "core:encoding/xml"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"


// Playlist_Entry :: struct {
// 	src:         string,
// 	albumTitle:  string,
// 	albumArtist: string,
// 	trackTitle:  string,
// 	trackArtist: string,
// 	duration:    string,
// }


Playlist_Metadata :: struct {
	total_duration: string,
	item_count:     string,
	generator:      string,
	title:          string,
}


Playlist :: struct {
	meta:    Playlist_Metadata,
	entries: [dynamic]common.FileEntry,
}


PlaylistTypes :: enum {
	Global,
	Local,
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

load_zpl_playlist :: proc(path: string) -> (playlist: Playlist, ok: bool) {
	doc, err := xml.load_from_file(path)
	if err != nil {
		fmt.println("Failed to load XML.")
		return Playlist{}, false
	}

	playlist_res: Playlist

	entries: [dynamic]common.FileEntry

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

				if child.ident == "media" {
					entry := common.FileEntry{}
					file: taglib.TagLib_File
					for attr in child.attribs {
						if attr.key == "src" {
							file = taglib.file_new(fmt.ctprint(attr.val))
							// fmt.println("Found srcs: ", attr.val)
						}


						// Get the tag information
						// tag := taglib.file_tag(file)
						// defer taglib.file_free(file) // memory sky rockets when not cleaned up
						// if is_valid_path(path) {
						// 	entry.metadata.title = strings.clone_from_cstring(
						// 		taglib.tag_title(tag),
						// 	)
						// 	entry.metadata.artist =
						// 		len(taglib.tag_artist(tag)) > 0 ? strings.clone_from_cstring(taglib.tag_artist(tag)) : "Unknown Artist"
						// 	entry.metadata.year = fmt.tprintf("%d", taglib.tag_year(tag))
						// 	entry.metadata.album =
						// 		len(taglib.tag_album(tag)) > 0 ? strings.clone_from_cstring(taglib.tag_album(tag)) : "Unknown Album"
						// 	entry.metadata.genre =
						// 		len(taglib.tag_genre(tag)) > 0 ? strings.clone_from_cstring(taglib.tag_genre(tag)) : "Unknown Genre"
						// 	entry.valid_metadata = true

						// } else {
						// 	entry.valid_metadata = false
						// }

						switch attr.key {
						case "src":
							entry.fullpath = fmt.ctprint(attr.val)
						case "albumTitle":
							// entry.metadata.album = len(taglib.tag_album(tag)) > 0 ? strings.clone_from_cstring(taglib.tag_album(tag)) : "Unknown Album"
							entry.metadata.album = fmt.ctprint(attr.val)
						case "albumArtist":
							entry.metadata.artist = fmt.ctprint(attr.val)
						case "trackTitle":
							entry.metadata.title = fmt.ctprint(attr.val)
						case "trackArtist":
							entry.metadata.artist = fmt.ctprint(attr.val)
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


load_all_zpl_playlists :: proc(mutex: ^sync.Mutex, plists: ^[dynamic]Playlist) {
	folder_path := "C:/Users/St.Klue/Music/Playlists"
	dir_handle, err := os.open(folder_path)
	if err != os.ERROR_NONE {
		fmt.println("Failed to open directory: ", err)
	}
	defer os.close(dir_handle)
	// Get all files in the directory
	files, read_err := os.read_dir(dir_handle, 1024)
	if read_err != nil {
		fmt.println("Failed to read directory:", folder_path)
	}
	sync.mutex_lock(mutex)
	for file in files {
		if !file.is_dir && strings.has_suffix(file.name, ".zpl") {
			// full_path := path.join(folder_path, file.name)
			playlist, ok := load_zpl_playlist(file.fullpath)
			if ok {
				append(plists, playlist)
			}
		}
	}
	fmt.printf("Playlists %d found\n", len(plists))
	// fmt.println(plists[:2])
	sync.mutex_unlock(mutex)
	fmt.printf("%d files scanned\n", len(files))
}
