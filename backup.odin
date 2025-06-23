package main

// DISABLE_DOCKING :: #config(DISABLE_DOCKING, true)

// import "core:fmt"
// import "core:os"
// import "core:strings"

// // import im "../odin-imgui"
// // import "../odin-imgui/imgui_impl_glfw"
// // import "../odin-imgui/imgui_impl_opengl3"

// import "core:sync"
// import "core:thread"
// import "core:time"
// import gl "vendor:OpenGL"
// import "vendor:glfw"


// // load files in this thread
// load_files_thread_proc :: proc(mutex: ^sync.Mutex, shared: ^[dynamic]os.File_Info) {
// 	dir_path := "C:/Users/St.Klue/Music/Songs"
// 	dir_handle, err := os.open(dir_path)
// 	if err != os.ERROR_NONE {
// 		fmt.println("Failed to open directory: ", err)
// 		// return nil
// 	}
// 	defer os.close(dir_handle)
// 	// Read directory entries
// 	files, read_err := os.read_dir(dir_handle, 1024) // Read up to 1024 entries
// 	if read_err != os.ERROR_NONE {
// 		fmt.println("Failed to read directory: ", read_err)
// 		// return nil
// 	}


// 	sync.mutex_lock(mutex)
// 	// append(shared, file.name)
// 	append(shared, ..files[:])
// 	sync.mutex_unlock(mutex)
// 	fmt.printf("loaded %d files\n", len(files))

// 	// for file in files {
// 	// 	// Lock mutex before modifying shared data
// 	// 	sync.mutex_lock(mutex)
// 	// 	append(shared, file.name)
// 	// 	sync.mutex_unlock(mutex)

// 	// 	// thread.sleep_ms(10) // optional: simulate delay or prevent hogging CPU
// 	// 	time.sleep(time.Duration(f32(time.Millisecond) * 10))
// 	// 	// file_path := file.fullpath

// 	// 	// Attempt to read file
// 	// 	// data, err := os.read_entire_file_from_filename_or_err(file_path, context.allocator)
// 	// 	// if err != os.ERROR_NONE {
// 	// 	// 	fmt.println("Skipping file (read failed): ", file.name)
// 	// 	// 	continue
// 	// 	// }

// 	// 	// fmt.println("Loaded file: ", file.name, " size: ", len(data))

// 	// 	// Use the file data...
// 	// 	// defer context.allocator.free(data)  // Free memory if needed
// 	// }

// 	// return nil
// }


// main :: proc() {
// 	assert(cast(bool)glfw.Init())
// 	defer glfw.Terminate()

// 	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 3)
// 	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 2)
// 	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
// 	glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, 1) // i32(true)
// 	// glfw.WindowHint(glfw.DECORATED, false)
// 	// glfw.WindowHint(glfw.TRANSPARENT_FRAMEBUFFER, true)
// 	monitor := glfw.GetPrimaryMonitor()
// 	mode := glfw.GetVideoMode(monitor)
// 	window := glfw.CreateWindow(1920, 1080, "Music Player", nil, nil)
// 	assert(window != nil)
// 	defer glfw.DestroyWindow(window)

// 	glfw.MakeContextCurrent(window)
// 	glfw.SwapInterval(1) // vsync

// 	gl.load_up_to(3, 2, proc(p: rawptr, name: cstring) {
// 		(cast(^rawptr)p)^ = glfw.GetProcAddress(name)
// 	})

// 	im.CHECKVERSION()
// 	im.CreateContext()
// 	defer im.DestroyContext()
// 	io := im.GetIO()
// 	io.ConfigFlags += {.NavEnableKeyboard, .NavEnableGamepad}
// 	when !DISABLE_DOCKING {
// 		io.ConfigFlags += {.DockingEnable}
// 		io.ConfigFlags += {.ViewportsEnable}

// 		style := im.GetStyle()
// 		style.WindowRounding = 0
// 		style.Colors[im.Col.WindowBg].w = 1
// 	}

// 	im.StyleColorsDark()

// 	imgui_impl_glfw.InitForOpenGL(window, true)
// 	defer imgui_impl_glfw.Shutdown()
// 	imgui_impl_opengl3.Init("#version 150")
// 	defer imgui_impl_opengl3.Shutdown()

// 	// globals
// 	shared_files: [dynamic]os.File_Info
// 	shared_files_mutex: sync.Mutex

// 	// loading music files into memory
// 	file_thread := thread.create_and_start_with_poly_data2(
// 		&shared_files_mutex,
// 		&shared_files,
// 		load_files_thread_proc,
// 	)


// 	//  gui state
// 	off := false
// 	my_buffer: [256]u8

// 	for !glfw.WindowShouldClose(window) {
// 		glfw.PollEvents()

// 		imgui_impl_opengl3.NewFrame()
// 		imgui_impl_glfw.NewFrame()
// 		im.NewFrame()


// 		viewport := im.GetMainViewport()
// 		screen_w := io.DisplaySize.x
// 		screen_h := io.DisplaySize.y

// 		third_w := screen_w / 4
// 		third_h := screen_h / 6

// 		top_h := screen_h - third_h // top 2/3 of height
// 		right_w := screen_w - third_w // right 2/3 of width

// 		im.PushStyleVar(im.StyleVar.WindowRounding, 0)
// 		im.PushStyleVar(im.StyleVar.WindowBorderSize, 0)
// 		// main window 
// 		im.SetNextWindowPos(im.Vec2{0, 0}, .Appearing)
// 		im.SetNextWindowSize(viewport.Size, .Appearing)
// 		if im.Begin("Track Player", nil, {.NoResize, .NoCollapse, .NoMove, .MenuBar}) {
// 			// Top Left
// 			im.SetNextWindowPos(im.Vec2{0, 0})
// 			im.SetNextWindowSize(im.Vec2{third_w, top_h})

// 			cstring_buffer := cast(cstring)(&my_buffer[0])
// 			if im.Begin("Top Left") {
// 				im.Text("This is Top Left")
// 				if im.InputText("Search for songs", cstring_buffer, 100) {
// 				}

// 			}
// 			im.End()

// 			// Top Right
// 			im.SetNextWindowPos(im.Vec2{third_w, 0})
// 			im.SetNextWindowSize(im.Vec2{right_w, top_h})
// 			if im.Begin("Top Right") {
// 				im.Text("This is Top Right")
// 				sync.mutex_lock(&shared_files_mutex)
// 				for file_name in shared_files {
// 					im.Text(strings.clone_to_cstring(file_name.name))
// 				}
// 				sync.mutex_unlock(&shared_files_mutex)
// 			}
// 			im.End()

// 			// Bottom
// 			im.SetNextWindowPos(im.Vec2{0, top_h})
// 			im.SetNextWindowSize(im.Vec2{screen_w, third_h})
// 			if im.Begin("Bottom") {
// 				im.Text("This is Bottom Row")
// 			}
// 			im.End()
// 		}
// 		im.End()

// 		im.PopStyleVar(2)

// 		im.Render()
// 		display_w, display_h := glfw.GetFramebufferSize(window)
// 		gl.Viewport(0, 0, display_w, display_h)
// 		gl.ClearColor(0, 0, 0, 1)
// 		gl.Clear(gl.COLOR_BUFFER_BIT)
// 		imgui_impl_opengl3.RenderDrawData(im.GetDrawData())

// 		when !DISABLE_DOCKING {
// 			backup_current_window := glfw.GetCurrentContext()
// 			im.UpdatePlatformWindows()
// 			im.RenderPlatformWindowsDefault()
// 			glfw.MakeContextCurrent(backup_current_window)
// 		}

// 		glfw.SwapBuffers(window)
// 	}
// }



// // Progress bar
// 				// progress :=
// 				// 	audio_state.duration > 0 ? audio_state.current_time / audio_state.duration : 0
// 				// im.ProgressBar(
// 				// 	progress,
// 				// 	{im.GetContentRegionAvail().x, 20},
// 				// 	strings.clone_to_cstring(
// 				// 		fmt.tprintf(
// 				// 			"%.1f / %.1f seconds",
// 				// 			audio_state.current_time,
// 				// 			audio_state.duration,
// 				// 		),
// 				// 	),
// 				// )

// 				// // Seek slider
// 				// if im.SliderFloat(
// 				// 	"##seek",
// 				// 	&audio_state.current_time,
// 				// 	0,
// 				// 	audio_state.duration,
// 				// 	text(
// 				// 		fmt.tprintf(
// 				// 			"%.0f:%.0f",
// 				// 			math.floor(audio_state.current_time / 60),
// 				// 			math.floor(math.mod(audio_state.current_time, 60)),
// 				// 		),
// 				// 	),
// 				// ) {
// 				// 	// fmt.println("touching the slider")

// 				// 	// Only seek when user releases the slider
// 				// 	if im.IsMouseReleased(.Left) {
// 				// 		fmt.println("mouse was released")
// 				// 		// audio.seek_to_position(audio_state, audio_state.current_time)
// 				// 	}
// 				// }
// 				// if im.IsItemDeactivatedAfterEdit() {
// 				// 	fmt.println("mouse was released")
// 				// 	audio.seek_to_position(audio_state, audio_state.current_time)

// 				// }