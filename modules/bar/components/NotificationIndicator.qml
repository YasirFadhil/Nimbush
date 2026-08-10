import QtQuick
import QtQuick.Layouts
import "../../../services" as Services

RowLayout {
    spacing: 4

    Item {
        Layout.preferredWidth: bellText.implicitWidth
        Layout.preferredHeight: bellText.implicitHeight

        Text {
            id: bellText
            anchors.fill: parent
            text: Services.Notifications.doNotDisturb ? "󰂛" : "󰂚"
            font.family: "Liga SFMono Nerd Font"
            font.pixelSize: 14
            color: Services.Theme.textPrimary
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                const newState = !Services.Notifications.centerVisible
                if (newState) Services.OverlayManager.closeAllExcept("notifCenter")
                Services.Notifications.centerVisible = newState
            }
        }
    }

    Text {
        visible: Services.Notifications.historyList.count > 0
        text: Services.Notifications.historyList.count
        font.family: "Liga SFMono Nerd Font"
        font.pixelSize: 11
        color: Services.Theme.accent
    }
}
