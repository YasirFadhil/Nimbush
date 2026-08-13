import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Services.Mpris
import "../../services" as Services

Rectangle {
    id: card
    readonly property var player: Services.Mpris.activePlayer
    readonly property bool hasPlayer: player !== null
    readonly property bool isPlaying: player?.isPlaying ?? false

    Layout.fillWidth: true
    implicitHeight: 84
    radius: Services.Theme.radiusLg
    color: Services.Theme.surfaceVariant
    border.color: isPlaying ? Services.Theme.borderHighlight : "transparent"
    border.width: isPlaying ? 1 : 0
    clip: true

    Behavior on border.color { ColorAnimation { duration: 150 } }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        // Artwork / avatar container
        Rectangle {
            width: 60; height: 60
            radius: Services.Theme.radiusMd
            color: Services.Theme.surface
            antialiasing: true
            smooth: true
            Layout.alignment: Qt.AlignVCenter

            Text {
                anchors.centerIn: parent
                text: card.hasPlayer
                    ? (card.player?.trackArtist ?? card.player?.trackTitle ?? "\uf001").charAt(0).toUpperCase()
                    : "\uf001"
                font.family: "Symbols Nerd Font Mono"
                color: Services.Theme.textDisabled
                font.pixelSize: 20
                font.bold: true
                visible: !card.hasPlayer || artImg.status !== Image.Ready
            }
            Image {
                id: artImg
                anchors.fill: parent
                source: card.hasPlayer ? (card.player?.trackArtUrl ?? "") : ""
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
                maskSource: artMask
                visible: card.hasPlayer && artImg.status === Image.Ready
            }
            Item {
                id: artMask
                anchors.fill: artImg
                visible: false
                layer.enabled: true
                layer.smooth: true
                layer.samples: 8
                Rectangle {
                    anchors.fill: parent
                    radius: Services.Theme.radiusMd
                    color: "black"
                    antialiasing: true
                    smooth: true
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            Text {
                text: card.hasPlayer ? (card.player?.trackTitle || "Playing Media") : "No Active Media"
                color: card.hasPlayer ? Services.Theme.textPrimary : Services.Theme.textDisabled
                font.pixelSize: 12
                font.bold: true
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                text: card.hasPlayer ? (card.player?.trackArtist || (card.player?.identity || "Unknown")) : "Idle player session"
                color: Services.Theme.textSecondary
                font.pixelSize: 10
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            RowLayout {
                spacing: 6
                Layout.topMargin: 4
                visible: card.hasPlayer

                Rectangle {
                    width: 24; height: 24; radius: 12
                    color: prevHover.containsMouse ? Services.Theme.bgHover : "transparent"
                    opacity: (card.player?.canGoPrevious ?? false) ? 1 : 0.3
                    Behavior on color { ColorAnimation { duration: 100 } }

                    Text { anchors.centerIn: parent; text: "\uf04a"; font.family: "Symbols Nerd Font Mono"; font.pixelSize: 10; color: Services.Theme.textSecondary }
                    MouseArea {
                        id: prevHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: card.player?.canGoPrevious ?? false
                        onClicked: card.player.previous()
                    }
                }
                Rectangle {
                    width: 26; height: 26; radius: 13
                    color: playHover.containsMouse ? "#ffffff" : Services.Theme.accent
                    Behavior on color { ColorAnimation { duration: 100 } }

                    Text { anchors.centerIn: parent; text: card.isPlaying ? "\uf04c" : "\uf04b"; font.family: "Symbols Nerd Font Mono"; font.pixelSize: 10; color: "#0a0a0a" }
                    MouseArea {
                        id: playHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: card.player?.canTogglePlaying ?? true
                        onClicked: card.player.togglePlaying()
                    }
                }
                Rectangle {
                    width: 24; height: 24; radius: 12
                    color: nextHover.containsMouse ? Services.Theme.bgHover : "transparent"
                    opacity: (card.player?.canGoNext ?? false) ? 1 : 0.3
                    Behavior on color { ColorAnimation { duration: 100 } }

                    Text { anchors.centerIn: parent; text: "\uf04e"; font.family: "Symbols Nerd Font Mono"; font.pixelSize: 10; color: Services.Theme.textSecondary }
                    MouseArea {
                        id: nextHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: card.player?.canGoNext ?? false
                        onClicked: card.player.next()
                    }
                }
            }
        }
    }
}
