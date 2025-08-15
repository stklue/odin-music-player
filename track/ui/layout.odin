package ui

import "core:log"

import im "../../odin-imgui"
import "../../odin-imgui/imgui_impl_glfw"
import "../../odin-imgui/imgui_impl_opengl3"
import media "../media"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import image "vendor:stb/image"

import app "../app"
import audio "../audio_state"
import "base:runtime"
import json "core:encoding/json"
import "core:encoding/xml"
import "core:math"
import "core:path/filepath"
import "core:sync"
import "core:thread"


ICON_BUTTON_PLAY :: "\u25b6"
ICON_BUTTON_NEXT :: "\u23e9"
ICON_BUTTON_PREV :: "\u23ea"
ICON_BUTTON_PAUSE :: "\u23f8"
ICON_BUTTON_STOP :: "\u23f9"
ICON_BUTTON_VOL_OFF :: "\uf026"
ICON_BUTTON_VOL_LOW :: "\uf027"
ICON_BUTTON_VOL_HIGH :: "\uf028"
ICON_BUTTON_REPEAT_ALL :: "\uf363"
ICON_BUTTON_NO_REPEAT :: "\u00d7"
ICON_BUTTON_IS_SONG :: "\uf001"
// ICON_BUTTON_IS_ALBUM :: "\uf152"
ICON_BUTTON_IS_ALBUM :: "\uf192"
ICON_BUTTON_IS_ARTIST :: "\uf007"
ICON_BUTTON_PLAYLIST :: "\uf025"
ICON_BUTTON_DEFAULT_SONG_PLAY :: "\uf587"


//  stores cstrings in app arena
text :: proc(s: string) -> cstring {
	return strings.clone_to_cstring(s, app.g_app.arena_allocator)
}

Vec4 :: [4]f32
color_vec4_to_u32 :: proc(c: Vec4) -> u32 {
	r := cast(u32)(c.x * 255.0)
	g := cast(u32)(c.y * 255.0)
	b := cast(u32)(c.z * 255.0)
	a := cast(u32)(c.w * 255.0)
	return (a << 24) | (b << 16) | (g << 8) | r
}


top_left_panel :: proc(
	search_buffer: ^[256]u8,
	search_results: ^[dynamic]media.SearchItem,
	audio_state: ^audio.AudioState,
	window_size: im.Vec2,
) {
	root := "C:/Users/St.Klue/Music"

	im.PushStyleColor(im.Col.ScrollbarBg, color_vec4_to_u32({0.10, 0.12, 0.18, 0.25})) // dark blue base
	im.PushStyleColor(im.Col.ScrollbarGrab, color_vec4_to_u32({0.20, 0.50, 0.90, 0.35})) // cool blue
	im.PushStyleColor(im.Col.ScrollbarGrabHovered, color_vec4_to_u32({0.30, 0.60, 1.00, 0.45}))
	im.PushStyleColor(im.Col.ScrollbarGrabActive, color_vec4_to_u32({0.45, 0.80, 1.00, 0.60}))


	if im.Begin("##top-left", nil, {.NoTitleBar, .NoResize, .NoBackground, .NoScrollbar}) {
		offset_x: f32 = 35
		size := im.GetContentRegionAvail()

		// === Search Bar ===
		im.Dummy({0, 20})
		im.Dummy({10, 0})
		im.SameLine()
		bar_size := im.Vec2{size.x - offset_x, 40} // includes padding space
		// draw_search_bar("##search-bar", query_buffer, bar_size)
		draw_search_bar(search_buffer, bar_size)
		search_cstring := transmute(cstring)search_buffer
		if im.IsItemEdited() {
			if app.g_app.library.search_thread != nil {
				thread.destroy(app.g_app.library.search_thread)
			}
			// fmt.tprint(cast(cstring)(&query_buffer[0])),
			app.g_app.library.search_thread = thread.create_and_start_with_poly_data4(
				app.g_app,
				strings.clone_from_cstring(search_cstring, app.g_app.arena_allocator),
				&app.g_app.library.songs,
				search_results,
				app.search_song,
			)
		}

		// === Playlist Container ===
		im.Dummy({0, 20}) // space below search bar

		child_height := size.y - 70 // subtract fixed search + spacing
		if im.BeginChild(
			"##playlist-scroll",
			{size.x, child_height},
			{},
			{.AlwaysUseWindowPadding},
		) {
			im.Dummy({0, 10})

			// All Songs Button
			if draw_custom_button("All Songs", {}, {size.x - offset_x, 30}, {10, 10}) {
				using app
				clear(&g_app.play_queue)
				append(&g_app.play_queue, ..g_app.library.songs[:])
				g_app.ui_view = .All_Songs
				g_app.last_view = .All_Songs
			}

			im.Separator()

			// draw playlists
			if len(search_cstring) == 0 {
				for v, i in app.g_app.library.playlists {
					currently_selected := app.g_app.library.playlist_index == i
					if draw_item_selectable(
						fmt.ctprint(v.meta.title),
						currently_selected,
						{},
						{size.x - offset_x, 30},
						{10, 10},
					) {
						app.g_app.library.playlist_index = i
						app.g_app.ui_view = .Playlist
						app.g_app.last_view = .Playlist
						// destroy thread first if it was already created
						if app.g_app.library.playlist_thread != nil {
							thread.destroy(app.g_app.library.playlist_thread)
						}
						app.g_app.library.playlist_thread =
							thread.create_and_start_with_poly_data3(
								&app.g_app.mutex,
								&app.g_app.library.playlists[i],
								&app.g_app.clicked_playlist_entries,
								media.scan_playlist_entries,
							)
					}
				}
			} else {
				// drawing search results
				if len(search_results) > 0 && len(search_results) < 100 {
					for search_result, i in search_results {
						currently_selected := app.g_app.search_result_index == i
						if draw_selectable_search_item(
							search_result.label,
							currently_selected,
							{},
							{size.x - offset_x, 30},
							{10, 10},
							search_result.kind,
						) {
							app.g_app.ui_view = .Search
							app.g_app.last_view = .Search
							search_cstring = search_result.file_name
							switch search_result.kind {
							case .Title:
								clear(&app.g_app.clicked_search_results_entries)
								app.search_one_song(
									&app.g_app.library.songs,
									search_result.file_name,
									&app.g_app.clicked_search_results_entries,
								)
							case .Album:
								clear(&app.g_app.clicked_search_results_entries)
								app.search_album(
									&app.g_app.library.songs,
									search_result.file_name,
									&app.g_app.clicked_search_results_entries,
								)
							case .Artist:
								clear(&app.g_app.clicked_search_results_entries)
								app.search_artist(
									&app.g_app.library.songs,
									search_result.file_name,
									&app.g_app.clicked_search_results_entries,
								)
							}
						}

					}
				}
			}
		}
		im.EndChild()
	}
	im.End()

	im.PopStyleColor(4)

}
top_right_panel :: proc(
	audio_state: ^audio.AudioState,
	window_position: im.Vec2,
	window_size: im.Vec2,
	search_buffer: ^[256]byte,
) {
	im.SetNextWindowPos(window_position)
	im.SetNextWindowSize(window_size)
	style := im.GetStyle()
	old_padding := style.FramePadding
	defer style.FramePadding = old_padding // Restore after the frame

	style.FramePadding = 16
	search_cstring := transmute(cstring)search_buffer
	if im.Begin(
		"##right-panel-header",
		nil,
		{.NoResize, .NoCollapse, .NoTitleBar, .NoBackground},
	) {
		using app
		title: cstring

		switch g_app.ui_view {
		case .All_Songs:
			title = "All Songs"
		case .Search:
			title = text(fmt.tprint("Search results for", search_cstring))
		case .Playlist:
			title = text(g_app.library.playlists[g_app.library.playlist_index].meta.title)
		case .Visualizer:
			#partial switch g_app.last_view {
			case .All_Songs:
				title = "All Songs"
			case .Search:
				title = text(fmt.tprint("Search results for", search_cstring))
			case .Playlist:
				title = text(g_app.library.playlists[g_app.library.playlist_index].meta.title)
			}
		}

		im.SetCursorPos(im.Vec2{0, 20})
		im.PushFont(g_app.header_font)
		draw_custom_header(title, im.GetContentRegionAvail().x)
		im.PopFont()
		im.Dummy(im.Vec2{0, 20})


		size := im.GetContentRegionAvail()
		im.BeginChild("##list-region", size) // border=true


		switch g_app.ui_view {
		case .Visualizer:
			pos := im.GetCursorScreenPos()
			render_audio_visualizer(audio_state, pos, size)
		case .All_Songs:
			draw_all_songs(&g_app.library.songs, audio_state, size)
		case .Search:
			draw_search_results_clicked(audio_state, size)
		case .Playlist:
			draw_playlist_items(audio_state, size)
		}


		im.EndChild()
	}
	im.End()

}
bottom_panel :: proc(
	app_state: ^app.AppState,
	audio_state: ^audio.AudioState,
	top_h, screen_w, third_h: f32,
) {
	im.SetNextWindowPos(im.Vec2{0, top_h})
	im.SetNextWindowSize(im.Vec2{screen_w, third_h})
	if im.Begin("##bottom", nil, {.NoTitleBar, .NoResize, .NoBackground}) {

		draw_audio_progress_bar(audio_state)

		im.Dummy({0, 18})

		spacing := im.GetStyle().ItemSpacing.x
		frame_padding_x := im.GetStyle().FramePadding.x

		im.PushFont(app.g_app.prev_and_next_icon_font)
		prev_size := im.CalcTextSize(ICON_BUTTON_PREV).x + 2 * frame_padding_x
		next_size := im.CalcTextSize(ICON_BUTTON_NEXT).x + 2 * frame_padding_x
		stop_size := im.CalcTextSize(ICON_BUTTON_STOP).x + 2 * frame_padding_x
		repeat_all_size := im.CalcTextSize(ICON_BUTTON_REPEAT_ALL).x + 2 * frame_padding_x
		no_repeat_size := im.CalcTextSize(ICON_BUTTON_NO_REPEAT).x + 2 * frame_padding_x
		one_size := im.CalcTextSize("1").x + 2 * frame_padding_x
		repeat_size := math.max(repeat_all_size, math.max(one_size, no_repeat_size))
		im.PopFont()

		im.PushFont(app.g_app.play_and_pause_icon_font)
		play_size := im.CalcTextSize(ICON_BUTTON_PLAY).x + 2 * frame_padding_x
		pause_size := im.CalcTextSize(ICON_BUTTON_PAUSE).x + 2 * frame_padding_x
		play_button_size := math.max(play_size, pause_size)
		im.PopFont()

		total_width :=
			prev_size + play_button_size + next_size + stop_size + repeat_size + (spacing * 4)

		if im.BeginTable("audio_controls", 3) {
			im.TableSetupColumn("left", {.WidthStretch})
			im.TableSetupColumn("center", {.WidthFixed}, total_width)
			im.TableSetupColumn("right", {.WidthStretch})
			im.TableNextRow()

			// Left column: song details
			im.TableSetColumnIndex(0)
			if len(app_state.play_queue) > 0 {
				left_margin: f32 = 40.0
				im.SetCursorPosX(im.GetCursorPosX() + left_margin)
				im.Text(app_state.play_queue[app_state.play_queue_index].metadata.title)
				im.SameLine()
				im.Dummy({20, 0})
				im.SameLine()
				im.Text(app_state.play_queue[app_state.play_queue_index].metadata.artist)
			}

			// Center column: buttons
			im.TableSetColumnIndex(1)
			im.PushStyleColor(im.Col.Button, 0) // transparent button bg
			im.PushStyleColor(im.Col.ButtonHovered, color_vec4_to_u32({0.9, 0.3, 0.3, 1})) // transparent hover
			im.PushStyleColor(im.Col.ButtonActive, 0) // transparent active
			im.PushStyleColor(im.Col.Text, color_vec4_to_u32({0.8, 0.8, 0.8, 0.8}))
			im.PushFont(app.g_app.prev_and_next_icon_font)
			if im.Button(ICON_BUTTON_PREV) {
				prev_path_index :=
					app_state.play_queue_index - 1 >= 0 ? app_state.play_queue_index - 1 : 0
				audio.update_path(audio_state, app_state.all_songs[prev_path_index].fullpath)
				audio.create_audio_play_thread(audio_state)
				sync.mutex_lock(&app_state.mutex)
				app_state.play_queue_index = prev_path_index
				sync.mutex_unlock(&app_state.mutex)
			}
			im.PopFont()
			im.SameLine()


			im.PushFont(app.g_app.play_and_pause_icon_font)
			if im.Button(audio_state.is_playing ? ICON_BUTTON_PAUSE : ICON_BUTTON_PLAY) {
				audio.toggle_playback(audio_state)
			}

			im.PopFont()
			im.SameLine()

			// Next button
			im.PushFont(app.g_app.prev_and_next_icon_font)
			if im.Button(ICON_BUTTON_NEXT) {
				next_path_index :=
					app_state.play_queue_index + 1 >= len(app_state.all_songs) ? app_state.play_queue_index : app_state.play_queue_index + 1
				audio.update_path(audio_state, app_state.all_songs[next_path_index].fullpath)
				audio.create_audio_play_thread(audio_state)
				sync.mutex_lock(&app_state.mutex)
				app_state.play_queue_index = next_path_index
				sync.mutex_unlock(&app_state.mutex)
			}
			im.SameLine()

			// Stop button
			if im.Button(ICON_BUTTON_STOP) {
				audio.stop_playback(audio_state)
			}
			im.SameLine()
			switch audio_state.repeat_option {
			case .All:
				if im.Button(ICON_BUTTON_REPEAT_ALL) {
					audio_state.repeat_option = .One
				}
			case .One:
				if im.Button("1") {
					audio_state.repeat_option = .Off
				}
			case .Off:
				if im.Button(ICON_BUTTON_NO_REPEAT) {
					audio_state.repeat_option = .All
				}
			}
			im.PopFont()
			im.PopStyleColor(4)

			// Right column: volume slider
			im.TableSetColumnIndex(2)
			draw_volume_bar(audio_state)

			im.EndTable()
		}


	}
	im.End()

}
