package ui

import "core:sync"
import im "../../odin-imgui"
import "../media"
import audio "../audio_state"

set_global_style :: proc() {
	// global styles
	im.PushStyleColor(im.Col.ScrollbarBg, im.ColorConvertFloat4ToU32({0.10, 0.12, 0.18, 0.25}))
	im.PushStyleColor(im.Col.ScrollbarGrab, im.ColorConvertFloat4ToU32({0.52, 0.5, 0.6, 0.25}))
	im.PushStyleColor(
		im.Col.ScrollbarGrabHovered,
		im.ColorConvertFloat4ToU32({0.52, 0.5, 0.6, 0.6}),
	)
	im.PushStyleColor(
		im.Col.ScrollbarGrabActive,
		im.ColorConvertFloat4ToU32({0.52, 0.5, 0.6, 0.8}),
	)
}


render_ui :: proc(library: ^media.MediaLibrary, audio_state: ^audio.AudioState) {
	io := im.GetIO()
	screen_w := io.DisplaySize.x
	screen_h := io.DisplaySize.y
	third_w := screen_w / 4
	third_h := screen_h / 6
	top_h := screen_h - third_h // top 2/3 of height
	right_w := screen_w - third_w // right 2/3 of width


	// ==================== Top Left ====================
	im.SetNextWindowPos(im.Vec2{0, 0})
	im.SetNextWindowSize(im.Vec2{third_w, top_h})

	style := im.GetStyle()
	style.ChildRounding = 10
	left_panel_window_size := im.Vec2{third_w, top_h}
	sync.mutex_lock(&library.playlists_mutex)
	if library.playlists_done {
		top_left_panel(library,audio_state, left_panel_window_size)
	}
	sync.mutex_unlock(&library.playlists_mutex)

	// ==================== Top Right ==================== 
	sync.mutex_lock(&library.playlists_mutex)
	right_panel_window_position := im.Vec2{third_w, 0}
	right_panel_window_size := im.Vec2{right_w, top_h}
	if library.songs_done {
		top_right_panel(
			library,
			audio_state,
			right_panel_window_position,
			right_panel_window_size,
		)
	}
	sync.mutex_unlock(&library.playlists_mutex)

	// // ==================== Bottom ====================
	bottom_panel(library,audio_state, top_h, screen_w, third_h)

}
