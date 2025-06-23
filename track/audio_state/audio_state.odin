package audio


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
	repeat:                      bool,
	thread_done:                 bool,
	play_next:                   bool,
}

// Initializes a new AudioState
init_audio_state :: proc() -> ^AudioState {
	state := new(AudioState)
	state.volume = 0.3 // Default volume
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
play_audio :: proc(state: ^AudioState, file_path: cstring) {
	sync.mutex_lock(&state.mutex)
	defer sync.mutex_unlock(&state.mutex)
	state.thread_done = false
	state.repeat = true
	fmt.println("[PLAY_AUDIO_LOG] Starting new song playback...")

	// Stop and clean up any currently playing audio
	if state.device != nil {
		fmt.println("[PLAY_AUDIO_LOG] Stopping and cleaning up previous device...")
		ma.device_stop(state.device)
		time.sleep(5 * time.Millisecond)
		state.current_time = 0
		ma.decoder_seek_to_pcm_frame(state.decoder, 0)
		ma.device_uninit(state.device)
		free(state.device)
		state.device = nil
	}

	if state.decoder != nil {
		fmt.println("[PLAY_AUDIO_LOG] Uninitializing previous decoder...")
		ma.decoder_uninit(state.decoder)
		free(state.decoder)
		state.decoder = nil
	}

	// Initialize new decoder
	fmt.printf("Loading audio file: %s\n", file_path)
	decoder := new(ma.decoder)
	ma.decoder_seek_to_pcm_frame(decoder, 0)

	err := ma.decoder_init_file(file_path, nil, decoder)
	if err != .SUCCESS {
		fmt.printf("Failed to load file: %v\n", err)
		free(decoder)
		return
	}

	// Seek decoder to beginning before playback starts
	fmt.println("[PLAY_AUDIO_LOG] Seeking decoder to the beginning...")

	// Get duration of the track
	frame_count: u64
	ma.decoder_get_available_frames(decoder, &frame_count)
	state.duration = auto_cast frame_count / auto_cast decoder.outputSampleRate

	fmt.printf("Duration: %.2f seconds (%.1f minutes)\n", state.duration, state.duration / 60)

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
			fmt.printf("Seeking inside callback to frame: %d\n", target_frame)
			ma.decoder_seek_to_pcm_frame(state.decoder, target_frame)
			state.current_time = state.seek_target
			state.should_seek = false
		}

		// if !state.was_paused {
		// 	state.is_playing = false
		// }

		frames_read: u64 = 0
		read_result := ma.decoder_read_pcm_frames(
			state.decoder,
			output,
			auto_cast frame_count,
			&frames_read,
		)

		state.current_time += auto_cast frames_read / auto_cast state.decoder.outputSampleRate
		// fmt.printf("🎧 Current time: %.2f / %.2f\n", state.current_time, state.duration)

		if read_result != .SUCCESS || frames_read < auto_cast frame_count {
			context = runtime.default_context()
			fmt.println("[PLAY_AUDIO_LOG] Reached end of stream or error during read.")
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
	fmt.println("[PLAY_AUDIO_LOG] Initializing playback device...")
	device := new(ma.device)
	if ma.device_init(nil, &device_config, device) != .SUCCESS {
		fmt.println("[PLAY_AUDIO_LOG] Failed to open playback device")
		ma.decoder_uninit(decoder)
		free(decoder)
		free(device)
		return
	}

	// Set volume
	fmt.printf("Setting volume to %.2f\n", state.volume)
	ma.device_set_master_volume(device, state.volume)

	// Start playback
	if ma.device_start(device) != .SUCCESS {
		fmt.println("[PLAY_AUDIO_LOG] Failed to start playback device")
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

	fmt.println("[PLAY_AUDIO_LOG] Playback started from the beginning successfully.")
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


update_audio :: proc(state: ^AudioState) {
	sync.mutex_lock(&state.mutex)
	defer sync.mutex_unlock(&state.mutex)

	if state.device == nil || state.decoder == nil {
		return
	}

	// Check if sound finished playing
	// if state.is_playing && state.current_time >= state.duration {
	// fmt.println("Song finished.")
	// state.is_playing = false
	// state.current_time = 0
	if !state.is_playing && !state.was_paused {
		if state.repeat {
			fmt.println("Repeating song...")
			state.seek_target = 0
			state.should_seek = true
			state.is_playing = true
			ma.device_start(state.device)
		} else if state.play_next {
			state.seek_target = 0
			state.should_seek = true
			state.is_playing = true
			ma.device_start(state.device)

		}
		// ma.decoder_seek_to_pcm_frame(state.decoder, 0)
	}
}


create_audio_play_thread :: proc(state: ^AudioState, path: cstring) {
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
	state.thread = thread.create_and_start_with_poly_data2(state, path, play_audio)
}
