import qs
import qs.components
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Clipboard history (cliphist) with pinned entries and image previews.
//   Enter / click    copy the entry          Ctrl+P   pin / unpin it
//   Ctrl+D           remove it                   row 0    clear history (pins stay)
// Pins live in Quickshell's data dir, so clearing or rotating cliphist history
// never drops them; pinned images are copied there too.
BaseExpandPopup {
    id: clipboard

    ipcTarget: "clipboard"
    placeholder: "Search clipboard…   Ctrl+P pin · Ctrl+D remove"

    implicitWidth: 420
    // The list keeps its own height; the preview area is added below it and
    // stays once shown (until the popup closes), so stepping through a mix of
    // text and images doesn't keep resizing the popup
    readonly property int listHeight: Math.min(500, 106 + Math.max(1, filteredEntries.length) * 34)
    implicitHeight: listHeight + (previewReserved ? previewHeight + 8 : 0)

    searchHeight: 40
    columnSpacing: 6
    searchFontSize: 13
    searchIconSize: 14

    minIndex: entryList.minIndex
    maxIndex: entryList.maxIndex

    readonly property int previewHeight: 200
    readonly property string cacheDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-clipboard"
    readonly property string pinDir: Quickshell.dataPath("clipboard-pins")

    property var entries: []

    // ── PINS ───────────────────────────────────────────────────
    FileView {
        path: Quickshell.dataPath("clipboard-pins.json")
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        JsonAdapter {
            id: pinStore
            // [{ text } | { image: "/path/to/file", label }]
            property var pins: []
        }
    }

    readonly property var pinEntries: (pinStore.pins || []).map((p, i) => ({
        pinned: true,
        pinIndex: i,
        content: p.image ? (p.label || "Image") : p.text,
        imageFile: p.image || ""
    }))

    function pinnedText(text) {
        return (pinStore.pins || []).some(p => p.text === text)
    }

    // ── LIST ───────────────────────────────────────────────────
    readonly property string query: searchText.toLowerCase()
    readonly property var filteredEntries: {
        // History entries that are already pinned would just be duplicates
        const history = entries.filter(e => e.imageFile !== "" || !clipboard.pinnedText(e.content))
        const all = pinEntries.concat(history)
        if (query === "") return all
        return all.filter(e => e.content.toLowerCase().includes(query))
    }

    readonly property var selectedEntry: selectedIndex > 0 ? filteredEntries[selectedIndex - 1] ?? null : null
    readonly property string previewImage: selectedEntry && selectedEntry.imageFile ? selectedEntry.imageFile : ""

    // What the preview shows, updated only once the selection settles so
    // scrolling quickly through the list doesn't strobe
    property bool previewReserved: false
    property string shownImage: ""
    property bool previewOnImage: false

    onPreviewImageChanged: previewSettle.restart()

    Timer {
        id: previewSettle
        interval: 90
        onTriggered: {
            clipboard.previewOnImage = clipboard.previewImage !== ""
            if (clipboard.previewOnImage) {
                clipboard.shownImage = clipboard.previewImage
                clipboard.previewReserved = true
            }
        }
    }

    onOpened: {
        previewReserved = false
        previewOnImage = false
        shownImage = ""
        loadProc.running = true
    }

    onSearchEdited: selectedIndex = (searchText !== "" && filteredEntries.length > 0) ? 1 : 0

    onAccepted: (index) => {
        if (index === 0) {
            clearProc.running = true
            close()
        } else {
            paste(filteredEntries[index - 1])
        }
    }

    Shortcut {
        sequence: "Ctrl+P"
        enabled: clipboard.visible
        onActivated: clipboard.togglePin(clipboard.selectedEntry)
    }
    Shortcut {
        // Ctrl+Delete would be swallowed by the search field (delete word)
        sequence: "Ctrl+D"
        enabled: clipboard.visible
        onActivated: clipboard.remove(clipboard.selectedEntry)
    }

    function paste(entry) {
        if (!entry) return
        if (entry.imageFile !== "" && (entry.pinned || !entry.raw)) {
            Quickshell.execDetached(["sh", "-c", 'exec wl-copy < "$1"', "sh", entry.imageFile])
        } else if (entry.pinned) {
            Quickshell.execDetached(["wl-copy", "--", entry.content])
        } else {
            Quickshell.execDetached(["sh", "-c", 'printf "%s\\n" "$1" | cliphist decode | wl-copy', "sh", entry.raw])
        }
        close()
    }

    function togglePin(entry) {
        if (!entry) return
        const pins = (pinStore.pins || []).slice()
        if (entry.pinned) {
            const removed = pins.splice(entry.pinIndex, 1)[0]
            if (removed && removed.image) Quickshell.execDetached(["rm", "-f", "--", removed.image])
        } else if (entry.imageFile !== "") {
            // Copy out of the runtime cache so the pin survives reboots
            const file = clipboard.pinDir + "/" + Date.now() + "." + (entry.ext || "png")
            Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && cp -- "$2" "$3"', "sh",
                clipboard.pinDir, entry.imageFile, file])
            pins.unshift({ image: file, label: entry.content })
        } else {
            pins.unshift({ text: entry.content })
        }
        pinStore.pins = pins
        clipboard.selectedIndex = Math.min(clipboard.selectedIndex, clipboard.filteredEntries.length)
    }

    function remove(entry) {
        if (!entry) return
        if (entry.pinned) {
            togglePin(entry)
            return
        }
        deleteProc.command = ["sh", "-c", 'printf "%s\\n" "$1" | cliphist delete', "sh", entry.raw]
        deleteProc.running = true
        clipboard.entries = clipboard.entries.filter(e => e.id !== entry.id)
    }

    // ── HISTORY ────────────────────────────────────────────────
    Process {
        id: loadProc
        command: ["/usr/bin/cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const imageIds = []
                const lines = text.trim().split("\n").filter(l => l.length > 0)
                clipboard.entries = lines.map(line => {
                    const tab = line.indexOf("\t")
                    const id = tab >= 0 ? line.substring(0, tab) : line
                    const content = tab >= 0 ? line.substring(tab + 1) : line
                    // e.g. "[[ binary data 372 KiB png 1920x1080 ]]"
                    const img = /^\[\[ binary data (.+?) (png|jpe?g|webp|gif|bmp) (\d+x\d+) \]\]$/.exec(content)
                    if (img) imageIds.push(id + "." + img[2])
                    return {
                        pinned: false,
                        id: id,
                        raw: line,
                        content: img ? "Image " + img[3] + " · " + img[1] : content,
                        ext: img ? img[2] : "",
                        imageFile: img ? clipboard.cacheDir + "/" + id + "." + img[2] : ""
                    }
                })
                if (imageIds.length > 0) {
                    decodeProc.command = ["sh", "-c",
                        'd="$1"; shift; mkdir -p "$d"; for f; do [ -s "$d/$f" ] || cliphist decode "${f%.*}" > "$d/$f"; done',
                        "sh", clipboard.cacheDir].concat(imageIds)
                    decodeProc.running = true
                }
            }
        }
    }

    // Decodes images into the runtime cache once; bumping the revision makes
    // the thumbnails reload after decoding finishes
    property int decodeRevision: 0
    Process {
        id: decodeProc
        onExited: clipboard.decodeRevision++
    }

    Process { id: deleteProc }

    Process {
        id: clearProc
        command: ["/usr/bin/cliphist", "wipe"]
        onRunningChanged: {
            if (!running) {
                notifyProc.running = true
                clipboard.entries = []
            }
        }
    }

    Process {
        id: notifyProc
        command: ["/usr/bin/notify-send", "Clipboard", "History cleared (pinned entries kept)"]
    }

    function imageUrl(file) {
        return file ? "file://" + file + "?r=" + clipboard.decodeRevision : ""
    }

    // Not anchored to the bottom: the card's height animation then just reveals
    // the preview instead of squeezing the list while it catches up
    ColumnLayout {
        anchors { top: parent.top; left: parent.left; right: parent.right }
        spacing: 8

        SelectableListView {
            id: entryList
            Layout.fillWidth: true
            // listHeight minus the card's margins, search box and spacing
            Layout.preferredHeight: clipboard.listHeight - 24 - clipboard.searchHeight - clipboard.columnSpacing
            model: clipboard.filteredEntries
            rowHeight: 32
            headerHeight: 36
            accentColor: Theme.color5
            headerAccentColor: Theme.color1
            emptyText: clipboard.query !== "" ? "No matches found" : "Clipboard is empty"

            onSelectedIndexChanged: if (clipboard.selectedIndex !== selectedIndex) clipboard.selectedIndex = selectedIndex
            Connections {
                target: clipboard
                function onSelectedIndexChanged() {
                    if (entryList.selectedIndex !== clipboard.selectedIndex) entryList.selectedIndex = clipboard.selectedIndex
                }
            }

            header: Component {
                RowLayout {
                    property bool selected: false
                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                    spacing: 8

                    Text {
                        text: "󰃢"
                        color: selected ? Theme.background : Theme.color1
                        font.pixelSize: 14
                        font.family: "Symbols Nerd Font"
                    }
                    Text {
                        text: "Clear History"
                        color: selected ? Theme.background : Theme.color1
                        font.pixelSize: 13
                        font.bold: selected
                    }

                    TapHandler {
                        onTapped: {
                            clearProc.running = true
                            clipboard.close()
                        }
                    }
                }
            }

            delegate: Component {
                Item {
                    id: row
                    property var modelData
                    property int index
                    property bool selected: false

                    property bool flashing: false

                    readonly property string content: row.modelData?.content ?? ""
                    readonly property bool isImage: (row.modelData?.imageFile ?? "") !== ""
                    readonly property bool isPinned: row.modelData?.pinned ?? false
                    readonly property bool isPath: content.startsWith("/") || content.startsWith("~/")
                    readonly property bool isUrl: content.startsWith("http://") || content.startsWith("https://")
                    readonly property bool isCode: content.startsWith("$") || content.includes("{") || content.includes("()")

                    readonly property color rowAccentColor: {
                        if (isPinned) return Theme.color4
                        if (isImage) return Theme.color3
                        if (isUrl)   return Theme.color6
                        if (isPath)  return Theme.color5
                        if (isCode)  return Theme.color2
                        return Theme.hexToRgba(Theme.foreground, 0.2)
                    }

                    // Flash feedback overlays the shared selection highlight
                    // briefly on tap, same as the original.
                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: Theme.hexToRgba(Theme.color5, 0.4)
                        opacity: row.flashing ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 100 } }
                    }

                    RowLayout {
                        anchors.fill: parent
                        spacing: 0

                        Rectangle {
                            width: 3
                            height: parent.height * 0.6
                            radius: 2
                            color: row.rowAccentColor
                            Layout.leftMargin: 6
                            Layout.alignment: Qt.AlignVCenter
                        }

                        // Small thumbnail for images
                        Image {
                            visible: row.isImage
                            Layout.leftMargin: 8
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 24
                            Layout.alignment: Qt.AlignVCenter
                            source: row.isImage ? clipboard.imageUrl(row.modelData.imageFile) : ""
                            sourceSize: Qt.size(72, 48)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            TapHandler { onTapped: row.activate() }
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.leftMargin: 8
                            Layout.rightMargin: 8
                            verticalAlignment: Text.AlignVCenter

                            text: row.content
                            color: row.selected
                                ? Theme.background
                                : (row.isImage ? Theme.color3 : Theme.foreground)
                            font.pixelSize: 12
                            font.family: "Departure Mono"
                            elide: Text.ElideRight

                            // Copy on click; kept off the pin icon so pinning doesn't also copy
                            TapHandler { onTapped: row.activate() }
                        }

                        Text {
                            text: row.isPinned ? "󰐃" : "#" + row.index
                            color: row.isPinned
                                ? Theme.color4
                                : (row.selected
                                    ? Theme.hexToRgba(Theme.background, 0.5)
                                    : Theme.hexToRgba(Theme.foreground, 0.25))
                            font.pixelSize: row.isPinned ? 13 : 10
                            font.family: row.isPinned ? "Symbols Nerd Font" : "Departure Mono"
                            Layout.rightMargin: 10
                            Layout.alignment: Qt.AlignVCenter

                            // Click the pin / number to pin or unpin
                            TapHandler { onTapped: clipboard.togglePin(row.modelData) }
                        }
                    }

                    function activate() {
                        row.flashing = true
                        flashTimer.start()
                    }

                    Timer {
                        id: flashTimer
                        interval: 120
                        onTriggered: {
                            row.flashing = false
                            clipboard.paste(row.modelData)
                        }
                    }
                }
            }
        }

        // Larger preview of the selected image
        Rectangle {
            visible: clipboard.previewReserved
            Layout.fillWidth: true
            Layout.preferredHeight: clipboard.previewHeight
            radius: 10
            color: Theme.hexToRgba(Theme.foreground, 0.05)

            Image {
                anchors { fill: parent; margins: 6 }
                source: clipboard.imageUrl(clipboard.shownImage)
                sourceSize: Qt.size(816, 400)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                // Keep the previous image up until the next one has decoded
                retainWhileLoading: true
                // Dimmed (not hidden) while a text entry is selected
                opacity: clipboard.previewOnImage ? 1 : 0.15
                Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            }

            Text {
                anchors.centerIn: parent
                text: "No preview for text"
                color: Theme.hexToRgba(Theme.foreground, 0.4)
                font.pixelSize: 11
                opacity: clipboard.previewOnImage ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }
        }
    }
}
