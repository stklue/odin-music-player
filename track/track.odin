package main

DISABLE_DOCKING :: #config(DISABLE_DOCKING, true)

import taglib "../taglib-odin"
import common "common"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import image "vendor:stb/image"

import im "../odin-imgui"
import "../odin-imgui/imgui_impl_glfw"
import "../odin-imgui/imgui_impl_opengl3"

import app "app"
import audio "audio_state"
import "base:runtime"
import json "core:encoding/json"
import "core:encoding/xml"
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


main :: proc() {
	// ============== OPENGL AND GLFW INIT ===============================
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


	// ============== APP STATE AND IM GUI SETUP ===============================
	im.CHECKVERSION()
	im.CreateContext()
	defer im.DestroyContext()
	io := im.GetIO()

	io.ConfigFlags += {.NavEnableKeyboard, .NavEnableGamepad}
	base_font := im.FontAtlas_AddFontFromFileTTF(
		io.Fonts,
		"C:/Projects/track_player/track/fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf",
		16,
	)
	bold_header_font := im.FontAtlas_AddFontFromFileTTF(
		io.Fonts,
		"C:/Projects/track_player/track/fonts/Roboto/static/Roboto_Condensed-Bold.ttf",
		30,
	)

	// init app state
	app.g_app = app.init_app()
	root := "C:/Users/St.Klue/Music"
	stop_watch: time.Stopwatch
	time.stopwatch_start(&stop_watch)
	// thread.create_and_start_with_poly_data(root, app.search_all_files)
	// app.search_all_files_archive(root)
	app.scan_all_files(root)

	// (root)
	// app.search_all_files_threaded(&app.g_app.all_songs, root, 4)
	time.stopwatch_stop(&stop_watch)
	// fmt.println(app.g_app.all_songs)
	fmt.printfln(
		"Found %d/%d files in %v",
		len(app.g_app.all_songs),
		app.g_app.total_files,
		stop_watch._accumulation,
	)

	// app.write_metadata_to_txt(app.g_app.all_songs)


	if app.g_app.taglib_file_count > 0 {
		avg :=
			time.duration_milliseconds(app.g_app.taglib_total_duration) /
			f64(app.g_app.taglib_file_count)
		total := app.g_app.taglib_total_duration
		fmt.printfln("TagLib processed %d files", app.g_app.taglib_file_count)
		fmt.printfln("Total TagLib time: %.3f", total)
		fmt.printfln("Average per file: %.3fms", avg)
	} else {
		fmt.println("No .mp3 files processed with TagLib.")
	}

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

	style := im.GetStyle()
	style.Colors[im.Col.ScrollbarBg] = im.Vec4{0.10, 0.12, 0.18, 0.25}
	style.Colors[im.Col.ScrollbarGrab] = im.Vec4{0.20, 0.50, 0.90, 0.35}
	style.Colors[im.Col.ScrollbarGrabHovered] = im.Vec4{0.30, 0.60, 1.00, 0.45}
	style.Colors[im.Col.ScrollbarGrabActive] = im.Vec4{0.45, 0.80, 1.00, 0.60}

	ui.set_red_black_theme()
	imgui_impl_glfw.InitForOpenGL(window, true)
	defer imgui_impl_glfw.Shutdown()
	imgui_impl_opengl3.Init("#version 150")
	defer imgui_impl_opengl3.Shutdown()

	// globals
	// shared_files: [dynamic]common.FileEntry
	// shared_files_mutex: sync.Mutex

	search_results: [dynamic]common.FileEntry
	search_results2: [dynamic]common.SearchItem
	search_mutex: sync.Mutex

	// loading music files into memory
	// file_thread := thread.create_and_start_with_poly_data2(
	// 	&shared_files_mutex,
	// 	&shared_files,
	// 	app.load_files_thread_proc,
	// )

	// loading playlists
	playlists_thread := thread.create_and_start_with_poly_data2(
		&app.g_app.mutex,
		&app.g_app.playlists,
		pl.load_all_zpl_playlists,
	)


	//  gui state
	my_buffer: [256]u8
	// Initialize once at startup
	ui.init_visualizer()

	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()

		imgui_impl_opengl3.NewFrame()
		imgui_impl_glfw.NewFrame()
		im.NewFrame()


		viewport := im.GetMainViewport()
		screen_w := io.DisplaySize.x
		screen_h := io.DisplaySize.y

		third_w := screen_w / 4
		third_h := screen_h / 6

		top_h := screen_h - third_h // top 2/3 of height
		right_w := screen_w - third_w // right 2/3 of width


		// Update audio state
		audio.update_audio(audio_state)

		// ========= UI KEY PRESSES ===========
		if io.KeysDown[im.Key.Space] && im.IsKeyPressed(.Space) {
			// Check if any text input is currently active
			if !im.IsAnyItemActive() {
				audio.toggle_playback(audio_state)
			}
		}
		// shortcut
		if im.IsKeyPressed(.S, true) {
			if !im.IsAnyItemActive() {
				app.g_app.show_visualizer = !app.g_app.show_visualizer
			}
		}
		// if im.IsKeyPressed(.F) && !io.WantCaptureKeyboard {
		// 	//  || io.KeySuper) {
		// 	fmt.println("pressed control F")
		// 	im.SetKeyboardFocusHere()
		// }

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

		// Top Left
		im.SetNextWindowPos(im.Vec2{0, 0})
		im.SetNextWindowSize(im.Vec2{third_w, top_h})

		im.PushStyleColor(im.Col.ScrollbarBg, ui.color_vec4_to_u32({0.10, 0.12, 0.18, 0.25})) // dark blue base
		im.PushStyleColor(im.Col.ScrollbarGrab, ui.color_vec4_to_u32({0.20, 0.50, 0.90, 0.35})) // cool blue
		im.PushStyleColor(
			im.Col.ScrollbarGrabHovered,
			ui.color_vec4_to_u32({0.30, 0.60, 1.00, 0.45}),
		) // brighter on hover
		im.PushStyleColor(
			im.Col.ScrollbarGrabActive,
			ui.color_vec4_to_u32({0.45, 0.80, 1.00, 0.60}),
		) // vivid on drag


		style := im.GetStyle()
		style.ChildRounding = 10
		// style.WindowRounding = 40
		ui.top_left_panel(
			app.g_app,
			&search_results2,
			&search_mutex,
			root,
			audio_state,
			&my_buffer,
		)

		im.PopStyleColor(4)

		// Top Right 
		display_songs :=
			app.g_app.current_view_index == 0 ? app.g_app.all_songs : app.g_app.clicked_playlist
		ui.top_right_panel(app.g_app, bold_header_font, audio_state, top_h, third_w, right_w)
		// Bottom
		different_playlist_songs :=
			app.g_app.playlist_item_clicked ? display_songs : app.g_app.all_songs
		ui.bottom_panel(
			app.g_app,
			&different_playlist_songs,
			audio_state,
			top_h,
			screen_w,
			third_h,
		)

		// ui.render_audio_visualizer(audio_state)


		im.Render()
		display_w, display_h := glfw.GetFramebufferSize(window)
		gl.Viewport(0, 0, display_w, display_h)
		gl.ClearColor(0.05, 0.08, 0.12, 1.0)
		gl.Clear(gl.COLOR_BUFFER_BIT)
		imgui_impl_opengl3.RenderDrawData(im.GetDrawData())

		when !DISABLE_DOCKING {
			backup_current_window := glfw.GetCurrentContext()
			im.UpdatePlatformWindows()
			im.RenderPlatformWindowsDefault()
			glfw.MakeContextCurrent(backup_current_window)
		}

		glfw.SwapBuffers(window)
		free_all(context.temp_allocator)
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
