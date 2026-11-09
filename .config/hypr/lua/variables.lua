-- ~/.config/hypr/lua/variables.lua

-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
-- ┃                     Environment Variables                   ┃
-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("HYPRCURSOR_SIZE", "18")
hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("XCURSOR_SIZE", "18")
hl.env("QT_CURSOR_THEME", "Bibata-Modern-Classic")
hl.env("QT_CURSOR_SIZE", "18")
hl.env("TERMINAL", "alacritty")

-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
-- ┃                     Defaults Configuration                  ┃
-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

local defaults = {
	apps = {
		filemanager = "thunar",
		terminal = "alacritty",
		idlehandler = "hypridle",
	},
	shots = {
		region = "grimblast copy area",
		window = "grimblast copy active",
		screen = "grimblast copy output",
		save = "grimblast --notify copysave area",
	},
}

return defaults
