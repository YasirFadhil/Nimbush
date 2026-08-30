import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "components" as Components
import "../../services" as Services

Variants {
    id: barVariants
    model: (Services.Config && Services.Config.barScreens) ? Services.Config.barScreens : Quickshell.screens

    delegate: PanelWindow {
        id: root
        required property var modelData
        screen: modelData

        readonly property bool isBottom: Services.Config ? (Services.Config.barPosition === "bottom") : false
    readonly property string barStyle: Services.Config ? Services.Config.barStyle : "islands"
    readonly property bool isMinimal: barStyle === "minimal"
    readonly property bool isUnified: barStyle === "unified"
    readonly property bool isFloating: barStyle === "floating"
    readonly property bool isIslands: barStyle === "islands"

    readonly property bool showDynamicIsland: root.isIslands && ((Services.Config ? Services.Config.islandStyle : "expanded") !== "hidden")

    readonly property int barHeight: isMinimal ? 30 : (isUnified ? 38 : 36)
    readonly property int barYOffset: isFloating 
        ? (isBottom ? (root.height - barHeight - 6) : 6) 
        : (isIslands ? (isBottom ? (root.height - barHeight - 4) : 4) : (isBottom ? (root.height - barHeight) : 0))

    anchors {
        top: !root.isBottom
        bottom: root.isBottom
        left: true
        right: true
    }

    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:bar"
    WlrLayershell.keyboardFocus: (root.showDynamicIsland && (dynamicIsland.replyMode || dynamicIsland.wallpaperMode)) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    exclusiveZone: isMinimal ? 30 : (isUnified ? 38 : (isFloating ? 46 : 36))
    implicitHeight: 220

    mask: Region {
        // Base bar clickable region
        Region {
            x: root.isFloating ? 12 : 0
            y: root.barYOffset
            width: root.isFloating ? (root.width - 24) : root.width
            height: root.barHeight
        }
        // Dynamic Island expanded region (only in islands mode)
        Region {
            readonly property bool isIslandActive: root.showDynamicIsland
            x: isIslandActive ? ((root.width - (dynamicIsland.expanded ? Math.max(480, dynamicIsland.islandWidth) : Math.max(160, dynamicIsland.calculatedCollapsedWidth + 20))) / 2) : 0
            y: isIslandActive ? (root.isBottom ? (root.height - (dynamicIsland.expanded ? Math.max(140, dynamicIsland.islandHeight) : root.barHeight)) : 0) : 0
            width: isIslandActive ? (dynamicIsland.expanded ? Math.max(480, dynamicIsland.islandWidth) : Math.max(160, dynamicIsland.calculatedCollapsedWidth + 20)) : 0
            height: isIslandActive ? (dynamicIsland.expanded ? Math.max(140, dynamicIsland.islandHeight) : root.barHeight) : 0
        }
    }

    Item {
        id: barContainer
        anchors.fill: parent

        // ── 1. Floating Glass Bar Container ───────────────────────────────────
        Rectangle {
            id: floatingBg
            visible: root.isFloating
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            y: root.barYOffset
            height: root.barHeight
            radius: Math.min(18, Services.Theme.baseRadius)
            color: Services.Theme.bgElevated
            border.color: Services.Theme.border
            border.width: 1

            // Subtle top/inner glow
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.color: Qt.rgba(1, 1, 1, Services.Theme.isDark ? 0.07 : 0.2)
                border.width: 1
            }
        }

        // ── 2. Unified Edge-to-Edge Bar Container ────────────────────────────
        Rectangle {
            id: unifiedBg
            visible: root.isUnified
            anchors.left: parent.left
            anchors.right: parent.right
            y: root.barYOffset
            height: root.barHeight
            color: Services.Theme.bgElevated

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: root.isBottom ? undefined : parent.bottom
                anchors.top: root.isBottom ? parent.top : undefined
                height: 1
                color: Services.Theme.border
            }
        }

        // ── 3. Minimalist Bar Container ──────────────────────────────────────
        Rectangle {
            id: minimalBg
            visible: root.isMinimal
            anchors.left: parent.left
            anchors.right: parent.right
            y: root.barYOffset
            height: root.barHeight
            color: Qt.rgba(Services.Theme.bgElevated.r, Services.Theme.bgElevated.g, Services.Theme.bgElevated.b, 0.65)

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: root.isBottom ? undefined : parent.bottom
                anchors.top: root.isBottom ? parent.top : undefined
                height: 1
                color: Services.Theme.borderSubtle
            }
        }

        // ── Main Bar Content Row ─────────────────────────────────────────────
        Item {
            id: barRow
            anchors.left: parent.left
            anchors.right: parent.right
            height: root.barHeight
            y: root.barYOffset
            z: dynamicIsland.expanded ? 1 : 10

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: root.isFloating ? 18 : (root.isUnified ? 16 : 12)
                anchors.rightMargin: root.isFloating ? 18 : (root.isUnified ? 16 : 12)
                spacing: root.isMinimal ? 8 : 12

                Components.WorkspaceIndicator {
                    Layout.alignment: Qt.AlignVCenter
                    visible: Services.Config ? Services.Config.showWorkspaces : true
                    opacity: Services.OverlayManager.isLocked ? 0.0 : 1.0
                    transform: Translate {
                        x: Services.OverlayManager.isLocked ? -35 : 0
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
                    barWidth: root.width
                    islandRightEdge: root.showDynamicIsland ? ((root.width + (dynamicIsland.expanded ? dynamicIsland.calculatedExpandedWidth : dynamicIsland.calculatedCollapsedWidth)) / 2) : 0
                    isIslandExpanded: root.showDynamicIsland && dynamicIsland.expanded
                }
            }
        }

        // ── Center Clock for Non-Island Modes (Floating, Unified, Minimal) ────
        Item {
            id: centerClockContainer
            visible: !root.showDynamicIsland && (Services.Config ? Services.Config.showClockTray : true)
            anchors.centerIn: barRow
            height: root.barHeight
            z: 10

            Components.ClockCenter {
                anchors.centerIn: parent
            }
        }
          
        // ── Dynamic Island (Exclusive to Islands Mode) ────────────────────────
        Components.DynamicIsland {
            id: dynamicIsland
            anchors.fill: parent
            z: dynamicIsland.expanded ? 999 : 5
            visible: root.showDynamicIsland
        }
    }
}
}
