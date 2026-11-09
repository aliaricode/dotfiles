pragma Singleton

import Quickshell
import Quickshell.Io
import qs.services

Singleton {
    id: root

    readonly property string background: adapter.background
    readonly property string foreground: adapter.foreground
    readonly property string color0:  adapter.color0
    readonly property string color1:  adapter.color1
    readonly property string color2:  adapter.color2
    readonly property string color3:  adapter.color3
    readonly property string color4:  adapter.color4
    readonly property string color5:  adapter.color5
    readonly property string color6:  adapter.color6
    readonly property string color7:  adapter.color7
    readonly property string color8:  adapter.color8
    readonly property string color9:  adapter.color9
    readonly property string color10: adapter.color10
    readonly property string color11: adapter.color11
    readonly property string color12: adapter.color12
    readonly property string color13: adapter.color13
    readonly property string color14: adapter.color14
    readonly property string color15: adapter.color15

    FileView {
        id: colorFile
        path: Qt.resolvedUrl("./theme.json")
        watchChanges: true
        blockLoading: true
        onFileChanged: reload()

        // Used until wallust has written theme.json (fresh install) -- same
        // palette as hypr/lua/colors_default.lua, so nothing is black-on-black
        JsonAdapter {
            id: adapter
            property string background: "#36393D"
            property string foreground: "#BFB0B6"
            property string color0:   "#433B33"
            property string color1:   "#06472C"
            property string color2:   "#6A1E0E"
            property string color3:   "#167B39"
            property string color4:   "#AD6E20"
            property string color5:   "#20EAD4"
            property string color6:   "#2195FE"
            property string color7:   "#9B868E"
            property string color8:   "#6C5E64"
            property string color9:   "#06472C"
            property string color10:  "#6A1E0E"
            property string color11:  "#167B39"
            property string color12:  "#AD6E20"
            property string color13:  "#20EAD4"
            property string color14:  "#2195FE"
            property string color15:  "#9B868E"
        }
    }

    function hexToRgba(hex, alpha) {
        return Qt.rgba(
            parseInt(hex.slice(1, 3), 16) / 255,
            parseInt(hex.slice(3, 5), 16) / 255,
            parseInt(hex.slice(5, 7), 16) / 255,
            alpha
        )
    }

    function surfaceAlpha(base) {
        return PowerState.blurEnabled ? base : Math.min(1.0, base + 0.15)
    }
}
