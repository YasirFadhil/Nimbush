import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "components" as Components
import "../../services" as Services

PanelWindow {
    id: root

    readonly property bool isBottom: Services.Config ? (Services.Config.barPosition === "bottom") : false

    anchors {
        top: !root.isBottom
        bottom: root.isBottom
        left: true
        right: true
    }

    color: "transparent"
    WlrLayershell.namespace: "quickshell:bar"
    WlrLayershell.keyboardFocus: dynamicIsland.replyMode ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    exclusiveZone: 36
    implicitHeight: 160

    mask: Region {
        Region {
            x: 0
            y: root.isBottom ? (root.height - 36) : 0
            width: root.width
            height: 36
        }
        Region {
            x: (root.width - (dynamicIsland.expanded ? 400 : Math.max(160, dynamicIsland.calculatedCollapsedWidth + 20))) / 2
            y: root.isBottom ? (root.height - (dynamicIsland.expanded ? 160 : 36)) : 0
            width: dynamicIsland.expanded ? 400 : Math.max(160, dynamicIsland.calculatedCollapsedWidth + 20)
            height: dynamicIsland.expanded ? 160 : 36
        }
    }

    Item {
        id: barContainer
        anchors.fill: parent

        Item {
            id: barRow
            anchors.left: parent.left
            anchors.right: parent.right
            height: 36
            y: root.isBottom ? (parent.height - height - 4) : 4

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 12

                Components.WorkspaceIndicator {
                    Layout.alignment: Qt.AlignVCenter
                    visible: (Services.Config ? Services.Config.showWorkspaces : true) && opacity > 0
                    opacity: Services.OverlayManager.isLocked ? 0.0 : 1.0
                    transform: Translate {
                        x: Services.OverlayManager.isLocked ? -40 : 0
                        Behavior on x { NumberAnimation { duration: 350; easing.type: Services.OverlayManager.isLocked ? Easing.OutCubic : Easing.InCubic } }
                    }
                    Behavior on opacity { NumberAnimation { duration: 350; easing.type: Services.OverlayManager.isLocked ? Easing.OutCubic : Easing.InCubic } }
                }

                Item {
                    Layout.fillWidth: true
                }

                Components.StatusTray {
                    id: statusTray
                    Layout.alignment: Qt.AlignVCenter

                    readonly property real islandRightEdge: (root.width + dynamicIsland.calculatedCollapsedWidth) / 2
                    readonly property real trayFullLeftEdge: root.width - 12 - statusTray.fullUncollapsedWidth

                    collapseNear: dynamicIsland.expanded
                                 || (dynamicIsland.calculatedCollapsedWidth > 180)
                                 || (trayFullLeftEdge <= islandRightEdge + 24)
                    collapseMore: dynamicIsland.expanded && (dynamicIsland.calculatedExpandedWidth >= 320 || dynamicIsland.notifActive || dynamicIsland.replyMode)
                }
            }
        }
          
        Components.DynamicIsland {
            id: dynamicIsland
            anchors.fill: parent
            z: 999
        }
    }
}
