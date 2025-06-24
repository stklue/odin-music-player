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
import app "app"



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
	app_state := app.init_app()
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
	// all_paths: [dynamic]app.FileEntry

	app.search_all_files(&app_state.all_songs, root)
	fmt.printfln("Number  of files found: %d", len(app_state.all_songs))

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
	shared_files: [dynamic]app.FileEntry
	shared_files_mutex: sync.Mutex

	search_results: [dynamic]app.FileEntry
	search_mutex: sync.Mutex

	// loading music files into memory
	file_thread := thread.create_and_start_with_poly_data2(
		&shared_files_mutex,
		&shared_files,
		app.load_files_thread_proc,
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
	filtered_results: [dynamic]app.FileEntry
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
			im.PushStyleColor(im.Col.ScrollbarBg, ui.color_vec4_to_u32({0.5, 0.1, 0.1, 1}))
			im.PushStyleColor(im.Col.ScrollbarGrab, ui.color_vec4_to_u32({0.9, 0.3, 0.3, 1}))
			im.PushStyleColor(im.Col.ScrollbarGrabHovered, ui.color_vec4_to_u32({0.9, 0.2, 0.2, 1}))
			im.PushStyleColor(im.Col.ScrollbarGrabActive, ui.color_vec4_to_u32({0.9, 0.25, 0.25, 1}))
			im.PushStyleColor(im.Col.ChildBg, ui.color_vec4_to_u32({0.9, 0.25, 0.25, 1}))
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
						app.search_song,
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
						app.load_files_thread_proc,
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
						// im.PushStyleColor(im.PushStyleColor(im.Col.im, ui.color_vec4_to_u32({0.9, 0.3, 0.3, 1})).Col.ButtonActive, 0) // transparent active

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
								app.load_files_from_pl_thread,
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
			ui.top_right_panel(
				&shared_files_mutex,
				&app_state.all_songs,
				audio_state,
				app_state,
				top_h,
				third_w,
				right_w,
			)
			// Bottom
			ui.bottom_panel(app_state, audio_state, top_h, screen_w, third_h)
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