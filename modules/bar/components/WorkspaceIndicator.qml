import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../services" as Services

RowLayout {
    spacing: 8

    // OS Logo & Workspaces Pill
    Rectangle {
        id: wsPill
        implicitHeight: 28
        implicitWidth: wsPillLayout.implicitWidth + 20
        radius: 14
        color: Services.Theme.surface
        border.color: Services.Theme.border
        border.width: 1

        RowLayout {
            id: wsPillLayout
            anchors.centerIn: parent
            spacing: 10

            // OS Logo — click to toggle launcher
            Item {
                Layout.preferredWidth: logoText.implicitWidth
                Layout.preferredHeight: logoText.implicitHeight
                Layout.alignment: Qt.AlignVCenter

                Text {
                    id: logoText
                    anchors.centerIn: parent
                    text: Services.OsInfo.logoGlyph
                    font.family: "Liga SFMono Nerd Font"
                    font.pixelSize: 15
                    color: Services.Theme.accent
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Services.OverlayManager.launcherToggleRequested()
                }
            }

            // Divider
            Rectangle {
                width: 1
                height: 12
                color: Services.Theme.border
                opacity: 0.8
                Layout.alignment: Qt.AlignVCenter
            }

            // Workspace Indicators (Render 1..5 + any open workspace)
            RowLayout {
                id: wsRow
                spacing: 6
                Layout.alignment: Qt.AlignVCenter

                property var workspaceList: {
                    const list = [1, 2, 3, 4, 5]
                    const openList = Services.Workspaces.workspaceIds || []
                    for (let i = 0; i < openList.length; i++) {
                        const id = openList[i]
                        if (id > 0 && !list.includes(id)) list.push(id)
                    }
                    return list.sort((a, b) => a - b)
                }

                Repeater {
                    model: wsRow.workspaceList

                    Item {
                        id: wsItem
                        required property int modelData
                        property int wsId: modelData
                        property bool isActive: wsId === Services.Workspaces.activeWorkspaceId
                        property bool isOccupied: (Services.Workspaces.workspaceIds || []).includes(wsId)

                        Layout.preferredWidth: isActive ? 22 : (isOccupied ? 12 : 7)
                        Layout.preferredHeight: 7
                        Layout.alignment: Qt.AlignVCenter

                        Rectangle {
                            anchors.fill: parent
                            radius: 3.5
                            color: wsItem.isActive ? Services.Theme.accent
                                 : wsItem.isOccupied ? Services.Theme.accentDim
                                 : Services.Theme.textDisabled
                            opacity: wsItem.isActive ? 1.0 : (wsItem.isOccupied ? 0.75 : 0.35)

                            Behavior on color { ColorAnimation { duration: 180 } }
                            Behavior on opacity { NumberAnimation { duration: 180 } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.Workspaces.switchTo(wsItem.wsId)
                        }
                    }
                }
            }
        }
    }

    // Active Window Title Pill
    Rectangle {
        id: titlePill
        implicitHeight: 28
        implicitWidth: titleText.implicitWidth + 20
        radius: 14
        color: Services.Theme.surface
        border.color: Services.Theme.border
        border.width: 1
        visible: Services.Workspaces.activeWindowTitle.length > 0
        Layout.maximumWidth: 280

        Text {
            id: titleText
            anchors.centerIn: parent
            width: parent.width - 20
            text: Services.Workspaces.activeWindowTitle
            font.family: "Liga SFMono Nerd Font"
            font.pixelSize: 12
            color: Services.Theme.textSecondary
            elide: Text.ElideRight
        }
    }
}
