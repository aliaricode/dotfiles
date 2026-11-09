#!/bin/bash
# Shared post-processing that runs after `wallust run` succeeds: swaps the
# wallpaper cache, clears fastfetch's cache, reloads hyprland, reapplies blur,
# and syncs RGB if openrgb is running. Sourced by apply-theme.sh so this
# sequence only has to be edited in one place.
set -euo pipefail

post_apply() {
  local -
  set -euo pipefail
  local wallpaper="$1"
  local still="$2"
  local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local theme_dir="$HOME/.config/quickshell/bar"

  if [ -f "$theme_dir/theme.json.new" ]; then
    mv "$theme_dir/theme.json.new" "$theme_dir/theme.json"
  else
    notify-send "Wallust" "theme.json.new missing — shell colors not updated" -u critical
  fi

  # Lockscreen background; ~/Pictures may not exist yet on a fresh install
  mkdir -p ~/Pictures
  if ! magick "$still" ~/Pictures/current.png; then
    notify-send "Wallust" "Theme updated but wallpaper copy failed" -u critical
    return 1
  fi

  local state_dir="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell"
  mkdir -p "$state_dir"
  printf '%s\n' "$wallpaper" >"$state_dir/current-wallpaper"

  rm -rf ~/.cache/fastfetch/

  notify-send "Reloading hypr apps..."
  hyprctl reload
  ~/.config/hypr/scripts/set-blur.sh
  ~/.config/hypr/scripts/gamemode.sh reapply
  if pgrep -x "openrgb" >/dev/null; then
    "$script_dir/update-rgb.sh"
  fi
  notify-send "Colors updated successfully!"
}
