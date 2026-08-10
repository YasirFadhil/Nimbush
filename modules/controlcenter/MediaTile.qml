import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import "../../services" as Services

Rectangle {
    id: card
    readonly property var player: Services.Mpris.activePlayer
    readonly property bool hasPlayer: player !== null
    readonly property bool isPlaying: player?.isPlaying ?? false

    Layout.fillWidth: true
    implicitHeight: 92
    radius: Services.Theme.radiusLg
    color: Services.Theme.surfaceVariant
    clip: true

    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        // Artwork / avatar
        Rectangle {
            width: 60; height: 60
            radius: Services.Theme.radiusMd
            color: Services.Theme.surface
            clip: true
            Layout.alignment: Qt.AlignVCenter

            Text {
                anchors.centerIn: parent
                text: card.hasPlayer
                    ? (card.player?.trackArtist ?? card.player?.trackTitle ?? "\u266a").charAt(0).toUpperCase()
                    : "\u266a"
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
                visible: status === Image.Ready
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 4

            Text {
                text: card.hasPlayer ? (card.player?.trackTitle || "\u2014") : "Nothing Playing"
                color: card.hasPlayer ? Services.Theme.textPrimary : Services.Theme.textDisabled
                font.pixelSize: 13
                font.bold: true
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                text: card.hasPlayer ? (card.player?.trackArtist || "") : "No media session"
                color: Services.Theme.textSecondary
                font.pixelSize: 11
                elide: Text.ElideRight
                Layout.fillWidth: true
                visible: card.hasPlayer ? text.length > 0 : true
            }

            RowLayout {
                spacing: 4
                Layout.topMargin: 4
                visible: card.hasPlayer

                Item {
                    width: 24; height: 24
                    opacity: (card.player?.canGoPrevious ?? false) ? 1 : 0.3
                    Text { anchors.centerIn: parent; text: "\uf04a"; font.family: "Symbols Nerd Font Mono"; font.pixelSize: 11; color: Services.Theme.textSecondary }
                    MouseArea { anchors.fill: parent; enabled: card.player?.canGoPrevious ?? false; onClicked: card.player.previous() }
                }
                Rectangle {
                    width: 26; height: 26; radius: 8
                    color: Services.Theme.accent
                    Text { anchors.centerIn: parent; text: card.isPlaying ? "\uf04c" : "\uf04b"; font.family: "Symbols Nerd Font Mono"; font.pixelSize: 11; color: "#0a0a0a" }
                    MouseArea { anchors.fill: parent; enabled: card.player?.canTogglePlaying ?? true; onClicked: card.player.togglePlaying() }
                }
                Item {
                    width: 24; height: 24
                    opacity: (card.player?.canGoNext ?? false) ? 1 : 0.3
                    Text { anchors.centerIn: parent; text: "\uf04e"; font.family: "Symbols Nerd Font Mono"; font.pixelSize: 11; color: Services.Theme.textSecondary }
                    MouseArea { anchors.fill: parent; enabled: card.player?.canGoNext ?? false; onClicked: card.player.next() }
                }
            }
        }
    }
}
