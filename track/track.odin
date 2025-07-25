package track

DISABLE_DOCKING :: #config(DISABLE_DOCKING, true)

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
import ui "ui"
import gl "vendor:OpenGL"
import "vendor:glfw"
import ma "vendor:miniaudio"
import vis "visualizer"

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

	imgui_impl_glfw.InitForOpenGL(window, true)
	defer imgui_impl_glfw.Shutdown()
	imgui_impl_opengl3.Init("#version 150")
	defer imgui_impl_opengl3.Shutdown()

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

	all_songs := new([dynamic]common.Song)
	all_songs_mutex: sync.Mutex
	all_files_scan_done: bool
	scan_all_songs_thread := thread.create_and_start_with_poly_data3(
		&all_songs_mutex,
		all_songs,
		&all_files_scan_done,
		common.scan_all_files,
	)

	all_playlists := new([dynamic]common.Playlist)
	all_playlists_mutex: sync.Mutex
	all_playlists_scan_done: bool
	scan_playlists_thread := thread.create_and_start_with_poly_data3(
		&all_playlists_mutex,
		all_playlists,
		&all_playlists_scan_done,
		common.scan_all_playlists,
	)
	// ==================== loading playlists ====================
	// thread.create_and_start_with_poly_data2(
	// 	&app.g_app.mutex,
	// 	&app.g_app.playlists,
	// 	pl.load_all_zpl_playlists,
	// )


	// thread.destroy(scan_all_songs_thread)

	// Use the sear_all_files with write metadata using taglib because it's slow
	// app.search_all_files_threaded(&app.g_app.all_songs, root, 4)

	// Use this to write the metadata to a txt file because taglib is slow
	// app.write_metadata_to_txt(app.g_app.all_songs)

	// if app.g_app.taglib_file_count > 0 {
	// 	avg :=
	// 		time.duration_milliseconds(app.g_app.taglib_total_duration) /
	// 		f64(app.g_app.taglib_file_count)
	// 	total := app.g_app.taglib_total_duration
	// 	fmt.printfln("TagLib processed %d files", app.g_app.taglib_file_count)
	// 	fmt.printfln("Total TagLib time: %.3f", total)
	// 	fmt.printfln("Average per file: %.3fms", avg)
	// } else {
	// 	fmt.println("No .mp3 files processed with TagLib.")
	// }

	//  initialize audio state and miniaudio engine
	audio_state := audio.init_audio_state()
	defer audio.destroy_audio_state(audio_state)
	ma.engine_init(nil, &audio_state.engine)
	defer ma.engine_uninit(&audio_state.engine)


	style := im.GetStyle()
	style.Colors[im.Col.ScrollbarBg] = im.Vec4{0.10, 0.12, 0.18, 0.25}
	style.Colors[im.Col.ScrollbarGrab] = im.Vec4{0.20, 0.50, 0.90, 0.35}
	style.Colors[im.Col.ScrollbarGrabHovered] = im.Vec4{0.30, 0.60, 1.00, 0.45}
	style.Colors[im.Col.ScrollbarGrabActive] = im.Vec4{0.45, 0.80, 1.00, 0.60}


	// globals
	search_results: [dynamic]common.SearchItem
	search_mutex: sync.Mutex


	//  gui state
	song_query_buffer: [256]u8 // search buffer 
	// Initialize once at startup
	ui.init_visualizer()
	vis.init_visualizer()

	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()

		imgui_impl_opengl3.NewFrame()
		imgui_impl_glfw.NewFrame()
		im.NewFrame()

		// ==================== Layout dimensions ====================
		viewport := im.GetMainViewport()
		screen_w := io.DisplaySize.x
		screen_h := io.DisplaySize.y

		third_w := screen_w / 4
		third_h := screen_h / 6

		top_h := screen_h - third_h // top 2/3 of height
		right_w := screen_w - third_w // right 2/3 of width


		// Update audio state
		audio.update_audio(audio_state)

		// ==================== UI Key input ====================
		if io.KeysDown[im.Key.Space] && im.IsKeyPressed(.Space) {
			// Check if any text input is currently active
			if !im.IsAnyItemActive() {
				audio.toggle_playback(audio_state)
			}
		}
		// shortcut
		if im.IsKeyPressed(.S, true) {
			if !im.IsAnyItemActive() {
				if app.g_app.ui_view != .Visualizer {
					app.g_app.ui_view = .Visualizer
				} else {
					app.g_app.ui_view = app.g_app.last_view
				}
				// app.g_app.show_visualizer = !app.g_app.show_visualizer
			}
		}
		if im.IsKeyPressed(.F) && im.GetIO().KeyCtrl {
			//  || io.KeySuper) {
			fmt.println("pressed control F")
			im.SetKeyboardFocusHere(4)
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

		// ==================== Top Left ====================
		im.SetNextWindowPos(im.Vec2{0, 0})
		im.SetNextWindowSize(im.Vec2{third_w, top_h})

		im.PushStyleColor(im.Col.ScrollbarBg, ui.color_vec4_to_u32({0.10, 0.12, 0.18, 0.25})) // dark blue base
		im.PushStyleColor(im.Col.ScrollbarGrab, ui.color_vec4_to_u32({0.20, 0.50, 0.90, 0.35})) // cool blue
		im.PushStyleColor(
			im.Col.ScrollbarGrabHovered,
			ui.color_vec4_to_u32({0.30, 0.60, 1.00, 0.45}),
		)
		im.PushStyleColor(
			im.Col.ScrollbarGrabActive,
			ui.color_vec4_to_u32({0.45, 0.80, 1.00, 0.60}),
		)

		// sync.mutex_lock(&all_songs_mutex)
		// if (all_files_scan_done) {
		// 	fmt.println("Main thread. Scanning is done.")
		// 	fmt.println("Here is the data: ", len(all_songs))
		// } else {
		// 	fmt.println("nothing")
		// }
		// sync.mutex_unlock(&all_songs_mutex)

		style := im.GetStyle()
		style.ChildRounding = 10
		// style.WindowRounding = 40
		left_panel_window_size := im.Vec2{third_w, top_h}
		if all_playlists_scan_done {
			ui.top_left_panel(
				all_songs,
				all_playlists,
				&all_playlists_mutex,
				all_playlists_scan_done,
				app.g_app,
				&search_results,
				root,
				audio_state,
				&song_query_buffer,
				left_panel_window_size,
			)
		}

		im.PopStyleColor(4)

		// ==================== Top Right ==================== 
		right_panel_window_position := im.Vec2{third_w, 0}
		right_panel_window_size := im.Vec2{right_w, top_h}
		if all_files_scan_done {
			ui.top_right_panel(
				all_songs,
				bold_header_font,
				audio_state,
				right_panel_window_position,
				right_panel_window_size,
			)
		}

		// ==================== Bottom ====================
		ui.bottom_panel(
			app.g_app,
			audio_state,
			top_h,
			screen_w,
			third_h,
		)

		im.Render()
		display_w, display_h := glfw.GetFramebufferSize(window)
		gl.Viewport(0, 0, display_w, display_h)
		gl.ClearColor(0.05, 0.08, 0.12, 1.0)
		gl.Clear(gl.COLOR_BUFFER_BIT)
		imgui_impl_opengl3.RenderDrawData(im.GetDrawData())

		glfw.SwapBuffers(window)
		free_all(context.temp_allocator) // free after every frame
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
