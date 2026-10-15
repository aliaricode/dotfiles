import qs
import qs.services
import qs.components
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

BaseExpandPopup {
    id: root

    ipcTarget: "wallpaper"
    showSearch: false
    focusSearchOnOpen: false

    readonly property string homeDir: Quickshell.env("HOME") ?? ""
    readonly property string wallpaperRoot: root.homeDir + "/Pictures/wallpapers"
    readonly property string scriptsDir: root.homeDir + "/.config/quickshell/scripts"

    implicitWidth: barWindow ? barWindow.width * 0.50 : 1200
    implicitHeight: 190

    heightPhaseMultiplier: 4000

    property int applyingIndex: -1
    property string pendingFilename: ""
    property double lastScanTime: 0

    onOpened: {
        applyingIndex = -1
        root.selectedTarget = root.openedScreenName
        if (root.wallpapers.length === 0 || Date.now() - root.lastScanTime > 30000) {
            root.lastScanTime = Date.now()
            wallpaperScanner.running = true
        } else {
            root.reshuffle()
        }
        syncPresetSelection()
    }

    onAnimInChanged: if (!animIn) {
        applyTimer.stop()
        root.applyingIndex = -1
    }

    property var thumbPaths: ({})
    property var wallpapers: []
    property string currentWallpaper: ""

    // ---- monitor targeting ----
    property var wallpaperByMonitor: ({})
    property string selectedTarget: "All"
    readonly property string monitorStateFile: root.homeDir + "/.cache/quickshell/monitor-wallpapers.json"

    readonly property string themeScreenOverride: ""

    readonly property string openedScreenName: barWindow?.screen?.name ?? Hyprland.focusedMonitor?.name ?? ""

    readonly property var screenNames: {
        const names = []
        for (let i = 0; i < Quickshell.screens.length; i++) names.push(Quickshell.screens[i].name)
        return names
    }
    readonly property var targets: ["All", ...root.screenNames]
    readonly property string effectiveTarget: root.targets.includes(root.selectedTarget) ? root.selectedTarget : "All"

    readonly property string themeScreenName: {
        if (root.themeScreenOverride !== "") return root.themeScreenOverride
        let best = ""
        let bestArea = -1
        for (let i = 0; i < Quickshell.screens.length; i++) {
            const s = Quickshell.screens[i]
            if (s.width * s.height > bestArea) {
                bestArea = s.width * s.height
                best = s.name
            }
        }
        return best
    }

    function screenByName(name) {
        for (let i = 0; i < Quickshell.screens.length; i++) {
            if (Quickshell.screens[i].name === name) return Quickshell.screens[i]
        }
        return null
    }

    function wallpaperFor(name) {
        return root.wallpaperByMonitor[name] ?? root.currentWallpaper
    }

    function isShownOn(path) {
        const t = root.effectiveTarget
        if (t === "All") {
            const names = root.screenNames
            if (names.length === 0) return path === root.currentWallpaper
            return names.every(n => root.wallpaperFor(n) === path)
        }
        return root.wallpaperFor(t) === path
    }

    function cycleTarget(step) {
        const list = root.targets
        const idx = list.indexOf(root.effectiveTarget)
        root.selectedTarget = list[(idx + step + list.length) % list.length]
    }

    readonly property real targetAspect: {
        const s = root.screenByName(root.effectiveTarget)
        return s && s.height > 0 ? s.width / s.height : 0
    }
    readonly property real thumbWidth: root.targetAspect > 0
        ? Math.round(Math.max(90, Math.min(480, thumbList.height * root.targetAspect)))
        : 200

    FileView {
        id: monitorStateFileView
        path: root.monitorStateFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.wallpaperByMonitor = JSON.parse(monitorStateFileView.text() || "{}")
            } catch (e) {
                root.wallpaperByMonitor = {}
            }
        }
        onLoadFailed: root.wallpaperByMonitor = {}
    }

    // ---- categories (subfolders under Pictures/wallpapers) ----
    property var categories: []
    property string selectedCategory: "All"
    readonly property var filteredWallpapers: root.selectedCategory === "All"
        ? root.wallpapers
        : root.wallpapers.filter(f => f.split("/")[0] === root.selectedCategory)

    // ---- shuffle (display order only; doesn't touch actual scan order) ----
    property var shuffledFiltered: []

    function shuffleArray(arr) {
        const a = arr.slice()
        for (let i = a.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1))
            const tmp = a[i]
            a[i] = a[j]
            a[j] = tmp
        }
        return a
    }

    function reshuffle() {
        root.shuffledFiltered = root.shuffleArray(root.filteredWallpapers)
    }

    onFilteredWallpapersChanged: root.reshuffle()

    function cycleCategory(step) {
        const list = ["All", ...root.categories]
        if (list.length === 0) return
        const idx = list.indexOf(root.selectedCategory)
        const next = (idx + step + list.length) % list.length
        root.selectedCategory = list[next]
    }

    function toggleTab() {
        root.showingThemeTab = !root.showingThemeTab
    }

    // ---- theme presets ----
    property bool showingThemeTab: false
    readonly property var themePresets: ["default", "vibrant", "calm", "mono", "remix"]
    property string previewedWallpaper: ""
    property bool generatingPresets: false
    property var presetPreviewPaths: ({})
    property var lastPresetByWallpaper: ({})
    readonly property string lastPresetStateFile: root.homeDir + "/.cache/quickshell/last-presets.json"
    readonly property string currentWallpaperStateFile: root.homeDir + "/.cache/quickshell/current-wallpaper"

    function generatePresetsFor(wallpaper) {
        root.previewedWallpaper = wallpaper
        root.generatingPresets = true
        presetWatchdog.restart()
        if (generateAllProc.running) {
            generateAllProc.running = false
        }
        generateAllProc.command = [
            root.homeDir + "/.config/quickshell/scripts/generate-presets.sh",
            wallpaper,
            root.homeDir + "/.config/wallust/presets",
            "/tmp",
            ...root.themePresets
        ]
        generateAllProc.running = true
    }

    function syncPresetSelection() {
        const last = root.lastPresetByWallpaper[root.currentWallpaper]
        presetList.currentIndex = last ? root.themePresets.indexOf(last) : -1
    }

    onShowingThemeTabChanged: {
        if (showingThemeTab) {
            root.syncPresetSelection()
            if (root.previewedWallpaper !== root.currentWallpaper) {
                root.generatePresetsFor(root.currentWallpaper)
            }
        }
    }

    Process {
        id: generateAllProc
        command: []
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) return
            // running === true means a newer generation already superseded
            // this one — its own exit will handle the flag.
            if (generateAllProc.running) return
            presetWatchdog.stop()
            root.generatingPresets = false
        }
        stdout: StdioCollector {
                onStreamFinished: {
                  const map = {}
                  if (text) {
                      for (const line of text.trim().split("\n")) {
                          const i = line.indexOf(":")
                          if (i > 0) map[line.slice(0, i)] = line.slice(i + 1)
                      }
                  }

                  if (map["#wallpaper"] !== root.previewedWallpaper) return
                  delete map["#wallpaper"]

                  presetWatchdog.stop()
                  root.presetPreviewPaths = map
                  root.generatingPresets = false
                }
        }
    }

    // ---- last-used preset memory (persisted to disk) ----
    FileView {
        id: lastPresetFile
        path: root.lastPresetStateFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.lastPresetByWallpaper = JSON.parse(lastPresetFile.text() || "{}")
            } catch (e) {
                root.lastPresetByWallpaper = {}
            }
            if (root.visible) root.syncPresetSelection()
        }
        onLoadFailed: root.lastPresetByWallpaper = {}
    }

    Process {
        id: savePresetChoiceProc
        command: []
    }

    Process {
        id: applyThemeProc
        command: []
    }

    function applyPreset(name) {
        applyThemeProc.command = [
            root.homeDir + "/.config/quickshell/scripts/apply-theme.sh",
            root.currentWallpaper,
            root.homeDir + "/.config/wallust/presets/" + name + ".toml"
        ]
        applyThemeProc.running = true

        const map = Object.assign({}, root.lastPresetByWallpaper)
        map[root.currentWallpaper] = name
        root.lastPresetByWallpaper = map
        savePresetChoiceProc.command = [
            root.homeDir + "/.config/quickshell/scripts/save-last-preset.sh",
            root.currentWallpaper,
            name,
            root.lastPresetStateFile
        ]
        savePresetChoiceProc.running = true

        close()
    }

    Process {
        id: wallpaperScanner
        command: [root.scriptsDir + "/scan-wallpapers.sh", root.wallpaperRoot]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text) return
                const files = []
                const thumbs = {}
                for (const line of text.trim().split("\n")) {
                    const i = line.indexOf("\t")
                    if (i <= 0) continue
                    const rel = line.slice(0, i)
                    files.push(rel)
                    thumbs[rel] = line.slice(i + 1)
                }
                root.wallpapers = files
                root.thumbPaths = thumbs
                root.categories = [...new Set(files.map(f => f.split("/")[0]))].sort()
                if (root.selectedCategory !== "All" && !root.categories.includes(root.selectedCategory)) {
                    root.selectedCategory = "All"
                }
            }
        }
    }

    FileView {
        id: currentWallpaperFile
        path: root.currentWallpaperStateFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const p = currentWallpaperFile.text().trim()
            if (p) root.currentWallpaper = p
        }
    }

    Process {
        id: applyWallpaperProc
        command: []
    }

    function applyWallpaper(filename, index) {
        if (root.applyingIndex !== -1) return
        root.applyingIndex = index
        root.pendingFilename = filename
        applyTimer.start()
    }

    Timer {
        id: applyTimer
        interval: 220
        onTriggered: root.commitWallpaper()
    }

    Timer {
        id: presetWatchdog
        interval: 20000
        onTriggered: root.generatingPresets = false
    }

    function commitWallpaper() {
        const path = root.wallpaperRoot + "/" + root.pendingFilename
        const target = root.effectiveTarget
        // Only the theme monitor (or "All") is allowed to retint the shell.
        const drivesTheme = target === "All" || target === root.themeScreenName

        // No --output means every monitor (the old behaviour); the script's
        // second positional argument is still the optional preset path.
        applyWallpaperProc.command = [
            root.homeDir + "/.config/quickshell/scripts/apply-wallpaper.sh",
            path,
            ...(target === "All" ? [] : ["--output", target]),
            ...(drivesTheme ? [] : ["--no-theme"])
        ]
        applyWallpaperProc.running = true

        // Optimistic update so checkmarks are right even before the script
        // has rewritten the state file.
        const map = Object.assign({}, root.wallpaperByMonitor)
        for (const n of (target === "All" ? root.screenNames : [target])) map[n] = path
        root.wallpaperByMonitor = map

        if (drivesTheme) {
            root.currentWallpaper = path
            root.generatePresetsFor(path)
        }
        close()
    }

    // ---- content ----
    RowLayout {
        id: tabRow
        anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
        height: 26
        spacing: 6

        Rectangle {
            Layout.preferredWidth: 90
            Layout.fillHeight: true
            radius: 8
            color: !root.showingThemeTab ? Theme.hexToRgba(Theme.color5, 0.25) : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
            Text {
                anchors.centerIn: parent
                text: "Wallpaper"
                color: Theme.foreground
                font.pixelSize: 11
                font.bold: !root.showingThemeTab
            }
            TapHandler { onTapped: root.showingThemeTab = false }
        }
        Rectangle {
            Layout.preferredWidth: 90
            Layout.fillHeight: true
            radius: 8
            color: root.showingThemeTab ? Theme.hexToRgba(Theme.color5, 0.25) : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
            Text {
                anchors.centerIn: parent
                text: "Theme"
                color: Theme.foreground
                font.pixelSize: 11
                font.bold: root.showingThemeTab
            }
            TapHandler { onTapped: root.showingThemeTab = true }
        }
    }

    // Target monitor chips (wallpaper tab only, and only with 2+ screens)
    Row {
        id: targetRow
        anchors { top: parent.top; right: parent.right }
        height: tabRow.height
        spacing: 6
        visible: !root.showingThemeTab && root.screenNames.length > 1

        Text {
            height: targetRow.height
            verticalAlignment: Text.AlignVCenter
            text: "Apply to"
            color: Theme.hexToRgba(Theme.foreground, 0.5)
            font.pixelSize: 10
        }

        Repeater {
            model: root.targets

            delegate: Rectangle {
                readonly property bool isSelected: root.effectiveTarget === modelData
                readonly property var scr: root.screenByName(modelData)
                readonly property bool isThemeScreen: modelData === root.themeScreenName

                width: targetLabel.implicitWidth + 16
                height: targetRow.height
                radius: 8
                color: isSelected ? Theme.hexToRgba(Theme.color5, 0.3) : Theme.hexToRgba(Theme.foreground, 0.06)
                border.color: isSelected ? Theme.color5 : "transparent"
                border.width: 1
                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    id: targetLabel
                    anchors.centerIn: parent
                    text: (isThemeScreen ? "● " : "") + modelData
                        + (scr ? "  " + scr.width + "×" + scr.height : "")
                    color: Theme.foreground
                    font.pixelSize: 10
                    font.bold: isSelected
                }
                TapHandler { onTapped: root.selectedTarget = modelData }
            }
        }
    }

    Item {
        id: categoryRowContainer
        anchors { top: tabRow.bottom; left: parent.left; right: parent.right; topMargin: 6 }
        height: 22
        visible: !root.showingThemeTab && root.categories.length > 0

        ListView {
            id: categoryRow
            anchors.fill: parent
            orientation: ListView.Horizontal
            spacing: 6
            clip: true
            model: ["All", ...root.categories]

            delegate: Rectangle {
                readonly property bool isSelected: root.selectedCategory === modelData
                width: chipLabel.implicitWidth + 16
                height: categoryRow.height
                radius: 6
                color: isSelected ? Theme.hexToRgba(Theme.color5, 0.3) : Theme.hexToRgba(Theme.foreground, 0.06)
                border.color: isSelected ? Theme.color5 : "transparent"
                border.width: 1
                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    id: chipLabel
                    anchors.centerIn: parent
                    text: modelData
                    color: Theme.foreground
                    font.pixelSize: 10
                    font.bold: isSelected
                }
                TapHandler { onTapped: root.selectedCategory = modelData }
            }
        }

        // Edge fades hint that there's more to scroll when chips overflow the row
        Rectangle {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: 18
            visible: categoryRow.contentWidth > categoryRow.width && !categoryRow.atXBeginning
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Theme.hexToRgba(Theme.background, 0.92) }
                GradientStop { position: 1.0; color: Theme.hexToRgba(Theme.background, 0.0) }
            }
        }
        Rectangle {
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: 18
            visible: categoryRow.contentWidth > categoryRow.width && !categoryRow.atXEnd
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Theme.hexToRgba(Theme.background, 0.0) }
                GradientStop { position: 1.0; color: Theme.hexToRgba(Theme.background, 0.92) }
            }
        }
    }

    ListView {
        id: thumbList
        anchors {
            top: root.categories.length > 0 ? categoryRowContainer.bottom : tabRow.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            topMargin: 6
        }
        visible: !root.showingThemeTab
        orientation: ListView.Horizontal
        spacing: 8
        clip: true
        model: root.shuffledFiltered

        flickDeceleration: 3000
        maximumFlickVelocity: 4000

        Keys.onReturnPressed: {
            if (currentIndex >= 0 && currentIndex < root.shuffledFiltered.length) {
                root.applyWallpaper(root.shuffledFiltered[currentIndex], currentIndex)
            }
        }
        Keys.onTabPressed: (event) => {
            root.toggleTab()
            event.accepted = true
        }
        Keys.onBacktabPressed: (event) => {
            root.toggleTab()
            event.accepted = true
        }
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Space) {
                root.cycleCategory(event.modifiers & Qt.ShiftModifier ? -1 : 1)
                event.accepted = true
            } else if (event.key === Qt.Key_R) {
                root.reshuffle()
                event.accepted = true
            } else if (event.key === Qt.Key_M) {
                root.cycleTarget(event.modifiers & Qt.ShiftModifier ? -1 : 1)
                event.accepted = true
            }
        }

        highlight: Item {
            z: 2
            width: root.thumbWidth
            height: thumbList.height

            Rectangle {
                anchors.fill: parent
                anchors.margins: -2
                radius: 12
                color: "transparent"
                border.color: Theme.hexToRgba(Theme.color5, 0.3)
                border.width: 4
            }
            Rectangle {
                anchors.fill: parent
                radius: 10
                color: "transparent"
                border.color: Theme.color5
                border.width: 2
            }
        }
        highlightFollowsCurrentItem: true
        highlightMoveDuration: 120
        focus: !root.showingThemeTab

        delegate: Item {
            id: thumb
            width: root.thumbWidth
            height: thumbList.height
            readonly property string filename: modelData
            readonly property bool isCurrent: root.isShownOn(root.wallpaperRoot + "/" + filename)
            readonly property bool applying: index === root.applyingIndex

            scale: applying ? 1.05 : 1.0
            Behavior on scale {
                NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
            }

            Rectangle {
                anchors.fill: parent
                radius: 10
                color: "transparent"
                border.color: Theme.hexToRgba(Theme.color5, 0.8)
                border.width: 2
                visible: thumb.isCurrent
            }

            Image {
                id: thumbImg
                anchors.fill: parent
                anchors.margins: thumb.isCurrent ? 3 : 0
                source: "file://" + (root.thumbPaths[filename]
                    ?? (root.homeDir + "/Pictures/wallpapers/" + filename))
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: Math.max(400, root.thumbWidth * 2)
                asynchronous: true
                cache: true

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: Theme.hexToRgba(Theme.background, thumb.isCurrent ? 0 : 0.25)
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }

            Rectangle {
                id: placeholder
                anchors.fill: parent
                radius: 10
                color: Theme.hexToRgba(Theme.foreground, 0.05)
                opacity: thumbImg.status === Image.Ready ? 0 : 1
                visible: opacity > 0
                Behavior on opacity {
                    NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: Theme.hexToRgba(Theme.foreground, 0.06)
                    SequentialAnimation on opacity {
                        running: placeholder.visible
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.2; to: 0.8; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 0.8; to: 0.2; duration: 700; easing.type: Easing.InOutSine }
                    }
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 24
                radius: 8
                color: Theme.hexToRgba(Theme.background, 0.7)

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 8
                    text: filename.split("/").pop().replace(/\.[^.]+$/, "")
                    color: Theme.foreground
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 6
                width: 20
                height: 20
                radius: 10
                color: Theme.color5
                visible: thumb.isCurrent

                Text {
                    anchors.centerIn: parent
                    text: "󰄬"
                    color: Theme.background
                    font.pixelSize: 12
                    font.family: "Symbols Nerd Font"
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: 44
                height: 44
                radius: 22
                color: Theme.hexToRgba(Theme.color5, 0.9)
                opacity: thumb.applying ? 1 : 0
                scale: thumb.applying ? 1 : 0.6
                Behavior on opacity { NumberAnimation { duration: 150 } }
                Behavior on scale {
                    NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                }

                Text {
                    anchors.centerIn: parent
                    text: "󰄬"
                    color: Theme.background
                    font.pixelSize: 22
                    font.family: "Symbols Nerd Font"
                }
            }

            TapHandler {
                onTapped: root.applyWallpaper(thumb.filename, index)
            }
        }
    }

    Text {
        anchors.centerIn: thumbList
        text: "Loading wallpapers…"
        color: Theme.hexToRgba(Theme.foreground, 0.5)
        font.pixelSize: 12
        visible: !root.showingThemeTab && wallpaperScanner.running && root.wallpapers.length === 0
    }

    ListView {
        id: presetList
        anchors {
            top: tabRow.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            topMargin: 6
        }
        visible: root.showingThemeTab
        orientation: ListView.Horizontal
        spacing: 8
        clip: true
        model: root.themePresets
        focus: root.showingThemeTab

        Keys.onReturnPressed: {
            if (currentIndex >= 0 && currentIndex < root.themePresets.length) {
                root.applyPreset(root.themePresets[currentIndex])
            }
        }
        Keys.onTabPressed: (event) => {
            root.toggleTab()
            event.accepted = true
        }
        Keys.onBacktabPressed: (event) => {
            root.toggleTab()
            event.accepted = true
        }

        delegate: Item {
            id: presetThumb
            width: 160
            height: presetList.height
            readonly property string presetName: modelData
            readonly property bool isGenerating: root.generatingPresets

            FileView {
                id: previewFile
                path: root.presetPreviewPaths[presetThumb.presetName] ?? ""
                watchChanges: true
                onFileChanged: reload()
                JsonAdapter {
                    id: swatchAdapter
                    property string background: "#000000"
                    property string foreground: "#ffffff"
                    property string color0: "#000000"
                    property string color1: "#000000"
                    property string color2: "#000000"
                    property string color3: "#000000"
                    property string color4: "#000000"
                    property string color5: "#000000"
                    property string color6: "#000000"
                    property string color7: "#000000"
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: 10
                color: Theme.hexToRgba(Theme.foreground, 0.05)
                border.color: presetList.currentIndex === index
                    ? Theme.color5 : Theme.hexToRgba(Theme.foreground, 0.1)
                border.width: presetList.currentIndex === index ? 2 : 1
                Behavior on border.color { ColorAnimation { duration: 120 } }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    GridLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        columns: 4
                        rowSpacing: 4
                        columnSpacing: 4

                        Repeater {
                            model: [
                                swatchAdapter.color1, swatchAdapter.color2,
                                swatchAdapter.color3, swatchAdapter.color4,
                                swatchAdapter.color5, swatchAdapter.color6,
                                swatchAdapter.color7, swatchAdapter.background
                            ]
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 4
                                color: modelData
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: presetThumb.presetName
                        color: Theme.foreground
                        font.pixelSize: 11
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: Theme.hexToRgba(Theme.background, 0.5)
                    visible: presetThumb.isGenerating
                    Text {
                        anchors.centerIn: parent
                        text: "…"
                        color: Theme.foreground
                        font.pixelSize: 18
                    }
                }
            }

            TapHandler {
                onTapped: root.applyPreset(presetThumb.presetName)
            }
        }
    }
}
