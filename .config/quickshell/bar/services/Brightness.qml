pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Single source of truth for backlight brightness (OSD, bar slider, quick
// settings). Reads sysfs directly so changes made outside the shell (hypridle
// dimming, brightnessctl in a terminal) show up, and coalesces writes so a fast
// slider drag or a held brightness key always lands on the last value asked for.
Singleton {
    id: root

    property string device: ""
    property int current: 0
    property int max: 1

    readonly property real fraction: max > 0 ? current / max : 0
    readonly property bool available: device !== "" && max > 1

    // Never go fully dark from a relative step or the slider
    readonly property int floor: Math.max(1, Math.round(max * 0.01))

    Process {
        id: deviceResolver
        command: ["sh", "-c", "ls /sys/class/backlight | head -n1"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.device = text.trim()
        }
    }

    FileView {
        id: currentFile
        path: root.device ? "/sys/class/backlight/" + root.device + "/actual_brightness" : ""
        onLoaded: {
            // Don't let a stale read fight an in-flight write
            if (setProc.running || root._pending >= 0) return
            const v = parseInt(text().trim())
            if (!isNaN(v)) root.current = v
        }
    }

    FileView {
        id: maxFile
        path: root.device ? "/sys/class/backlight/" + root.device + "/max_brightness" : ""
        onLoaded: root.max = parseInt(text().trim()) || 1
    }

    // sysfs doesn't emit change notifications, so poll the (cheap) file read
    Timer {
        interval: 2000
        running: root.device !== ""
        repeat: true
        onTriggered: currentFile.reload()
    }

    function refresh() { currentFile.reload() }

    // ── WRITES ─────────────────────────────────────────────────
    property int _pending: -1

    Process {
        id: setProc
        onRunningChanged: {
            if (running) return
            if (root._pending >= 0) root._write(root._pending)
            else currentFile.reload()
        }
    }

    function _write(value) {
        if (setProc.running) {
            root._pending = value
            return
        }
        root._pending = -1
        setProc.command = ["/usr/bin/brightnessctl", "-q", "-d", root.device, "set", String(value)]
        setProc.running = true
    }

    function setRaw(value) {
        if (!root.available) return
        const v = Math.max(root.floor, Math.min(root.max, Math.round(value)))
        root.current = v // optimistic, so repeated steps accumulate
        root._write(v)
    }

    function setPercent(percent) { root.setRaw(root.max * percent / 100) }
    function up() { root.setRaw(root.current + root.max * 0.05) }
    function down() { root.setRaw(root.current - root.max * 0.05) }
}
