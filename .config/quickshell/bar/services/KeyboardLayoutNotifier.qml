import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

// Each machine has one intended layout (see machine.lua), so a layout switch
// is almost always an accidental Alt+Shift. Flash a notification when it
// happens so it doesn't go unnoticed.
QtObject {
    id: root

    property string current: ""

    // Seed from the main keyboard so startup doesn't count as a "switch"
    readonly property Process seed: Process {
        command: ["hyprctl", "devices", "-j"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const main = JSON.parse(text).keyboards.find(k => k.main)
                    if (main && root.current === "") root.current = main.active_keymap
                } catch (e) {}
            }
        }
    }

    readonly property Connections events: Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "activelayout") return
            // data is "<keyboard>,<layout>"; every keyboard device reports the
            // same switch, so only act when the layout name actually changes
            const layout = event.data.slice(event.data.indexOf(",") + 1)
            if (!layout || layout === root.current) return
            const first = root.current === ""
            root.current = layout
            if (!first) root.notify(layout)
        }
    }

    function notify(layout) {
        // --transient keeps these out of the notification centre history
        Quickshell.execDetached([
            "notify-send", "--transient", "-a", "Keyboard", "-i", "input-keyboard",
            "-t", "3000", "Keyboard layout: " + layout,
            "Switched with Alt+Shift. Press it again to switch back."
        ])
    }
}
