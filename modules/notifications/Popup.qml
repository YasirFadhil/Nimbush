import QtQuick
import QtQuick.Layouts
import "../../services" as Services

Rectangle {
    id: root

    property var notif: null

    signal actionClicked(string identifier, string text)
    signal dismissed()

    implicitWidth: 300
    implicitHeight: contentColumn.implicitHeight + 14

    radius: Services.Theme.radiusMd
    color: Services.Theme.surfaced
    border.color: notif && notif.urgency === 2 ? Services.Theme.danger : Services.Theme.border
    border.width: 1

    ColumnLayout {
        id: contentColumn
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
        spacing: 3

        // Top Row: App Name + Close Button
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                text: root.notif ? (root.notif.appName || "Notification") : ""
                color: Services.Theme.textDisabled
                font.pixelSize: 10
                font.bold: true
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Rectangle {
                width: 16; height: 16; radius: 8
                color: closeMouse.containsMouse ? Services.Theme.danger : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: Services.Icons.close
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: 9
                    color: closeMouse.containsMouse ? Services.Theme.white : Services.Theme.textSecondary
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.notif && root.notif.notifId !== undefined) {
                            Services.Notifications.dismiss(root.notif.notifId)
                        }
                        root.dismissed()
                    }
                }
            }
        }

        // Summary Title
        Text {
            visible: root.notif && root.notif.summary !== undefined && root.notif.summary.length > 0
            text: root.notif ? root.notif.summary : ""
            color: Services.Theme.textPrimary
            font.pixelSize: 11
            font.bold: true
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        // Body Preview
        Text {
            visible: root.notif && root.notif.body !== undefined && root.notif.body.length > 0
            text: root.notif ? root.notif.body : ""
            color: Services.Theme.textSecondary
            font.pixelSize: 10
            maximumLineCount: 2
            elide: Text.ElideRight
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        // Action / Reply Row
        RowLayout {
            id: actionsRow
            readonly property var actList: root.notif ? root.notif.actions : null
            readonly property int actCount: actList ? (actList.count !== undefined ? actList.count : (actList.length !== undefined ? actList.length : 0)) : 0
            visible: actCount > 0
            spacing: 5
            Layout.topMargin: 3

            Repeater {
                model: actionsRow.actList
                delegate: Rectangle {
                    required property string identifier
                    required property string text
                    radius: Services.Theme.radiusSm
                    color: actMouse.containsMouse ? Services.Theme.accent : Services.Theme.surface
                    border.color: Services.Theme.border
                    border.width: 1
                    implicitHeight: 22
                    implicitWidth: actLabel.implicitWidth + 14

                    Text {
                        id: actLabel
                        anchors.centerIn: parent
                        text: parent.text
                        color: actMouse.containsMouse ? Services.Theme.bgOnAccent : Services.Theme.textPrimary
                        font.pixelSize: 10
                        font.bold: true
                    }

                    MouseArea {
                        id: actMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.notif && root.notif.notifId !== undefined) {
                                Services.Notifications.invokeAction(root.notif.notifId, parent.identifier)
                            }
                            root.actionClicked(parent.identifier, parent.text)
                        }
                    }
                }
            }
        }
    }
}
