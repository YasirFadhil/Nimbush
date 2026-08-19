import QtQuick
import QtQuick.Layouts
import "../../../services" as Services

Rectangle {
    id: sysmonPill
    implicitHeight: 28
    implicitWidth: sysmonRow.implicitWidth + 20
    radius: 14
    color: sysmonMouse.containsMouse ? Services.Theme.surfaceVariant : Services.Theme.surface
    border.color: sysmonMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.border
    border.width: 1

    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on border.color { ColorAnimation { duration: 150 } }

    RowLayout {
        id: sysmonRow
        anchors.centerIn: parent
        spacing: 6

        Text {
            text: Services.Icons.cpu
            font.family: Services.Theme.fontSymbols
            font.pixelSize: Services.Theme.fontSizeXl
            color: sysmonMouse.containsMouse ? Services.Theme.accent : Services.Theme.textPrimary
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        Text {
            text: Math.round(Services.Sysmon.cpuUsage) + "%"
            font.family: Services.Theme.fontMono
            font.pixelSize: Services.Theme.fontSizeMd
            color: Services.Theme.textSecondary
        }
    }

    MouseArea {
        id: sysmonMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Services.OverlayManager.dashboardToggleRequested()
    }
}
