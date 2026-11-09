-- ~/.config/hypr/lua/autostart.lua
local vars = require("lua.variables")
local machine = require("lua.machine")

hl.on("hyprland.start", function()
	-- uwsm exports the environment to systemd/dbus, and the polkit agent runs as
	-- hyprpolkitagent.service (enabled by install.sh)

	-- Core UI Daemons
	hl.exec_cmd("quickshell -c bar")
	if not machine.laptop then
		hl.exec_cmd("openrgb --server")
	end

	-- Idle, Lock, and Wallpaper
	hl.exec_cmd("~/.config/quickshell/scripts/lock.sh --start")
	hl.exec_cmd(vars.apps.idlehandler)
	hl.exec_cmd("awww-daemon")
	hl.exec_cmd("~/.config/quickshell/scripts/video-wallpaper.sh resume")
	hl.exec_cmd("nice -n 19 ionice -c 3 ~/.config/quickshell/scripts/scan-wallpapers.sh > /dev/null")

	-- Clipboard Utilities
	hl.exec_cmd("wl-paste --type text --watch cliphist store")
	hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)
