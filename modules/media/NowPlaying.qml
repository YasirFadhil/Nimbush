import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Services.Mpris
import "../../services" as Services

Item {
    id: card
    visible: Services.Mpris.activePlayer !== null
    
    // implicitHeight (bukan height) yang di-baca ColumnLayout untuk sizing
    // Behavior di sini = layout space-nya juga ikut animasi smooth
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
            // spacing lebih kecil saat compact biar pas di 62px
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

                    // Player identity badge — hanya saat playing, benar-benar collapse
                    Rectangle {
                        height: 14
                        implicitWidth: Math.min(badgeTxt.implicitWidth + 10, 80)
                        radius: 4
                        color: card.t.surfaceVariant
                        // visible false = tidak makan layout space sama sekali
                        visible: card.isPlaying && (card.player?.identity ?? "").length > 0

                        Text {
                            id: badgeTxt
                            anchors.centerIn: parent
                            text: card.player?.identity ?? ""
                            color: card.t.textDisabled
                            font.pixelSize: 8
                            font.bold: true
                            elide: Text.ElideRight
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
                        // Sembunyikan artist saat compact jika title terlalu panjang
                        // (biarkan title breathing room)
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
                        text: "\uf04b"
                        font.family: "Symbols Nerd Font Mono"; font.pixelSize: 11
                        color: "#0a0a0a"
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
                    text: card.fmtTime(card.player?.position)
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

                // Track bg
                Rectangle {
                    id: progressBg
                    anchors {
                        left: parent.left; right: parent.right
                        top: posLabel.bottom; topMargin: 4
                    }
                    height: 4; radius: 2
                    color: card.t.surfaceVariant

                    // Fill
                    Rectangle {
                        id: progressFill
                        height: parent.height; radius: 2
                        color: card.t.accent
                        width: {
                            const len = card.player?.length ?? 0
                            const pos = card.player?.position ?? 0
                            return len > 0 ? Math.max(0, Math.min(1, pos / len)) * parent.width : 0
                        }
                        Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.Linear } }
                    }

                    // Thumb
                    Rectangle {
                        width: 10; height: 10; radius: 5
                        color: card.t.accent
                        anchors.verticalCenter: parent.verticalCenter
                        x: Math.max(0, progressFill.width - 5)
                        visible: seekArea.containsMouse || seekArea.pressed
                    }
                }

                MouseArea {
                    id: seekArea
                    anchors.fill: progressBg
                    height: 14; hoverEnabled: true
                    onClicked: (mouse) => {
                        const ratio = mouse.x / width
                        const len = card.player?.length ?? 0
                        if (len > 0 && (card.player?.positionSupported ?? false))
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
                    Text { anchors.centerIn: parent; text: "\uf074"; font.family: "Symbols Nerd Font Mono"; font.pixelSize: 12; color: (card.player?.shuffle ?? false) ? card.t.accent : card.t.textSecondary }
                    MouseArea { id: shArea; anchors.fill: parent; hoverEnabled: true; enabled: card.player?.shuffleSupported ?? false; onClicked: card.player.shuffle = !card.player.shuffle }
                }

                Item { Layout.fillWidth: true }

                // Previous
                Item {
                    width: 32; height: 32
                    opacity: (card.player?.canGoPrevious ?? false) ? 1 : 0.3
                    Rectangle { anchors.fill: parent; radius: 8; color: prvArea.containsMouse ? card.t.surfaceVariant : "transparent"; Behavior on color { ColorAnimation { duration: 80 } } }
                    Text { anchors.centerIn: parent; text: "\uf04a"; font.family: "Symbols Nerd Font Mono"; font.pixelSize: 13; color: card.t.textSecondary }
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
                        text: card.isPlaying ? "\uf04c" : "\uf04b"
                        font.family: "Symbols Nerd Font Mono"; font.pixelSize: 14
                        color: "#0a0a0a"
                    }
                    MouseArea { id: playArea; anchors.fill: parent; hoverEnabled: true; enabled: card.player?.canTogglePlaying ?? true; onClicked: card.player.togglePlaying() }
                }

                // Next
                Item {
                    width: 32; height: 32
                    opacity: (card.player?.canGoNext ?? false) ? 1 : 0.3
                    Rectangle { anchors.fill: parent; radius: 8; color: nxtArea.containsMouse ? card.t.surfaceVariant : "transparent"; Behavior on color { ColorAnimation { duration: 80 } } }
                    Text { anchors.centerIn: parent; text: "\uf04e"; font.family: "Symbols Nerd Font Mono"; font.pixelSize: 13; color: card.t.textSecondary }
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
                        font.family: "Symbols Nerd Font Mono"; font.pixelSize: 12
                        text: (card.player?.loop ?? MprisLoopState.None) === MprisLoopState.Track ? "\uf365" : "\uf364"
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
