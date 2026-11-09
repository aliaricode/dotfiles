import qs
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

// Window switcher / overview: live previews of every window, most recently
// used first.
//   Alt+Tab        open with the previous window selected; keep tapping Tab
//                  to move on, release Alt to switch (classic alt-tab)
//   type           filter by title or app
//   arrows / Tab   move the selection      Enter / click   switch to it
//   middle-click / Ctrl+W   close that window             Esc   cancel
PanelWindow {
    id: root

    property bool shown: false
    // Opened by Alt+Tab: releasing Alt picks the selected window
    property bool altMode: false
    property int selectedIndex: 0
    property var lastPointer: null

    screen: BarRegistry.focusedBar ? BarRegistry.focusedBar.screen : null
    visible: shown
    color: "transparent"

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:switcher"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // ── DATA ───────────────────────────────────────────────────
    readonly property string query: searchField.text.toLowerCase()

    readonly property var windows: {
        const list = Hyprland.toplevels.values.map(t => {
            const ipc = t.lastIpcObject || {}
            return {
                toplevel: t,
                title: t.title || ipc.title || "",
                appClass: ipc.class || "",
                workspace: ipc.workspace ? ipc.workspace.name : "",
                history: ipc.focusHistoryID ?? 999
            }
        })
        list.sort((a, b) => a.history - b.history)
        if (root.query === "") return list
        return list.filter(w => w.title.toLowerCase().includes(root.query)
            || w.appClass.toLowerCase().includes(root.query))
    }

    onWindowsChanged: root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, root.windows.length - 1))

    // App icon from the window class; generic icon for classes without a
    // desktop entry (e.g. custom terminal classes)
    function iconFor(appClass) {
        const name = DesktopEntries.heuristicLookup(appClass)?.icon ?? ""
        const path = name ? Quickshell.iconPath(name, true) : ""
        return path !== "" ? path : Quickshell.iconPath("application-x-executable", true)
    }

    function address(t) {
        const a = String(t.address)
        return a.startsWith("0x") ? a : "0x" + a
    }

    function open(alt) {
        Hyprland.refreshToplevels()
        searchField.text = ""
        root.altMode = alt
        root.lastPointer = null
        // Index 0 is the window you're already in, so start on the previous one
        root.selectedIndex = Hyprland.toplevels.values.length > 1 ? 1 : 0
        root.shown = true
        searchField.forceActiveFocus()
    }

    function close() {
        root.shown = false
        root.altMode = false
    }

    function move(delta) {
        const n = root.windows.length
        if (n === 0) return
        root.selectedIndex = (root.selectedIndex + delta + n) % n
    }

    // Hide first, focus a moment later: while the overlay holds keyboard focus
    // (and right as it unmaps) Hyprland restores focus to the previously
    // focused window, which would override an immediate request
    property string pendingFocus: ""

    function activate(index) {
        const w = root.windows[index]
        root.close()
        if (!w) return
        root.pendingFocus = root.address(w.toplevel)
        focusTimer.restart()
    }

    Timer {
        id: focusTimer
        interval: 60
        onTriggered: Hyprland.dispatch('hl.dsp.focus({ window = "address:' + root.pendingFocus + '" })')
    }

    function closeWindow(index) {
        const w = root.windows[index]
        if (!w) return
        Hyprland.dispatch('hl.dsp.window.close({ window = "address:' + root.address(w.toplevel) + '" })')
        refreshTimer.restart()
    }

    // focusHistoryID (the MRU order) only updates on refresh, so keep it fresh
    // on every focus change rather than racing a refresh when Alt+Tab opens
    Connections {
        target: Hyprland
        function onActiveToplevelChanged() { refreshTimer.restart() }
    }

    Timer {
        id: refreshTimer
        interval: 50
        onTriggered: Hyprland.refreshToplevels()
    }

    IpcHandler {
        target: "switcher"
        function toggle(): void { if (root.shown) root.close(); else root.open(false) }
        // Alt+Tab: open, or step forward if already open
        function altTab(): void { if (root.shown) root.move(1); else root.open(true) }
        // Alt released (bound in Hyprland, so it works even before we have focus)
        function altReleased(): void { if (root.shown && root.altMode) root.activate(root.selectedIndex) }
    }

    // ── UI ─────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Theme.hexToRgba(Theme.background, Theme.surfaceAlpha(0.7))
        opacity: root.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }

        TapHandler { onTapped: root.close() }
    }

    readonly property int cardWidth: 300
    readonly property int previewHeight: 170
    readonly property int columns: Math.max(1, Math.min(root.windows.length,
        Math.floor((root.width - 120) / (root.cardWidth + 16))))

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(root.width - 80, root.columns * (root.cardWidth + 16))
        spacing: 18

        // Search
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 420
            Layout.preferredHeight: 42
            radius: 12
            color: Theme.hexToRgba(Theme.background, 0.9)
            border.color: Theme.hexToRgba(Theme.color4, 0.6)
            border.width: 1

            RowLayout {
                anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                spacing: 8

                Text {
                    text: "󰖯"
                    color: Theme.hexToRgba(Theme.foreground, 0.5)
                    font.pixelSize: 15
                    font.family: "Symbols Nerd Font"
                }

                TextInput {
                    id: searchField
                    Layout.fillWidth: true
                    color: Theme.foreground
                    font.pixelSize: 14
                    clip: true

                    onTextChanged: root.selectedIndex = 0

                    Keys.onPressed: (event) => {
                        const ctrl = event.modifiers & Qt.ControlModifier
                        if (event.key === Qt.Key_Escape) root.close()
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.activate(root.selectedIndex)
                        else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Right) root.move(1)
                        else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Left) root.move(-1)
                        else if (event.key === Qt.Key_Down) root.move(root.columns)
                        else if (event.key === Qt.Key_Up) root.move(-root.columns)
                        else if (ctrl && event.key === Qt.Key_W) root.closeWindow(root.selectedIndex)
                        else return
                        event.accepted = true
                    }

                    Keys.onReleased: (event) => {
                        if (event.key === Qt.Key_Alt && root.altMode) {
                            event.accepted = true
                            root.activate(root.selectedIndex)
                        }
                    }

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "Filter windows…   (Enter switch · Ctrl+W close · Esc cancel)"
                        color: Theme.hexToRgba(Theme.foreground, 0.3)
                        font.pixelSize: 13
                        visible: searchField.text === ""
                    }
                }
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            visible: root.windows.length === 0
            text: root.query === "" ? "No windows open" : "No matching windows"
            color: Theme.hexToRgba(Theme.foreground, 0.6)
            font.pixelSize: 14
        }

        GridLayout {
            Layout.alignment: Qt.AlignHCenter
            columns: root.columns
            rowSpacing: 16
            columnSpacing: 16

            Repeater {
                model: root.windows

                delegate: Rectangle {
                    id: card
                    required property var modelData
                    required property int index
                    readonly property bool selected: index === root.selectedIndex

                    Layout.preferredWidth: root.cardWidth
                    Layout.preferredHeight: root.previewHeight + 52
                    radius: 14
                    color: Theme.hexToRgba(Theme.background, selected ? 0.95 : 0.8)
                    border.color: selected
                        ? Theme.color4
                        : Theme.hexToRgba(Theme.foreground, cardHover.hovered ? 0.25 : 0.08)
                    border.width: selected ? 2 : 1
                    scale: selected ? 1.03 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                    // Only real pointer movement selects: a mouse resting where a
                    // card happens to appear mustn't steal the Alt+Tab selection
                    HoverHandler {
                        id: cardHover
                        onPointChanged: {
                            if (!hovered) return
                            const p = point.scenePosition
                            if (root.lastPointer === null) { root.lastPointer = p; return }
                            if (p.x === root.lastPointer.x && p.y === root.lastPointer.y) return
                            root.lastPointer = p
                            root.selectedIndex = card.index
                        }
                    }
                    TapHandler {
                        acceptedButtons: Qt.LeftButton
                        onTapped: root.activate(card.index)
                    }
                    TapHandler {
                        acceptedButtons: Qt.MiddleButton
                        onTapped: root.closeWindow(card.index)
                    }

                    // Live preview, letterboxed to the window's aspect ratio
                    Item {
                        id: previewBox
                        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 8 }
                        height: root.previewHeight

                        ScreencopyView {
                            id: preview
                            readonly property real aspect: sourceSize.height > 0
                                ? sourceSize.width / sourceSize.height : 16 / 9
                            anchors.centerIn: parent
                            width: Math.min(parent.width, parent.height * aspect)
                            height: width / aspect
                            captureSource: root.shown ? card.modelData.toplevel.wayland : null
                            live: root.shown
                            constraintSize: Qt.size(previewBox.width, previewBox.height)
                        }

                        // Shown until the first frame arrives (or if capture fails)
                        IconImage {
                            anchors.centerIn: parent
                            visible: !preview.hasContent
                            implicitSize: 56
                            source: root.iconFor(card.modelData.appClass)
                        }
                    }

                    RowLayout {
                        anchors {
                            left: parent.left; right: parent.right; bottom: parent.bottom
                            leftMargin: 12; rightMargin: 12; bottomMargin: 10
                        }
                        spacing: 8

                        IconImage {
                            implicitSize: 20
                            source: root.iconFor(card.modelData.appClass)
                        }

                        Text {
                            Layout.fillWidth: true
                            text: card.modelData.title || card.modelData.appClass
                            color: Theme.foreground
                            font.pixelSize: 12
                            font.bold: card.selected
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            visible: card.modelData.workspace !== ""
                            implicitWidth: wsLabel.implicitWidth + 12
                            implicitHeight: 18
                            radius: 9
                            color: Theme.hexToRgba(Theme.color4, 0.25)

                            Text {
                                id: wsLabel
                                anchors.centerIn: parent
                                text: card.modelData.workspace.replace("special:", "")
                                color: Theme.foreground
                                font.pixelSize: 10
                                font.family: "Departure Mono"
                            }
                        }
                    }
                }
            }
        }
    }
}
