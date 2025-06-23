package playlist

import "base:runtime"
import "core:encoding/xml"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"


Playlist_Entry :: struct {
	src:         string,
	albumTitle:  string,
	albumArtist: string,
	trackTitle:  string,
	trackArtist: string,
	duration:    string,
}


Playlist_Metadata :: struct {
	total_duration: string,
	item_count:     string,
	generator:      string,
	title:          string,
}


Playlist :: struct {
	meta:    Playlist_Metadata,
	entries: [dynamic]Playlist_Entry,
}


PlaylistTypes :: enum {
	Global,
	Local,
}


load_zpl_playlist :: proc(path: string) -> (playlist: Playlist, ok: bool) {
	doc, err := xml.load_from_file(path)
	if err != nil {
		fmt.println("Failed to load XML.")
		return Playlist{}, false
	}

	playlist_res: Playlist

	entries: [dynamic]Playlist_Entry

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
					entry := Playlist_Entry{}
					for attr in child.attribs {
						switch attr.key {
						case "src":
							entry.src = attr.val
						case "albumTitle":
							entry.albumTitle = attr.val
						case "albumArtist":
							entry.albumArtist = attr.val
						case "trackTitle":
							entry.trackTitle = attr.val
						case "trackArtist":
							entry.trackArtist = attr.val
						case "duration":
							entry.duration = attr.val
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
