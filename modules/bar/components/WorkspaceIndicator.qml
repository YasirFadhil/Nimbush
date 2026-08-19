import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../services" as Services

// Workspace Indicators (Render 1..5 + any open workspace)
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
                    font.family: Services.Theme.fontMono
                    font.pixelSize: Services.Theme.fontSize3xl
                    color: logoMouse.containsMouse ? Qt.lighter(Services.Theme.accent, 1.2) : Services.Theme.accent
                    scale: logoMouse.containsMouse ? 1.1 : 1.0

                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                }

                MouseArea {
                    id: logoMouse
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.LeftButton) {
                            Services.OverlayManager.dashboardToggleRequested()
                        } else if (mouse.button === Qt.RightButton) {
                            Services.OverlayManager.launcherToggleRequested()
                        }
                    }
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

                        Behavior on Layout.preferredWidth {
                            NumberAnimation { duration: 180 }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 3.5
                            color: wsItem.isActive ? Services.Theme.accent
                                 : (wsMouse.containsMouse ? Services.Theme.textPrimary
                                 : (wsItem.isOccupied ? Services.Theme.accentDim : Services.Theme.textDisabled))
                            opacity: wsItem.isActive ? 1.0 : (wsMouse.containsMouse ? 1.0 : (wsItem.isOccupied ? 0.75 : 0.35))

                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }

                        MouseArea {
                            id: wsMouse
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
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
            font.family: Services.Theme.fontMono
            font.pixelSize: Services.Theme.fontSizeLg
            color: Services.Theme.textSecondary
            elide: Text.ElideRight
        }
    }
}
