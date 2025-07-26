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
	playlists: ^[dynamic]media.Playlist, // all_songs: ^[dynamic]media.Song,
	playlists_mutex: ^sync.Mutex,
	all_playlists_scan_done: bool,
	app_state: ^app.AppState,
	search_results: ^[dynamic]media.SearchItem,
	root: string,
	audio_state: ^audio.AudioState,
	query_buffer: ^[256]u8,
	window_size: im.Vec2,
) {
	if im.Begin("##top-left", nil, {.NoTitleBar, .NoResize, .NoBackground, .NoScrollbar}) {
		offset_x: f32 = 35
		size := im.GetContentRegionAvail()

		// === Search Bar ===
		im.Dummy({0, 20})
		im.Dummy({10, 0})
		im.SameLine()
		bar_size := im.Vec2{size.x - offset_x, 40} // includes padding space
		draw_search_bar("##search-bar", query_buffer, bar_size)
		if im.IsItemEdited() {
			if app.g_app.library.search_thread  != nil {
				thread.destroy(app.g_app.library.search_thread)
			}
			app.g_app.library.search_thread = thread.create_and_start_with_poly_data4(
				app.g_app,
				fmt.tprint(cast(cstring)(&query_buffer[0])),
				&app_state.library.songs,
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

			// TODO: fix this not setting to true when press ctrl and backspace
			empty := true
			diff: u8
			for val in query_buffer {
				if val != 0 {
					diff = val
					empty = false
				}
			}

			// draw playlists
			if empty {
				for v, i in playlists {
					currently_selected := app.g_app.playlist_index == i
					if draw_item_selectable(
						fmt.ctprint(v.meta.title),
						currently_selected,
						{},
						{size.x - offset_x, 30},
						{10, 10},
					) {
						app.g_app.playlist_index = i
						app.g_app.ui_view = .Playlist
						app.g_app.last_view = .Playlist
						// destroy thread first if it was already created
						if app.g_app.library.playlist_thread != nil {
							thread.destroy(app.g_app.library.playlist_thread)
						}
						app.g_app.library.playlist_thread =
							thread.create_and_start_with_poly_data4(
								&app.g_app.mutex,
								&playlists[i],
								&app.g_app.clicked_playlist_entries,
								app.g_app.scan_playlist_done,
								media.scan_playlist_entries,
							)
					}
				}
			} else {
				// drawing search results
				if len(search_results) > 0 && len(search_results) < 100 {
					for search_result, i in search_results {
						currently_selected := app.g_app.search_result_index == i
						if draw_item_selectable(
							search_result.label,
							currently_selected,
							{},
							{size.x - offset_x, 30},
							{10, 10},
						) {
							app.g_app.ui_view = .Search
							app.g_app.last_view = .Search
							app.g_app.search_query =  search_result.file_name
							switch search_result.kind {
							case .Title:
								clear(&app_state.clicked_search_results_entries)
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

}
top_right_panel :: proc(
	all_songs: ^[dynamic]media.Song,
	bolt_font: ^im.Font,
	audio_state: ^audio.AudioState,
	window_position: im.Vec2,
	window_size: im.Vec2,
) {
	im.SetNextWindowPos(window_position)
	im.SetNextWindowSize(window_size)
	style := im.GetStyle()
	old_padding := style.FramePadding
	defer style.FramePadding = old_padding // Restore after the frame

	style.FramePadding = 16

	if im.Begin(
		"##right-panel-header",
		nil,
		{.NoResize, .NoCollapse, .NoTitleBar, .NoBackground},
	) {
		using app
		title: cstring

		#partial switch g_app.ui_view {
		case .All_Songs:
			title = "All Songs"
		case .Search:
			title = strings.clone_to_cstring(fmt.tprint("Search results for", g_app.search_query))
		case .Playlist:
			title = text(g_app.library.playlists[g_app.playlist_index].meta.title)
		}

		im.SetCursorPos(im.Vec2{0, 20})
		im.PushFont(bolt_font)
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
			draw_all_songs(all_songs, audio_state, size)
		case .Search:
			draw_search_results_clicked(audio_state, size)
		case .Playlist:
			draw_playlist_items(audio_state, size)
		}
		// if app.g_app.show_visualizer {
		// 	pos := im.GetCursorScreenPos()
		// 	render_audio_visualizer(audio_state, pos, size)
		// } else if app.g_app.show_clicked_playlist {
		// 	draw_playlist_items(audio_state, size)
		// } else if app.g_app.show_search_results {
		// 	draw_search_results_clicked(audio_state, size)
		// } else {
		// 	draw_all_songs(all_songs, audio_state, size)
		// }

		im.EndChild()
		// sync.mutex_unlock(&app_state.mutex)
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
		im.PushStyleColor(im.Col.Button, 0) // transparent button bg
		im.PushStyleColor(im.Col.ButtonHovered, color_vec4_to_u32({0.9, 0.3, 0.3, 1})) // transparent hover
		im.PushStyleColor(im.Col.ButtonActive, 0) // transparent active

		button_count: f32 = 4.0
		button_width: f32 = 100.0
		spacing := im.GetStyle().ItemSpacing.x
		total_width := (button_width * button_count) + (spacing * (button_count - 1))

		avail := im.GetContentRegionAvail().x
		offset_x := (avail - total_width) / 2.0

		// Move cursor to horizontal center
		im.SetCursorPosX(im.GetCursorPosX() + offset_x)
		if im.Button("Prev") {
			prev_path_index :=
				app_state.play_queue_index - 1 >= 0 ? app_state.play_queue_index - 1 : 0
			audio.update_path(audio_state, app_state.all_songs[prev_path_index].fullpath)
			audio.create_audio_play_thread(audio_state)
			sync.mutex_lock(&app_state.mutex)
			app_state.play_queue_index = prev_path_index
			sync.mutex_unlock(&app_state.mutex)
		}

		im.SameLine()

		if im.Button(audio_state.is_playing ? "Pause" : "Play") {
			audio.toggle_playback(audio_state)
		}

		im.SameLine()

		// Stop button
		if im.Button("Next") {
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
		if im.Button("Stop") {
			audio.stop_playback(audio_state)
		}
		im.SameLine()
		switch audio_state.repeat_option {
		case .All:
			if im.Button("All") {
				audio_state.repeat_option = .One
			}
		case .One:
			if im.Button("One") {
				audio_state.repeat_option = .Off
			}
		case .Off:
			if im.Button("Off") {
				audio_state.repeat_option = .All
			}
		}


		im.PopStyleColor(3)

		draw_audio_progress_bar_and_volume_bar(audio_state)

		im.Dummy({0, 20})

		if len(app_state.play_queue) > 0 {
			im.Dummy({20, 0})
			im.SameLine()
			im.Text(app_state.play_queue[app_state.play_queue_index].metadata.title)
			im.Dummy({20, 0})
			im.SameLine()
			im.Text(app_state.play_queue[app_state.play_queue_index].metadata.artist)
		}
	}
	im.End()

}
