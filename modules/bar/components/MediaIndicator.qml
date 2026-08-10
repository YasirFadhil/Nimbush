import QtQuick
import QtQuick.Layouts
import "../../../services" as Services

RowLayout {
    spacing: 6
    visible: Services.Mpris.activePlayer !== null

    Text {
        text: Services.Mpris.activePlayer && Services.Mpris.activePlayer.isPlaying ? "󰎈" : "󰏤"
        font.family: "Liga SFMono Nerd Font"
        font.pixelSize: 14
        color: Services.Theme.textPrimary
    }

    Text {
        text: Services.Mpris.activePlayer ? (Services.Mpris.activePlayer.trackTitle || "") : ""
        font.family: "Liga SFMono Nerd Font"
        font.pixelSize: 12
        color: Services.Theme.textSecondary
        elide: Text.ElideRight
        Layout.maximumWidth: 120
    }
}
