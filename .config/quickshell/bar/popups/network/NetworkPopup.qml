import qs
import qs.services
import qs.widgets
import qs.components
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import QtQuick

ToggleListPopup {
    id: popup

    maxListHeight: 6 * 52
    maxPopupHeight: 420
    pinMaxHeight: true
    implicitWidth: 320
    title: "Wi-Fi"

    toggleOn: Net.wifiEnabled
    toggleInteractive: Net.hasWifi && !Net.hardwareBlocked
    toggleTrackColor: Net.hardwareBlocked
        ? Theme.hexToRgba(Theme.foreground, 0.15)
        : (Net.wifiEnabled ? Theme.color5 : Theme.hexToRgba(Theme.foreground, 0.2))
    toggleThumbColor: Net.hardwareBlocked
        ? Theme.hexToRgba(Theme.foreground, 0.4)
        : Theme.background

    onToggled: Net.toggleWifi()

    model: Net.networks
    rowHeight: 52
    maxVisible: 6

    onVisibleChanged: Net.scanning = popup.visible

    emptyText: !Net.hasWifi
        ? "No adapter"
        : !Net.wifiEnabled
        ? "Wi-Fi is off"
        : "Scanning…"

    footerIcon: "󰒓"
    footerText: "Network Settings"
    onFooterActivated: {
        popup.close()
        nmtui.startDetached()
    }

    readonly property string terminal: Quickshell.env("TERMINAL") || "alacritty"

    Process {
        id: nmtui
        command: [popup.terminal, "-e", "/usr/bin/nmtui"]
    }

    rowDelegate: Component {
        NetworkRow {
            required property var modelData
            width: ListView.view.width
            network: modelData
        }
    }
}
