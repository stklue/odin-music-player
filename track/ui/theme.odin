package ui

import im "../../odin-imgui"
import "../../odin-imgui/imgui_impl_glfw"
import "../../odin-imgui/imgui_impl_opengl3"


set_red_black_theme :: proc() {
	style := im.GetStyle()
	colors := style.Colors

	// Backgrounds
	colors[im.Col.WindowBg] = {0.05, 0.05, 0.05, 1.0} // deep black
	colors[im.Col.ChildBg] = {0.08, 0.08, 0.08, 1.0}
	colors[im.Col.PopupBg] = {0.1, 0.1, 0.1, 1.0}

	// Text
	colors[im.Col.Text] = {1.0, 0.3, 0.3, 1.0} // light red
	colors[im.Col.TextDisabled] = {0.4, 0.2, 0.2, 1.0}

	// Borders
	colors[im.Col.Border] = {0.3, 0.0, 0.0, 1.0}
	colors[im.Col.BorderShadow] = {0.1, 0.0, 0.0, 0.5}

	// Frames (inputs, buttons)
	colors[im.Col.FrameBg] = {0.2, 0.05, 0.05, 1.0}
	colors[im.Col.FrameBgHovered] = {0.4, 0.1, 0.1, 1.0}
	colors[im.Col.FrameBgActive] = {0.6, 0.0, 0.0, 1.0}

	// Title bar
	colors[im.Col.TitleBg] = {0.1, 0.0, 0.0, 1.0}
	colors[im.Col.TitleBgActive] = {0.6, 0.0, 0.0, 1.0}

	// Buttons
	colors[im.Col.Button] = {0.3, 0.0, 0.0, 1.0}
	colors[im.Col.ButtonHovered] = {0.6, 0.1, 0.1, 1.0}
	colors[im.Col.ButtonActive] = {0.8, 0.0, 0.0, 1.0}

	// Selectables
	colors[im.Col.Header] = {0.3, 0.0, 0.0, 1.0}
	colors[im.Col.HeaderHovered] = {0.5, 0.0, 0.0, 1.0}
	colors[im.Col.HeaderActive] = {0.7, 0.0, 0.0, 1.0}

	// Tabs (optional)
	colors[im.Col.Tab] = {0.2, 0.0, 0.0, 1.0}
	colors[im.Col.TabHovered] = {0.5, 0.0, 0.0, 1.0}
	colors[im.Col.TabActive] = {0.6, 0.0, 0.0, 1.0}

	// Sliders, checks, grabs
	colors[im.Col.SliderGrab] = {1.0, 0.2, 0.2, 1.0}
	colors[im.Col.SliderGrabActive] = {1.0, 0.4, 0.4, 1.0}
	colors[im.Col.CheckMark] = {1.0, 0.2, 0.2, 1.0}

	// Menus (optional)
	colors[im.Col.MenuBarBg] = {0.1, 0.0, 0.0, 1.0}

	// Adjust rounding if you want a clean boxy look
	style.FrameRounding = 4
	style.WindowRounding = 6
	style.PopupRounding = 4
}
