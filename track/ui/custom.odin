
package ui


import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import image "vendor:stb/image"

import im "../../odin-imgui"
import "../../odin-imgui/imgui_impl_glfw"
import "../../odin-imgui/imgui_impl_opengl3"

import audio "../audio_state"
import "core:math"
import "core:sync"
import "core:thread"
import "core:time"
import gl "vendor:OpenGL"
import "vendor:glfw"
import ma "vendor:miniaudio"

CustomSelectable :: proc(
	label: cstring,
	selected: bool,
	bg_color: u32,
	flags: im.SelectableFlags,
	size: im.Vec2,
	padding: im.Vec2,
) -> bool {
	draw_list := im.GetWindowDrawList()
	pos := im.GetCursorScreenPos()
	im.DrawList_ChannelsSplit(draw_list, 2)

	// === Padding Setup ===
	// padding := im.Vec2{50, 10} // {horizontal, vertical}
	rounding: f32 = 6.0

	// === Compute full padded size ===
	full_size := im.Vec2{size.x + padding.x * 2, size.y + padding.y * 2}

	// === Input area ===
	im.DrawList_ChannelsSetCurrent(draw_list, 1)
	im.InvisibleButton(label, full_size)
	is_hovered := im.IsItemHovered()
	is_clicked := im.IsItemClicked()

	// === Background draw ===
	im.DrawList_ChannelsSetCurrent(draw_list, 0)
	min := pos
	max := pos + full_size

	color := bg_color
	if bg_color == 1 {
		if selected {
			color = color_vec4_to_u32({0.6, 0.1, 0.4, 0.25})
		} else if is_hovered {
			color = color_vec4_to_u32({0.6, 0.1, 0.4, 0.25})
		} else {
			color = color_vec4_to_u32({0.2, 0.2, 0.2, 0.1})
		}

	} else {
		if selected {
			color = color_vec4_to_u32({0.8, 0.2, 0.6, 0.35})
		} else if is_hovered {
			color = color_vec4_to_u32({0.6, 0.1, 0.4, 0.25})
		} else {
			color = color_vec4_to_u32({0.5, 0.0, 0.3, 0.15})
		}
	}

	im.DrawList_AddRectFilled(draw_list, min, max, color, rounding)

	// === Draw text centered within the padded area ===
	text_size := im.CalcTextSize(label, nil, false, -1.0)
	text_pos := im.Vec2{pos.x + padding.x, pos.y + padding.y + (size.y - text_size.y) / 2.0}
	im.DrawList_AddText(draw_list, text_pos, color_vec4_to_u32({1, 1, 1, 1}), label)

	im.DrawList_ChannelsMerge(draw_list)
	return is_clicked
}

CustomButton :: proc(
	label: cstring,
	flags: im.SelectableFlags,
	size: im.Vec2,
	padding: im.Vec2,
) -> bool {
	draw_list := im.GetWindowDrawList()
	pos := im.GetCursorScreenPos()
	im.DrawList_ChannelsSplit(draw_list, 2)

	// === Padding Setup ===
	// padding := im.Vec2{50, 10} // {horizontal, vertical}
	rounding: f32 = 6.0

	// === Compute full padded size ===
	full_size := im.Vec2{size.x + padding.x * 2, size.y + padding.y * 2}

	// === Input area ===
	im.DrawList_ChannelsSetCurrent(draw_list, 1)
	im.InvisibleButton(label, full_size)
	is_hovered := im.IsItemHovered()
	is_clicked := im.IsItemClicked()

	// === Background draw ===
	im.DrawList_ChannelsSetCurrent(draw_list, 0)
	min := pos
	max := pos + full_size

	color: u32

	if is_hovered {
		color = color_vec4_to_u32({0.6, 0.1, 0.4, 0.25})
	} else {
		color = color_vec4_to_u32({0.5, 0.0, 0.3, 0.15})
	}


	im.DrawList_AddRectFilled(draw_list, min, max, color, rounding)

	// === Draw text centered within the padded area ===
	text_size := im.CalcTextSize(label, nil, false, -1.0)
	text_pos := im.Vec2{pos.x + padding.x, pos.y + padding.y + (size.y - text_size.y) / 2.0}
	im.DrawList_AddText(draw_list, text_pos, color_vec4_to_u32({1, 1, 1, 1}), label)

	im.DrawList_ChannelsMerge(draw_list)
	return is_clicked
}


CustomSearchBar :: proc(id: string, buffer: ^[256]u8, size: im.Vec2) -> bool {
	rounding: f32 = 6.0
	padding := im.Vec2{10, 6}
	bg_color := color_vec4_to_u32({0.2, 0.0, 0.2, 0.25}) // background
	border_color := color_vec4_to_u32({1.0, 0.4, 1.0, 0.35})
	text_color := color_vec4_to_u32({1.0, 1.0, 1.0, 1.0})

	pos := im.GetCursorScreenPos()
	draw_list := im.GetWindowDrawList()

	// Draw background
	min := pos
	max := pos + size
	im.DrawList_AddRectFilled(draw_list, min, max, bg_color, rounding)
	im.DrawList_AddRect(draw_list, min, max, border_color, rounding)

	// Set up invisible input
	im.SetCursorScreenPos(pos + padding)
	im.PushStyleVar(im.StyleVar.FrameBorderSize, 0)
	im.PushStyleVar(im.StyleVar.FrameRounding, rounding)
	im.PushStyleColor(.FrameBg, color_vec4_to_u32({0, 0, 0, 0})) // fully transparent
	im.PushStyleColor(.Border, 0)
	im.PushStyleColor(.Text, text_color)
	cstring_buffer := cast(cstring)(&buffer[0])
	flags: im.InputTextFlags
	flags += {
		im.InputTextFlags.EnterReturnsTrue,
		im.InputTextFlags.AutoSelectAll,
		im.InputTextFlags.NoHorizontalScroll,
	}
	// flags.set(.AutoSelectAll)
	// flags.set(.NoHorizontalScroll)
	edited := im.InputTextWithHint(text(id), "Search...", cstring_buffer, 100, flags)

	im.PopStyleColor(3)
	im.PopStyleVar(2)

	return edited
}


clamp :: proc(value, min_value, max_value: f32) -> f32 {
	if value < min_value {
		return min_value
	}
	if value > max_value {
		return max_value
	}
	return value
}

audio_progress_bar_and_volume_bar :: proc(audio_state: ^audio.AudioState) {
	total_width := im.GetContentRegionAvail().x
	spacing := im.GetStyle().ItemSpacing.x

	progress_width := (total_width - spacing) * 6.0 / 8.0
	volume_width := (total_width - spacing) * 2.0 / 8.0
	height: f32 = 10.0

	// ========== AUDIO PROGRESS ==========
	im.PushID("audio_seekbar")

	value := audio_state.duration > 0 ? audio_state.current_time / audio_state.duration : 0.0
	slider_size := im.Vec2{progress_width, height}
	slider_pos := im.GetCursorScreenPos()

	im.InvisibleButton("##seek_slider", slider_size)

	if im.IsItemActive() {
		mouse := im.GetIO().MousePos
		new_time := ((mouse.x - slider_pos.x) / progress_width) * audio_state.duration
		audio_state.current_time = math.clamp(new_time, 0.0, audio_state.duration)
	}
	hovered := im.IsItemHovered()
	active := im.IsItemActive()

	draw_list := im.GetWindowDrawList()
	p0 := slider_pos
	p1 := im.Vec2{p0.x + progress_width, p0.y + height}
	handle_x := p0.x + progress_width * value
	handle_radius: f32 = active || hovered ? 7.0 : 5.0

	// col_bg := color_vec4_to_u32({0.5, 0.1, 0.1, 1})
	// // col_bg :=    im.GetColorU32(.FrameBg)
	// col_fg := color_vec4_to_u32({0.8, 0.25, 0.25, 1})
	// col_border := im.GetColorU32(.Border)
	// // col_handle := im.GetColorU32(.Text)
	// col_handle := color_vec4_to_u32({0.9, 0.3, 0.3, 1})


	col_bg := color_vec4_to_u32({0.2, 0.0, 0.2, 0.25}) // dark purple base
	col_fg := color_vec4_to_u32({0.6, 0.1, 0.6, 0.35}) // progress fill (hover pink)
	col_handle := color_vec4_to_u32({0.9, 0.3, 0.9, 0.55}) // draggable circle (bright magenta)
	col_border := color_vec4_to_u32({1.0, 0.4, 1.0, 0.35}) // subtle purple outline


	rounding: f32 = 2.0

	im.DrawList_AddRectFilled(draw_list, p0, p1, col_bg, rounding)
	im.DrawList_AddRectFilled(draw_list, p0, im.Vec2{handle_x, p1.y}, col_fg, rounding)
	im.DrawList_AddRect(draw_list, p0, p1, col_border, rounding)

	center := im.Vec2{handle_x, p0.y + height / 2}
	im.DrawList_AddCircleFilled(draw_list, center, handle_radius, col_handle)

	label := strings.clone_to_cstring(
		fmt.tprintf(
			"%.0f:%.0f / %.0f:%.0f",
			math.floor(audio_state.current_time / 60),
			math.mod(audio_state.current_time, 60),
			math.floor(audio_state.duration / 60),
			math.mod(audio_state.duration, 60),
		),
	)
	text_size := im.CalcTextSize(label)
	text_pos := im.Vec2{(p0.x + p1.x - text_size.x) / 2, p1.y + 4}
	im.DrawList_AddText(draw_list, text_pos, col_handle, label)

	if im.IsItemDeactivatedAfterEdit() || im.IsMouseReleased(.Left) {
		audio.seek_to_position(audio_state, audio_state.current_time)
	}
	im.PopID()

	// ========== VOLUME SLIDER ==========
	im.SameLine()
	im.PushID("volume_slider")

	volume_slider_pos := im.GetCursorScreenPos()
	volume_slider_size := im.Vec2{volume_width, height}

	im.InvisibleButton("##volume_slider", volume_slider_size)

	if im.IsItemActive() {
		mouse := im.GetIO().MousePos
		new_volume := (mouse.x - volume_slider_pos.x) / volume_width
		audio_state.volume = math.clamp(new_volume, 0.0, 1.0)
	}
	vol_hovered := im.IsItemHovered()
	vol_active := im.IsItemActive()

	vol_draw_list := im.GetWindowDrawList()
	v_p0 := volume_slider_pos
	v_p1 := im.Vec2{v_p0.x + volume_width, v_p0.y + height}
	v_handle_x := v_p0.x + volume_width * audio_state.volume
	v_handle_radius: f32 = vol_active || vol_hovered ? 7.0 : 5.0

	im.DrawList_AddRectFilled(vol_draw_list, v_p0, v_p1, col_bg, rounding)
	im.DrawList_AddRectFilled(vol_draw_list, v_p0, im.Vec2{v_handle_x, v_p1.y}, col_fg, rounding)
	im.DrawList_AddRect(vol_draw_list, v_p0, v_p1, col_border, rounding)

	vol_center := im.Vec2{v_handle_x, v_p0.y + height / 2}
	im.DrawList_AddCircleFilled(vol_draw_list, vol_center, v_handle_radius, col_handle)

	if im.IsItemDeactivatedAfterEdit() || im.IsMouseReleased(.Left) {
		audio.set_volume(audio_state, audio_state.volume)
	}

	im.PopID()
}
