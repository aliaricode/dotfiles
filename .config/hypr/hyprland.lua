-- ~/.config/hypr/hyprland.lua

-- Machine-generated files (nwg-displays) are gitignored, so they may not exist on a fresh clone
local function optional(module)
	local ok, err = pcall(require, module)
	if not ok and not tostring(err):find("module '" .. module .. "' not found", 1, true) then
		error(err)
	end
end

require("lua.theme") -- Aesthetics (loads wallust colors, falls back to defaults)
require("lua.machine") -- Hardware (Laptop/Desktop)
require("lua.input") -- Keyboard/Mouse
optional("monitors") -- Display bridge (nwg-displays)
optional("workspaces") -- Workspace -> monitor assignments (nwg-displays)
require("lua.windowrules") -- Window Rules
require("lua.keybinds") -- The Keyboard Shortcuts
require("lua.autostart") -- Startup scripts
