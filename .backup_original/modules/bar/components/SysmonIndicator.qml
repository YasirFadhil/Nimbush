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
          text: Services.Icons.cpu
            font.family: Services.Theme.fontSymbols
            // font.family: Services.Theme.fontMono
            font.pixelSize: Services.Theme.fontSizeXl
            color: Services.Theme.textPrimary
        }

        Text {
            text: Math.round(Services.Sysmon.cpuUsage) + "%"
            font.family: Services.Theme.fontMono
            font.pixelSize: Services.Theme.fontSizeMd
            color: Services.Theme.textSecondary
        }
    }
}
