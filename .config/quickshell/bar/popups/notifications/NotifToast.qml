import qs
import qs.services
import qs.components
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: root

    anchors.top: true
    anchors.right: true
    margins.top: 60
    margins.right: 12

    implicitWidth: 360
    implicitHeight: card.implicitHeight
    color: "transparent"

    exclusionMode: ExclusionMode.Ignore

    mask: Region {
        item: NotifService.toastVisible ? card : null
    }

    WlrLayershell.namespace: "quickshell:toast"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    readonly property var notif: NotifService.toastNotification
    readonly property bool isCritical: NotifService.isCritical(notif)
    readonly property string imageSource: (notif && notif.image) ? notif.image : ""

    Rectangle {
        id: card
        width: parent.width
        implicitHeight: contentCol.implicitHeight + 24
        radius: 14
        color: Theme.hexToRgba(Theme.background, Theme.surfaceAlpha(0.92))
        border.color: root.isCritical
            ? Theme.hexToRgba(Theme.color1, 0.8)
            : Theme.hexToRgba(Theme.foreground, 0.1)
        border.width: 1

        opacity: NotifService.toastVisible ? 1 : 0
        transformOrigin: Item.Top
        scale: NotifService.toastVisible ? 1 : 0.95

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        HoverHandler {
            id: toastHover
            onHoveredChanged: NotifService.toastPaused = hovered
        }

        ColumnLayout {
            id: contentCol
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: 12
            }
            spacing: 4

            // ---- header ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Image {
                    Layout.preferredWidth: 16
                    Layout.preferredHeight: 16
                    source: root.notif ? Quickshell.iconPath(root.notif.appIcon, true) : ""
                    visible: source !== ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }

                Text {
                    Layout.fillWidth: true
                    text: root.notif ? root.notif.appName : ""
                    color: Theme.hexToRgba(Theme.foreground, 0.5)
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                Rectangle {
                    visible: NotifService.queuedCount > 0
                    Layout.preferredWidth: queueLabel.implicitWidth + 10
                    Layout.preferredHeight: 16
                    radius: 8
                    color: Theme.hexToRgba(Theme.color1, 0.2)

                    Text {
                        id: queueLabel
                        anchors.centerIn: parent
                        text: "+" + NotifService.queuedCount
                        color: Theme.color1
                        font.pixelSize: 10
                        font.bold: true
                    }
                }

                Text {
                    text: "󰅖"
                    color: Theme.hexToRgba(Theme.foreground, 0.4)
                    font.pixelSize: 12
                    font.family: "Symbols Nerd Font"
                    TapHandler {
                        onTapped: NotifService.dismissToast()
                    }
                }
            }

            // ---- body, with optional image ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Image {
                    visible: root.imageSource !== ""
                    source: root.imageSource
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    Layout.alignment: Qt.AlignTop
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: root.notif ? root.notif.summary : ""
                        color: Theme.foreground
                        font.pixelSize: 13
                        font.bold: true
                        elide: Text.ElideRight
                        visible: text !== ""
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.notif ? root.notif.body : ""
                        color: Theme.hexToRgba(Theme.foreground, 0.75)
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        visible: text !== ""
                    }
                }
            }

            NotifActions {
                Layout.fillWidth: true
                Layout.topMargin: 4
                notification: root.notif
            }
        }

        TapHandler {
            onTapped: NotifService.dismissToast()
        }
    }
}
