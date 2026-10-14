import Quickshell.Io
import QtQuick

Process {
    id: call

    property string script
    property var pendingArgs: null
    readonly property bool hasPending: pendingArgs !== null

    signal result(var data)

    function request(args) {
        if (running) {
            pendingArgs = args
            return
        }
        command = ["python3", script].concat(args)
        running = true
    }

    onRunningChanged: {
        if (running || pendingArgs === null) return
        const args = pendingArgs
        pendingArgs = null
        Qt.callLater(() => call.request(args))
    }

    stdout: StdioCollector {
        onStreamFinished: {
            let data
            try {
                data = JSON.parse(text)
            } catch (err) {
                data = { ok: false, error: "bad-output" }
            }
            call.result(data)
        }
    }
    stderr: StdioCollector {
        onStreamFinished: if (text.trim() !== "") console.warn("[Spotify] stderr:", text)
    }
}
