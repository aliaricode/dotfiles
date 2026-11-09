import qs
import qs.widgets
import qs.services
import qs.components
import qs.popups.notifications
import Quickshell
import Quickshell.Io
import QtQuick

BarButton {
    id: root

    implicitWidth: widget.implicitWidth
    implicitHeight: widget.implicitHeight

    readonly property bool dnd: NotifService.dnd
    readonly property int count: NotifService.count

    readonly property string bellIcon: {
        if (dnd)        return "󰂛"
        if (count > 0)  return "󰂚"
        return "󰂜"
    }
    readonly property color bellColor: dnd
        ? Theme.color1
        : count > 0 ? Theme.color5 : Theme.foreground
    readonly property string bellLabel: {
        if (dnd)        return "DND"
        if (count > 0)  return count + ""
        return ""
    }

    popup: NotifCenter {}

    onRightClicked: NotifService.toggleDnd()

    // `qs -c bar ipc call notifications toggle`; only the focused monitor's
    // bell answers, since every bar has one
    IpcHandler {
        target: "notifications"
        enabled: root.barWindow === BarRegistry.focusedBar
        function toggle(): void { root.openPopup() }
    }

    ExpandingWidget {
        id: widget
        icon: bellIcon
        label: bellLabel
        iconColor: bellColor
    }
}
