import QtQuick
import QtQuick.Layouts
import "../../../services" as Services

RowLayout {
    spacing: 4

    Text {
        text: "󰘚"
        font.family: "Liga SFMono Nerd Font"
        font.pixelSize: 13
        color: Services.Theme.textPrimary
    }

    Text {
        text: Math.round(Services.Sysmon.cpuUsage) + "%"
        font.family: "Liga SFMono Nerd Font"
        font.pixelSize: 12
        color: Services.Theme.textSecondary
    }
}
