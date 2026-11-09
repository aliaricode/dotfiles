import qs
import QtQuick
import QtQuick.Layouts

// Action buttons ("Open", "Reply", ...) a notification offers. The "default"
// action has no label of its own, so it isn't shown as a button.
Flow {
    id: root
    required property var notification

    readonly property var buttons: {
        const out = []
        const acts = root.notification ? root.notification.actions : []
        for (let i = 0; i < acts.length; i++) {
            if (acts[i].identifier !== "default" && acts[i].text !== "") out.push(acts[i])
        }
        return out
    }

    visible: buttons.length > 0
    spacing: 6

    Repeater {
        model: root.buttons

        delegate: Rectangle {
            required property var modelData
            implicitWidth: label.implicitWidth + 20
            implicitHeight: 24
            radius: 8
            color: hover.hovered
                ? Theme.hexToRgba(Theme.foreground, 0.16)
                : Theme.hexToRgba(Theme.foreground, 0.08)

            Text {
                id: label
                anchors.centerIn: parent
                text: modelData.text
                color: Theme.foreground
                font.pixelSize: 11
            }

            HoverHandler { id: hover }
            TapHandler { onTapped: modelData.invoke() }
        }
    }
}
