pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick

Singleton {
    id: root

    readonly property var bat: UPower.displayDevice

    readonly property int lowThreshold: 15
    readonly property int criticalThreshold: 5

    property bool warnedLow: false
    property bool warnedCritical: false

    readonly property bool discharging: !!bat && bat.ready
        && bat.state === UPowerDeviceState.Discharging

    Process { id: notifyProc }

    function notify(urgency, summary, body) {
        notifyProc.command = ["notify-send", "-u", urgency, summary, body]
        notifyProc.running = true
    }

    function check() {
        if (!root.bat || !root.bat.ready) return

        if (!root.discharging) {
            root.warnedLow = false
            root.warnedCritical = false
            return
        }

        const pct = root.bat.percentage * 100

        if (pct <= root.criticalThreshold && !root.warnedCritical) {
            root.warnedCritical = true
            root.warnedLow = true
            root.notify("critical", "Battery critical", Math.round(pct) + "% remaining")
        } else if (pct <= root.lowThreshold && !root.warnedLow) {
            root.warnedLow = true
            root.notify("normal", "Battery low", Math.round(pct) + "% remaining")
        }
    }

    Connections {
        target: root.bat
        function onReadyChanged() { root.check() }
        function onPercentageChanged() { root.check() }
        function onStateChanged() { root.check() }
    }

    // Catch "already low at login" instead of waiting for the next % change
    Component.onCompleted: root.check()
}
