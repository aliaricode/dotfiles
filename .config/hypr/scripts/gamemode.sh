#!/usr/bin/env bash
# usage: gamemode.sh [reapply]
# Toggle a stripped-down "game mode" (no animations/blur/gaps/rounding).
# Uses `hyprctl eval` because the Lua config has no `hyprctl keyword`.
#   reapply  re-apply game mode if it is on -- called after `hyprctl reload`
#            (e.g. post-apply.sh), which would otherwise silently undo it

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/hypr-gamemode"

apply() {
  hyprctl eval 'hl.config({
    animations = { enabled = false },
    decoration = { rounding = 0, fullscreen_opacity = 1, shadow = { enabled = false }, blur = { enabled = false } },
    general = { gaps_in = 0, gaps_out = 0, border_size = 1 },
  })' >/dev/null
}

if [ "${1:-}" = "reapply" ]; then
  [ -f "$STATE_FILE" ] && apply
  exit 0
fi

if [ ! -f "$STATE_FILE" ]; then
  apply
  touch "$STATE_FILE"
  notify-send "Gamemode [ON]"
else
  rm -f "$STATE_FILE"
  hyprctl reload >/dev/null
  ~/.config/hypr/scripts/set-blur.sh
  notify-send "Gamemode [OFF]"
fi
