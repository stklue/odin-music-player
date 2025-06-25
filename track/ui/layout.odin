package ui


import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import image "vendor:stb/image"

import im "../../odin-imgui"
import "../../odin-imgui/imgui_impl_glfw"
import "../../odin-imgui/imgui_impl_opengl3"

// import audio "audio_state"
import app "../app"
import audio "../audio_state"
import "base:runtime"
import json "core:encoding/json"
import "core:encoding/xml"
import "core:math"
import "core:path/filepath"
import "core:sync"

text :: proc(s: string) -> cstring {
	return strings.clone_to_cstring(s)
}

Vec4 :: [4]f32
color_vec4_to_u32 :: proc(c: Vec4) -> u32 {
	r := cast(u32)(c.x * 255.0)
	g := cast(u32)(c.y * 255.0)
	b := cast(u32)(c.z * 255.0)
	a := cast(u32)(c.w * 255.0)
	return (a << 24) | (b << 16) | (g << 8) | r
}


top_right_panel :: proc(
	bolt_font: ^im.Font,
	shared_files_mutex: ^sync.Mutex,
	all_paths: ^[dynamic]app.FileEntry,
	audio_state: ^audio.AudioState,
	app_state: ^app.AppState,
	top_h, third_w, right_w: f32,
) {
	im.SetNextWindowPos(im.Vec2{third_w, 0})
	im.SetNextWindowSize(im.Vec2{right_w, top_h})
	style := im.GetStyle()
	old_padding := style.FramePadding
	defer style.FramePadding = old_padding // Restore after the frame

	style.FramePadding = 16

	if im.Begin("##right-panel-header", nil, {.NoResize, .NoCollapse, .NoTitleBar}) {
		title :=
			app_state.playlist_index == -1 ? "All Songs" : text(app_state.playlists[app_state.playlist_index].meta.title)

		im.PushFont(bolt_font)
		draw_custom_header(title)
		im.PopFont()


		// if im.Begin("##top-right", nil, {.NoResize}) {
		sync.mutex_lock(shared_files_mutex)

		size := im.GetContentRegionAvail()
		im.BeginChild("ListRegion", size) // border=true

		for v, i in all_paths {
			is_selected := app_state.current_item_playing_index == i

			im.BeginGroup()
			im.Spacing()

			bg := color_vec4_to_u32({0.9, 0.2, 0.2, 1})

			if CustomSelectable(v.name, is_selected, 0, {}, {size.x, 30}, {50, 10}) {


				fmt.printf("[App] Playing: %s\n", v.name)
				fmt.println(i, app_state.current_item_playing_index, is_selected)
				// set_current_item(app_state, v)

				sync.mutex_lock(&app_state.mutex)
				// if app_state.playlist_item_clicked {

				// }
				// app_state.
				app_state.all_songs_item_playling = v
				app_state.playlist_item_clicked = true
				app_state.current_item_playing_index = i
				sync.mutex_unlock(&app_state.mutex)

				audio.update_path(audio_state, v.fullpath)
				audio.create_audio_play_thread(audio_state)
			}

			im.EndGroup()
		}


		im.EndChild()
		sync.mutex_unlock(shared_files_mutex)
	}
	im.End()

}
bottom_panel :: proc(
	app_state: ^app.AppState,
	display_songs: ^[dynamic]app.FileEntry,
	audio_state: ^audio.AudioState,
	top_h, screen_w, third_h: f32,
) {
	im.SetNextWindowPos(im.Vec2{0, top_h})
	im.SetNextWindowSize(im.Vec2{screen_w, third_h})
	if im.Begin("##bottom", nil, {.NoTitleBar, .NoResize}) {
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
				app_state.current_item_playing_index - 1 >= 0 ? app_state.current_item_playing_index - 1 : 0
			app_state.all_songs_item_playling = app_state.all_songs[prev_path_index]
			audio.update_path(audio_state, app_state.all_songs[prev_path_index].fullpath)
			audio.create_audio_play_thread(audio_state)
			sync.mutex_lock(&app_state.mutex)
			app_state.current_item_playing_index = prev_path_index
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
				app_state.current_item_playing_index + 1 >= len(app_state.all_songs) ? app_state.current_item_playing_index : app_state.current_item_playing_index + 1
			app_state.all_songs_item_playling = app_state.all_songs[next_path_index]
			audio.update_path(audio_state, app_state.all_songs[next_path_index].fullpath)
			audio.create_audio_play_thread(audio_state)
			sync.mutex_lock(&app_state.mutex)
			app_state.current_item_playing_index = next_path_index
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

		audio_progress_bar_and_volume_bar(audio_state)

		im.Dummy({0, 20})
		// im.Text(
		// 	app_state.current_item_playing_index == -1 ? "" : display_songs[app_state.current_item_playing_index].name,
		// )
	}
	im.End()

}
