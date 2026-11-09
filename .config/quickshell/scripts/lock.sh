#!/usr/bin/env bash
# Single entry point for the Quickshell lockscreen (autostart, Super+L, hypridle).
#
# usage: lock.sh           lock now
#        lock.sh --start   start the lockscreen instance at login, already locked
#
# Locking normally just pings the running lockscreen over IPC. If that instance
# has died, the IPC call fails, so a fresh one is started already locked instead
# of silently leaving the session unlocked (e.g. before suspend).
LOCK_QML="$HOME/.config/quickshell/lockscreen/lock.qml"

start_locked() {
  QS_START_LOCKED=1 exec quickshell -n -p "$LOCK_QML" "$@"
}

if [ "${1:-}" = "--start" ]; then
  start_locked
fi

if ! quickshell -p "$LOCK_QML" ipc call lock lock >/dev/null 2>&1; then
  start_locked -d
fi
