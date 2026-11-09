import qs
import qs.services
import qs.components
import Quickshell
import QtQuick

Item {
    implicitWidth: icon.implicitWidth + 8
    implicitHeight: icon.implicitHeight

    Text {
        id: icon
        anchors.centerIn: parent
        text: IdleInhibit.inhibiting ? "" : ""
        color: IdleInhibit.inhibiting ? Theme.color5 : Theme.foreground
        font.pixelSize: 15
    }

    MouseArea {
        anchors.fill: parent
        // Same source as the Quick Settings "Keep Awake" tile (inhibiting is read-only)
        onClicked: IdleInhibit.toggle("manual")
    }
}
