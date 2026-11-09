import qs
import qs.services
import QtQuick
import QtQuick.Layouts

// Red dot + elapsed time while a screen recording runs; click to stop.
Item {
    id: root
    visible: Recorder.recording
    implicitWidth: row.implicitWidth + 8
    implicitHeight: row.implicitHeight

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6

        Rectangle {
            implicitWidth: 10
            implicitHeight: 10
            radius: 5
            color: "#e0405a" // fixed red: palette colors can come out muted

            SequentialAnimation on opacity {
                running: root.visible
                loops: Animation.Infinite
                NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
            }
        }

        Text {
            text: Recorder.elapsedLabel
            color: Theme.foreground
            font.pixelSize: 12
            font.family: "Departure Mono"
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Recorder.stop()
    }
}
