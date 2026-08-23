import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Services.Mpris
import "../../services" as Services
import "../media" as MediaModule

Rectangle {
    id: card
    readonly property var player: Services.Mpris.activePlayer
    readonly property bool hasPlayer: player !== null
    readonly property bool isPlaying: player?.isPlaying ?? false

    Layout.fillWidth: true
    implicitHeight: hasPlayer ? 86 : 48
    radius: Services.Theme.radiusLg
    color: Services.Theme.surfaceVariant
    border.color: isPlaying ? Services.Theme.borderHighlight : Services.Theme.borderSubtle
    border.width: 1
    clip: true

    Behavior on implicitHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

    function fmtTime(sec) {
        const s = Math.max(0, Math.floor(sec ?? 0))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    // ── Idle State (No Media Playing) ──
    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8
        visible: !card.hasPlayer

        Text {
            text: Services.Icons.music
            font.family: Services.Theme.fontSymbols
            font.pixelSize: 14
            color: Services.Theme.textDisabled
        }

        Text {
            text: "No Active Media"
            font.pixelSize: 11
            color: Services.Theme.textDisabled
            Layout.fillWidth: true
        }
    }

    // ── Active Media Player ──
    RowLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10
        visible: card.hasPlayer

        // 1. Album Artwork
        Rectangle {
            width: 60; height: 60
            radius: Services.Theme.radiusMd
            color: Services.Theme.surface
            clip: true
            Layout.alignment: Qt.AlignVCenter

            Text {
                anchors.centerIn: parent
                text: (card.player?.trackArtist ?? card.player?.trackTitle ?? "♪").charAt(0).toUpperCase()
                color: Services.Theme.textSecondary
                font.pixelSize: 22
                font.bold: true
                visible: !card.hasPlayer || artImg.status !== Image.Ready
            }
            Image {
                id: artImg
                anchors.fill: parent
                source: card.hasPlayer ? (card.player?.trackArtUrl ?? "") : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                sourceSize: Qt.size(120, 120)
                visible: status === Image.Ready
            }
        }

        // 2. Info & Controls Column
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            // Top Row: Title + Source Stepper Pill
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: card.player?.trackTitle || "—"
                    color: Services.Theme.textPrimary
                    font.pixelSize: 12
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                // Source Stepper Pill [ ‹ 󰓇 Spotify › ]
                Rectangle {
                    implicitHeight: 20
                    implicitWidth: stepperRow.implicitWidth + 8
                    radius: 10
                    color: Services.Theme.surface
                    border.color: Services.Theme.borderSubtle
                    border.width: 1
                    visible: (card.player?.identity ?? "").length > 0

                    RowLayout {
                        id: stepperRow
                        anchors.centerIn: parent
                        spacing: 3

                        // Previous Player Arrow
                        Rectangle {
                            visible: Services.Mpris.playerCount > 1
                            width: 14; height: 14; radius: 7
                            color: prevArrMouse.containsMouse ? Services.Theme.bgHover : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: "‹"
                                font.bold: true
                                font.pixelSize: 11
                                color: prevArrMouse.containsMouse ? Services.Theme.accent : Services.Theme.textSecondary
                            }
                            MouseArea {
                                id: prevArrMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: (mouse) => {
                                    Services.Mpris.prevPlayer()
                                    mouse.accepted = true
                                }
                            }
                        }

                        // App Icon
                        Text {
                            text: Services.Icons.playerIcon(card.player?.identity)
                            color: Services.Theme.accent
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 10
                        }

                        // App Name
                        Text {
                            text: card.player?.identity || ""
                            color: Services.Theme.textPrimary
                            font.pixelSize: 9
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.maximumWidth: 60
                        }

                        // Next Player Arrow
                        Rectangle {
                            visible: Services.Mpris.playerCount > 1
                            width: 14; height: 14; radius: 7
                            color: nextArrMouse.containsMouse ? Services.Theme.bgHover : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: "›"
                                font.bold: true
                                font.pixelSize: 11
                                color: nextArrMouse.containsMouse ? Services.Theme.accent : Services.Theme.textSecondary
                            }
                            MouseArea {
                                id: nextArrMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: (mouse) => {
                                    Services.Mpris.nextPlayer()
                                    mouse.accepted = true
                                }
                            }
                        }
                    }
                }
            }

            // Middle Row: Artist & Duration Timestamps
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: card.player?.trackArtist || "Unknown Artist"
                    color: Services.Theme.textSecondary
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Text {
                    text: {
                        const pos = card.fmtTime(tileWavyBar.livePosition)
                        const len = card.player?.length ?? 0
                        const dur = len > 0 ? card.fmtTime(len) : "--:--"
                        return pos + " / " + dur
                    }
                    color: Services.Theme.textDisabled
                    font.pixelSize: 9
                    font.family: Services.Theme.fontMono
                }
            }

            // Bottom Row: Wavy Progress Bar + Playback Controls
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                // Wavy Progress Bar
                MediaModule.WavyProgressBar {
                    id: tileWavyBar
                    Layout.fillWidth: true
                    height: 14
                    isPlaying: card.isPlaying
                    waveColor: Services.Theme.accent
                    trackColor: Services.Theme.surface
                    lineWidth: 2.2
                    maxAmplitude: 2.2
                    position: card.player?.position ?? 0
                    duration: card.player?.length ?? 0
                    onSeekRequested: (ratio) => {
                        const len = card.player?.length ?? 0
                        if (len > 0 && (card.player?.canSeek ?? (card.player?.positionSupported ?? false)))
                            card.player.position = ratio * len
                    }
                }

                // Controls: Prev, Play/Pause, Next
                RowLayout {
                    spacing: 4

                    // Prev
                    Rectangle {
                        width: 22; height: 22; radius: 11
                        color: prevHover.containsMouse ? Services.Theme.bgHover : "transparent"
                        opacity: (card.player?.canGoPrevious ?? false) ? 1 : 0.3
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.mediaPrev
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 10
                            color: prevHover.containsMouse ? Services.Theme.accent : Services.Theme.textSecondary
                        }
                        MouseArea {
                            id: prevHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: card.player?.canGoPrevious ?? false
                            onClicked: (mouse) => { card.player.previous(); mouse.accepted = true }
                        }
                    }

                    // Play/Pause (Accent Filled)
                    Rectangle {
                        width: 26; height: 26; radius: 13
                        color: playHover.containsMouse ? Qt.lighter(Services.Theme.accent, 1.15) : Services.Theme.accent
                        scale: playHover.containsMouse ? 1.06 : 1.0
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.mediaPlayPause(card.isPlaying)
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 11
                            color: Services.Theme.bgDeep
                        }
                        MouseArea {
                            id: playHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: card.player?.canTogglePlaying ?? true
                            onClicked: (mouse) => { card.player?.togglePlaying(); mouse.accepted = true }
                        }
                    }

                    // Next
                    Rectangle {
                        width: 22; height: 22; radius: 11
                        color: nextHover.containsMouse ? Services.Theme.bgHover : "transparent"
                        opacity: (card.player?.canGoNext ?? false) ? 1 : 0.3
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.mediaNext
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 10
                            color: nextHover.containsMouse ? Services.Theme.accent : Services.Theme.textSecondary
                        }
                        MouseArea {
                            id: nextHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: card.player?.canGoNext ?? false
                            onClicked: (mouse) => { card.player.next(); mouse.accepted = true }
                        }
                    }
                }
            }
        }
    }
}

