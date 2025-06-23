package main

DISABLE_DOCKING :: #config(DISABLE_DOCKING, true)

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import image "vendor:stb/image"

import im "../odin-imgui"
import "../odin-imgui/imgui_impl_glfw"
import "../odin-imgui/imgui_impl_opengl3"

import audio "audio_state"
import "base:runtime"
import "core:encoding/xml"
import json "core:encoding/json"
import "core:math"
import "core:path/filepath"
import "core:sync"
import "core:thread"
import "core:time"
import pl "playlist"
import ui "ui"
import gl "vendor:OpenGL"
import "vendor:glfw"
import ma "vendor:miniaudio"

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


FileEntry :: struct {
	info:            os.File_Info,
	name:            cstring,
	fullpath:        cstring,
	lowercase_name:  string,
	index_all_songs: int,
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


load_texture_from_file :: proc(path: cstring) -> u32 {
	image.set_flip_vertically_on_load(1)
	width, height, channels: i32
	data := image.load(path, &width, &height, &channels, 4)

	if data == nil {
		fmt.printfln("Failed to load texture: %s", path)
		return 0
	}

	texture_id: u32
	gl.GenTextures(1, &texture_id)
	gl.BindTexture(gl.TEXTURE_2D, texture_id)

	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, data)
	gl.GenerateMipmap(gl.TEXTURE_2D)

	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)

	image.image_free(data)

	return texture_id
}

// HasFileEntry :: union {FileEntry, nil} 

AppState :: struct {
	views:                      [100]bool,
	current_view_index:         int,
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
}

init_app :: proc() -> ^AppState {
	state := new(AppState)
	state.views[0] = true // default view should display
	state.playlist_index = -1 // -1 = all the songs playlist
	// state.all_songs_item_playling = nil
	return state
}


set_current_item :: proc(state: ^AppState, fe: FileEntry) {
	state.current_item_playing = fe
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


main :: proc() {
	assert(cast(bool)glfw.Init())
	defer glfw.Terminate()

	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 3)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 2)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, 1) // i32(true)
	monitor := glfw.GetPrimaryMonitor()
	mode := glfw.GetVideoMode(monitor)
	window := glfw.CreateWindow(1920, 1080, "Music Player", nil, nil)
	assert(window != nil)
	defer glfw.DestroyWindow(window)

	glfw.MakeContextCurrent(window)
	glfw.SwapInterval(1) // vsync

	gl.load_up_to(3, 2, proc(p: rawptr, name: cstring) {
		(cast(^rawptr)p)^ = glfw.GetProcAddress(name)
	})

	im.CHECKVERSION()
	im.CreateContext()
	defer im.DestroyContext()
	io := im.GetIO()

	io.ConfigFlags += {.NavEnableKeyboard, .NavEnableGamepad} // io.Fonts->AddFontFromFileTTF("fonts/Roboto-Medium.ttf", 16.0f);
	im.FontAtlas_AddFontFromFileTTF(
		io.Fonts,
		"C:/Projects/track_player/track/fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf",
		16,
	)

	// init app state
	app_state := init_app()
	// Load saved state
	// state := read_playback_state("playback_state.json")
	// fmt.printf("Last played song: %s\n", state.last_song_path)

	// // Update state when song changes
	// state.last_song_path = "music/cool_song.mp3"
	// state.last_playlist_path = "playlists/favs.json"
	// state.volume = 0.75
	// state.playback_seconds = 42.3

	// save_playback_state("playback_state.json", state)
	root := "C:/Users/St.Klue/Music"
	// all_paths: [dynamic]FileEntry

	search_all_files(&app_state.all_songs, root)
	fmt.printfln("Number  of files found: %d", len(app_state.all_songs))
	play_texture := load_texture_from_file("C:/Projects/track_player/track/textures/play-50.png")
	fmt.println("Texture loaded successfully: ", play_texture)

	//  init audio stuff
	// global audio state
	audio_state := audio.init_audio_state()
	defer audio.destroy_audio_state(audio_state)

	ma.engine_init(nil, &audio_state.engine)
	defer ma.engine_uninit(&audio_state.engine)

	when !DISABLE_DOCKING {
		io.ConfigFlags += {.DockingEnable}
		io.ConfigFlags += {.ViewportsEnable}

		style := im.GetStyle()
		style.WindowRounding = 0
		style.Colors[im.Col.WindowBg].w = 1
	}

	// im.StyleColorsDark()
	// Set custom style
	// set_custom_style()
	ui.set_red_black_theme()
	imgui_impl_glfw.InitForOpenGL(window, true)
	defer imgui_impl_glfw.Shutdown()
	imgui_impl_opengl3.Init("#version 150")
	defer imgui_impl_opengl3.Shutdown()

	// globals
	shared_files: [dynamic]FileEntry
	shared_files_mutex: sync.Mutex

	search_results: [dynamic]FileEntry
	search_mutex: sync.Mutex

	// loading music files into memory
	file_thread := thread.create_and_start_with_poly_data2(
		&shared_files_mutex,
		&shared_files,
		load_files_thread_proc,
	)

	// loading playlists

	playlists_thread := thread.create_and_start_with_poly_data2(
		&app_state.mutex,
		&app_state.playlists,
		pl.load_all_zpl_playlists,
	)


	//  gui state
	my_buffer: [256]u8

	//  search details
	search_input: string
	previous_input: string
	filtered_results: [dynamic]FileEntry
	current_pl_item: i32 = 0 // pl = playlist
	current_sr_item: i32 = 0 // sr = search results
	is_selected := false


	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()

		imgui_impl_opengl3.NewFrame()
		imgui_impl_glfw.NewFrame()
		im.NewFrame()


		// Update audio state
		audio.update_audio(audio_state)

		// ========= UI KEY PRESSES ===========
		if im.IsKeyPressed(.Space, false) {
			fmt.println("You pressed on the space button")
			audio.toggle_playback(audio_state)
		}


		if im.IsKeyPressed(.RightArrow, true) {
			audio.skip_2s_forward(audio_state)
		}
		if im.IsKeyPressed(.LeftArrow, true) {
			audio.skip_2s_backward(audio_state)
		}
		if im.IsKeyPressed(.LeftCtrl, false) || im.IsKeyPressed(.RightCtrl, false) {
			if im.IsKeyPressed(.RightArrow, false) {
				audio.skip_5s_forward(audio_state)
			}
		}
		if im.IsKeyPressed(.LeftCtrl, false) || im.IsKeyPressed(.RightCtrl, false) {
			if im.IsKeyPressed(.LeftArrow, false) {
				audio.skip_5s_backward(audio_state)
			}
		}

		viewport := im.GetMainViewport()
		screen_w := io.DisplaySize.x
		screen_h := io.DisplaySize.y

		third_w := screen_w / 4
		third_h := screen_h / 6

		top_h := screen_h - third_h // top 2/3 of height
		right_w := screen_w - third_w // right 2/3 of width

		im.PushStyleVar(im.StyleVar.WindowRounding, 0)
		im.PushStyleVar(im.StyleVar.WindowBorderSize, 0)
		// main window 
		im.SetNextWindowPos(im.Vec2{0, 0}, .Appearing)
		im.SetNextWindowSize(viewport.Size, .Appearing)
		if im.Begin("Track Player", nil, {.NoResize, .NoCollapse, .NoMove, .MenuBar}) {
			// Top Left
			im.SetNextWindowPos(im.Vec2{0, 0})
			im.SetNextWindowSize(im.Vec2{third_w, top_h})

			cstring_buffer := cast(cstring)(&my_buffer[0])
			im.PushStyleColor(im.Col.ScrollbarBg, color_vec4_to_u32({0.5, 0.1, 0.1, 1}))
			im.PushStyleColor(im.Col.ScrollbarGrab, color_vec4_to_u32({0.9, 0.3, 0.3, 1}))
			im.PushStyleColor(im.Col.ScrollbarGrabHovered, color_vec4_to_u32({0.9, 0.2, 0.2, 1}))
			im.PushStyleColor(im.Col.ScrollbarGrabActive, color_vec4_to_u32({0.9, 0.25, 0.25, 1}))
			im.PushStyleColor(im.Col.ChildBg, color_vec4_to_u32({0.9, 0.25, 0.25, 1}))
			style := im.GetStyle()
			style.ChildRounding = 10
			// style.WindowRounding = 40
			if im.Begin("##top-left", nil, {.NoTitleBar, .NoResize}) {
				if im.InputText("Search", cstring_buffer, 100) {

					// search on each key press
					thread.create_and_start_with_poly_data5(
						app_state,
						strings.clone_from_cstring(cstring_buffer),
						&app_state.all_songs,
						&search_results,
						&search_mutex,
						search_song,
					)
				}
				sync.mutex_lock(&app_state.mutex)

				size := im.GetContentRegionAvail()
				im.BeginChild("##list-region", size, {.AutoResizeX}) // border=true

				if im.Button("All Songs", {third_w, 0}) {
					// sync.mutex_lock(&app_state.m)
					app_state.playlist_index = -1
					// sync.mutex_unlock(&app_state.playlist_selection_mutex)


					//! TODO: SHOULD CHANGE THE FILES PROC TO BE THE ALL FILES PROC 
					thread.create_and_start_with_poly_data2(
						&shared_files_mutex,
						&app_state.all_songs,
						load_files_thread_proc,
					)
				}

				im.Separator()

				// Show searches or the the initial playlist items
				if len(cstring_buffer) == 0 {
					for v, i in app_state.playlists {
						currently_selected_playlist := current_pl_item == cast(i32)i
						// if app_state.playlist_index == -1 {

						// } else {

						// }
						// app_state.playlist_item_playling

						// Start a group per row
						// im.PushStyleColor(im.Col.Sele, 0) // transparent button bg
						// im.PushStyleColor(im.PushStyleColor(im.Col.im, color_vec4_to_u32({0.9, 0.3, 0.3, 1})).Col.ButtonActive, 0) // transparent active

						im.BeginGroup()
						im.Dummy(im.Vec2{20, 20})
						im.SameLine()
						if im.Selectable(
							strings.clone_to_cstring(v.meta.title),
							currently_selected_playlist,
							{},
							{size.x, 30},
						) {
							current_pl_item = cast(i32)i

							// sync.mutex_lock(&app_state.mutex)
							// sync.mutex_lock(&app_state.playlist_selection_mutex)
							app_state.playlist_index = i
							// sync.mutex_unlock(&app_state.playlist_selection_mutex)
							// sync.mutex_unlock(&app_state.mutex)

							thread.create_and_start_with_poly_data4(
								&shared_files_mutex,
								&app_state.all_songs,
								i,
								&app_state.playlists,
								load_files_from_pl_thread,
							)
						}


						im.EndGroup()
					}
				} else {
					if len(search_results) > 0 {
						for search_result, i in search_results {
							currently_selected_search_result := current_sr_item == cast(i32)i

							im.BeginGroup()

							if im.Selectable(
								search_result.name,
								currently_selected_search_result,
								{},
								{size.x, 30},
							) {
								current_sr_item = cast(i32)i
								// app_state.current_item_playing_index = i
								// fmt.println(app_state.current_item_playing_index)
								// fmt.println(i)

								audio.create_audio_play_thread(audio_state, search_result.fullpath)
							}


							im.EndGroup()
						}
					}
				}
				im.EndChild()
				sync.mutex_unlock(&app_state.mutex)
			}
			im.End()
			im.PopStyleColor(5)

			// Top Right
			top_right_panel(
				&shared_files_mutex,
				&app_state.all_songs,
				audio_state,
				app_state,
				top_h,
				third_w,
				right_w,
			)
			// Bottom
			bottom_panel(app_state, audio_state, top_h, screen_w, third_h)
		}
		im.End()

		im.PopStyleVar(2)

		im.Render()
		display_w, display_h := glfw.GetFramebufferSize(window)
		gl.Viewport(0, 0, display_w, display_h)
		gl.ClearColor(0, 0, 0, 1)
		gl.Clear(gl.COLOR_BUFFER_BIT)
		imgui_impl_opengl3.RenderDrawData(im.GetDrawData())

		when !DISABLE_DOCKING {
			backup_current_window := glfw.GetCurrentContext()
			im.UpdatePlatformWindows()
			im.RenderPlatformWindowsDefault()
			glfw.MakeContextCurrent(backup_current_window)
		}

		glfw.SwapBuffers(window)
	}

	// Cleanup audio on exit
	sync.mutex_lock(&audio_state.mutex)
	if audio_state.device != nil {
		ma.device_stop(audio_state.device)
		ma.device_uninit(audio_state.device)
		free(audio_state.device)
	}
	if audio_state.decoder != nil {
		ma.decoder_uninit(audio_state.decoder)
		free(audio_state.decoder)
	}
	sync.mutex_unlock(&audio_state.mutex)
}


set_custom_style :: proc() {
	style := im.GetStyle()

	// Rounding
	style.WindowRounding = 5.0
	style.ChildRounding = 5.0
	style.FrameRounding = 3.0
	style.PopupRounding = 5.0
	style.GrabRounding = 3.0
	style.TabRounding = 3.0

	// Spacing
	style.WindowPadding = {8.0, 8.0}
	style.FramePadding = {6.0, 4.0}
	style.ItemSpacing = {8.0, 4.0}
	style.ItemInnerSpacing = {4.0, 4.0}

	// Modern dark theme colors
	colors := style.Colors

	// Base colors
	colors[im.Col.Text] = {0.95, 0.96, 0.98, 1.00}
	colors[im.Col.TextDisabled] = {0.50, 0.50, 0.50, 1.00}
	colors[im.Col.WindowBg] = {0.10, 0.10, 0.12, 1.00}
	colors[im.Col.ChildBg] = {0.08, 0.08, 0.09, 1.00}
	colors[im.Col.PopupBg] = {0.12, 0.12, 0.14, 0.94}
	colors[im.Col.Border] = {0.20, 0.20, 0.25, 1.00}

	// Button colors
	colors[im.Col.Button] = {0.25, 0.46, 0.78, 1.00}
	colors[im.Col.ButtonHovered] = {0.30, 0.52, 0.85, 1.00}
	colors[im.Col.ButtonActive] = {0.20, 0.40, 0.70, 1.00}

	// Frame colors
	colors[im.Col.FrameBg] = {0.18, 0.18, 0.20, 1.00}
	colors[im.Col.FrameBgHovered] = {0.25, 0.25, 0.28, 1.00}
	colors[im.Col.FrameBgActive] = {0.30, 0.30, 0.32, 1.00}

	// Title colors
	colors[im.Col.TitleBg] = {0.08, 0.08, 0.09, 1.00}
	colors[im.Col.TitleBgActive] = {0.10, 0.10, 0.12, 1.00}
	colors[im.Col.TitleBgCollapsed] = {0.08, 0.08, 0.09, 1.00}

	// Scrollbar colors
	colors[im.Col.ScrollbarBg] = {0.08, 0.08, 0.09, 1.00}
	colors[im.Col.ScrollbarGrab] = {0.30, 0.30, 0.32, 1.00}
	colors[im.Col.ScrollbarGrabHovered] = {0.35, 0.35, 0.38, 1.00}
	colors[im.Col.ScrollbarGrabActive] = {0.40, 0.40, 0.43, 1.00}

	// Slider colors
	colors[im.Col.SliderGrab] = {0.40, 0.60, 0.90, 1.00}
	colors[im.Col.SliderGrabActive] = {0.45, 0.65, 0.95, 1.00}
}

show_custom_window :: proc() {
	im.SetNextWindowSize({400, 300}, .FirstUseEver)
	im.Begin("Modern Odin Window", nil, {})

	im.Text("This is a custom-styled window!")
	im.Separator()

	im.TextWrapped("Notice the rounded corners, custom colors, and improved spacing.")

	im.Spacing()
	im.Button("Fancy Button", {100, 30})

	im.Spacing()
	im.Text("Progress:")
	im.ProgressBar(0.75, {0, 0}, "75%")

	im.End()
}


// show_music_player :: proc(audio: ^AudioState) {
// 	im.SetNextWindowPos({50, 50}, .FirstUseEver)
// 	im.SetNextWindowSize({700, 300}, .FirstUseEver)
// 	im.Begin("Music Player", nil, {})

// 	// Display current song info
// 	im.Text("Now Playing: sample.mp3") // Replace with dynamic name
// 	im.Separator()

// 	// Progress bar
// 	progress := audio.current_time / audio.duration
// 	im.ProgressBar(
// 		progress,
// 		{600, 20},
// 		strings.clone_to_cstring(
// 			fmt.tprintf("%.1f / %.1f seconds", audio.current_time, audio.duration),
// 		),
// 	)

// 	// Time display
// 	im.Text(
// 		strings.clone_to_cstring(
// 			fmt.tprintf(
// 				"%02d:%02d / %02d:%02d",
// 				i32(audio.current_time) / 60,
// 				i32(audio.current_time) % 60,
// 				i32(audio.duration) / 60,
// 				i32(audio.duration) % 60,
// 			),
// 		),
// 	)

// 	// Controls
// 	if im.Button(audio.is_playing ? "Pause" : "Play", {80, 30}) {
// 		audio.is_playing = !audio.is_playing
// 		if audio.is_playing {
// 			ma.sound_start(&audio.sound)
// 		} else {
// 			ma.sound_stop(&audio.sound)
// 		}
// 	}

// 	im.SameLine()
// 	if im.Button("Stop", {80, 30}) {
// 		audio.is_playing = false
// 		audio.current_time = 0
// 		ma.sound_stop(&audio.sound)
// 		ma.sound_seek_to_pcm_frame(&audio.sound, 0)
// 	}

// 	// Seek control
// 	im.PushItemWidth(600)
// 	if im.SliderFloat("##seek", &audio.current_time, 0, audio.duration, "", {.NoInput}) {
// 		// User is dragging the slider - seek to position
// 		ma.sound_seek_to_second(&audio.sound, audio.current_time)
// 	}
// 	im.PopItemWidth()

// 	im.End()
// }

text :: proc(s: string) -> cstring {
	return strings.clone_to_cstring(s)
}

clamp :: proc(value, min_value, max_value: f32) -> f32 {
	if value < min_value {
		return min_value
	}
	if value > max_value {
		return max_value
	}
	return value
}

audio_progress_bar_and_volume_bar :: proc(audio_state: ^audio.AudioState) {
	total_width := im.GetContentRegionAvail().x
	spacing := im.GetStyle().ItemSpacing.x

	progress_width := (total_width - spacing) * 6.0 / 8.0
	volume_width := (total_width - spacing) * 2.0 / 8.0
	height: f32 = 10.0

	// ========== AUDIO PROGRESS ==========
	im.PushID("audio_seekbar")

	value := audio_state.duration > 0 ? audio_state.current_time / audio_state.duration : 0.0
	slider_size := im.Vec2{progress_width, height}
	slider_pos := im.GetCursorScreenPos()

	im.InvisibleButton("##seek_slider", slider_size)

	if im.IsItemActive() {
		mouse := im.GetIO().MousePos
		new_time := ((mouse.x - slider_pos.x) / progress_width) * audio_state.duration
		audio_state.current_time = math.clamp(new_time, 0.0, audio_state.duration)
	}
	hovered := im.IsItemHovered()
	active := im.IsItemActive()

	draw_list := im.GetWindowDrawList()
	p0 := slider_pos
	p1 := im.Vec2{p0.x + progress_width, p0.y + height}
	handle_x := p0.x + progress_width * value
	handle_radius: f32 = active || hovered ? 7.0 : 5.0

	col_bg := color_vec4_to_u32({0.5, 0.1, 0.1, 1})
	// col_bg :=    im.GetColorU32(.FrameBg)
	col_fg := color_vec4_to_u32({0.8, 0.25, 0.25, 1})
	col_border := im.GetColorU32(.Border)
	// col_handle := im.GetColorU32(.Text)
	col_handle := color_vec4_to_u32({0.9, 0.3, 0.3, 1})

	im.DrawList_AddRectFilled(draw_list, p0, p1, col_bg)
	im.DrawList_AddRectFilled(draw_list, p0, im.Vec2{handle_x, p1.y}, col_fg)
	im.DrawList_AddRect(draw_list, p0, p1, col_border)

	center := im.Vec2{handle_x, p0.y + height / 2}
	im.DrawList_AddCircleFilled(draw_list, center, handle_radius, col_handle)

	label := strings.clone_to_cstring(
		fmt.tprintf(
			"%.0f:%.0f / %.0f:%.0f",
			math.floor(audio_state.current_time / 60),
			math.mod(audio_state.current_time, 60),
			math.floor(audio_state.duration / 60),
			math.mod(audio_state.duration, 60),
		),
	)
	text_size := im.CalcTextSize(label)
	text_pos := im.Vec2{(p0.x + p1.x - text_size.x) / 2, p1.y + 4}
	im.DrawList_AddText(draw_list, text_pos, col_handle, label)

	if im.IsItemDeactivatedAfterEdit() || im.IsMouseReleased(.Left) {
		audio.seek_to_position(audio_state, audio_state.current_time)
	}
	im.PopID()

	// ========== VOLUME SLIDER ==========
	im.SameLine()
	im.PushID("volume_slider")

	volume_slider_pos := im.GetCursorScreenPos()
	volume_slider_size := im.Vec2{volume_width, height}

	im.InvisibleButton("##volume_slider", volume_slider_size)

	if im.IsItemActive() {
		mouse := im.GetIO().MousePos
		new_volume := (mouse.x - volume_slider_pos.x) / volume_width
		audio_state.volume = math.clamp(new_volume, 0.0, 1.0)
	}
	vol_hovered := im.IsItemHovered()
	vol_active := im.IsItemActive()

	vol_draw_list := im.GetWindowDrawList()
	v_p0 := volume_slider_pos
	v_p1 := im.Vec2{v_p0.x + volume_width, v_p0.y + height}
	v_handle_x := v_p0.x + volume_width * audio_state.volume
	v_handle_radius: f32 = vol_active || vol_hovered ? 7.0 : 5.0

	im.DrawList_AddRectFilled(vol_draw_list, v_p0, v_p1, col_bg)
	im.DrawList_AddRectFilled(vol_draw_list, v_p0, im.Vec2{v_handle_x, v_p1.y}, col_fg)
	im.DrawList_AddRect(vol_draw_list, v_p0, v_p1, col_border)

	vol_center := im.Vec2{v_handle_x, v_p0.y + height / 2}
	im.DrawList_AddCircleFilled(vol_draw_list, vol_center, v_handle_radius, col_handle)

	if im.IsItemDeactivatedAfterEdit() || im.IsMouseReleased(.Left) {
		audio.set_volume(audio_state, audio_state.volume)
	}

	im.PopID()
}

Vec4 :: [4]f32
color_vec4_to_u32 :: proc(c: Vec4) -> u32 {
	r := cast(u32)(c.x * 255.0)
	g := cast(u32)(c.y * 255.0)
	b := cast(u32)(c.z * 255.0)
	a := cast(u32)(c.w * 255.0)
	return (a << 24) | (b << 16) | (g << 8) | r
}

top_left_panel :: proc() {

}
top_right_panel :: proc(
	shared_files_mutex: ^sync.Mutex,
	all_paths: ^[dynamic]FileEntry,
	audio_state: ^audio.AudioState,
	app_state: ^AppState,
	top_h, third_w, right_w: f32,
) {
	im.SetNextWindowPos(im.Vec2{third_w, 0})
	im.SetNextWindowSize(im.Vec2{right_w, top_h})
	style := im.GetStyle()
	old_padding := style.FramePadding
	defer style.FramePadding = old_padding // Restore after the frame

	style.FramePadding = 16
	if im.Begin(
		app_state.playlist_index == -1 ? "All Songs" : text(app_state.playlists[app_state.playlist_index].meta.title),
		nil,
		{.NoResize, .NoCollapse},
	) {
		// if im.Begin("##top-right", nil, {.NoResize}) {
		sync.mutex_lock(shared_files_mutex)

		size := im.GetContentRegionAvail()
		im.BeginChild("ListRegion", size) // border=true

		for v, i in all_paths {
			is_selected := app_state.current_item_playing_index == i

			im.BeginGroup()
			im.Spacing()

			bg := color_vec4_to_u32({0.9, 0.2, 0.2, 1})

			if CustomSelectable(v.name, is_selected, bg, {}, im.Vec2{size.x, 30}) {
				fmt.printf("[App] Playing: %s\n", v.name)
				fmt.println(i, app_state.current_item_playing_index, is_selected)
				set_current_item(app_state, v)

				sync.mutex_lock(&app_state.mutex)
				app_state.all_songs_item_playling = v
				app_state.current_item_playing_index = i
				sync.mutex_unlock(&app_state.mutex)

				audio.create_audio_play_thread(audio_state, v.fullpath)
			}

			im.EndGroup()
		}


		im.EndChild()
		sync.mutex_unlock(shared_files_mutex)
	}
	im.End()

}
bottom_panel :: proc(
	app_state: ^AppState,
	audio_state: ^audio.AudioState,
	top_h, screen_w, third_h: f32,
) {
	im.SetNextWindowPos(im.Vec2{0, top_h})
	im.SetNextWindowSize(im.Vec2{screen_w, third_h})
	if im.Begin("##bottom", nil, {.NoTitleBar, .NoResize}) {
		im.PushStyleColor(im.Col.Button, 0) // transparent button bg
		im.PushStyleColor(im.Col.ButtonHovered, color_vec4_to_u32({0.9, 0.3, 0.3, 1})) // transparent hover
		im.PushStyleColor(im.Col.ButtonActive, 0) // transparent active
		// im.PushStyleVarY
		// if im.ImageButton(
		// "play_btn",
		// cast(rawptr)(cast(uintptr)play_texture),
		// im.Vec2{32, 32},
		// im.Vec2{0, 0},
		// im.Vec2{1, 1},
		// im.Vec4{0, 0, 0, 0}, // ✅ transparent background
		// im.Vec4{1, 0, 0, 1},
		// ) {
		// 	// Trigger play logic here
		// }
		// im.SameLine()
		button_count: f32 = 4.0
		button_width: f32 = 100.0
		spacing := im.GetStyle().ItemSpacing.x
		total_width := (button_width * button_count) + (spacing * (button_count - 1))

		avail := im.GetContentRegionAvail().x
		offset_x := (avail - total_width) / 2.0

		// Move cursor to horizontal center
		im.SetCursorPosX(im.GetCursorPosX() + offset_x)
		if im.Button("Prev") {
			prev_path_index :=
				app_state.current_item_playing_index - 1 >= 0 ? app_state.current_item_playing_index - 1 : 0
			app_state.all_songs_item_playling = app_state.all_songs[prev_path_index]
			audio.create_audio_play_thread(
				audio_state,
				app_state.all_songs[prev_path_index].fullpath,
			)
			sync.mutex_lock(&app_state.mutex)
			app_state.current_item_playing_index = prev_path_index
			sync.mutex_unlock(&app_state.mutex)
		}

		im.SameLine()

		if im.Button(audio_state.is_playing ? "Pause" : "Play") {
			audio.toggle_playback(audio_state)
		}

		im.SameLine()

		// Stop button
		if im.Button("Next") {
			next_path_index :=
				app_state.current_item_playing_index + 1 >= len(app_state.all_songs) ? app_state.current_item_playing_index : app_state.current_item_playing_index + 1
			app_state.all_songs_item_playling = app_state.all_songs[next_path_index]
			audio.create_audio_play_thread(
				audio_state,
				app_state.all_songs[next_path_index].fullpath,
			)
			sync.mutex_lock(&app_state.mutex)
			app_state.current_item_playing_index = next_path_index
			sync.mutex_unlock(&app_state.mutex)
		}
		im.SameLine()

		// Stop button
		if im.Button("Stop") {
			audio.stop_playback(audio_state)
		}


		im.PopStyleColor(3)

		audio_progress_bar_and_volume_bar(audio_state)

		im.Dummy({0, 20})
		im.Text(
			len(app_state.all_songs_item_playling.name) == 0 ? "" : app_state.all_songs_item_playling.name,
		)


	}
	im.End()

}


SelectableColor :: proc(bg_color: u32) {
	dl := im.GetWindowDrawList()
	min := im.GetItemRectMin()
	max := im.GetItemRectMax()
	im.DrawList_AddRectFilled(dl, min, max, bg_color, 0.0)
}

CustomSelectable :: proc(
	label: cstring,
	selected: bool,
	bg_color: u32,
	flags: im.SelectableFlags,
	size: im.Vec2,
) -> bool {
	draw_list := im.GetWindowDrawList()
	im.DrawList_ChannelsSplit(draw_list, 2)

	// Foreground
	im.DrawList_ChannelsSetCurrent(draw_list, 1)
	im.Dummy({0, 10})
	im.Dummy({10, 0})
	im.SameLine()
	result := im.Selectable(label, selected, flags, size)

	// Background
	im.DrawList_ChannelsSetCurrent(draw_list, 0)

	// padding := im.Vec2{10, 4}       // padding around the selectable box
	rounding: f32 = 6.0            // corner radius

	min := im.GetItemRectMin()
	max := im.GetItemRectMax() 

	color := bg_color
	if selected {
		color = color_vec4_to_u32({0.9, 0.3, 0.3, 1.0})
	} else if im.IsItemHovered() {
		color = color_vec4_to_u32({0.9, 0.2, 0.1, 1.0})
	}

	im.DrawList_AddRectFilled(draw_list, min, max, color, rounding)

	im.DrawList_ChannelsMerge(draw_list)
	return result
}
