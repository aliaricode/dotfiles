import qs
import qs.widgets
import qs.components
import Quickshell
import QtQuick
import QtQuick.Layouts

BasePopup {
    id: popup

    implicitWidth: 160
    implicitHeight: actionsCol.implicitHeight + 16

    property string armedAction: ""

    onAnimInChanged: if (!animIn) armedAction = ""

    Timer {
        id: disarmTimer
        interval: 2500
        onTriggered: popup.armedAction = ""
    }

    readonly property var actions: [
        { icon: "󰌾", label: "Lock",      cmd: ["loginctl", "lock-session"],                     destructive: false },
        { icon: "󰒲", label: "Suspend",   cmd: ["systemctl", "suspend"],                          destructive: false },
        { icon: "󰋊", label: "Hibernate", cmd: ["systemctl", "hibernate"],                        destructive: false },
        { icon: "󰍃", label: "Logout",    cmd: ["uwsm", "stop"],                                  destructive: true  },
        { icon: "󰑐", label: "Reboot",    cmd: ["systemctl", "reboot"],                           destructive: true  },
        { icon: "󰐥", label: "Shutdown",  cmd: ["systemctl", "poweroff"],                         destructive: true  },
    ]

    ColumnLayout {
        id: actionsCol
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: 8
        }
        spacing: 4

        Repeater {
            model: popup.actions

            delegate: Item {
                readonly property var action: popup.actions[index]
                readonly property bool armed: popup.armedAction === action.label
                Layout.fillWidth: true
                height: 40

                HoverHandler { id: actionHover }

                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: {
                        if (armed) return Theme.hexToRgba(Theme.color1, 0.25)
                        if (!actionHover.hovered) return "transparent"
                        if (action.destructive)
                            return Theme.hexToRgba(Theme.color1, 0.15)
                        return Theme.hexToRgba(Theme.foreground, 0.08)
                    }
                    Behavior on color {
                        ColorAnimation { duration: 100 }
                    }
                }

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: 10
                        rightMargin: 10
                    }
                    spacing: 8

                    Text {
                        text: action.icon
                        font.pixelSize: 15
                        font.family: "Symbols Nerd Font"
                        color: {
                            if (armed) return Theme.color1
                            if (!actionHover.hovered) return Theme.hexToRgba(Theme.foreground, 0.7)
                            if (action.destructive) return Theme.color1
                            return Theme.color5
                        }
                        Behavior on color {
                            ColorAnimation { duration: 100 }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: armed ? "Confirm?" : action.label
                        font.pixelSize: 13
                        font.bold: armed
                        color: armed
                            ? Theme.color1
                            : (actionHover.hovered ? Theme.foreground : Theme.hexToRgba(Theme.foreground, 0.7))
                        Behavior on color {
                            ColorAnimation { duration: 100 }
                        }
                    }
                }

                TapHandler {
                    onTapped: {
                        if (action.destructive && !armed) {
                            popup.armedAction = action.label
                            disarmTimer.restart()
                            return
                        }
                        popup.armedAction = ""
                        popup.close()
                        Quickshell.execDetached(action.cmd)
                    }
                }
            }
        }
    }
}
