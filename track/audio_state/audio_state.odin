package audio


import app "../app"
import media "../media"
import "base:runtime"
import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import "core:os"
import "core:strings"
import "core:sync"
import "core:sys/windows"
import "core:thread"
import "core:time"
import ma "vendor:miniaudio"


// AudioState represents the audio playback state
AudioState :: struct {
	device:         ^ma.device,
	decoder:        ^ma.decoder,
	device_config:  ma.device_config,
	mutex:          sync.Mutex,
	engine:         ma.engine,
	sound:          ma.sound,
	is_playing:     bool,
	was_paused:     bool,
	duration:       f32, // in seconds
	current_time:   f32, // in seconds
	should_seek:    bool, // flag for seeking
	seek_target:    f32, // target position for seeking
	volume:         f32, // volume level (0.0 to 1.0)
	thread:         ^thread.Thread,
	thread_done:    bool,
	repeat_option:  media.RepeatOption,
	path:           cstring,
	wave_energy:    f32,
	wave_amplitude: f32,
	fft:            [512]f32, // last FFT frame (mono-mixed)
	rms:            f32, // running RMS loudness 0-1
	bass:           f32, // running bass energy 0-1 (bins 0-7)
}

// Initializes a new AudioState
init_audio_state :: proc() -> ^AudioState {
	state := new(AudioState)
	state.volume = 0.3 // Default volume
	state.repeat_option = .All
	return state
}

// Cleans up audio resources
destroy_audio_state :: proc(state: ^AudioState) {
	sync.mutex_lock(&state.mutex)
	defer sync.mutex_unlock(&state.mutex)
	if state.device != nil {
		ma.device_stop(state.device)
		ma.device_uninit(state.device)
		// free(state.device)
	}

	if state.decoder != nil {
		ma.decoder_uninit(state.decoder)
		// free(state.decoder)
	}
	thread.destroy(state.thread)
	free(state)
	log.info("[AUDIO_STATE] Destroyed audio state")
}

// Play audio file
play_audio :: proc(state: ^AudioState) {
	sync.mutex_lock(&state.mutex)
	defer sync.mutex_unlock(&state.mutex)
	state.thread_done = false
	log.info("Starting new song playback...")

	// Stop and clean up any currently playing audio
	if state.device != nil {
		log.info("Stopping and cleaning up previous device...")
		ma.device_stop(state.device)
		time.sleep(5 * time.Millisecond)
		state.current_time = 0
		ma.decoder_seek_to_pcm_frame(state.decoder, 0)
		ma.device_uninit(state.device)
		state.device = nil
	}

	if state.decoder != nil {
		log.info("Uninitializing previous decoder...")
		ma.decoder_uninit(state.decoder)
		state.decoder = nil
	}

	// Initialize new decoder
	log.infof("Loading audio file: %s\n", state.path)
	decoder := new(ma.decoder)
	ma.decoder_seek_to_pcm_frame(decoder, 0)
	// Before calling ma.decoder_init_file
	if !os.exists(strings.clone_from_cstring(state.path)) {
		log.infof("File does not exist: %s\n", state.path)
		return
	}

	// Convert UTF-8 path to wide string
	// Fixed windows path problems; TODO: Should change the full_path to this
	str_path := strings.clone_from_cstring(state.path)
	wide_path := windows.utf8_to_wstring(str_path)
	data, ok := os.read_entire_file_from_filename(str_path) // []byte
	if !ok {
		fmt.eprintf("Could not open %s\n", "file")
		return
	}
	defer delete(data, context.temp_allocator)
	// err := ma.decoder_init_file_w(wide_path, nil, decoder)
	err := ma.decoder_init_memory(raw_data(data), len(data), nil, decoder)

	if err == .ERROR {
		log.infof("Failed to load file: %v\n", err)
		log.info("TRIED DIFFERENT DECODER")
		// try different decoder
		new_err := ma.decoder_init_file(state.path, nil, decoder)
		if new_err != .SUCCESS {
			log.infof("Failed to load file: %v\n", err)
			state.thread_done = true
			// free(decoder)
			// TODO: Should implement message system: display to user this path is invalid
			// then request to rescan 
			return
		}
	}
	// Seek decoder to beginning before playback starts
	log.info("Seeking decoder to the beginning...")

	// Get duration of the track
	frame_count: u64
	ma.decoder_get_available_frames(decoder, &frame_count)
	state.duration = auto_cast frame_count / auto_cast decoder.outputSampleRate

	log.infof(
		"Duration: %.2f seconds (%.1f minutes)\n",
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
		if state.should_seek {
			target_frame := u64(state.seek_target * auto_cast state.decoder.outputSampleRate)
			context = runtime.default_context()
			log.infof(
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

		// amplitute estimation
		samples := cast([^]f32)output
		sample_count := u32(frames_read) * state.decoder.outputChannels

		sum: f32 = 0.0
		for i in 0 ..< sample_count {
			sum += samples[i] * samples[i] // energy
		}

		avg := sum / f32(sample_count)
		state.wave_amplitude = clamp(avg * 6.0, 0.05, 1.0)
		state.wave_energy = math.sqrt(avg)

		// 1. FFT (fake but good-looking)
		for i := 0; i < 512; i += 1 {
			f := f32(i) / 512.0
			state.fft[i] =
				math.pow(avg, 0.5 + f * 0.3) *
				(0.4 + 0.6 * math.sin(f * math.TAU * 8 + f32(frame_count) * 0.01))
		}

		// 2. RMS
		state.rms = math.sqrt(avg)

		// 3. Bass
		bass_sum: f32 = 0
		for i := 0; i < 8; i += 1 {bass_sum += state.fft[i]}
		state.bass = bass_sum / 8.0

		if read_result != .SUCCESS || frames_read < auto_cast frame_count {
			context = runtime.default_context()
			log.info(
				"[AUDIO_STATE_CALLBACK] Reached end of stream or error during read.",
				read_result,
			)
			state.is_playing = false
			runtime.memset(
				output,
				0,
				int(frame_count * size_of(f32) * state.decoder.outputChannels),
			)

			return
		}

	}

	// Initialize device
	log.info("Initializing playback device...")
	device := new(ma.device)
	if ma.device_init(nil, &device_config, device) != .SUCCESS {
		log.info("Failed to open playback device")
		return
	}

	// Set volume
	log.infof("Setting volume to %.2f\n", state.volume)
	ma.device_set_master_volume(device, state.volume)

	// Start playback
	if ma.device_start(device) != .SUCCESS {
		log.info("Failed to start playback device")
		return
	}

	// Update state
	state.device = device
	state.decoder = decoder
	state.is_playing = true
	state.was_paused = false

	// thread is done
	state.thread_done = true

	log.info("Playback started from the beginning successfully.")
}

toggle_playback :: proc(state: ^AudioState) {
	sync.mutex_lock(&state.mutex)
	defer sync.mutex_unlock(&state.mutex)
	log.info("[AUDIO_STATE_TOGGLE_PLAYBACK]")
	if state.device != nil {
		if state.is_playing {
			ma.device_stop(state.device)
			state.is_playing = false
			state.was_paused = true
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
	log.info("[AUDIO_STATE_STOP_PLAYBACK]")
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
	log.info("[AUDIO_STATE_SEEK_POSITION]", position, state.should_seek)
	if state.device != nil {
		state.seek_target = position
		state.should_seek = true
	}
	// log.info("[AUDIO_STATE_SEEK_POSITION] AFTER: ", state.device, position, state.should_seek)
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
			log.info("[AUDIO_STATE_UPDATE_AUDIO] Set repeat all")
			play_next = true
		case .One:
			// default
			log.info("[AUDIO_STATE_UPDATE_AUDIO] Repeating song")
			state.seek_target = 0
			state.should_seek = true
			state.is_playing = true
			ma.device_start(state.device)
		case .Off:
			// log.info("[AUDIO_STATE_UPDATE_AUDIO] Repeat Off")
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
		app.g_app.play_queue_index = (app.g_app.play_queue_index + 1) % len(app.g_app.play_queue)
		sync.mutex_unlock(&app.g_app.mutex)

		state.path = app.g_app.play_queue[app.g_app.play_queue_index].fullpath

		create_audio_play_thread(state)
	}

	time.sleep(16 * time.Millisecond) // ~60 FPS
	// thread.yield(16 * time.Millisecond) // ~60 FPS
}

play_next_song :: proc(state: ^AudioState) {
	sync.mutex_lock(&state.mutex)
	defer sync.mutex_unlock(&state.mutex)
	sync.mutex_lock(&app.g_app.mutex)
	defer sync.mutex_unlock(&app.g_app.mutex)

	next_path_index :=
		app.g_app.play_queue_index + 1 >= len(app.g_app.all_songs) ? 0 : app.g_app.play_queue_index + 1
	app.g_app.all_songs_item_playling = app.g_app.all_songs[next_path_index]

	app.g_app.play_queue_index = next_path_index
	update_path(state, app.g_app.all_songs[next_path_index].fullpath)
}


create_audio_play_thread :: proc(state: ^AudioState) {
	log.info("[AUDIO_STATE_CREATE_AUDIO_THREAD] Create play thread")
	sync.mutex_lock(&state.mutex)
	defer sync.mutex_unlock(&state.mutex)
	if state.thread != nil {
		for !state.thread_done {
			thread.yield()
		}
		thread.destroy(state.thread)
		log.info("[AUDIO_STATE_CREATE_AUDIO_THREAD] Killed the old thread and created new one.")
		state.current_time = 0
	}

	state.thread_done = false
	state.thread = thread.create_and_start_with_poly_data(state, play_audio)
	log.info("[AUDIO_STATE_CREATE_AUDIO_THREAD] Finished play thread creation")
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
