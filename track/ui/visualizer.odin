package ui

import im "../../odin-imgui"
import audio "../audio_state"
import "core:math"
import "core:math/rand"
import "core:time"
import gl "vendor:OpenGL"

// Visualizer Config
NUM_SAMPLES: int : 1024
NUM_BANDS: int : 64
PARTICLE_LIMIT: int : 300
HISTORY_SIZE: int : 32


// HSV to RGB
hsv_to_rgb :: proc(h: f32, s: f32, v: f32) -> im.Vec4 {
	c := v * s
	x := c * (1.0 - math.abs(math.mod(h * 6.0, 2.0) - 1.0))
	m := v - c
	r, g, b: f32

	if h < 1.0 / 6.0 {
		r, g, b = c, x, 0
	} else if h < 2.0 / 6.0 {
		r, g, b = x, c, 0
	} else if h < 3.0 / 6.0 {
		r, g, b = 0, c, x
	} else if h < 4.0 / 6.0 {
		r, g, b = 0, x, c
	} else if h < 5.0 / 6.0 {
		r, g, b = x, 0, c
	} else {
		r, g, b = c, 0, x
	}

	return im.Vec4{r + m, g + m, b + m, 1.0}
}


Wave_Particle :: struct {
	pos:      im.Vec2,
	velocity: im.Vec2,
	color:    im.Vec4,
	life:     f32,
	size:     f32,
}

Visualizer_State :: struct {
	wave_time:         f32,
	wave_speed:        f32,
	wave_amplitude:    f32,
	wave_freq:         f32,
	particles:         [dynamic]Wave_Particle,
	max_particles:     int,
	last_time:         time.Time,
	color:             im.Vec4,
	audio_reactivity:  f32, // 0-1 how much to react to audio
	audio_sensitivity: f32, // scales audio input
}

g_vis: Visualizer_State

init_visualizer :: proc() {
	g_vis.wave_time = 0
	g_vis.wave_speed = 2.0
	g_vis.wave_amplitude = 80.0
	g_vis.wave_freq = 4.0
	g_vis.max_particles = 150
	g_vis.particles = make([dynamic]Wave_Particle, 0, g_vis.max_particles)
	g_vis.color = im.Vec4{0.2, 0.8, 1.0, 1.0}
	g_vis.last_time = time.now()
	g_vis.audio_reactivity = 0.7
	g_vis.audio_sensitivity = 1.5
}

update_visualizer :: proc(audio_state: ^audio.AudioState, dt: f32, canvas_size: im.Vec2) {
	g_vis.wave_time += g_vis.wave_speed * dt

	// Use audio data to influence the wave
	audio_influence: f32 = 0.0
	if len(audio_state.fft) > 0 {
		// Get average of low frequencies (bass)
		bass := f32(0)
		bass_count := min(10, len(audio_state.fft))
		for i in 0 ..< bass_count {
			bass += audio_state.fft[i]
		}
		bass /= f32(bass_count)
		audio_influence = bass * g_vis.audio_sensitivity * g_vis.audio_reactivity
	}

	// Particle update
	for i := len(g_vis.particles) - 1; i >= 0; i -= 1 {
		p := &g_vis.particles[i]
		p.life -= dt
		if p.life <= 0 {
			ordered_remove(&g_vis.particles, i)
		} else {
			// Make particles react to audio
			p.velocity.y += (20.0 + 50.0 * audio_influence) * dt
			p.pos.x += p.velocity.x * dt
			p.pos.y += p.velocity.y * dt
			p.color.w = p.life / 2.0

			// Make particle size pulse with audio
			if audio_influence > 0.1 {
				p.size = math.lerp(p.size, f32(5.0 * (1.0 + audio_influence)), f32(0.1))
			}
		}
	}

	// Spawn particles along wave - more when audio is loud
	spawn_intensity: f32 = (audio_state.rms * 0.4 + audio_state.bass * 0.6) * 1.5
	spawn_count := int(clamp(math.floor(spawn_intensity * 30), 5, 60))
	if audio_state.rms > 0.2 {
		spawn_count += int(10.0 * audio_state.rms)
	}

	if len(g_vis.particles) < g_vis.max_particles {
		for i in 0 ..< spawn_count {
			x := rand.float32() * canvas_size.x
			spawn_y := canvas_size.y * 0.25 + rand.float32() * canvas_size.y * 0.5
			// base_y := canvas_size.y / 2
			t := x / canvas_size.x

			// Use FFT to get frequency-based kick
			fft_index := int(t * 512)
			fft_kick := fft_index < len(audio_state.fft) ? audio_state.fft[fft_index] : 0.0


			audio_kick := fft_kick * 80.0

			// More variation in angle
			// angle := (rand.float32() - 0.5) * math.TAU * 0.5
			// speed := 30.0 + fft_kick * 150.0


			angle := (rand.float32() - 0.5) * math.TAU // full circle
			speed := 100.0 + fft_kick * 300.0

			velocity := im.Vec2 {
				math.cos(angle) * speed,
				-math.abs(math.sin(angle) * speed * 1.2), // force upward
			}


			hue := math.mod(g_vis.wave_time * 0.2 + fft_kick * 5.0, 1.0)
			color := hsv_to_rgb(hue, 0.8, 1.0)

			particle := Wave_Particle {
				pos      = im.Vec2{x, spawn_y + audio_kick},
				velocity = velocity,
				color    = color,
				life     = 1.0 + rand.float32() * (1.0 + fft_kick),
				size     = 2.0 + rand.float32() * 4.0 * (1.0 + fft_kick),
			}
			append(&g_vis.particles, particle)
		}
		// for i in 0..<spawn_count {
		//     x := rand.float32() * canvas_size.x
		//     base_y := canvas_size.y/2
		//     wave_y := math.sin(x * 0.01 + g_vis.wave_time) * g_vis.wave_amplitude
		//     audio_y := -audio_influence * 100.0 // make wave jump with bass

		//     particle := Wave_Particle{
		//         pos = im.Vec2{x, base_y + wave_y + audio_y},
		//         velocity = im.Vec2{
		//             (rand.float32() - 0.5) * 30.0 * (1.0 + audio_influence),
		//             (rand.float32() - 0.8) * 30.0 * (1.0 + audio_influence), // more upward
		//         },
		//         color = g_vis.color,
		//         life = 1.5 + rand.float32() * (1.0 + audio_influence),
		//         size = 2.0 + rand.float32() * 3.0 * (1.0 + audio_influence),
		//     }
		//     append(&g_vis.particles, particle)
		// }
	}
}

draw_wave :: proc(
	draw_list: ^im.DrawList,
	audio_state: ^audio.AudioState,
	canvas_pos: im.Vec2,
	canvas_size: im.Vec2,
) {
	points := 512
	NUM_BACKGROUND_WAVES := 4
	prev := im.Vec2{}

	// Get overall influence
	influence :=
		(audio_state.rms * 0.6 + audio_state.wave_amplitude * 0.4 + audio_state.bass * 0.6) *
		g_vis.audio_sensitivity *
		g_vis.audio_reactivity

	// === BACKGROUND WAVES ===
	for wave_idx in 0 ..< NUM_BACKGROUND_WAVES {
		wave_offset := f32(wave_idx)
		band_start := 20 * wave_idx
		band_end := band_start + 30
		fft_sum: f32 = 0
		for j in band_start ..< min(band_end, len(audio_state.fft)) {
			fft_sum += audio_state.fft[j]
		}
		band_energy := fft_sum / f32(max(band_end - band_start, 1))

		freq := g_vis.wave_freq + wave_offset * 1.3
		amp := g_vis.wave_amplitude * (0.3 + band_energy * 1.5)
		phase := g_vis.wave_time + wave_offset * 0.7

		center_y :=
			canvas_pos.y +
			canvas_size.y / 2 +
			math.sin(g_vis.wave_time * 0.5 + wave_offset) * 40.0 * audio_state.bass

		hue := math.mod(0.25 + wave_offset * 0.15 + g_vis.wave_time * 0.04, 1.0)
		fade := 0.08 + 0.1 * (1.0 - f32(wave_idx) / f32(NUM_BACKGROUND_WAVES))
		color := hsv_to_rgb(hue, 0.9, 1.0)
		color.w = fade

		prev = im.Vec2{}
		for i in 0 ..< points {
			t := f32(i) / f32(points - 1)
			x := canvas_pos.x + t * canvas_size.x

			fft_index := int(t * 512)
			fft_val := fft_index < len(audio_state.fft) ? audio_state.fft[fft_index] : 0

			// Wave + FFT shake
			y :=
				center_y +
				math.sin(t * freq * math.TAU + phase) * amp +
				math.sin(t * 15 + g_vis.wave_time * 1.5) * fft_val * 30.0

			if i > 0 {
				im.DrawList_AddLine(
					draw_list,
					prev,
					im.Vec2{x, y},
					im.ColorConvertFloat4ToU32(color),
					1.2,
				)
			}
			prev = im.Vec2{x, y}
		}
	}

	// === FOREGROUND WAVE ===
	prev = im.Vec2{}
	for i in 0 ..< points {
		t := f32(i) / f32(points - 1)
		x := canvas_pos.x + t * canvas_size.x
		y_base := canvas_pos.y + canvas_size.y / 2.0

		// Combine multiple harmonics for richness
		y_wave :=
			math.sin(t * g_vis.wave_freq * math.TAU + g_vis.wave_time) * g_vis.wave_amplitude +
			math.sin(t * g_vis.wave_freq * 3.0 * math.TAU + g_vis.wave_time * 1.2) *
				g_vis.wave_amplitude *
				0.4 +
			math.sin(t * g_vis.wave_freq * 6.5 * math.TAU + g_vis.wave_time * 0.9) *
				g_vis.wave_amplitude *
				0.25

		// High-frequency modulation from FFT
		fft_index := int(t * 512)
		fft_val := fft_index < len(audio_state.fft) ? audio_state.fft[fft_index] : 0
		y_shake := math.sin(t * 40.0 + g_vis.wave_time * 3.5) * fft_val * 50.0

		y := y_base + y_wave + y_shake

		if i > 0 {
			thickness := 2.0 + influence * 3.0
			im.DrawList_AddLine(
				draw_list,
				prev,
				im.Vec2{x, y},
				im.ColorConvertFloat4ToU32(g_vis.color),
				thickness,
			)
		}
		prev = im.Vec2{x, y}
	}
}


render_audio_visualizer :: proc(audio_state: ^audio.AudioState) {
	now := time.now()
	dt := f32(time.duration_seconds(time.since(g_vis.last_time)))
	g_vis.last_time = now
	dt = math.min(dt, 0.033)

	im.SetNextWindowSize({900, 600}, {})
	if im.Begin("Wave Visualizer", nil, {.NoCollapse, .NoTitleBar, .NoMove, .NoResize}) {
		draw_list := im.GetWindowDrawList()
		canvas_pos := im.GetCursorScreenPos()
		canvas_size := im.GetContentRegionAvail()

		update_visualizer(audio_state, dt, canvas_size)

		// Background
		bg := im.Vec4{0.05, 0.05, 0.1, 1.0}
		im.DrawList_AddRectFilled(
			draw_list,
			canvas_pos,
			im.Vec2{canvas_pos.x + canvas_size.x, canvas_pos.y + canvas_size.y},
			im.ColorConvertFloat4ToU32(bg),
		)

		draw_wave(draw_list, audio_state, canvas_pos, canvas_size)
		draw_particles(draw_list)

		im.InvisibleButton("canvas", canvas_size)
		im.End()
	}
}

draw_particles :: proc(draw_list: ^im.DrawList) {
	for p in g_vis.particles {
		im.DrawList_AddCircleFilled(
			draw_list,
			p.pos,
			p.size,
			im.ColorConvertFloat4ToU32(p.color),
			12,
		)
	}
}
