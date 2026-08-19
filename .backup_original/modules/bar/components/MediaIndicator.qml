import QtQuick
import QtQuick.Layouts
import "../../../services" as Services

RowLayout {
    spacing: 6
    visible: Services.Mpris.activePlayer !== null

    Text {
        text: Services.Mpris.activePlayer && Services.Mpris.activePlayer.isPlaying ? "󰎈" : "󰏤"
        font.family: Services.Theme.fontMono
        font.pixelSize: Services.Theme.fontSize2xl
        color: Services.Theme.textPrimary
    }

    Text {
        text: Services.Mpris.activePlayer ? (Services.Mpris.activePlayer.trackTitle || "") : ""
        font.family: Services.Theme.fontMono
        font.pixelSize: Services.Theme.fontSizeLg
        color: Services.Theme.textSecondary
        elide: Text.ElideRight
        Layout.maximumWidth: 120
    }
}
