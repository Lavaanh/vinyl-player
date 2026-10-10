import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root
    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    // ---- easy settings ----
    property real bgBlur: Plasmoid.configuration.bgBlur
    property real bgDim: Plasmoid.configuration.bgDim
    property real bgOpacity: Plasmoid.configuration.bgOpacity
    property bool useAlbumBg: Plasmoid.configuration.useAlbumBg
    property color bgColor: Plasmoid.configuration.bgColor
    property int cornerRadius: 24
    property color accent: "#d0bcff"

    // ---- optional features ----
    property bool popupOnSongChange: Plasmoid.configuration.popupOnSongChange
    property int popupSeconds: Plasmoid.configuration.popupSeconds
    property bool showTonearm: Plasmoid.configuration.showTonearm

    // ---- state from Spotify ----
    property bool playing: false
    property bool shuffle: false
    property string loopMode: "None"      // None, Track, Playlist
    property real position: 0             // seconds
    property real length: 0               // seconds
    property string title: "Nothing playing"
    property string artist: ""
    property string artUrl: ""

    // ---- show/hide via flag file (toggled by the keybind script) ----
    property bool shown: false
    Timer {
        interval: 40
        running: true
        repeat: true
        onTriggered: {
            var x = new XMLHttpRequest()
            x.open("GET", "file://" + "__FLAG_FILE__")
            x.onreadystatechange = function () {
                if (x.readyState === 4)
                    root.shown = (x.responseText || "").trim() === "1"
            }
            x.send()
        }
    }

    // ---- instant play/pause status from the listener script ----
    Component.onCompleted: runner.run("setsid -f ~/.local/bin/vinyl-follow > /dev/null 2>&1")
    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            var y = new XMLHttpRequest()
            y.open("GET", "file://" + "__FLAG_FILE__".replace("vinyl-visible", "vinyl-status"))
            y.onreadystatechange = function () {
                if (y.readyState === 4 && (y.responseText || "") !== "" && Date.now() > root.lockUntil)
                    root.playing = y.responseText.trim() === "Playing"
            }
            y.send()
        }
    }

    // ---- popup on song change ----
    property bool popupActive: false
    property bool popupArmed: false
    Timer {
        id: popupTimer
        interval: root.popupSeconds * 1000
        onTriggered: root.popupActive = false
    }
    onTitleChanged: {
        if (!root.popupOnSongChange || root.title === "Nothing playing") return
        if (!root.popupArmed) { root.popupArmed = true; return }   // skip the first song found
        root.popupActive = true
        popupTimer.restart()
    }
    onShownChanged: { root.popupActive = false; popupTimer.stop() }

    // ---- volume (scroll wheel) ----
    property real volume: 0.5
    property double volLockUntil: 0
    Timer { id: volToastTimer; interval: 1200 }
    function setVolume(v) {
        v = Math.max(0, Math.min(1, v))
        root.volume = v
        root.volLockUntil = Date.now() + 1500
        volToastTimer.restart()
        runner.run("playerctl -p spotify volume " + v.toFixed(2))
    }
    Plasma5Support.DataSource {
        engine: "executable"
        connectedSources: ["playerctl -p spotify volume"]
        interval: 2000
        onNewData: (source, data) => {
            const v = parseFloat((data["stdout"] || "").trim())
            if (!isNaN(v) && Date.now() > root.volLockUntil) root.volume = v
        }
    }

    function fmt(s) {
        s = Math.max(0, Math.floor(s))
        const m = Math.floor(s / 60)
        const r = s % 60
        return m + ":" + (r < 10 ? "0" : "") + r
    }

    // ---- runs one-off playerctl commands (buttons) ----
    Plasma5Support.DataSource {
        id: runner
        engine: "executable"
        onNewData: (source, data) => disconnectSource(source)
        function run(cmd) { connectSource(cmd + " #" + Date.now()) }
    }

    property double lockUntil: 0
    function ctl(args) { root.lockUntil = Date.now() + 1500; runner.run("playerctl -p spotify " + args) }

    // ---- polls Spotify every second ----
    Plasma5Support.DataSource {
        engine: "executable"
        connectedSources: ["playerctl -p spotify metadata --format '{{status}}~|~{{position}}~|~{{mpris:length}}~|~{{shuffle}}~|~{{loop}}~|~{{mpris:artUrl}}~|~{{artist}}~|~{{title}}'"]
        interval: 1000
        onNewData: (source, data) => {
            const out = (data["stdout"] || "").trim()
            if (!out) {
                root.playing = false
                root.title = "Nothing playing"
                root.artist = ""
                root.artUrl = ""
                root.position = 0
                root.length = 0
                return
            }
            const p = out.split("~|~")
            if (p.length < 8) return
            // play/pause now comes from the fast listener (vinyl-status)
            root.position = Number(p[1]) / 1000000
            root.length = Number(p[2]) / 1000000
            if (Date.now() > root.lockUntil) root.shuffle = p[3].toLowerCase() === "true"
            if (Date.now() > root.lockUntil) root.loopMode = p[4]
            root.artUrl = p[5]
            root.artist = p[6]
            root.title = p.slice(7).join("~|~")
        }
    }

    fullRepresentation: Item {
        id: full
        opacity: (root.shown || root.popupActive) ? 1 : 0
        enabled: root.shown
        Behavior on opacity { NumberAnimation { duration: 100 } }

        Layout.preferredWidth: 400
        Layout.preferredHeight: 560
        Layout.minimumWidth: 240
        Layout.minimumHeight: 400

        // reusable round icon button
        component IconButton: Item {
            property string icon: ""
            property real iconSize: 28
            property bool active: true
            signal clicked()
            width: iconSize + 16
            height: iconSize + 16

            Kirigami.Icon {
                anchors.centerIn: parent
                width: parent.iconSize
                height: width
                source: parent.icon
                isMask: true
                color: parent.active ? "white" : "#80ffffff"
                scale: ma.pressed ? 0.85 : (ma.containsMouse ? 1.12 : 1.0)
                Behavior on scale { NumberAnimation { duration: 90 } }
            }
            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: parent.clicked()
            }
        }

        // ---------- blurred album-art background ----------
        Item {
            anchors.fill: parent
            opacity: root.bgOpacity

            Rectangle {
                anchors.fill: parent
                radius: root.cornerRadius
                color: root.bgColor
            }

            Image {
                visible: root.useAlbumBg
                anchors.fill: parent
                source: root.artUrl
                fillMode: Image.PreserveAspectCrop
                layer.enabled: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: root.bgBlur
                    blurMax: 64
                    maskEnabled: true
                    maskSource: bgMask
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: root.cornerRadius
                color: "black"
                opacity: root.useAlbumBg ? root.bgDim : 0
            }

            Item {
                id: bgMask
                anchors.fill: parent
                visible: false
                layer.enabled: true
                Rectangle {
                    anchors.fill: parent
                    radius: root.cornerRadius
                }
            }
        }

        // invisible area above the controls; the disc centers itself in here
        Item {
            id: stage
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: controls.top
            anchors.margins: 16
        }

        // ---------- spinning record ----------
        Item {
            id: disc
            width: Math.max(0, Math.min(stage.width, stage.height))
            height: width
            anchors.centerIn: stage

            // spin speed eases toward 1 while playing and toward 0 when paused
            property real spinSpeed: root.playing ? 1 : 0
            Behavior on spinSpeed {
                NumberAnimation { duration: 1500; easing.type: Easing.OutCubic }
            }
            // 60 degrees per second at full speed (one turn per 6s)
            FrameAnimation {
                running: root.playing || disc.spinSpeed > 0.001
                onTriggered: disc.rotation = (disc.rotation + frameTime * 60 * disc.spinSpeed) % 360
            }

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "#111111"
            }

            Repeater {
                model: 6
                Rectangle {
                    anchors.centerIn: parent
                    width: disc.width * (0.97 - index * 0.07)
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.color: "#262626"
                    border.width: 1
                }
            }

            Item {
                anchors.centerIn: parent
                width: disc.width * 0.5
                height: width

                Image {
                    anchors.fill: parent
                    source: root.artUrl
                    fillMode: Image.PreserveAspectCrop
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: labelMask
                    }
                }
                Item {
                    id: labelMask
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                    }
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: disc.width * 0.04
                height: width
                radius: width / 2
                color: "#14111c"
            }
        }

        // ---------- tonearm (optional) ----------
        Item {
            id: arm
            visible: root.showTonearm
            x: disc.x + disc.width * 0.98
            y: disc.y + disc.height * 0.02
            rotation: root.playing ? -27 : 12
            Behavior on rotation { NumberAnimation { duration: 700; easing.type: Easing.InOutQuad } }
            Rectangle { x: -disc.width * 0.4; y: -2; width: disc.width * 0.4; height: 4; radius: 2; color: "white" }
            Rectangle { x: -disc.width * 0.4 - 6; y: -7; width: 18; height: 14; radius: 3; color: "white" }
            Rectangle { x: -9; y: -9; width: 18; height: 18; radius: 9; color: "white" }
        }

        // ---------- settings menu (3 dots) ----------
        property bool menuOpen: false

        Connections {
            target: root
            function onShownChanged() { if (!root.shown) full.menuOpen = false }
        }

        Timer { id: volThrottle; interval: 150 }

        component MenuSlider: Item {
            id: ms
            property string label: ""
            property real value: 0
            signal moved(real v)
            signal released()
            width: parent ? parent.width : 200
            height: 44

            Text { text: ms.label; color: "#d0c4ee"; font.pixelSize: 12; anchors.left: parent.left; anchors.top: parent.top }
            Text { text: Math.round(ms.value * 100) + "%"; color: "#c0ffffff"; font.pixelSize: 12; anchors.right: parent.right; anchors.top: parent.top }
            Rectangle {
                y: 28
                width: parent.width
                height: 5
                radius: 3
                color: "#40ffffff"
                Rectangle { width: parent.width * ms.value; height: parent.height; radius: 3; color: root.accent }
            }
            Rectangle {
                y: 25
                x: ms.width * ms.value - width / 2
                width: 11; height: 11; radius: 6
                color: "white"
            }
            MouseArea {
                y: 16
                width: parent.width
                height: 28
                preventStealing: true
                cursorShape: Qt.PointingHandCursor
                onPressed: (mouse) => ms.moved(Math.max(0, Math.min(1, mouse.x / width)))
                onPositionChanged: (mouse) => { if (pressed) ms.moved(Math.max(0, Math.min(1, mouse.x / width))) }
                onReleased: ms.released()
            }
        }

        component MenuToggle: Item {
            id: mt
            property string label: ""
            property bool checked: false
            signal toggled()
            width: parent ? parent.width : 200
            height: 34

            Text { text: mt.label; color: "white"; font.pixelSize: 13; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter }
            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 38; height: 20; radius: 10
                color: mt.checked ? root.accent : "#40ffffff"
                Behavior on color { ColorAnimation { duration: 120 } }
                Rectangle {
                    y: 2
                    x: mt.checked ? 20 : 2
                    width: 16; height: 16; radius: 8
                    color: "white"
                    Behavior on x { NumberAnimation { duration: 120 } }
                }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: mt.toggled() }
        }

        // click outside the panel to close it
        MouseArea {
            anchors.fill: parent
            z: 19
            visible: full.menuOpen
            enabled: full.menuOpen
            onClicked: full.menuOpen = false
        }

        Item {
            id: dotsBtn
            z: 21
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 12
            width: 34
            height: 34

            Rectangle {
                anchors.fill: parent
                radius: 17
                color: "#40ffffff"
                opacity: (dotsMouse.containsMouse || full.menuOpen) ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
            Column {
                anchors.centerIn: parent
                spacing: 3
                Repeater {
                    model: 3
                    Rectangle { width: 4; height: 4; radius: 2; color: "white"; opacity: 0.85 }
                }
            }
            MouseArea {
                id: dotsMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: full.menuOpen = !full.menuOpen
            }
        }

        Rectangle {
            id: menuPanel
            z: 20
            opacity: full.menuOpen ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
            anchors.top: dotsBtn.bottom
            anchors.topMargin: 6
            anchors.left: parent.left
            anchors.leftMargin: 12
            width: Math.min(full.width - 24, 270)
            height: menuCol.implicitHeight + 28
            radius: 16
            color: "#f01c1826"
            border.color: "#30ffffff"
            border.width: 1

            MouseArea { anchors.fill: parent }   // swallow clicks inside the panel

            Column {
                id: menuCol
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 14
                spacing: 4

                Text { text: "Settings"; color: "white"; font.pixelSize: 15; font.bold: true; height: 26 }

                MenuSlider {
                    label: "Volume"
                    value: root.volume
                    onMoved: (v) => {
                        root.volume = v
                        root.volLockUntil = Date.now() + 1500
                        if (!volThrottle.running) {
                            runner.run("playerctl -p spotify volume " + v.toFixed(2))
                            volThrottle.start()
                        }
                    }
                    onReleased: runner.run("playerctl -p spotify volume " + root.volume.toFixed(2))
                }

                MenuToggle {
                    label: "Popup on song change"
                    checked: root.popupOnSongChange
                    onToggled: Plasmoid.configuration.popupOnSongChange = !root.popupOnSongChange
                }
                MenuToggle {
                    label: "Tonearm"
                    checked: root.showTonearm
                    onToggled: Plasmoid.configuration.showTonearm = !root.showTonearm
                }

                MenuToggle {
                    label: "Album art background"
                    checked: root.useAlbumBg
                    onToggled: Plasmoid.configuration.useAlbumBg = !root.useAlbumBg
                }
                Item {
                    id: colorRow
                    visible: !root.useAlbumBg
                    width: parent.width
                    height: visible ? 62 : 0

                    function parseColor(t) {
                        t = t.trim().toLowerCase()
                        var m = t.match(/^#?([0-9a-f]{6})$/)
                        if (m) return "#" + m[1]
                        m = t.match(/^(?:rgb\()?\s*(\d{1,3})\s*[, ]\s*(\d{1,3})\s*[, ]\s*(\d{1,3})\s*\)?$/)
                        if (m) {
                            var c = [m[1], m[2], m[3]].map(function (n) { return parseInt(n) })
                            if (c.some(function (n) { return n > 255 })) return ""
                            return "#" + c.map(function (n) { return (n < 16 ? "0" : "") + n.toString(16) }).join("")
                        }
                        m = t.match(/^#?([0-9a-f])([0-9a-f])([0-9a-f])$/)
                        if (m) return "#" + m[1] + m[1] + m[2] + m[2] + m[3] + m[3]
                        return ""
                    }

                    Text { text: "Color (hex or RGB)"; color: "#d0c4ee"; font.pixelSize: 12; anchors.left: parent.left; anchors.top: parent.top }
                    Text {
                        id: colorStatus
                        text: ""
                        color: "#f2b8b5"
                        font.pixelSize: 11
                        anchors.right: parent.right
                        anchors.top: parent.top
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 32
                        radius: 8
                        color: "#25ffffff"
                        border.width: 1
                        border.color: colorInput.activeFocus ? root.accent : "#30ffffff"

                        Rectangle {
                            id: colorPreview
                            anchors.left: parent.left
                            anchors.leftMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20; height: 20; radius: 10
                            color: root.bgColor
                            border.width: 1
                            border.color: "#60ffffff"
                        }
                        TextInput {
                            id: colorInput
                            anchors.left: colorPreview.right
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            color: "white"
                            font.pixelSize: 13
                            selectByMouse: true
                            clip: true
                            Component.onCompleted: text = String(root.bgColor)
                            onTextEdited: {
                                var c = colorRow.parseColor(text)
                                colorStatus.text = (c === "" && text.length > 0) ? "invalid" : ""
                                if (c !== "") Plasmoid.configuration.bgColor = c
                            }
                            onEditingFinished: {
                                var c = colorRow.parseColor(text)
                                if (c !== "") { Plasmoid.configuration.bgColor = c; text = c }
                                else { text = String(root.bgColor) }
                                colorStatus.text = ""
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            z: -1
                            onClicked: colorInput.forceActiveFocus()
                        }
                    }
                }

                MenuSlider {
                    label: "Background opacity"
                    value: root.bgOpacity
                    onMoved: (v) => Plasmoid.configuration.bgOpacity = v
                }
                MenuSlider {
                    label: "Background blur"
                    visible: root.useAlbumBg
                    value: root.bgBlur
                    onMoved: (v) => Plasmoid.configuration.bgBlur = v
                }
                MenuSlider {
                    label: "Background darkness"
                    visible: root.useAlbumBg
                    value: root.bgDim
                    onMoved: (v) => Plasmoid.configuration.bgDim = v
                }
            }
        }

        // ---------- bottom controls ----------
        Column {
            id: controls
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 6

            Text {
                width: parent.width
                text: root.title
                color: "white"
                font.pixelSize: 20
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: root.artist
                color: "#d0c4ee"
                font.pixelSize: 15
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            // progress bar (click to seek)
            Item {
                width: parent.width
                height: 22

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 5
                    radius: 3
                    color: "#40ffffff"

                    Rectangle {
                        width: root.length > 0 ? parent.width * Math.min(1, root.position / root.length) : 0
                        height: parent.height
                        radius: 3
                        color: root.accent
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: (mouse) => {
                        if (root.length > 0) {
                            const t = (mouse.x / width) * root.length
                            root.position = t
                            root.ctl("position " + t.toFixed(1))
                        }
                    }
                }
            }

            // time labels
            Item {
                width: parent.width
                height: 14
                Text {
                    anchors.left: parent.left
                    text: root.fmt(root.position)
                    color: "#c0ffffff"
                    font.pixelSize: 12
                }
                Text {
                    anchors.right: parent.right
                    text: root.fmt(root.length)
                    color: "#c0ffffff"
                    font.pixelSize: 12
                }
            }

            // buttons
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                IconButton {
                    icon: "media-playlist-shuffle"
                    iconSize: 22
                    active: root.shuffle
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: {
                        root.shuffle = !root.shuffle
                        root.ctl("shuffle Toggle")
                    }
                }
                IconButton {
                    icon: "media-skip-backward"
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: root.ctl("previous")
                }
                IconButton {
                    icon: root.playing ? "media-playback-pause" : "media-playback-start"
                    iconSize: 42
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: {
                        root.playing = !root.playing
                        root.ctl("play-pause")
                    }
                }
                IconButton {
                    icon: "media-skip-forward"
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: root.ctl("next")
                }
                IconButton {
                    icon: root.loopMode === "Track" ? "media-playlist-repeat-song" : "media-playlist-repeat"
                    iconSize: 22
                    active: root.loopMode !== "None"
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: {
                        const next = root.loopMode === "None" ? "Playlist"
                                   : root.loopMode === "Playlist" ? "Track" : "None"
                        root.loopMode = next
                        root.ctl("loop " + next)
                    }
                }
            }

        }
    }
}
