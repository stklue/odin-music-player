package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sys/windows"
import "core:time"
import "core:unicode/utf8"
import ma "vendor:miniaudio"
// import rl "vendor:raylib"

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

	// rl.InitAudioDevice() // 1. start WASAPI backend
	// defer rl.CloseAudioDevice()


	data, ok := os.read_entire_file_from_filename(
		"C:/Users/St.Klue/Music/2022/CHVRCHES - Gun.mp3",
	) // []byte
	if !ok {
		fmt.eprintf("Could not open %s\n", "file")
		return
	}
	defer delete(data, context.temp_allocator)

	// Feed raw bytes to raylib; it autodetects MP3
	// music := rl.LoadMusicStreamFromMemory(".mp3", raw_data(data), i32(len(data)))

	// music := rl.LoadMusicStream("C:/Users/St.Klue/Music/2022/Band of Horses - The Funeral.mp3")
	// music := rl.LoadMusicStream("C:/Users/St.Klue/Music/2022/CHVRCHES - Gun.mp3")
	// music := rl.LoadMusicStream(strings.clone_to_cstring(ascii_path))
	// defer rl.UnloadMusicStream(music)

	// rl.PlayMusicStream(music)

	// for rl.IsMusicStreamPlaying(music) {
	// 	rl.UpdateMusicStream(music)
	// 	// rl.WaitTime(0.1) // 100 ms sleep to keep CPU down
	// }
	//   "C:/Users/St.Klue/Music/2022/Band of Horses - The Funeral.mp3",
	// "C:/Users\\St.Klue\\Music\\2022\\CHVRCHES - Gun.mp3",
	// "C:/Users/St.Klue/Music/2022/CHVRCHES - Gun.mp3",


	// 2. Init engine
	engine: ma.engine
	if err := ma.engine_init(nil, &engine); err != .SUCCESS {
		fmt.panicf("engine_init: %v", err)
	}
	defer ma.engine_uninit(&engine)
	if res := ma.engine_start(&engine); res != .SUCCESS {fmt.panicf("engine_start: %v", res)}

	// 3. Create decoder from memory
	decoder: ma.decoder
	if err := ma.decoder_init_memory(raw_data(data), len(data), nil, &decoder); err != .SUCCESS {
		fmt.panicf("decoder_init_memory: %v", err)
	}
	defer ma.decoder_uninit(&decoder)

	// 4. Play it
	sound: ma.sound
	if err := ma.sound_init_from_data_source(&engine, decoder.pBackend, {.DECODE}, nil, &sound);
	   err != .SUCCESS {
		fmt.panicf("sound_init_from_data_source: %v", err)
	}
	defer ma.sound_uninit(&sound)

	ma.sound_start(&sound)
	for ma.sound_is_playing(&sound) {
		time.sleep(100)
	}
	fmt.println("Done.")
}
