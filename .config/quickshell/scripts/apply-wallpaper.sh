#!/bin/bash
# Top layer: puts a wallpaper on screen AND regenerates colors.
# Colour-only changes (preset switching) call apply-theme.sh directly so
# they don't re-trigger a display transition.
#
# usage: apply-wallpaper.sh <source> [preset.toml] [--output NAME] [--no-theme]
#   --output NAME  only change that monitor (default: every monitor)
#   --no-theme     skip colour generation (for monitors that don't drive the theme)
set -euo pipefail

output=""
theme=1
positional=()
while [ $# -gt 0 ]; do
  case "$1" in
  --output)
    if [ $# -lt 2 ]; then
      notify-send "Wallpaper" "--output needs a monitor name" -u critical
      exit 1
    fi
    output="$2"
    shift 2
    ;;
  --no-theme)
    theme=0
    shift
    ;;
  *)
    positional+=("$1")
    shift
    ;;
  esac
done

source_img="${positional[0]:-}"
preset_config="${positional[1]:-}"

if [ -z "$source_img" ]; then
  notify-send "Wallpaper" "No wallpaper path given" -u critical
  exit 1
fi

TRANS_TYPE="${AWWW_TRANSITION_TYPE:-grow}"
TRANS_POS="${AWWW_TRANSITION_POS:-center}"
TRANS_DUR="${AWWW_TRANSITION_DURATION:-0.7}"
TRANS_FPS="${AWWW_TRANSITION_FPS:-144}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
still=$("$script_dir/derive-still.sh" "$source_img")

# Drop any existing video layer first so awww's transition is visible.
# With --output, only that monitor's video layer should go.
"$script_dir/video-wallpaper.sh" clear ${output:+"$output"}

awww_args=(--transition-type "$TRANS_TYPE" --transition-pos "$TRANS_POS"
  --transition-duration "$TRANS_DUR" --transition-fps "$TRANS_FPS")
if [ -n "$output" ]; then
  awww_args+=(--outputs "$output")
fi

case "${source_img,,}" in
*.mp4 | *.webm | *.mkv | *.mov)
  awww img "$still" "${awww_args[@]}"
  "$script_dir/video-wallpaper.sh" start "$source_img" "$TRANS_DUR" ${output:+"$output"}
  ;;
*)
  awww img "$source_img" "${awww_args[@]}"
  ;;
esac

state="$HOME/.cache/quickshell/monitor-wallpapers.json"

save_monitor_state() {
  command -v jq >/dev/null 2>&1 || return 1
  local outs=()
  if [ -n "$output" ]; then
    outs=("$output")
  else
    mapfile -t outs < <(hyprctl monitors -j | jq -r '.[].name')
  fi
  [ "${#outs[@]}" -gt 0 ] || return 1
  mkdir -p "$(dirname "$state")"
  [ -s "$state" ] || echo '{}' >"$state"
  local tmp
  tmp="$(mktemp "$state.XXXXXX")"
  if jq --arg p "$source_img" 'reduce $ARGS.positional[] as $o (.; .[$o] = $p)' \
    --args "${outs[@]}" <"$state" >"$tmp"; then
    mv "$tmp" "$state"
  else
    rm -f "$tmp"
    return 1
  fi
}

if ! save_monitor_state; then
  notify-send "Wallpaper" "Couldn't save the per-monitor wallpaper map (needs jq and hyprctl)"
fi

if [ "$theme" -eq 1 ]; then
  "$script_dir/apply-theme.sh" "$source_img" "$preset_config"
fi
