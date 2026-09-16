-- ~/.config/hypr/lua/keybinds.lua
local vars = require("lua.variables")
local mod = "SUPER"
local lotm = require("scripts.lotm")

-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
-- ┃                     Core Applications                       ┃
-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
hl.bind(mod .. " + RETURN", hl.dsp.exec_cmd(vars.apps.terminal), { description = "Apps: Open terminal" })
hl.bind(mod .. " + E", hl.dsp.exec_cmd(vars.apps.filemanager), { description = "Apps: Open file manager" })
hl.bind(mod .. " + B", hl.dsp.exec_cmd("xdg-open 'https://'"), { description = "Apps: Open browser" })
hl.bind(
	mod .. " + D",
	hl.dsp.exec_cmd("qs --config bar ipc call launcher toggle"),
	{ description = "Apps: Toggle launcher" }
)
hl.bind(
	mod .. " + M",
	hl.dsp.exec_cmd("qs --config bar ipc call musiclibrary toggle"),
	{ description = "Apps: Toggle quickshell music player" }
)
hl.bind(
	mod .. " + S",
	hl.dsp.exec_cmd("qs --config bar ipc call quicksettings toggle"),
	{ description = "Apps: Toggle quick settings" }
)
hl.bind(
	mod .. " + W",
	hl.dsp.exec_cmd("qs --config bar ipc call wallpaper toggle"),
	{ description = "Apps: Toggle wallpaper picker" }
)
hl.bind(
	mod .. " + C",
	hl.dsp.exec_cmd("qs --config bar ipc call sysmonitor open"),
	{ description = "Apps: Open system monitor" }
)
hl.bind(
	mod .. " + H",
	hl.dsp.exec_cmd("qs --config bar ipc call keybinds toggle"),
	{ description = "Apps: Open Cheatsheet" }
)
hl.bind(
	mod .. " + SHIFT + G",
	hl.dsp.exec_cmd("~/.config/hypr/scripts/gamemode.sh"),
	{ description = "Apps: Toggle game mode" }
)
hl.bind(mod .. " + N", hl.dsp.exec_cmd("nwg-displays"), { description = "Apps: Open display settings" })
hl.bind(
	mod .. " + SHIFT + M",
	hl.dsp.exec_cmd("~/.config/hypr/scripts/toggle-music.sh"),
	{ description = "Apps: Toggle youtube music player" }
)

-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
-- ┃                     Window Management                       ┃
-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
-- object dispatchers
hl.bind(mod .. " + Q", hl.dsp.window.close(), { description = "Windows: Close window" })
hl.bind(mod .. " + SHIFT + Q", hl.dsp.window.kill(), { description = "Windows: Kill window" })
hl.bind(mod .. " + SHIFT + F", hl.dsp.window.fullscreen(), { description = "Windows: Toggle fullscreen" })
hl.bind(mod .. " + V", hl.dsp.window.float({ action = "toggle" }), { description = "Windows: Toggle floating" })
hl.bind(mod .. " + Y", hl.dsp.window.pin(), { description = "Windows: Pin window" })
hl.bind(mod .. " + J", hl.dsp.layout("togglesplit"), { description = "Windows: Toggle split layout" })

-- Grouping
hl.bind(mod .. " + K", hl.dsp.group.toggle(), { description = "Windows: Toggle window group" })
hl.bind(mod .. " + Tab", hl.dsp.group.next(), { description = "Windows: Next window in group" })

-- Moving Focus
hl.bind(mod .. " + left", hl.dsp.focus({ direction = "l" }), { description = "Focus & Move: Focus left" })
hl.bind(mod .. " + right", hl.dsp.focus({ direction = "r" }), { description = "Focus & Move: Focus right" })
hl.bind(mod .. " + up", hl.dsp.focus({ direction = "u" }), { description = "Focus & Move: Focus up" })
hl.bind(mod .. " + down", hl.dsp.focus({ direction = "d" }), { description = "Focus & Move: Focus down" })

-- Moving Windows
hl.bind(
	mod .. " + CTRL + left",
	hl.dsp.window.move({ direction = "l" }),
	{ description = "Focus & Move: Move window left" }
)
hl.bind(
	mod .. " + CTRL + right",
	hl.dsp.window.move({ direction = "r" }),
	{ description = "Focus & Move: Move window right" }
)
hl.bind(
	mod .. " + CTRL + up",
	hl.dsp.window.move({ direction = "u" }),
	{ description = "Focus & Move: Move window up" }
)
hl.bind(
	mod .. " + CTRL + down",
	hl.dsp.window.move({ direction = "d" }),
	{ description = "Focus & Move: Move window down" }
)

-- Resizing Windows (using relative coordinates)
hl.bind(
	mod .. " + SHIFT + left",
	hl.dsp.window.resize({ x = -50, y = 0, relative = true }),
	{ description = "Focus & Move: Shrink window width" }
)
hl.bind(
	mod .. " + SHIFT + right",
	hl.dsp.window.resize({ x = 50, y = 0, relative = true }),
	{ description = "Focus & Move: Grow window width" }
)
hl.bind(
	mod .. " + SHIFT + up",
	hl.dsp.window.resize({ x = 0, y = -50, relative = true }),
	{ description = "Focus & Move: Shrink window height" }
)
hl.bind(
	mod .. " + SHIFT + down",
	hl.dsp.window.resize({ x = 0, y = 50, relative = true }),
	{ description = "Focus & Move: Grow window height" }
)

-- Mouse Binds (using the mouse flag)
hl.bind(
	mod .. " + mouse:272",
	hl.dsp.window.drag(),
	{ mouse = true, description = "Focus & Move: Move window (mouse)" }
)
hl.bind(
	mod .. " + mouse:273",
	hl.dsp.window.resize(),
	{ mouse = true, description = "Focus & Move: Resize window (mouse)" }
)

hl.bind(mod .. " + T", function()
	lotm.setup()
end, { description = "Set up the LotM translation workspace" })

hl.bind(mod .. " + SHIFT + T", function()
	lotm.lookup()
end, { description = "Toggle the LotM lookup scratchpad" })

-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
-- ┃                   Clipboard & Screenshots                   ┃
-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
hl.bind(
	mod .. " + SHIFT + code:201",
	hl.dsp.exec_cmd("qs --config bar ipc call clipboard toggle"),
	{ description = "Clipboard & Screenshots: Toggle clipboard history (Menu key)" }
)
hl.bind(
	"code:135",
	hl.dsp.exec_cmd("qs --config bar ipc call clipboard toggle"),
	{ description = "Clipboard & Screenshots: Toggle clipboard history (Menu key, alt keyboards)" }
)
hl.bind(
	"PRINT",
	hl.dsp.exec_cmd(vars.shots.region),
	{ description = "Clipboard & Screenshots: Copy region screenshot to clipboard" }
)
hl.bind(
	"SHIFT + PRINT",
	hl.dsp.exec_cmd(vars.shots.screen),
	{ description = "Clipboard & Screenshots: Copy full screen to clipboard" }
)

-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
-- ┃                     Media & Hardware                        ┃
-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
hl.bind(
	mod .. " + F2",
	hl.dsp.exec_cmd("~/.config/hypr/scripts/toggle-dp3.sh"),
	{ description = "Media & Hardware: Toggle second display" }
)

hl.bind(
	"XF86AudioRaiseVolume",
	hl.dsp.exec_cmd("qs --config bar ipc call osd volumeUp"),
	{ description = "Media & Hardware: Raise volume" }
)
hl.bind(
	"XF86AudioLowerVolume",
	hl.dsp.exec_cmd("qs --config bar ipc call osd volumeDown"),
	{ description = "Media & Hardware: Lower volume" }
)
hl.bind(
	"XF86AudioMute",
	hl.dsp.exec_cmd("qs --config bar ipc call osd volumeMute"),
	{ locked = true, description = "Media & Hardware: Toggle mute" }
)
hl.bind(
	"XF86AudioMicMute",
	hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),
	{ locked = true, description = "Media & Hardware: Toggle mic mute" }
)

hl.bind(
	"XF86AudioPlay",
	hl.dsp.exec_cmd("playerctl play-pause"),
	{ locked = true, description = "Media & Hardware: Play / pause media" }
)
hl.bind(
	"XF86AudioNext",
	hl.dsp.exec_cmd("playerctl next"),
	{ locked = true, description = "Media & Hardware: Next track" }
)
hl.bind(
	"XF86AudioPrev",
	hl.dsp.exec_cmd("playerctl previous"),
	{ locked = true, description = "Media & Hardware: Previous track" }
)

hl.bind(
	"XF86MonBrightnessUp",
	hl.dsp.exec_cmd("qs --config bar ipc call osd brightnessUp"),
	{ description = "Media & Hardware: Raise brightness" }
)
hl.bind(
	"XF86MonBrightnessDown",
	hl.dsp.exec_cmd("qs --config bar ipc call osd brightnessDown"),
	{ description = "Media & Hardware: Lower brightness" }
)

hl.bind(
	"switch:on:Lid Switch",
	hl.dsp.dpms({ action = "disable" }),
	{ locked = true, description = "Media & Hardware: Screen off on lid close" }
)
hl.bind(
	"switch:off:Lid Switch",
	hl.dsp.dpms({ action = "enable" }),
	{ locked = true, description = "Media & Hardware: Screen on on lid open" }
)

hl.bind(
	mod .. " + L",
	hl.dsp.exec_cmd("quickshell -p ~/.config/quickshell/lockscreen/lock.qml ipc call lock lock"),
	{ description = "Media & Hardware: Lock screen" }
)

-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
-- ┃                 Workspaces & Submaps                        ┃
-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
for i = 1, 10 do
	local ws = tostring(i)
	local key = tostring(i % 10)
	hl.bind(
		mod .. " + " .. key,
		hl.dsp.focus({ workspace = ws }),
		{ description = "Workspaces: Switch to workspace " .. ws }
	)
	hl.bind(
		mod .. " + SHIFT + " .. key,
		hl.dsp.window.move({ workspace = ws, follow = true }),
		{ description = "Workspaces: Move window to workspace " .. ws .. " (follow)" }
	)
	hl.bind(
		mod .. " + CTRL + " .. key,
		hl.dsp.window.move({ workspace = ws, follow = false }),
		{ description = "Workspaces: Move window to workspace " .. ws .. " (stay)" }
	)
end

hl.bind(mod .. " + PERIOD", hl.dsp.focus({ workspace = "e-1" }), { description = "Workspaces: Previous workspace" })
hl.bind(mod .. " + COMMA", hl.dsp.focus({ workspace = "e+1" }), { description = "Workspaces: Next workspace" })
hl.bind(
	mod .. " + mouse_down",
	hl.dsp.focus({ workspace = "e+1" }),
	{ description = "Workspaces: Next workspace (scroll)" }
)
hl.bind(
	mod .. " + mouse_up",
	hl.dsp.focus({ workspace = "e-1" }),
	{ description = "Workspaces: Previous workspace (scroll)" }
)
hl.bind(
	mod .. " + slash",
	hl.dsp.focus({ workspace = "previous" }),
	{ description = "Workspaces: Toggle previous workspace" }
)

hl.bind(
	mod .. " + minus",
	hl.dsp.window.move({ workspace = "special" }),
	{ description = "Workspaces: Move window to special workspace" }
)
hl.bind(
	mod .. " + equal",
	hl.dsp.workspace.toggle_special("special"),
	{ description = "Workspaces: Toggle special workspace" }
)
hl.bind(
	mod .. " + F1",
	hl.dsp.workspace.toggle_special("scratchpad"),
	{ description = "Workspaces: Toggle scratchpad" }
)
hl.bind(
	mod .. " + CTRL + F1",
	hl.dsp.window.move({ workspace = "special:scratchpad", follow = false }),
	{ description = "Workspaces: Move window to scratchpad" }
)

-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
-- ┃                     Config Overrides                        ┃
-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
hl.config({
	binds = {
		allow_workspace_cycles = true,
		workspace_back_and_forth = true,
		workspace_center_on = 1,
		movefocus_cycles_fullscreen = true,
		window_direction_monitor_fallback = true,
	},
})
