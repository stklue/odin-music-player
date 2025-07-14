package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"


media_extensions :: []string{".mp3"}
found_files: [dynamic]string

scan_folder :: proc(path: string) {
	fd, err := os.open(path)
	defer os.close(fd)
	entries, read_err := os.read_dir(fd, -1)
	if err != nil {
		fmt.println("Failed to read: {}", path)
		return
	}
	if read_err != nil {
		fmt.println("Failed to read: {}", path)
		return
	}

	for entry in entries {
		full_path := strings.join([]string{path, entry.name}, "/")
		if entry.is_dir {
			scan_folder(full_path) // Recursive call
		} else {
			lower_name := strings.to_lower(entry.name)
			for ext, i in media_extensions {
				if strings.has_suffix(lower_name, ext) {
					append(&found_files, full_path)
					break
				}
			}
		}
	}
}


main :: proc() {
    song_path := "C:/Users/St.Klue/Music/2025/Iframe Sun-EL Musician Feat. Mlindo - Bamthathile.mp3"
    // title, artist, album := get_metadata(song_path)
    // fmt.printfln("%s - %s (%s)", artist, title, album)

	root_path := "C:/Users/St.Klue/Music" // Change this to your root folder

	fmt.println("Scanning folder: ", root_path)

	start := time.now()

	// media_extensions :: []string{".mp3", ".flac", ".wav", ".ogg"}

	scan_folder(root_path)

	duration := time.since(start)

	fmt.println("Scan complete!")
	fmt.println("Total media files found: ", len(found_files))
	fmt.println("Time taken: ", duration)

	// Show preview
	preview_count := 5
	if len(found_files) < preview_count {
		preview_count = len(found_files)
	}
	for i in 0 ..< preview_count {
		fmt.println("{}", found_files[i])
	}
}
