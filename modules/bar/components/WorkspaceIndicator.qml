import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../services" as Services

RowLayout {
    id: wsRoot
    spacing: isMinimal ? 4 : 8

    readonly property string barStyle: Services.Config ? Services.Config.barStyle : "islands"
    readonly property string workspaceStyle: Services.Config ? Services.Config.workspaceStyle : "pills"
    readonly property bool showAll: Services.Config ? Services.Config.workspaceShowAll : true
    readonly property bool isIslands: barStyle === "islands"
    readonly property bool isMinimal: barStyle === "minimal"
    readonly property bool isFloating: barStyle === "floating"
    readonly property bool isUnified: barStyle === "unified"

    readonly property int pillHeight: isMinimal ? 24 : 28
    readonly property int pillRadius: isMinimal ? 6 : (isIslands ? 14 : 10)

    function getPillBg(hovered) {
        if (hovered) return Services.Theme.bgHover
        if (isIslands) return Services.Theme.surface
        if (isFloating) return Qt.rgba(Services.Theme.surface.r, Services.Theme.surface.g, Services.Theme.surface.b, 0.45)
        if (isUnified) return Qt.rgba(Services.Theme.bgDeep.r, Services.Theme.bgDeep.g, Services.Theme.bgDeep.b, 0.4)
        return "transparent"
    }

    function getPillBorder(hovered) {
        if (hovered) return Services.Theme.borderHighlight
        if (isIslands) return Services.Theme.border
        if (isFloating) return Qt.rgba(Services.Theme.border.r, Services.Theme.border.g, Services.Theme.border.b, 0.4)
        if (isUnified) return Qt.rgba(Services.Theme.border.r, Services.Theme.border.g, Services.Theme.border.b, 0.3)
        return "transparent"
    }

    // OS Logo & Workspaces Pill
    Rectangle {
        id: wsPill
        implicitHeight: wsRoot.pillHeight
        implicitWidth: wsPillLayout.implicitWidth + (wsRoot.isMinimal ? 12 : 20)
        radius: wsRoot.pillRadius
        color: wsRoot.getPillBg(wsPillMouse.containsMouse)
        border.color: wsRoot.getPillBorder(wsPillMouse.containsMouse)
        border.width: wsRoot.isMinimal ? 0 : 1

        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

        MouseArea {
            id: wsPillMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }

        RowLayout {
            id: wsPillLayout
            anchors.centerIn: parent
            spacing: wsRoot.isMinimal ? 6 : 10

            // OS Logo — click to toggle launcher / dashboard
            Item {
                Layout.preferredWidth: logoText.implicitWidth
                Layout.preferredHeight: logoText.implicitHeight
                Layout.alignment: Qt.AlignVCenter

                Text {
                    id: logoText
                    anchors.centerIn: parent
                    text: Services.OsInfo.logoGlyph
                    font.family: Services.Theme.fontMono
                    font.pixelSize: wsRoot.isMinimal ? Services.Theme.fontSizeXl : Services.Theme.fontSize3xl
                    color: logoMouse.containsMouse ? Qt.lighter(Services.Theme.accent, 1.2) : Services.Theme.accent
                    scale: logoMouse.containsMouse ? 1.1 : 1.0

                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
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
                height: wsRoot.isMinimal ? 10 : 12
                color: Services.Theme.border
                opacity: 0.8
                Layout.alignment: Qt.AlignVCenter
            }

            // Workspace Indicators
            RowLayout {
                id: wsRow
                spacing: (wsRoot.workspaceStyle === "numbers" || wsRoot.workspaceStyle === "icons") ? (wsRoot.isMinimal ? 2 : 4) : 6
                Layout.alignment: Qt.AlignVCenter

                property var workspaceList: {
                    const list = wsRoot.showAll ? [1, 2, 3, 4, 5] : []
                    const openList = Services.Workspaces.workspaceIds || []
                    const activeId = Services.Workspaces.activeWorkspaceId || 1
                    if (!list.includes(activeId)) list.push(activeId)
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

                        Layout.alignment: Qt.AlignVCenter

                        // Size depends on workspaceStyle
                        Layout.preferredWidth: {
                            if (wsRoot.workspaceStyle === "numbers" || wsRoot.workspaceStyle === "icons") {
                                return wsRoot.isMinimal ? 18 : 22
                            } else if (wsRoot.workspaceStyle === "dots") {
                                return isActive ? (wsRoot.isMinimal ? 8 : 10) : (isOccupied ? 6 : 5)
                            } else {
                                // "pills" default
                                return isActive ? 22 : (isOccupied ? 12 : 7)
                            }
                        }

                        Layout.preferredHeight: {
                            if (wsRoot.workspaceStyle === "numbers" || wsRoot.workspaceStyle === "icons") {
                                return wsRoot.isMinimal ? 18 : 22
                            } else if (wsRoot.workspaceStyle === "dots") {
                                return isActive ? (wsRoot.isMinimal ? 8 : 10) : (isOccupied ? 6 : 5)
                            } else {
                                return 7
                            }
                        }

                        Behavior on Layout.preferredWidth {
                            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                        }

                        // --- PILLS STYLE ---
                        Rectangle {
                            visible: wsRoot.workspaceStyle === "pills"
                            anchors.fill: parent
                            radius: 3.5
                            color: wsItem.isActive ? Services.Theme.accent
                                 : (wsMouse.containsMouse ? Services.Theme.textPrimary
                                 : (wsItem.isOccupied ? Services.Theme.accentDim : Services.Theme.textDisabled))
                            opacity: wsItem.isActive ? 1.0 : (wsMouse.containsMouse ? 1.0 : (wsItem.isOccupied ? 0.75 : 0.35))

                            Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }

                        // --- DOTS STYLE ---
                        Rectangle {
                            visible: wsRoot.workspaceStyle === "dots"
                            anchors.fill: parent
                            radius: width / 2
                            color: wsItem.isActive ? Services.Theme.accent
                                 : (wsMouse.containsMouse ? Services.Theme.textPrimary
                                 : (wsItem.isOccupied ? Services.Theme.accentDim : Services.Theme.textDisabled))
                            opacity: wsItem.isActive ? 1.0 : (wsMouse.containsMouse ? 1.0 : (wsItem.isOccupied ? 0.8 : 0.3))

                            Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }

                        // --- NUMBERS STYLE ---
                        Rectangle {
                            visible: wsRoot.workspaceStyle === "numbers"
                            anchors.fill: parent
                            radius: wsRoot.isMinimal ? 4 : 6
                            color: wsItem.isActive ? Services.Theme.accent 
                                : (wsMouse.containsMouse ? Services.Theme.bgHover 
                                : (wsItem.isOccupied ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15) : "transparent"))
                            border.color: wsItem.isActive ? Services.Theme.accent 
                                : (wsItem.isOccupied ? Services.Theme.accentDim : "transparent")
                            border.width: wsItem.isOccupied && !wsItem.isActive ? 1 : 0

                            Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                            Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                            Text {
                                anchors.centerIn: parent
                                text: wsItem.wsId
                                font.family: Services.Theme.fontMono
                                font.pixelSize: wsRoot.isMinimal ? 9 : 10
                                font.bold: wsItem.isActive || wsItem.isOccupied
                                color: wsItem.isActive ? Services.Theme.bgOnAccent 
                                    : (wsMouse.containsMouse ? Services.Theme.textPrimary 
                                    : (wsItem.isOccupied ? Services.Theme.accent : Services.Theme.textDisabled))
                                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                            }
                        }

                        // --- ICONS STYLE ---
                        Rectangle {
                            visible: wsRoot.workspaceStyle === "icons"
                            anchors.fill: parent
                            radius: wsRoot.isMinimal ? 4 : 6
                            color: wsItem.isActive ? Services.Theme.accent 
                                : (wsMouse.containsMouse ? Services.Theme.bgHover : "transparent")
                            border.color: (wsItem.isOccupied && !wsItem.isActive) ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.3) : "transparent"
                            border.width: 1

                            Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                            function getWsIcon(id) {
                                switch (id) {
                                    case 1: return "\uf120" // terminal
                                    case 2: return "\uf268" // web
                                    case 3: return "\uf121" // code
                                    case 4: return "\uf001" // music
                                    case 5: return "\uf07c" // files
                                    default: return "\uf108" // display
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: parent.getWsIcon(wsItem.wsId)
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: wsRoot.isMinimal ? 9 : 11
                                color: wsItem.isActive ? Services.Theme.bgOnAccent 
                                    : (wsMouse.containsMouse ? Services.Theme.textPrimary 
                                    : (wsItem.isOccupied ? Services.Theme.accent : Services.Theme.textDisabled))
                                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                            }
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
        implicitHeight: wsRoot.pillHeight
        implicitWidth: titleText.implicitWidth + (wsRoot.isMinimal ? 12 : 20)
        radius: wsRoot.pillRadius
        color: wsRoot.getPillBg(false)
        border.color: wsRoot.getPillBorder(false)
        border.width: wsRoot.isMinimal ? 0 : 1
        visible: Services.Workspaces.activeWindowTitle.length > 0
        Layout.maximumWidth: wsRoot.isMinimal ? 220 : 280

        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

        Text {
            id: titleText
            anchors.centerIn: parent
            width: parent.width - (wsRoot.isMinimal ? 12 : 20)
            text: Services.Workspaces.activeWindowTitle
            font.family: Services.Theme.fontMono
            font.pixelSize: wsRoot.isMinimal ? Services.Theme.fontSizeMd : Services.Theme.fontSizeLg
            color: Services.Theme.textSecondary
            elide: Text.ElideRight
        }
    }
}
