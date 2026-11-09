pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Windscribe (windscribe-cli) and Tailscale status + toggles for Quick
// Settings. Both CLIs are slow-ish, so they're only polled while someone is
// looking (Quick Settings open) and right after a toggle.
Singleton {
    id: root

    // Set while Quick Settings is open
    property bool polling: false
    onPollingChanged: if (polling) refresh()

    function refresh() {
        if (!wsCheck.running) wsCheck.running = true
        if (!tsStatus.running) tsStatus.running = true
    }

    Timer {
        interval: 5000
        repeat: true
        running: root.polling
        onTriggered: root.refresh()
    }

    function notify(summary, body) {
        Quickshell.execDetached(["notify-send", "-a", "VPN", summary, body])
    }

    // ── WINDSCRIBE ─────────────────────────────────────────────
    // windscribe-cli starts the Windscribe app if it isn't running, so the
    // CLI is only asked for status while the app already runs. Otherwise the
    // tile just shows "Off" and pressing it is what launches + connects.
    property bool wsAvailable: false
    property bool wsAppRunning: false
    // "Connected" | "Disconnected" | "Connecting" | "Disconnecting" | ""
    property string wsState: ""
    property string wsLocation: ""
    readonly property bool wsConnected: wsState === "Connected"
    readonly property bool wsBusy: wsToggle.running || wsState.endsWith("ing")

    Process {
        id: wsCheck
        // 127 = not installed, 1 = installed but the app isn't running
        command: ["sh", "-c", "command -v windscribe-cli >/dev/null || exit 127; pgrep -x Windscribe >/dev/null"]
        onExited: (code) => {
            root.wsAvailable = code !== 127
            root.wsAppRunning = code === 0
            if (root.wsAppRunning) {
                if (!wsStatus.running) wsStatus.running = true
            } else if (!wsToggle.running) {
                root.wsState = "Disconnected"
                root.wsLocation = ""
            }
        }
    }

    Process {
        id: wsStatus
        command: ["windscribe-cli", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                // Output mixes JSON log lines with "Key: value" lines
                const state = /Connect state:\s*([A-Za-z]+)/.exec(text)
                root.wsState = state ? state[1] : ""
                const loc = /Connected to:?\s*([^\n"\\]+)/.exec(text)
                root.wsLocation = loc ? loc[1].trim() : ""
            }
        }
    }

    Process {
        id: wsToggle
        onExited: (code) => {
            if (code !== 0) root.notify("Windscribe", "Couldn't change the connection. Is the Windscribe app logged in?")
            root.refresh()
        }
    }

    function toggleWindscribe() {
        if (wsToggle.running) return
        wsToggle.command = ["windscribe-cli", root.wsConnected ? "disconnect" : "connect"]
        root.wsState = root.wsConnected ? "Disconnecting" : "Connecting"
        wsToggle.running = true
    }

    // ── TAILSCALE ──────────────────────────────────────────────
    property bool tsAvailable: false
    // tailscaled BackendState: Running | Stopped | NeedsLogin | NoState | Starting
    property string tsState: ""
    readonly property bool tsLoggedIn: tsState === "Running" || tsState === "Stopped" || tsState === "Starting"
    readonly property bool tsConnected: tsState === "Running"

    Process {
        id: tsStatus
        command: ["sh", "-c", "command -v tailscale >/dev/null || exit 127; tailscale status --json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.tsState = JSON.parse(text).BackendState || "" }
                catch (e) { root.tsState = "" }
            }
        }
        onExited: (code) => root.tsAvailable = code !== 127
    }

    Process {
        id: tsToggle
        property string err: ""
        stderr: StdioCollector { onStreamFinished: tsToggle.err = text }
        onExited: (code) => {
            if (code !== 0) {
                // Without an operator, only root may bring tailscale up/down
                const perm = /access denied|operator|permission/i.test(tsToggle.err)
                root.notify("Tailscale", perm
                    ? "Needs permission once: sudo tailscale set --operator=$USER"
                    : (tsToggle.err.trim().split("\n").pop() || "Command failed"))
            }
            root.refresh()
        }
    }

    function toggleTailscale() {
        if (tsToggle.running) return
        tsToggle.command = ["tailscale", root.tsConnected ? "down" : "up"]
        tsToggle.running = true
    }

    Component.onCompleted: refresh()
}
