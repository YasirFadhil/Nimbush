import QtQuick
import QtQuick.Layouts
import "../../../services" as Services

Item {
    implicitWidth: notifRow.implicitWidth
    implicitHeight: notifRow.implicitHeight

    RowLayout {
        id: notifRow
        anchors.fill: parent
        spacing: 4

        Text {
            id: bellText
            text: Services.Notifications.doNotDisturb ? "󰂛" : "󰂚"
            font.family: Services.Theme.fontSymbols
            font.pixelSize: Services.Theme.fontSize2xl
            color: (notifMouse.containsMouse || Services.Notifications.centerVisible) ? Services.Theme.accent : Services.Theme.textPrimary
            Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
        }

        Text {
            visible: Services.Notifications.historyList.count > 0
            text: Services.Notifications.historyList.count
            font.family: Services.Theme.fontMono
            font.pixelSize: Services.Theme.fontSizeMd
            color: Services.Theme.accent
        }
    }

    MouseArea {
        id: notifMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const newState = !Services.Notifications.centerVisible
            if (newState) Services.OverlayManager.closeAllExcept("notifCenter")
            Services.Notifications.centerVisible = newState
        }
    }
}
