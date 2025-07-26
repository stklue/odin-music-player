package track

import "core:c/libc"
import "core:mem"
DISABLE_DOCKING :: #config(DISABLE_DOCKING, true)

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import media "media"
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

import "core:log"


main :: proc() {
	context.logger = log.create_console_logger()
	default_allocator := context.allocator
	tracking_allocator: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking_allocator, default_allocator)
	context.allocator = mem.tracking_allocator(&tracking_allocator)

	running: bool = true // Atomic for thread safety

	reset_tracking_allocator :: proc(a: ^mem.Tracking_Allocator) -> bool {
		err := false
		for _, value in a.allocation_map {
			fmt.printfln("%v: Leaked %v bytes", value.location, value.size)
			err = true
		}

		mem.tracking_allocator_clear(a)
		return err
	}


	// ============== OPENGL AND GLFW INIT ===============================
	if glfw.Init() != glfw.TRUE {
		fmt.println("Failed to initialize GLFW")
	}
	defer glfw.Terminate()

	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 3)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 2)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, 1) // i32(true)
	monitor := glfw.GetPrimaryMonitor()
	mode := glfw.GetVideoMode(monitor)
	window := glfw.CreateWindow(1920, 1080, "Music Player", nil, nil)
	// assert(window != nil)
	if window == nil {
		fmt.println("Unable to create window")
		return
	}
	defer glfw.DestroyWindow(window)


	glfw.MakeContextCurrent(window)
	glfw.SwapInterval(1) // vsync
	// glfw.SetKeyCallback(window, key_callback)

	gl.load_up_to(3, 2, proc(p: rawptr, name: cstring) {
		(cast(^rawptr)p)^ = glfw.GetProcAddress(name)
	})


	// ============== APP STATE AND IM GUI SETUP ===============================
	im.CHECKVERSION()
	im.CreateContext(nil)
	defer im.DestroyContext(nil)
	io := im.GetIO()

	imgui_impl_glfw.InitForOpenGL(window, true)
	defer {
		log.info("Shutting down ImGui GLFW")
		imgui_impl_glfw.Shutdown()
	}
	imgui_impl_opengl3.Init("#version 150")
	defer {
		log.info("Shutting down ImGui OpenGL3")
		imgui_impl_opengl3.Shutdown()
	}

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

	all_songs_mutex: sync.Mutex
	all_files_scan_done: bool
	scan_all_songs_thread := thread.create_and_start_with_poly_data3(
		&app.g_app.library,
		&all_songs_mutex,
		&all_files_scan_done,
		media.scan_all_files,
	)

	all_playlists_mutex: sync.Mutex
	all_playlists_scan_done: bool
	scan_playlists_thread := thread.create_and_start_with_poly_data3(
		&app.g_app.library,
		&all_playlists_mutex,
		&all_playlists_scan_done,
		media.scan_all_playlists,
	)


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
	ma.engine_init(nil, &audio_state.engine)
	defer ma.engine_uninit(&audio_state.engine)


	style := im.GetStyle()
	style.Colors[im.Col.ScrollbarBg] = im.Vec4{0.10, 0.12, 0.18, 0.25}
	style.Colors[im.Col.ScrollbarGrab] = im.Vec4{0.20, 0.50, 0.90, 0.35}
	style.Colors[im.Col.ScrollbarGrabHovered] = im.Vec4{0.30, 0.60, 1.00, 0.45}
	style.Colors[im.Col.ScrollbarGrabActive] = im.Vec4{0.45, 0.80, 1.00, 0.60}


	// globals
	search_results: [dynamic]media.SearchItem
	search_mutex: sync.Mutex


	//  gui state
	song_query_buffer: [256]u8 // search buffer 
	// Initialize once at startup
	// ui.init_visualizer()

	// for !glfw.WindowShouldClose(window) && running {
	for !glfw.WindowShouldClose(window) && sync.atomic_load(&running) {
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


		// // Update audio state
		audio.update_audio(audio_state)

		// // ==================== UI Key input ====================
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
			}
		}
		if im.IsKeyPressed(.F) && im.GetIO().KeyCtrl {
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

		style := im.GetStyle()
		style.ChildRounding = 10
		left_panel_window_size := im.Vec2{third_w, top_h}
		if all_playlists_scan_done {
			ui.top_left_panel(
				&app.g_app.library.playlists,
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
				&app.g_app.library.songs,
				bold_header_font,
				audio_state,
				right_panel_window_position,
				right_panel_window_size,
			)
		}

		// // ==================== Bottom ====================
		ui.bottom_panel(app.g_app, audio_state, top_h, screen_w, third_h)

		im.Render()
		display_w, display_h := glfw.GetFramebufferSize(window)
		gl.Viewport(0, 0, display_w, display_h)
		gl.ClearColor(0.05, 0.08, 0.12, 1.0)
		gl.Clear(gl.COLOR_BUFFER_BIT)
		imgui_impl_opengl3.RenderDrawData(im.GetDrawData())

		glfw.SwapBuffers(window)


		if len(tracking_allocator.bad_free_array) > 0 {
			for b in tracking_allocator.bad_free_array {
				log.errorf("Bad free at: %v\n", b.location)
			}
			libc.getchar()
			panic("Bad free detected")
		}
		free_all(context.temp_allocator) // free after every frame
	}
	log.info("Exiting main loop")
	sync.atomic_store(&running, false)

	// kill threads
	// At the end of main, before cleanup
	if all_files_scan_done {
		thread.destroy(scan_all_songs_thread)
	} else {
		panic("All files thread did not manage to finish")
	}
	if all_playlists_scan_done {
		thread.destroy(scan_playlists_thread)
	} else {
		panic("Playlists thread did not manage to finish")
	}

	// these two threads may not execute and will be nil
	if app.g_app.library.search_thread != nil {
		thread.destroy(app.g_app.library.search_thread)
		log.info("Killed search thread")
	}
	if app.g_app.library.playlist_thread != nil {
		thread.destroy(app.g_app.library.playlist_thread)
		log.info("Killed playlist thread")
	}

	{
		delete_dynamic_array(app.g_app.clicked_playlist_entries)
		delete_dynamic_array(app.g_app.clicked_search_results_entries)
		delete_dynamic_array(app.g_app.play_queue)
		delete(app.g_app.arena.data)
		log.info("Deleting dynamic arrays")
		media.delete_library(&app.g_app.library)
		free(app.g_app)
		log.info("Freed global app")
	}
	
	audio.destroy_audio_state(audio_state)
	if reset_tracking_allocator(&tracking_allocator) {
		libc.getchar()
	}
	mem.tracking_allocator_destroy(&tracking_allocator)
}


// Called when glfw keystate changes
// key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
// 	// Exit program on escape pressed
// 	if key == glfw.KEY_ESCAPE {
// 		running = false
// 	}
// }
