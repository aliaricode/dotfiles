pragma Singleton

import Quickshell
import QtQuick

Singleton {
    id: root

    property var active: null

    property var activeBar: null

    property bool expanded: false
    property real targetWidth: 0

    property real growDuration: 0

    // Animation timing shared by the pill and every expand popup. Duration
    // grows with the square root of the distance, so short moves stay as they
    // were and long ones (a half-screen-wide popup on an ultrawide) don't drag:
    //   250 px ~ 220 ms   730 px ~ 300 ms   1500 px ~ 390 ms (capped at maxDuration)
    readonly property real baseDuration: 115
    readonly property real msPerSqrtPx: 7
    readonly property int maxDuration: 420
    // Closing runs a bit quicker than opening
    readonly property real closeScale: 0.85
    // One easing for every phase (the original curve; stronger ones made the
    // short pill stretch read as a flicker)
    readonly property int easing: Easing.OutCubic
    // How far into the stretch the drop starts (OutCubic is ~97% there)
    readonly property real phaseOverlap: 0.7
    // How far into the fold the popup hides and the pill starts shrinking;
    // later than phaseOverlap so the card is fully folded before it vanishes
    readonly property real closeOverlap: 0.9

    property var pendingPopup: null
    property var pendingBar: null

    function durationFor(from, to, scale) {
        const distance = Math.abs(to - from)
        if (distance < 1) return 0
        const ms = Math.min(root.maxDuration, root.baseDuration + root.msPerSqrtPx * Math.sqrt(distance))
        return Math.round(ms * (scale ?? 1))
    }

    function _beginExpand(popup, bar) {
        const from = (bar && bar.pillCurrentWidth > 0)
            ? bar.pillCurrentWidth
            : popup.originWidth

        root.growDuration = root.durationFor(from, popup.implicitWidth)

        root.active = popup
        root.activeBar = bar
        root.targetWidth = popup.implicitWidth
        root.expanded = true

        return root.growDuration
    }

    function expand(popup, bar) {
        if (root.pendingPopup && root.pendingPopup !== popup) {
            root.pendingPopup.abortOpen()
            root.pendingPopup = null
            root.pendingBar = null
        }

        if (root.active && root.active !== popup) {
            root.pendingPopup = popup
            root.pendingBar = bar
            root.active.close(true)
            return -1
        }

        return root._beginExpand(popup, bar)
    }

    function collapse(popup) {
        if (root.active !== popup) return

        if (root.pendingPopup) {
            const p = root.pendingPopup
            const b = root.pendingBar
            root.pendingPopup = null
            root.pendingBar = null
            p.startExpandPhase(root._beginExpand(p, b))
            return
        }

        const bar = root.activeBar
        const from = (bar && bar.pillCurrentWidth > 0) ? bar.pillCurrentWidth : root.targetWidth
        const to = (bar && bar.pillWidth > 0) ? bar.pillWidth : popup.originWidth

        root.growDuration = root.durationFor(from, to, root.closeScale)
        root.expanded = false
    }

    function notifyClosed(popup) {
        if (root.active === popup) {
            root.active = null
            root.activeBar = null
        }
    }
}
