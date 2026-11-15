import QtQuick
import QtQuick.Layouts
import "../../../services" as Services

Item {
    id: root
    implicitWidth: notifRow.implicitWidth
    implicitHeight: notifRow.implicitHeight
    Layout.alignment: Qt.AlignVCenter

    // Interactive spring scale
    scale: notifMouse.pressed ? 0.88 : (notifMouse.containsMouse ? 1.12 : 1.0)
    Behavior on scale {
        NumberAnimation {
            duration: 160
            easing.type: Easing.OutBack
            easing.overshoot: 1.2
        }
    }

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

            scale: bellScale
            property real bellScale: 1.0

            Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

            onTextChanged: notifMorphAnim.restart()

            SequentialAnimation {
                id: notifMorphAnim
                NumberAnimation { target: bellText; property: "bellScale"; to: 0.5; duration: 80; easing.type: Easing.InQuad }
                NumberAnimation { target: bellText; property: "bellScale"; to: 1.25; duration: 160; easing.type: Easing.OutBack }
                NumberAnimation { target: bellText; property: "bellScale"; to: 1.0; duration: 90; easing.type: Easing.OutQuad }
            }
        }

        Text {
            visible: Services.Notifications.historyList.count > 0
            text: Services.Notifications.historyList.count
            font.family: Services.Theme.fontMono
            font.pixelSize: Services.Theme.fontSizeMd
            font.bold: true
            color: Services.Theme.accent

            scale: visible ? 1.0 : 0.0
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
        }
    }

    MouseArea {
        id: notifMouse
        anchors.fill: parent
        anchors.margins: -4
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const newState = !Services.Notifications.centerVisible
            if (newState) Services.OverlayManager.closeAllExcept("notifCenter")
            Services.Notifications.centerVisible = newState
        }
    }
}
