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
        // Smoothly blooms on enter (140ms), velvety & calm dissolve on exit (380ms OutQuad).
        // 1:1 instantaneous zero-latency tracking while moving inside the dock.
        property real hoverProgress: (root.magnification && root.isHovered) ? 1.0 : 0.0
        Behavior on hoverProgress {
            NumberAnimation {
                duration: root.isHovered ? 140 : 380
                easing.type: root.isHovered ? Easing.OutCubic : Easing.OutQuad
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

        readonly property real nominalStartCoord: root.isVertical
            ? ((root.height - totalNominalLength) / 2)
            : ((root.width - totalNominalLength) / 2)

        // ── Exact Harmonic Expansion Constant ────────────────────────────────
        // Sum of cos^2 envelope across all icons is mathematically 2.0.
        // Therefore total dock pill expansion is strictly invariant during horizontal travel.
        readonly property real maxWaveExpansion: (root.iconSize * (root.maxScale - 1.0) * 2.0)

        readonly property real stableDockWidth: root.isVertical
            ? root.dockBarHeight
            : (totalNominalLength + 16 + (maxWaveExpansion * root.hoverProgress))

        readonly property real stableDockHeight: root.isVertical
            ? (totalNominalLength + 16 + (maxWaveExpansion * root.hoverProgress))
            : root.dockBarHeight

        function getNominalCenter(isPinnedGroup, index) {
            if (isPinnedGroup) {
                return nominalStartCoord + (index * (root.iconSize + itemSpacing)) + (root.iconSize / 2)
            } else {
                return nominalStartCoord + (pinnedCount * (root.iconSize + itemSpacing)) + (hasSeparator ? (separatorNominalSize + itemSpacing) : 0) + (index * (root.iconSize + itemSpacing)) + (root.iconSize / 2)
            }
        }

        // ── Single Dock Mouse Coordinate Tracker ─────────────────────────────
        readonly property real mouseScreenCoord: (root.isHovered && dockTracker.containsMouse) ? dockTracker.currentMouseCoord : dockTracker.lastValidMouseCoord

        // ── 2D Approach Ramp Calculation ─────────────────────────────────────
        function calcApproachRamp(cross) {
            if (cross === -99999) return 1.0
            const rampDist = 32.0
            if (root.isBottom) {
                if (cross >= rampDist) return 1.0
                if (cross <= 0) return 0.0
                const norm = (rampDist - cross) / rampDist
                const c = Math.cos(norm * (Math.PI / 2))
                return c * c
            } else if (root.isRight) {
                if (cross >= rampDist) return 1.0
                if (cross <= 0) return 0.0
                const norm = (rampDist - cross) / rampDist
                const c = Math.cos(norm * (Math.PI / 2))
                return c * c
            } else if (root.isLeft) {
                const rightEdge = dockTracker.width
                const distFromRight = rightEdge - cross
                if (distFromRight >= rampDist) return 1.0
                if (distFromRight <= 0) return 0.0
                const norm = (rampDist - distFromRight) / rampDist
                const c = Math.cos(norm * (Math.PI / 2))
                return c * c
            }
            return 1.0
        }

        readonly property real approachRamp: {
            if (!root.isHovered || !dockTracker.containsMouse) return dockTracker.lastApproachRamp
            return calcApproachRamp(dockTracker.currentMouseCrossCoord)
        }

        // ── Masking (Wayland Input Region) ───────────────────────────────────
        mask: Region {
            // Active Dock Region: Generous coverage for lifted icons and tooltips
            Region {
                x: root.isVertical ? (root.isRight ? Math.max(0, dockContainer.x - 24) : 0) : Math.max(0, dockContainer.x - 16)
                y: root.isVertical ? Math.max(0, dockContainer.y - 16) : (root.isBottom ? Math.max(0, dockContainer.y - 56) : 0)
                width: root.isVertical ? (dockContainer.width + 28) : (dockContainer.width + 32)
                height: root.isVertical ? (dockContainer.height + 32) : (dockContainer.height + 64)
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

            // Dynamic Dimensions: fits content + generous padding (stationary during hover)
            height: Math.round(root.stableDockHeight)
            width: Math.round(root.stableDockWidth)
            radius: Math.min(22, Math.round(root.dockBarHeight * 0.35))

            // macOS Liquid Glass Styling
            color: Services.Theme.isDark ? Qt.rgba(0.08, 0.08, 0.12, 0.84) : Qt.rgba(0.96, 0.96, 0.98, 0.90)
            border.color: Services.Theme.isDark ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.10)
            border.width: 1

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
            // Covers the dock container plus smooth 22px approach zone.
            // Doesn't consume clicks (acceptedButtons: Qt.NoButton).
            MouseArea {
                id: dockTracker
                anchors.fill: parent
                anchors.topMargin: root.isBottom ? -32 : -8
                anchors.bottomMargin: root.isBottom ? 0 : -8
                anchors.leftMargin: root.isRight ? -22 : -12
                anchors.rightMargin: root.isLeft ? -22 : -12
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                cursorShape: Qt.PointingHandCursor
                z: 100

                property real currentMouseCoord: -99999
                property real currentMouseCrossCoord: -99999
                property real lastValidMouseCoord: root.width / 2
                property real lastApproachRamp: 1.0

                onPositionChanged: (mouse) => {
                    if (root.isVertical) {
                        currentMouseCoord = dockContainer.y + dockTracker.y + mouse.y
                        currentMouseCrossCoord = mouse.x
                    } else {
                        currentMouseCoord = dockContainer.x + dockTracker.x + mouse.x
                        currentMouseCrossCoord = mouse.y
                    }
                    lastValidMouseCoord = currentMouseCoord
                    lastApproachRamp = root.calcApproachRamp(currentMouseCrossCoord)
                }
                onEntered: {
                    hideDelayTimer.stop()
                    root.isHovered = true
                }
                onExited: {
                    currentMouseCoord = -99999
                    currentMouseCrossCoord = -99999
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

                // ── Stable Nominal Center Math ───────────────────────────────
                // ── Stable Nominal Center Math ───────────────────────────────
                readonly property real itemNominalCenter: root.getNominalCenter(isPinnedItem, index)
                readonly property real distToMouse: Math.abs(root.mouseScreenCoord - itemNominalCenter)

                // Harmonic 2-pitch radius ensures sum(cos^2) is mathematically constant (= 2.0)
                readonly property real radiusInfluence: (root.iconSize + root.itemSpacing) * 2.0

                // Mathematical macOS Raised-Cosine Harmonic Envelope
                readonly property real rawEnvelope: {
                    if (distToMouse >= radiusInfluence) return 0.0
                    const norm = distToMouse / radiusInfluence
                    const c = Math.cos(norm * (Math.PI / 2))
                    return c * c
                }

                // ── True macOS Direct Visual Scale (Zero Latency Wave) ────────
                readonly property real visualScale: 1.0 + ((root.maxScale - 1.0) * rawEnvelope * root.approachRamp * root.hoverProgress)

                // ── macOS Delegate Bounds (Continuous Sub-pixel Wave Push) ───
                width: root.isVertical ? root.iconSize : (root.iconSize * visualScale)
                height: root.isVertical ? (root.iconSize * visualScale) : root.iconSize

                // Higher scale icons render in front
                z: Math.round(visualScale * 100)

                // ── Hover Detection for Tooltip ──────────────────────────────
                readonly property bool isDirectlyHovered: root.isHovered && (distToMouse < (root.iconSize * 0.48))

                // ── Visual Icon Item (macOS Shelf-Anchored Lift) ─────────────
                Item {
                    id: iconVisual
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: root.isBottom ? 4 : 0
                    anchors.left: root.isLeft ? parent.left : undefined
                    anchors.leftMargin: root.isLeft ? 4 : 0
                    anchors.right: root.isRight ? parent.right : undefined
                    anchors.rightMargin: root.isRight ? 4 : 0
                    anchors.verticalCenter: root.isVertical ? parent.verticalCenter : undefined

                    width: root.iconSize
                    height: root.iconSize
                    scale: iconDelegate.visualScale
                    transformOrigin: root.isBottom ? Item.Bottom : (root.isLeft ? Item.Left : (root.isRight ? Item.Right : Item.Center))

                    // Tactile macOS Bounce on Launch / Click
                    SequentialAnimation {
                        id: clickBounce
                        property real baseScale: iconDelegate.visualScale
                        onStarted: baseScale = iconDelegate.visualScale
                        onFinished: iconVisual.scale = Qt.binding(() => iconDelegate.visualScale)
                        NumberAnimation { target: iconVisual; property: "scale"; to: clickBounce.baseScale * 0.82; duration: 65;  easing.type: Easing.InQuad }
                        NumberAnimation { target: iconVisual; property: "scale"; to: clickBounce.baseScale * 1.20; duration: 110; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                        NumberAnimation { target: iconVisual; property: "scale"; to: iconDelegate.visualScale;   duration: 80;  easing.type: Easing.OutCubic }
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
                    anchors.bottom: root.isBottom ? parent.bottom : undefined
                    anchors.left: root.isLeft ? parent.left : undefined
                    anchors.right: root.isRight ? parent.right : undefined
                    anchors.bottomMargin: root.isBottom ? -4 : 0
                    anchors.leftMargin: root.isLeft ? -4 : 0
                    anchors.rightMargin: root.isRight ? -4 : 0

                    visible: root.showIndicators && Boolean(iconDelegate.modelData && iconDelegate.modelData.isRunning)

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
                    visible: root.showTooltips && iconDelegate.isDirectlyHovered
                    opacity: visible ? 1 : 0
                    scale: visible ? 1 : 0.92
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

                // ── Click MouseArea ──────────────────────────────────────────
                // Covers the full delegate plus upward headroom for lifted icons
                MouseArea {
                    id: clickArea
                    anchors.fill: parent
                    anchors.topMargin: root.isBottom ? -(root.iconSize * 0.45) : 0
                    anchors.leftMargin: root.isRight ? -(root.iconSize * 0.45) : 0
                    anchors.rightMargin: root.isLeft ? -(root.iconSize * 0.45) : 0
                    hoverEnabled: false
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor

                    onClicked: (mouse) => {
                        if (mouse.button === Qt.RightButton) {
                            if (Services.DockService) {
                                const iconScreenX = dockContainer.x + itemsLayout.x + iconDelegate.x + iconDelegate.width / 2
                                const iconScreenY = dockContainer.y + itemsLayout.y + iconDelegate.y + iconDelegate.height / 2
                                Services.DockService.openMenu(iconDelegate.modelData, iconScreenX, iconScreenY)
                            }
                        } else {
                            if (root.bounceOnClick) {
                                clickBounce.restart()
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
