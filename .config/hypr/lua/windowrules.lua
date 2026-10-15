-- ~/.config/hypr/lua/windowrules.lua

-- ============================================================
-- 1. TAG DEFINITIONS
-- ============================================================

-- Browsers
local browsers =
	"([Ff]irefox|org.mozilla.firefox|[Ff]irefox-esr|[Gg]oogle-chrome|[Cc]hromium|[Mm]icrosoft-edge|Brave-browser|[Tt]horium-browser|[Cc]achy-browser|zen-alpha|zen)"
hl.window_rule({ match = { class = "^" .. browsers .. "$" }, tag = "+browser" })

-- Terminal
hl.window_rule({
	match = { class = "^(Alacritty|kitty|kitty-dropterm|KWrite|lotm-editor|lotm-scripts|lotm-lookup)$" },
	tag = "+terminal",
})

-- Projects / IDEs
hl.window_rule({
	match = { class = "^(codium|codium-url-handler|VSCodium|[Cc]ode|vscode|code-url-handler|jetbrains-.+)$" },
	tag = "+projects",
})

-- Instant Messaging
hl.window_rule({
	match = {
		class = "^([Dd]iscord|[Ww]ebCord|[Vv]esktop|[Ff]erdium|[Ww]hatsapp-for-linux|ZapZap|com.rtosta.zapzap|org.telegram.desktop|teams-for-linux|im.riot.Riot|Element)$",
	},
	tag = "+im",
})

-- Email
hl.window_rule({ match = { class = "^([Tt]hunderbird|org.gnome.Evolution|eu.betterbird.Betterbird)$" }, tag = "+email" })

-- File Managers
hl.window_rule({
	match = { class = "^([Tt]hunar|org.gnome.Nautilus|[Pp]cmanfm-qt|app.drey.Warp)$" },
	tag = "+file-manager",
})

-- Multimedia
hl.window_rule({ match = { class = "^([Aa]udacious)$" }, tag = "+multimedia" })
hl.window_rule({ match = { class = "^([Mm]pv|vlc)$" }, tag = "+multimedia_video" })

hl.window_rule({ match = { class = "^(com\\.github\\.th_ch\\.youtube_music)$" }, tag = "+music" })

-- Games
hl.window_rule({ match = { class = "^(gamescope)$" }, tag = "+games" })
hl.window_rule({ match = { class = "^(steam_app_[0-9]+)$" }, tag = "+games" })

-- Game Stores
hl.window_rule({ match = { class = "^([Ss]team)$" }, tag = "+gamestore" })
hl.window_rule({ match = { class = "^(com.heroicgameslauncher.hgl)$" }, tag = "+gamestore" })

-- Settings
hl.window_rule({ match = { class = "^(nm-applet|nm-connection-editor|blueman-manager)$" }, tag = "+settings" })
hl.window_rule({
	match = { class = "^(pavucontrol|org.pulseaudio.pavucontrol|com.saivert.pwvucontrol)$" },
	tag = "+settings",
})
hl.window_rule({ match = { class = "^(qt5ct|qt6ct|[Yy]ad)$" }, tag = "+settings" })
hl.window_rule({ match = { class = "^(nwg-displays|nwg-look)$" }, tag = "+settings" })
hl.window_rule({ match = { class = "^(gnome-disks|file-roller|org.gnome.FileRoller)$" }, tag = "+settings" })
hl.window_rule({ match = { title = "^(ROG Control)$" }, tag = "+settings" })

-- Viewers
hl.window_rule({
	match = { class = "^(gnome-system-monitor|org.gnome.SystemMonitor|io.missioncenter.MissionCenter)$" },
	tag = "+viewer",
})
hl.window_rule({ match = { class = "^(evince|eog|org.gnome.Loupe)$" }, tag = "+viewer" })

-- Screenshare
hl.window_rule({ match = { class = "^(com.obsproject.Studio)$" }, tag = "+screenshare" })

-- ============================================================
-- 2. OPACITY RULES (Dynamic)
-- ============================================================

hl.window_rule({ match = { tag = "browser*" }, opacity = "0.9 0.9" })
hl.window_rule({ match = { tag = "projects*" }, opacity = "0.9 0.9" })
hl.window_rule({ match = { tag = "im*" }, opacity = "0.94 0.86" })
hl.window_rule({ match = { tag = "multimedia*" }, opacity = "0.94 0.94" })
hl.window_rule({ match = { tag = "file-manager*" }, opacity = "0.85 0.85" })
hl.window_rule({ match = { tag = "terminal*" }, opacity = "0.9 0.9" })
hl.window_rule({ match = { tag = "settings*" }, opacity = "0.85 0.85" })
hl.window_rule({ match = { tag = "viewer*" }, opacity = "0.82 0.75" })
hl.window_rule({ match = { tag = "music*" }, opacity = "0.9 0.9" })
hl.window_rule({ match = { class = "^(gedit|org.gnome.TextEditor|mousepad)$" }, opacity = "0.8 0.8" })
hl.window_rule({ match = { class = "^(deluge)$" }, opacity = "0.9 0.8" })
hl.window_rule({ match = { class = "^(seahorse)$" }, opacity = "0.9 0.8" })

-- Video: force opaque
hl.window_rule({ match = { tag = "multimedia_video*" }, no_blur = true })
hl.window_rule({ match = { tag = "multimedia_video*" }, opacity = "1.0 override" })

-- ============================================================
-- 3. FLOAT RULES (Static)
-- ============================================================

hl.window_rule({ match = { tag = "settings*" }, float = true })
hl.window_rule({ match = { tag = "viewer*" }, float = true })
hl.window_rule({ match = { class = "^([Ff]erdium)$" }, float = true })
hl.window_rule({ match = { class = "^(mpv|com.github.rafostar.Clapper)$" }, float = true })
hl.window_rule({ match = { class = "^([Qq]alculate-gtk)$" }, float = true })
hl.window_rule({ match = { class = "^([Zz]oom)$" }, float = true })
hl.window_rule({ match = { class = "^(org.gnome.Calculator)$", title = "^(Calculator)$" }, float = true })

-- Popups & Dialogs
hl.window_rule({ match = { title = "^(Authentication Required)$" }, float = true, center = true })
hl.window_rule({
	match = { title = "^(Add Folder to Workspace)$" },
	float = true,
	center = true,
	size = { "70%", "60%" },
})
hl.window_rule({ match = { title = "^(Save As)$" }, float = true, center = true, size = { "70%", "60%" } })
hl.window_rule({
	match = { class = "^(pavucontrol|org.pulseaudio.pavucontrol)$" },
	float = true,
	center = true,
	size = { 800, 600 },
})
hl.window_rule({ match = { class = "^([Ss]team)$", title = "negative:^([Ss]team)$" }, float = true })
hl.window_rule({
	match = { class = "^(com.heroicgameslauncher.hgl)$", title = "negative:(Heroic Games Launcher)" },
	float = true,
})

-- ============================================================
-- 4. CENTER RULES
-- ============================================================

hl.window_rule({ match = { title = "^(ROG Control)$" }, center = true })
hl.window_rule({
	match = { class = "^(pavucontrol|org.pulseaudio.pavucontrol|com.saivert.pwvucontrol)$" },
	center = true,
})
hl.window_rule({ match = { class = "^([Ff]erdium)$" }, center = true })
hl.window_rule({ match = { class = "^([Ww]hatsapp-for-linux|ZapZap|com.rtosta.zapzap)$" }, center = true })

-- ============================================================
-- 5. SIZE RULES
-- ============================================================

hl.window_rule({ match = { tag = "settings*" }, size = { "70%", "70%" } })
hl.window_rule({ match = { class = "^([Ww]hatsapp-for-linux|ZapZap|com.rtosta.zapzap)$" }, size = { "60%", "70%" } })
hl.window_rule({ match = { class = "^([Ff]erdium)$" }, size = { "60%", "70%" } })

-- ============================================================
-- 6. PICTURE IN PICTURE
-- ============================================================

hl.window_rule({
	match = { title = "^(Picture-in-Picture)$" },
	float = true,
	pin = true,
	move = { "72%", "7%" },
	opacity = "0.95 override 0.75 override",
	keep_aspect_ratio = true,
})

-- ============================================================
-- 7. WORKSPACE ASSIGNMENTS
-- ============================================================

hl.window_rule({ match = { tag = "gamestore*" }, workspace = "10" })
hl.window_rule({ match = { tag = "games*" }, workspace = "5" })
hl.window_rule({ match = { tag = "screenshare*" }, workspace = "4 silent" })

-- ============================================================
-- 8. GAME / PERFORMANCE RULES
-- ============================================================

hl.window_rule({ match = { tag = "games*" }, no_blur = true, fullscreen = true })
hl.window_rule({ match = { class = "^([Ss]team)$" }, suppress_event = "maximize" })

-- ============================================================
-- 9. BORDER COLORS
-- ============================================================

hl.window_rule({ match = { fullscreen = true }, border_color = "rgb(EE4B55) rgb(880808)" })
hl.window_rule({ match = { float = true }, border_color = "rgb(282737) rgb(1E1D2D)" })

-- ============================================================
-- 10. MISC APP FIXES
-- ============================================================

hl.window_rule({ match = { class = "^(jetbrains-.+)$" }, no_initial_focus = true })

hl.window_rule({
	match = { tag = "music*" },
	workspace = "special:music silent",
	float = true,
	size = { 1400, 850 },
	max_size = { 1400, 850 },
	min_size = { 1400, 850 },
	center = true,
	opacity = "0.85",
	suppress_event = "maximize fullscreen",
})

-- Screenshare bridge
hl.window_rule({
	match = { class = "^(xwaylandvideobridge)$" },
	opacity = "0.0 override 0.0 override",
	no_anim = true,
	no_focus = true,
	no_initial_focus = true,
})

-- ============================================================
-- 11. IDLE INHIBIT
-- ============================================================

hl.window_rule({ match = { fullscreen = true }, idle_inhibit = "fullscreen" })

-- ============================================================
-- 12. LAYER RULES
-- ============================================================

hl.layer_rule({ match = { namespace = "quickshell:bar" }, blur = true, blur_popups = true, ignore_alpha = 0.1 })
hl.layer_rule({ match = { namespace = "wallpaper" }, blur = true, ignore_alpha = 0.05, no_anim = true })
hl.layer_rule({ match = { namespace = "quickshell:toast" }, blur = true, ignore_alpha = 0.05, no_anim = true })
hl.layer_rule({ match = { namespace = "launcher" }, blur = true, ignore_alpha = 0.05, no_anim = true })
hl.layer_rule({ match = { namespace = "clipboard" }, blur = true, ignore_alpha = 0.05, no_anim = true })

-- ============================================================
-- 13. WORKSPACE RULES
-- ============================================================

hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
hl.workspace_rule({ workspace = "f[1]", gaps_out = 0, gaps_in = 0 })
hl.window_rule({ match = { float = false, workspace = "w[tv1]" }, border_size = 0, rounding = 0 })
hl.window_rule({ match = { float = false, workspace = "f[1]" }, border_size = 0, rounding = 0 })
