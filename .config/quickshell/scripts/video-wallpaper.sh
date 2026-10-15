#!/bin/bash
# Owns the mpvpaper layer. Keeps a record of which video *should* be
# playing on each monitor so it can be stopped and resumed (battery)
# independently of which wallpaper is applied.
#
#   start <src> [delay] [output]  record + launch after delay
#                                 (no output = every monitor)
#   stop [output]                 kill, keep the record (resumable)
#   resume [output]               relaunch from the record, if any
#   clear [output]                kill + forget
#
# One mpvpaper per monitor. The record holds one "<output>\t<src>" line for
# each monitor that should be playing a video.
set -euo pipefail

state_dir="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell"
record="$state_dir/video-wallpaper"
mkdir -p "$state_dir"

MPV_OPTS="--loop-file=inf --no-audio --hwdec=auto --panscan=1.0"

monitors() {
  local out
  out="$(hyprctl monitors 2>/dev/null | awk '/^Monitor /{print $2}')" || true
  printf '%s\n' "${out:-*}"
}

re_escape() {
  printf '%s' "$1" | sed 's#[][\.*^$+?(){}|/]#\\&#g'
}

kill_output() {
  pkill -f -- "^([^ ]*/)?mpvpaper .* $(re_escape "$1") " 2>/dev/null || true
}

launch() { # <output> <src>
  kill_output "$1"
  setsid mpvpaper -f -s -o "$MPV_OPTS" "$1" "$2" </dev/null >/dev/null 2>&1 &
}

migrate_record() {
  [ -s "$record" ] || return 0
  if grep -q $'\t' "$record"; then return 0; fi
  local src o
  src="$(head -n1 "$record")"
  : >"$record"
  while IFS= read -r o; do
    printf '%s\t%s\n' "$o" "$src" >>"$record"
  done < <(monitors)
}

record_get() {
  [ -s "$record" ] || return 0
  awk -F'\t' -v o="$1" '$1 == o { print $2; exit }' "$record"
}

record_drop() {
  [ -e "$record" ] || return 0
  local tmp
  tmp="$(mktemp "$record.XXXXXX")"
  awk -F'\t' -v o="$1" '$1 != o' "$record" >"$tmp"
  if [ -s "$tmp" ]; then
    mv "$tmp" "$record"
  else
    rm -f "$tmp" "$record"
  fi
}

record_set() {
  record_drop "$1"
  printf '%s\t%s\n' "$1" "$2" >>"$record"
}

case "${1:-}" in
start)
  src="${2:-}"
  delay="${3:-0}"
  output="${4:-}"
  [ -n "$src" ] || exit 1
  migrate_record
  if [ -n "$output" ]; then
    targets=("$output")
  else
    mapfile -t targets < <(monitors)
    rm -f "$record"
  fi
  for o in "${targets[@]}"; do
    record_set "$o" "$src"
  done
  setsid "$0" _delayed "$src" "$delay" "${targets[@]}" >/dev/null 2>&1 &
  ;;
_delayed)
  src="$2"
  delay="$3"
  shift 3
  sleep "$delay"
  for o in "$@"; do
    if [ "$(record_get "$o")" = "$src" ]; then
      launch "$o" "$src"
    fi
  done
  ;;
stop)
  if [ -n "${2:-}" ]; then
    kill_output "$2"
  else
    pkill -x mpvpaper 2>/dev/null || true
  fi
  ;;
resume)
  migrate_record
  [ -s "$record" ] || exit 0
  while IFS=$'\t' read -r o s; do
    [ -n "$o" ] || continue
    if [ -z "${2:-}" ] || [ "$o" = "$2" ]; then
      launch "$o" "$s"
    fi
  done <"$record"
  ;;
clear)
  if [ -n "${2:-}" ]; then
    migrate_record
    record_drop "$2"
    kill_output "$2"
  else
    rm -f "$record"
    pkill -x mpvpaper 2>/dev/null || true
  fi
  ;;
*)
  echo "usage: video-wallpaper.sh start <src> [delay] [output]" >&2
  echo "       video-wallpaper.sh <stop|resume|clear> [output]" >&2
  exit 1
  ;;
esac
