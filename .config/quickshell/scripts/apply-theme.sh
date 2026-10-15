#!/bin/bash
# Generates colors from a wallpaper and renders every wallust template.
#
# Flow (the extra middle step is palette-fix.py, see its header):
#   1. wallust run -> raw palette, written to a scratch JSON (no real templates)
#   2. palette-fix -> same hues, readable lightness/chroma, repaired ANSI row
#   3. wallust cs  -> renders ALL the real templates + terminal sequences from
#                     the fixed palette
# If any of that fails we fall back to the old single `wallust run`, so a bug
# in the fixer can never leave you without a theme.
set -euo pipefail

wallpaper="${1:-}"
preset_config="${2:-}" # optional: a preset's global-options-only toml.
# Empty = current default behavior (main wallust.toml).

if [ -z "$wallpaper" ]; then
  notify-send "Wallust" "No wallpaper path given" -u critical
  exit 1
fi

notify-send "Running Wallust"

tmp_files=()
cleanup() {
  if [ "${#tmp_files[@]}" -gt 0 ]; then
    rm -f "${tmp_files[@]}"
  fi
  return 0
}
trap cleanup EXIT

run_config="$HOME/.config/wallust/wallust.toml"

if [ -n "$preset_config" ]; then
  # Merge the preset's color-generation mood with the REAL templates list,
  # so applying a preset still updates alacritty/gtk/hyprland/etc, exactly
  # like a normal wallpaper change does today. This keeps the templates
  # list defined in ONE place (your real wallust.toml) so it never drifts
  # out of sync with the presets.
  preset_opts=$(sed '/^\[templates\]/,$d' "$preset_config")
  real_templates=$(sed -n '/^\[templates\]/,$p' "$run_config")

  tmp_toml=$(mktemp --suffix=.toml)
  tmp_files+=("$tmp_toml")
  {
    echo "$preset_opts"
    echo
    echo "$real_templates"
  } >"$tmp_toml"

  run_config="$tmp_toml"
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

lock_dir="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell"
mkdir -p "$lock_dir"
exec 9>"$lock_dir/apply.lock"
flock 9

still=$("$script_dir/derive-still.sh" "$wallpaper")

# palette-fix profile = preset name ("default" for a plain wallpaper change)
profile="default"
if [ -n "$preset_config" ]; then
  profile=$(basename "$preset_config" .toml)
fi

apply_fixed_palette() {
  command -v python3 >/dev/null 2>&1 || return 1

  local raw_toml raw_json fixed_json
  raw_toml=$(mktemp --suffix=.toml)
  raw_json=$(mktemp --suffix=.json)
  fixed_json=$(mktemp --suffix=.json)
  tmp_files+=("$raw_toml" "$raw_json" "$fixed_json")

  # Same color options as the real run, but the only template is the pywal
  # style JSON that palette-fix.py and `wallust cs` both understand.
  {
    sed '/^\[templates\]/,$d' "$run_config"
    echo
    echo "[templates]"
    echo "raw = { template = 'wallust-json.hbs', target = '$raw_json' }"
  } >"$raw_toml"

  wallust run -s -q -C "$raw_toml" "$still" || return 1
  python3 "$script_dir/palette-fix.py" --profile "$profile" --in "$raw_json" --out "$fixed_json" || return 1
  wallust cs -f pywal -C "$run_config" "$fixed_json" || return 1
}

if ! apply_fixed_palette; then
  notify-send "Wallust" "Palette fix failed, applying the unfixed colors" -u normal
  if ! wallust run -C "$run_config" "$still"; then
    notify-send "Wallust failed" "Check the image format/path" -u critical
    exit 1
  fi
fi

source "$script_dir/post-apply.sh"
post_apply "$wallpaper" "$still"
