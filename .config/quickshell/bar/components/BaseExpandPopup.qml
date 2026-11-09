import qs
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

PopupWindow {
    id: root

    // ---- public API ----
    property var barWindow: BarRegistry.focusedBar
    property string ipcTarget: ""
    property string placeholder: "Search..."

    property real originX: barWindow ? barWindow.width / 2 : 0
    property real originWidth: barWindow ? barWindow.pillWidth : 200

    property int searchHeight: 42
    property int columnSpacing: 6
    property int searchFontSize: 13
    property int searchIconSize: 14

    property int selectedIndex: 0
    property int minIndex: 0
    property int maxIndex: 0

    property bool showSearch: true

    property alias searchText: searchField.text
    property alias headerContent: headerSlot.data
    property bool focusSearchOnOpen: true
    readonly property bool animIn: controller.animIn

    signal tabPressed()
    signal backtabPressed()

    signal accepted(int index)
    signal playRequested(int index)
    signal searchEdited(string text)
    signal opened()

    default property alias content: contentSlot.data

    color: "transparent"
    visible: false

    // Used when another popup is taking over
    property int fastCloseDuration: 160
    property int heightAnimDuration: root.heightPhaseDuration

    ExpandPopupController {
        id: controller
        animEnter: root.heightPhaseDuration
        // Hide (and let the pill start shrinking) once the fold is nearly done
        animExit: Math.round(root.heightAnimDuration * ExpandPopupCoordinator.closeOverlap)
        onClosed: {
            ExpandPopupCoordinator.collapse(root)
            root.visible = false
            root.cardCollapsedHeight = 0
            widthShrinkTimer.restart()
        }
    }

    anchor {
        window: barWindow
        rect: Qt.rect(
            Math.max(8, Math.min(
                root.originX - root.implicitWidth / 2,
                (barWindow?.width ?? 1920) - root.implicitWidth - 8
            )),
            0, 0, 0
        )
    }

    // ---- height phase (width phase duration comes from the coordinator) ----
    // >1 slows this popup's drop down relative to the others
    property real heightPhaseScale: 1.0
    readonly property int heightPhaseDuration:
        ExpandPopupCoordinator.durationFor(0, root.implicitHeight, root.heightPhaseScale)
    readonly property real collapsedHeight: barWindow ? barWindow.pillHeight : 44
    property real cardCollapsedHeight: 0

    // Assigned by open() from the coordinator's computed travel time.
    property int openPhaseDuration: 0

    Timer {
        id: widthPhaseTimer
        // Start dropping down while the pill finishes stretching
        interval: Math.round(root.openPhaseDuration * ExpandPopupCoordinator.phaseOverlap)
        onTriggered: {
            root.heightAnimDuration = root.heightPhaseDuration
            controller.open()
            if (root.focusSearchOnOpen) Qt.callLater(() => searchField.forceActiveFocus())
        }
    }

    Timer {
        id: widthShrinkTimer
        interval: ExpandPopupCoordinator.growDuration
        onTriggered: {
            ExpandPopupCoordinator.notifyClosed(root)
        }
    }

    function open() {
        widthShrinkTimer.stop()
        controller.cancelClose()
        root.barWindow = BarRegistry.focusedBar
        visible = true
        selectedIndex = 0
        searchField.text = ""
        const d = ExpandPopupCoordinator.expand(root, root.barWindow)
        if (d >= 0) root.startExpandPhase(d)
        root.opened()
    }

    function close(fast) {
        widthPhaseTimer.stop()
        root.heightAnimDuration = fast === true
            ? root.fastCloseDuration
            : Math.round(root.heightPhaseDuration * ExpandPopupCoordinator.closeScale)
        root.cardCollapsedHeight = root.collapsedHeight
        focusGrab.active = false
        controller.close()
    }

    function startExpandPhase(duration) {
        root.openPhaseDuration = duration
        focusGrab.active = true
        widthPhaseTimer.restart()
    }

    function abortOpen() {
        widthPhaseTimer.stop()
        focusGrab.active = false
        root.visible = false
    }

    function toggle() {
        if (visible && controller.animIn) close()
        else open()
    }

    IpcHandler {
        target: root.ipcTarget
        function toggle(): void { root.toggle() }
        function open(): void { root.open() }
        function close(): void { root.close() }
    }

    HyprlandFocusGrab {
        id: focusGrab
        windows: [root]
        onCleared: root.close()
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.visible
        onActivated: root.close()
    }

    readonly property bool contentReady: controller.animIn && !growGuard.running
    Timer {
        id: growGuard
        // Content fades in while the card is still landing
        interval: Math.round(root.heightPhaseDuration * 0.5)
    }
    Connections {
        target: controller
        function onAnimInChanged() {
            if (controller.animIn) growGuard.restart()
        }
    }

    // ---- animated card: width is already fixed (matches the bar's target),
    Rectangle {
        id: bg
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: controller.animIn ? root.implicitHeight : root.cardCollapsedHeight
        clip: true
        radius: Math.min(root.collapsedHeight / 2, height / 2)
        antialiasing: true
        color: Theme.hexToRgba(Theme.background, Theme.surfaceAlpha(0.92))
        border.color: Theme.hexToRgba(Theme.foreground, 0.08)
        border.width: 1

        Behavior on height {
            NumberAnimation {
                duration: root.heightAnimDuration
                easing.type: ExpandPopupCoordinator.easing
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: root.columnSpacing
            opacity: root.contentReady ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }

            // ---- header slot ----
            Item {
                id: headerSlot
                Layout.fillWidth: true
                implicitHeight: childrenRect.height
                visible: children.length > 0
            }

            // ---- search box ----
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: root.showSearch ? root.searchHeight : 0
                radius: 10
                color: Theme.hexToRgba(Theme.foreground, 0.07)
                border.color: searchField.activeFocus
                    ? Theme.hexToRgba(Theme.color4, 0.8)
                    : Theme.hexToRgba(Theme.foreground, 0.1)
                border.width: 1

                opacity: root.showSearch ? 1 : 0
                visible: Layout.preferredHeight > 0
                clip: true

                Behavior on Layout.preferredHeight {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }

                Behavior on border.color {
                    ColorAnimation { duration: 150 }
                }

                RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                    spacing: 8

                    Text {
                        text: "󰍉"
                        color: Theme.hexToRgba(Theme.foreground, 0.5)
                        font.pixelSize: root.searchIconSize
                        font.family: "Symbols Nerd Font"
                    }

                    TextInput {
                        id: searchField
                        Layout.fillWidth: true
                        color: Theme.foreground
                        font.pixelSize: root.searchFontSize
                        selectionColor: Theme.hexToRgba(Theme.color4, 0.4)
                        selectedTextColor: Theme.foreground
                        clip: true
                        selectByMouse: true

                        onTextChanged: root.searchEdited(text)

                        Keys.onTabPressed: (event) => {
                            event.accepted = true
                            root.tabPressed()
                        }
                        Keys.onBacktabPressed: (event) => {
                            event.accepted = true
                            root.backtabPressed()
                        }
                        Keys.onUpPressed: (event) => {
                            event.accepted = true
                            root.selectedIndex = Math.max(root.minIndex, root.selectedIndex - 1)
                        }
                        Keys.onDownPressed: (event) => {
                            event.accepted = true
                            root.selectedIndex = Math.min(root.maxIndex, root.selectedIndex + 1)
                        }
                        Keys.onReturnPressed: (event) => {
                            event.accepted = true
                            if (event.modifiers & Qt.ShiftModifier)
                                root.playRequested(root.selectedIndex)
                            else
                                root.accepted(root.selectedIndex)
                        }

                        Text {
                            anchors.fill: parent
                            text: root.placeholder
                            color: Theme.hexToRgba(Theme.foreground, 0.3)
                            font.pixelSize: root.searchFontSize
                            visible: searchField.text === ""
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }

            Item {
                id: contentSlot
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }
    }
}

