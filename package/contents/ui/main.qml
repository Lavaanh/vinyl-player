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
    property real bgBlur: 1.0
    property real bgDim: 0.45
    property real bgOpacity: 1.0
    property int cornerRadius: 24
    property color accent: "#d0bcff"

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
            if (Date.now() > root.lockUntil) root.playing = p[0] === "Playing"
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
        opacity: root.shown ? 1 : 0
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
                color: "#14111c"
            }

            Image {
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
                opacity: root.bgDim
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
