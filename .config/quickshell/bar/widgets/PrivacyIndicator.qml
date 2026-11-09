import qs
import qs.services
import QtQuick
import QtQuick.Layouts

// Mic / camera / screen-share dots, shown only while something captures.
// Hovering slides out which apps are doing it.
Item {
    id: root
    visible: Privacy.anyActive
    implicitWidth: row.implicitWidth + 8
    implicitHeight: row.implicitHeight

    readonly property color alert: "#f0a030"

    readonly property string details: {
        const parts = []
        if (Privacy.micActive) parts.push("Mic: " + Privacy.micApps.join(", "))
        if (Privacy.cameraActive) parts.push("Camera: " + Privacy.cameraApps.join(", "))
        if (Privacy.screenActive) parts.push("Screen: " + Privacy.screenApps.join(", "))
        return parts.join("  ·  ")
    }

    HoverHandler { id: hover }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6

        Text {
            visible: Privacy.micActive
            text: "󰍬"
            color: root.alert
            font.pixelSize: 15
            font.family: "Symbols Nerd Font"
        }
        Text {
            visible: Privacy.cameraActive
            text: "󰄀"
            color: root.alert
            font.pixelSize: 15
            font.family: "Symbols Nerd Font"
        }
        Text {
            visible: Privacy.screenActive
            text: "󰹑"
            color: root.alert
            font.pixelSize: 15
            font.family: "Symbols Nerd Font"
        }

        // App names, revealed on hover
        Text {
            Layout.preferredWidth: hover.hovered ? implicitWidth : 0
            clip: true
            text: root.details
            color: Theme.foreground
            font.pixelSize: 11
            Behavior on Layout.preferredWidth { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }
    }
}
