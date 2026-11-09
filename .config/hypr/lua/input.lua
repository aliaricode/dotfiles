-- ~/.config/hypr/lua/input.lua

-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
-- ┃                     Input Configuration                     ┃
-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

hl.config({
	input = {
		follow_mouse = 2,
		float_switch_override_focus = 2,
		-- kb_layout is per machine (machine.lua): the first entry is the default
		kb_options = "grp:alt_shift_toggle",
		accel_profile = "flat",
		sensitivity = 0.0,
	},
})
