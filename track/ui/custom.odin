
package ui


import app "../app"
import media "../media"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import image "vendor:stb/image"

import im "../../odin-imgui"

import audio "../audio_state"
import "core:math"
import "core:sync"
import "core:thread"
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
		color = color_vec4_to_u32({0.52, 0.5, 0.6, 0.25})
	} else if is_hovered {
		color = color_vec4_to_u32({0.52, 0.5, 0.6, 0.25})
	}


	im.DrawList_AddRectFilled(draw_list, min, max, color, rounding)
	im.DrawList_AddRectFilled(draw_list, min, max, color, rounding)
	icon_font_color := [4]f32{0.8, 0.8, 0.8, 0.8}
	im.PushFont(app.g_app.search_item_icon_font)
	font_size: im.Vec2
	font_pos: im.Vec2

	font_size = im.CalcTextSize(ICON_BUTTON_IS_ALBUM, nil, false, -1.0)
	font_pos = im.Vec2{pos.x + padding.x, pos.y + padding.y + (size.y - font_size.y) / 2.0}
	im.DrawList_AddText(
		draw_list,
		font_pos,
		color_vec4_to_u32(icon_font_color),
		ICON_BUTTON_PLAYLIST,
	)

	im.PopFont()
	// === Draw text centered within the padded area ===
	text_padding_x :: 20
	text_size := im.CalcTextSize(label, nil, false, -1.0)
	text_pos := im.Vec2 {
		pos.x + text_padding_x + font_size.x,
		pos.y + padding.y + (size.y - text_size.y) / 2.0,
	}
	im.DrawList_AddText(draw_list, text_pos, color_vec4_to_u32({1, 1, 1, 1}), label)

	im.DrawList_ChannelsMerge(draw_list)
	return is_clicked
}
draw_selectable_search_item :: proc(
	label: cstring,
	selected: bool,
	flags: im.SelectableFlags,
	size: im.Vec2,
	padding: im.Vec2,
	media_kind: media.MediaKind,
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
		color = color_vec4_to_u32(im.Vec4{0.2, 0.8, 1.0, 0.25})
	} else if is_hovered {
		color = color_vec4_to_u32(im.Vec4{0.2, 0.8, 1.0, 0.12})
	}


	im.DrawList_AddRectFilled(draw_list, min, max, color, rounding)
	icon_font_color := [4]f32{0.8, 0.8, 0.8, 0.8}
	im.PushFont(app.g_app.search_item_icon_font)
	font_size: im.Vec2
	font_pos: im.Vec2
	switch media_kind {
	case .Album:
		font_size = im.CalcTextSize(ICON_BUTTON_IS_ALBUM, nil, false, -1.0)
		font_pos = im.Vec2{pos.x + padding.x, pos.y + padding.y + (size.y - font_size.y) / 2.0}

		im.DrawList_AddText(
			draw_list,
			font_pos,
			color_vec4_to_u32(icon_font_color),
			ICON_BUTTON_IS_ALBUM,
		)
	case .Artist:
		font_size = im.CalcTextSize(ICON_BUTTON_IS_ARTIST, nil, false, -1.0)
		font_pos = im.Vec2{pos.x + padding.x, pos.y + padding.y + (size.y - font_size.y) / 2.0}

		im.DrawList_AddText(
			draw_list,
			font_pos,
			color_vec4_to_u32(icon_font_color),
			ICON_BUTTON_IS_ARTIST,
		)
	case .Title:
		font_size = im.CalcTextSize(ICON_BUTTON_IS_SONG, nil, false, -1.0)
		font_pos = im.Vec2{pos.x + padding.x, pos.y + padding.y + (size.y - font_size.y) / 2.0}

		im.DrawList_AddText(
			draw_list,
			font_pos,
			color_vec4_to_u32(icon_font_color),
			ICON_BUTTON_IS_SONG,
		)
	}

	im.PopFont()
	// === Draw text centered within the padded area ===
	text_padding_x :: 20
	text_size := im.CalcTextSize(label, nil, false, -1.0)
	text_pos := im.Vec2 {
		pos.x + text_padding_x + font_size.x,
		pos.y + padding.y + (size.y - text_size.y) / 2.0,
	}
	im.DrawList_AddText(draw_list, text_pos, color_vec4_to_u32({1, 1, 1, 1}), label)

	im.DrawList_ChannelsMerge(draw_list)
	return is_clicked
}


// draw debug window
draw_debug_window :: proc(state: ^app.AppState) {
	// Create a debug window
	im.Begin("Debug Window", nil, im.WindowFlags{})
	defer im.End()

	// Display AppState fields
	im.Text("AppState Debug Info")
	im.Separator()

	// Basic fields
	im.Text(text(fmt.tprintf("is_searching: %v", state.is_searching)))
	im.Text(text(fmt.tprintf("search_result_index: %d", state.search_result_index)))
	im.Text(text(fmt.tprintf("play_queue_index: %d", state.play_queue_index)))
	im.Text(text(fmt.tprintf("ui_view: %v", state.ui_view)))
	im.Text(text(fmt.tprintf("last_view: %v", state.last_view)))
	im.Text(text(fmt.tprintf("has_right_clicked: %v", state.has_right_clicked)))
	im.Text(
		text(
			fmt.tprintf(
				"last_mouse_click_pos: [%.2f, %.2f]",
				state.last_mouse_click_pos.x,
				state.last_mouse_click_pos.y,
			),
		),
	)
	im.Text(text(fmt.tprintf("ui_right_click_ctx: %v", state.ui_right_click_ctx)))
	im.Text(text(fmt.tprintf("ui_layer_interact: %v", state.ui_layer_interact)))
	// im.Text("Last clicked rectangle: %s", last_clicked_index >= 0 ? fmt.tprintf("Rectangle %d", last_clicked_index) : "None")

	// Display all_songs
	// if im.TreeNode("all_songs") {
	//     for song, i in state.all_songs {
	//         if im.TreeNode(fmt.tprintf("Song %d", i)) {
	//             im.Text("Title: %s", song.title)
	//             im.Text("Artist: %s", song.artist)
	//             im.Text("Album: %s", song.album)
	//             im.Text("Genre: %s", song.genre)
	//             im.Text("Year: %d", song.year)
	//             im.TreePop()
	//         }
	//     }
	//     im.TreePop()
	// }

	// Display clicked_playlist_entries
	// if im.TreeNode("clicked_playlist_entries") {
	//     for song, i in state.clicked_playlist_entries {
	//         if im.TreeNode(fmt.tprintf("Song %d", i)) {
	//             im.Text("Title: %s", song.title)
	//             im.Text("Artist: %s", song.artist)
	//             im.Text("Album: %s", song.album)
	//             im.Text("Genre: %s", song.genre)
	//             im.Text("Year: %d", song.year)
	//             im.TreePop()
	//         }
	//     }
	//     im.TreePop()
	// }

	// Display clicked_search_results_entries
	// if im.TreeNode("clicked_search_results_entries") {
	//     for song, i in state.clicked_search_results_entries {
	//         if im.TreeNode(fmt.tprintf("Song %d", i)) {
	//             im.Text("Title: %s", song.title)
	//             im.Text("Artist: %s", song.artist)
	//             im.Text("Album: %s", song.album)
	//             im.Text("Genre: %s", song.genre)
	//             im.Text("Year: %d", song.year)
	//             im.TreePop()
	//         }
	//     }
	//     im.TreePop()
	// }

	// Display play_queue
	// if im.TreeNode("play_queue") {
	//     for song, i in state.play_queue {
	//         if im.TreeNode(fmt.tprintf("Song %d", i)) {
	//             im.Text("Title: %s", song.title)
	//             im.Text("Artist: %s", song.artist)
	//             im.Text("Album: %s", song.album)
	//             im.Text("Genre: %s", song.genre)
	//             im.Text("Year: %d", song.year)
	//             im.TreePop()
	//         }
	//     }
	//     im.TreePop()
	// }

	// Display library
	// if im.TreeNode("library") {
	//     if im.TreeNode("songs") {
	//         for song, i in state.library.songs {
	//             if im.TreeNode(fmt.tprintf("Song %d", i)) {
	//                 im.Text("Title: %s", song.title)
	//                 im.Text("Artist: %s", song.artist)
	//                 im.Text("Album: %s", song.album)
	//                 im.Text("Genre: %s", song.genre)
	//                 im.Text("Year: %d", song.year)
	//                 im.TreePop()
	//             }
	//         }
	//         im.TreePop()
	//     }
	//     im.TreePop()
	// }

}


// draw music information bar
draw_information_bar :: proc(
	file_entry: media.Song,
	selected: bool,
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
	if app.g_app.ui_layer_interact == .Base_Layer {
		if selected {
			color = color_vec4_to_u32(im.Vec4{0.1, 0.12, 0.2, 0.9}) // Cyan-blue w/ low alpha
		} else if is_hovered {
			color = color_vec4_to_u32({0.52, 0.5, 0.6, 0.25})
		} else {
			color = color_vec4_to_u32(im.Vec4{0.1, 0.12, 0.2, 0.9}) // Very dark blue-gray background
		}
	}


	im.DrawList_AddRectFilled(draw_list, min, max, color, rounding)

	// === Calculate section widths ===
	content_width := size.x
	section_widths := [5]f32 {
		content_width * 0.30, // Title - 30%
		content_width * 0.25, // Artist - 25%
		content_width * 0.15, // Album - 15%
		content_width * 0.15, // Year - 15%
		content_width * 0.10, // Duration - 10%
	}

	// === Draw text in sections ===\

	texts := [5]cstring {
		file_entry.metadata.title,
		file_entry.metadata.artist,
		file_entry.metadata.album,
		file_entry.metadata.year,
		file_entry.metadata.genre,
	}

	text_color := color_vec4_to_u32({1, 1, 1, 1})
	current_x := pos.x + padding.x


	for i in 0 ..< 5 {
		section_width := section_widths[i]
		text := texts[i]

		if text == nil || len(string(text)) == 0 {
			current_x += section_width
			continue
		}
		if i == 0 { 	// Title section: draw play button first, then title
			text := texts[0]
			if text == nil || len(string(text)) == 0 {
				current_x += section_width
				continue
			}

			text_color := color_vec4_to_u32({1, 1, 1, 1})

			im.DrawList_PushClipRect(
				draw_list,
				im.Vec2{current_x, pos.y},
				im.Vec2{current_x + section_width - 5, pos.y + full_size.y},
				true,
			)

			play_label: cstring = "play"
			play_text_size := im.CalcTextSize(play_label, nil, false, section_width)
			play_pos := im.Vec2{current_x, pos.y + padding.y + (size.y - play_text_size.y) / 2.0}

			play_button_id := fmt.ctprintf("##play_button_%s", file_entry.fullpath)

			if is_hovered {
				// Draw play icon
				im.DrawList_AddText(draw_list, play_pos, text_color, play_label)

				// Setup play button over icon
				im.SetCursorScreenPos(play_pos)
				im.InvisibleButton(
					play_button_id,
					im.Vec2{play_text_size.x + 4.0, play_text_size.y + 4.0},
				)

				if im.IsItemHovered() {
					im.SetTooltip("Play song")
				}
				if im.IsItemClicked() {
					fmt.println("Clicked play for: ", file_entry.metadata.title)
				}
			}

			// Now draw the title after the play button (with padding)
			text_title := texts[0]
			title_text_size := im.CalcTextSize(text, nil, false, section_width)
			title_pos := im.Vec2 {
				play_pos.x + play_text_size.x + 8.0, // 8px spacing after icon
				pos.y + padding.y + (size.y - title_text_size.y) / 2.0,
			}

			im.DrawList_AddText(draw_list, title_pos, text_color, text_title)

			im.DrawList_PopClipRect(draw_list)

		} else {
			// Draw remaining sections (artist, album, etc.)
			text := texts[i]
			if text != nil && len(string(text)) > 0 {
				text_size := im.CalcTextSize(text, nil, false, section_width)
				text_pos := im.Vec2{current_x, pos.y + padding.y + (size.y - text_size.y) / 2.0}

				im.DrawList_PushClipRect(
					draw_list,
					im.Vec2{current_x, pos.y},
					im.Vec2{current_x + section_width - 5, pos.y + full_size.y},
					true,
				)
				im.DrawList_AddText(draw_list, text_pos, text_color, text)
				im.DrawList_PopClipRect(draw_list)
			}
		}

		current_x += section_width


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
		color = color_vec4_to_u32({0.52, 0.5, 0.6, 0.25})
	} else {
		color = color_vec4_to_u32({0.52, 0.5, 0.6, 0.25})
	}


	im.DrawList_AddRectFilled(draw_list, min, max, color, rounding)

	// === Draw text centered within the padded area ===
	text_size := im.CalcTextSize(label, nil, false, -1.0)
	text_pos := im.Vec2{pos.x + padding.x, pos.y + padding.y + (size.y - text_size.y) / 2.0}
	im.DrawList_AddText(draw_list, text_pos, color_vec4_to_u32({1, 1, 1, 1}), label)

	im.DrawList_ChannelsMerge(draw_list)
	return is_clicked
}


draw_search_bar :: proc(search_buffer: ^[256]u8, size: im.Vec2) -> bool {
	// draw_search_bar :: proc(id: string, buffer: cstring, size: im.Vec2) -> bool {
	if search_buffer == nil {
		fmt.println("Buffer pointer is nil")
		panic("Buffer pointer is nil")
	}
	search_cstring := transmute(cstring)search_buffer

	rounding: f32 = 6.0
	padding := im.Vec2{3, 8}

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
	// cstring_buffer := cast(cstring)(&buffer[0])
	im.PushItemWidth(input_size.x)
	edited := im.InputTextWithHint(
		"##searching_id",
		"Search songs, albums, artists...",
		// cstring_buffer,
		search_cstring,
		100,
		flags,
	)
	im.PopItemWidth()

	// Cleanup
	im.PopStyleColor(3)
	im.PopStyleVar(2)

	return edited
}

draw_playlist_items :: proc(audio_state: ^audio.AudioState, size: [2]f32) {
	for v, i in app.g_app.clicked_playlist_entries {
		is_selected := app.g_app.play_queue_index == i
		im.BeginGroup()
		im.Spacing()

		if draw_information_bar(v, is_selected, {}, {size.x, 30}, {50, 10}) {
			fmt.printf("[TRACK::App] Playing: %s\n", v.name)
			clear(&app.g_app.play_queue)
			append(&app.g_app.play_queue, ..app.g_app.clicked_playlist_entries[:])
			app.g_app.play_queue_index = i
			audio.update_path(audio_state, v.fullpath)
			audio.create_audio_play_thread(audio_state)
		}

		im.EndGroup()
	}
}

draw_search_results_clicked :: proc(audio_state: ^audio.AudioState, size: [2]f32) {
	using app
	for v, i in g_app.clicked_search_results_entries {
		is_selected := g_app.play_queue_index == i
		im.BeginGroup()
		im.Spacing()

		if draw_information_bar(v, is_selected, {}, {size.x, 30}, {50, 10}) {
			// if the song is alread playing do not start over
			if len(g_app.play_queue) > 0 &&
			   i < len(g_app.play_queue) &&
			   g_app.play_queue[g_app.play_queue_index].name == g_app.play_queue[i].name {
			} else {
				fmt.printf("[TRACK::Search result] Playing: %s\n", v.name)
				clear(&g_app.play_queue)
				append(&g_app.play_queue, ..(app.g_app.clicked_search_results_entries)[:])
				g_app.play_queue_index = i
				audio.update_path(audio_state, v.fullpath)
				audio.create_audio_play_thread(audio_state)
			}
		}

		im.EndGroup()
	}
}

draw_all_songs :: proc(
	all_songs: ^[dynamic]media.Song,
	audio_state: ^audio.AudioState,
	size: [2]f32,
) {
	using app

	for v, i in all_songs {
		is_selected := g_app.play_queue_index == i
		im.BeginGroup()
		im.Spacing()

		if draw_information_bar(v, is_selected, {}, {size.x, 30}, {50, 10}) {
			fmt.println("[TRACK::App] Started new play queue")
			fmt.printf("[TRACK::App] Playing: %s\n", v.name)
			clear(&g_app.play_queue)
			append(&g_app.play_queue, ..all_songs[:])

			g_app.play_queue_index = i

			audio.update_path(audio_state, v.fullpath)
			audio.create_audio_play_thread(audio_state)
		}


		if g_app.has_right_clicked {
			draw_option_item("Play Next", g_app.ui_right_click_ctx, g_app.last_mouse_click_pos)
			draw_option_item(
				"Show Artist",
				g_app.ui_right_click_ctx,
				g_app.last_mouse_click_pos + {0, 30},
			)
			draw_option_item(
				"Show Album",
				g_app.ui_right_click_ctx,
				g_app.last_mouse_click_pos + {0, 60},
			)
		}

		im.EndGroup()
	}
}


draw_custom_header :: proc(title: cstring, width: f32) {
	header_height: f32 = 60.0
	rounding: f32 = 8.0

	bg_color := color_vec4_to_u32({0.1, 0.12, 0.2, 0.9}) // deep background
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
	#partial switch app.g_app.ui_view {
	case .Visualizer:
		im.DrawList_AddCircleFilled(draw_list, center, radius, icon_color)
	case:
		im.DrawList_AddCircle(draw_list, center, radius, icon_color, 16, 1.5)

	}

	if im.IsItemClicked() {
		if app.g_app.ui_view != .Visualizer {
			app.g_app.ui_view = .Visualizer
		} else {
			app.g_app.ui_view = app.g_app.last_view
		}
	}
}

draw_audio_progress_bar :: proc(audio_state: ^audio.AudioState) {
	left_margin: f32 = 40.0
	right_margin: f32 = 40.0
	spacing := im.GetStyle().ItemSpacing.x

	avail_width := im.GetContentRegionAvail().x
	usable_width := avail_width - left_margin - right_margin
	height: f32 = 10.0

	min_cur := int(math.floor(audio_state.current_time / 60))
	sec_cur := int(math.floor(math.mod(audio_state.current_time, 60)))
	min_dur := int(math.floor(audio_state.duration / 60))
	sec_dur := int(math.floor(math.mod(audio_state.duration, 60)))

	// label memory should be freed
	label := strings.clone_to_cstring(
		fmt.tprintf("%d:%02d / %d:%02d", min_cur, sec_cur, min_dur, sec_dur),
		app.g_app.arena_allocator,
	)
	text_size := im.CalcTextSize(label)
	progress_width := usable_width - spacing - text_size.x

	im.PushID("audio_seekbar")

	value := audio_state.duration > 0 ? audio_state.current_time / audio_state.duration : 0.0
	slider_size := im.Vec2{progress_width, height}

	slider_pos := im.GetCursorScreenPos()
	slider_pos.x += left_margin

	im.SetCursorScreenPos(slider_pos)
	im.InvisibleButton("##seek_slider", slider_size)


	if im.IsItemActive() || (im.IsItemHovered() && im.IsMouseClicked(.Left)) {
		mouse := im.GetIO().MousePos
		new_time := ((mouse.x - slider_pos.x) / progress_width) * audio_state.duration
		audio_state.current_time = math.clamp(new_time, 0.0, audio_state.duration)

		// If this was a click (not drag), seek immediately
		if im.IsMouseClicked(.Left) && !im.IsMouseDragging(.Left) {
			audio.seek_to_position(audio_state, audio_state.current_time)
		}
	}

	// When user releases mouse after dragging, seek to final position
	if im.IsItemDeactivatedAfterEdit() {
		audio.seek_to_position(audio_state, audio_state.current_time)
		fmt.println("Seeked to position:", audio_state.current_time)
	}

	hovered := im.IsItemHovered()
	active := im.IsItemActive()

	draw_list := im.GetWindowDrawList()
	p0 := slider_pos
	p1 := im.Vec2{p0.x + progress_width, p0.y + height}
	handle_x := p0.x + progress_width * value
	handle_radius: f32 = active || hovered ? 12.0 : 10.0

	col_bg := color_vec4_to_u32({0.1, 0.2, 0.25, 0.4}) // background
	col_fg := color_vec4_to_u32({0.52, 0.5, 0.6, 1}) // progress bar fill
	col_handle := color_vec4_to_u32({0.52, 0.5, 0.6, 1}) // draggable circle
	col_border := color_vec4_to_u32({0.1, 0.2, 0.25, 0.4}) // outer border line
	rounding: f32 = 4.0

	im.DrawList_AddRectFilled(draw_list, p0, p1, col_bg, rounding)
	im.DrawList_AddRectFilled(draw_list, p0, im.Vec2{handle_x, p1.y}, col_fg, rounding)
	im.DrawList_AddRect(draw_list, p0, p1, col_border, rounding)

	center := im.Vec2{handle_x, p0.y + height / 2}
	im.DrawList_AddCircleFilled(draw_list, center, handle_radius, col_handle)

	text_pos := im.Vec2{p0.x + progress_width + spacing, p0.y + (height - text_size.y) / 2}
	im.DrawList_AddText(draw_list, text_pos, color_vec4_to_u32({0.9, 0.95, 1.0, 1.0}), label)


	im.PopID()

}
draw_volume_bar :: proc(audio_state: ^audio.AudioState) {
	left_margin: f32 = 5.0
	right_margin: f32 = 100.0
	spacing := im.GetStyle().ItemSpacing.x

	avail_width := im.GetContentRegionAvail().x
	usable_width := avail_width - left_margin - right_margin
	height: f32 = 10.0


	icon_pos := im.GetCursorScreenPos()

	// ---------------- SLIDER ----------------
	slider_x := icon_pos.x +  spacing
	slider_width := usable_width - spacing

	im.PushID("volume_slider")

	volume_slider_pos := im.GetCursorScreenPos()
	volume_slider_pos.x = slider_x
	volume_slider_pos.y += 5

	volume_slider_size := im.Vec2{slider_width, height}

	im.SetCursorScreenPos(volume_slider_pos)
	im.InvisibleButton("##volume_slider", volume_slider_size)

	if im.IsItemActive() || (im.IsItemHovered() && im.IsMouseClicked(.Left)) {
		mouse := im.GetIO().MousePos
		new_volume := (mouse.x - volume_slider_pos.x) / slider_width
		audio_state.volume = math.clamp(new_volume, 0.0, 1.0)
		audio.set_volume(audio_state, audio_state.volume)
	}

	vol_hovered := im.IsItemHovered()
	vol_active := im.IsItemActive()

	vol_draw_list := im.GetWindowDrawList()
	v_p0 := volume_slider_pos
	v_p1 := im.Vec2{v_p0.x + slider_width, v_p0.y + height}
	v_handle_x := v_p0.x + slider_width * audio_state.volume
	v_handle_radius: f32
	if vol_active || vol_hovered {v_handle_radius = 7.0} else {v_handle_radius = 5.0}
	col_bg := color_vec4_to_u32({0.1, 0.2, 0.25, 0.4})
	col_fg := color_vec4_to_u32({0.52, 0.5, 0.6, 1})
	col_handle := color_vec4_to_u32({0.52, 0.5, 0.6, 1})
	col_border := color_vec4_to_u32({0.1, 0.2, 0.25, 0.4})
	rounding: f32 = 4.0

	im.DrawList_AddRectFilled(vol_draw_list, v_p0, v_p1, col_bg, rounding)
	im.DrawList_AddRectFilled(vol_draw_list, v_p0, im.Vec2{v_handle_x, v_p1.y}, col_fg, rounding)
	im.DrawList_AddRect(vol_draw_list, v_p0, v_p1, col_border, rounding)

	vol_center := im.Vec2{v_handle_x, v_p0.y + height / 2}
	im.DrawList_AddCircleFilled(vol_draw_list, vol_center, v_handle_radius, col_handle)

	im.PopID()
}


// draw right click options bar item
draw_option_item :: proc(
	label: cstring,
	click_context: app.UI_Right_Click_Context,
	mouse_pos: im.Vec2,
) {
	container_width: f32 : 150
	container_height: f32 : 30
	rounding :: 1.0
	draw_list := im.GetForegroundDrawList()
	bottom_right := im.Vec2{mouse_pos.x + container_width, mouse_pos.y + container_height}
	padding :: 6
	size: [2]f32 = {container_width, container_height}

	color: u32

	border_color := color_vec4_to_u32({0.2, 0.22, 0.1, 0.9})
	is_hovered := im.IsMouseHoveringRect(mouse_pos, bottom_right)
	if is_hovered {
		color = color_vec4_to_u32({0.1, 0.12, 0.3, 1})
	} else {
		color = color_vec4_to_u32({0.3, 12, 0.2, 0.9})
	}


	im.DrawList_AddRectFilled(draw_list, mouse_pos, bottom_right, color, rounding, {})
	im.DrawList_AddRect(draw_list, mouse_pos, bottom_right, border_color, rounding)
	text_size := im.CalcTextSize(label)
	text_pos := mouse_pos + [2]f32{20, container_height / 2} - text_size.y / 2
	text_color := color_vec4_to_u32({1.0, 1.0, 1.0, 1.0})
	im.DrawList_AddText(draw_list, text_pos, text_color, label)
}
