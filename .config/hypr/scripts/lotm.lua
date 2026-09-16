-- ~/.config/hypr/lotm.lua

local M = {}

-- ─── config ──────────────────────────────────────────────────────────────────

local WS_BROWSER = 1
local WS_TERMS = 2

local HOME = os.getenv("HOME")
local EDITOR_DIR = HOME .. "/Projects/LotM/Imperium34.github.io"
local SCRIPTS_DIR = HOME .. "/Projects/LotM/Scripts"

local TERM = "alacritty"

local EDITOR_CLASS = "lotm-editor"
local SCRIPTS_CLASS = "lotm-scripts"
local LOOKUP_CLASS = "lotm-lookup"

local SPECIAL = "lotm"

local LOOKUP_CMD = nil

local EDITOR_CMD = nil

local ZEN = "zen-browser"
local ZEN_PREFIX = "zen"

-- ─── helpers ─────────────────────────────────────────────────────────────────

local function find_class(name)
	for _, w in pairs(hl.get_windows()) do
		if w.class and string.lower(w.class) == name then
			return w
		end
	end
	return nil
end

local function find_class_prefix(prefix)
	for _, w in pairs(hl.get_windows()) do
		if w.class and string.sub(string.lower(w.class), 1, #prefix) == prefix then
			return w
		end
	end
	return nil
end

local function term_cmd(class, dir, exec)
	local cmd = string.format('%s --class %s --working-directory "%s"', TERM, class, dir)
	if exec then
		cmd = cmd .. " -e " .. exec
	end
	return cmd
end

local awaiting = nil

hl.on("window.open", function(w)
	if not awaiting or not w.class or w.class ~= awaiting.class then
		return
	end
	local step = awaiting.run
	awaiting = nil
	hl.timer(step, { timeout = 100, type = "oneshot" })
end)

local function open_scripts_term()
	hl.exec_cmd(term_cmd(SCRIPTS_CLASS, SCRIPTS_DIR))
end

local function open_editor_term(then_open_scripts)
	if then_open_scripts then
		awaiting = {
			class = EDITOR_CLASS,
			run = function()
				hl.dispatch(hl.dsp.layout("preselect r"))
				open_scripts_term()
			end,
		}
	end
	hl.exec_cmd(term_cmd(EDITOR_CLASS, EDITOR_DIR, EDITOR_CMD))
end

-- ─── window rules ────────────────────────────────────────────────────────────

hl.window_rule({
	name = "lotm-terminals",
	match = { class = "^(" .. EDITOR_CLASS .. "|" .. SCRIPTS_CLASS .. ")$" },
	workspace = tostring(WS_TERMS),
})

hl.window_rule({
	name = "lotm-lookup-scratchpad",
	match = { class = "^" .. LOOKUP_CLASS .. "$" },
	workspace = "special:" .. SPECIAL .. " silent",
})

-- ─── entry point ─────────────────────────────────────────────────────────────

function M.setup()
	if not find_class_prefix(ZEN_PREFIX) then
		hl.exec_cmd(ZEN, { workspace = WS_BROWSER .. " silent" })
	end

	local editor = find_class(EDITOR_CLASS)
	local scripts = find_class(SCRIPTS_CLASS)

	hl.dispatch(hl.dsp.focus({ workspace = WS_TERMS }))

	if editor and scripts then
		hl.notification.create({ text = "LotM workspace already up", timeout = 2000, icon = "ok" })
		return
	end

	if not editor then
		open_editor_term(not scripts)
	elseif not scripts then
		open_scripts_term()
	end
end

function M.lookup()
	if not find_class(LOOKUP_CLASS) then
		hl.exec_cmd(term_cmd(LOOKUP_CLASS, SCRIPTS_DIR, LOOKUP_CMD))
	end
	hl.dispatch(hl.dsp.workspace.toggle_special(SPECIAL))
end

_G.LotM = M

return M
