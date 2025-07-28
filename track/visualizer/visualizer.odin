/********************************************************************
 *  super_vis.odin  –  reactive ImGui audio visualizer
 ********************************************************************/
package visualizer

import im "../../odin-imgui"
import audio "../audio_state"
import "core:math"
import "core:math/rand"
import "core:time"
import "core:slice"

/* ---------- config ------------------------------------------------ */
NUM_BANDS         :: 256
HISTORY_LEN       :: 32
PARTICLE_LIMIT    :: 800
ONSET_THRESHOLD   :: 0.12   // tweak for your music
/* ---------- helpers ---------------------------------------------- */
hsv_to_rgb :: proc(h, s, v: f32) -> im.Vec4 {
    c := v * s
    x := c * (1 - math.abs(math.mod(h*6, 2) - 1))
    m := v - c
    if      h < 1/6.0 { return im.Vec4{c+m, x+m,   m, 1} }
    else if h < 2/6.0 { return im.Vec4{x+m, c+m,   m, 1} }
    else if h < 3/6.0 { return im.Vec4{  m, c+m, x+m, 1} }
    else if h < 4/6.0 { return im.Vec4{  m, x+m, c+m, 1} }
    else if h < 5/6.0 { return im.Vec4{x+m,   m, c+m, 1} }
    else               { return im.Vec4{c+m,   m, x+m, 1} }
}

/* ---------- data -------------------------------------------------- */
Particle :: struct {
    pos, vel: im.Vec2,
    color:    im.Vec4,
    life:     f32,
    size:     f32
}

State :: struct {
    history: [HISTORY_LEN][NUM_BANDS]f32,
    hist_idx: int,
    last_time: time.Time,
    bass_prev: f32,
    onset:     bool,
    particles: [dynamic]Particle,
    hue:       f32
}
g: State

init_visualizer :: proc() {
    g.last_time = time.now()
    g.hue = 0
    g.particles = make([dynamic]Particle, 0, PARTICLE_LIMIT)
}

/* ---------- main -------------------------------------------------- */
render_audio_visualizer :: proc(state: ^audio.AudioState, pos, size: im.Vec2) {
    dt := f32(time.duration_seconds(time.since(g.last_time)))
    g.last_time = time.now()
    dt = math.min(dt, 0.033)

    /* ---- update FFT history ---- */
    if len(state.fft) >= NUM_BANDS {
        x := state.fft
        copy(g.history[g.hist_idx][:], state.fft[:NUM_BANDS])
        // g.history[g.hist_idx] = state.fft[:NUM_BANDS]
        g.hist_idx = (g.hist_idx + 1) % HISTORY_LEN
    }

    /* ---- onset detection ---- */
    bass := state.bass
    delta := bass - g.bass_prev
    g.onset = delta > ONSET_THRESHOLD && bass > 0.20
    g.bass_prev = bass

    /* ---- spawn particles ---- */
    if g.onset || len(g.particles) < 10 {
        burst := 5 + int(bass * 40)
        for _ in 0 ..< burst {
            if len(g.particles) >= PARTICLE_LIMIT { break }
            angle := rand.float32() * 2 - 1
            speed := 80 + bass * 300
            p := Particle{
                pos   = {size.x * 0.5, size.y * 0.9},
                vel   = {angle * speed, -speed * 0.8},
                color = hsv_to_rgb(f32(int(g.hue + bass * 2) % 1), 0.9, 1),
                life  = 1.0 + rand.float32() * 1.5,
                size  = 2 + rand.float32() * 6 * (1 + bass),
            }
            append(&g.particles, p)
        }
    }

    /* ---- update particles ---- */
    for i := len(g.particles) - 1; i >= 0; i -= 1 {
        p := &g.particles[i]
        p.life -= dt
        if p.life <= 0 { ordered_remove(&g.particles, i); continue }
        p.pos += p.vel * dt
        p.vel.y += 400 * dt
    }

    /* ---- draw ---- */
    dl := im.GetWindowDrawList()
    bg := im.Vec4{0.05, 0.05, 0.1, 1}
    im.DrawList_AddRectFilled(dl, pos, pos + size,
                              im.ColorConvertFloat4ToU32(bg), 6)

    /* frequency ribbons */
    bar_w := size.x / NUM_BANDS
    for i in 0 ..< NUM_BANDS {
        h :f32= 0.0
        for j in 0 ..< HISTORY_LEN {
            h += g.history[(g.hist_idx - 1 - j + HISTORY_LEN) % HISTORY_LEN][i]
        }
        h = h / HISTORY_LEN
        h *= size.y * 0.8
        hue := math.mod_f32(f32(i)/NUM_BANDS + g.hue, 1)
        col := hsv_to_rgb(hue, 0.8, 0.7 + math.min(h / size.y, 0.3))
        thick :f32= 1 + (g.onset ? 4 : 0)
        im.DrawList_AddRectFilled(dl,
            pos + im.Vec2{bar_w * f32(i), size.y - h},
            pos + im.Vec2{bar_w * f32(i + 1), size.y},
            im.ColorConvertFloat4ToU32(col),
            thick)
    }

    /* particles */
    for p in g.particles {
        col := p.color
        col.w = p.life
        im.DrawList_AddCircleFilled(dl, pos + p.pos, p.size,
                                    im.ColorConvertFloat4ToU32(col))
    }

    g.hue += dt * 0.15
    g.hue = math.mod(g.hue, 1)
}