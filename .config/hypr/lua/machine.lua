-- ~/.config/hypr/lua/machine.lua

local function file_exists(path)
	local f = io.open(path, "r")
	if f then
		f:close()
		return true
	end
	return false
end

local function is_laptop()
	return file_exists("/sys/class/power_supply/BAT0") or file_exists("/sys/class/power_supply/BAT1")
end

local laptop = is_laptop()
-- Only present when the proprietary/open NVIDIA kernel driver is loaded
local nvidia = file_exists("/proc/driver/nvidia/version")

hl.config({
	debug = { vfr = true },
	misc = {
		force_default_wallpaper = 0,
		-- lets lock.sh start a new lockscreen if the old one crashed while locked
		allow_session_lock_restore = true,
	},
})

hl.curve("machineEase", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })

-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
-- ┃                     Machine Profiles                        ┃
-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

local profiles = {
	laptop = {
		kb_layout = "tr, us", -- built-in Turkish keyboard
		general = { gaps_in = 3, gaps_out = 5, border_size = 2 },
		rounding = 5,
		blur_enabled = false,
		vrr = 0,
		animations = {
			{ leaf = "windows", speed = 3, bezier = "machineEase" },
			{ leaf = "windowsOut", speed = 3, bezier = "machineEase", style = "popin 80%" },
			{ leaf = "border", speed = 2, bezier = "default" },
			{ leaf = "fade", speed = 3, bezier = "default" },
			{ leaf = "workspaces", speed = 3, bezier = "machineEase" },
		},
		gestures = {
			{ fingers = 4, direction = "horizontal", action = "workspace" },
			{ fingers = 3, direction = "down", action = "close" },
			{ fingers = 3, direction = "up", action = "fullscreen" },
			{ fingers = 3, direction = "left", action = "float" },
		},
		env = {
			{ "LIBVA_DRIVER_NAME", "iHD" },
		},
	},
	desktop = {
		kb_layout = "us, tr", -- US keyboard, so start in English
		general = { gaps_in = 5, gaps_out = 10, border_size = 3 },
		blur_enabled = true,
		vrr = 1,
		animations = {
			{ leaf = "windows", speed = 7, bezier = "machineEase" },
			{ leaf = "windowsOut", speed = 7, bezier = "default", style = "popin 80%" },
			{ leaf = "border", speed = 10, bezier = "default" },
			{ leaf = "borderangle", speed = 8, bezier = "default" },
			{ leaf = "fade", speed = 7, bezier = "default" },
			{ leaf = "workspaces", speed = 6, bezier = "default" },
		},
		gestures = {},
		env = {},
	},
}

local profile = profiles[laptop and "laptop" or "desktop"]

-- NVIDIA-specific settings follow the driver, not the machine type (mesa needs no env vars)
if nvidia and not laptop then
	profile.no_hardware_cursors = 2
	profile.env = {
		{ "LIBVA_DRIVER_NAME", "nvidia" },
		{ "GBM_BACKEND", "nvidia-drm" },
		{ "__GLX_VENDOR_LIBRARY_NAME", "nvidia" },
	}
end

-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
-- ┃                     Apply Active Profile                    ┃
-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓

local config = {
	general = profile.general,
	decoration = { blur = { enabled = profile.blur_enabled } },
	misc = { vrr = profile.vrr },
	input = { kb_layout = profile.kb_layout },
}
if profile.rounding then
	config.decoration.rounding = profile.rounding
end
if profile.no_hardware_cursors then
	config.cursor = { no_hardware_cursors = profile.no_hardware_cursors }
end
hl.config(config)

for _, anim in ipairs(profile.animations) do
	hl.animation({ leaf = anim.leaf, enabled = true, speed = anim.speed, bezier = anim.bezier, style = anim.style })
end

for _, g in ipairs(profile.gestures) do
	hl.gesture(g)
end

for _, e in ipairs(profile.env) do
	hl.env(e[1], e[2])
end

return { laptop = laptop, nvidia = nvidia }
