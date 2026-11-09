pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Mirrors ~/.config/hypr/scripts/gamemode.sh, whose state file says whether
// game mode is on (it can also be toggled with Super+Shift+G).
Singleton {
    id: root

    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/gamemode.sh"
    readonly property string stateFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/hypr-gamemode"

    property bool active: false
    readonly property bool busy: toggleProc.running

    Process {
        id: check
        command: ["test", "-f", root.stateFile]
        onExited: (code) => root.active = code === 0
    }

    function refresh() { if (!check.running) check.running = true }

    Process {
        id: toggleProc
        command: [root.script]
        onExited: root.refresh()
    }

    function toggle() {
        if (toggleProc.running) return
        toggleProc.running = true
    }

    Component.onCompleted: refresh()
}
