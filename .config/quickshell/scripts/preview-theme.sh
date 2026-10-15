#!/bin/bash
# Generates a preview theme.json for one wallust preset, WITHOUT touching
# any real app config (alacritty/gtk/hyprland/etc). Reuses the existing
# quickshell-theme.json.hbs template but points it at a scratch file.
set -euo pipefail

wallpaper="$1"     # path to the currently selected wallpaper
preset_config="$2" # e.g. ~/.config/quickshell/wallust-presets/vibrant.toml
# (only needs the global options: backend/color_space/
# palette/saturation/check_contrast — no [templates])
out_json="$3" # e.g. /tmp/wallust-preview-vibrant.json

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
still=$("$script_dir/derive-still.sh" "$wallpaper")

if [ -z "$wallpaper" ] || [ -z "$preset_config" ] || [ -z "$out_json" ]; then
  echo "usage: preview-theme.sh <wallpaper> <preset.toml> <out.json>" >&2
  exit 1
fi

# Pull just the global options out of the preset, in case it has its own
# [templates] section left in by mistake — we don't want that here.
global_opts=$(sed '/^\[templates\]/,$d' "$preset_config")

tmp_toml=$(mktemp --suffix=.toml)
trap 'rm -f "$tmp_toml" "$out_json.tmp"' EXIT

{
  echo "$global_opts"
  echo
  echo "[templates]"
  echo "preview = { template = 'quickshell-theme.json.hbs', target = '$out_json.tmp' }"
} >"$tmp_toml"

wallust run -s -q -C "$tmp_toml" "$still"

# Same color fixes the real apply uses (apply-theme.sh), so the swatches in
# the Theme tab show what will actually be applied. If the fixer fails, the
# raw preview is better than no preview.
profile=$(basename "$preset_config" .toml)
if command -v python3 >/dev/null 2>&1; then
  python3 "$script_dir/palette-fix.py" --profile "$profile" \
    --in "$out_json.tmp" --out "$out_json.tmp" 2>/dev/null || true
fi

mv "$out_json.tmp" "$out_json"
