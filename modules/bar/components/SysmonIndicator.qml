import QtQuick
import QtQuick.Layouts
import "../../../services" as Services

Rectangle {
    id: sysmonPill
    implicitHeight: 28
    implicitWidth: sysmonRow.implicitWidth + 20
    radius: 14
    color: Services.Theme.surface
    border.color: Services.Theme.border
    border.width: 1

    RowLayout {
        id: sysmonRow
        anchors.centerIn: parent
        spacing: 6

        Text {
            text: "󰘚"
            font.family: "Liga SFMono Nerd Font"
            font.pixelSize: 13
            color: Services.Theme.textPrimary
        }

        Text {
            text: Math.round(Services.Sysmon.cpuUsage) + "%"
            font.family: "Liga SFMono Nerd Font"
            font.pixelSize: 11
            color: Services.Theme.textSecondary
        }
    }
}
