import qs
import qs.services
import qs.components
import qs.widgets
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Services.Mpris
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

Scope {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: barWindow
            required property var modelData
            screen: modelData

            readonly property real pillCurrentWidth: centerPill.width
            readonly property real pillWidth: centerPill.implicitWidth
            readonly property real pillHeight: centerPill.implicitHeight

            Component.onCompleted: BarRegistry.register(modelData.name, barWindow)
            Component.onDestruction: BarRegistry.unregister(modelData.name)

            anchors {
                top: true
                left: true
                right: true
            }

            implicitHeight: 52
            margins.top: 8
            color: "transparent"

            WlrLayershell.namespace: "quickshell:bar"

            exclusionMode: ExclusionMode.Normal
            exclusiveZone: 52

            Item {
                id: pillRow
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    leftMargin: 10
                    rightMargin: 10
                }
                height: 44

                // ── LEFT PILL ─────────────────────────────────
                Pill {
                    id: leftPill
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                    }
                    padding: 8
                    spacing: 8

                    PowerButton { barWindow: barWindow }
                    Workspaces { screen: barWindow.screen }
                    MediaPlayer {
                        id: mediaWidget
                        barWindow: barWindow
                    }
                }

                // ── CENTER PILL ───────────────────────────────
                Pill {
                    id: centerPill
                    anchors {
                        horizontalCenter: parent.horizontalCenter
                        verticalCenter: parent.verticalCenter
                    }
                    padding: 10
                    spacing: 10

                    readonly property bool expandedHere: ExpandPopupCoordinator.expanded
                        && ExpandPopupCoordinator.activeBar === barWindow

                    width: expandedHere ? ExpandPopupCoordinator.targetWidth : implicitWidth
                    Behavior on width {
                        NumberAnimation { id: pillWidthAnim; easing.type: ExpandPopupCoordinator.easing }
                    }

                    Connections {
                        target: ExpandPopupCoordinator
                        function onGrowDurationChanged() {
                            pillWidthAnim.duration = ExpandPopupCoordinator.growDuration
                        }
                    }

                    contentOpacity: (!expandedHere && !shrinkGuard.running) ? 1 : 0
                    Behavior on contentOpacity {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }

                    Timer {
                        id: shrinkGuard
                        interval: pillWidthAnim.duration
                    }

                    onExpandedHereChanged: if (!expandedHere) shrinkGuard.restart()

                    SysMonitor { barWindow: barWindow; side: "cpu" }
                    Clock { barWindow: barWindow }
                    SysMonitor { barWindow: barWindow; side: "ram" }
                }

                // ── RIGHT PILL ────────────────────────────────
                Pill {
                    id: rightPill
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    padding: 15
                    spacing: 8

                    PrivacyIndicator {}
                    RecordingIndicator {}
                    IdleInhibitor {}
                    Audio { barWindow: barWindow }
                    Backlight {}
                    Network { barWindow: barWindow }
                    Bluetooth { barWindow: barWindow }
                    Battery { barWindow: barWindow }
                    Tray { barWindow: barWindow }
                    NotificationBell { barWindow: barWindow }
                }
            }
        }
    }
}
