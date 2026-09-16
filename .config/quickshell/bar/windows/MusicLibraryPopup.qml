import qs
import qs.services
import qs.components
import QtQuick
import QtQuick.Layouts

BaseExpandPopup {
    id: popup

    // ══ WINDOW ═══════════════════════════════════════════════════
    ipcTarget: "musiclibrary"
    placeholder: "Search Spotify..."

    implicitWidth: 480
    implicitHeight: 460

    // ══ VIEW STATE ═══════════════════════════════════════════════
    property string currentView: "search"
    property string playlistMode: "browse"

    readonly property var tabOrder: ["nowPlaying","queue" ,"search", "playlists"]
    readonly property var tabModel: [
        { key: "nowPlaying", label: "Now" },
        { key: "queue",      label: "Queue" },
        { key: "search",     label: "Search" },
        { key: "playlists",  label: "Playlists" }
    ]

    readonly property bool inPlaylistTracks:
        currentView === "playlists" && playlistMode === "tracks"

    showSearch: currentView === "search"

    // ══ KEYBOARD SELECTION ═══════════════════════════════════════
    readonly property var activeModel: {
        if (currentView === "search") return Spotify.searchResults
        if (currentView === "playlists") {
            return playlistMode === "tracks" ? Spotify.playlistTracks : Spotify.playlists
        }
        if (currentView === "queue") return Spotify.queueList
        return null
    }

    readonly property int activeListCount: activeModel ? activeModel.count : 0

    readonly property string currentError: {
        if (currentView === "search") return Spotify.searchError
        if (currentView === "playlists") {
            return playlistMode === "tracks" ? Spotify.tracksError : Spotify.playlistsError
        }
        if (currentView === "queue") return Spotify.queueError
        return ""
    }

    minIndex: 0
    maxIndex: Math.max(activeListCount - 1, 0)

    // ══ ACTIONS ══════════════════════════════════════════════════
    function switchTab(view) {
        currentView = view
        playlistMode = "browse"
        selectedIndex = 0

        if (view === "playlists") Spotify.loadPlaylists()
        if (view === "queue") Spotify.loadQueue()
    }

    function cycleTab(direction) {
        const i = tabOrder.indexOf(currentView)
        switchTab(tabOrder[(i + direction + tabOrder.length) % tabOrder.length])
    }

    function openPlaylist(playlist) {
        if (!playlist) return
        // Followed playlists can't be listed through the API, only played.
        if (playlist.browsable === false) {
            playPlaylistMix(playlist)
            return
        }
        Spotify.loadPlaylistTracks(playlist.id, playlist.name)
        playlistMode = "tracks"
        selectedIndex = 0
    }

    function backToPlaylists() {
        playlistMode = "browse"
        selectedIndex = 0
    }

    function playTrack(track) {
        if (!track) return
        Spotify.playNow(track)
        popup.close()
    }

    function queueTrack(track) {
        if (!track) return
        Spotify.queueTrack(track)
    }

    function playPlaylistMix(playlist) {
        if (!playlist) return
        Spotify.playPlaylist(playlist)
        popup.close()
    }

    // ══ INPUT ════════════════════════════════════════════════════
    onOpened: {
        currentView = "nowPlaying"
        playlistMode = "browse"
        Spotify.clearSearch()
    }

    onSearchEdited: (text) => {
        if (currentView === "search") Spotify.search(text)
    }

    onAccepted: (index) => {
        if (!activeModel || index < 0 || index >= activeModel.count) return

        if (currentView === "playlists" && playlistMode === "browse") {
            openPlaylist(activeModel.get(index))
            return
        }
        if (currentView === "search" || inPlaylistTracks) {
            playTrack(activeModel.get(index))
            return
        }
    }

    onPlayRequested: (index) => {
        if (!activeModel || index < 0 || index >= activeModel.count) return
        const item = activeModel.get(index)

        if (currentView === "playlists" && playlistMode === "browse") {
            playPlaylistMix(item)
            return
        }
        if (currentView === "search" || inPlaylistTracks) {
            queueTrack(item)
            return
        }
    }

    onTabPressed: cycleTab(1)
    onBacktabPressed: cycleTab(-1)

    Binding {
        target: MprisState
        property: "positionPolling"
        value: popup.currentView === "nowPlaying" && popup.visible
    }

    // ══ TAB BAR ══════════════════════════════════════════════════
    headerContent: RowLayout {
        width: parent.width
        spacing: 8

        Repeater {
            model: popup.tabModel

            delegate: Rectangle {
                required property var modelData
                readonly property bool active: popup.currentView === modelData.key

                Layout.preferredWidth: 90
                Layout.preferredHeight: 28
                radius: 8
                color: active
                    ? Theme.hexToRgba(Theme.color5, 0.22)
                    : Theme.hexToRgba(Theme.foreground, 0.05)
                border.color: active
                    ? Theme.hexToRgba(Theme.color5, 0.55)
                    : "transparent"
                border.width: 1

                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: modelData.label
                    color: Theme.foreground
                    font.pixelSize: 12
                    font.bold: active
                }

                TapHandler {
                    onTapped: popup.switchTab(modelData.key)
                }
            }
        }

        Item { Layout.fillWidth: true }

        Rectangle {
            visible: popup.inPlaylistTracks
            Layout.preferredWidth: 70
            Layout.preferredHeight: 28
            radius: 8
            color: Theme.hexToRgba(Theme.foreground, 0.05)

            Text {
                anchors.centerIn: parent
                text: "\uf060 Back"
                font.family: "Symbols Nerd Font"
                font.pixelSize: 11
                color: Theme.foreground
            }

            TapHandler {
                onTapped: popup.backToPlaylists()
            }
        }
    }

    // ══ UI ═══════════════════════════════════════════════════════
    Item {
        id: viewArea
        anchors.fill: parent
        clip: true

        // ── SEARCH ───────────────────────────────────────────
        SelectableListView {
            id: searchList
            anchors.fill: parent

            opacity: popup.currentView === "search" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            model: Spotify.searchResults
            rowHeight: 56
            accentColor: Theme.color5

            emptyText: Spotify.isSearching
                ? "Searching..."
                : (Spotify.searchError !== ""
                    ? Spotify.searchError
                    : (popup.searchText === "" ? "Type to search" : "No results"))

            onSelectedIndexChanged: if (popup.selectedIndex !== selectedIndex) popup.selectedIndex = selectedIndex
            Connections {
                target: popup
                function onSelectedIndexChanged() {
                    if (searchList.selectedIndex !== popup.selectedIndex)
                        searchList.selectedIndex = popup.selectedIndex
                }
            }

            delegate: Component {
                TrackRow {
                    thumbnailSource: modelData ? (modelData.thumbnail ?? "") : ""
                    primaryText: modelData ? (modelData.title ?? "") : ""
                    secondaryText: modelData ? (modelData.artist ?? "") : ""
                    trailingText: modelData ? Spotify.formatDuration(modelData.durationMs ?? 0) : ""
                    onActivated: popup.playTrack(modelData)
                }
            }
        }

        // ── PLAYLISTS ────────────────────────────────────────
        Item {
            id: playlistsArea
            anchors.fill: parent
            clip: true

            opacity: popup.currentView === "playlists" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            SelectableListView {
                id: playlistsList
                anchors { top: parent.top; bottom: parent.bottom }
                width: parent.width

                x: popup.playlistMode === "tracks" ? -width : 0
                Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                model: Spotify.playlists
                rowHeight: 52
                accentColor: Theme.color5

                emptyText: Spotify.isLoadingPlaylists
                    ? "Loading playlists..."
                    : (Spotify.playlistsError !== "" ? Spotify.playlistsError : "No playlists found")

                onSelectedIndexChanged: if (popup.selectedIndex !== selectedIndex) popup.selectedIndex = selectedIndex
                Connections {
                    target: popup
                    function onSelectedIndexChanged() {
                        if (playlistsList.selectedIndex !== popup.selectedIndex)
                            playlistsList.selectedIndex = popup.selectedIndex
                    }
                }

                delegate: Component {
                    TrackRow {
                        thumbnailSize: 36
                        thumbnailSource: modelData ? (modelData.thumbnail ?? "") : ""
                        primaryText: modelData ? (modelData.name ?? "") : ""
                        secondaryText: !modelData ? ""
                            : (modelData.browsable === false
                                ? "Followed playlist"
                                : (modelData.trackCount ?? 0) + " tracks")
                        showPlayButton: true
                        onActivated: popup.openPlaylist(modelData)
                        onPlayRequested: popup.playPlaylistMix(modelData)
                    }
                }
            }

            SelectableListView {
                id: playlistTracksList
                anchors { top: parent.top; bottom: parent.bottom }
                width: parent.width

                x: popup.playlistMode === "tracks" ? 0 : width
                Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                model: Spotify.playlistTracks
                rowHeight: 56
                accentColor: Theme.color5

                emptyText: Spotify.isLoadingTracks
                    ? "Loading tracks..."
                    : (Spotify.tracksError !== "" ? Spotify.tracksError : "No tracks found")

                onSelectedIndexChanged: if (popup.selectedIndex !== selectedIndex) popup.selectedIndex = selectedIndex
                Connections {
                    target: popup
                    function onSelectedIndexChanged() {
                        if (playlistTracksList.selectedIndex !== popup.selectedIndex)
                            playlistTracksList.selectedIndex = popup.selectedIndex
                    }
                }

                delegate: Component {
                    TrackRow {
                        showThumbnail: false
                        primaryText: modelData ? (modelData.title ?? "") : ""
                        secondaryText: modelData ? (modelData.artist ?? "") : ""
                        trailingText: modelData ? Spotify.formatDuration(modelData.durationMs ?? 0) : ""
                        onActivated: popup.playTrack(modelData)
                    }
                }
            }
        }

        // ── QUEUE ────────────────────────────────────────────
        SelectableListView {
            id: queueList
            anchors.fill: parent

            opacity: popup.currentView === "queue" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            model: Spotify.queueList
            rowHeight: 56
            headerHeight: 60
            accentColor: Theme.color5

            emptyText: Spotify.isLoadingQueue
                ? "Loading queue..."
                : (Spotify.queueError !== "" ? Spotify.queueError : "Queue is empty")

            onSelectedIndexChanged: if (popup.selectedIndex !== selectedIndex) popup.selectedIndex = selectedIndex
            Connections {
                target: popup
                function onSelectedIndexChanged() {
                    if (queueList.selectedIndex !== popup.selectedIndex)
                        queueList.selectedIndex = popup.selectedIndex
                }
            }

            header: Component {
                TrackRow {
                    overlineText: "\uf144 Now Playing"
                    thumbnailSource: (Spotify.currentTrack && Spotify.currentTrack.thumbnail)
                        ? Spotify.currentTrack.thumbnail
                        : ""
                    primaryText: Spotify.currentTrack ? Spotify.currentTrack.title : "Nothing playing"
                    secondaryText: Spotify.currentTrack ? Spotify.currentTrack.artist : ""
                }
            }

            delegate: Component {
                TrackRow {
                    showThumbnail: false
                    primaryText: modelData ? (modelData.title ?? "") : ""
                    secondaryText: modelData ? (modelData.artist ?? "") : ""
                    trailingText: modelData ? Spotify.formatDuration(modelData.durationMs ?? 0) : ""
                }
            }
        }

        // ── NOW PLAYING ──────────────────────────────────────
        ColumnLayout {
            id: nowPlayingView
            anchors.fill: parent
            anchors.margins: 8
            spacing: 16

            opacity: popup.currentView === "nowPlaying" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            Item { Layout.fillHeight: true }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 160
                Layout.preferredHeight: 160
                radius: 10
                color: Theme.hexToRgba(Theme.foreground, 0.05)
                clip: true

                Image {
                    anchors.fill: parent
                    source: MprisState.hasArt ? MprisState.trackArtUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: MprisState.hasArt
                }

                Text {
                    anchors.centerIn: parent
                    text: "󰎆"
                    color: Theme.hexToRgba(Theme.foreground, 0.4)
                    font.pixelSize: 44
                    font.family: "Symbols Nerd Font"
                    visible: !MprisState.hasArt
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: MprisState.hasPlayer
                        ? (MprisState.trackTitle || "Unknown Title")
                        : "Nothing playing"
                    color: Theme.foreground
                    font.pixelSize: 15
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    visible: MprisState.hasPlayer
                    text: MprisState.trackArtist || "Unknown Artist"
                    color: Theme.hexToRgba(Theme.foreground, 0.6)
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }

            TransportControls {
                Layout.alignment: Qt.AlignHCenter
                spacing: 24
                buttonSize: 42
            }

            SeekBar {
                Layout.fillWidth: true
            }

            Item { Layout.fillHeight: true }
        }

        // ── ERROR BANNER ─────────────────────────────────────
        Rectangle {
            id: errorBanner
            visible: popup.currentError !== "" && popup.activeListCount > 0
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                margins: 6
            }
            height: bannerText.implicitHeight + 14
            radius: 8
            z: 10
            color: Theme.hexToRgba(Theme.color1, 0.18)
            border.color: Theme.hexToRgba(Theme.color1, 0.5)
            border.width: 1

            Text {
                id: bannerText
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 10
                    rightMargin: 10
                }
                text: "\uf071  " + popup.currentError
                font.family: "Symbols Nerd Font"
                font.pixelSize: 11
                color: Theme.foreground
                wrapMode: Text.WordWrap
            }
        }
    }
}
