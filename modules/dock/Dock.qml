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

    // qmllint disable uncreatable-type
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
        readonly property int dockBarHeight: iconSize + 24
        // Extra headroom for icon lift, shadow, and tooltips
        readonly property int windowHeadroom: 64
        readonly property int windowBreadth: dockBarHeight + windowHeadroom
        readonly property real dockExitOffset: dockBarHeight + edgeMargin + 50

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
        WlrLayershell.namespace: "quickshell:dock" // Hyprland layer rule: blur + ignore_alpha
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
                let d = Math.abs(coord - center)
                if (k === targetDropIndex) {
                    d -= 12
                }
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
                x: root.isRight
                    ? Math.max(0, dockContainer.x - (root.isDraggingPinned ? 120 : (root.isHovered ? 6 : 0)))
                    : (root.isLeft ? 0 : Math.max(0, dockContainer.x - (root.isDraggingPinned ? 60 : 0)))
                y: root.isBottom
                    ? Math.max(0, dockContainer.y - (root.isDraggingPinned ? 120 : (root.isHovered ? 6 : 0)))
                    : (root.isVertical ? Math.max(0, dockContainer.y - (root.isDraggingPinned ? 60 : 0)) : dockContainer.y)
                width: root.isVertical
                    ? (dockContainer.width + (root.isDraggingPinned ? 120 : (root.isHovered ? 6 : 0)))
                    : (dockContainer.width + (root.isDraggingPinned ? 120 : 0))
                height: root.isBottom
                    ? (dockContainer.height + root.edgeMargin + (root.isDraggingPinned ? 120 : (root.isHovered ? 6 : 0)))
                    : ((root.isVertical && (root.isHovered || root.isDraggingPinned)) ? (dockContainer.height + 6) : dockContainer.height)
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
                if (!root.isDraggingPinned && !hoverEdgeDetector.containsMouse && !dockTracker.containsMouse) {
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

        readonly property bool isDockHiddenForLock: Boolean(
            Services.OverlayManager && (Services.OverlayManager.isLocked || Services.OverlayManager.isLockAbsorbing)
        )

        // ── macOS Glass Material Tokens ──────────────────────────────────────
        // Fills are intentionally low-alpha: the compositor blur does the heavy lifting.
        // Tint is neutral grey/white (macOS), not blue. Tune alpha by eye per wallpaper.
        readonly property bool dark: Services.Theme.isDark
        readonly property color glassFill: dark ? Qt.rgba(0.11, 0.11, 0.12, 0.38) : Qt.rgba(1, 1, 1, 0.30)
        readonly property color glassBorder: dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.50)
        readonly property color glassSpecular: dark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.65)
        readonly property color glassDot: dark ? Qt.rgba(1, 1, 1, 0.78) : Qt.rgba(0, 0, 0, 0.60)
        readonly property color tooltipFill: dark ? Qt.rgba(0.14, 0.14, 0.15, 0.62) : Qt.rgba(1, 1, 1, 0.70)
        readonly property color tooltipBorder: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.10)
        readonly property color tooltipText: dark ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(0, 0, 0, 0.85)

        // ── Launch Bounce: per-app memory + personality ──────────────────────
        // launchStats remembers how long each app took to open (EMA, this session),
        // so the bounce tempo follows how fast/slow that app really is.
        property var launchStats: ({})

        // Pending launches live HERE (appKey -> click timestamp), not on the delegate or on
        // modelData: delegates get recreated when the dock model refreshes, and
        // modelData.isLaunching can go stale. Both used to silently kill the bounce.
        property var launchingSince: ({})

        // Set true, then watch `qs log` for "[dock-bounce]" lines to see what is happening.
        readonly property bool debugBounce: false

        // The launch bounce is the only "I'm opening it" feedback, so it ignores
        // Services.Performance.decorativeMotion unless you flip this to true.
        readonly property bool respectReducedMotion: false
        function dbg(msg) {
            if (debugBounce) console.log("[dock-bounce] " + msg)
        }

        function markLaunching(key) {
            if (launchingSince[key] !== undefined) return
            const c = Object.assign({}, launchingSince)
            c[key] = Date.now()
            launchingSince = c
            dbg("launch start: " + key)
        }
        function finishLaunch(key, opened) {
            const since = launchingSince[key]
            if (since === undefined) return
            const c = Object.assign({}, launchingSince)
            delete c[key]
            launchingSince = c
            const elapsed = Date.now() - since
            dbg("launch end: " + key + " opened=" + opened + " after " + elapsed + "ms")
            // only learn from real launches (ignore timeouts / instant flips)
            if (opened && elapsed > 80 && elapsed < 9500) recordLaunch(key, elapsed)
        }

        function launchEstimate(key) {
            const v = launchStats[key]
            return v !== undefined ? v : 900   // unknown app: assume "medium"
        }
        function recordLaunch(key, ms) {
            const prev = launchStats[key]
            const copy = Object.assign({}, launchStats)
            copy[key] = prev === undefined ? ms : Math.round(prev * 0.5 + ms * 0.5)
            launchStats = copy
        }

        // Small seeded PRNG so every app gets a stable, distinct "character"
        function seededRandom(seed) {
            let a = seed >>> 0
            return function() {
                a = (a + 0x6D2B79F5) >>> 0
                let t = a
                t = Math.imul(t ^ (t >>> 15), t | 1)
                t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
                return ((t ^ (t >>> 14)) >>> 0) / 4294967296
            }
        }
        function makePersona(key) {
            let h = 2166136261
            for (let i = 0; i < key.length; i++) {
                h ^= key.charCodeAt(i)
                h = Math.imul(h, 16777619)
            }
            const r = seededRandom(h)
            return {
                heightScale: 0.80 + r() * 0.45,          // how high it hops
                periodScale: 0.88 + r() * 0.28,          // how fast it hops
                skew: 0.80 + r() * 0.45,                 // when the apex happens (floaty vs snappy)
                cushion: 0.08 + r() * 0.10,              // fraction of a hop spent squashing on landing
                cushionDepth: 1.5 + r() * 3.0,           // px of landing squash
                burst: 1 + Math.floor(r() * 3),          // 1-3 hops, then a breath
                pause: r() * 0.45,                       // breath length (fraction of a hop)
                settle: r() > 0.4,                       // small final hop after the app opens
                jitter: 0.04 + r() * 0.06                // per-hop randomness
            }
        }

        // ── Main Dock Container (Liquid Glass Floating Pill) ─────────────────
        Rectangle {
            id: dockContainer
            opacity: (Services.OverlayManager && Services.OverlayManager.isWizardActive) ? 0.0 : (root.isDockHiddenForLock ? 0.0 : 1.0)
            Behavior on opacity {
                NumberAnimation {
                    duration: root.isDockHiddenForLock ? 220 : 380
                    easing.type: Easing.OutCubic
                }
            }

            transform: Translate {
                y: root.isDockHiddenForLock
                    ? (root.isBottom ? root.dockExitOffset : -root.dockExitOffset)
                    : 0
                x: root.isDockHiddenForLock
                    ? (root.isLeft ? -root.dockExitOffset : (root.isRight ? root.dockExitOffset : 0))
                    : 0

                Behavior on y {
                    NumberAnimation {
                        duration: root.isDockHiddenForLock ? 240 : 480
                        easing.type: root.isDockHiddenForLock ? Easing.InCubic : Easing.OutBack
                        easing.overshoot: root.isDockHiddenForLock ? 0.0 : 1.15
                    }
                }
                Behavior on x {
                    NumberAnimation {
                        duration: root.isDockHiddenForLock ? 240 : 480
                        easing.type: root.isDockHiddenForLock ? Easing.InCubic : Easing.OutBack
                        easing.overshoot: root.isDockHiddenForLock ? 0.0 : 1.15
                    }
                }
            }

            // Center positioning on screen
            x: {
                if (root.isBottom) {
                    return Math.round((parent.width - width) / 2)
                } else if (root.isLeft) {
                    return !root.autoHide ? root.edgeMargin : ((root.isHovered || root.isDraggingPinned) ? root.edgeMargin : (-width + 4))
                } else {
                    return !root.autoHide ? (parent.width - width - root.edgeMargin) : ((root.isHovered || root.isDraggingPinned) ? (parent.width - width - root.edgeMargin) : (parent.width - 4))
                }
            }

            y: {
                if (root.isBottom) {
                    return !root.autoHide ? (parent.height - height - root.edgeMargin) : ((root.isHovered || root.isDraggingPinned) ? (parent.height - height - root.edgeMargin) : (parent.height - 4))
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

            // macOS Dock material: neutral translucent fill. The backdrop blur itself
            // comes from the compositor (layer rule on "quickshell:dock").
            color: root.glassFill
            border.color: root.glassBorder
            border.width: 1

            // ── Unified Dock Tracker MouseArea ───────────────────────────────
            // Strictly 0 margins when idle so hover only triggers when cursor physically touches the dock pill.
            // When already hovered, expands slightly upward so cursor can hover lifted icons.
            MouseArea {
                id: dockTracker
                anchors.fill: parent
                anchors.topMargin: (root.isBottom && (root.isHovered || root.isDraggingPinned)) ? (root.isDraggingPinned ? -120 : -6) : 0
                anchors.bottomMargin: root.isBottom ? -root.edgeMargin : 0
                anchors.leftMargin: (root.isRight && (root.isHovered || root.isDraggingPinned)) ? (root.isDraggingPinned ? -120 : -6) : 0
                anchors.rightMargin: (root.isLeft && (root.isHovered || root.isDraggingPinned)) ? (root.isDraggingPinned ? -120 : -6) : 0
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                cursorShape: root.isDraggingPinned ? Qt.ClosedHandCursor : Qt.PointingHandCursor
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
                    if (root.isDraggingPinned) return
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
                z: 1
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
                        color: root.dark ? Qt.rgba(1, 1, 1, 0.24) : Qt.rgba(0, 0, 0, 0.20)
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

                readonly property real slotShift: root.iconSize + root.itemSpacing
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
                // Level-triggered: the delegate always reconciles itself against
                // root.launchingSince, so a missed signal, a recreated delegate or a stale
                // modelData flag can no longer leave the bounce stuck "off".
                readonly property bool keyed: root.launchingSince[appKey] !== undefined
                readonly property bool isLaunching: keyed
                readonly property bool runningNow: Boolean(modelData && (modelData.isRunning || modelData.windowCount > 0))

                onKeyedChanged: reconcile()
                onRunningNowChanged: reconcile()
                Component.onCompleted: reconcile()

                function startLaunching() {
                    root.markLaunching(appKey)
                    if (modelData) modelData.isLaunching = true   // keep other consumers (launcher etc.) informed
                    reconcile()
                }

                function reconcile() {
                    // 1. A pending launch ends when the app shows up, or after 10s at most
                    const since = root.launchingSince[appKey]
                    if (since !== undefined) {
                        if (runningNow) root.finishLaunch(appKey, true)
                        else if (Date.now() - since > 10000) root.finishLaunch(appKey, false)
                    }
                    const want = root.launchingSince[appKey] !== undefined

                    // 2. Bring the bounce in line with that state
                    if (want && !launchActive) beginLaunchBounce()
                    else if (!want && launchActive) endLaunchBounce()

                    // 3. Never leave a stale "launching" flag on the model
                    if (!want && modelData && modelData.isLaunching) modelData.isLaunching = false

                    // 4. Engine liveness: revive a stalled engine, reset a stuck hop
                    if (bounceState !== "idle") {
                        if (stateT > 5) {
                            root.dbg("stuck hop reset: " + appKey)
                            stopEngine()
                        } else if (!bounceEngine.running && motionAllowed) {
                            root.dbg("engine revived: " + appKey)
                            bounceEngine.running = true
                        }
                    }
                }

                // Self-heal tick while anything bounce-related is pending or in flight
                Timer {
                    interval: 250
                    repeat: true
                    running: iconDelegate.keyed || iconDelegate.launchActive || iconDelegate.bounceState !== "idle"
                    onTriggered: iconDelegate.reconcile()
                }

                // Launches started elsewhere (app launcher etc.) flip modelData.isLaunching
                Connections {
                    target: iconDelegate.modelData || null
                    function onIsLaunchingChanged() {
                        if (!iconDelegate.modelData) return
                        if (iconDelegate.modelData.isLaunching) {
                            root.markLaunching(iconDelegate.appKey)
                        } else if (iconDelegate.keyed) {
                            root.finishLaunch(iconDelegate.appKey, iconDelegate.runningNow)
                        }
                    }
                }

                // ── Launch / Click Bounce Engine ─────────────────────────────
                // A frame-driven hop simulation instead of fixed keyframes:
                //  - tempo follows how long this app usually takes to open (root.launchStats)
                //  - every app has its own hop height / timing / rhythm (root.makePersona)
                //  - each hop gets a little random jitter so it never looks mechanical
                //  - it always plays at least minHops, and finishes the current hop
                //    gracefully when the app opens (no abrupt cut)
                readonly property string appKey: modelData ? String(modelData.desktopId || modelData.name || ("slot" + index)) : ("slot" + index)
                readonly property var persona: root.makePersona(appKey)
                readonly property real liftDir: root.isBottom ? -1 : (root.isLeft ? 1 : -1)
                readonly property real peakBase: Math.min(root.iconSize * 0.42, 26)
                readonly property bool motionAllowed: !root.respectReducedMotion || (Services.Performance ? Services.Performance.decorativeMotion : true)

                property real bounceOffset: 0          // px along the lift axis (sign already applied)
                property string bounceState: "idle"    // "idle" | "hop" | "pause"
                property real stateT: 0
                property real hopDur: 0.4
                property real hopH: 20
                property real pauseDur: 0
                property real basePeriod: 0.4
                property real ampMul: 1.0
                property int hopsDone: 0
                property int burstPos: 0
                property int minHops: 2
                property bool launchActive: false
                property bool settleQueued: false

                // Height above rest (px, positive = away from the dock edge) at hop progress u in [0,1]
                function hopLift(u) {
                    const air = 1 - persona.cushion
                    if (u < air) {
                        const v = Math.pow(u / air, persona.skew)
                        return hopH * 4 * v * (1 - v)
                    }
                    const w = (u - air) / persona.cushion
                    return -persona.cushionDepth * Math.sin(Math.PI * w)
                }

                function beginHop() {
                    const p = persona
                    const j = 1 + (Math.random() * 2 - 1) * p.jitter
                    hopDur = Math.max(0.18, basePeriod * p.periodScale * j)
                    hopH = Math.min(30, peakBase * p.heightScale * ampMul * (1 + (Math.random() * 2 - 1) * p.jitter * 1.5))
                    bounceState = "hop"
                    stateT = 0
                }

                function runEngine() {
                    if (!motionAllowed) {
                        root.dbg("blocked by Services.Performance.decorativeMotion=false")
                        bounceState = "idle"
                        bounceOffset = 0
                        return
                    }
                    bounceEngine.running = true
                }

                function stopEngine() {
                    bounceEngine.running = false
                    bounceState = "idle"
                    bounceOffset = 0
                }

                // Decide what follows a finished hop / pause
                function advance() {
                    if (launchActive || hopsDone < minHops) {
                        beginHop()
                    } else if (settleQueued) {
                        settleQueued = false
                        ampMul = 0.35
                        beginHop()
                    } else {
                        stopEngine()
                    }
                }

                function endHop() {
                    hopsDone++
                    burstPos++
                    bounceOffset = 0
                    if ((launchActive || hopsDone < minHops) && burstPos >= persona.burst) {
                        burstPos = 0
                        bounceState = "pause"
                        stateT = 0
                        pauseDur = hopDur * persona.pause * (0.8 + Math.random() * 0.4)
                    } else {
                        advance()
                    }
                }

                function stepBounce(dt) {
                    if (!(dt > 0)) dt = 0.016          // guard against NaN / 0 frame time
                    if (!isFinite(bounceOffset)) bounceOffset = 0
                    if (bounceState === "hop") {
                        stateT += dt
                        const u = Math.min(1, stateT / hopDur)
                        bounceOffset = liftDir * hopLift(u)
                        if (u >= 1) endHop()
                    } else if (bounceState === "pause") {
                        stateT += dt
                        if (stateT >= pauseDur) advance()
                    } else {
                        bounceEngine.running = false
                    }
                }

                function beginLaunchBounce() {
                    if (launchActive) return
                    launchActive = true
                    const est = root.launchEstimate(appKey)
                    root.dbg("bounce begin: " + appKey + " est=" + est + "ms motionAllowed=" + motionAllowed)
                    // fast app -> brisk 0.30s hops, slow app -> relaxed 0.52s hops
                    basePeriod = 0.30 + 0.22 * Math.max(0, Math.min(1, (est - 250) / 1750))
                    ampMul = 1.0
                    hopsDone = 0
                    burstPos = 0
                    minHops = 2
                    settleQueued = persona.settle
                    if (bounceState === "idle") {
                        beginHop()
                        runEngine()
                    }
                }

                function endLaunchBounce() {
                    if (!launchActive) return
                    launchActive = false
                    root.dbg("bounce end: " + appKey)
                }

                // Small hop for clicking an app that is already running
                function bounceOnce() {
                    if (launchActive) return
                    if (bounceState !== "idle" && bounceEngine.running) return   // a hop is already in flight
                    basePeriod = 0.28
                    ampMul = 0.70
                    hopsDone = 0
                    burstPos = 0
                    minHops = 1
                    settleQueued = false
                    beginHop()
                    runEngine()
                }

                FrameAnimation {
                    id: bounceEngine
                    running: false
                    onTriggered: iconDelegate.stepBounce(Math.min(0.05, frameTime))
                }

                // ── Hover Detection for Tooltip ──────────────────────────────
                readonly property bool isDirectlyHovered: root.isHovered && (distToMouse < (root.iconSize * 0.48))

                // ── Visual Icon Item (macOS Shelf-Anchored Lift) ─────────────
                Item {
                    id: iconVisual
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.alignWhenCentered: false
                    anchors.bottom: root.isBottom ? undefined : parent.bottom
                    anchors.bottomMargin: 0
                    anchors.left: root.isLeft ? parent.left : undefined
                    anchors.leftMargin: root.isLeft ? (4 + Math.round((iconDelegate.visualScale - 1.0) * 8)) : 0
                    anchors.right: root.isRight ? parent.right : undefined
                    anchors.rightMargin: root.isRight ? (4 + Math.round((iconDelegate.visualScale - 1.0) * 8)) : 0
                    anchors.verticalCenter: root.isBottom || root.isVertical ? parent.verticalCenter : undefined
                    anchors.verticalCenterOffset: -2

                    width: root.iconSize
                    height: root.iconSize
                    scale: iconDelegate.isDraggingThis ? (iconDelegate.visualScale * 1.08) : iconDelegate.visualScale
                    opacity: iconDelegate.isDraggingThis ? 0.88 : 1.0
                    transformOrigin: root.isBottom ? Item.Bottom : (root.isLeft ? Item.Left : (root.isRight ? Item.Right : Item.Center))

                    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

                    transform: [
                        Translate {
                            id: bounceTranslate
                            x: root.isVertical ? iconDelegate.bounceOffset : 0
                            y: root.isVertical ? 0 : iconDelegate.bounceOffset
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

                    // Fallback Badge (Letter)
                    Rectangle {
                        anchors.fill: parent
                        radius: Math.round(root.iconSize * 0.24)
                        color: root.dark
                            ? Qt.rgba(1, 1, 1, iconDelegate.isDirectlyHovered ? 0.20 : 0.12)
                            : Qt.rgba(0, 0, 0, iconDelegate.isDirectlyHovered ? 0.14 : 0.08)
                        border.color: Qt.rgba(1, 1, 1, root.dark ? 0.14 : 0.40)
                        border.width: 1
                        visible: !appImg.source || appImg.status !== Image.Ready || !appImg.visible

                        Text {
                            anchors.centerIn: parent
                            text: (iconDelegate.modelData ? (iconDelegate.modelData.name || "?") : "?").charAt(0).toUpperCase()
                            color: root.tooltipText
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
                    anchors.top: root.isBottom ? iconVisual.bottom : undefined
                    anchors.left: root.isLeft ? parent.left : undefined
                    anchors.right: root.isRight ? parent.right : undefined
                    anchors.topMargin: root.isBottom ? 2 : 0
                    anchors.leftMargin: root.isLeft ? -4 : 0
                    anchors.rightMargin: root.isRight ? -4 : 0

                    visible: root.showIndicators && Boolean(iconDelegate.modelData && iconDelegate.modelData.isRunning) && !iconDelegate.isDraggingThis

                    // Dynamic width based on style & orientation
                    width: {
                        if (root.isVertical) {
                            if (style === "line") return 3
                            if (style === "pill") return 4
                            if (style === "glow") return 4
                            return isActiveApp ? 5 : 4 // "dot"
                        } else {
                            if (style === "line") return isActiveApp ? 18 : 10
                            if (style === "pill") return isActiveApp ? 12 : 7
                            if (style === "glow") return isActiveApp ? 20 : 12
                            return isActiveApp ? 5 : 4 // "dot"
                        }
                    }

                    // Dynamic height based on style & orientation
                    height: {
                        if (root.isVertical) {
                            if (style === "line") return isActiveApp ? 18 : 10
                            if (style === "pill") return isActiveApp ? 12 : 7
                            if (style === "glow") return isActiveApp ? 20 : 12
                            return isActiveApp ? 5 : 4 // "dot"
                        } else {
                            if (style === "line") return 3
                            if (style === "pill") return 4
                            if (style === "glow") return 4
                            return isActiveApp ? 5 : 4 // "dot"
                        }
                    }

                    radius: {
                        if (style === "dot") return Math.min(width, height) / 2
                        if (style === "line") return 1.5
                        if (style === "pill") return 2
                        return 2 // "glow"
                    }

                    // macOS: neutral dot, same for every running app (no accent, no halo)
                    color: root.glassDot
                    opacity: 1.0

                    Behavior on width { NumberAnimation { duration: 150 } }
                    Behavior on height { NumberAnimation { duration: 150 } }
                    Behavior on color { ColorAnimation { duration: 150 } }
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
                    radius: 7
                    color: root.tooltipFill
                    border.color: root.tooltipBorder
                    border.width: 1

                    Text {
                        id: tooltipText
                        anchors.centerIn: parent
                        text: (iconDelegate.modelData ? iconDelegate.modelData.name : "") + ((iconDelegate.modelData && iconDelegate.modelData.windowCount > 1) ? " (" + iconDelegate.modelData.windowCount + ")" : "")
                        font.pixelSize: Services.Theme.fontSizeSm
                        font.weight: Font.Medium
                        color: root.tooltipText
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
                                iconDelegate.pressStartX = mouse.x
                                iconDelegate.pressStartY = mouse.y
                                root.startPinnedDrag(iconDelegate.index)
                            }

                            if (iconDelegate.isDraggingThis) {
                                iconDelegate.dragOffsetX = mouse.x - iconDelegate.pressStartX
                                iconDelegate.dragOffsetY = mouse.y - iconDelegate.pressStartY

                                const posInDock = iconDelegate.mapToItem(dockTracker, mouse.x, mouse.y)
                                dockTracker.updateMouse(posInDock.x, posInDock.y)

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
                                root.finishPinnedDrag()
                                iconDelegate.dragOffsetX = 0
                                iconDelegate.dragOffsetY = 0
                                return
                            }
                        }
                    }

                    onCanceled: () => {
                        if (iconDelegate.isDraggingThis) {
                            root.cancelPinnedDrag()
                            iconDelegate.dragOffsetX = 0
                            iconDelegate.dragOffsetY = 0
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
                            root.dbg("click " + iconDelegate.appKey
                                + " bounceOnClick=" + root.bounceOnClick
                                + " isRunning=" + (iconDelegate.modelData ? iconDelegate.modelData.isRunning : "n/a")
                                + " windowCount=" + (iconDelegate.modelData ? iconDelegate.modelData.windowCount : "n/a")
                                + " motionAllowed=" + iconDelegate.motionAllowed)
                            if (root.bounceOnClick) {
                                if (iconDelegate.modelData && !iconDelegate.modelData.isRunning) {
                                    iconDelegate.startLaunching()
                                } else {
                                    iconDelegate.bounceOnce()
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
