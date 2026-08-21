import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Services.Mpris
import "../../services" as Services

Item {
    id: card
    visible: Services.Mpris.activePlayer !== null
    
    implicitHeight: visible ? (card.isPlaying ? 160 : 62) : 0
    height: implicitHeight
    Behavior on implicitHeight { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

    property var player: Services.Mpris.activePlayer
    readonly property bool isPlaying: card.player?.isPlaying ?? false

    // Shorthand
    readonly property var t: Services.Theme

    // Format seconds → "m:ss"
    function fmtTime(sec) {
        const s = Math.max(0, Math.floor(sec ?? 0))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    Timer {
        interval: 1000
        running: card.isPlaying
        repeat: true
        onTriggered: card.player?.refreshPosition?.()
    }

    // ── Card ─────────────────────────────────────────────────────────
    Rectangle {
        id: cardRect
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
        anchors.leftMargin: 10; anchors.rightMargin: 10
        height: parent.height - 8
        radius: 12
        color: card.t.surface
        border.color: card.t.border
        border.width: 1
        clip: true

        ColumnLayout {
            anchors { fill: parent; margins: 12 }
            // smaller spacing when compact to fit in 62px
            spacing: card.isPlaying ? 8 : 4

            // ── Row 1: Artwork + Info + (compact play button) ─────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                // Artwork
                Rectangle {
                    width:  card.isPlaying ? 48 : 38
                    height: card.isPlaying ? 48 : 38
                    Behavior on width  { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    radius: card.t.radiusSm
                    color: card.t.surfaceVariant
                    antialiasing: true
                    smooth: true
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        anchors.centerIn: parent
                        text: (card.player?.trackArtist ?? card.player?.trackTitle ?? "♪").charAt(0).toUpperCase()
                        color: card.t.textSecondary
                        font.pixelSize: card.isPlaying ? 18 : 14
                        font.bold: true
                        visible: artImg.status !== Image.Ready
                    }
                    Image {
                        id: artImg
                        anchors.fill: parent
                        source: card.player?.trackArtUrl ?? ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        sourceSize: Qt.size(100, 100)
                        smooth: true
                        mipmap: true
                        antialiasing: true
                        visible: false
                    }
                    MultiEffect {
                        anchors.fill: artImg
                        source: artImg
                        maskEnabled: true
                        maskSource: npArtMask
                        visible: artImg.status === Image.Ready
                    }
                    Item {
                        id: npArtMask
                        anchors.fill: artImg
                        visible: false
                        layer.enabled: true
                        layer.smooth: true
                        layer.samples: 8
                        Rectangle {
                            anchors.fill: parent
                            radius: card.t.radiusSm
                            color: "black"
                            antialiasing: true
                            smooth: true
                        }
                    }
                }

                // Info
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2

                    // Player source selector pill
                    // Player identity badge
                    Rectangle {
                        height: 15
                        implicitWidth: badgeRow.implicitWidth + 8
                        radius: 4
                        color: card.t.surfaceVariant
                        visible: card.isPlaying && (card.player?.identity ?? "").length > 0

                        RowLayout {
                            id: badgeRow
                            anchors.centerIn: parent
                            spacing: 3

                            Text {
                                text: Services.Icons.playerIcon(card.player?.identity)
                                color: card.t.accent
                                font.family: card.t.fontSymbols
                                font.pixelSize: 9
                            }

                            Text {
                                text: card.player?.identity ?? ""
                                color: card.t.textDisabled
                                font.pixelSize: 8
                                font.bold: true
                                elide: Text.ElideRight
                                Layout.maximumWidth: 80
                            }
                        }
                    }

                    Text {
                        text: card.player?.trackTitle || "—"
                        color: card.t.textPrimary
                        font.pixelSize: card.isPlaying ? 13 : 12
                        Behavior on font.pixelSize { NumberAnimation { duration: 150 } }
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: card.player?.trackArtist || ""
                        color: card.t.textSecondary
                        font.pixelSize: 10
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        // Hide artist when compact if title is too long (give title breathing room)
                        visible: text.length > 0
                        opacity: card.isPlaying ? 1 : 0.7
                    }
                }

                // Compact play button (only when NOT playing)
                Rectangle {
                    width: 28; height: 28; radius: 7
                    color: compactPlay.containsMouse ? Qt.lighter(card.t.accent, 1.1) : card.t.accent
                    Behavior on color { ColorAnimation { duration: 80 } }
                    opacity: card.isPlaying ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        anchors.centerIn: parent
                        text: Services.Icons.mediaPlay
                        font.family: Services.Theme.fontSymbols; font.pixelSize: Services.Theme.fontSizeMd
                        color: Services.Theme.bgDeep
                    }
                    MouseArea {
                        id: compactPlay; anchors.fill: parent; hoverEnabled: true
                        enabled: !(card.isPlaying) && (card.player?.canTogglePlaying ?? true)
                        onClicked: card.player.togglePlaying()
                    }
                }
            }

            // ── Row 2: Progress bar (full width) — only when playing ──
            Item {
                Layout.fillWidth: true
                height: 20
                opacity: card.isPlaying ? 1 : 0
                visible: card.isPlaying
                Behavior on opacity { NumberAnimation { duration: 200 } }

                // Current time
                Text {
                    id: posLabel
                    anchors { left: parent.left; top: parent.top }
                    text: card.fmtTime(nowPlayingWavyBar.livePosition)
                    color: card.t.textDisabled; font.pixelSize: 9
                }

                // Duration
                Text {
                    id: durLabel
                    anchors { right: parent.right; top: parent.top }
                    text: {
                        const len = card.player?.length ?? 0
                        return len > 0 ? card.fmtTime(len) : "--:--"
                    }
                    color: card.t.textDisabled; font.pixelSize: 9
                }

                WavyProgressBar {
                    id: nowPlayingWavyBar
                    anchors {
                        left: parent.left; right: parent.right
                        top: posLabel.bottom; topMargin: 2
                    }
                    height: 18
                    isPlaying: card.isPlaying
                    waveColor: card.t.accent
                    trackColor: card.t.surfaceVariant
                    lineWidth: 3.0
                    maxAmplitude: 3.0
                    position: card.player?.position ?? 0
                    duration: card.player?.length ?? 0
                    onSeekRequested: (ratio) => {
                        const len = card.player?.length ?? 0
                        if (len > 0 && (card.player?.canSeek ?? (card.player?.positionSupported ?? false)))
                            card.player.position = ratio * len
                    }
                }
            }

            // ── Row 3: Full controls — only when playing ──────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                opacity: card.isPlaying ? 1 : 0
                visible: card.isPlaying
                Behavior on opacity { NumberAnimation { duration: 200 } }

                // Shuffle
                Item {
                    width: 32; height: 32
                    opacity: (card.player?.shuffleSupported ?? false) ? 1 : 0.2
                    Rectangle { anchors.fill: parent; radius: 8; color: shArea.containsMouse ? card.t.surfaceVariant : "transparent"; Behavior on color { ColorAnimation { duration: 80 } } }
                    Text { anchors.centerIn: parent; text: Services.Icons.mediaShuffle; font.family: Services.Theme.fontSymbols; font.pixelSize: Services.Theme.fontSizeLg; color: (card.player?.shuffle ?? false) ? card.t.accent : card.t.textSecondary }
                    MouseArea { id: shArea; anchors.fill: parent; hoverEnabled: true; enabled: card.player?.shuffleSupported ?? false; onClicked: card.player.shuffle = !card.player.shuffle }
                }

                Item { Layout.fillWidth: true }

                // Previous
                Item {
                    width: 32; height: 32
                    opacity: (card.player?.canGoPrevious ?? false) ? 1 : 0.3
                    Rectangle { anchors.fill: parent; radius: 8; color: prvArea.containsMouse ? card.t.surfaceVariant : "transparent"; Behavior on color { ColorAnimation { duration: 80 } } }
                    Text { anchors.centerIn: parent; text: Services.Icons.mediaPrev; font.family: Services.Theme.fontSymbols; font.pixelSize: Services.Theme.fontSizeXl; color: card.t.textSecondary }
                    MouseArea { id: prvArea; anchors.fill: parent; hoverEnabled: true; enabled: card.player?.canGoPrevious ?? false; onClicked: card.player.previous() }
                }

                // Play / Pause (large, filled)
                Rectangle {
                    width: 36; height: 36; radius: 10
                    color: playArea.containsMouse ? Qt.lighter(card.t.accent, 1.12) : card.t.accent
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        anchors.centerIn: parent
                        text: Services.Icons.mediaPlayPause(card.isPlaying)
                        font.family: Services.Theme.fontSymbols; font.pixelSize: Services.Theme.fontSize2xl
                        color: Services.Theme.bgDeep
                    }
                    MouseArea { id: playArea; anchors.fill: parent; hoverEnabled: true; enabled: card.player?.canTogglePlaying ?? true; onClicked: card.player.togglePlaying() }
                }

                // Next
                Item {
                    width: 32; height: 32
                    opacity: (card.player?.canGoNext ?? false) ? 1 : 0.3
                    Rectangle { anchors.fill: parent; radius: 8; color: nxtArea.containsMouse ? card.t.surfaceVariant : "transparent"; Behavior on color { ColorAnimation { duration: 80 } } }
                    Text { anchors.centerIn: parent; text: Services.Icons.mediaNext; font.family: Services.Theme.fontSymbols; font.pixelSize: Services.Theme.fontSizeXl; color: card.t.textSecondary }
                    MouseArea { id: nxtArea; anchors.fill: parent; hoverEnabled: true; enabled: card.player?.canGoNext ?? false; onClicked: card.player.next() }
                }

                Item { Layout.fillWidth: true }

                // Repeat
                Item {
                    width: 32; height: 32
                    opacity: (card.player?.loopSupported ?? false) ? 1 : 0.2
                    Rectangle { anchors.fill: parent; radius: 8; color: rpArea.containsMouse ? card.t.surfaceVariant : "transparent"; Behavior on color { ColorAnimation { duration: 80 } } }
                    Text {
                        anchors.centerIn: parent
                        font.family: Services.Theme.fontSymbols; font.pixelSize: Services.Theme.fontSizeLg
                        text: (card.player?.loop ?? MprisLoopState.None) === MprisLoopState.Track ? Services.Icons.mediaLoopOne : Services.Icons.mediaLoopAll
                        color: (card.player?.loop ?? MprisLoopState.None) !== MprisLoopState.None ? card.t.accent : card.t.textSecondary
                    }
                    MouseArea {
                        id: rpArea; anchors.fill: parent; hoverEnabled: true
                        enabled: card.player?.loopSupported ?? false
                        onClicked: {
                            const l = card.player?.loop ?? MprisLoopState.None
                            if (l === MprisLoopState.None)           card.player.loop = MprisLoopState.Playlist
                            else if (l === MprisLoopState.Playlist)  card.player.loop = MprisLoopState.Track
                            else                                     card.player.loop = MprisLoopState.None
                        }
                    }
                }
            }
        }
    }
}
