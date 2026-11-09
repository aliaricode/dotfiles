#!/usr/bin/env bash
# usage: toggle-dp3.sh [output]   (default: DP-3)
# Toggles a secondary display. State is read from Hyprland itself, so it can't drift.
OUTPUT="${1:-DP-3}"

if hyprctl monitors -j | jq -e --arg o "$OUTPUT" 'any(.[]; .name == $o)' >/dev/null; then
  hyprctl eval "hl.monitor({ output = \"$OUTPUT\", disabled = true })" >/dev/null
  notify-send "$OUTPUT disabled"
else
  hyprctl eval "hl.monitor({ output = \"$OUTPUT\", mode = \"preferred\", position = \"0x0\", scale = 1 })" >/dev/null
  notify-send "$OUTPUT enabled"
fi
