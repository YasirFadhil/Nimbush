import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../services" as Services
PanelWindow {
    id: popupWin
    anchors { top: true; right: true }
    margins { top: 12; right: 12 }
    implicitWidth: 340
    implicitHeight: mainColumn.implicitHeight + 24
    visible: Services.Notifications.popupList.count > 0
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.namespace: "quickshell:hud"
    ColumnLayout {
        id: mainColumn
        width: parent.width
        spacing: 8
        Repeater {
            model: Services.Notifications.popupList
            delegate: Rectangle {
                id: notifCard
                property var notif: model
                Layout.fillWidth: true
                implicitHeight: content.implicitHeight + 20
                radius: Services.Theme.radiusMd
                color: Services.Theme.surface
                border.color: notifCard.notif.urgency === 2 ? Services.Theme.danger : Services.Theme.border

                MouseArea {
                    id: dismissArea
                    anchors.fill: parent
                    z: 0
                    onClicked: Services.Notifications.dismiss(notifCard.notif.notifId)
                }

                ColumnLayout {
                    id: content
                    z: 1
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                    spacing: 4
                    Text { text: notifCard.notif.appName; color: Services.Theme.textDisabled; font.pixelSize: 11 }
                    Text { text: notifCard.notif.summary; color: Services.Theme.textPrimary; font.bold: true; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Text { visible: notifCard.notif.body.length > 0; text: notifCard.notif.body; color: Services.Theme.textSecondary; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    RowLayout {
                        id: actionsRow
                        z: 2
                        visible: notifCard.notif.actions && notifCard.notif.actions.count > 0
                        spacing: 6
                        Layout.topMargin: 4
                        Repeater {
                            model: notifCard.notif.actions
                            delegate: Rectangle {
                                id: actBtn
                                required property string identifier
                                required property string text
                                radius: Services.Theme.radiusSm; color: Services.Theme.surfaceVariant
                                implicitHeight: 26
                                implicitWidth: actLabel.implicitWidth + 16
                                Text {
                                    id: actLabel
                                    anchors.centerIn: parent
                                    text: actBtn.text
                                    color: Services.Theme.textPrimary; font.pixelSize: 11
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    z: 3
                                    propagateComposedEvents: false
                                    onClicked: (mouse) => {
                                        console.log("[Popup] action clicked:", actBtn.identifier)
                                        Services.Notifications.invokeAction(notifCard.notif.notifId, actBtn.identifier)
                                        mouse.accepted = true
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
