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

        visible: !(Services.OverlayManager && Services.OverlayManager.isWizardActive)

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
            readonly property real currentIslandW: dynamicIsland ? Math.max(dynamicIsland.calculatedCollapsedWidth + 20, dynamicIsland.islandWidth) : 0
            readonly property real currentIslandH: dynamicIsland ? Math.max(root.barHeight, dynamicIsland.islandHeight) : 0

            x: isIslandActive ? ((root.width - currentIslandW) / 2) : 0
            y: isIslandActive ? (root.isBottom ? (root.height - currentIslandH) : 0) : 0
            width: isIslandActive ? currentIslandW : 0
            height: isIslandActive ? currentIslandH : 0
        }
    }

    property real barTransitionState: (Services.OverlayManager && Services.OverlayManager.isLocked) ? 0.0 : 1.0

    // ── Expose bar visibility progress to lockscreen for phase-sync ───────────
    Binding {
        target: Services.OverlayManager
        property: "barIslandProgress"
        value: root.barTransitionState
        when: Services.OverlayManager !== null
    }

    NumberAnimation {
        id: barAbsorbAnim
        target: root
        property: "barTransitionState"
        from: 1.0
        to: 0.0
        duration: 240
        easing.type: Easing.InCubic
    }

    NumberAnimation {
        id: barEjectAnim
        target: root
        property: "barTransitionState"
        from: root.barTransitionState
        to: 1.0
        duration: 380
        easing.type: Easing.OutBack
        easing.overshoot: 1.20
    }

    Connections {
        target: Services.OverlayManager
        function onIsLockAbsorbingChanged() {
            if (Services.OverlayManager && Services.OverlayManager.isLockAbsorbing) {
                barEjectAnim.stop()
                barAbsorbAnim.restart()
            }
        }
        function onIsLockedChanged() {
            if (!Services.OverlayManager) return
            if (!Services.OverlayManager.isLocked) {
                // Desktop layer unlocked — begin eject immediately so bar
                // is already rising while lockscreen is still dissolving
                barEjectAnim.from = root.barTransitionState
                barEjectAnim.restart()
            } else if (!Services.OverlayManager.isLockAbsorbing) {
                root.barTransitionState = 0.0
            }
        }
        // ── Early eject: begin re-appearing at 55% suction so desktop bar
        //    overlaps the tail of the lockscreen dissolve — no dead zone
        function onUnlockSuctionProgressChanged() {
            if (!Services.OverlayManager) return
            const p = Services.OverlayManager.unlockSuctionProgress
            if (p >= 0.55 && root.barTransitionState < 0.05 && !barEjectAnim.running) {
                barEjectAnim.from = root.barTransitionState
                barEjectAnim.restart()
            }
        }
    }

    Item {
        id: barContainer
        anchors.fill: parent
        opacity: (Services.OverlayManager && Services.OverlayManager.isWizardActive) ? 0.0 : 1.0

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
            opacity: root.barTransitionState

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
            opacity: root.barTransitionState

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
            opacity: root.barTransitionState

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
                    id: workspaceIndicator
                    Layout.alignment: Qt.AlignVCenter
                    visible: Services.Config ? Services.Config.showWorkspaces : true

                    readonly property real wsCenterX: workspaceIndicator.x + ((workspaceIndicator.implicitWidth > 0 ? workspaceIndicator.implicitWidth : workspaceIndicator.width) / 2)
                    readonly property real targetDx: (root.width / 2) - wsCenterX

                    transform: [
                        Translate {
                            x: workspaceIndicator.targetDx * (1.0 - root.barTransitionState)
                        },
                        Scale {
                            origin.x: (workspaceIndicator.implicitWidth > 0 ? workspaceIndicator.implicitWidth : workspaceIndicator.width) / 2
                            origin.y: workspaceIndicator.height / 2
                            xScale: 0.15 + 0.85 * root.barTransitionState
                            yScale: 0.15 + 0.85 * root.barTransitionState
                        }
                    ]
                    opacity: Math.min(1.0, Math.max(0.0, root.barTransitionState * 1.35))
                }

                Item {
                    Layout.fillWidth: true
                }

                Components.StatusTray {
                    id: statusTray
                    Layout.alignment: Qt.AlignVCenter
                    barWidth: root.width
                    rightMargin: root.isFloating ? 18 : (root.isUnified ? 16 : 12)

                    // Lebar yang diklaim oleh elemen tengah — island, atau jam tengah pada mode non-island.
                    centerReservedWidth: root.showDynamicIsland
                        ? dynamicIsland.reservedWidth
                        : (centerClockContainer.visible ? centerClockContainer.width : 0)

                    islandDemand: root.showDynamicIsland ? dynamicIsland.demand : "idle"

                    readonly property real trayCenterX: statusTray.x + ((statusTray.implicitWidth > 0 ? statusTray.implicitWidth : statusTray.width) / 2)
                    readonly property real targetDx: (root.width / 2) - trayCenterX

                    transform: [
                        Translate {
                            x: statusTray.targetDx * (1.0 - root.barTransitionState)
                        },
                        Scale {
                            origin.x: (statusTray.implicitWidth > 0 ? statusTray.implicitWidth : statusTray.width) / 2
                            origin.y: statusTray.height / 2
                            xScale: 0.15 + 0.85 * root.barTransitionState
                            yScale: 0.15 + 0.85 * root.barTransitionState
                        }
                    ]
                    opacity: Math.min(1.0, Math.max(0.0, root.barTransitionState * 1.35))
                }
            }
        }

        // ── Center Clock for Non-Island Modes (Floating, Unified, Minimal) ────
        Item {
            id: centerClockContainer
            visible: !root.showDynamicIsland && (Services.Config ? Services.Config.showClockTray : true)
            anchors.centerIn: barRow
            height: root.barHeight
            width: centerClock.implicitWidth
            z: 10

            transform: Scale {
                origin.x: centerClockContainer.width / 2
                origin.y: centerClockContainer.height / 2
                xScale: 0.15 + 0.85 * root.barTransitionState
                yScale: 0.15 + 0.85 * root.barTransitionState
            }
            opacity: Math.min(1.0, Math.max(0.0, root.barTransitionState * 1.35))

            Components.ClockCenter {
                id: centerClock
                anchors.centerIn: parent
            }
        }
    }

    // ── Dynamic Island (Exclusive to Islands Mode) ────────────────────────
    Components.DynamicIsland {
        id: dynamicIsland
        anchors.fill: parent
        z: dynamicIsland.expanded ? 999 : 5
        visible: root.showDynamicIsland
    }

    // ── Wallpaper Preloader (GPU Pixmap Cache for Zero-Lag Lockscreen Transition) ──
    Image {
        id: lockscreenWallpaperCachePreloader
        visible: false
        width: 1
        height: 1
        sourceSize: Qt.size(Math.ceil(((root.screen && root.screen.width) ? root.screen.width : 1366) * 1.15), Math.ceil(((root.screen && root.screen.height) ? root.screen.height : 768) * 1.15))
        cache: true
        asynchronous: true
        source: {
            if (Services.Config && Services.Config.lockscreenWallpaperMode === "custom" && Services.Config.lockscreenCustomWallpaper.length > 0) {
                return "file://" + Services.Config.lockscreenCustomWallpaper
            }
            if (Services.Wallpaper && Services.Wallpaper.currentWallpaper && Services.Wallpaper.currentWallpaper.length > 0) {
                return "file://" + Services.Wallpaper.currentWallpaper
            }
            return (Services.Wallpaper && Services.Wallpaper.darkWallbler) ? ("file://" + Services.Wallpaper.darkWallbler) : ""
        }
    }
}
}

