import qs
import qs.services
import qs.components
import Quickshell
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    required property var notification

    implicitHeight: inner.implicitHeight + 16

    readonly property bool isCritical: NotifService.isCritical(notification)
    readonly property string imageSource: (notification && notification.image) ? notification.image : ""

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: {
            if (!root.notification) return "transparent"
            return root.isCritical
                ? Theme.hexToRgba(Theme.color1, 0.08)
                : Theme.hexToRgba(Theme.foreground, 0.04)
        }
        border.color: {
            if (!root.notification) return "transparent"
            return root.isCritical
                ? Theme.hexToRgba(Theme.color1, 0.3)
                : Theme.hexToRgba(Theme.foreground, 0.08)
        }
        border.width: 1
    }

    ColumnLayout {
        id: inner
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: 10
        }
        spacing: 3

        // ---- header ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Image {
                Layout.preferredWidth: 14
                Layout.preferredHeight: 14
                source: root.notification ? Quickshell.iconPath(root.notification.appIcon, true) : ""
                visible: source !== ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }

            Text {
                Layout.fillWidth: true
                text: root.notification ? root.notification.appName : ""
                color: Theme.hexToRgba(Theme.foreground, 0.45)
                font.pixelSize: 11
                elide: Text.ElideRight
            }

            Text {
                text: NotifService.relativeTime(root.notification)
                color: Theme.hexToRgba(Theme.foreground, 0.3)
                font.pixelSize: 10
                font.family: "Departure Mono"
                visible: text !== ""
            }

            Text {
                text: "󰅖"
                color: Theme.hexToRgba(Theme.foreground, 0.35)
                font.pixelSize: 11
                font.family: "Symbols Nerd Font"

                TapHandler {
                    onTapped: if (root.notification) root.notification.dismiss()
                }
            }
        }

        // ---- body, with optional image ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Image {
                visible: root.imageSource !== ""
                source: root.imageSource
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
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
                    text: root.notification ? root.notification.summary : ""
                    color: Theme.foreground
                    font.pixelSize: 12
                    font.bold: true
                    elide: Text.ElideRight
                    visible: text !== ""
                }

                Text {
                    Layout.fillWidth: true
                    text: root.notification ? root.notification.body : ""
                    color: Theme.hexToRgba(Theme.foreground, 0.7)
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    visible: text !== ""
                }
            }
        }

        NotifActions {
            Layout.fillWidth: true
            Layout.topMargin: 4
            notification: root.notification
        }
    }
}
