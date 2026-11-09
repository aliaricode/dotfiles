import qs
import qs.components
import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

BaseExpandPopup {
    id: launcher

    ipcTarget: "launcher"
    placeholder: "Search applications..."

    implicitWidth: 480
    implicitHeight: Math.min(600, 74 + filteredApps.length * 50)

    searchHeight: 44
    columnSpacing: 8
    searchFontSize: 14
    searchIconSize: 16

    minIndex: appsList.minIndex
    maxIndex: appsList.maxIndex

    readonly property var allApps: DesktopEntries.applications.values
    readonly property string query: searchText.toLowerCase()
    readonly property var filteredApps: {
        const named = allApps.filter(app => app.name)

        if (query === "") return named.slice().sort((a, b) => a.name.localeCompare(b.name))

        const q = query
        return named.filter(app => app.name.toLowerCase().includes(q)).sort((a, b) => {
            const aStarts = a.name.toLowerCase().startsWith(q)
            const bStarts = b.name.toLowerCase().startsWith(q)
            if (aStarts && !bStarts) return -1
            if (!aStarts && bStarts) return 1
            return a.name.localeCompare(b.name)
        })
    }

    onSearchEdited: selectedIndex = 0

    onAccepted: (index) => launcher.launch(filteredApps[index])

    // Launched through `uwsm app` so each app gets its own systemd scope in the
    // uwsm session instead of running as a child of the shell
    function launch(app) {
        if (!app) return
        const terminal = Quickshell.env("TERMINAL") || "alacritty"
        const cmd = app.runInTerminal ? [terminal, "-e"].concat(app.command) : app.command
        Quickshell.execDetached({
            command: ["uwsm", "app", "--"].concat(cmd),
            workingDirectory: app.workingDirectory
        })
        close()
    }

    function resolveIcon(name) {
        if (!name) return ""
        const primary = Quickshell.iconPath(name, true)
        if (primary !== "") return primary
        return Quickshell.iconPath("application-x-executable", true)
    }

    SelectableListView {
        id: appsList
        anchors.fill: parent
        model: launcher.filteredApps
        rowHeight: 48
        emptyText: ""

        onSelectedIndexChanged: if (launcher.selectedIndex !== selectedIndex) launcher.selectedIndex = selectedIndex
        Connections {
            target: launcher
            function onSelectedIndexChanged() {
                if (appsList.selectedIndex !== launcher.selectedIndex) appsList.selectedIndex = launcher.selectedIndex
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

                IconImage {
                    source: launcher.resolveIcon(row.modelData?.icon)
                    implicitSize: 28
                    asynchronous: true
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: row.modelData?.name ?? ""
                        color: row.selected ? Theme.background : Theme.foreground
                        font.pixelSize: 13
                        font.bold: row.selected
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: row.modelData?.genericName || row.modelData?.comment || ""
                        color: row.selected
                            ? Theme.hexToRgba(Theme.background, 0.7)
                            : Theme.hexToRgba(Theme.foreground, 0.5)
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        visible: text !== ""
                    }
                }

                TapHandler {
                    onTapped: launcher.launch(row.modelData)
                }
            }
        }
    }
}
