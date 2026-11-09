import qs
import qs.services
import qs.components
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

// Screenshot & recording menu. Screenshots go through grimblast (Esc cancels
// a selection; clicking a window instead of dragging grabs that window).
BaseExpandPopup {
    id: capture

    ipcTarget: "capture"
    placeholder: "Screenshot or record…"

    implicitWidth: 420
    implicitHeight: Math.min(620, 74 + Math.max(1, rows.length) * 44)

    minIndex: actionList.minIndex
    maxIndex: actionList.maxIndex

    readonly property string home: Quickshell.env("HOME")
    readonly property string shotDir: home + "/Pictures/Screenshots"

    property bool hasSatty: false
    Process {
        command: ["sh", "-c", "command -v satty"]
        running: true
        onExited: (code) => capture.hasSatty = code === 0
    }

    // Shell snippets; $DIR/$FILE are filled in by shot()
    readonly property var allActions: [
        { glyph: "󰩭", title: "Region to clipboard", subtitle: "Drag a region or click a window",
          shot: 'grimblast --notify --freeze copy area' },
        { glyph: "󰹑", title: "Region to file", subtitle: "Saved to ~/Pictures/Screenshots and copied",
          shot: 'grimblast --notify --freeze copysave area "$FILE"' },
        { glyph: "󰏫", title: "Region and annotate", subtitle: "Opens in satty to draw, crop or blur",
          shot: 'grimblast --freeze save area - | satty --filename - --output-filename "$FILE" --copy-command wl-copy --early-exit',
          needsSatty: true },
        { glyph: "󰖯", title: "Active window to clipboard", subtitle: "",
          shot: 'grimblast --notify copy active' },
        { glyph: "󰍹", title: "Screen to clipboard", subtitle: "The monitor you're on",
          shot: 'grimblast --notify copy output' },
        { glyph: "󰍹", title: "Screen to file", subtitle: "Saved and copied",
          shot: 'grimblast --notify copysave output "$FILE"' },
        { glyph: "󰔛", title: "Screen in 5 seconds", subtitle: "Saved and copied, time to open a menu first",
          shot: 'grimblast --notify --wait 5 copysave output "$FILE"' },
        { glyph: "󰑋", title: "Record region", subtitle: "Drag a region, stop from the bar",
          record: "region", audio: false },
        { glyph: "󰑋", title: "Record screen", subtitle: "Stop from the bar or Super+Shift+R",
          record: "screen", audio: false },
        { glyph: "󰕾", title: "Record screen with audio", subtitle: "Includes desktop sound",
          record: "screen", audio: true },
        { glyph: "󰉋", title: "Open screenshots folder", subtitle: "",
          folder: "Pictures/Screenshots" },
        { glyph: "󰉋", title: "Open recordings folder", subtitle: "",
          folder: "Videos/Recordings" }
    ]

    readonly property var rows: {
        let list = allActions
        if (Recorder.recording)
            list = [{ glyph: "󰓛", title: "Stop recording", subtitle: Recorder.elapsedLabel, stop: true }]
                .concat(list.filter(a => !a.record))
        const q = searchText.toLowerCase()
        if (q !== "") list = list.filter(a => a.title.toLowerCase().includes(q))
        return list
    }

    onSearchEdited: selectedIndex = 0
    onAccepted: (index) => capture.run(rows[index])

    function run(action) {
        if (!action) return
        if (action.needsSatty && !capture.hasSatty) {
            Quickshell.execDetached(["notify-send", "-a", "Screenshot", "Annotating needs satty",
                "Install the satty package"])
            return
        }
        // Close fast, then act once the popup is gone so it isn't in the shot
        capture.close(true)
        pending.action = action
        pending.restart()
    }

    Timer {
        id: pending
        property var action: null
        interval: 400
        onTriggered: {
            const a = action
            if (a.stop) Recorder.stop()
            else if (a.record) Recorder.start(a.record, a.audio)
            else if (a.folder) Quickshell.execDetached(["sh", "-c",
                'mkdir -p "$1" && exec uwsm app -- xdg-open "$1"', "sh", capture.home + "/" + a.folder])
            else if (a.shot) Quickshell.execDetached(["sh", "-c",
                'DIR="$1"; mkdir -p "$DIR"; FILE="$DIR/$(date +%Y-%m-%d_%H-%M-%S).png"; ' + a.shot,
                "sh", capture.shotDir])
        }
    }

    SelectableListView {
        id: actionList
        anchors.fill: parent
        model: capture.rows
        rowHeight: 42
        emptyText: "No matching actions"

        onSelectedIndexChanged: if (capture.selectedIndex !== selectedIndex) capture.selectedIndex = selectedIndex
        Connections {
            target: capture
            function onSelectedIndexChanged() {
                if (actionList.selectedIndex !== capture.selectedIndex) actionList.selectedIndex = capture.selectedIndex
            }
        }

        delegate: Component {
            RowLayout {
                id: row
                property var modelData
                property int index
                property bool selected: false

                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                spacing: 12

                Text {
                    Layout.preferredWidth: 22
                    horizontalAlignment: Text.AlignHCenter
                    text: row.modelData?.glyph ?? ""
                    color: row.modelData?.stop || row.modelData?.record ? Theme.color1 : Theme.foreground
                    font.pixelSize: 17
                    font.family: "Symbols Nerd Font"
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        Layout.fillWidth: true
                        text: row.modelData?.title ?? ""
                        color: Theme.foreground
                        font.pixelSize: 13
                        font.bold: row.selected
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: row.modelData?.subtitle ?? ""
                        visible: text !== ""
                        color: Theme.hexToRgba(Theme.foreground, 0.5)
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }

                TapHandler { onTapped: capture.run(row.modelData) }
            }
        }
    }
}
