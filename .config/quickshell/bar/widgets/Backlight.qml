import qs
import qs.services
import qs.widgets
import qs.components
import Quickshell
import QtQuick
import QtQuick.Layouts

Item {
    id: backlightRoot
    implicitWidth: widget.implicitWidth
    implicitHeight: widget.implicitHeight

    // No backlight (desktop monitors) -> nothing to control
    visible: Brightness.available

    property real sliderValue: percent / 100

    readonly property int percent: Math.round(Brightness.fraction * 100)

    readonly property string backlightIcon: {
        if (percent < 33) return "󰃞";
        if (percent < 66) return "󰃟";
        return "󰃠";
    }

    Binding {
        target: backlightRoot
        property: "sliderValue"
        value: backlightRoot.percent / 100
        when: !widget.expanded
    }

    SliderWidget {
        id: widget
        icon: backlightIcon
        value: sliderValue
        onSliderMoved: (v) => {
            sliderValue = v
            Brightness.setPercent(v * 100)
        }
    }
}
