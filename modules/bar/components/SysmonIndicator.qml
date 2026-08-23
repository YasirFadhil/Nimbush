import QtQuick
import QtQuick.Layouts
import "../../../services" as Services

Rectangle {
    id: sysmonPill

    readonly property string barStyle: Services.Config ? Services.Config.barStyle : "islands"
    readonly property bool isIslands: barStyle === "islands"
    readonly property bool isMinimal: barStyle === "minimal"
    readonly property bool isFloating: barStyle === "floating"
    readonly property bool isUnified: barStyle === "unified"

    implicitHeight: isMinimal ? 24 : 28
    implicitWidth: sysmonRow.implicitWidth + (isMinimal ? 12 : 20)
    radius: isMinimal ? 6 : (isIslands ? 14 : 10)

    color: sysmonMouse.containsMouse ? Services.Theme.bgHover 
         : (isIslands ? Services.Theme.surface 
         : (isFloating ? Qt.rgba(Services.Theme.surface.r, Services.Theme.surface.g, Services.Theme.surface.b, 0.45) 
         : (isUnified ? Qt.rgba(Services.Theme.bgDeep.r, Services.Theme.bgDeep.g, Services.Theme.bgDeep.b, 0.4) : "transparent")))

    border.color: sysmonMouse.containsMouse ? Services.Theme.borderHighlight 
         : (isIslands ? Services.Theme.border 
         : (isFloating ? Qt.rgba(Services.Theme.border.r, Services.Theme.border.g, Services.Theme.border.b, 0.4) 
         : (isUnified ? Qt.rgba(Services.Theme.border.r, Services.Theme.border.g, Services.Theme.border.b, 0.3) : "transparent")))
    border.width: isMinimal ? 0 : 1

    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
    Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

    RowLayout {
        id: sysmonRow
        anchors.centerIn: parent
        spacing: isMinimal ? 4 : 6

        Text {
            text: Services.Icons.cpu
            font.family: Services.Theme.fontSymbols
            font.pixelSize: isMinimal ? Services.Theme.fontSizeMd : Services.Theme.fontSizeXl
            color: sysmonMouse.containsMouse ? Services.Theme.accent : Services.Theme.textPrimary
            Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
        }

        Text {
            text: Math.round(Services.Sysmon.cpuUsage) + "%"
            font.family: Services.Theme.fontMono
            font.pixelSize: isMinimal ? Services.Theme.fontSizeSm : Services.Theme.fontSizeMd
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
