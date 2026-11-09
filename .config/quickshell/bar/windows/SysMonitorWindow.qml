import qs
import qs.services
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

FloatingWindow {
    id: window

    title: "System Monitor"
    implicitWidth: 760
    implicitHeight: 480
    color: Theme.hexToRgba(Theme.background, 0.70)

    Component.onCompleted: {
        SysInfo.startGpuPolling()
        SysInfo.startSensorPolling()
        SysInfo.startDiskPolling()
        SysInfo.startProcessPolling()
    }
    Component.onDestruction: {
        SysInfo.stopGpuPolling()
        SysInfo.stopSensorPolling()
        SysInfo.stopDiskPolling()
        SysInfo.stopProcessPolling()
    }

    onClosed: closeRequested()
    signal closeRequested()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // ---- top strip: per-core CPU ----
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Text { text: "CPU"; color: Theme.foreground; font.pixelSize: 13; font.bold: true }
                Item { Layout.fillWidth: true }
                Text {
                    text: Math.round(SysInfo.cpuUsage * 100) + "%  ·  "
                        + Math.round(SysInfo.cpuTempC) + "°C"
                        + (SysInfo.fans.length > 0
                            ? "  ·  " + SysInfo.fans.map(f => Math.round(f.rpm) + " RPM").join(" / ")
                            : "")
                    color: Theme.hexToRgba(Theme.foreground, 0.6)
                    font.pixelSize: 12
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 12
                rowSpacing: 6
                columnSpacing: 6

                Repeater {
                    model: SysInfo.perCore
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        height: 22
                        radius: 4
                        color: Theme.hexToRgba(Theme.foreground, 0.08)
                        clip: true

                        Rectangle {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            height: parent.height * parent.modelData.usage
                            radius: 4
                            color: parent.modelData.usage >= 0.9
                                ? "#e0405a" : Theme.hexToRgba(Theme.color5, 0.85)
                            Behavior on height { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.hexToRgba(Theme.foreground, 0.08) }

        // ---- bottom: left stat column + right process list ----
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 14

            // ---- left column: Memory / Disk / Network / GPU ----
            ColumnLayout {
                Layout.preferredWidth: 260
                Layout.fillHeight: true
                spacing: 14

                // Memory
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Memory"; color: Theme.foreground; font.pixelSize: 13; font.bold: true }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: (SysInfo.memUsedKb / 1048576).toFixed(1) + " / "
                                + (SysInfo.memTotalKb / 1048576).toFixed(1) + " GiB"
                            color: Theme.hexToRgba(Theme.foreground, 0.6)
                            font.pixelSize: 11
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        height: 8
                        radius: 4
                        color: Theme.hexToRgba(Theme.foreground, 0.1)
                        Rectangle {
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            width: parent.width * SysInfo.memUsage
                            radius: 4
                            color: SysInfo.memUsage >= 0.9 ? "#e0405a" : Theme.color5
                            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.hexToRgba(Theme.foreground, 0.06) }

                // Disk
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text { text: "Disk"; color: Theme.foreground; font.pixelSize: 13; font.bold: true }

                    Repeater {
                        model: SysInfo.disks
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 3

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: parent.parent.modelData.mount
                                    color: Theme.foreground
                                    font.pixelSize: 11
                                    elide: Text.ElideMiddle
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: (parent.parent.modelData.usedBytes / 1073741824).toFixed(0) + "/"
                                        + (parent.parent.modelData.sizeBytes / 1073741824).toFixed(0) + "G"
                                    color: Theme.hexToRgba(Theme.foreground, 0.6)
                                    font.pixelSize: 10
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                height: 5
                                radius: 3
                                color: Theme.hexToRgba(Theme.foreground, 0.1)
                                Rectangle {
                                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                    width: parent.width * parent.parent.modelData.usage
                                    radius: 3
                                    color: parent.parent.modelData.usage >= 0.9 ? "#e0405a" : Theme.color5
                                    Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                                }
                            }
                        }
                    }
                    Text {
                        visible: SysInfo.disks.length === 0
                        text: "No mounted disks found"
                        color: Theme.hexToRgba(Theme.foreground, 0.4)
                        font.pixelSize: 11
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.hexToRgba(Theme.foreground, 0.06) }

                // Network
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Text { text: "Network"; color: Theme.foreground; font.pixelSize: 13; font.bold: true }
                    Text {
                        text: "↓ " + (SysInfo.netRxKBs >= 1024
                            ? (SysInfo.netRxKBs / 1024).toFixed(1) + " MB/s"
                            : SysInfo.netRxKBs.toFixed(0) + " KB/s")
                        color: Theme.hexToRgba(Theme.foreground, 0.7)
                        font.pixelSize: 12
                    }
                    Text {
                        text: "↑ " + (SysInfo.netTxKBs >= 1024
                            ? (SysInfo.netTxKBs / 1024).toFixed(1) + " MB/s"
                            : SysInfo.netTxKBs.toFixed(0) + " KB/s")
                        color: Theme.hexToRgba(Theme.foreground, 0.7)
                        font.pixelSize: 12
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.hexToRgba(Theme.foreground, 0.06) }

                // GPU
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "GPU"; color: Theme.foreground; font.pixelSize: 13; font.bold: true }
                        Item { Layout.fillWidth: true }

                        Rectangle {
                            visible: SysInfo.hasNvidia
                            width: 30
                            height: 16
                            radius: 8
                            color: SysInfo.fetchNvidiaEnabled ? Theme.color5 : Theme.hexToRgba(Theme.foreground, 0.15)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Rectangle {
                                width: 12
                                height: 12
                                radius: 6
                                anchors.verticalCenter: parent.verticalCenter
                                x: SysInfo.fetchNvidiaEnabled ? parent.width - width - 2 : 2
                                color: Theme.background
                                Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            }
                            TapHandler {
                                onTapped: SysInfo.setFetchNvidia(!SysInfo.fetchNvidiaEnabled)
                            }
                        }
                    }

                    ColumnLayout {
                        visible: SysInfo.fetchNvidiaEnabled
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: Math.round(SysInfo.gpuUtil * 100) + "%  ·  "
                                + Math.round(SysInfo.gpuTempC) + "°C  ·  "
                                + SysInfo.gpuPowerW.toFixed(0) + "W"
                            color: Theme.hexToRgba(Theme.foreground, 0.7)
                            font.pixelSize: 12
                        }
                        Text {
                            text: "VRAM " + (SysInfo.gpuMemUsedMb / 1024).toFixed(1) + " / "
                                + (SysInfo.gpuMemTotalMb / 1024).toFixed(1) + " GiB"
                            color: Theme.hexToRgba(Theme.foreground, 0.6)
                            font.pixelSize: 11
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            height: 6
                            radius: 3
                            color: Theme.hexToRgba(Theme.foreground, 0.1)
                            readonly property real vramFrac: SysInfo.gpuMemTotalMb > 0
                                ? SysInfo.gpuMemUsedMb / SysInfo.gpuMemTotalMb : 0
                            Rectangle {
                                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                width: parent.width * parent.vramFrac
                                radius: 3
                                color: parent.vramFrac >= 0.9 ? "#e0405a" : Theme.color5
                                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                            }
                        }
                    }

                    Text {
                        visible: !SysInfo.fetchNvidiaEnabled
                        text: SysInfo.hasNvidia ? "NVIDIA fetching off" : "No NVIDIA GPU"
                        color: Theme.hexToRgba(Theme.foreground, 0.4)
                        font.pixelSize: 11
                    }
                }

                Item { Layout.fillHeight: true }
            }

            Rectangle { Layout.fillHeight: true; width: 1; color: Theme.hexToRgba(Theme.foreground, 0.08) }

            // ---- right column: process list ----
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Text { Layout.preferredWidth: 60; text: "PID"; color: Theme.hexToRgba(Theme.foreground, 0.5); font.pixelSize: 11 }
                    Text { Layout.fillWidth: true; text: "Name"; color: Theme.hexToRgba(Theme.foreground, 0.5); font.pixelSize: 11 }
                    Text { Layout.preferredWidth: 60; text: "CPU%"; color: Theme.hexToRgba(Theme.foreground, 0.5); font.pixelSize: 11 }
                    Text { Layout.preferredWidth: 60; text: "MEM%"; color: Theme.hexToRgba(Theme.foreground, 0.5); font.pixelSize: 11 }
                    Item { Layout.preferredWidth: 70 }
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: SysInfo.processes

                    delegate: Item {
                        id: procRow
                        required property var modelData
                        width: ListView.view.width
                        height: 26

                        property bool armed: false

                        Timer {
                            id: disarmTimer
                            interval: 2500
                            onTriggered: procRow.armed = false
                        }

                        RowLayout {
                            anchors.fill: parent
                            Text {
                                Layout.preferredWidth: 60
                                text: String(procRow.modelData.pid)
                                color: Theme.hexToRgba(Theme.foreground, 0.6)
                                font.pixelSize: 12
                            }
                            Text {
                                Layout.fillWidth: true
                                text: procRow.modelData.name
                                color: Theme.foreground
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.preferredWidth: 60
                                text: procRow.modelData.cpu.toFixed(1)
                                color: Theme.hexToRgba(Theme.foreground, 0.6)
                                font.pixelSize: 12
                            }
                            Text {
                                Layout.preferredWidth: 60
                                text: procRow.modelData.mem.toFixed(1)
                                color: Theme.hexToRgba(Theme.foreground, 0.6)
                                font.pixelSize: 12
                            }

                            Rectangle {
                                Layout.preferredWidth: 62
                                Layout.preferredHeight: 22
                                radius: 6
                                color: procRow.armed
                                    ? Theme.hexToRgba("#e0405a", 0.85)
                                    : Theme.hexToRgba(Theme.foreground, 0.08)
                                Behavior on color { ColorAnimation { duration: 120 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: procRow.armed ? "Confirm?" : "Kill"
                                    color: procRow.armed ? Theme.background : Theme.hexToRgba(Theme.foreground, 0.7)
                                    font.pixelSize: 10
                                    font.bold: procRow.armed
                                }

                                TapHandler {
                                    onTapped: {
                                        if (procRow.armed) {
                                            SysInfo.killProcess(procRow.modelData.pid)
                                            procRow.armed = false
                                            disarmTimer.stop()
                                        } else {
                                            procRow.armed = true
                                            disarmTimer.restart()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
