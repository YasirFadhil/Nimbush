import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../services" as Services

Variants {
    id: dockVariants
    model: {
        if (!Services.Config || !Services.Config.dockEnabled) return []
        if (Services.Config.dockMonitorMode === "primary") {
            var prim = ""
            if (Services.Compositor && Services.Compositor.monitorsList && Services.Compositor.monitorsList.length > 0) {
                var f = Services.Compositor.monitorsList.find(m => m.focused)
                prim = f ? f.name : Services.Compositor.monitorsList[0].name
            }
            if (Quickshell.screens) {
                for (var j = 0; j < Quickshell.screens.length; j++) {
                    if (Quickshell.screens[j] && Quickshell.screens[j].name === prim) {
                        return [Quickshell.screens[j]]
                    }
                }
                return Quickshell.screens[0] ? [Quickshell.screens[0]] : []
            }
            return []
        }
        return Quickshell.screens || []
    }

    delegate: PanelWindow {
        id: root
        required property var modelData
        screen: modelData

        visible: !(Services.OverlayManager && Services.OverlayManager.isWizardActive)

        // ── Configuration Properties ─────────────────────────────────────────
        readonly property string pos: Services.Config ? Services.Config.dockPosition : "bottom"
        readonly property bool isBottom: pos === "bottom"
        readonly property bool isLeft: pos === "left"
        readonly property bool isRight: pos === "right"
        readonly property bool isVertical: isLeft || isRight

        readonly property bool autoHide: Services.Config ? Services.Config.dockAutoHide : false
        readonly property int iconSize: Services.Config ? Services.Config.dockIconSize : 48
        readonly property bool magnification: Services.Config ? Services.Config.dockMagnification : true
        readonly property real maxScale: Services.Config ? Services.Config.dockMagnificationScale : 1.35
        readonly property bool showIndicators: Services.Config ? Services.Config.dockShowIndicators : true
        readonly property string indicatorStyle: Services.Config ? Services.Config.dockIndicatorStyle : "dot"
        readonly property bool showTooltips: Services.Config ? Services.Config.dockShowTooltips : true
        readonly property bool showWindowCount: Services.Config ? Services.Config.dockShowWindowCount : true
        readonly property bool bounceOnClick: Services.Config ? Services.Config.dockBounceOnClick : true
        readonly property bool showSeparator: Services.Config ? Services.Config.dockShowSeparator : true
        readonly property int edgeMargin: Services.Config ? Services.Config.dockFloatingDistance : 6

        // Dock Dimensions
        readonly property int dockBarHeight: iconSize + 16
        // Extra headroom for icon lift, shadow, and tooltips
        readonly property int windowHeadroom: 64
        readonly property int windowBreadth: dockBarHeight + windowHeadroom

        property bool isHovered: false

        // ── macOS Global Magnification Progress ──────────────────────────────
        // Crisp 60ms bloom on enter (instant response, zero delay), swift 100ms dissolve on exit.
        property real hoverProgress: (root.magnification && root.isHovered) ? 1.0 : 0.0
        Behavior on hoverProgress {
            NumberAnimation {
                duration: root.isHovered ? 60 : 100
                easing.type: Easing.OutQuad
            }
        }

        anchors {
            bottom: root.isBottom || root.isVertical
            top: root.isVertical
            left: root.isBottom || root.isLeft
            right: root.isBottom || root.isRight
        }

        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell:dock"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // Reserve space for tiled windows only when auto-hide is disabled
        exclusiveZone: root.autoHide ? 0 : (root.dockBarHeight + root.edgeMargin + 2)

        implicitHeight: root.isVertical ? (root.screen ? root.screen.height : 768) : root.windowBreadth
        implicitWidth: root.isVertical ? root.windowBreadth : (root.screen ? root.screen.width : 1366)

        // ── Analytical Nominal Center Geometry ───────────────────────────────
        // Invariant to dynamic delegate width and scaling.
        // Prevents layout feedback loops and hover jitter.
        readonly property int pinnedCount: (Services.DockService && Services.DockService.pinnedDockItems) ? Services.DockService.pinnedDockItems.length : 0
        readonly property int unpinnedCount: (Services.DockService && Services.DockService.unpinnedDockItems) ? Services.DockService.unpinnedDockItems.length : 0
        readonly property bool hasSeparator: root.showSeparator && pinnedCount > 0 && unpinnedCount > 0
        readonly property real separatorNominalSize: hasSeparator ? 13 : 0
        readonly property real itemSpacing: 8

        readonly property real totalNominalLength: {
            const count = pinnedCount + unpinnedCount
            if (count === 0) return 0
            const totalItems = count + (hasSeparator ? 1 : 0)
            return (count * root.iconSize) + (hasSeparator ? separatorNominalSize : 0) + ((totalItems - 1) * itemSpacing)
        }

        function getNominalCenter(isPinnedGroup, index) {
            if (isPinnedGroup) {
                return (index * (root.iconSize + itemSpacing)) + (root.iconSize / 2)
            } else {
                return (pinnedCount * (root.iconSize + itemSpacing)) + (hasSeparator ? (separatorNominalSize + itemSpacing) : 0) + (index * (root.iconSize + itemSpacing)) + (root.iconSize / 2)
            }
        }

        // ── Single Dock Mouse Coordinate Tracker (Dock-Relative Space) ────────
        readonly property real mouseDockCoord: (root.isHovered && dockTracker.containsMouse) ? dockTracker.dockMousePos : dockTracker.lastValidDockMousePos

        // ── Pinned Drag-and-Drop Reordering State ─────────────────────────────
        property int draggedPinnedIndex: -1
        property int targetDropIndex: -1
        readonly property bool isDraggingPinned: draggedPinnedIndex >= 0

        function startPinnedDrag(index) {
            draggedPinnedIndex = index
            targetDropIndex = index
        }

        function updatePinnedDrag(targetIndex) {
            if (targetDropIndex !== targetIndex) {
                targetDropIndex = targetIndex
            }
        }

        function finishPinnedDrag() {
            const fromIdx = draggedPinnedIndex
            const toIdx = targetDropIndex
            draggedPinnedIndex = -1
            targetDropIndex = -1
            if (fromIdx >= 0 && toIdx >= 0 && fromIdx !== toIdx) {
                if (Services.DockService) {
                    Services.DockService.movePinned(fromIdx, toIdx)
                }
            }
        }

        function cancelPinnedDrag() {
            draggedPinnedIndex = -1
            targetDropIndex = -1
        }

        function getClosestPinnedSlot(coord) {
            if (root.pinnedCount <= 1) return 0
            let closestIdx = 0
            let minDist = 999999
            for (let k = 0; k < root.pinnedCount; k++) {
                const itm = pinnedRepeater.itemAt(k)
                if (!itm) continue
                const center = root.isVertical ? (itm.y + itm.height / 2) : (itm.x + itm.width / 2)
                const d = Math.abs(coord - center)
                if (d < minDist) {
                    minDist = d
                    closestIdx = k
                }
            }
            return closestIdx
        }

        // ── Masking (Wayland Input Region) ───────────────────────────────────
        // Strictly matches dockContainer horizontally.
        // Reaches bottom of monitor (zero bottom gap) and only 6px upward when hovered.
        mask: Region {
            Region {
                x: (root.isRight && root.isHovered) ? Math.max(0, dockContainer.x - 6) : dockContainer.x
                y: (root.isBottom && root.isHovered) ? Math.max(0, dockContainer.y - 6) : dockContainer.y
                width: (root.isVertical && root.isHovered) ? (dockContainer.width + 6) : dockContainer.width
                height: root.isBottom
                    ? (dockContainer.height + root.edgeMargin + (root.isHovered ? 6 : 0))
                    : ((root.isVertical && root.isHovered) ? (dockContainer.height + 6) : dockContainer.height)
            }
            // Auto-hide bottom edge trigger strip (when autoHide is enabled)
            Region {
                x: root.isLeft ? 0 : (root.isRight ? (root.width - 8) : Math.max(0, (root.width - Math.max(320, dockContainer.width)) / 2))
                y: root.isBottom ? (root.height - 8) : 0
                width: root.isVertical ? (root.autoHide ? 8 : 0) : Math.max(320, dockContainer.width)
                height: root.isVertical ? Math.max(320, dockContainer.height) : (root.autoHide ? 8 : 0)
            }
        }

        // ── Auto-hide Hide Delay Timer ───────────────────────────────────────
        Timer {
            id: hideDelayTimer
            interval: 350
            repeat: false
            onTriggered: {
                if (!hoverEdgeDetector.containsMouse && !dockTracker.containsMouse) {
                    root.isHovered = false
                }
            }
        }

        // ── Auto-hide Edge Trigger Detector ──────────────────────────────────
        MouseArea {
            id: hoverEdgeDetector
            visible: root.autoHide
            anchors.bottom: root.isBottom ? parent.bottom : undefined
            anchors.top: root.isVertical ? parent.top : undefined
            anchors.left: root.isLeft ? parent.left : (root.isBottom ? parent.left : undefined)
            anchors.right: root.isRight ? parent.right : (root.isBottom ? parent.right : undefined)

            width: root.isVertical ? 8 : parent.width
            height: root.isVertical ? parent.height : 8

            hoverEnabled: true
            onEntered: {
                hideDelayTimer.stop()
                root.isHovered = true
            }
        }

        // ── Main Dock Container (Liquid Glass Floating Pill) ─────────────────
        Rectangle {
            id: dockContainer
            opacity: (Services.OverlayManager && Services.OverlayManager.isWizardActive) ? 0.0 : 1.0
            Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

            // Center positioning on screen
            x: {
                if (root.isBottom) {
                    return Math.round((parent.width - width) / 2)
                } else if (root.isLeft) {
                    return !root.autoHide ? root.edgeMargin : (root.isHovered ? root.edgeMargin : (-width + 4))
                } else {
                    return !root.autoHide ? (parent.width - width - root.edgeMargin) : (root.isHovered ? (parent.width - width - root.edgeMargin) : (parent.width - 4))
                }
            }

            y: {
                if (root.isBottom) {
                    return !root.autoHide ? (parent.height - height - root.edgeMargin) : (root.isHovered ? (parent.height - height - root.edgeMargin) : (parent.height - 4))
                } else {
                    return Math.round((parent.height - height) / 2)
                }
            }

            Behavior on x {
                enabled: root.autoHide && root.isVertical
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
            Behavior on y {
                enabled: root.autoHide && !root.isVertical
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

            // Dynamic Dimensions: exactly hugs itemsLayout with 8px padding.
            // Expands in 100% hardware lockstep with icon magnification.
            height: root.isVertical ? Math.max(root.dockBarHeight, Math.round(itemsLayout.height + 16)) : root.dockBarHeight
            width: root.isVertical ? root.dockBarHeight : Math.max(root.dockBarHeight, Math.round(itemsLayout.width + 16))
            radius: Math.min(22, Math.round(root.dockBarHeight * 0.35))

            // macOS Liquid Glass Styling
            color: Services.Theme.isDark ? Qt.rgba(0.08, 0.08, 0.12, 0.84) : Qt.rgba(0.96, 0.96, 0.98, 0.90)
            border.color: Services.Theme.isDark
                ? Qt.rgba(1, 1, 1, root.isHovered ? 0.22 : 0.14)
                : Qt.rgba(0, 0, 0, root.isHovered ? 0.16 : 0.10)
            border.width: 1
            Behavior on border.color { ColorAnimation { duration: 180 } }

            // Inner subtle border rim
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                color: "transparent"
                border.color: Qt.rgba(1, 1, 1, Services.Theme.isDark ? 0.04 : 0.15)
                border.width: 1
            }

            // ── Unified Dock Tracker MouseArea ───────────────────────────────
            // Strictly 0 margins when idle so hover only triggers when cursor physically touches the dock pill.
            // When already hovered, expands slightly upward so cursor can hover lifted icons.
            MouseArea {
                id: dockTracker
                anchors.fill: parent
                anchors.topMargin: (root.isBottom && root.isHovered) ? -6 : 0
                anchors.bottomMargin: root.isBottom ? -root.edgeMargin : 0
                anchors.leftMargin: (root.isRight && root.isHovered) ? -6 : 0
                anchors.rightMargin: (root.isLeft && root.isHovered) ? -6 : 0
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                cursorShape: Qt.PointingHandCursor
                z: 100

                property real dockMousePos: -99999
                property real lastValidDockMousePos: 0

                function updateMouse(mx, my) {
                    if (root.isVertical) {
                        dockMousePos = dockTracker.y + my
                    } else {
                        dockMousePos = dockTracker.x + mx
                    }
                    lastValidDockMousePos = dockMousePos
                }

                onPositionChanged: (mouse) => {
                    updateMouse(mouse.x, mouse.y)
                    if (!root.isHovered) {
                        hideDelayTimer.stop()
                        root.isHovered = true
                    }
                }
                onEntered: {
                    hideDelayTimer.stop()
                    updateMouse(dockTracker.mouseX, dockTracker.mouseY)
                    root.isHovered = true
                }
                onExited: {
                    dockMousePos = -99999
                    root.isHovered = false
                    if (root.autoHide) {
                        hideDelayTimer.restart()
                    }
                }
            }

            // ── Items Layout ─────────────────────────────────────────────────
            Grid {
                id: itemsLayout
                anchors.centerIn: parent
                anchors.alignWhenCentered: false
                spacing: root.itemSpacing
                flow: root.isVertical ? Grid.TopToBottom : Grid.LeftToRight
                rows: root.isVertical ? -1 : 1
                columns: root.isVertical ? 1 : -1

                // ── 1. Pinned Applications ───────────────────────────────────
                Repeater {
                    id: pinnedRepeater
                    model: (Services.DockService && Services.DockService.pinnedDockItems) ? Services.DockService.pinnedDockItems : []
                    delegate: iconDelegateComponent
                }

                // ── 2. macOS-Style Hairline Separator ────────────────────────
                Item {
                    id: dockSeparatorContainer
                    visible: root.hasSeparator
                    width: root.isVertical ? root.iconSize : 13
                    height: root.isVertical ? 13 : root.iconSize

                    Rectangle {
                        id: dockSeparator
                        anchors.centerIn: parent
                        width: root.isVertical ? (root.iconSize * 0.55) : 1
                        height: root.isVertical ? 1 : (root.iconSize * 0.55)
                        color: Services.Theme.isDark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.18)

                        // Subtle shadow alongside hairline
                        Rectangle {
                            anchors.top: root.isVertical ? parent.bottom : parent.top
                            anchors.bottom: root.isVertical ? undefined : parent.bottom
                            anchors.left: root.isVertical ? parent.left : parent.right
                            anchors.right: root.isVertical ? parent.right : undefined
                            width: root.isVertical ? parent.width : 1
                            height: root.isVertical ? 1 : parent.height
                            color: Services.Theme.isDark ? Qt.rgba(0, 0, 0, 0.3) : Qt.rgba(1, 1, 1, 0.45)
                        }
                    }
                }

                // ── 3. Running Unpinned Applications ─────────────────────────
                Repeater {
                    id: unpinnedRepeater
                    model: (Services.DockService && Services.DockService.unpinnedDockItems) ? Services.DockService.unpinnedDockItems : []
                    delegate: iconDelegateComponent
                }
            }
        }

        // ── Reusable Icon Delegate Component ─────────────────────────────────
        Component {
            id: iconDelegateComponent

            Item {
                id: iconDelegate
                required property var modelData
                required property int index

                // Group identification
                readonly property bool isPinnedItem: Boolean(modelData && modelData.isPinned)

                // ── Stable Nominal Center Math (Dock-Relative Space) ─────────
                readonly property real itemNominalCenter: root.getNominalCenter(isPinnedItem, index)
                readonly property real distToMouse: Math.abs(root.mouseDockCoord - 8 - itemNominalCenter)

                // Harmonic 2.2-pitch radius ensures a luscious, organic wave crest
                readonly property real radiusInfluence: (root.iconSize + root.itemSpacing) * 2.2

                // Mathematical macOS Raised-Cosine Harmonic Envelope
                readonly property real rawEnvelope: {
                    if (distToMouse >= radiusInfluence) return 0.0
                    const norm = distToMouse / radiusInfluence
                    const c = Math.cos(norm * (Math.PI / 2))
                    return c * c
                }

                // ── True macOS Direct Visual Scale (Zero Latency Wave) ────────
                // ── True macOS Direct Visual Scale ───────────────────────────
                property real visualScale: 1.0 + ((root.maxScale - 1.0) * rawEnvelope * root.hoverProgress)
                Behavior on visualScale {
                    enabled: root.isHovered
                    NumberAnimation {
                        duration: 75
                        easing.type: Easing.OutQuad
                    }
                }

                // ── macOS Delegate Bounds (Continuous Sub-pixel Wave Push) ───
                width: root.isVertical ? root.iconSize : (root.iconSize * visualScale)
                height: root.isVertical ? (root.iconSize * visualScale) : root.iconSize

                // Higher scale icons render in front smoothly without integer scene-graph sorting churn
                z: isDraggingThis ? 9999 : ((visualScale > 1.002) ? (10 + visualScale) : 1)

                // ── Drag Reorder State ───────────────────────────────────────
                readonly property bool isDraggingThis: root.draggedPinnedIndex === iconDelegate.index && iconDelegate.isPinnedItem
                property bool wasDragged: false
                property real pressStartX: 0
                property real pressStartY: 0
                property real dragOffsetX: 0
                property real dragOffsetY: 0

                readonly property real slotShift: root.iconSize * 1.1 + root.itemSpacing
                readonly property real reorderShift: {
                    if (!root.isDraggingPinned || !isPinnedItem || isDraggingThis) return 0
                    if (root.draggedPinnedIndex < root.targetDropIndex) {
                        if (index > root.draggedPinnedIndex && index <= root.targetDropIndex) {
                            return -slotShift
                        }
                    } else if (root.draggedPinnedIndex > root.targetDropIndex) {
                        if (index < root.draggedPinnedIndex && index >= root.targetDropIndex) {
                            return slotShift
                        }
                    }
                    return 0
                }

                // ── App Launch State Tracking ────────────────────────────────
                property bool isLaunching: Boolean(modelData && modelData.isLaunching)

                Timer {
                    id: launchTimeoutTimer
                    interval: 10000 // 10s maximum safety limit
                    repeat: false
                    onTriggered: {
                        iconDelegate.isLaunching = false
                        if (iconDelegate.modelData) iconDelegate.modelData.isLaunching = false
                    }
                }

                function startLaunching() {
                    iconDelegate.isLaunching = true
                    if (iconDelegate.modelData) iconDelegate.modelData.isLaunching = true
                    launchTimeoutTimer.restart()
                }

                Connections {
                    target: iconDelegate.modelData || null
                    function onIsRunningChanged() {
                        if (iconDelegate.modelData && iconDelegate.modelData.isRunning) {
                            launchTimeoutTimer.stop()
                            iconDelegate.isLaunching = false
                        }
                    }
                    function onWindowCountChanged() {
                        if (iconDelegate.modelData && iconDelegate.modelData.windowCount > 0) {
                            launchTimeoutTimer.stop()
                            iconDelegate.isLaunching = false
                        }
                    }
                    function onIsLaunchingChanged() {
                        iconDelegate.isLaunching = Boolean(iconDelegate.modelData && iconDelegate.modelData.isLaunching)
                        if (iconDelegate.isLaunching) launchTimeoutTimer.restart()
                        else launchTimeoutTimer.stop()
                    }
                }

                // ── Hover Detection for Tooltip ──────────────────────────────
                readonly property bool isDirectlyHovered: root.isHovered && (distToMouse < (root.iconSize * 0.48))

                // ── Visual Icon Item (macOS Shelf-Anchored Lift) ─────────────
                Item {
                    id: iconVisual
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.alignWhenCentered: false
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: root.isBottom ? (4 + Math.round((iconDelegate.visualScale - 1.0) * 8)) : 0
                    anchors.left: root.isLeft ? parent.left : undefined
                    anchors.leftMargin: root.isLeft ? (4 + Math.round((iconDelegate.visualScale - 1.0) * 8)) : 0
                    anchors.right: root.isRight ? parent.right : undefined
                    anchors.rightMargin: root.isRight ? (4 + Math.round((iconDelegate.visualScale - 1.0) * 8)) : 0
                    anchors.verticalCenter: root.isVertical ? parent.verticalCenter : undefined

                    width: root.iconSize
                    height: root.iconSize
                    scale: iconDelegate.isDraggingThis ? (iconDelegate.visualScale * 1.08) : iconDelegate.visualScale
                    opacity: iconDelegate.isDraggingThis ? 0.88 : 1.0
                    transformOrigin: root.isBottom ? Item.Bottom : (root.isLeft ? Item.Left : (root.isRight ? Item.Right : Item.Center))

                    transform: [
                        Translate {
                            id: bounceTranslate
                            x: 0
                            y: 0
                        },
                        Translate {
                            id: dragTranslate
                            x: iconDelegate.isDraggingThis ? iconDelegate.dragOffsetX : 0
                            y: iconDelegate.isDraggingThis ? iconDelegate.dragOffsetY : 0
                        },
                        Translate {
                            id: reorderTranslate
                            x: root.isVertical ? 0 : iconDelegate.reorderShift
                            y: root.isVertical ? iconDelegate.reorderShift : 0
                            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }
                            Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }
                        }
                    ]

                    // Continuous macOS-style Launch Bounce (repeats until app window opens)
                    SequentialAnimation {
                        id: launchBounceAnim
                        loops: Animation.Infinite
                        running: iconDelegate.isLaunching

                        // 1. Leap up
                        NumberAnimation {
                            target: bounceTranslate
                            property: root.isVertical ? "x" : "y"
                            to: root.isBottom ? -20 : (root.isLeft ? 20 : -20)
                            duration: 220
                            easing.type: Easing.OutQuad
                        }

                        // 2. Drop down
                        NumberAnimation {
                            target: bounceTranslate
                            property: root.isVertical ? "x" : "y"
                            to: 0
                            duration: 200
                            easing.type: Easing.InQuad
                        }

                        // 3. Impact cushion / squash
                        NumberAnimation {
                            target: bounceTranslate
                            property: root.isVertical ? "x" : "y"
                            to: root.isBottom ? 2 : (root.isLeft ? -2 : 2)
                            duration: 60
                            easing.type: Easing.OutQuad
                        }

                        // 4. Return to rest
                        NumberAnimation {
                            target: bounceTranslate
                            property: root.isVertical ? "x" : "y"
                            to: 0
                            duration: 70
                            easing.type: Easing.OutCubic
                        }

                        // Pause
                        PauseAnimation {
                            duration: 110
                        }

                        onStopped: {
                            settleAnimation.restart()
                        }
                    }

                    // Graceful landing animation when launch completes
                    NumberAnimation {
                        id: settleAnimation
                        target: bounceTranslate
                        properties: "x,y"
                        to: 0
                        duration: 140
                        easing.type: Easing.OutCubic
                    }

                    // Tactile macOS Bounce on Window Focus / Click (Already running)
                    SequentialAnimation {
                        id: clickBounce
                        NumberAnimation {
                            target: bounceTranslate
                            property: root.isVertical ? "x" : "y"
                            to: root.isBottom ? -8 : (root.isLeft ? 8 : -8)
                            duration: 70
                            easing.type: Easing.OutQuad
                        }
                        NumberAnimation {
                            target: bounceTranslate
                            property: root.isVertical ? "x" : "y"
                            to: 0
                            duration: 90
                            easing.type: Easing.OutBounce
                        }
                    }

                    // Fallback Badge (Letter)
                    Rectangle {
                        anchors.fill: parent
                        radius: Math.round(root.iconSize * 0.24)
                        color: (iconDelegate.modelData && iconDelegate.modelData.isActive)
                            ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.25)
                            : (iconDelegate.isDirectlyHovered ? Services.Theme.bgHover : Qt.rgba(255, 255, 255, 0.08))
                        border.color: (iconDelegate.modelData && iconDelegate.modelData.isActive) ? Services.Theme.accent : "transparent"
                        border.width: (iconDelegate.modelData && iconDelegate.modelData.isActive) ? 1 : 0
                        visible: !appImg.source || appImg.status !== Image.Ready || !appImg.visible

                        Text {
                            anchors.centerIn: parent
                            text: (iconDelegate.modelData ? (iconDelegate.modelData.name || "?") : "?").charAt(0).toUpperCase()
                            color: (iconDelegate.modelData && iconDelegate.modelData.isActive) ? Services.Theme.accent : Services.Theme.textPrimary
                            font.pixelSize: Math.round(root.iconSize * 0.45)
                            font.bold: true
                        }
                    }

                    // Real Application Icon Image
                    Image {
                        id: appImg
                        anchors.fill: parent
                        source: {
                            const rawApp = (iconDelegate.modelData && iconDelegate.modelData.app) ? iconDelegate.modelData.app : iconDelegate.modelData
                            const rawIcon = rawApp ? (typeof rawApp.icon === "string" ? rawApp.icon : (rawApp.icon?.name || (typeof iconDelegate.modelData.icon === "string" ? iconDelegate.modelData.icon : ""))) : ""
                            if (!rawIcon) return ""
                            if (Services.SystemTheme) {
                                const res = Services.SystemTheme.getIcon(rawIcon)
                                if (res && res.length > 0) return res
                            }
                            if (rawIcon.startsWith("file://") || rawIcon.startsWith("http://") || rawIcon.startsWith("https://")) return rawIcon
                            if (rawIcon.startsWith("/")) return "file://" + rawIcon
                            let s = rawIcon.startsWith("image://icon/") ? rawIcon.substring(13) : rawIcon
                            if (s.startsWith("image://")) return s
                            const qp = Quickshell.iconPath(s, true)
                            return (qp && qp.startsWith("/")) ? ("file://" + qp) : (qp || "")
                        }
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: true
                        sourceSize: Qt.size(128, 128)
                        mipmap: true
                        smooth: true
                        visible: appImg.status === Image.Ready && appImg.source.toString().length > 0
                    }

                    // Multiple Windows Count Badge
                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: -2
                        anchors.rightMargin: -2
                        visible: root.showWindowCount && Boolean(iconDelegate.modelData && iconDelegate.modelData.windowCount > 1)
                        width: Math.max(16, countText.implicitWidth + 6)
                        height: 16
                        radius: 8
                        color: Services.Theme.accent
                        border.color: Services.Theme.bgDeep
                        border.width: 1.5

                        Text {
                            id: countText
                            anchors.centerIn: parent
                            text: iconDelegate.modelData ? String(iconDelegate.modelData.windowCount) : ""
                            font.pixelSize: 9
                            font.bold: true
                            color: Services.Theme.bgOnAccent
                        }
                    }
                }

                // ── Running Application Indicator (Stationary & Calmed) ──────
                Rectangle {
                    id: runIndicator
                    readonly property bool isActiveApp: Boolean(iconDelegate.modelData && iconDelegate.modelData.isActive)
                    readonly property string style: root.indicatorStyle
                    z: 15

                    anchors.horizontalCenter: root.isBottom ? parent.horizontalCenter : undefined
                    anchors.verticalCenter: root.isVertical ? parent.verticalCenter : undefined
                    anchors.alignWhenCentered: false
                    anchors.bottom: root.isBottom ? parent.bottom : undefined
                    anchors.left: root.isLeft ? parent.left : undefined
                    anchors.right: root.isRight ? parent.right : undefined
                    anchors.bottomMargin: root.isBottom ? -4 : 0
                    anchors.leftMargin: root.isLeft ? -4 : 0
                    anchors.rightMargin: root.isRight ? -4 : 0

                    visible: root.showIndicators && Boolean(iconDelegate.modelData && iconDelegate.modelData.isRunning) && !iconDelegate.isDraggingThis

                    // Dynamic width based on style & orientation
                    width: {
                        if (root.isVertical) {
                            if (style === "line") return 3
                            if (style === "pill") return 4
                            if (style === "glow") return 4
                            return isActiveApp ? 6 : 4 // "dot"
                        } else {
                            if (style === "line") return isActiveApp ? 18 : 10
                            if (style === "pill") return isActiveApp ? 12 : 7
                            if (style === "glow") return isActiveApp ? 20 : 12
                            return isActiveApp ? 6 : 4 // "dot"
                        }
                    }

                    // Dynamic height based on style & orientation
                    height: {
                        if (root.isVertical) {
                            if (style === "line") return isActiveApp ? 18 : 10
                            if (style === "pill") return isActiveApp ? 12 : 7
                            if (style === "glow") return isActiveApp ? 20 : 12
                            return isActiveApp ? 6 : 4 // "dot"
                        } else {
                            if (style === "line") return 3
                            if (style === "pill") return 4
                            if (style === "glow") return 4
                            return isActiveApp ? 6 : 4 // "dot"
                        }
                    }

                    radius: {
                        if (style === "dot") return Math.min(width, height) / 2
                        if (style === "line") return 1.5
                        if (style === "pill") return 2
                        return 2 // "glow"
                    }

                    color: isActiveApp ? Services.Theme.accent : Services.Theme.textDisabled
                    opacity: isActiveApp ? 1.0 : (style === "glow" ? 0.6 : 0.75)

                    Behavior on width { NumberAnimation { duration: 150 } }
                    Behavior on height { NumberAnimation { duration: 150 } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    // Soft halo glow behind active indicator
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + (runIndicator.style === "glow" ? 8 : 6)
                        height: parent.height + (runIndicator.style === "glow" ? 6 : 6)
                        radius: parent.radius + 2
                        visible: runIndicator.isActiveApp
                        color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, runIndicator.style === "glow" ? 0.5 : 0.35)
                        z: -1
                    }
                }

                // ── Tooltip Floating Beside / Above Icon ─────────────────────
                Rectangle {
                    id: tooltip
                    anchors.bottom: root.isBottom ? parent.top : undefined
                    anchors.left: root.isLeft ? parent.right : undefined
                    anchors.right: root.isRight ? parent.left : undefined
                    anchors.bottomMargin: root.isBottom ? (Math.round((iconDelegate.visualScale - 1.0) * root.iconSize) + 12) : 0
                    anchors.leftMargin: root.isLeft ? (Math.round((iconDelegate.visualScale - 1.0) * root.iconSize) + 12) : 0
                    anchors.rightMargin: root.isRight ? (Math.round((iconDelegate.visualScale - 1.0) * root.iconSize) + 12) : 0
                    anchors.horizontalCenter: root.isBottom ? parent.horizontalCenter : undefined
                    anchors.verticalCenter: root.isVertical ? parent.verticalCenter : undefined

                    z: 999
                    readonly property bool shouldShow: root.showTooltips && iconDelegate.isDirectlyHovered && !root.isDraggingPinned
                    visible: opacity > 0.01
                    opacity: shouldShow ? 1 : 0
                    scale: shouldShow ? 1 : 0.92
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                    implicitWidth: tooltipText.implicitWidth + 16
                    implicitHeight: tooltipText.implicitHeight + 8
                    radius: 8
                    color: Services.Theme.bgElevated
                    border.color: Services.Theme.borderHighlight
                    border.width: 1

                    Text {
                        id: tooltipText
                        anchors.centerIn: parent
                        text: (iconDelegate.modelData ? iconDelegate.modelData.name : "") + ((iconDelegate.modelData && iconDelegate.modelData.windowCount > 1) ? " (" + iconDelegate.modelData.windowCount + ")" : "")
                        font.pixelSize: Services.Theme.fontSizeSm
                        font.weight: Font.Medium
                        color: Services.Theme.textPrimary
                    }
                }

                // ── Click & Drag MouseArea ──────────────────────────────────
                // Covers the full delegate plus upward headroom for lifted icons
                MouseArea {
                    id: clickArea
                    anchors.fill: parent
                    anchors.topMargin: root.isBottom ? -6 : 0
                    anchors.bottomMargin: root.isBottom ? -root.edgeMargin : 0
                    anchors.leftMargin: root.isRight ? -6 : 0
                    anchors.rightMargin: root.isLeft ? -6 : 0
                    hoverEnabled: false
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: iconDelegate.isDraggingThis ? Qt.ClosedHandCursor : Qt.PointingHandCursor

                    onPressed: (mouse) => {
                        if (mouse.button === Qt.LeftButton) {
                            iconDelegate.pressStartX = mouse.x
                            iconDelegate.pressStartY = mouse.y
                            iconDelegate.wasDragged = false
                            iconDelegate.dragOffsetX = 0
                            iconDelegate.dragOffsetY = 0
                        }
                    }

                    onPositionChanged: (mouse) => {
                        if (mouse.buttons & Qt.LeftButton) {
                            const dx = mouse.x - iconDelegate.pressStartX
                            const dy = mouse.y - iconDelegate.pressStartY
                            const dist = Math.hypot(dx, dy)

                            if (!iconDelegate.isDraggingThis && iconDelegate.isPinnedItem && dist > 8) {
                                iconDelegate.wasDragged = true
                                root.startPinnedDrag(iconDelegate.index)
                            }

                            if (iconDelegate.isDraggingThis) {
                                iconDelegate.dragOffsetX = dx
                                iconDelegate.dragOffsetY = dy

                                const posInLayout = iconDelegate.mapToItem(itemsLayout, mouse.x, mouse.y)
                                const coord = root.isVertical ? posInLayout.y : posInLayout.x
                                const newTarget = root.getClosestPinnedSlot(coord)
                                root.updatePinnedDrag(newTarget)
                            }
                        }
                    }

                    onReleased: (mouse) => {
                        if (mouse.button === Qt.LeftButton) {
                            if (iconDelegate.isDraggingThis) {
                                iconDelegate.dragOffsetX = 0
                                iconDelegate.dragOffsetY = 0
                                root.finishPinnedDrag()
                                return
                            }
                        }
                    }

                    onCanceled: () => {
                        if (iconDelegate.isDraggingThis) {
                            iconDelegate.dragOffsetX = 0
                            iconDelegate.dragOffsetY = 0
                            root.cancelPinnedDrag()
                        }
                    }

                    onClicked: (mouse) => {
                        if (iconDelegate.wasDragged) {
                            iconDelegate.wasDragged = false
                            return
                        }
                        if (mouse.button === Qt.RightButton) {
                            if (Services.DockService) {
                                const iconScreenX = dockContainer.x + itemsLayout.x + iconDelegate.x + iconDelegate.width / 2
                                const iconScreenY = dockContainer.y + itemsLayout.y + iconDelegate.y + iconDelegate.height / 2
                                Services.DockService.openMenu(iconDelegate.modelData, iconScreenX, iconScreenY)
                            }
                        } else {
                            if (root.bounceOnClick) {
                                if (iconDelegate.modelData && !iconDelegate.modelData.isRunning) {
                                    iconDelegate.startLaunching()
                                } else {
                                    clickBounce.restart()
                                }
                            }
                            if (Services.DockService) {
                                Services.DockService.closeMenu()
                                Services.DockService.focusApp(iconDelegate.modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
