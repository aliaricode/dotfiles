pragma Singleton

import qs
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick

Singleton {
    id: root

    // Do Not Disturb survives shell restarts
    readonly property alias dnd: dndSettings.dnd
    FileView {
        path: Quickshell.dataPath("notifications.json")
        printErrors: false // first run: created on the first DND toggle
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        JsonAdapter {
            id: dndSettings
            property bool dnd: false
        }
    }

    // ── TOAST STATE ────────────────────────────────────────────
    property var toastNotification: null
    property bool toastVisible: false
    property bool toastPaused: false

    property var toastQueue: []
    readonly property int maxQueue: 5
    readonly property int queuedCount: toastQueue.length

    readonly property var server: NotificationServer {
        actionsSupported: true
        bodySupported: true
        imageSupported: true
        keepOnReload: true

        onNotification: (notif) => {
            notif.tracked = !notif.transient
            if (notif.tracked) root.noteArrival(notif)

            if (root.dnd && !root.isCritical(notif)) return

            root.enqueueToast(notif)
        }
    }

    function isCritical(n) {
        return !!n && n.urgency === NotificationUrgency.Critical
    }

    function enqueueToast(notif) {
        const showingCritical = root.toastVisible && root.isCritical(root.toastNotification)

        if (root.isCritical(notif)) {
            if (showingCritical) {
                if (root.toastQueue.length < root.maxQueue)
                    root.toastQueue = root.toastQueue.concat([notif])
            } else {
                root.showToast(notif)
            }
            return
        }

        if (showingCritical) return
        root.showToast(notif)
    }

    function showToast(notif) {
        toastGap.stop()
        root.toastNotification = notif
        root.toastVisible = true
        root.toastPaused = false
        toastTimer.restart()
    }

    function nextToast() {
        if (root.toastQueue.length > 0) {
            const next = root.toastQueue[0]
            root.toastQueue = root.toastQueue.slice(1)
            root.showToast(next)
        } else {
            root.toastNotification = null
        }
    }

    function dismissToast() {
        toastTimer.stop()
        root.toastVisible = false
        toastGap.restart()
    }

    Timer {
        id: toastTimer
        interval: {
            if (!root.toastNotification) return 5000

            if (root.isCritical(root.toastNotification)) return 60000

            const t = root.toastNotification.expireTimeout
            if (t < 0) return 5000
            if (t === 0) return 60000
            return Math.max(t * 1000, 3000)
        }
        onTriggered: {
            root.toastVisible = false
            toastGap.restart()
        }
    }

    Timer {
        id: toastGap
        interval: 220
        onTriggered: root.nextToast()
    }

    onToastPausedChanged: {
        if (!root.toastVisible) return
        if (root.toastPaused) toastTimer.stop()
        else toastTimer.restart()
    }

    // ── ARRIVAL TIMES ──────────────────────────────────────────
    property var arrivalTimes: ({})
    property int nowTick: 0

    function noteArrival(notif) {
        const m = Object.assign({}, root.arrivalTimes)
        m[notif.id] = Date.now()
        root.arrivalTimes = m
    }

    function relativeTime(notif) {
        const _dep = root.nowTick
        if (!notif) return ""
        const t = root.arrivalTimes[notif.id]
        if (!t) return ""

        const s = Math.floor((Date.now() - t) / 1000)
        if (s < 60) return "now"
        if (s < 3600) return Math.floor(s / 60) + "m"
        if (s < 86400) return Math.floor(s / 3600) + "h"
        return Math.floor(s / 86400) + "d"
    }

    function pruneArrivals() {
        const live = {}
        for (const n of root.server.trackedNotifications.values) {
            const t = root.arrivalTimes[n.id]
            if (t) live[n.id] = t
        }
        root.arrivalTimes = live
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            root.nowTick++
            root.pruneArrivals()
        }
    }

    // ── CENTER ─────────────────────────────────────────────────
    readonly property var notifications: server.trackedNotifications
    readonly property int count: server.trackedNotifications.values.length

    readonly property int criticalCount: {
        let c = 0
        for (const n of server.trackedNotifications.values)
            if (root.isCritical(n)) c++
        return c
    }

    function dismissAll() {
        const notifs = server.trackedNotifications.values.slice()
        for (const n of notifs) n.dismiss()
        root.toastQueue = []
    }

    function toggleDnd() {
        dndSettings.dnd = !dndSettings.dnd
        if (root.dnd) {
            root.toastQueue = []
            root.dismissToast()
        }
    }
}
