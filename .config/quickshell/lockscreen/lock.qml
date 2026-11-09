import qs
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pam
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

Scope {
    GlobalShortcut {
        appid: "quickshell"
        name: "lock"
        onPressed: sessionLock.locked = true
    }

    IpcHandler {
        target: "lock"
        function lock(): void { sessionLock.locked = true }
        function isLocked(): bool { return sessionLock.locked }
    }

    WlSessionLock {
        id: sessionLock
        locked: Quickshell.env("QS_START_LOCKED") === "1"

        WlSessionLockSurface {
            id: surface
            // Shows through when ~/Pictures/current.png doesn't exist yet
            color: Theme.background

            // ── STATE ─────────────────────────────────────────────
            property bool unlocking: false
            property bool fpAvailable: false
            property string fpStatus: "Touch sensor"
            property int denyLimit: 3
            property bool capsOn: false
            property string kbLayout: ""
            property string netIcon: ""
            property string netLabel: ""
            property bool userPresent: true
            property real dimProgress: 0

            readonly property bool isPrimary: !!surface.screen
                && Quickshell.screens.length > 0
                && (Quickshell.screens.length === 1
                    || surface.screen.name === Quickshell.screens[0].name)

            function wake() {
                if (!surface.userPresent) {
                    surface.userPresent = true
                    if (surface.isPrimary) {
                        capsProc.running = true
                        netProc.running = true
                        layoutProc.running = true
                    }
                }
                surface.dimProgress = 0
                idleTimer.restart()
            }

            function unlock() {
                if (surface.unlocking) return
                surface.unlocking = true
                content.opacity = 0
                content.scale = 1.03
                unlockTimer.start()
            }

            function activatePrimary() {
              if (!surface.isPrimary) return
              passwordInput.forceActiveFocus()
              pamPassword.tryStart()
              pamFinger.tryStart()
            }

            Component.onCompleted: {
                content.opacity = 1
                content.scale = 1.0
                surface.activatePrimary()
            }

            onIsPrimaryChanged: surface.activatePrimary()

            Timer {
                id: unlockTimer
                interval: 320
                onTriggered: sessionLock.locked = false
            }

            Timer {
                id: idleTimer
                interval: 60000
                running: true
                onTriggered: surface.userPresent = false
            }

            SystemClock {
                id: clock
                precision: SystemClock.Minutes
            }

            // ── AUTH: PASSWORD ────────────────────────────────────
            PamContext {
                id: pamPassword
                config: "system-local-login"

                property string pending: ""
                property int failCount: 0
                property bool checking: false
                property bool started: false

                function tryStart() {
                  if (started) return
                  started = true
                  start()
                }

                onResponseRequiredChanged: {
                  if (responseRequired && pending.length > 0) {
                    respond(pending)
                    pending = ""
                  }
                }

                onCompleted: (result) => {
                    checking = false
                    if (surface.unlocking) return
                    if (result === PamResult.Success) {
                        surface.unlock()
                        return
                    }

                    passwordInput.text = ""
                    shakeAnim.restart()
                    flashAnim.restart()

                    if (result === PamResult.Failed) {
                        pamPassword.failCount++
                        start()
                    } else if (result === PamResult.MaxTries) {
                        pamPassword.failCount = surface.denyLimit
                        rearmTimer.restart()
                    } else {
                        rearmTimer.restart()
                    }
                }
            }

            PamContext {
                id: pamFinger
                config: "quickshell-fprint"
                property int fails: 0
                property bool started: false

                function tryStart() {
                    if (started) return
                    started = true
                    start()
                }

                Component.onCompleted: if (surface.isPrimary) tryStart()

                onCompleted: (result) => {
                    if (surface.unlocking) return
                    if (result === PamResult.Error) {
                        surface.fpAvailable = false
                        return
                    }

                    surface.fpAvailable = true

                    if (result === PamResult.Success) {
                        surface.unlock()
                    } else {
                        surface.fpStatus = "Try again"
                        fpFlash.restart()
                        if (result !== PamResult.MaxTries && pamFinger.fails < 5) {
                            pamFinger.fails++
                            fpRestart.start()
                        } else {
                            surface.fpStatus = "Locked out"
                        }
                    }
                }
            }

            Timer {
                id: rearmTimer
                interval: 8000
                onTriggered: {
                    if (!surface.unlocking && !pamPassword.responseRequired) {
                        pamPassword.failCount = 0
                        pamPassword.start()
                    }
                }
            }

            Timer {
                id: fpRestart
                interval: 700
                onTriggered: {
                    if (!surface.unlocking) {
                        surface.fpStatus = "Touch sensor"
                        pamFinger.start()
                    }
                }
            }

            Process {
                id: capsProc
                command: ["bash", "-c", "hyprctl devices -j | grep -q '\"capsLock\": true' && echo 1 || echo 0"]
                stdout: StdioCollector {
                    onStreamFinished: surface.capsOn = (text.trim() === "1")
                }
            }

            Timer {
                interval: 900
                running: surface.isPrimary && surface.userPresent && !surface.unlocking
                repeat: true
                onTriggered: capsProc.running = true
            }

            Process {
                id: layoutProc
                command: ["bash", "-c",
                    "hyprctl devices -j | grep -o '\"active_keymap\": *\"[^\"]*\"' | head -1 | sed 's/.*: *\"//;s/\"$//'"]
                stdout: StdioCollector {
                    onStreamFinished: surface.kbLayout = text.trim()
                }
            }

            Timer {
                interval: 2000
                running: surface.isPrimary && surface.userPresent && !surface.unlocking
                repeat: true
                onTriggered: layoutProc.running = true
            }

            Process {
                id: netProc
                running: true
                command: ["bash", "-c",
                    "t=$(nmcli -t -f TYPE,STATE dev status 2>/dev/null | grep ':connected$' | head -1 | cut -d: -f1); " +
                    "if [ \"$t\" = ethernet ]; then echo eth; " +
                    "elif [ \"$t\" = wifi ]; then s=$(nmcli -t -f ACTIVE,SIGNAL dev wifi 2>/dev/null | grep '^yes' | head -1 | cut -d: -f2); echo \"wifi:$s\"; " +
                    "else echo off; fi"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        var out = text.trim()
                        if (out === "eth") {
                            surface.netIcon = "󰈀"; surface.netLabel = "Ethernet"
                        } else if (out.indexOf("wifi:") === 0) {
                            var sig = parseInt(out.split(":")[1] || "0")
                            surface.netIcon = sig >= 66 ? "󰤨" : (sig >= 33 ? "󰤥" : "󰤟")
                            surface.netLabel = (isNaN(sig) ? "" : sig + "%")
                        } else {
                            surface.netIcon = "󰤭"; surface.netLabel = ""
                        }
                    }
                }
            }
            Timer {
                interval: 5000
                running: surface.isPrimary && surface.userPresent
                repeat: true
                onTriggered: netProc.running = true
            }

            // ── BACKGROUND (static, full-bleed) ───────────────────
            Image {
                id: bgSource
                anchors.fill: parent
                source: "file://" + Quickshell.env("HOME") + "/Pictures/current.png"
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 1280
                cache: false
                visible: false
            }

            MultiEffect {
                anchors.fill: parent
                source: bgSource
                blurEnabled: true
                blurMax: 64
                blur: 0.5 + surface.dimProgress * 0.5
                brightness: -0.35 - surface.dimProgress * 0.25
                saturation: 0.1 - surface.dimProgress * 0.1
                Behavior on blur { NumberAnimation { duration: 800; easing.type: Easing.InOutSine } }
                Behavior on brightness { NumberAnimation { duration: 800; easing.type: Easing.InOutSine } }
                Behavior on saturation { NumberAnimation { duration: 800; easing.type: Easing.InOutSine } }
            }

            NumberAnimation {
                id: dimRamp
                target: surface
                property: "dimProgress"
                to: 1
                duration: 180000
                easing.type: Easing.InOutSine
                running: !surface.userPresent && !surface.unlocking
            }

            // ── FOREGROUND (animated in/out) ──────────────────────
            Item {
                id: content
                anchors.fill: parent
                opacity: 0
                scale: 0.98
                transformOrigin: Item.Center

                Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                Behavior on scale   { NumberAnimation { duration: 480; easing.type: Easing.OutCubic } }

                // ── LEFT COLUMN: IDENTITY & AUTH ──────────────────
                Item {
                    id: leftCol
                    visible: surface.isPrimary
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.horizontalCenterOffset: -400
                    width: 320
                    height: 600

                    Text {
                        id: timeText
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 0
                        text: Qt.formatDateTime(clock.date, "HH:mm")
                        color: Theme.color7
                        font.pixelSize: 85
                        font.family: "Departure Mono"
                        font.bold: true
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: timeText.bottom
                        anchors.topMargin: -10
                        text: Qt.formatDateTime(clock.date, "dd MMMM yyyy")
                        color: Theme.color7
                        font.pixelSize: 24
                        font.family: "Departure Mono"
                    }

                    Rectangle {
                        id: profilePic
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: timeText.bottom
                        anchors.topMargin: 80
                        width: 160
                        height: 160
                        radius: 80
                        color: Theme.hexToRgba(Theme.foreground, 0.1)
                        border.color: Theme.background
                        border.width: 2

                        layer.enabled: true
                        layer.smooth: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: circleMask
                        }

                        SequentialAnimation on scale {
                            running: surface.isPrimary && surface.userPresent && !surface.unlocking
                            loops: Animation.Infinite
                            NumberAnimation { to: 1.015; duration: 2600; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0;   duration: 2600; easing.type: Easing.InOutSine }
                        }

                        Image {
                            id: avatarImage
                            anchors.fill: parent
                            source: "file://" + Quickshell.env("HOME") + "/Pictures/ProfilePhoto.png"
                            fillMode: Image.PreserveAspectCrop
                        }
                        // Fallback when ~/Pictures/ProfilePhoto.png doesn't exist
                        Text {
                            anchors.centerIn: parent
                            visible: avatarImage.status !== Image.Ready
                            text: "󰀄"
                            color: Theme.hexToRgba(Theme.foreground, 0.6)
                            font.pixelSize: 72
                        }
                        Item {
                            id: circleMask
                            anchors.fill: profilePic
                            layer.enabled: true
                            visible: false
                            Rectangle {
                                anchors.fill: parent
                                radius: 80
                                color: "black"
                            }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: profilePic.bottom
                        anchors.topMargin: 20
                        text: "  Imperium"
                        color: Theme.foreground
                        font.pixelSize: 16
                        font.family: "Departure Mono"
                    }

                    Rectangle {
                        anchors.centerIn: authRing
                        width: authRing.width + 10
                        height: authRing.height + 10
                        radius: height / 2
                        color: "transparent"
                        border.width: 2
                        border.color: Theme.color7
                        opacity: passwordInput.activeFocus ? 0.45 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.InOutSine } }
                    }

                    Rectangle {
                        anchors.centerIn: authRing
                        width: authRing.width + 10
                        height: authRing.height + 10
                        radius: height / 2
                        color: "transparent"
                        border.width: 2
                        border.color: Theme.color5
                        visible: pamPassword.checking
                        opacity: 0
                        SequentialAnimation on opacity {
                            running: pamPassword.checking
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.7; duration: 550; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 0.1; duration: 550; easing.type: Easing.InOutSine }
                        }
                    }

                    Rectangle {
                        id: authRing
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: profilePic.bottom
                        anchors.topMargin: 60
                        width: 320
                        height: 55
                        radius: 27.5
                        color: Theme.hexToRgba(Theme.background, 0.5)
                        border.color: Theme.hexToRgba(Theme.foreground, 0.15)
                        border.width: 2

                        SequentialAnimation {
                            id: shakeAnim
                            NumberAnimation { target: authRing; property: "anchors.horizontalCenterOffset"; to: -15; duration: 40; easing.type: Easing.OutSine }
                            NumberAnimation { target: authRing; property: "anchors.horizontalCenterOffset"; to: 15; duration: 40; easing.type: Easing.InOutSine }
                            NumberAnimation { target: authRing; property: "anchors.horizontalCenterOffset"; to: -10; duration: 40; easing.type: Easing.InOutSine }
                            NumberAnimation { target: authRing; property: "anchors.horizontalCenterOffset"; to: 10; duration: 40; easing.type: Easing.InOutSine }
                            NumberAnimation { target: authRing; property: "anchors.horizontalCenterOffset"; to: 0; duration: 40; easing.type: Easing.InSine }
                        }

                        SequentialAnimation {
                            id: flashAnim
                            ColorAnimation { target: authRing; property: "border.color"; to: Theme.color1; duration: 100 }
                            PauseAnimation { duration: 400 }
                            ColorAnimation { target: authRing; property: "border.color"; to: Theme.hexToRgba(Theme.foreground, 0.15); duration: 300 }
                        }

                        TextInput {
                            id: passwordInput
                            anchors.fill: parent
                            anchors.leftMargin: 20
                            anchors.rightMargin: 20
                            verticalAlignment: TextInput.AlignVCenter
                            horizontalAlignment: TextInput.AlignHCenter
                            color: Theme.foreground
                            font.pixelSize: 18
                            font.family: "Departure Mono"
                            echoMode: TextInput.Password
                            passwordCharacter: "•"
                            clip: true
                            focus: true

                            onTextChanged: surface.wake()

                            Text {
                                anchors.centerIn: parent
                                text: "<i>🔒 Password</i>"
                                color: Theme.hexToRgba(Theme.foreground, 0.4)
                                font.pixelSize: 16
                                font.family: "Departure Mono"
                                textFormat: Text.RichText
                                visible: passwordInput.text === ""
                            }

                            Keys.onReturnPressed: {
                                if (passwordInput.text === "")
                                    return
                                pamPassword.checking = true
                                if (pamPassword.responseRequired)
                                    pamPassword.respond(passwordInput.text)
                                else
                                    pamPassword.pending = passwordInput.text
                            }
                        }
                    }

                    Rectangle {
                        id: capsPill
                        anchors.left: authRing.right
                        anchors.leftMargin: 12
                        anchors.verticalCenter: authRing.verticalCenter
                        opacity: surface.capsOn ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                        implicitWidth: capsText.implicitWidth + 22
                        implicitHeight: 30
                        radius: 15
                        color: Theme.hexToRgba(Theme.color1, 0.15)
                        border.color: Theme.color1
                        border.width: 1
                        Text {
                            id: capsText
                            anchors.centerIn: parent
                            text: "⇪ CAPS"
                            color: Theme.color1
                            font.pixelSize: 12
                            font.family: "Departure Mono"
                        }
                    }

                    Rectangle {
                        id: layoutPill
                        anchors.left: capsPill.visible ? capsPill.right : authRing.right
                        anchors.leftMargin: 12
                        anchors.verticalCenter: authRing.verticalCenter
                        opacity: surface.kbLayout !== "" ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                        implicitWidth: layoutText.implicitWidth + 22
                        implicitHeight: 30
                        radius: 15
                        color: Theme.hexToRgba(Theme.foreground, 0.08)
                        border.color: Theme.hexToRgba(Theme.foreground, 0.2)
                        border.width: 1
                        Text {
                            id: layoutText
                            anchors.centerIn: parent
                            text: surface.kbLayout.substring(0, 2).toUpperCase()
                            color: Theme.hexToRgba(Theme.foreground, 0.8)
                            font.pixelSize: 12
                            font.family: "Departure Mono"
                        }
                    }

                    // ── FINGERPRINT STATUS ────────────────────────
                    Row {
                        id: fpRow
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: authRing.bottom
                        anchors.topMargin: 22
                        spacing: 10
                        opacity: surface.fpAvailable ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 300 } }

                        Rectangle {
                            id: fpDot
                            width: 10
                            height: 10
                            radius: 5
                            anchors.verticalCenter: parent.verticalCenter
                            color: surface.fpStatus === "Try again" || surface.fpStatus === "Locked out"
                                   ? Theme.color1 : Theme.color7

                            SequentialAnimation on opacity {
                                running: surface.fpAvailable && surface.userPresent && !surface.unlocking
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.3; duration: 850; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0; duration: 850; easing.type: Easing.InOutSine }
                            }
                        }

                        Text {
                            id: fpText
                            anchors.verticalCenter: parent.verticalCenter
                            text: surface.fpStatus
                            color: Theme.hexToRgba(Theme.foreground, 0.7)
                            font.pixelSize: 14
                            font.family: "Departure Mono"
                        }

                        SequentialAnimation {
                            id: fpFlash
                            NumberAnimation { target: fpRow; property: "scale"; to: 1.08; duration: 90; easing.type: Easing.OutSine }
                            NumberAnimation { target: fpRow; property: "scale"; to: 1.0;  duration: 220; easing.type: Easing.InOutSine }
                        }
                    }

                    // ── ATTEMPTS / LOCKOUT ────────────────────────
                    Column {
                        id: attemptsBox
                        anchors.top: fpRow.bottom
                        anchors.topMargin: 18
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 9
                        opacity: pamPassword.failCount > 0 ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 300 } }

                        readonly property int remaining: Math.max(0, surface.denyLimit - pamPassword.failCount)

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 9
                            Repeater {
                                model: surface.denyLimit
                                Rectangle {
                                    id: pip
                                    width: 9
                                    height: 9
                                    radius: 4.5
                                    property bool spent: index >= attemptsBox.remaining
                                    color: spent ? Theme.color1 : Theme.color7
                                    opacity: spent ? 0.9 : 1
                                    transformOrigin: Item.Center
                                    Behavior on color { ColorAnimation { duration: 250 } }

                                    Connections {
                                        target: pamPassword
                                        function onFailCountChanged() {
                                            if (index === surface.denyLimit - pamPassword.failCount)
                                                pipPop.restart()
                                        }
                                    }
                                    SequentialAnimation {
                                        id: pipPop
                                        NumberAnimation { target: pip; property: "scale"; to: 1.6; duration: 90; easing.type: Easing.OutSine }
                                        NumberAnimation { target: pip; property: "scale"; to: 1.0; duration: 220; easing.type: Easing.OutBack }
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 320
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: attemptsBox.remaining > 0
                                  ? attemptsBox.remaining + (attemptsBox.remaining === 1 ? " attempt left" : " attempts left")
                                  : "Locked out — wait ~10 min, reboot, or reset with faillock"
                            color: attemptsBox.remaining > 0
                                   ? Theme.hexToRgba(Theme.foreground, 0.65) : Theme.color1
                            font.pixelSize: 12
                            font.family: "Departure Mono"
                        }
                    }
                }

                // ── RIGHT COLUMN: MEDIA ───────────────────────────
                Item {
                    id: rightCol
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 150
                    width: 500
                    height: 620

                    opacity: (surface.isPrimary && MprisState.hasPlayer) ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.InOutSine } }

                    Binding {
                        target: MprisState
                        property: "positionPolling"
                        value: surface.isPrimary && surface.userPresent && !surface.unlocking
                    }

                    Rectangle {
                        id: playerCard
                        anchors.fill: parent
                        radius: 30
                        color: Theme.hexToRgba(Theme.background, 0.4)
                        border.color: Theme.hexToRgba(Theme.foreground, 0.1)
                        border.width: 1
                        clip: true

                        Image {
                            id: bgArt
                            anchors.fill: parent
                            source: MprisState.hasArt ? MprisState.trackArtUrl : ""
                            fillMode: Image.PreserveAspectCrop
                            opacity: 0.3
                            visible: MprisState.hasArt

                            layer.enabled: true
                            layer.smooth: true
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: playerCardMask
                            }
                        }

                        Item {
                            id: playerCardMask
                            anchors.fill: playerCard
                            layer.enabled: true
                            visible: false
                            Rectangle {
                                anchors.fill: parent
                                radius: playerCard.radius
                                color: "black"
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 40
                            spacing: 16

                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: 300
                                Layout.preferredHeight: 300
                                radius: 20
                                color: Theme.hexToRgba(Theme.foreground, 0.1)
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    source: MprisState.hasArt ? MprisState.trackArtUrl : ""
                                    fillMode: Image.PreserveAspectCrop
                                    visible: MprisState.hasArt
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: MprisState.hasPlayer ? (MprisState.trackTitle || "Unknown") : ""
                                color: Theme.foreground
                                font.pixelSize: 22
                                font.family: "Departure Mono"
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: MprisState.hasPlayer ? (MprisState.trackArtist || "Unknown Artist") : ""
                                color: Theme.hexToRgba(Theme.foreground, 0.7)
                                font.pixelSize: 18
                                font.family: "Departure Mono"
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }

                            // ── TRANSPORT CONTROLS ────────────────
                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.topMargin: 6
                                spacing: 30

                                Text {
                                    text: "󰒮"
                                    color: MprisState.canGoPrevious
                                           ? Theme.foreground : Theme.hexToRgba(Theme.foreground, 0.3)
                                    font.pixelSize: 24
                                    font.family: "Symbols Nerd Font"
                                    Layout.alignment: Qt.AlignVCenter
                                    scale: prevTap.pressed ? 0.85 : 1
                                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                    TapHandler {
                                        id: prevTap
                                        onTapped: MprisState.previous()
                                    }
                                }

                                Rectangle {
                                    Layout.preferredWidth: 46
                                    Layout.preferredHeight: 46
                                    radius: 23
                                    color: Theme.color5
                                    Layout.alignment: Qt.AlignVCenter
                                    scale: playTap.pressed ? 0.9 : 1
                                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                    Text {
                                        anchors.centerIn: parent
                                        anchors.horizontalCenterOffset: MprisState.isPlaying ? 0 : 1
                                        text: MprisState.isPlaying ? "󰏤" : "󰐊"
                                        color: Theme.background
                                        font.pixelSize: 20
                                        font.family: "Symbols Nerd Font"
                                    }
                                    TapHandler {
                                        id: playTap
                                        onTapped: MprisState.togglePlaying()
                                    }
                                }

                                Text {
                                    text: "󰒭"
                                    color: MprisState.canGoNext
                                           ? Theme.foreground : Theme.hexToRgba(Theme.foreground, 0.3)
                                    font.pixelSize: 24
                                    font.family: "Symbols Nerd Font"
                                    Layout.alignment: Qt.AlignVCenter
                                    scale: nextTap.pressed ? 0.85 : 1
                                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                    TapHandler {
                                        id: nextTap
                                        onTapped: MprisState.next()
                                    }
                                }
                            }

                            // ── PROGRESS BAR + TIME ───────────────
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 8
                                spacing: 6

                                Item {
                                    id: seekArea
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 16

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: 5
                                        radius: 2.5
                                        color: Theme.hexToRgba(Theme.foreground, 0.15)

                                        Rectangle {
                                            id: fill
                                            width: parent.width * MprisState.progress
                                            height: parent.height
                                            radius: 2.5
                                            color: Theme.color5
                                            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                                        }
                                    }

                                    TapHandler {
                                        onTapped: (eventPoint) => {
                                            MprisState.seekToRatio(eventPoint.position.x / seekArea.width)
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: MprisState.formatTime(MprisState.position)
                                        color: Theme.hexToRgba(Theme.foreground, 0.6)
                                        font.pixelSize: 13
                                        font.family: "Departure Mono"
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: MprisState.formatTime(MprisState.length)
                                        color: Theme.hexToRgba(Theme.foreground, 0.6)
                                        font.pixelSize: 13
                                        font.family: "Departure Mono"
                                    }
                                }
                            }
                        }
                    }
                }

                // ── POWER BUTTON (top-left) ───────────────────────
                Rectangle {
                    id: powerButton
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.topMargin: 44
                    anchors.leftMargin: 54
                    width: 40
                    height: 40
                    radius: 20
                    color: powerConfirming
                        ? Theme.hexToRgba(Theme.color1, 0.25)
                        : (powerTap.hovered ? Theme.hexToRgba(Theme.foreground, 0.12) : Theme.hexToRgba(Theme.background, 0.4))
                    border.color: powerConfirming ? Theme.color1 : Theme.hexToRgba(Theme.foreground, 0.15)
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    property bool powerConfirming: false

                    scale: powerTap.pressed ? 0.9 : 1
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰐥"
                        color: powerButton.powerConfirming ? Theme.color1 : Theme.foreground
                        font.pixelSize: 18
                        font.family: "Symbols Nerd Font"
                    }

                    Text {
                        anchors.top: parent.bottom
                        anchors.topMargin: 8
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 140
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: "Tap again to shut down"
                        color: Theme.color1
                        font.pixelSize: 11
                        font.family: "Departure Mono"
                        visible: powerButton.powerConfirming
                        opacity: visible ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }

                    Timer {
                        id: powerConfirmTimer
                        interval: 3000
                        onTriggered: powerButton.powerConfirming = false
                    }

                    Process {
                        id: powerProc
                        command: ["systemctl", "poweroff"]
                    }

                    TapHandler {
                        id: powerTap
                        onTapped: {
                            if (powerButton.powerConfirming) {
                                powerConfirmTimer.stop()
                                powerProc.running = true
                            } else {
                                powerButton.powerConfirming = true
                                powerConfirmTimer.restart()
                            }
                        }
                    }
                }

                // ── STATUS CLUSTER (top-right) ────────────────────
                Row {
                    id: statusCluster
                    visible: surface.isPrimary
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: 44
                    anchors.rightMargin: 54
                    spacing: 22

                    Row {
                        spacing: 8
                        anchors.verticalCenter: parent.verticalCenter
                        visible: surface.netLabel !== ""
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: surface.netIcon
                            color: Theme.hexToRgba(Theme.foreground, 0.85)
                            font.pixelSize: 17
                            font.family: "Symbols Nerd Font"
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: surface.netLabel
                            color: Theme.hexToRgba(Theme.foreground, 0.85)
                            font.pixelSize: 14
                            font.family: "Departure Mono"
                        }
                    }

                    Row {
                        id: batt
                        spacing: 8
                        anchors.verticalCenter: parent.verticalCenter
                        visible: UPower.displayDevice && UPower.displayDevice.isLaptopBattery
                        property var dev: UPower.displayDevice
                        property int pct: dev ? Math.round(dev.percentage * 100) : 0
                        property bool charging: dev && dev.state === UPowerDeviceState.Charging

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            height: 14
                            radius: 3
                            color: "transparent"
                            border.color: Theme.hexToRgba(Theme.foreground, 0.85)
                            border.width: 1.5

                            Rectangle {
                                anchors.left: parent.left
                                anchors.leftMargin: 2
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(0, (parent.width - 4) * batt.pct / 100)
                                height: parent.height - 4
                                radius: 1.5
                                color: batt.pct <= 15 ? Theme.color1
                                       : (batt.charging ? Theme.color5 : Theme.foreground)
                                Behavior on width { NumberAnimation { duration: 400 } }
                            }
                            Rectangle {
                                anchors.left: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 2.5
                                height: 6
                                radius: 1
                                color: Theme.hexToRgba(Theme.foreground, 0.85)
                            }
                            Text {
                                anchors.centerIn: parent
                                text: "⚡"
                                font.pixelSize: 10
                                visible: batt.charging
                                color: Theme.background
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: batt.pct + "%"
                            color: Theme.hexToRgba(Theme.foreground, 0.85)
                            font.pixelSize: 14
                            font.family: "Departure Mono"
                        }
                    }
                }

                // ── BOTTOM: QUOTES ────────────────────────────────
                Text {
                    id: quoteText
                    visible: surface.isPrimary
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 80
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: ""
                    color: Theme.color7
                    font.pixelSize: 18
                    font.family: "Departure Mono"

                    onTextChanged: {
                        quoteText.opacity = 0
                        quoteFade.restart()
                    }
                    NumberAnimation {
                        id: quoteFade
                        target: quoteText
                        property: "opacity"
                        from: 0; to: 1
                        duration: 600
                        easing.type: Easing.OutCubic
                    }
                }

                // ── SECONDARY MONITORS: plain clock only ──────────
                Column {
                    id: secondaryClock
                    visible: !surface.isPrimary
                    anchors.centerIn: parent
                    spacing: -6

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDateTime(clock.date, "HH:mm")
                        color: Theme.color7
                        font.pixelSize: 85
                        font.family: "Departure Mono"
                        font.bold: true
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDateTime(clock.date, "dd MMMM yyyy")
                        color: Theme.color7
                        font.pixelSize: 24
                        font.family: "Departure Mono"
                    }
                }
            }

            Process {
                id: quoteProc
                command: ["/bin/bash", "-c", Quickshell.env("HOME") + "/.config/quickshell/scripts/quote.sh"]
                running: surface.isPrimary
                stdout: StdioCollector {
                    onStreamFinished: quoteText.text = text.trim()
                }
            }

            Timer {
                interval: 14400000
                running: surface.isPrimary
                repeat: true
                onTriggered: quoteProc.running = true
            }

            MouseArea {
                anchors.fill: parent
                z: -1
                hoverEnabled: true
                onClicked: {
                    passwordInput.forceActiveFocus()
                    surface.wake()
                }
                onPositionChanged: surface.wake()
            }
        }
    }
}
