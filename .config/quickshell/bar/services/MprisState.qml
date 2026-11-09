pragma Singleton

import Quickshell
import Quickshell.Services.Mpris
import QtQuick

Singleton {
    id: root

    // Last player that was playing, so pausing doesn't make the bar jump to
    // some other idle player (e.g. a paused browser tab)
    property var lastPlaying: null

    readonly property var playingPlayer: {
        const players = Mpris.players.values
        const preferred = players.find(p =>
            (p.identity === "mpv" || p.identity === "Spotifyd") && p.isPlaying
        )
        return preferred ?? players.find(p => p.isPlaying) ?? null
    }

    onPlayingPlayerChanged: if (playingPlayer) lastPlaying = playingPlayer

    readonly property var activePlayer: {
        const players = Mpris.players.values
        if (root.playingPlayer) return root.playingPlayer
        // lastPlaying may have exited; only reuse it while it's still registered
        if (root.lastPlaying && players.includes(root.lastPlaying)) return root.lastPlaying
        return players[0] ?? null
    }

    readonly property bool hasPlayer: activePlayer !== null
    readonly property bool isPlaying: hasPlayer && activePlayer.isPlaying

    readonly property bool canGoPrevious: hasPlayer && activePlayer.canGoPrevious
    readonly property bool canGoNext: hasPlayer && activePlayer.canGoNext
    readonly property bool canTogglePlaying: hasPlayer && activePlayer.canTogglePlaying
    readonly property bool canSeek: hasPlayer && activePlayer.canSeek

    readonly property string trackTitle: hasPlayer ? (activePlayer.trackTitle || "") : ""
    readonly property string trackArtist: hasPlayer ? (activePlayer.trackArtist || "") : ""
    readonly property string trackArtUrl: hasPlayer ? (activePlayer.trackArtUrl || "") : ""
    readonly property bool hasArt: trackArtUrl !== ""
    readonly property real length: hasPlayer ? activePlayer.length : 0

    // ── POSITION ───────────────────────────────────────────────
    property bool positionPolling: false
    property real position: 0

    readonly property real progress: length > 0
        ? Math.max(0, Math.min(1, position / length))
        : 0

    function syncPosition() {
        root.position = root.hasPlayer ? root.activePlayer.position : 0
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.positionPolling && root.isPlaying
        onTriggered: root.syncPosition()
    }

    onPositionPollingChanged: if (root.positionPolling) root.syncPosition()
    onActivePlayerChanged: root.syncPosition()

    // ── ACTIONS ────────────────────────────────────────────────
    function previous() { if (root.canGoPrevious) root.activePlayer.previous() }
    function next() { if (root.canGoNext) root.activePlayer.next() }
    function togglePlaying() { if (root.canTogglePlaying) root.activePlayer.togglePlaying() }

    function seekToRatio(ratio) {
        if (!root.canSeek) return
        const r = Math.max(0, Math.min(1, ratio))
        root.activePlayer.position = r * root.length
        root.syncPosition()
    }

    function formatTime(seconds) {
        if (!seconds || seconds < 0) seconds = 0
        const m = Math.floor(seconds / 60)
        const s = Math.floor(seconds % 60)
        return m + ":" + (s < 10 ? "0" + s : s)
    }
}
