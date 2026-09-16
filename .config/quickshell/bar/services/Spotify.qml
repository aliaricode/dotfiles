pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property string backendScript: Quickshell.env("HOME") + "/.config/quickshell/scripts/spotify-backend.py"

    property string deviceId: ""

    // ══ ERRORS ═══════════════════════════════════════════════════

    function errorMessage(code) {
        const c = code ?? ""
        if (c.startsWith("network: ")) return "Network error: " + c.slice(9)
        switch (c) {
        case "no-auth":                return "Not logged in to Spotify. Run spotify-auth.py."
        case "reauth-required":        return "Spotify login expired. Run spotify-auth.py again."
        case "dns-failure":            return "Can't reach Spotify (DNS lookup failed)."
        case "no-device":              return "No Spotify device found. Is quickshell-player running?"
        case "playlist-not-browsable": return "Spotify doesn't allow listing tracks of playlists you only follow. You can still play it."
        case "premium-required":       return "Spotify Premium is required for playback."
        case "rate-limited":           return "Spotify is rate-limiting requests. Try again shortly."
        case "quota-exceeded":         return "Your Spotify app's API quota is used up."
        case "bad-output":             return "The Spotify backend returned invalid output."
        case "":                       return "Unknown error."
        default:                       return c
        }
    }

    function notifyError(title, code) {
        Quickshell.execDetached([
            "notify-send", "-a", "Spotify", "-u", "normal",
            "-h", "string:x-canonical-private-synchronous:quickshell-spotify",
            title, root.errorMessage(code)
        ])
    }

    // ══ RETRIEVAL CALLS ══════════════════════════════════════════
    component BackendCall: Process {
        id: call

        property string script
        property var pendingArgs: null
        readonly property bool hasPending: pendingArgs !== null

        signal result(var data)

        function request(args) {
            if (running) {
                pendingArgs = args
                return
            }
            command = ["python3", script].concat(args)
            running = true
        }

        onRunningChanged: {
            if (running || pendingArgs === null) return
            const args = pendingArgs
            pendingArgs = null
            Qt.callLater(() => call.request(args))
        }

        stdout: StdioCollector {
            onStreamFinished: {
                let data
                try {
                    data = JSON.parse(text)
                } catch (err) {
                    data = { ok: false, error: "bad-output" }
                }
                call.result(data)
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "") console.warn("[Spotify] stderr:", text)
        }
    }

    // ── SEARCH ───────────────────────────────────────────────────
    property ListModel searchResults: ListModel {}
    property bool isSearching: false
    property string searchError: ""

    property int debounceMs: 350
    property string _pendingQuery: ""

    Timer {
        id: debounceTimer
        interval: root.debounceMs
        onTriggered: root._runSearch(root._pendingQuery)
    }

    function search(query) {
        _pendingQuery = query ?? ""
        if (_pendingQuery.trim() === "") {
            debounceTimer.stop()
            searchResults.clear()
            isSearching = false
            searchError = ""
            return
        }
        debounceTimer.restart()
    }

    function _runSearch(query) {
        isSearching = true
        searchError = ""
        searchCall.request(["search", query])
    }

    BackendCall {
        id: searchCall
        script: root.backendScript

        onResult: (data) => {
            if (root._pendingQuery.trim() === "") return
            if (data.ok && data.query !== root._pendingQuery) return
            if (!data.ok && searchCall.hasPending) return
            root.isSearching = false

            if (!data.ok) {
                root.searchError = root.errorMessage(data.error)
                return
            }
            root.searchResults.clear()
            for (const t of (data.results ?? [])) {
                root.searchResults.append({
                    uri: t.uri,
                    title: t.title,
                    artist: t.artist,
                    durationMs: t.durationMs,
                    thumbnail: t.thumbnail ?? ""
                })
            }
        }
    }

    function clearSearch() {
        debounceTimer.stop()
        _pendingQuery = ""
        searchResults.clear()
        isSearching = false
        searchError = ""
    }

    // ── PLAYLISTS ────────────────────────────────────────────────
    property ListModel playlists: ListModel {}
    property bool isLoadingPlaylists: false
    property string playlistsError: ""

    function loadPlaylists() {
        isLoadingPlaylists = true
        playlistsError = ""
        playlistsCall.request(["playlists"])
    }

    BackendCall {
        id: playlistsCall
        script: root.backendScript

        onResult: (data) => {
            if (playlistsCall.hasPending) return
            root.isLoadingPlaylists = false

            if (!data.ok) {
                root.playlistsError = root.errorMessage(data.error)
                return
            }
            root.playlists.clear()
            for (const p of (data.playlists ?? [])) {
                root.playlists.append({
                    id: p.id,
                    uri: p.uri,
                    name: p.name,
                    thumbnail: p.thumbnail ?? "",
                    trackCount: p.trackCount ?? 0,
                    browsable: p.browsable ?? true
                })
            }
        }
    }

    // ── PLAYLIST TRACKS ──────────────────────────────────────────
    property ListModel playlistTracks: ListModel {}
    property bool isLoadingTracks: false
    property string tracksError: ""
    property string currentPlaylistId: ""
    property string currentPlaylistName: ""

    function loadPlaylistTracks(playlistId, name) {
        currentPlaylistId = playlistId ?? ""
        currentPlaylistName = name ?? ""
        playlistTracks.clear()
        isLoadingTracks = true
        tracksError = ""
        tracksCall.request(["playlist", currentPlaylistId])
    }

    BackendCall {
        id: tracksCall
        script: root.backendScript

        onResult: (data) => {
            if (data.ok && data.playlistId !== root.currentPlaylistId) return  // superseded
            if (!data.ok && tracksCall.hasPending) return
            root.isLoadingTracks = false

            if (!data.ok) {
                root.tracksError = root.errorMessage(data.error)
                return
            }
            root.playlistTracks.clear()
            for (const t of (data.tracks ?? [])) root.playlistTracks.append(t)
        }
    }

    // ── QUEUE ────────────────────────────────────────────────────
    property var currentTrack: null
    property ListModel queueList: ListModel {}
    property bool isLoadingQueue: false
    property string queueError: ""

    function loadQueue() {
        isLoadingQueue = true
        queueError = ""
        queueCall.request(["queue_state"])
    }

    BackendCall {
        id: queueCall
        script: root.backendScript

        onResult: (data) => {
            if (queueCall.hasPending) return
            root.isLoadingQueue = false

            if (!data.ok) {
                root.queueError = root.errorMessage(data.error)
                return
            }
            root.currentTrack = data.current ?? null
            root.queueList.clear()
            for (const t of (data.upcoming ?? [])) root.queueList.append(t)
        }
    }

    // ══ PLAYBACK ACTIONS ═════════════════════════════════════════

    property var _actions: []
    property var _currentAction: null

    function _enqueueAction(action) {
        _actions = _actions.concat([action])
        if (!actionProcess.running) _nextAction()
    }

    function _nextAction() {
        if (actionProcess.running || _actions.length === 0) return
        _currentAction = _actions[0]
        _actions = _actions.slice(1)
        actionProcess.command = ["python3", root.backendScript]
            .concat(_currentAction.args, [root.deviceId])
        actionProcess.running = true
    }

    Process {
        id: actionProcess

        onRunningChanged: if (!running) Qt.callLater(root._nextAction)

        stdout: StdioCollector {
            onStreamFinished: {
                const action = root._currentAction
                if (!action) return

                let data
                try {
                    data = JSON.parse(text)
                } catch (err) {
                    data = { ok: false, error: "bad-output" }
                }

                if (!data.ok) {
                    root.notifyError(action.failTitle, data.error)
                    return
                }
                if (data.deviceId) root.deviceId = data.deviceId
                if (action.onSuccess) action.onSuccess(data)
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "") console.warn("[Spotify] action stderr:", text)
        }
    }

    function playNow(item) {
        if (!item || !item.uri) return
        _enqueueAction({
            args: ["play", item.uri],
            failTitle: "Couldn't play " + (item.title || "track")
        })
    }

    function queueTrack(item) {
        if (!item || !item.uri) return
        _enqueueAction({
            args: ["queue", item.uri],
            failTitle: "Couldn't queue " + (item.title || "track"),
            onSuccess: () => root.loadQueue()
        })
    }

    function playPlaylist(playlist) {
        if (!playlist || !playlist.uri) return
        const name = playlist.name || "playlist"
        _enqueueAction({
            args: ["play_mix", playlist.uri, String(playlist.trackCount ?? 0)],
            failTitle: "Couldn't play " + name,
            onSuccess: (data) => {
                if (data.shuffle === false)
                    Quickshell.execDetached([
                        "notify-send", "-a", "Spotify",
                        "-h", "string:x-canonical-private-synchronous:quickshell-spotify",
                        "Playing " + name, "Couldn't turn on shuffle."
                    ])
            }
        })
    }

    // ══ HELPERS ══════════════════════════════════════════════════
    function formatDuration(ms) {
        const seconds = Math.floor((ms ?? 0) / 1000)
        const m = Math.floor(seconds / 60)
        const s = seconds % 60
        return m + ":" + (s < 10 ? "0" + s : s)
    }
}
