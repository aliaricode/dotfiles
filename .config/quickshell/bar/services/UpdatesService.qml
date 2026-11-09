pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // repo updates via `checkupdates` (pacman-contrib) sync a throwaway
    // copy of the pacman db, so no root/password prompt is needed.
    // AUR updates via `paru -Qua` hit the AUR RPC directly, same deal.
    property var repoUpdates: []
    property var aurUpdates: []
    readonly property var packages: [...root.repoUpdates, ...root.aurUpdates]
    readonly property int pendingCount: root.packages.length

    readonly property bool checking: repoCheck.running || aurCheck.running
    property bool updating: false

    function parseUpdateLines(text, source) {
        if (!text) return []
        return text.trim().split("\n").filter(l => l.trim() !== "").map(line => {
            const parts = line.trim().split(/\s+/)
            return {
                name: parts[0] ?? line,
                oldVersion: parts[1] ?? "",
                newVersion: parts[3] ?? "",
                source: source
            }
        })
    }

    // Results are only applied on a clean exit, so a failed check (offline,
    // mirror down) keeps the last known list instead of resetting it to 0.
    // checkupdates exits 2 for "no updates"; paru -Qua exits 1 for the same.
    Process {
        id: repoCheck
        command: ["checkupdates"]
        property string out: ""
        stdout: StdioCollector { onStreamFinished: repoCheck.out = text }
        onExited: (code) => {
            if (code === 0 || code === 2)
                root.repoUpdates = root.parseUpdateLines(code === 0 ? out : "", "repo")
        }
    }

    Process {
        id: aurCheck
        command: ["paru", "-Qua"]
        property string out: ""
        stdout: StdioCollector { onStreamFinished: aurCheck.out = text }
        onExited: (code) => {
            if (code === 0 || out.trim() === "")
                root.aurUpdates = root.parseUpdateLines(code === 0 ? out : "", "aur")
        }
    }

    function refresh() {
        repoCheck.running = true
        aurCheck.running = true
    }

    Process {
        id: updateProc
        // --hold keeps the window open so errors can be read before closing it
        command: [Quickshell.env("TERMINAL") || "alacritty", "--hold", "-e", "paru"]
        onRunningChanged: root.updating = running
        onExited: root.refresh()
    }

    function runUpdate() {
        if (root.updating) return
        updateProc.running = true
    }

    Timer {
        interval: 30 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: false
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()
}
