import qs
import qs.services
import qs.components
import qs.widgets
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick

ToggleListPopup {
    id: popup

    implicitWidth: 300
    title: "Bluetooth"

    toggleOn: BtService.enabled
    onToggled: BtService.toggleEnabled()

    model: BtService.devices
    rowHeight: 56
    maxVisible: 6

    emptyText: !BtService.enabled
        ? "Bluetooth is off"
        : BtService.adapter === null
        ? "No adapter"
        : "No devices"

    footerIcon: "󰂰"
    footerText: "Bluetooth Settings"
    onFooterActivated: {
        popup.close()
        bluetui.startDetached()
    }

    Process {
        id: bluetui
        command: [Quickshell.env("TERMINAL") || "alacritty", "--class", "bluetui", "-e", "/usr/bin/bluetui"]
    }

    rowDelegate: Component {
        Item {
            required property int index
            width: ListView.view.width
            height: rowInstance.height
            readonly property var dev: BtService.devices[index]

            BluetoothRow {
                id: rowInstance
                width: parent.width
                device: parent.dev
            }
        }
    }
}
