import qs
import qs.components
import qs.services
import qs.widgets
import Quickshell
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts

ToggleListPopup {
    id: popup

    implicitWidth: 380
    title: "Notifications"

    toggleOn: NotifService.dnd
    toggleOnColor: Theme.color1
    onToggled: NotifService.toggleDnd()

    model: groups
    maxListHeight: 480
    maxPopupHeight: 600

    emptyText: NotifService.dnd ? "Do not disturb" : "No notifications"

    footerText: "Clear all"
    footerVisible: NotifService.count > 0
    onFooterActivated: NotifService.dismissAll()

    // Notifications grouped by app, newest group first. A group with several
    // notifications collapses to its newest one until expanded.
    readonly property var groups: {
        const _dep = NotifService.count
        const byApp = {}
        const order = []
        for (const n of NotifService.notifications.values.slice().reverse()) {
            const app = n.appName || "Other"
            if (!byApp[app]) {
                byApp[app] = []
                order.push(app)
            }
            byApp[app].push(n)
        }
        return order.map(app => ({ app: app, notifs: byApp[app] }))
    }

    property var expanded: ({})

    function toggleGroup(app) {
        const e = Object.assign({}, popup.expanded)
        e[app] = !e[app]
        popup.expanded = e
    }

    function dismissGroup(group) {
        for (const n of group.notifs.slice()) n.dismiss()
    }

    rowDelegate: Component {
        Item {
            id: groupItem
            required property int index
            readonly property var group: popup.groups[index] ?? null
            readonly property bool stacked: !!group && group.notifs.length > 1
            readonly property bool open: stacked && popup.expanded[group.app] === true

            width: ListView.view.width
            height: col.implicitHeight + 6

            Column {
                id: col
                width: parent.width - 12
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 4

                // Group header (only for stacks)
                RowLayout {
                    visible: groupItem.stacked
                    width: parent.width
                    height: 22
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        text: groupItem.stacked ? groupItem.group.app + "  ·  " + groupItem.group.notifs.length : ""
                        color: Theme.hexToRgba(Theme.foreground, 0.6)
                        font.pixelSize: 11
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        text: groupItem.open ? "Show less" : "Show all"
                        color: Theme.color4
                        font.pixelSize: 11
                        TapHandler { onTapped: popup.toggleGroup(groupItem.group.app) }
                    }

                    Text {
                        Layout.rightMargin: 4
                        text: "󰅖"
                        color: Theme.hexToRgba(Theme.foreground, 0.45)
                        font.pixelSize: 12
                        font.family: "Symbols Nerd Font"
                        TapHandler { onTapped: popup.dismissGroup(groupItem.group) }
                    }
                }

                Repeater {
                    model: !groupItem.group ? []
                        : (groupItem.open ? groupItem.group.notifs : [groupItem.group.notifs[0]])

                    delegate: NotifCard {
                        required property var modelData
                        width: col.width
                        notification: modelData
                    }
                }

                // Collapsed stack: a sliver of "cards underneath"; click to expand
                Item {
                    visible: groupItem.stacked && !groupItem.open
                    width: col.width
                    height: 8

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: -4
                        width: parent.width - 16
                        height: 8
                        radius: 4
                        color: Theme.hexToRgba(Theme.foreground, 0.06)
                        border.color: Theme.hexToRgba(Theme.foreground, 0.08)
                        border.width: 1
                    }

                    TapHandler { onTapped: popup.toggleGroup(groupItem.group.app) }
                }
            }
        }
    }
}
