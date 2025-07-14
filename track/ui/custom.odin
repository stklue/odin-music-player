
package ui


import app "../app"
import common "../common"
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

draw_item_selectable :: proc(
	label: cstring,
	selected: bool,
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

	if selected {
		color = color_vec4_to_u32(im.Vec4{0.2, 0.8, 1.0, 0.25}) // Cyan-blue w/ low alpha
	} else if is_hovered {
		color = color_vec4_to_u32(im.Vec4{0.2, 0.8, 1.0, 0.12}) // Softer cyan-blue
	}


	im.DrawList_AddRectFilled(draw_list, min, max, color, rounding)

	// === Draw text centered within the padded area ===
	text_size := im.CalcTextSize(label, nil, false, -1.0)
	text_pos := im.Vec2{pos.x + padding.x, pos.y + padding.y + (size.y - text_size.y) / 2.0}
	im.DrawList_AddText(draw_list, text_pos, color_vec4_to_u32({1, 1, 1, 1}), label)

	im.DrawList_ChannelsMerge(draw_list)
	return is_clicked
}


// draw music information bar
draw_information_bar :: proc(
	file_entry: common.FileEntry,
	selected: bool,
	// bg_color: u32,
	flags: im.SelectableFlags,
	size: im.Vec2,
	padding: im.Vec2,
) -> bool {
	draw_list := im.GetWindowDrawList()
	pos := im.GetCursorScreenPos()
	im.DrawList_ChannelsSplit(draw_list, 2)


	rounding: f32 = 6.0

	// === Compute full padded size ===
	full_size := im.Vec2{size.x + padding.x * 2, size.y + padding.y * 2}

	// === Input area ===
	im.DrawList_ChannelsSetCurrent(draw_list, 1)
	// label := file_entry.fullpath // Use filename as the unique ID
	label := fmt.ctprintf("##track_%s", file_entry.fullpath)

	im.InvisibleButton(label, full_size)
	is_hovered := im.IsItemHovered()
	is_clicked := im.IsItemClicked()

	// === Background draw ===
	im.DrawList_ChannelsSetCurrent(draw_list, 0)
	min := pos
	max := pos + full_size

	color: u32

	if selected {
		color = color_vec4_to_u32(im.Vec4{0.2, 0.8, 1.0, 0.25}) // Cyan-blue w/ low alpha
	} else if is_hovered {
		color = color_vec4_to_u32(im.Vec4{0.2, 0.8, 1.0, 0.12}) // Softer cyan-blue
	} else {
		color = color_vec4_to_u32(im.Vec4{0.1, 0.15, 0.2, 0.6}) // Very dark blue-gray background
	}


	im.DrawList_AddRectFilled(draw_list, min, max, color, rounding)

	// === Calculate section widths ===
	content_width := size.x
	section_widths := [5]f32 {
		// content_width * 0.25,  // Filename - 25%
		content_width * 0.30, // Title - 25%
		content_width * 0.25, // Artist - 20%
		content_width * 0.15, // Album - 15%
		content_width * 0.15, // Year - 10%
		content_width * 0.15, // Duration - 5%
	}

	// === Draw text in sections ===\

	texts := [5]cstring {
		file_entry.metadata.title,
		file_entry.metadata.artist,
		file_entry.metadata.album,
		file_entry.metadata.year,
		file_entry.metadata.genre,
	}

	// fmt.println("Writing name: ", texts)

	text_color := color_vec4_to_u32({1, 1, 1, 1})
	current_x := pos.x + padding.x

	for i in 0 ..< 5 {
		if texts[i] != nil && len(string(texts[i])) > 0 {
			// Calculate text position within this section
			text_size := im.CalcTextSize(texts[i], nil, false, section_widths[i])
			text_pos := im.Vec2{current_x, pos.y + padding.y + (size.y - text_size.y) / 2.0}

			// Clip text to section width
			section_max := im.Vec2 {
				current_x + section_widths[i] - 5, // Small margin between sections
				pos.y + full_size.y,
			}

			im.DrawList_PushClipRect(draw_list, im.Vec2{current_x, pos.y}, section_max, true)
			if selected {
				im.DrawList_AddText(
					draw_list,
					text_pos,
					color_vec4_to_u32(im.Vec4{1.0, 0.6, 0.2, 1.0}), // Warm orange
					texts[i],
				)
			} else {
				im.DrawList_AddText(draw_list, text_pos, text_color, texts[i])
			}

			im.DrawList_PopClipRect(draw_list)
		}

		current_x += section_widths[i]
	}

	im.DrawList_ChannelsMerge(draw_list)

	// delete(title)
	return is_clicked
}

draw_custom_button :: proc(
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
		color = color_vec4_to_u32(im.Vec4{0.2, 0.8, 1.0, 0.12}) // Softer cyan-blue
	} else {
		color = color_vec4_to_u32(im.Vec4{0.2, 0.8, 1.0, 0.25}) // Cyan-blue w/ low alpha
	}


	im.DrawList_AddRectFilled(draw_list, min, max, color, rounding)

	// === Draw text centered within the padded area ===
	text_size := im.CalcTextSize(label, nil, false, -1.0)
	text_pos := im.Vec2{pos.x + padding.x, pos.y + padding.y + (size.y - text_size.y) / 2.0}
	im.DrawList_AddText(draw_list, text_pos, color_vec4_to_u32({1, 1, 1, 1}), label)

	im.DrawList_ChannelsMerge(draw_list)
	return is_clicked
}


draw_search_bar :: proc(id: string, buffer: ^[256]u8, size: im.Vec2) -> bool {
	rounding: f32 = 6.0
	padding := im.Vec2{10, 6}

	bg_color := color_vec4_to_u32({0.10, 0.12, 0.20, 0.75}) // deep bluish background
	border_color := color_vec4_to_u32({0.35, 0.60, 1.00, 0.45}) // light electric blue border
	text_color := color_vec4_to_u32({0.90, 0.95, 1.00, 1.00}) // soft white/blue-tinted text

	draw_list := im.GetWindowDrawList()
	pos := im.GetCursorScreenPos()

	// Outer bounds
	min := pos
	max := pos + size
	im.DrawList_AddRectFilled(draw_list, min, max, bg_color, rounding)
	im.DrawList_AddRect(draw_list, min, max, border_color, rounding)

	// Inner input
	input_pos := pos + padding
	input_size := size - padding * 2
	im.SetCursorScreenPos(input_pos)

	// Style setup
	im.PushStyleVar(im.StyleVar.FrameBorderSize, 0)
	im.PushStyleVar(im.StyleVar.FrameRounding, rounding)
	im.PushStyleColor(.FrameBg, color_vec4_to_u32({0, 0, 0, 0})) // transparent bg
	im.PushStyleColor(.Border, 0)
	im.PushStyleColor(.Text, text_color)

	// Input flags
	flags: im.InputTextFlags
	flags += {
		im.InputTextFlags.EnterReturnsTrue,
		im.InputTextFlags.AutoSelectAll,
		im.InputTextFlags.NoHorizontalScroll,
	}

	// Actual input field
	cstring_buffer := cast(cstring)(&buffer[0])
	edited := im.InputTextWithHint(text(id), "Search...", cstring_buffer, 100, flags)

	// Cleanup
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

draw_custom_header :: proc(title: cstring, width: f32) {
	header_height: f32 = 60.0
	rounding: f32 = 8.0

	bg_color := color_vec4_to_u32({0.05, 0.08, 0.12, 1.0}) // deep background
	text_color := color_vec4_to_u32({0.90, 0.95, 1.00, 1.00}) // soft bluish-white
	btn_bg := color_vec4_to_u32({0.20, 0.25, 0.35, 0.8}) // button normal
	btn_hover := color_vec4_to_u32({0.30, 0.45, 0.65, 0.9}) // button hover
	btn_active := color_vec4_to_u32({0.40, 0.65, 1.00, 1.0}) // button active
	icon_color := color_vec4_to_u32({1, 1, 1, 0.9})

	draw_list := im.GetWindowDrawList()
	p0 := im.GetCursorScreenPos()
	p1 := im.Vec2{p0.x + width, p0.y + header_height}

	// Draw header background
	im.DrawList_AddRectFilled(draw_list, p0, p1, bg_color, rounding)

	// Draw header text (left aligned)
	text_size := im.CalcTextSize(title)
	text_pos := im.Vec2{p0.x + 20.0, p0.y + (header_height - text_size.y) / 2.0}
	im.DrawList_AddText(draw_list, text_pos, text_color, title)

	// Toggle Button (right side of header)
	btn_size := im.Vec2{30, 30}
	btn_pos := im.Vec2 {
		p1.x - btn_size.x - 20.0, // 20px right margin
		p0.y + (header_height - btn_size.y) / 2.0,
	}

	im.SetCursorScreenPos(btn_pos)
	im.InvisibleButton("##header_toggle_btn", btn_size)

	is_hovered := im.IsItemHovered()
	is_active := im.IsItemActive()
	btn_col: u32
	if is_active {
		btn_col = btn_active
	} else if is_hovered {
		btn_col = btn_hover
	} else {
		btn_col = btn_bg
	}
	im.DrawList_AddRectFilled(draw_list, btn_pos, btn_pos + btn_size, btn_col, 6.0)

	// Icon or indicator inside button (simple chevron or circle)
	center := btn_pos + btn_size / 2
	radius: f32 = 6.0
	if app.g_app.show_visualizer {
		im.DrawList_AddCircleFilled(draw_list, center, radius, icon_color)
	} else {
		im.DrawList_AddCircle(draw_list, center, radius, icon_color, 16, 1.5)
	}

	if im.IsItemClicked() {
		app.g_app.show_visualizer = !app.g_app.show_visualizer
	}
}

// TODO: BUG: Clicking any where will udpdate the values
draw_audio_progress_bar_and_volume_bar :: proc(audio_state: ^audio.AudioState) {
	left_margin: f32 = 40.0
	right_margin: f32 = 40.0
	spacing := im.GetStyle().ItemSpacing.x

	total_width := im.GetContentRegionAvail().x - left_margin - right_margin
	progress_width := (total_width - spacing) * 6.0 / 8.0
	volume_width := (total_width - spacing) * 2.0 / 8.0
	height: f32 = 10.0

	im.PushID("audio_seekbar")

	value := audio_state.duration > 0 ? audio_state.current_time / audio_state.duration : 0.0
	slider_size := im.Vec2{progress_width, height}

	slider_pos := im.GetCursorScreenPos()
	slider_pos.x += left_margin // ✅ Add left margin

	im.SetCursorScreenPos(slider_pos)
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

	col_bg := color_vec4_to_u32({0.1, 0.2, 0.25, 0.2}) // background
	col_fg := color_vec4_to_u32({0.2, 0.8, 1.0, 0.35}) // progress bar fill
	col_handle := color_vec4_to_u32({0.2, 0.9, 1.0, 0.75}) // draggable circle
	col_border := color_vec4_to_u32({0.3, 0.9, 1.0, 0.4}) // outer border line
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
	im.DrawList_AddText(draw_list, text_pos, color_vec4_to_u32({0.9, 0.95, 1.0, 1.0}), label)

	if im.IsItemDeactivatedAfterEdit() && im.IsItemHovered() && im.IsItemActive() {
		audio.seek_to_position(audio_state, audio_state.current_time)
		fmt.println("hello world")
	}
	im.PopID()

	// ========== VOLUME SLIDER ==========

	im.SameLine()
	im.PushID("volume_slider")

	volume_slider_pos := im.GetCursorScreenPos()

	volume_slider_size := im.Vec2{volume_width, height}
	im.SetCursorScreenPos(volume_slider_pos)
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
		fmt.println("update volume hello world")

	}

	im.PopID()
}
