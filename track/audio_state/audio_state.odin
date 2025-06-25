package audio


import app "../app"
import common "../common"
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:sync"
import "core:thread"
import "core:time"
import ma "vendor:miniaudio"


// AudioState represents the audio playback state
AudioState :: struct {
	device:                      ^ma.device,
	decoder:                     ^ma.decoder,
	device_config:               ma.device_config,
	mutex:                       sync.Mutex,
	engine:                      ma.engine,
	sound:                       ma.sound,
	is_playing:                  bool,
	was_paused:                  bool,
	duration:                    f32, // in seconds
	current_time:                f32, // in seconds
	should_seek:                 bool, // flag for seeking
	seek_target:                 f32, // target position for seeking
	volume:                      f32, // volume level (0.0 to 1.0)
	thread:                      ^thread.Thread,
	is_new_song_but_not_same_pl: bool,
	thread_done:                 bool,
	repeat_option:               common.RepeatOption,
	path:                        cstring,
	next_path:                   cstring,
	next_path_index:             int,
}

// Initializes a new AudioState
init_audio_state :: proc() -> ^AudioState {
	state := new(AudioState)
	state.volume = 0.3 // Default volume
	state.repeat_option = .One
	// sync.mutext_(&state.mutex)
	return state
}

// Cleans up audio resources
destroy_audio_state :: proc(state: ^AudioState) {
	sync.mutex_lock(&state.mutex)
	defer sync.mutex_unlock(&state.mutex)

	if state.device != nil {
		ma.device_stop(state.device)
		ma.device_uninit(state.device)
		free(state.device)
		state.device = nil
	}

	if state.decoder != nil {
		ma.decoder_uninit(state.decoder)
		free(state.decoder)
		state.decoder = nil
	}

	free(state)
}

// Play audio file
play_audio :: proc(state: ^AudioState) {
	sync.mutex_lock(&state.mutex)
	defer sync.mutex_unlock(&state.mutex)
	state.thread_done = false
	// state.repeat = true
	fmt.println("[AUDIO_STATE_PLAY_AUDIO] Starting new song playback...")

	// Stop and clean up any currently playing audio
	if state.device != nil {
		fmt.println("[AUDIO_STATE_PLAY_AUDIO] Stopping and cleaning up previous device...")
		ma.device_stop(state.device)
		time.sleep(5 * time.Millisecond)
		state.current_time = 0
		ma.decoder_seek_to_pcm_frame(state.decoder, 0)
		ma.device_uninit(state.device)
		free(state.device)
		state.device = nil
	}

	if state.decoder != nil {
		fmt.println("[AUDIO_STATE_PLAY_AUDIO] Uninitializing previous decoder...")
		ma.decoder_uninit(state.decoder)
		free(state.decoder)
		state.decoder = nil
	}

	// Initialize new decoder
	fmt.printf("[AUDIO_STATE_PLAY_AUDIO] Loading audio file: %s\n", state.path)
	decoder := new(ma.decoder)
	ma.decoder_seek_to_pcm_frame(decoder, 0)

	err := ma.decoder_init_file(state.path, nil, decoder)
	if err != .SUCCESS {
		fmt.printf("[AUDIO_STATE_PLAY_AUDIO] Failed to load file: %v\n", err)
		free(decoder)
		return
	}

	// Seek decoder to beginning before playback starts
	fmt.println("[AUDIO_STATE_PLAY_AUDIO] Seeking decoder to the beginning...")

	// Get duration of the track
	frame_count: u64
	ma.decoder_get_available_frames(decoder, &frame_count)
	state.duration = auto_cast frame_count / auto_cast decoder.outputSampleRate

	fmt.printf(
		"[AUDIO_STATE_PLAY_AUDIO] Duration: %.2f seconds (%.1f minutes)\n",
		state.duration,
		state.duration / 60,
	)

	// Set up device config
	device_config := ma.device_config_init(.playback)
	device_config.playback.format = decoder.outputFormat
	device_config.playback.channels = decoder.outputChannels
	device_config.sampleRate = decoder.outputSampleRate
	device_config.pUserData = state

	// Data callback with progress tracking
	device_config.dataCallback =
	proc "c" (device: ^ma.device, output: rawptr, input: rawptr, frame_count: u32) {
		state := cast(^AudioState)device.pUserData
		sync.mutex_lock(&state.mutex)
		defer sync.mutex_unlock(&state.mutex)
		// context = runtime.default_context()
		// fmt.printfln("1. Inside callback: %d", state.current_time)

		if state.should_seek {
			target_frame := u64(state.seek_target * auto_cast state.decoder.outputSampleRate)
			context = runtime.default_context()
			fmt.printf(
				"[AUDIO_STATE_CALLBACK] Seeking inside callback to frame: %d\n",
				target_frame,
			)
			ma.decoder_seek_to_pcm_frame(state.decoder, target_frame)
			state.current_time = state.seek_target
			state.should_seek = false
		}

		frames_read: u64 = 0
		read_result := ma.decoder_read_pcm_frames(
			state.decoder,
			output,
			auto_cast frame_count,
			&frames_read,
		)

		state.current_time += auto_cast frames_read / auto_cast state.decoder.outputSampleRate
		// fmt.printf(" Current time: %.2f / %.2f\n", state.current_time, state.duration)

		if read_result != .SUCCESS || frames_read < auto_cast frame_count {
			context = runtime.default_context()
			fmt.println(
				"[AUDIO_STATE_CALLBACK] Reached end of stream or error during read.",
				read_result,
			)
			state.is_playing = false
			// ma.device_stop(device)
			runtime.memset(
				output,
				0,
				int(frame_count * size_of(f32) * state.decoder.outputChannels),
			)

			return
		}


		// context = runtime.default_context()
		// fmt.printfln("2. Inside callback: %.2f", state.current_time)
	}

	// Initialize device
	fmt.println("[AUDIO_STATE_PLAY_AUDIO] Initializing playback device...")
	device := new(ma.device)
	if ma.device_init(nil, &device_config, device) != .SUCCESS {
		fmt.println("[AUDIO_STATE_PLAY_AUDIO] Failed to open playback device")
		ma.decoder_uninit(decoder)
		free(decoder)
		free(device)
		return
	}

	// Set volume
	fmt.printf("[AUDIO_STATE_PLAY_AUDIO] Setting volume to %.2f\n", state.volume)
	ma.device_set_master_volume(device, state.volume)

	// Start playback
	if ma.device_start(device) != .SUCCESS {
		fmt.println("[AUDIO_STATE_PLAY_AUDIO] Failed to start playback device")
		ma.device_uninit(device)
		ma.decoder_uninit(decoder)
		free(device)
		free(decoder)
		return
	}

	// Update state
	state.device = device
	state.decoder = decoder
	state.is_playing = true
	state.was_paused = false

	// thread is done
	state.thread_done = true

	fmt.println("[AUDIO_STATE_PLAY_AUDIO] Playback started from the beginning successfully.")
}

toggle_playback :: proc(state: ^AudioState) {
	sync.mutex_lock(&state.mutex)
	defer sync.mutex_unlock(&state.mutex)

	// if state.device != nil {
	// 	if state.is_playing {
	// 		ma.device_stop(state.device)
	// 		state.is_playing = false
	// 	} else {
	// 		ma.device_start(state.device)
	// 		state.is_playing = true
	// 	}
	// }

	if state.device != nil {
		if state.is_playing {
			ma.device_stop(state.device)
			state.is_playing = false
			state.was_paused = true // ✅ Mark it was a user pause
		} else {
			ma.device_start(state.device)
			state.is_playing = true
			state.was_paused = false
		}
	}

}

stop_playback :: proc(state: ^AudioState) {
	sync.mutex_lock(&state.mutex)
	defer sync.mutex_unlock(&state.mutex)

	if state.device != nil {
		ma.device_stop(state.device)
		state.is_playing = false
		state.current_time = 0
		if state.decoder != nil {
			ma.decoder_seek_to_pcm_frame(state.decoder, 0)
		}
	}
}

seek_to_position :: proc(state: ^AudioState, position: f32) {
	sync.mutex_lock(&state.mutex)
	defer sync.mutex_unlock(&state.mutex)

	if state.device != nil {
		state.seek_target = position
		state.should_seek = true
	}
}

set_volume :: proc(state: ^AudioState, volume: f32) {
	sync.mutex_lock(&state.mutex)
	defer sync.mutex_unlock(&state.mutex)

	state.volume = clamp(volume, 0.0, 1.0)
	if state.device != nil {
		ma.device_set_master_volume(state.device, state.volume)
	}
}


update_path :: proc(state: ^AudioState, p: cstring) {
	sync.mutex_lock(&state.mutex)
	defer sync.mutex_unlock(&state.mutex)

	state.path = p
}

//  called every frame in UI
update_audio :: proc(state: ^AudioState) {
	play_next := false
	sync.mutex_lock(&state.mutex)
	// defer sync.mutex_unlock(&state.mutex)

	if state.device == nil || state.decoder == nil {
		sync.mutex_unlock(&state.mutex)
		return
	}

	// Check if sound finished playing
	if !state.is_playing && !state.was_paused {
		switch state.repeat_option {
		case .All:
			fmt.println("[AUDIO_STATE_UPDATE_AUDIO] Set repeat all")
			play_next = true
		case .One:
			// default
			fmt.println("[AUDIO_STATE_UPDATE_AUDIO] Repeating song")
			state.seek_target = 0
			state.should_seek = true
			state.is_playing = true
			ma.device_start(state.device)
		case .Off:
			// fmt.println("[AUDIO_STATE_UPDATE_AUDIO] Repeat Off")
			state.seek_target = 0
			state.should_seek = true
			state.is_playing = false
			ma.device_stop(state.device)
		}
		// ma.decoder_seek_to_pcm_frame(state.decoder, 0)
	}


	sync.mutex_unlock(&state.mutex)

	// Safe to call now, *after* releasing the lock
	if play_next {
		sync.mutex_lock(&app.g_app.mutex)
		app.g_app.current_item_playing_index += 1
		sync.mutex_unlock(&app.g_app.mutex)
		state.path = app.g_app.all_songs[app.g_app.current_item_playing_index].fullpath

		create_audio_play_thread(state)
	}
}

play_next_song :: proc(state: ^AudioState) {
	sync.mutex_lock(&state.mutex)
	defer sync.mutex_unlock(&state.mutex)
	sync.mutex_lock(&app.g_app.mutex)
	defer sync.mutex_unlock(&app.g_app.mutex)

	next_path_index :=
		app.g_app.current_item_playing_index + 1 >= len(app.g_app.all_songs) ? 0 : app.g_app.current_item_playing_index + 1
	app.g_app.all_songs_item_playling = app.g_app.all_songs[next_path_index]

	app.g_app.current_item_playing_index = next_path_index
	update_path(state, app.g_app.all_songs[next_path_index].fullpath)
}


create_audio_play_thread :: proc(state: ^AudioState) {
	fmt.println("[AUDIO_STATE_CREATE_AUDIO_THREAD] Create play thread")
	sync.mutex_lock(&state.mutex)
	defer sync.mutex_unlock(&state.mutex)
	if state.thread != nil {
		for !state.thread_done {
			thread.yield()
		}
		thread.destroy(state.thread)
		state.thread = nil
		fmt.println("Killed the old thread and created new one.")
		// state.decoder = nil
		state.current_time = 0
	}

	state.thread_done = false
	// thread.destroy(state.thread)
	state.thread = thread.create_and_start_with_poly_data(state, play_audio)
	fmt.println("[AUDIO_STATE_CREATE_AUDIO_THREAD] Finished play thread creation")
}


skip_2s_forward :: proc(state: ^AudioState) {
	sync.mutex_lock(&state.mutex)
	defer sync.mutex_unlock(&state.mutex)

	if state.decoder == nil || state.device == nil {
		return
	}

	new_position := state.current_time + 2
	new_position = clamp(new_position, 0.0, state.duration)

	state.seek_target = new_position
	state.should_seek = true
}
skip_2s_backward :: proc(state: ^AudioState) {
	sync.mutex_lock(&state.mutex)
	defer sync.mutex_unlock(&state.mutex)

	if state.decoder == nil || state.device == nil {
		return
	}

	new_position := state.current_time - 2
	new_position = clamp(new_position, 0.0, state.duration)

	state.seek_target = new_position
	state.should_seek = true
}
skip_5s_forward :: proc(state: ^AudioState) {
	sync.mutex_lock(&state.mutex)
	defer sync.mutex_unlock(&state.mutex)

	if state.decoder == nil || state.device == nil {
		return
	}

	new_position := state.current_time + 5
	new_position = clamp(new_position, 0.0, state.duration)

	state.seek_target = new_position
	state.should_seek = true
}
skip_5s_backward :: proc(state: ^AudioState) {
	sync.mutex_lock(&state.mutex)
	defer sync.mutex_unlock(&state.mutex)

	if state.decoder == nil || state.device == nil {
		return
	}

	new_position := state.current_time - 5
	new_position = clamp(new_position, 0.0, state.duration)

	state.seek_target = new_position
	state.should_seek = true
}
