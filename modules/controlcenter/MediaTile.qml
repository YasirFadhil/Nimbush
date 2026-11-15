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
    implicitHeight: hasPlayer ? 126 : 48
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
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8
        visible: card.hasPlayer

        // Row 1: Artwork | Title, artist, source pill, controls
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // 1. Album Artwork (rounded via mask)
            Item {
                Layout.preferredWidth: 76
                Layout.preferredHeight: 76
                Layout.alignment: Qt.AlignTop

                Rectangle {
                    anchors.fill: parent
                    radius: Services.Theme.radiusMd
                    color: Services.Theme.surface
                    border.color: Services.Theme.borderSubtle
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: (card.player?.trackArtist ?? card.player?.trackTitle ?? "♪").charAt(0).toUpperCase()
                        color: Services.Theme.textSecondary
                        font.pixelSize: 26
                        font.bold: true
                        visible: artImg.status !== Image.Ready
                    }
                }

                Image {
                    id: artImg
                    anchors.fill: parent
                    source: card.hasPlayer ? (card.player?.trackArtUrl ?? "") : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize: Qt.size(220, 220)
                    visible: false
                }
                Rectangle {
                    id: artMask
                    anchors.fill: parent
                    radius: Services.Theme.radiusMd
                    visible: false
                    layer.enabled: true
                }
                MultiEffect {
                    anchors.fill: parent
                    source: artImg
                    maskEnabled: true
                    maskSource: artMask
                    visible: artImg.status === Image.Ready
                }
            }

            // 2. Title + Artist row
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 2

                Text {
                    text: card.player?.trackTitle || "—"
                    color: Services.Theme.textPrimary
                    font.pixelSize: 14
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: card.player?.trackArtist || "Unknown Artist"
                        color: Services.Theme.textSecondary
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    // Source Stepper Pill [ ‹ icon name › ]
                    Rectangle {
                        implicitHeight: 18
                        implicitWidth: stepperRow.implicitWidth + 8
                        radius: 9
                        color: Services.Theme.surface
                        border.color: Services.Theme.borderSubtle
                        border.width: 1
                        visible: (card.player?.identity ?? "").length > 0

                        RowLayout {
                            id: stepperRow
                            anchors.centerIn: parent
                            spacing: 3

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

                            Text {
                                text: Services.Icons.playerIcon(card.player?.identity)
                                color: Services.Theme.accent
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 10
                            }

                            Text {
                                text: card.player?.identity || ""
                                color: Services.Theme.textPrimary
                                font.pixelSize: 9
                                font.bold: true
                                elide: Text.ElideRight
                                Layout.maximumWidth: 50
                            }

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

                Item { Layout.fillHeight: true }

                // Controls: Prev, Play/Pause (filled accent), Next
                RowLayout {
                    spacing: 4

                    Rectangle {
                        width: 28; height: 28; radius: 14
                        color: prevHover.containsMouse && (card.player?.canGoPrevious ?? false) ? Services.Theme.bgHover : "transparent"
                        opacity: (card.player?.canGoPrevious ?? false) ? 1 : 0.3
                        Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }

                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.mediaPrev
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 12
                            color: prevHover.containsMouse && (card.player?.canGoPrevious ?? false) ? Services.Theme.accent : Services.Theme.textSecondary
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

                    Rectangle {
                        id: playBtn
                        width: 34; height: 34; radius: 17
                        color: Services.Theme.accent

                        scale: playHover.pressed ? 0.92 : (playHover.containsMouse ? 1.06 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.mediaPlayPause(card.isPlaying)
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 14
                            color: Qt.darker(Services.Theme.accent, 4)
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

                    Rectangle {
                        width: 28; height: 28; radius: 14
                        color: nextHover.containsMouse && (card.player?.canGoNext ?? false) ? Services.Theme.bgHover : "transparent"
                        opacity: (card.player?.canGoNext ?? false) ? 1 : 0.3
                        Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }

                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.mediaNext
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 12
                            color: nextHover.containsMouse && (card.player?.canGoNext ?? false) ? Services.Theme.accent : Services.Theme.textSecondary
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

        // Row 2: time | progress | duration
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: card.fmtTime(tileWavyBar.livePosition)
                color: Services.Theme.textDisabled
                font.pixelSize: 9
                font.family: Services.Theme.fontMono
            }

            MediaModule.WavyProgressBar {
                id: tileWavyBar
                Layout.fillWidth: true
                Layout.preferredHeight: 18
                isPlaying: card.isPlaying
                waveColor: Services.Theme.accent
                trackColor: Qt.alpha(Services.Theme.textPrimary, 0.18)
                barHeight: 6
                position: card.player?.position ?? 0
                duration: card.player?.length ?? 0
                onSeekRequested: (ratio) => {
                    const len = card.player?.length ?? 0
                    if (len > 0 && card.player) {
                        card.player.position = ratio * len
                        card.player.positionChanged()
                    }
                }
            }

            Text {
                text: {
                    const len = card.player?.length ?? 0
                    return len > 0 ? card.fmtTime(len) : "--:--"
                }
                color: Services.Theme.textDisabled
                font.pixelSize: 9
                font.family: Services.Theme.fontMono
            }
        }
    }
}
