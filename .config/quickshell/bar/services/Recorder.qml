pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

// Screen recording through gpu-screen-recorder (hardware encoding, so it's
// cheap on both the NVIDIA desktop and the Intel laptop). Stopping sends
// SIGINT, which makes gsr finish writing the file cleanly.
Singleton {
    id: root

    readonly property string outputDir: Quickshell.env("HOME") + "/Videos/Recordings"

    property bool available: false
    property bool recording: false
    property bool selecting: false
    property string file: ""
    property real startedAt: 0
    property int elapsed: 0

    readonly property string elapsedLabel: {
        const m = Math.floor(root.elapsed / 60)
        const s = root.elapsed % 60
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    Process {
        command: ["sh", "-c", "command -v gpu-screen-recorder"]
        running: true
        onExited: (code) => root.available = code === 0
    }

    // kind: "region" | "screen"; audio records the default output (desktop audio)
    function start(kind, audio) {
        if (root.recording || root.selecting) return
        if (!root.available) {
            root.notify("normal", "Recording unavailable", "Install the gpu-screen-recorder package")
            return
        }
        root._audio = !!audio
        if (kind === "region") {
            root.selecting = true
            slurp.running = true
        } else {
            const mon = Hyprland.focusedMonitor
            root._launch(["-w", mon ? mon.name : "screen"])
        }
    }

    function stop() {
        if (root.recording) recProc.signal(2)
    }

    function toggleStop() { root.stop() }

    property bool _audio: false

    Process {
        id: slurp
        command: ["slurp", "-f", "%wx%h+%x+%y"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.selecting = false
                const geom = text.trim()
                // Empty output = selection cancelled with Esc
                if (geom !== "") root._launch(["-w", "region", "-region", geom])
            }
        }
    }

    function _launch(targetArgs) {
        const stamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss") // local time
        root.file = root.outputDir + "/" + stamp + ".mp4"
        let cmd = ["gpu-screen-recorder"].concat(targetArgs, ["-f", "60", "-o", root.file])
        if (root._audio) cmd = cmd.concat(["-a", "default_output"])
        recProc.command = ["sh", "-c", 'mkdir -p "$1" && shift && exec "$@"', "sh", root.outputDir].concat(cmd)
        recProc.running = true
    }

    Process {
        id: recProc
        property string err: ""
        stderr: StdioCollector { onStreamFinished: recProc.err = text }
        onRunningChanged: {
            if (running) {
                root.recording = true
                root.startedAt = Date.now()
                root.elapsed = 0
            }
        }
        onExited: (code) => {
            root.recording = false
            // gsr exits 0 after SIGINT once the file is finalized
            if (code === 0) {
                root.notify("normal", "Recording saved", root.file.replace(Quickshell.env("HOME"), "~"))
            } else {
                const lines = recProc.err.trim().split("\n")
                root.notify("critical", "Recording failed", lines[lines.length - 1] || ("exit code " + code))
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.recording
        onTriggered: root.elapsed = Math.floor((Date.now() - root.startedAt) / 1000)
    }

    function notify(urgency, summary, body) {
        Quickshell.execDetached(["notify-send", "-a", "Recorder", "-u", urgency, summary, body])
    }

    IpcHandler {
        target: "recorder"
        function stop(): void { root.stop() }
        function screen(): void { root.start("screen", false) }
        function region(): void { root.start("region", false) }
    }
}
