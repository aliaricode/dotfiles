pragma Singleton

import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

// Who is using the microphone, camera or screen right now, read from the
// PipeWire graph: an app capturing shows up as a link from a source node to
// that app's stream node.
//   mic     Audio/Source -> stream
//   camera  Video/Source from a v4l2/libcamera device -> stream
//   screen  any other Video/Source (the xdg-desktop-portal screencast node)
// (The shell's own screen recorder uses KMS capture, not PipeWire; it has
// its own indicator.)
Singleton {
    id: root

    readonly property var captureLinks: Pipewire.linkGroups.values
        .filter(g => g.source && g.target && g.target.isStream)

    readonly property var micLinks: captureLinks
        .filter(g => g.source.type === PwNodeType.AudioSource)
    readonly property var videoLinks: captureLinks
        .filter(g => g.source.type === PwNodeType.VideoSource)
    readonly property var cameraLinks: videoLinks.filter(g => root.isCamera(g.source))
    readonly property var screenLinks: videoLinks.filter(g => !root.isCamera(g.source))

    function isCamera(node) {
        return /^(v4l2|libcamera)/.test(node.name || "")
    }

    // Stream nodes only expose their properties (application.name) while bound
    PwObjectTracker {
        objects: root.captureLinks.map(g => g.target).filter(t => !!t)
    }

    function apps(links) {
        const names = []
        for (const g of links) {
            const t = g.target
            if (!t) continue // link torn down mid-update
            const name = (t.properties && t.properties["application.name"]) || t.description || t.name || "Unknown"
            if (/^quickshell$/i.test(name)) continue
            if (!names.includes(name)) names.push(name)
        }
        return names
    }

    readonly property var micApps: apps(micLinks)
    readonly property var cameraApps: apps(cameraLinks)
    readonly property var screenApps: apps(screenLinks)

    readonly property bool micActive: micApps.length > 0
    readonly property bool cameraActive: cameraApps.length > 0
    readonly property bool screenActive: screenApps.length > 0
    readonly property bool anyActive: micActive || cameraActive || screenActive
}
