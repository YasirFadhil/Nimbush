import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../services" as Services

// ─────────────────────────────────────────────────────────────────────────────
//  Settings  ·  compact / minimalist rewrite
//  - public API unchanged: show/hide/toggle/open/close, overlayId, currentTab, compSubTab
//  - tab indices unchanged: 0 Appearance · 1 Bar&Dock · 2 Notifications · 3 Sound
//                           4 Lock&Power · 5 Compositor · 6 Keybindings · 7 Backup · 8 About
// ─────────────────────────────────────────────────────────────────────────────
FloatingWindow {
    id: rootWindow

    title: "Quickshell Settings"
    visible: false
    implicitWidth: 820
    implicitHeight: 580
    minimumSize: Qt.size(460, 380)
    color: ui.bg

    property string overlayId: "settings"
    property int currentTab: 0
    onCurrentTabChanged: {
        if (contentFlick) contentFlick.contentY = 0
        compSubTab = 0
        keyCategory = "all"
        keyBehaviourFilter = "all"
        isAddingKeybind = false
        keySearchQuery = ""
        formRepeat = false
        formLocked = false
        formMouse = false
        formNonConsuming = false
        formFile = ""
    }
    property int compSubTab: 0
    property string keySearchQuery: ""
    property string keyCategory: "all"
    property string keyBehaviourFilter: "all" // "all", "repeat", "locked", "mouse", "passthrough"
    property string sidebarSearchQuery: ""
    property bool sidebarCollapsed: false
    readonly property bool sidebarCompact: sidebarCollapsed || rootWindow.width < 580
    property bool isAddingKeybind: false
    property var editingBindId: ""
    property int editingBindLine: -1
    property string formKeys: ""
    property string formAction: ""
    property string formDesc: ""
    property bool formRepeat: false
    property bool formLocked: false
    property bool formMouse: false
    property bool formNonConsuming: false
    property string formFile: ""

    // ── Displays & Monitors State & Geometry (Directly on rootWindow) ───────────
    property var dispMonitors: (Services.Compositor && Services.Compositor.monitorsList) ? Services.Compositor.monitorsList : []
    property var dispLocalLayout: []
    property string dispSelectedMonitorName: ""
    property bool dispHasPendingChanges: false
    property bool dispIsDragging: false
    property bool dispIsApplying: false
    property string dispStatusMessage: ""
    property real dispSnapGuideX: -1
    property real dispSnapGuideY: -1
    property bool dispShowSnapGuideX: false
    property bool dispShowSnapGuideY: false
    property string dispDockMessage: ""
    property string faceIdEnrollmentNotice: ""

    onDispMonitorsChanged: syncDisplaysLocal(false)

    function getDisplayLogWidth(m) {
        if (!m) return 1920
        var rawW = (m.transform === 1 || m.transform === 3) ? parseInt(m.height || 1080) : parseInt(m.width || 1920)
        var sc = (m.scale && m.scale > 0) ? parseFloat(m.scale) : 1.0
        return Math.max(320, Math.round(rawW / sc))
    }

    function getDisplayLogHeight(m) {
        if (!m) return 1080
        var rawH = (m.transform === 1 || m.transform === 3) ? parseInt(m.width || 1920) : parseInt(m.height || 1080)
        var sc = (m.scale && m.scale > 0) ? parseFloat(m.scale) : 1.0
        return Math.max(240, Math.round(rawH / sc))
    }

    function syncDisplaysLocal(force) {
        if (!force && (dispIsDragging || dispIsApplying || dispHasPendingChanges)) return
        if (!dispMonitors || dispMonitors.length === 0) {
            dispLocalLayout = []
            dispSelectedMonitorName = ""
            return
        }
        var copy = []
        for (var i = 0; i < dispMonitors.length; i++) {
            var m = dispMonitors[i]
            copy.push({
                id: m.id !== undefined ? m.id : i,
                name: m.name || ("Display " + (i + 1)),
                description: m.description || "",
                make: m.make || "",
                model: m.model || "",
                width: parseInt(m.width || 1920),
                height: parseInt(m.height || 1080),
                physicalWidth: parseInt(m.physicalWidth || 0),
                physicalHeight: parseInt(m.physicalHeight || 0),
                refreshRate: parseInt(m.refreshRate || 60),
                exactRefreshRate: parseFloat(m.exactRefreshRate || m.refreshRate || 60),
                x: parseInt(m.x || 0),
                y: parseInt(m.y || 0),
                scale: parseFloat(m.scale || 1.0),
                transform: parseInt(m.transform || 0),
                focused: Boolean(m.focused),
                vrr: Boolean(m.vrr),
                dpmsStatus: m.dpmsStatus !== undefined ? Boolean(m.dpmsStatus) : true,
                disabled: Boolean(m.disabled),
                mirrorOf: m.mirrorOf || "none",
                mode: m.mode || "preferred",
                availableModes: Array.isArray(m.availableModes) ? m.availableModes : [],
                activeWorkspace: m.activeWorkspace || "1"
            })
        }
        dispLocalLayout = copy
        enforceDisplayNoOverlaps()
        if (!dispSelectedMonitorName || !findDisplayMonitor(dispSelectedMonitorName)) {
            var focused = dispLocalLayout.find(function(it) { return it.focused })
            dispSelectedMonitorName = focused ? focused.name : (dispLocalLayout[0] ? dispLocalLayout[0].name : "")
        }
        dispHasPendingChanges = false
    }

    function findDisplayMonitor(name) {
        if (!dispLocalLayout) return null
        for (var i = 0; i < dispLocalLayout.length; i++) {
            if (dispLocalLayout[i].name === name) return dispLocalLayout[i]
        }
        return null
    }

    readonly property var currentDisplayMon: findDisplayMonitor(dispSelectedMonitorName) || (dispLocalLayout && dispLocalLayout.length > 0 ? dispLocalLayout[0] : null)

    function updateDisplayProp(prop, val, applyLive) {
        if (!currentDisplayMon) return
        var copy = JSON.parse(JSON.stringify(dispLocalLayout))
        for (var i = 0; i < copy.length; i++) {
            if (copy[i].name === currentDisplayMon.name) {
                copy[i][prop] = val
                break
            }
        }
        dispLocalLayout = copy

        if (prop === "scale" || prop === "transform" || prop === "mode") {
            enforceDisplayNoOverlaps()
        }

        dispHasPendingChanges = true
        dispAutoSaveTimer.restart()

        if (applyLive !== false && Services.Compositor) {
            if (prop === "scale") Services.Compositor.setMonitorScale(currentDisplayMon.name, val, false)
            else if (prop === "transform") Services.Compositor.setMonitorTransform(currentDisplayMon.name, val, false)
            else if (prop === "mode") Services.Compositor.setMonitorMode(currentDisplayMon.name, val, false)
            else if (prop === "vrr") Services.Compositor.setMonitorVRR(currentDisplayMon.name, val, false)
            else if (prop === "disabled") Services.Compositor.setMonitorDisabled(currentDisplayMon.name, val, false)
            else if (prop === "mirrorOf") Services.Compositor.setMonitorMirror(currentDisplayMon.name, val, false)
            else if (prop === "x" || prop === "y") {
                normalizeDisplayPositions()
                Services.Compositor.applyMonitorLayout(dispLocalLayout, false)
            }
        }
    }

    function enforceDisplayNoOverlaps() {
        if (!dispLocalLayout || dispLocalLayout.length < 2) return
        var copy = JSON.parse(JSON.stringify(dispLocalLayout))
        var activeIndices = []
        for (var i = 0; i < copy.length; i++) {
            if (!copy[i].disabled) activeIndices.push(i)
        }
        if (activeIndices.length < 2) return

        activeIndices.sort(function(a, b) {
            if (copy[a].x !== copy[b].x) return copy[a].x - copy[b].x
            return copy[a].y - copy[b].y
        })

        for (var k = 1; k < activeIndices.length; k++) {
            var prevIdx = activeIndices[k - 1]
            var curIdx = activeIndices[k]
            var prev = copy[prevIdx]
            var cur = copy[curIdx]
            var prevW = getDisplayLogWidth(prev)
            var prevH = getDisplayLogHeight(prev)
            var curW = getDisplayLogWidth(cur)
            var curH = getDisplayLogHeight(cur)

            var overlapX = (cur.x < prev.x + prevW) && (cur.x + curW > prev.x)
            var overlapY = (cur.y < prev.y + prevH) && (cur.y + curH > prev.y)

            if (overlapX && overlapY) {
                cur.x = prev.x + prevW
            }
        }
        dispLocalLayout = copy
        normalizeDisplayPositions()
    }

    function normalizeDisplayPositions() {
        if (!dispLocalLayout || dispLocalLayout.length === 0) return
        var minX = Infinity, minY = Infinity
        for (var i = 0; i < dispLocalLayout.length; i++) {
            if (!dispLocalLayout[i].disabled) {
                if (dispLocalLayout[i].x < minX) minX = dispLocalLayout[i].x
                if (dispLocalLayout[i].y < minY) minY = dispLocalLayout[i].y
            }
        }
        if (minX === Infinity || minY === Infinity) return
        var copy = JSON.parse(JSON.stringify(dispLocalLayout))
        for (var j = 0; j < copy.length; j++) {
            copy[j].x = Math.max(0, copy[j].x - minX)
            copy[j].y = Math.max(0, copy[j].y - minY)
        }
        dispLocalLayout = copy
    }

    function applyDisplayLayout(saveToConfig) {
        if (!dispLocalLayout || dispLocalLayout.length === 0) return
        dispAutoSaveTimer.stop()
        enforceDisplayNoOverlaps()
        normalizeDisplayPositions()
        dispIsApplying = true
        dispStatusMessage = "Applying display configuration..."
        if (Services.Compositor) {
            Services.Compositor.applyMonitorLayout(dispLocalLayout, saveToConfig !== false)
        }
        dispHasPendingChanges = false
        dispFeedbackTimer.restart()
    }

    function revertDisplayChanges() {
        dispAutoSaveTimer.stop()
        syncDisplaysLocal(true)
        if (Services.Compositor && dispLocalLayout.length > 0) {
            Services.Compositor.applyMonitorLayout(dispLocalLayout, false)
        }
        dispStatusMessage = "Reverted unstaged display changes"
        dispClearTimer.restart()
    }

    function autoAlignDisplaysHorizontal() {
        if (!dispLocalLayout || dispLocalLayout.length === 0) return
        var copy = JSON.parse(JSON.stringify(dispLocalLayout))
        var curX = 0
        for (var i = 0; i < copy.length; i++) {
            if (!copy[i].disabled) {
                copy[i].x = curX
                copy[i].y = 0
                curX += getDisplayLogWidth(copy[i])
            }
        }
        dispLocalLayout = copy
        dispHasPendingChanges = true
        dispAutoSaveTimer.restart()
        if (Services.Compositor) Services.Compositor.applyMonitorLayout(dispLocalLayout, false)
    }

    function autoAlignDisplaysVertical() {
        if (!dispLocalLayout || dispLocalLayout.length === 0) return
        var copy = JSON.parse(JSON.stringify(dispLocalLayout))
        var curY = 0
        for (var i = 0; i < copy.length; i++) {
            if (!copy[i].disabled) {
                copy[i].x = 0
                copy[i].y = curY
                curY += getDisplayLogHeight(copy[i])
            }
        }
        dispLocalLayout = copy
        dispHasPendingChanges = true
        dispAutoSaveTimer.restart()
        if (Services.Compositor) Services.Compositor.applyMonitorLayout(dispLocalLayout, false)
    }

    function swapDisplays() {
        if (!dispLocalLayout || dispLocalLayout.length < 2) return
        var copy = JSON.parse(JSON.stringify(dispLocalLayout))
        var temp = copy[0]
        copy[0] = copy[1]
        copy[1] = temp

        var curX = 0
        for (var i = 0; i < copy.length; i++) {
            if (!copy[i].disabled) {
                copy[i].x = curX
                copy[i].y = 0
                curX += getDisplayLogWidth(copy[i])
            }
        }
        dispLocalLayout = copy
        dispHasPendingChanges = true
        dispAutoSaveTimer.restart()
        if (Services.Compositor) Services.Compositor.applyMonitorLayout(dispLocalLayout, false)
    }

    function setDisplayAsPrimary(name) {
        if (!name) return
        var copy = JSON.parse(JSON.stringify(dispLocalLayout))
        for (var i = 0; i < copy.length; i++) {
            copy[i].focused = (copy[i].name === name)
        }
        dispLocalLayout = copy
        dispHasPendingChanges = true
        dispAutoSaveTimer.restart()
        if (Services.Compositor) Services.Compositor.setPrimaryMonitor(name)
        dispStatusMessage = name + " set as primary display"
        dispClearTimer.restart()
    }

    function calcDisplaySnap(draggedIdx, rawStageX, rawStageY, boxW, boxH, originX, originY, scale) {
        if (!dispLocalLayout || draggedIdx < 0 || draggedIdx >= dispLocalLayout.length) {
            return {
                snappedStageX: rawStageX,
                snappedStageY: rawStageY,
                snappedVirtX: 0,
                snappedVirtY: 0,
                guideX: -1,
                hasGuideX: false,
                guideY: -1,
                hasGuideY: false,
                dockMessage: ""
            }
        }

        var target = dispLocalLayout[draggedIdx]
        var targetW = getDisplayLogWidth(target)
        var targetH = getDisplayLogHeight(target)

        var rawVirtX = (rawStageX - originX) / scale
        var rawVirtY = (rawStageY - originY) / scale

        // Snap threshold: 24 canvas screen pixels
        var snapPx = 24
        var snapVirt = snapPx / Math.max(0.01, scale)

        var snappedVirtX = rawVirtX
        var snappedVirtY = rawVirtY
        var gx = -1, gy = -1
        var dockMsg = ""

        for (var j = 0; j < dispLocalLayout.length; j++) {
            if (j === draggedIdx || dispLocalLayout[j].disabled) continue
            var other = dispLocalLayout[j]
            var otherW = getDisplayLogWidth(other)
            var otherH = getDisplayLogHeight(other)

            // Horizontal Magnetic Edge Snapping
            // 1. Flush Right of other
            if (Math.abs(rawVirtX - (other.x + otherW)) < snapVirt) {
                snappedVirtX = other.x + otherW
                gx = originX + (other.x + otherW) * scale
                dockMsg = "Right of " + other.name
            }
            // 2. Flush Left of other
            else if (Math.abs((rawVirtX + targetW) - other.x) < snapVirt) {
                snappedVirtX = other.x - targetW
                gx = originX + other.x * scale
                dockMsg = "Left of " + other.name
            }
            // 3. Align Left with other
            else if (Math.abs(rawVirtX - other.x) < snapVirt) {
                snappedVirtX = other.x
                gx = originX + other.x * scale
            }
            // 4. Align Right with other
            else if (Math.abs((rawVirtX + targetW) - (other.x + otherW)) < snapVirt) {
                snappedVirtX = other.x + otherW - targetW
                gx = originX + (other.x + otherW) * scale
            }

            // Vertical Magnetic Edge Snapping
            // 1. Align Top with other
            if (Math.abs(rawVirtY - other.y) < snapVirt) {
                snappedVirtY = other.y
                gy = originY + other.y * scale
            }
            // 2. Align Bottom with other
            else if (Math.abs((rawVirtY + targetH) - (other.y + otherH)) < snapVirt) {
                snappedVirtY = other.y + otherH - targetH
                gy = originY + (other.y + otherH) * scale
            }
            // 3. Flush Below other
            else if (Math.abs(rawVirtY - (other.y + otherH)) < snapVirt) {
                snappedVirtY = other.y + otherH
                gy = originY + (other.y + otherH) * scale
                dockMsg = "Below " + other.name
            }
            // 4. Flush Above other
            else if (Math.abs((rawVirtY + targetH) - other.y) < snapVirt) {
                snappedVirtY = other.y - targetH
                gy = originY + other.y * scale
                dockMsg = "Above " + other.name
            }
        }

        var snappedStageX = originX + snappedVirtX * scale
        var snappedStageY = originY + snappedVirtY * scale

        return {
            snappedStageX: snappedStageX,
            snappedStageY: snappedStageY,
            snappedVirtX: snappedVirtX,
            snappedVirtY: snappedVirtY,
            guideX: gx,
            hasGuideX: gx >= 0,
            guideY: gy,
            hasGuideY: gy >= 0,
            dockMessage: dockMsg
        }
    }

    function dockSelectedDisplay(direction) {
        if (!currentDisplayMon || !dispLocalLayout || dispLocalLayout.length < 2) return
        var selIdx = -1
        var otherIdx = -1
        for (var i = 0; i < dispLocalLayout.length; i++) {
            if (dispLocalLayout[i].name === currentDisplayMon.name) selIdx = i
            else if (!dispLocalLayout[i].disabled && otherIdx === -1) otherIdx = i
        }
        if (selIdx === -1 || otherIdx === -1) return

        var copy = JSON.parse(JSON.stringify(dispLocalLayout))
        var target = copy[selIdx]
        var other = copy[otherIdx]
        var targetW = getDisplayLogWidth(target)
        var targetH = getDisplayLogHeight(target)
        var otherW = getDisplayLogWidth(other)
        var otherH = getDisplayLogHeight(other)

        if (direction === "left") {
            target.x = 0
            target.y = 0
            other.x = targetW
            other.y = 0
        } else if (direction === "right") {
            other.x = 0
            other.y = 0
            target.x = otherW
            target.y = 0
        } else if (direction === "top") {
            target.x = 0
            target.y = 0
            other.x = 0
            other.y = targetH
        } else if (direction === "bottom") {
            other.x = 0
            other.y = 0
            target.x = 0
            target.y = otherH
        }

        dispLocalLayout = copy
        normalizeDisplayPositions()
        enforceDisplayNoOverlaps()
        dispHasPendingChanges = true
        dispAutoSaveTimer.restart()
        if (Services.Compositor) Services.Compositor.applyMonitorLayout(dispLocalLayout, false)
        dispStatusMessage = target.name + " attached to " + direction + " of " + other.name
        dispClearTimer.restart()
    }

    function commitDisplayDrop(draggedIndex, canvasX, canvasY, originX, originY, scale) {
        if (!dispLocalLayout || draggedIndex < 0 || draggedIndex >= dispLocalLayout.length) return
        var target = dispLocalLayout[draggedIndex]
        var targetW = getDisplayLogWidth(target)
        var targetH = getDisplayLogHeight(target)

        var snap = calcDisplaySnap(draggedIndex, canvasX, canvasY, 0, 0, originX, originY, scale)
        var snappedX = Math.round(snap.snappedVirtX)
        var snappedY = Math.round(snap.snappedVirtY)

        // Strict Overlap Prevention: if bounding boxes overlap with any monitor, resolve to nearest edge
        for (var k = 0; k < dispLocalLayout.length; k++) {
            if (k === draggedIndex || dispLocalLayout[k].disabled) continue
            var o = dispLocalLayout[k]
            var oW = getDisplayLogWidth(o)
            var oH = getDisplayLogHeight(o)

            var isOverlapX = (snappedX < o.x + oW) && (snappedX + targetW > o.x)
            var isOverlapY = (snappedY < o.y + oH) && (snappedY + targetH > o.y)

            if (isOverlapX && isOverlapY) {
                var pushRight = (o.x + oW) - snappedX
                var pushLeft = (snappedX + targetW) - o.x
                var pushDown = (o.y + oH) - snappedY
                var pushUp = (snappedY + targetH) - o.y

                var minP = Math.min(pushRight, pushLeft, pushDown, pushUp)
                if (minP === pushRight) snappedX = o.x + oW
                else if (minP === pushLeft) snappedX = o.x - targetW
                else if (minP === pushDown) snappedY = o.y + oH
                else snappedY = o.y - targetH
            }
        }

        var copy = JSON.parse(JSON.stringify(dispLocalLayout))
        copy[draggedIndex].x = snappedX
        copy[draggedIndex].y = snappedY
        dispLocalLayout = copy

        normalizeDisplayPositions()
        enforceDisplayNoOverlaps()
        dispHasPendingChanges = true
        dispAutoSaveTimer.restart()
        if (Services.Compositor) Services.Compositor.applyMonitorLayout(dispLocalLayout, false)
    }

    Timer {
        id: dispAutoSaveTimer
        interval: 1200
        repeat: false
        onTriggered: {
            if (rootWindow.dispHasPendingChanges && !rootWindow.dispIsDragging && !rootWindow.dispIsApplying) {
                rootWindow.applyDisplayLayout(true)
            }
        }
    }

    Timer {
        id: dispFeedbackTimer
        interval: 1000
        onTriggered: {
            rootWindow.dispIsApplying = false
            rootWindow.dispStatusMessage = "Display layout applied and saved"
            dispClearTimer.restart()
        }
    }

    Timer {
        id: dispClearTimer
        interval: 3000
        onTriggered: rootWindow.dispStatusMessage = ""
    }

    Component.onCompleted: {
        Services.OverlayManager.register(rootWindow)
        syncDisplaysLocal(true)
        if (Services.Compositor) {
            Services.Compositor.refreshState()
            Services.Compositor.loadKeybinds()
            Services.Compositor.loadAutostart()
        }
    }

    function show(tabIndex, subTabIndex) {
        if (typeof tabIndex === "number" && tabIndex >= 0) {
            currentTab = tabIndex
            if (typeof subTabIndex === "number" && subTabIndex >= 0) {
                compSubTab = subTabIndex
            } else {
                compSubTab = 0
            }
        } else {
            currentTab = 0
            compSubTab = 0
        }
        keyCategory = "all"
        isAddingKeybind = false
        keySearchQuery = ""
        sidebarSearchQuery = ""
        visible = true
        keyFocus.forceActiveFocus()
        if (Services.Compositor) {
            Services.Compositor.refreshState()
            Services.Compositor.loadKeybinds()
            Services.Compositor.loadAutostart()
        }
    }

    function hide() {
        dispAutoSaveTimer.stop()
        if (dispHasPendingChanges) {
            applyDisplayLayout(true)
        }
        if (Services.Config) {
            Services.Config.saveConfigImmediately()
        }
        currentTab = 0
        compSubTab = 0
        keyCategory = "all"
        isAddingKeybind = false
        keySearchQuery = ""
        sidebarSearchQuery = ""
        visible = false
    }

    function toggle() {
        visible ? hide() : show()
    }

    function open(tabIndex, subTabIndex) { show(tabIndex, subTabIndex) }
    function close() { hide() }

    onVisibleChanged: {
        if (visible) {
            keyFocus.forceActiveFocus()
        } else {
            dispAutoSaveTimer.stop()
            if (dispHasPendingChanges) {
                applyDisplayLayout(true)
            }
            if (Services.Config) {
                Services.Config.saveConfigImmediately()
            }
            currentTab = 0
            compSubTab = 0
            keyCategory = "all"
            isAddingKeybind = false
            keySearchQuery = ""
            sidebarSearchQuery = ""
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  DESIGN TOKENS  ·  flat, hairline-ruled, 12px base, 24px controls
    // ═════════════════════════════════════════════════════════════════════════
    QtObject {
        id: ui

        readonly property bool dark: Services.Theme.isDark
        readonly property color bg: Services.Theme.bg
        readonly property color fg: Services.Theme.textPrimary
        readonly property color dim: Services.Theme.textSecondary
        readonly property color faint: Services.Theme.textDisabled
        readonly property color accent: Services.Theme.accent
        readonly property color onAccent: Services.Theme.bgOnAccent || "#ffffff"
        readonly property color danger: Services.Theme.danger
        readonly property color ok: Services.Theme.success || "#34c759"
        readonly property color warn: Services.Theme.warning || "#f5a524"

        function tone(a) { return Qt.rgba(fg.r, fg.g, fg.b, a) }
        function wash(a) { return Qt.rgba(accent.r, accent.g, accent.b, a) }
        function dng(a)  { return Qt.rgba(danger.r, danger.g, danger.b, a) }

        readonly property color line: tone(0.08)
        readonly property color fill: tone(0.06)
        readonly property color fillHi: tone(0.12)
        readonly property color rail: Qt.tint(bg, tone(0.035))

        readonly property int rowH: 34
        readonly property int ctlH: 24
        readonly property int r: 6
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  PRIMITIVES
    // ═════════════════════════════════════════════════════════════════════════

    // Toggle: 30x16 pill
    component Tgl: Rectangle {
        id: tg
        property bool on: false
        property bool interactive: true
        signal flipped(bool v)

        implicitWidth: 30
        implicitHeight: 16
        radius: 8
        color: on ? ui.accent : ui.tone(0.20)
        Behavior on color { ColorAnimation { duration: 110 } }

        Rectangle {
            width: 12; height: 12; radius: 6
            y: 2
            x: tg.on ? tg.width - width - 2 : 2
            color: tg.on ? ui.onAccent : ui.tone(0.65)
            Behavior on x { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        }
        TapHandler { enabled: tg.interactive; onTapped: tg.flipped(!tg.on) }
        HoverHandler { enabled: tg.interactive; cursorShape: Qt.PointingHandCursor }
    }

    // Segmented control (<= 5 short options)
    component Seg: Rectangle {
        id: seg
        property var options: []
        property var current: null
        signal picked(var val)

        implicitHeight: ui.ctlH
        implicitWidth: segRow.implicitWidth + 4
        radius: ui.r
        color: ui.fill

        Row {
            id: segRow
            x: 2; y: 2
            spacing: 0
            Repeater {
                model: seg.options
                delegate: Rectangle {
                    id: sg
                    required property var modelData
                    readonly property bool sel: sg.modelData.id === seg.current
                    height: seg.height - 4
                    width: sgText.implicitWidth + 16
                    radius: ui.r - 2
                    color: sg.sel ? ui.wash(0.20) : (sgMa.containsMouse ? ui.tone(0.06) : "transparent")
                    Behavior on color { ColorAnimation { duration: 90 } }
                    Text {
                        id: sgText
                        anchors.centerIn: parent
                        text: sg.modelData.label
                        font.pixelSize: 11
                        font.weight: sg.sel ? Font.DemiBold : Font.Normal
                        color: sg.sel ? ui.accent : ui.dim
                    }
                    MouseArea {
                        id: sgMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: seg.picked(sg.modelData.id)
                    }
                }
            }
        }
    }

    // Dropdown (long lists / searchable)
    component Pick: Rectangle {
        id: pk
        property var model: []
        property var current: null
        property bool searchable: false
        property int minW: 96
        property int maxW: 190
        property int popH: 230
        property string query: ""
        property bool up: false
        property real gx: 0
        signal picked(var val)

        readonly property var cur: {
            for (let i = 0; i < model.length; i++) {
                if (model[i].id === current) return model[i]
            }
            return model.length > 0 ? model[0] : { label: "—" }
        }
        readonly property var shown: {
            if (!searchable || query.trim().length === 0) return model
            const q = query.toLowerCase().trim()
            return model.filter(function(it) { return (it.label || "").toLowerCase().indexOf(q) !== -1 })
        }

        function openPop() {
            query = ""
            const gp = pk.mapToItem(rootWindow.contentItem, 0, 0)
            const h = Math.min(popH, (searchable ? 32 : 0) + Math.max(1, shown.length) * 26 + 8)
            gx = gp ? gp.x : 0
            up = gp ? ((rootWindow.height - (gp.y + pk.height) < h + 12) && gp.y > h + 12) : false
            pop.open()
        }

        implicitHeight: ui.ctlH
        implicitWidth: Math.min(maxW, Math.max(minW, pkLabel.implicitWidth + 32))
        radius: ui.r
        color: pop.visible ? ui.wash(0.16) : (pkMa.containsMouse ? ui.fillHi : ui.fill)
        Behavior on color { ColorAnimation { duration: 90 } }

        Text {
            id: pkLabel
            anchors.left: parent.left
            anchors.leftMargin: 9
            anchors.right: pkArrow.left
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            text: pk.cur ? (pk.cur.label || "") : ""
            font.pixelSize: 11
            color: ui.fg
            elide: Text.ElideRight
        }
        Text {
            id: pkArrow
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: "▾"
            font.pixelSize: 9
            color: pop.visible ? ui.accent : ui.dim
        }
        MouseArea {
            id: pkMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { if (pop.visible) pop.close(); else pk.openPop() }
        }

        Popup {
            id: pop
            width: Math.max(pk.width, 168)
            height: Math.min(pk.popH, (pk.searchable ? 32 : 0) + Math.max(1, pk.shown.length) * 26 + 8)
            x: Math.max(6 - pk.gx, pk.width - width)
            y: pk.up ? -height - 4 : pk.height + 4
            padding: 4
            modal: false
            focus: true
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
            enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 90 } }
            exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 60 } }
            onOpened: if (pk.searchable) pkSearch.forceActiveFocus()

            background: Rectangle {
                radius: 8
                color: ui.dark ? Qt.tint(ui.bg, ui.tone(0.10)) : ui.bg
                border.width: 1
                border.color: ui.tone(0.14)
            }

            contentItem: ColumnLayout {
                spacing: 4

                Rectangle {
                    visible: pk.searchable
                    Layout.fillWidth: true
                    Layout.preferredHeight: 26
                    radius: 5
                    color: ui.fill
                    TextInput {
                        id: pkSearch
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        verticalAlignment: TextInput.AlignVCenter
                        font.pixelSize: 11
                        color: ui.fg
                        clip: true
                        selectByMouse: true
                        onTextChanged: pk.query = text
                        Keys.onEscapePressed: pop.close()
                        Text {
                            visible: pkSearch.text.length === 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Search…"
                            font.pixelSize: 11
                            color: ui.faint
                        }
                    }
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: pk.shown
                    spacing: 0
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Rectangle {
                        id: po
                        required property var modelData
                        readonly property bool isCur: po.modelData.id === pk.current
                        width: ListView.view.width
                        height: 26
                        radius: 5
                        color: po.isCur ? ui.wash(0.16) : (poMa.containsMouse ? ui.fill : "transparent")
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: po.modelData.label || ""
                            font.pixelSize: 11
                            font.weight: po.isCur ? Font.DemiBold : Font.Normal
                            color: po.isCur ? ui.accent : ui.fg
                            elide: Text.ElideRight
                        }
                        MouseArea {
                            id: poMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { pk.picked(po.modelData.id); pop.close() }
                        }
                    }
                }
            }
        }
    }

    // Inline slider: thin track + value readout
    component Sld: Item {
        id: sl
        property real from: 0
        property real to: 1
        property real step: 0.01
        property int decimals: 0
        property string suffix: ""
        property real value: 0
        property real _drag: 0
        property real _last: NaN
        property bool _active: false
        signal moved(real v)

        implicitWidth: 190
        implicitHeight: 22

        readonly property real shown: _active ? _drag : value
        readonly property real ratio: to > from ? Math.max(0, Math.min(1, (shown - from) / (to - from))) : 0

        function snap(v) {
            const st = step > 0 ? step : 0.01
            const n = Math.round((v - from) / st)
            return Math.max(from, Math.min(to, from + n * st))
        }

        Timer { id: slHold; interval: 380; onTriggered: sl._active = false }

        RowLayout {
            anchors.fill: parent
            spacing: 8

            Item {
                id: slTrack
                Layout.fillWidth: true
                Layout.fillHeight: true

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 3
                    radius: 1.5
                    color: ui.tone(0.14)
                    Rectangle {
                        width: parent.width * sl.ratio
                        height: parent.height
                        radius: 1.5
                        color: ui.accent
                    }
                }
                Rectangle {
                    width: 10; height: 10; radius: 5
                    anchors.verticalCenter: parent.verticalCenter
                    x: sl.ratio * (parent.width - width)
                    color: ui.accent
                    scale: slMa.pressed ? 1.3 : (slMa.containsMouse ? 1.15 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 90 } }
                }
                MouseArea {
                    id: slMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    function upd(mx) {
                        const r = Math.max(0, Math.min(1, (mx - 5) / Math.max(1, width - 10)))
                        const v = sl.snap(sl.from + r * (sl.to - sl.from))
                        sl._drag = v
                        if (v !== sl._last) { sl._last = v; sl.moved(v) }
                    }
                    onPressed: (m) => { slHold.stop(); sl._last = NaN; sl._active = true; upd(m.x) }
                    onPositionChanged: (m) => { if (pressed) upd(m.x) }
                    onReleased: slHold.restart()
                }
            }

            Text {
                Layout.preferredWidth: 44
                horizontalAlignment: Text.AlignRight
                text: sl.shown.toFixed(sl.decimals) + sl.suffix
                font.family: Services.Theme.fontMono
                font.pixelSize: 10
                color: ui.dim
            }
        }
    }

    // Small button
    component Btn: Rectangle {
        id: btn
        property string text: ""
        property string glyph: ""
        property string kind: "plain"   // plain | accent | danger
        property bool enabledState: true
        signal clicked()

        implicitHeight: ui.ctlH
        implicitWidth: Math.max(ui.ctlH, bRow.implicitWidth + 16)
        radius: ui.r
        opacity: enabledState ? 1.0 : 0.4
        scale: bMa.pressed ? 0.96 : 1.0
        Behavior on scale { NumberAnimation { duration: 80 } }
        color: kind === "accent"
            ? (bMa.containsMouse ? Qt.lighter(ui.accent, 1.1) : ui.accent)
            : (kind === "danger"
                ? ui.dng(bMa.containsMouse ? 0.26 : 0.14)
                : (bMa.containsMouse ? ui.fillHi : ui.fill))

        RowLayout {
            id: bRow
            anchors.centerIn: parent
            spacing: 5
            Text {
                visible: btn.glyph.length > 0
                text: btn.glyph
                font.family: Services.Theme.fontSymbols
                font.pixelSize: 12
                color: btn.kind === "accent" ? ui.onAccent : (btn.kind === "danger" ? ui.danger : ui.accent)
            }
            Text {
                visible: btn.text.length > 0
                text: btn.text
                font.pixelSize: 11
                color: btn.kind === "accent" ? ui.onAccent : (btn.kind === "danger" ? ui.danger : ui.fg)
            }
        }
        MouseArea {
            id: bMa
            anchors.fill: parent
            hoverEnabled: true
            enabled: btn.enabledState
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    // Text input
    component Inp: Rectangle {
        id: inp
        property alias text: ti.text
        property alias input: ti
        property string placeholder: ""
        property bool mono: false
        signal accepted(string value)
        signal edited(string value)

        implicitHeight: ui.ctlH
        implicitWidth: 170
        radius: ui.r
        color: ti.activeFocus ? ui.wash(0.12) : ui.fill
        border.width: ti.activeFocus ? 1 : 0
        border.color: ui.accent

        TextInput {
            id: ti
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            verticalAlignment: TextInput.AlignVCenter
            font.pixelSize: 11
            font.family: inp.mono ? Services.Theme.fontMono : Qt.application.font.family
            color: ui.fg
            clip: true
            selectByMouse: true
            onAccepted: inp.accepted(text)
            onTextEdited: inp.edited(text)
            Text {
                visible: ti.text.length === 0
                anchors.verticalCenter: parent.verticalCenter
                text: inp.placeholder
                font.pixelSize: 11
                color: ui.faint
            }
        }
    }

    // Toggle pill (multi-select chips, filters, presets)
    component Chip: Rectangle {
        id: chip
        property string text: ""
        property string glyph: ""
        property bool on: false
        property bool dimmed: false
        signal clicked()

        implicitHeight: 24
        implicitWidth: cRow.implicitWidth + 18
        radius: 12
        opacity: dimmed ? 0.55 : 1.0
        color: on ? ui.wash(0.20) : (cMa.containsMouse ? ui.fillHi : ui.fill)
        Behavior on color { ColorAnimation { duration: 90 } }

        RowLayout {
            id: cRow
            anchors.centerIn: parent
            spacing: 5
            Text {
                visible: chip.glyph.length > 0
                text: chip.glyph
                font.family: Services.Theme.fontSymbols
                font.pixelSize: 11
                color: chip.on ? ui.accent : ui.dim
            }
            Text {
                text: chip.text
                font.pixelSize: 11
                font.weight: chip.on ? Font.DemiBold : Font.Normal
                color: chip.on ? ui.accent : ui.fg
            }
        }
        MouseArea {
            id: cMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }

    // − value +  stepper
    component Stepper: Rectangle {
        id: stp
        property string label: ""
        property string valueText: ""
        signal dec()
        signal inc()

        implicitHeight: ui.ctlH
        implicitWidth: 112
        radius: ui.r
        color: ui.fill

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 2
            spacing: 4
            Text { text: stp.label; font.family: Services.Theme.fontMono; font.pixelSize: 10; color: ui.faint }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: stp.valueText
                font.family: Services.Theme.fontMono
                font.pixelSize: 10
                color: ui.fg
            }
            Rectangle {
                Layout.preferredWidth: 20; Layout.preferredHeight: 20; radius: 4
                color: mMa.containsMouse ? ui.fillHi : "transparent"
                Text { anchors.centerIn: parent; text: "−"; font.pixelSize: 12; color: ui.fg }
                MouseArea { id: mMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: stp.dec() }
            }
            Rectangle {
                Layout.preferredWidth: 20; Layout.preferredHeight: 20; radius: 4
                color: pMa.containsMouse ? ui.fillHi : "transparent"
                Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 12; color: ui.fg }
                MouseArea { id: pMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: stp.inc() }
            }
        }
    }

    // Tiny status label
    component Tag: Rectangle {
        id: tag
        property string text: ""
        property color tint: ui.dim
        implicitHeight: 16
        implicitWidth: tagT.implicitWidth + 10
        radius: 4
        color: Qt.rgba(tint.r, tint.g, tint.b, 0.14)
        Text {
            id: tagT
            anchors.centerIn: parent
            text: tag.text
            font.pixelSize: 9
            font.weight: Font.DemiBold
            color: tag.tint
        }
    }

    // Keyboard keycap
    component Cap: Rectangle {
        id: cap
        property string text: ""
        implicitHeight: 18
        implicitWidth: Math.max(18, capT.implicitWidth + 10)
        radius: 4
        color: "transparent"
        border.width: 1
        border.color: ui.tone(0.22)
        Text {
            id: capT
            anchors.centerIn: parent
            text: cap.text
            font.family: Services.Theme.fontMono
            font.pixelSize: 10
            color: ui.fg
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  LAYOUT BLOCKS
    // ═════════════════════════════════════════════════════════════════════════

    // Titled group of rules
    component SettingsGroup: ColumnLayout {
        id: grp
        property string title: ""
        default property alias content: grpBody.data
        Layout.fillWidth: true
        Layout.topMargin: 8
        spacing: 2

        Text {
            visible: grp.title.length > 0
            text: grp.title
            font.pixelSize: 10
            font.weight: Font.DemiBold
            font.letterSpacing: 0.9
            font.capitalization: Font.AllUppercase
            color: ui.faint
            Layout.leftMargin: 4
            Layout.bottomMargin: 2
        }
        ColumnLayout {
            id: grpBody
            Layout.fillWidth: true
            spacing: 0
        }
    }

    // Base row: label (+hint) on the left, control slot on the right
    component Opt: Item {
        id: opt
        property string label: ""
        property string hint: ""
        property string glyph: ""
        property bool clickable: false
        signal clicked()
        default property alias control: optSlot.data

        Layout.fillWidth: true
        implicitHeight: Math.max(ui.rowH, optText.implicitHeight + 14)

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 1
            anchors.bottomMargin: 1
            radius: ui.r
            color: ui.fill
            opacity: (opt.clickable && optHover.hovered) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 90 } }
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: ui.line
        }
        HoverHandler { id: optHover; enabled: opt.clickable; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: opt.clickable; onTapped: opt.clicked() }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            spacing: 10

            Text {
                visible: opt.glyph.length > 0
                Layout.preferredWidth: 16
                horizontalAlignment: Text.AlignHCenter
                text: opt.glyph
                font.family: Services.Theme.fontSymbols
                font.pixelSize: 13
                color: ui.dim
            }
            ColumnLayout {
                id: optText
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: opt.label
                    font.pixelSize: 12
                    color: ui.fg
                    elide: Text.ElideRight
                }
                Text {
                    visible: opt.hint.length > 0
                    Layout.fillWidth: true
                    text: opt.hint
                    font.pixelSize: 10
                    color: ui.dim
                    elide: Text.ElideRight
                }
            }
            Item {
                id: optSlot
                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                implicitWidth: childrenRect.width
                implicitHeight: childrenRect.height
            }
        }
    }

    component OptSwitch: Item {
        id: osw
        property alias label: ob.label
        property alias hint: ob.hint
        property alias glyph: ob.glyph
        property bool checked: false
        signal toggled(bool v)
        Layout.fillWidth: true
        implicitHeight: ob.implicitHeight
        Opt {
            id: ob
            anchors.left: parent.left
            anchors.right: parent.right
            clickable: true
            onClicked: osw.toggled(!osw.checked)
            Tgl { on: osw.checked; interactive: false }
        }
    }

    component OptSeg: Item {
        id: osg
        property alias label: ob.label
        property alias hint: ob.hint
        property alias glyph: ob.glyph
        property var options: []
        property var current: null
        signal picked(var val)
        Layout.fillWidth: true
        implicitHeight: ob.implicitHeight
        Opt {
            id: ob
            anchors.left: parent.left
            anchors.right: parent.right
            Seg { options: osg.options; current: osg.current; onPicked: (v) => osg.picked(v) }
        }
    }

    component OptPick: Item {
        id: opk
        property alias label: ob.label
        property alias hint: ob.hint
        property alias glyph: ob.glyph
        property var model: []
        property var current: null
        property bool searchable: false
        property int minW: 110
        property int maxW: 200
        signal picked(var val)
        Layout.fillWidth: true
        implicitHeight: ob.implicitHeight
        Opt {
            id: ob
            anchors.left: parent.left
            anchors.right: parent.right
            Pick {
                model: opk.model
                current: opk.current
                searchable: opk.searchable
                minW: opk.minW
                maxW: opk.maxW
                onPicked: (v) => opk.picked(v)
            }
        }
    }

    component OptSlide: Item {
        id: osl
        property alias label: ob.label
        property alias hint: ob.hint
        property alias glyph: ob.glyph
        property real from: 0
        property real to: 1
        property real step: 0.01
        property int decimals: 0
        property string suffix: ""
        property real value: 0
        signal moved(real v)
        Layout.fillWidth: true
        implicitHeight: ob.implicitHeight
        Opt {
            id: ob
            anchors.left: parent.left
            anchors.right: parent.right
            Sld {
                from: osl.from; to: osl.to; step: osl.step
                decimals: osl.decimals; suffix: osl.suffix
                value: osl.value
                onMoved: (v) => osl.moved(v)
            }
        }
    }

    // family + size pair
    component OptFont: Item {
        id: ofn
        property alias label: ob.label
        property var famModel: []
        property var fam: null
        property var size: 11
        signal famPicked(var val)
        signal sizePicked(var val)
        Layout.fillWidth: true
        implicitHeight: ob.implicitHeight
        Opt {
            id: ob
            anchors.left: parent.left
            anchors.right: parent.right
            RowLayout {
                spacing: 6
                Pick {
                    model: ofn.famModel
                    current: ofn.fam
                    searchable: true
                    minW: 120
                    maxW: 190
                    onPicked: (v) => ofn.famPicked(v)
                }
                Pick {
                    model: rootWindow.fontSizes
                    current: ofn.size
                    minW: 58
                    maxW: 70
                    onPicked: (v) => ofn.sizePicked(v)
                }
            }
        }
    }

    // Full-width custom content row (no label column)
    component Block: Item {
        id: blk
        default property alias content: blkBody.data
        property bool ruled: true
        Layout.fillWidth: true
        implicitHeight: blkBody.implicitHeight + 14
        Rectangle {
            visible: blk.ruled
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: ui.line
        }
        ColumnLayout {
            id: blkBody
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            anchors.topMargin: 7
            spacing: 6
        }
    }

    // Horizontal wallpaper thumbnails
    component WpStrip: ListView {
        id: wp
        property string current: ""
        property bool deletable: false
        signal chosen(string path)

        orientation: ListView.Horizontal
        spacing: 6
        clip: true
        implicitHeight: 54
        boundsBehavior: Flickable.StopAtBounds
        model: Services.Wallpaper ? Services.Wallpaper.allWallpapers : []

        WheelHandler {
            onWheel: (ev) => {
                const d = ev.angleDelta.y !== 0 ? ev.angleDelta.y : ev.angleDelta.x
                wp.contentX = Math.max(0, Math.min(Math.max(0, wp.contentWidth - wp.width), wp.contentX - d))
            }
        }

        delegate: Rectangle {
            id: wc
            required property var modelData
            readonly property bool isCur: wp.current === wc.modelData.path
            width: 88
            height: 50
            radius: 6
            color: ui.fill
            border.width: wc.isCur ? 2 : 0
            border.color: ui.accent
            clip: true

            Image {
                anchors.fill: parent
                anchors.margins: wc.isCur ? 2 : 0
                source: wc.modelData.path.startsWith("/") ? ("file://" + wc.modelData.path) : wc.modelData.path
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 176
                sourceSize.height: 100
                asynchronous: true
                smooth: true
                opacity: wcMa.containsMouse ? 0.85 : 1.0
            }
            Rectangle {
                visible: wp.deletable && wc.modelData.isCustom === true && (wcMa.containsMouse || delMa.containsMouse)
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 3
                width: 16; height: 16; radius: 8
                color: delMa.containsMouse ? ui.danger : Qt.rgba(0, 0, 0, 0.6)
                Text { anchors.centerIn: parent; text: "✕"; font.pixelSize: 8; color: "#ffffff" }
                MouseArea {
                    id: delMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { if (Services.Wallpaper) Services.Wallpaper.removeCustomWallpaper(wc.modelData.path) }
                }
            }
            MouseArea {
                id: wcMa
                anchors.fill: parent
                hoverEnabled: true
                z: -1
                cursorShape: Qt.PointingHandCursor
                onClicked: wp.chosen(wc.modelData.path)
            }
        }
    }

    // Key recorder (click → press combo). Writes "SUPER + SHIFT + Q" style strings.
    component KeyRec: Rectangle {
        id: recRoot
        property string value: ""
        property bool isRecording: false
        property var heldModifiers: []
        signal recorded(string keys)
        signal cleared()

        onIsRecordingChanged: rootWindow.recording = isRecording

        implicitHeight: 28
        radius: ui.r
        color: isRecording ? ui.wash(0.12) : (recMa.containsMouse ? ui.fillHi : ui.fill)
        border.width: isRecording ? 1 : 0
        border.color: ui.accent

        Item {
            id: keyReceiver
            anchors.fill: parent
            focus: recRoot.isRecording

            Keys.onPressed: (event) => {
                if (!recRoot.isRecording) return
                if (event.key === Qt.Key_Escape && event.modifiers === Qt.NoModifier) {
                    recRoot.isRecording = false
                    recRoot.heldModifiers = []
                    event.accepted = true
                    return
                }
                if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) && event.modifiers === Qt.NoModifier) {
                    recRoot.value = ""
                    recRoot.isRecording = false
                    recRoot.heldModifiers = []
                    recRoot.cleared()
                    event.accepted = true
                    return
                }
                const mods = []
                if ((event.modifiers & Qt.MetaModifier) || event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R || event.key === Qt.Key_Meta) mods.push("SUPER")
                if ((event.modifiers & Qt.ControlModifier) || event.key === Qt.Key_Control) mods.push("CTRL")
                if ((event.modifiers & Qt.AltModifier) || event.key === Qt.Key_Alt) mods.push("ALT")
                if ((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Shift) mods.push("SHIFT")

                if (event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R || event.key === Qt.Key_Meta ||
                    event.key === Qt.Key_Control || event.key === Qt.Key_Alt || event.key === Qt.Key_Shift) {
                    recRoot.heldModifiers = mods
                    event.accepted = true
                    return
                }
                const keyName = recRoot.resolveKeyName(event.key, event.text)
                if (keyName && keyName.length > 0) {
                    const resultStr = [...mods, keyName].join(" + ")
                    recRoot.value = resultStr
                    recRoot.isRecording = false
                    recRoot.heldModifiers = []
                    recRoot.recorded(resultStr)
                }
                event.accepted = true
            }

            Keys.onReleased: (event) => {
                if (!recRoot.isRecording) return
                const mods = []
                if (event.modifiers & Qt.MetaModifier) mods.push("SUPER")
                if (event.modifiers & Qt.ControlModifier) mods.push("CTRL")
                if (event.modifiers & Qt.AltModifier) mods.push("ALT")
                if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT")
                recRoot.heldModifiers = mods
                event.accepted = true
            }
        }

        function resolveKeyName(key, text) {
            switch (key) {
                case Qt.Key_Return:
                case Qt.Key_Enter: return "Return"
                case Qt.Key_Space: return "Space"
                case Qt.Key_Tab:
                case Qt.Key_Backtab: return "Tab"
                case Qt.Key_Backspace: return "BackSpace"
                case Qt.Key_Delete: return "Delete"
                case Qt.Key_Insert: return "Insert"
                case Qt.Key_Home: return "Home"
                case Qt.Key_End: return "End"
                case Qt.Key_PageUp: return "Page_Up"
                case Qt.Key_PageDown: return "Page_Down"
                case Qt.Key_Left: return "Left"
                case Qt.Key_Right: return "Right"
                case Qt.Key_Up: return "Up"
                case Qt.Key_Down: return "Down"
                case Qt.Key_Print: return "Print"
                case Qt.Key_Pause: return "Pause"
                case Qt.Key_CapsLock: return "Caps_Lock"
                case Qt.Key_NumLock: return "Num_Lock"
                case Qt.Key_ScrollLock: return "Scroll_Lock"
                case Qt.Key_F1: return "F1"
                case Qt.Key_F2: return "F2"
                case Qt.Key_F3: return "F3"
                case Qt.Key_F4: return "F4"
                case Qt.Key_F5: return "F5"
                case Qt.Key_F6: return "F6"
                case Qt.Key_F7: return "F7"
                case Qt.Key_F8: return "F8"
                case Qt.Key_F9: return "F9"
                case Qt.Key_F10: return "F10"
                case Qt.Key_F11: return "F11"
                case Qt.Key_F12: return "F12"
                case Qt.Key_VolumeUp: return "XF86AudioRaiseVolume"
                case Qt.Key_VolumeDown: return "XF86AudioLowerVolume"
                case Qt.Key_VolumeMute: return "XF86AudioMute"
                case Qt.Key_MicMute: return "XF86AudioMicMute"
                case Qt.Key_MediaPlay:
                case Qt.Key_MediaTogglePlayPause: return "XF86AudioPlay"
                case Qt.Key_MediaNext: return "XF86AudioNext"
                case Qt.Key_MediaPrevious: return "XF86AudioPrev"
                case Qt.Key_MediaStop: return "XF86AudioStop"
                case Qt.Key_MonBrightnessUp: return "XF86MonBrightnessUp"
                case Qt.Key_MonBrightnessDown: return "XF86MonBrightnessDown"
                case Qt.Key_KbdBrightnessUp: return "XF86KbdBrightnessUp"
                case Qt.Key_KbdBrightnessDown: return "XF86KbdBrightnessDown"
                case Qt.Key_Calculator: return "XF86Calculator"
                case Qt.Key_Minus: return "minus"
                case Qt.Key_Plus:
                case Qt.Key_Equal: return "equal"
                case Qt.Key_BracketLeft: return "bracketleft"
                case Qt.Key_BracketRight: return "bracketright"
                case Qt.Key_BraceLeft: return "braceleft"
                case Qt.Key_BraceRight: return "braceright"
                case Qt.Key_Semicolon: return "semicolon"
                case Qt.Key_Apostrophe: return "apostrophe"
                case Qt.Key_QuoteLeft:
                case Qt.Key_AsciiTilde: return "grave"
                case Qt.Key_Backslash: return "backslash"
                case Qt.Key_Comma: return "comma"
                case Qt.Key_Period: return "period"
                case Qt.Key_Slash: return "slash"
                default:
                    if (key >= Qt.Key_A && key <= Qt.Key_Z) {
                        return String.fromCharCode(key).toLowerCase()
                    }
                    if (key >= Qt.Key_0 && key <= Qt.Key_9) {
                        return String.fromCharCode(key)
                    }
                    if (text && text.trim().length === 1) {
                        return text.trim()
                    }
                    return ""
            }
        }

        function startRecording() {
            heldModifiers = []
            isRecording = true
            Qt.callLater(function() { keyReceiver.forceActiveFocus() })
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 6
            spacing: 6

            Rectangle {
                visible: recRoot.isRecording
                Layout.preferredWidth: 8; Layout.preferredHeight: 8; radius: 4
                color: ui.danger
                SequentialAnimation on opacity {
                    running: recRoot.isRecording
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.25; duration: 480 }
                    NumberAnimation { to: 1.0; duration: 480 }
                }
            }
            Text {
                Layout.fillWidth: true
                text: recRoot.isRecording
                    ? (recRoot.heldModifiers.length > 0 ? recRoot.heldModifiers.join(" + ") + " + …" : "Press a combo…  (Esc cancel · ⌫ clear)")
                    : (recRoot.value.length > 0 ? recRoot.value : "Click to record")
                font.family: recRoot.value.length > 0 || recRoot.isRecording ? Services.Theme.fontMono : Qt.application.font.family
                font.pixelSize: 11
                color: recRoot.isRecording ? ui.accent : (recRoot.value.length > 0 ? ui.fg : ui.faint)
                elide: Text.ElideRight
            }
            Text {
                visible: recRoot.value.length > 0 && !recRoot.isRecording
                text: "✕"
                font.pixelSize: 10
                color: clrMa.containsMouse ? ui.danger : ui.dim
                MouseArea {
                    id: clrMa
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { recRoot.value = ""; recRoot.cleared() }
                }
            }
        }
        MouseArea {
            id: recMa
            anchors.fill: parent
            hoverEnabled: true
            z: -1
            cursorShape: Qt.PointingHandCursor
            onClicked: { if (recRoot.isRecording) recRoot.isRecording = false; else recRoot.startRecording() }
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  SHELL STATE
    // ═════════════════════════════════════════════════════════════════════════
    property bool recording: false

    readonly property var fontSizes: [8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 20].map(function(s) { return { id: s, label: s + " pt" } })

    readonly property var navItems: [
        { id: 0, title: "Appearance",    cat: 0, icon: Services.Icons.palette || "",       kw: "appearance theme dark light wallpaper accent color font gtk icon cursor scale radius matugen typography hinting antialiasing" },
        { id: 1, title: "Bar & Dock",    cat: 0, icon: Services.Icons.controlcenter || "", kw: "bar dock pinned magnification island notch workspaces clock date pills dashboard weather widgets" },
        { id: 2, title: "Notifications", cat: 0, icon: Services.Icons.bell || "",          kw: "notifications dnd do not disturb timeout retention banner history" },
        { id: 3, title: "Sound",         cat: 0, icon: Services.Icons.speaker || "",       kw: "sound audio volume microphone mixer feedback mute output input" },
        { id: 4, title: "Lock & Power",  cat: 1, icon: Services.Icons.power || "",         kw: "lock screen power battery profile avatar faceid biometric face camera clock blur" },
        { id: 5, title: "Compositor",    cat: 1, icon: Services.Icons.display || "",       kw: "compositor window blur borders animations displays monitors scaling input touchpad gestures gaming autostart startup" },
        { id: 6, title: "Keybindings",   cat: 1, icon: Services.Icons.keyboard || "",      kw: "keybindings shortcuts hotkeys binds super mod" },
        { id: 7, title: "Backup",        cat: 2, icon: Services.Icons.undo || "",          kw: "backup restore reset defaults export import config wizard" },
        { id: 8, title: "About",         cat: 2, icon: Services.Icons.info || "",          kw: "about system os kernel version distro info" }
    ]
    readonly property var curNav: navItems[currentTab] || navItems[0]

    readonly property var searchHits: {
        const q = (sidebarSearchQuery || "").toLowerCase().trim()
        if (q.length === 0) return []
        return navItems.filter(function(n) {
            return n.title.toLowerCase().indexOf(q) !== -1 || n.kw.indexOf(q) !== -1
        })
    }

    function gotoTab(i) {
        if (currentTab !== i) currentTab = i
        if (i === 5 && Services.Compositor) {
            Services.Compositor.refreshState()
            Services.Compositor.loadAutostart()
        }
        if (i === 6 && Services.Compositor) Services.Compositor.loadKeybinds()
        sidebarSearchQuery = ""
        keyFocus.forceActiveFocus()
    }

    function pageFor(i) {
        const list = [pgAppearance, pgBar, pgNotif, pgSound, pgLock, pgComp, pgKeys, pgBackup, pgAbout]
        return list[i] || pgAppearance
    }

    function appIconSource(appObj) {
        const raw = appObj ? (typeof appObj.icon === "string" ? appObj.icon : (appObj.icon ? appObj.icon.name : "")) : ""
        if (!raw) return ""
        if (Services.SystemTheme) {
            const res = Services.SystemTheme.getIcon(raw)
            if (res && res.length > 0) return res
        }
        const qp = Quickshell.iconPath(raw, true)
        return (qp && qp.startsWith("/")) ? ("file://" + qp) : (qp || "")
    }

    Item {
        id: keyFocus
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: (event) => {
            if (rootWindow.sidebarSearchQuery.length > 0) rootWindow.sidebarSearchQuery = ""
            else rootWindow.hide()
            event.accepted = true
        }
        TapHandler { onTapped: keyFocus.forceActiveFocus() }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── Floating Island Sidebar ──────────────────────────────────────
        Rectangle {
            id: sidebarRail
            Layout.fillHeight: true
            Layout.topMargin: 10
            Layout.bottomMargin: 10
            Layout.leftMargin: 10
            Layout.rightMargin: 2
            Layout.preferredWidth: rootWindow.sidebarCompact ? 50 : 176
            radius: 14
            color: ui.rail
            border.width: 1
            border.color: ui.tone(0.10)
            z: 5

            Behavior on Layout.preferredWidth {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: 8
                anchors.bottomMargin: 10
                spacing: 2

                // Sidebar toggle header
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 7
                    Layout.rightMargin: 7
                    Layout.bottomMargin: 4
                    spacing: 6

                    Text {
                        visible: !rootWindow.sidebarCompact
                        Layout.fillWidth: true
                        Layout.leftMargin: 6
                        text: "Settings"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: ui.dim
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        id: railToggleBtn
                        Layout.alignment: rootWindow.sidebarCompact ? Qt.AlignHCenter : Qt.AlignRight
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 28
                        radius: 8
                        color: railToggleMa.containsMouse ? ui.tone(0.08) : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: rootWindow.sidebarCompact ? "›" : "‹"
                            font.pixelSize: 16
                            font.weight: Font.Medium
                            color: railToggleMa.containsMouse ? ui.fg : ui.dim
                        }

                        MouseArea {
                            id: railToggleMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: rootWindow.sidebarCollapsed = !rootWindow.sidebarCollapsed
                        }
                    }
                }

                Repeater {
                    model: rootWindow.navItems
                    delegate: Item {
                        id: nv
                        required property var modelData
                        required property int index
                        readonly property bool isCur: rootWindow.currentTab === nv.modelData.id
                        readonly property bool newCat: nv.index > 0 && rootWindow.navItems[nv.index - 1].cat !== nv.modelData.cat
                        Layout.fillWidth: true
                        Layout.leftMargin: 7
                        Layout.rightMargin: 7
                        Layout.preferredHeight: 34 + (nv.newCat ? 12 : 0)

                        Rectangle {
                            id: nvBox
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 34
                            radius: 9
                            color: nv.isCur ? ui.wash(0.20) : (nvMa.containsMouse ? ui.tone(0.07) : "transparent")
                            Behavior on color { ColorAnimation { duration: 100 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: rootWindow.sidebarCompact ? 0 : 10
                                anchors.rightMargin: rootWindow.sidebarCompact ? 0 : 8
                                spacing: 10

                                Text {
                                    Layout.preferredWidth: rootWindow.sidebarCompact ? parent.width : 18
                                    horizontalAlignment: Text.AlignHCenter
                                    text: nv.modelData.icon
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 15
                                    color: nv.isCur ? ui.accent : ui.dim
                                }

                                Text {
                                    visible: !rootWindow.sidebarCompact
                                    Layout.fillWidth: true
                                    text: nv.modelData.title
                                    font.pixelSize: 12
                                    font.weight: nv.isCur ? Font.DemiBold : Font.Normal
                                    color: nv.isCur ? ui.accent : ui.fg
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                id: nvMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: rootWindow.gotoTab(nv.modelData.id)
                            }
                        }

                        Rectangle {
                            visible: rootWindow.sidebarCompact && nvMa.containsMouse
                            x: nv.width + 14
                            anchors.verticalCenter: nvBox.verticalCenter
                            width: tipT.implicitWidth + 16
                            height: 22
                            radius: 5
                            color: ui.dark ? Qt.tint(ui.bg, ui.tone(0.16)) : ui.fg
                            z: 20
                            Text {
                                id: tipT
                                anchors.centerIn: parent
                                text: nv.modelData.title
                                font.pixelSize: 11
                                color: ui.dark ? ui.fg : ui.bg
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 7
                    Layout.rightMargin: 7
                    Layout.preferredHeight: 36
                    radius: 9
                    color: avMa.containsMouse ? ui.tone(0.07) : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: rootWindow.sidebarCompact ? 3 : 8
                        anchors.rightMargin: rootWindow.sidebarCompact ? 3 : 8
                        spacing: 9

                        Services.AvatarFrame {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            source: Services.OsInfo.avatarPath
                            shapeRadius: 14
                            backgroundColor: Services.Theme.accent
                            fallbackText: {
                                const u = (Services.OsInfo.username || Quickshell.env("USER") || "user").toUpperCase()
                                return u.length > 0 ? u.charAt(0) : "?"
                            }
                            fallbackFontFamily: Services.Theme.fontSymbols
                            fallbackFontSize: 12
                            fallbackColor: Services.Theme.bgOnAccent
                        }

                        Text {
                            visible: !rootWindow.sidebarCompact
                            Layout.fillWidth: true
                            text: Services.OsInfo.username || Quickshell.env("USER") || "User"
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            color: ui.fg
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: avMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: rootWindow.gotoTab(4)
                    }
                }
            }
        }

        // ── Body ─────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // header
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                Layout.leftMargin: 18
                Layout.rightMargin: 10
                spacing: 8

                Text {
                    text: rootWindow.curNav.title
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    color: ui.fg
                }
                Item { Layout.fillWidth: true }

                Inp {
                    id: searchBox
                    Layout.preferredWidth: searchBox.input.activeFocus ? 210 : 150
                    placeholder: "Search pages"
                    text: rootWindow.sidebarSearchQuery
                    onEdited: (v) => { rootWindow.sidebarSearchQuery = v }
                    onAccepted: { if (rootWindow.searchHits.length > 0) rootWindow.gotoTab(rootWindow.searchHits[0].id) }
                }

                Rectangle {
                    Layout.preferredWidth: 24; Layout.preferredHeight: 24; radius: 12
                    color: xMa.containsMouse ? ui.dng(0.2) : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: 11
                        color: xMa.containsMouse ? ui.danger : ui.dim
                    }
                    MouseArea {
                        id: xMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: rootWindow.hide()
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: ui.line }

            // page
            Flickable {
                id: contentFlick
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: pageLoader.height + 36
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    id: vbar
                    policy: ScrollBar.AsNeeded
                    implicitWidth: 6
                    background: null
                    contentItem: Rectangle {
                        implicitWidth: 3
                        radius: 1.5
                        color: ui.tone(vbar.pressed ? 0.4 : 0.2)
                    }
                }

                Loader {
                    id: pageLoader
                    width: Math.max(280, Math.min(contentFlick.width - 36, 900))
                    x: Math.max(18, (contentFlick.width - width) / 2)
                    y: 2
                    height: item ? item.implicitHeight : 0
                    sourceComponent: rootWindow.pageFor(rootWindow.currentTab)
                }
            }
        }
    }

    // search results (floating under header)
    Rectangle {
        visible: rootWindow.sidebarSearchQuery.length > 0
        z: 50
        x: parent.width - width - 10
        y: 46
        width: 230
        height: Math.max(30, rootWindow.searchHits.length * 28 + 8)
        radius: 8
        color: ui.dark ? Qt.tint(ui.bg, ui.tone(0.10)) : ui.bg
        border.width: 1
        border.color: ui.tone(0.14)

        Text {
            visible: rootWindow.searchHits.length === 0
            anchors.centerIn: parent
            text: "No matching pages"
            font.pixelSize: 11
            color: ui.faint
        }
        Column {
            anchors.fill: parent
            anchors.margins: 4
            Repeater {
                model: rootWindow.searchHits
                delegate: Rectangle {
                    id: sh
                    required property var modelData
                    required property int index
                    width: parent.width
                    height: 28
                    radius: 5
                    color: shMa.containsMouse ? ui.fill : (sh.index === 0 ? ui.wash(0.10) : "transparent")
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        spacing: 8
                        Text { text: sh.modelData.icon; font.family: Services.Theme.fontSymbols; font.pixelSize: 12; color: ui.accent }
                        Text { text: sh.modelData.title; font.pixelSize: 11; color: ui.fg }
                    }
                    MouseArea {
                        id: shMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: rootWindow.gotoTab(sh.modelData.id)
                    }
                }
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  PAGE 0 · APPEARANCE
    // ═════════════════════════════════════════════════════════════════════════
    Component {
        id: pgAppearance

        ColumnLayout {
            spacing: 0

            SettingsGroup {
                title: "Theme"

                OptSeg {
                    label: "Mode"
                    options: [{ id: "light", label: "Light" }, { id: "dark", label: "Dark" }]
                    current: Services.Config ? Services.Config.themeMode : "dark"
                    onPicked: (id) => {
                        if (Services.Config) Services.Config.setThemeMode(id)
                        if (Services.SystemTheme) Services.SystemTheme.setColorScheme(id === "light" ? "prefer-light" : "prefer-dark")
                    }
                }
                OptSwitch {
                    label: "Matugen palette"
                    hint: "Derive colors from the wallpaper"
                    checked: Services.Config ? Services.Config.useMatugen : false
                    onToggled: (v) => {
                        if (Services.Config) Services.Config.setUseMatugen(v, Services.Wallpaper ? Services.Wallpaper.currentWallpaper : "")
                    }
                }
                Opt {
                    label: "Accent"
                    hint: Services.Config ? Services.Config.accentName : ""
                }
                Block {
                    Flow {
                        Layout.fillWidth: true
                        spacing: 8
                        Repeater {
                            model: Services.Config ? Services.Config.accentPresets : []
                            delegate: Rectangle {
                                id: sw
                                required property var modelData
                                readonly property bool isCur: Services.Config && Services.Config.accentName === sw.modelData.name
                                width: 22; height: 22; radius: 11
                                color: sw.modelData.preview || (Services.Config && Services.Config.themeMode === "light" ? sw.modelData.lightHex : sw.modelData.darkHex)
                                border.width: sw.isCur ? 2 : 0
                                border.color: ui.fg
                                scale: swMa.containsMouse ? 1.12 : 1.0
                                Behavior on scale { NumberAnimation { duration: 90 } }
                                Text {
                                    visible: sw.modelData.isMatugen === true
                                    anchors.centerIn: parent
                                    text: "✦"
                                    font.pixelSize: 10
                                    color: "#ffffff"
                                }
                                MouseArea {
                                    id: swMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (!Services.Config) return
                                        const hex = Services.Config.themeMode === "light" ? sw.modelData.lightHex : sw.modelData.darkHex
                                        Services.Config.setAccent(hex, sw.modelData.name, sw.modelData.isMatugen)
                                        if (sw.modelData.isMatugen && Services.Wallpaper) Services.Config.generateMatugen(Services.Wallpaper.currentWallpaper)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            SettingsGroup {
                title: "Wallpaper"
                Block {
                    WpStrip {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 54
                        deletable: true
                        current: Services.Wallpaper ? Services.Wallpaper.currentWallpaper : ""
                        onChosen: (path) => {
                            if (!Services.Wallpaper) return
                            Services.Wallpaper.setWallpaper(path)
                            if (Services.Config && Services.Config.useMatugen) Services.Config.generateMatugen(path)
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        Btn {
                            glyph: Services.Icons.plus || "+"
                            text: "Add image"
                            onClicked: { if (Services.Wallpaper) Services.Wallpaper.pickCustomWallpaper() }
                        }
                    }
                }
            }

            SettingsGroup {
                title: "System theme"
                OptPick {
                    label: "GTK theme"
                    searchable: true
                    model: Services.SystemTheme ? Services.SystemTheme.gtkThemes : []
                    current: Services.SystemTheme ? Services.SystemTheme.currentGtkTheme : ""
                    onPicked: (id) => { if (Services.SystemTheme) Services.SystemTheme.setGtkTheme(id) }
                }
                OptPick {
                    label: "Icons"
                    searchable: true
                    model: Services.SystemTheme ? Services.SystemTheme.iconThemes : []
                    current: Services.SystemTheme ? Services.SystemTheme.currentIconTheme : ""
                    onPicked: (id) => { if (Services.SystemTheme) Services.SystemTheme.setIconTheme(id) }
                }
                OptPick {
                    label: "Cursor"
                    searchable: true
                    model: Services.SystemTheme ? Services.SystemTheme.cursorThemes : []
                    current: Services.SystemTheme ? Services.SystemTheme.currentCursorTheme : ""
                    onPicked: (id) => { if (Services.SystemTheme) Services.SystemTheme.setCursorTheme(id) }
                }
                OptPick {
                    label: "Cursor size"
                    minW: 70
                    model: Services.SystemTheme ? Services.SystemTheme.cursorSizes : []
                    current: Services.SystemTheme ? Services.SystemTheme.currentCursorSize : 24
                    onPicked: (id) => { if (Services.SystemTheme) Services.SystemTheme.setCursorSize(id) }
                }
            }

            SettingsGroup {
                title: "Shell fonts"
                OptPick {
                    label: "UI"
                    searchable: true
                    model: Services.SystemTheme ? Services.SystemTheme.systemFonts : []
                    current: Services.Config ? Services.Config.fontFamily : ""
                    onPicked: (id) => { if (Services.Config) Services.Config.setFontFamily(id) }
                }
                OptPick {
                    label: "Monospace"
                    searchable: true
                    model: Services.SystemTheme ? Services.SystemTheme.monospaceFonts : []
                    current: Services.Config ? Services.Config.fontMono : ""
                    onPicked: (id) => { if (Services.Config) Services.Config.setFontMono(id) }
                }
                OptPick {
                    label: "Display"
                    searchable: true
                    model: Services.SystemTheme ? Services.SystemTheme.systemFonts : []
                    current: Services.Config ? Services.Config.fontDisplay : ""
                    onPicked: (id) => { if (Services.Config) Services.Config.setFontDisplay(id) }
                }
            }

            SettingsGroup {
                title: "System fonts"
                OptFont {
                    label: "Interface"
                    famModel: Services.SystemTheme ? Services.SystemTheme.systemFonts : []
                    fam: Services.SystemTheme ? Services.SystemTheme.currentFontFamily : ""
                    size: Services.SystemTheme ? Services.SystemTheme.currentFontSize : 11
                    onFamPicked: (id) => { if (Services.SystemTheme) Services.SystemTheme.setFont("interface", id, Services.SystemTheme.currentFontSize) }
                    onSizePicked: (id) => { if (Services.SystemTheme) Services.SystemTheme.setFont("interface", Services.SystemTheme.currentFontFamily, id) }
                }
                OptFont {
                    label: "Document"
                    famModel: Services.SystemTheme ? Services.SystemTheme.systemFonts : []
                    fam: Services.SystemTheme ? Services.SystemTheme.currentDocFontFamily : ""
                    size: Services.SystemTheme ? Services.SystemTheme.currentDocFontSize : 12
                    onFamPicked: (id) => { if (Services.SystemTheme) Services.SystemTheme.setFont("document", id, Services.SystemTheme.currentDocFontSize) }
                    onSizePicked: (id) => { if (Services.SystemTheme) Services.SystemTheme.setFont("document", Services.SystemTheme.currentDocFontFamily, id) }
                }
                OptFont {
                    label: "Monospace"
                    famModel: Services.SystemTheme ? Services.SystemTheme.monospaceFonts : []
                    fam: Services.SystemTheme ? Services.SystemTheme.currentMonoFontFamily : ""
                    size: Services.SystemTheme ? Services.SystemTheme.currentMonoFontSize : 11
                    onFamPicked: (id) => { if (Services.SystemTheme) Services.SystemTheme.setFont("monospace", id, Services.SystemTheme.currentMonoFontSize) }
                    onSizePicked: (id) => { if (Services.SystemTheme) Services.SystemTheme.setFont("monospace", Services.SystemTheme.currentMonoFontFamily, id) }
                }
                OptSeg {
                    label: "Hinting"
                    options: [{ id: "none", label: "None" }, { id: "slight", label: "Slight" }, { id: "medium", label: "Medium" }, { id: "full", label: "Full" }]
                    current: Services.SystemTheme ? Services.SystemTheme.currentFontHinting : "slight"
                    onPicked: (id) => { if (Services.SystemTheme) Services.SystemTheme.setFontHinting(id) }
                }
                OptSeg {
                    label: "Antialiasing"
                    options: [{ id: "rgba", label: "Subpixel" }, { id: "grayscale", label: "Grayscale" }, { id: "none", label: "None" }]
                    current: Services.SystemTheme ? Services.SystemTheme.currentFontAntialiasing : "grayscale"
                    onPicked: (id) => { if (Services.SystemTheme) Services.SystemTheme.setFontAntialiasing(id) }
                }
                OptSlide {
                    label: "Text scale"
                    from: 0.75; to: 1.75; step: 0.05; decimals: 2; suffix: "x"
                    value: Services.SystemTheme ? Services.SystemTheme.currentTextScaling : 1.0
                    onMoved: (v) => { if (Services.SystemTheme) Services.SystemTheme.setTextScaling(Number(v.toFixed(2))) }
                }
            }

            SettingsGroup {
                title: "Shell shape"
                OptSlide {
                    label: "Corner radius"
                    from: 0; to: 32; step: 1; suffix: "px"
                    value: Services.Config ? Services.Config.cornerRadius : 16
                    onMoved: (v) => { if (Services.Config) Services.Config.setCornerRadius(Math.round(v)) }
                }
                OptSlide {
                    label: "Glass opacity"
                    from: 0.5; to: 1.0; step: 0.05; decimals: 2
                    value: Services.Config ? Services.Config.glassOpacity : 0.85
                    onMoved: (v) => { if (Services.Config) Services.Config.setGlassOpacity(Number(v.toFixed(2))) }
                }
                OptSlide {
                    label: "UI scale"
                    from: 75; to: 135; step: 5; suffix: "%"
                    value: Services.Config ? Math.round(Services.Config.uiScale * 100) : 100
                    onMoved: (v) => { if (Services.Config) Services.Config.setUiScale(v / 100) }
                }
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  PAGE 1 · BAR & DOCK
    // ═════════════════════════════════════════════════════════════════════════
    Component {
        id: pgBar

        ColumnLayout {
            id: tab1
            property int sub: 0
            property bool adding: false
            property string appQuery: ""

            readonly property var candidates: {
                const raw = (DesktopEntries.applications && DesktopEntries.applications.values) ? DesktopEntries.applications.values : []
                const q = tab1.appQuery.toLowerCase().trim()
                const res = []
                for (let i = 0; i < raw.length && res.length < 24; i++) {
                    const a = raw[i]
                    if (!a || !a.id) continue
                    if (Services.DockService && Services.DockService.isPinned(a.id)) continue
                    if (q.length === 0 || (a.name && a.name.toLowerCase().includes(q)) || a.id.toLowerCase().includes(q)) res.push(a)
                }
                return res
            }

            spacing: 0

            RowLayout {
                Layout.topMargin: 8
                Seg {
                    options: [{ id: 0, label: "Bar" }, { id: 1, label: "Dock" }]
                    current: tab1.sub
                    onPicked: (id) => { tab1.sub = id }
                }
                Item { Layout.fillWidth: true }
            }

            // ── BAR ──
            ColumnLayout {
                visible: tab1.sub === 0
                Layout.fillWidth: true
                spacing: 0

                SettingsGroup {
                    title: "Bar"
                    OptSeg {
                        label: "Monitors"
                        options: [{ id: "all", label: "All" }, { id: "primary", label: "Primary" }, { id: "custom", label: "Custom" }]
                        current: Services.Config ? Services.Config.barMonitorMode : "all"
                        onPicked: (id) => { if (Services.Config) Services.Config.setBarMonitorMode(id) }
                    }
                    Repeater {
                        model: (Services.Config && Services.Config.barMonitorMode === "custom" && Services.Compositor && Services.Compositor.monitorsList) ? Services.Compositor.monitorsList : []
                        delegate: OptSwitch {
                            required property var modelData
                            label: (modelData.name || "Display") + (modelData.focused ? " · primary" : "")
                            hint: modelData.width + "×" + modelData.height + " @ " + modelData.refreshRate + "Hz"
                            checked: Services.Config ? Services.Config.isBarMonitorEnabled(modelData.name) : true
                            onToggled: (v) => { if (Services.Config) Services.Config.setBarMonitor(modelData.name, v) }
                        }
                    }
                }

                SettingsGroup {
                    title: "Dynamic Island"
                    OptSwitch {
                        label: "System HUD alerts"
                        hint: "Volume, mute, charging, and camera activity"
                        checked: Services.Config ? Services.Config.islandSysHud : true
                        onToggled: (v) => { if (Services.Config) Services.Config.setIslandSysHud(v) }
                    }
                    OptSwitch {
                        label: "Notification popups"
                        hint: "Display live notification alerts inside the island"
                        checked: Services.Config ? Services.Config.islandNotifs : true
                        onToggled: (v) => { if (Services.Config) Services.Config.setIslandNotifs(v) }
                    }
                    OptSwitch {
                        label: "Drop-to-send"
                        hint: "Drag files onto the island to share via Device Share"
                        checked: Services.Config ? Services.Config.islandDropSend : true
                        onToggled: (v) => { if (Services.Config) Services.Config.setIslandDropSend(v) }
                    }
                    OptSwitch {
                        label: "Show on lockscreen"
                        hint: "Keep media and status island active when locked"
                        checked: Services.Config ? Services.Config.islandAllowOnLockscreen : true
                        onToggled: (v) => { if (Services.Config) Services.Config.setIslandAllowOnLockscreen(v) }
                    }
                }

                SettingsGroup {
                    title: "Workspaces"
                    OptSeg {
                        label: "Style"
                        options: [{ id: "pills", label: "Pills" }, { id: "numbers", label: "Numbers" }, { id: "dots", label: "Dots" }, { id: "icons", label: "Icons" }]
                        current: Services.Config ? Services.Config.workspaceStyle : "pills"
                        onPicked: (id) => { if (Services.Config) Services.Config.setWorkspaceStyle(id) }
                    }
                    OptSwitch {
                        label: "Always show 1–5"
                        checked: Services.Config ? Services.Config.workspaceShowAll : true
                        onToggled: (v) => { if (Services.Config) Services.Config.setWorkspaceShowAll(v) }
                    }
                }

                SettingsGroup {
                    title: "Clock"
                    OptSeg {
                        label: "Date format"
                        options: [{ id: "short", label: "Thu, 20 Aug" }, { id: "full", label: "Thursday, 20 August" }]
                        current: Services.Config ? Services.Config.clockDateFormat : "short"
                        onPicked: (id) => { if (Services.Config) Services.Config.setClockDateFormat(id) }
                    }
                    OptSwitch {
                        label: "24-hour"
                        checked: Services.Config ? Services.Config.clock24h : true
                        onToggled: (v) => { if (Services.Config) Services.Config.setClock24h(v) }
                    }
                    OptSwitch {
                        label: "Seconds"
                        checked: Services.Config ? Services.Config.clockShowSeconds : false
                        onToggled: (v) => { if (Services.Config) Services.Config.setClockShowSeconds(v) }
                    }
                    OptSwitch {
                        label: "Show date"
                        checked: Services.Config ? Services.Config.clockShowDate : true
                        onToggled: (v) => { if (Services.Config) Services.Config.setClockShowDate(v) }
                    }
                }

                SettingsGroup {
                    title: "Modules"
                    Block {
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Chip {
                                text: "Workspaces"
                                on: Services.Config ? Services.Config.showWorkspaces : true
                                onClicked: { if (Services.Config) Services.Config.setShowWorkspaces(!on) }
                            }
                            Chip {
                                text: "Tray"
                                on: Services.Config ? Services.Config.showSysTray : true
                                onClicked: { if (Services.Config) Services.Config.setShowSysTray(!on) }
                            }
                            Chip {
                                text: "Sysmon"
                                on: Services.Config ? Services.Config.showSysmonTray : true
                                onClicked: { if (Services.Config) Services.Config.setShowSysmonTray(!on) }
                            }
                            Chip {
                                text: "Battery"
                                on: Services.Config ? Services.Config.showBatteryTray : true
                                onClicked: { if (Services.Config) Services.Config.setShowBatteryTray(!on) }
                            }
                            Chip {
                                text: "Control center"
                                on: Services.Config ? Services.Config.showControlCenterTray : true
                                onClicked: { if (Services.Config) Services.Config.setShowControlCenterTray(!on) }
                            }
                            Chip {
                                text: "Clock"
                                on: Services.Config ? Services.Config.showClockTray : true
                                onClicked: { if (Services.Config) Services.Config.setShowClockTray(!on) }
                            }
                        }
                    }
                }

                SettingsGroup {
                    title: "Dashboard"
                    OptSeg {
                        label: "Main widget"
                        options: [{ id: "weather", label: "Weather" }, { id: "wallpaper", label: "Wallpapers" }, { id: "both", label: "Both" }]
                        current: Services.Config ? Services.Config.dashboardWidget : "weather"
                        onPicked: (id) => { if (Services.Config) Services.Config.setDashboardWidget(id) }
                    }
                    OptSeg {
                        label: "Weather location"
                        options: [{ id: "auto", label: "Auto (IP)" }, { id: "custom", label: "Custom" }]
                        current: Services.Config ? Services.Config.weatherLocationMode : "auto"
                        onPicked: (id) => { if (Services.Config) Services.Config.setWeatherLocationMode(id) }
                    }
                    Opt {
                        visible: Services.Config && Services.Config.weatherLocationMode === "custom"
                        label: "City or coordinates"
                        hint: "e.g. Jakarta or -7.55, 110.82"
                        RowLayout {
                            spacing: 6
                            Inp {
                                id: cityInput
                                Layout.preferredWidth: 160
                                placeholder: "City or lat, lon"
                                text: Services.Config ? Services.Config.weatherCustomCity : ""
                                onAccepted: (v) => { if (Services.Config) Services.Config.setWeatherCustomCity(v) }
                            }
                            Btn {
                                text: "Apply"
                                kind: "accent"
                                onClicked: { if (Services.Config) Services.Config.setWeatherCustomCity(cityInput.text) }
                            }
                        }
                    }
                    OptSeg {
                        label: "Temperature"
                        options: [{ id: "celsius", label: "°C" }, { id: "fahrenheit", label: "°F" }]
                        current: Services.Config ? Services.Config.weatherUnit : "celsius"
                        onPicked: (id) => { if (Services.Config) Services.Config.setWeatherUnit(id) }
                    }
                    Block {
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Chip {
                                text: "Metrics"
                                on: Services.Config ? Services.Config.dashboardShowMetrics : true
                                onClicked: { if (Services.Config) Services.Config.setDashboardShowMetrics(!on) }
                            }
                            Chip {
                                text: "Specs"
                                on: Services.Config ? Services.Config.dashboardShowSpecs : true
                                onClicked: { if (Services.Config) Services.Config.setDashboardShowSpecs(!on) }
                            }
                            Chip {
                                text: "Session actions"
                                on: Services.Config ? Services.Config.dashboardShowActions : true
                                onClicked: { if (Services.Config) Services.Config.setDashboardShowActions(!on) }
                            }
                        }
                    }
                }
            }

            // ── DOCK ──
            ColumnLayout {
                visible: tab1.sub === 1
                Layout.fillWidth: true
                spacing: 0

                SettingsGroup {
                    title: "Dock"
                    OptSwitch {
                        label: "Enabled"
                        checked: Services.Config ? Services.Config.dockEnabled : true
                        onToggled: (v) => { if (Services.Config) Services.Config.setDockEnabled(v) }
                    }
                    OptSeg {
                        label: "Edge"
                        options: [{ id: "bottom", label: "Bottom" }, { id: "left", label: "Left" }, { id: "right", label: "Right" }]
                        current: Services.Config ? Services.Config.dockPosition : "bottom"
                        onPicked: (id) => { if (Services.Config) Services.Config.setDockPosition(id) }
                    }
                    OptSwitch {
                        label: "Auto-hide"
                        checked: Services.Config ? Services.Config.dockAutoHide : false
                        onToggled: (v) => { if (Services.Config) Services.Config.setDockAutoHide(v) }
                    }
                    OptSeg {
                        label: "Monitors"
                        options: [{ id: "all", label: "All" }, { id: "primary", label: "Primary" }]
                        current: Services.Config ? Services.Config.dockMonitorMode : "all"
                        onPicked: (id) => { if (Services.Config) Services.Config.setDockMonitorMode(id) }
                    }
                    OptSeg {
                        label: "Edge gap"
                        options: [{ id: 0, label: "0" }, { id: 6, label: "6" }, { id: 12, label: "12" }, { id: 18, label: "18" }]
                        current: Services.Config ? Services.Config.dockFloatingDistance : 6
                        onPicked: (id) => { if (Services.Config) Services.Config.setDockFloatingDistance(Number(id)) }
                    }
                }

                SettingsGroup {
                    title: "Look"
                    OptSeg {
                        label: "Icon size"
                        options: [{ id: 36, label: "36" }, { id: 44, label: "44" }, { id: 48, label: "48" }, { id: 56, label: "56" }, { id: 64, label: "64" }]
                        current: Services.Config ? Services.Config.dockIconSize : 48
                        onPicked: (id) => { if (Services.Config) Services.Config.setDockIconSize(Number(id)) }
                    }
                    OptSwitch {
                        label: "Magnification"
                        checked: Services.Config ? Services.Config.dockMagnification : true
                        onToggled: (v) => { if (Services.Config) Services.Config.setDockMagnification(v) }
                    }
                    OptSeg {
                        visible: Services.Config ? Services.Config.dockMagnification : true
                        label: "Zoom"
                        options: [{ id: 1.2, label: "1.2×" }, { id: 1.35, label: "1.35×" }, { id: 1.5, label: "1.5×" }, { id: 1.75, label: "1.75×" }]
                        current: Services.Config ? Services.Config.dockMagnificationScale : 1.35
                        onPicked: (id) => { if (Services.Config) Services.Config.setDockMagnificationScale(Number(id)) }
                    }
                    OptSwitch {
                        label: "Running indicators"
                        checked: Services.Config ? Services.Config.dockShowIndicators : true
                        onToggled: (v) => { if (Services.Config) Services.Config.setDockShowIndicators(v) }
                    }
                    OptSeg {
                        visible: Services.Config ? Services.Config.dockShowIndicators : true
                        label: "Indicator"
                        options: [{ id: "dot", label: "Dot" }, { id: "line", label: "Line" }, { id: "pill", label: "Pill" }, { id: "glow", label: "Glow" }]
                        current: Services.Config ? Services.Config.dockIndicatorStyle : "dot"
                        onPicked: (id) => { if (Services.Config) Services.Config.setDockIndicatorStyle(id) }
                    }
                    Block {
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Chip {
                                text: "Tooltips"
                                on: Services.Config ? Services.Config.dockShowTooltips : true
                                onClicked: { if (Services.Config) Services.Config.setDockShowTooltips(!on) }
                            }
                            Chip {
                                text: "Window count"
                                on: Services.Config ? Services.Config.dockShowWindowCount : true
                                onClicked: { if (Services.Config) Services.Config.setDockShowWindowCount(!on) }
                            }
                            Chip {
                                text: "Launch bounce"
                                on: Services.Config ? Services.Config.dockBounceOnClick : true
                                onClicked: { if (Services.Config) Services.Config.setDockBounceOnClick(!on) }
                            }
                            Chip {
                                text: "Separator"
                                on: Services.Config ? Services.Config.dockShowSeparator : true
                                onClicked: { if (Services.Config) Services.Config.setDockShowSeparator(!on) }
                            }
                        }
                    }
                }

                SettingsGroup {
                    title: "Pinned (" + ((Services.Config && Services.Config.dockPinnedApps) ? Services.Config.dockPinnedApps.length : 0) + ")"

                    Block {
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Item { Layout.fillWidth: true }
                            Btn {
                                glyph: Services.Icons.undo || "↺"
                                text: "Defaults"
                                onClicked: { if (Services.DockService) Services.DockService.resetToDefaultPinned() }
                            }
                            Btn {
                                glyph: tab1.adding ? "✕" : (Services.Icons.plus || "+")
                                text: tab1.adding ? "Close" : "Add app"
                                kind: tab1.adding ? "plain" : "accent"
                                onClicked: { tab1.adding = !tab1.adding; tab1.appQuery = "" }
                            }
                        }
                        Inp {
                            visible: tab1.adding
                            Layout.fillWidth: true
                            placeholder: "Search applications"
                            onEdited: (v) => { tab1.appQuery = v }
                        }
                        Flow {
                            visible: tab1.adding
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: tab1.adding ? tab1.candidates : []
                                delegate: Chip {
                                    required property var modelData
                                    text: modelData.name || modelData.id
                                    glyph: "+"
                                    onClicked: { if (Services.DockService && modelData.id) Services.DockService.pinApp(modelData.id) }
                                }
                            }
                        }
                    }

                    Repeater {
                        model: (Services.Config && Services.Config.dockPinnedApps) ? Services.Config.dockPinnedApps : []
                        delegate: Opt {
                            id: pin
                            required property var modelData
                            readonly property var appObj: Services.DockService ? Services.DockService.findAppByDesktopId(pin.modelData) : null
                            label: pin.appObj ? (pin.appObj.name || pin.modelData) : String(pin.modelData).replace(/\.desktop$/, "")
                            hint: String(pin.modelData)
                            RowLayout {
                                spacing: 8
                                Image {
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20
                                    source: rootWindow.appIconSource(pin.appObj)
                                    fillMode: Image.PreserveAspectFit
                                    sourceSize.width: 40
                                    sourceSize.height: 40
                                    asynchronous: true
                                }
                                Btn {
                                    glyph: "✕"
                                    kind: "danger"
                                    onClicked: { if (Services.DockService) Services.DockService.unpinApp(pin.modelData) }
                                }
                            }
                        }
                    }
                }
            }

            Item { Layout.preferredHeight: 8 }
        }
    }

    // two-step button for destructive actions (click → "Confirm?" → click)
    component ArmBtn: Item {
        id: ab
        property string idle: ""
        property bool armed: false
        signal confirmed()
        implicitWidth: abBtn.implicitWidth
        implicitHeight: abBtn.implicitHeight
        Btn {
            id: abBtn
            text: ab.armed ? "Confirm?" : ab.idle
            kind: ab.armed ? "danger" : "plain"
            onClicked: {
                if (ab.armed) { ab.armed = false; ab.confirmed() }
                else { ab.armed = true; armTimer.restart() }
            }
        }
        Timer { id: armTimer; interval: 3000; onTriggered: ab.armed = false }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  PAGE 2 · NOTIFICATIONS
    // ═════════════════════════════════════════════════════════════════════════
    Component {
        id: pgNotif

        ColumnLayout {
            spacing: 0

            SettingsGroup {
                title: "Popups"
                OptSwitch {
                    label: "Do not disturb"
                    hint: "Mute all banners"
                    checked: Services.Notifications ? Services.Notifications.doNotDisturb : false
                    onToggled: (v) => { if (Services.Notifications) Services.Notifications.doNotDisturb = v }
                }
                OptPick {
                    label: "Position"
                    minW: 130
                    model: [
                        { id: "top_right", label: "Top right" },
                        { id: "top_center", label: "Top center" },
                        { id: "top_left", label: "Top left" },
                        { id: "bottom_right", label: "Bottom right" }
                    ]
                    current: Services.Config ? Services.Config.notificationPosition : "top_right"
                    onPicked: (id) => { if (Services.Config) Services.Config.setNotificationPosition(id) }
                }
                OptSlide {
                    label: "Duration"
                    from: 2; to: 15; step: 1; suffix: "s"
                    value: Services.Config ? Services.Config.notificationTimeout : 5
                    onMoved: (v) => { if (Services.Config) Services.Config.setNotificationTimeout(Math.round(v)) }
                }
                OptSwitch {
                    label: "Show over fullscreen"
                    hint: "Battery alerts always show"
                    checked: Services.Config ? Services.Config.notificationShowInFullscreen : false
                    onToggled: (v) => { if (Services.Config) Services.Config.setNotificationShowInFullscreen(v) }
                }
                OptSwitch {
                    label: "Split KDE Connect by app"
                    checked: Services.Config ? Services.Config.notificationSplitKdeApps : true
                    onToggled: (v) => { if (Services.Config) Services.Config.setNotificationSplitKdeApps(v) }
                }
            }

            SettingsGroup {
                title: "History"
                OptSlide {
                    label: "Keep for"
                    from: 1; to: 7; step: 1; suffix: " d"
                    value: Services.Config ? Services.Config.notificationRetentionDays : 7
                    onMoved: (v) => { if (Services.Config) Services.Config.setNotificationRetentionDays(Math.round(v)) }
                }
                Opt {
                    label: "Actions"
                    RowLayout {
                        spacing: 6
                        Btn { text: "Send test"; glyph: Services.Icons.bell || ""; onClicked: testNotifProc.running = true }
                        ArmBtn { idle: "Clear history"; onConfirmed: { if (Services.Notifications) Services.Notifications.clearHistory() } }
                    }
                }
            }

            Item { Layout.preferredHeight: 8 }
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  PAGE 3 · SOUND
    // ═════════════════════════════════════════════════════════════════════════
    Component {
        id: pgSound

        ColumnLayout {
            spacing: 0

            SettingsGroup {
                title: "Output"
                Opt {
                    label: "Volume"
                    hint: (Services.Audio && Services.Audio.isMuted) ? "Muted" : ""
                    RowLayout {
                        spacing: 8
                        Btn {
                            glyph: (Services.Audio && Services.Audio.isMuted) ? (Services.Icons.volMute || "") : (Services.Icons.speaker || "")
                            kind: (Services.Audio && Services.Audio.isMuted) ? "accent" : "plain"
                            onClicked: { if (Services.Audio) Services.Audio.toggleMute() }
                        }
                        Sld {
                            from: 0; to: 100; step: 1; suffix: "%"
                            value: Services.Audio ? Math.round(Math.max(0, Math.min(1, Services.Audio.volume)) * 100) : 0
                            onMoved: (v) => { if (Services.Audio) Services.Audio.setVolume(v / 100) }
                        }
                    }
                }
                OptPick {
                    label: "Device"
                    searchable: true
                    minW: 150
                    maxW: 240
                    model: {
                        const arr = []
                        if (Services.Audio && Services.Audio.sinks) {
                            for (let i = 0; i < Services.Audio.sinks.length; i++) {
                                const s = Services.Audio.sinks[i]
                                arr.push({ id: s.name || String(i), label: s.description || s.name || ("Output " + i) })
                            }
                        }
                        if (arr.length === 0) arr.push({ id: "default", label: "Default output" })
                        return arr
                    }
                    current: Services.Audio && Services.Audio.defaultSink ? (Services.Audio.defaultSink.name || "default") : "default"
                    onPicked: (id) => {
                        if (!Services.Audio || !Services.Audio.sinks) return
                        for (let i = 0; i < Services.Audio.sinks.length; i++) {
                            if ((Services.Audio.sinks[i].name || String(i)) === id) { Services.Audio.defaultSink = Services.Audio.sinks[i]; break }
                        }
                    }
                }
            }

            SettingsGroup {
                title: "Input"
                Opt {
                    label: "Mic volume"
                    hint: (Services.Audio && Services.Audio.isSourceMuted) ? "Muted" : ""
                    RowLayout {
                        spacing: 8
                        Btn {
                            glyph: (Services.Audio && Services.Audio.isSourceMuted) ? (Services.Icons.micMute || "") : (Services.Icons.mic || "")
                            kind: (Services.Audio && Services.Audio.isSourceMuted) ? "accent" : "plain"
                            onClicked: { if (Services.Audio) Services.Audio.toggleSourceMute() }
                        }
                        Sld {
                            from: 0; to: 100; step: 1; suffix: "%"
                            value: Services.Audio ? Math.round(Math.max(0, Math.min(1, Services.Audio.sourceVolume)) * 100) : 0
                            onMoved: (v) => { if (Services.Audio) Services.Audio.setSourceVolume(v / 100) }
                        }
                    }
                }
                OptPick {
                    label: "Device"
                    searchable: true
                    minW: 150
                    maxW: 240
                    model: {
                        const arr = []
                        if (Services.Audio && Services.Audio.sources) {
                            for (let i = 0; i < Services.Audio.sources.length; i++) {
                                const s = Services.Audio.sources[i]
                                arr.push({ id: s.name || String(i), label: s.description || s.name || ("Input " + i) })
                            }
                        }
                        if (arr.length === 0) arr.push({ id: "default", label: "Default input" })
                        return arr
                    }
                    current: Services.Audio && Services.Audio.defaultSource ? (Services.Audio.defaultSource.name || "default") : "default"
                    onPicked: (id) => {
                        if (!Services.Audio || !Services.Audio.sources) return
                        for (let i = 0; i < Services.Audio.sources.length; i++) {
                            if ((Services.Audio.sources[i].name || String(i)) === id) { Services.Audio.defaultSource = Services.Audio.sources[i]; break }
                        }
                    }
                }
            }

            SettingsGroup {
                title: "Apps"
                Repeater {
                    model: Services.Audio ? Services.Audio.streams : []
                    delegate: Opt {
                        id: st
                        required property var modelData
                        label: st.modelData.name || st.modelData.appName || "App"
                        hint: st.modelData.appName || ""
                        RowLayout {
                            spacing: 8
                            Btn {
                                glyph: st.modelData.isMuted ? (Services.Icons.volMute || "") : (Services.Icons.speaker || "")
                                kind: st.modelData.isMuted ? "accent" : "plain"
                                onClicked: { if (Services.Audio) Services.Audio.toggleStreamMute(st.modelData) }
                            }
                            Sld {
                                implicitWidth: 150
                                from: 0; to: 100; step: 1; suffix: "%"
                                value: Math.round(Math.max(0, Math.min(1, st.modelData.volume || 0)) * 100)
                                onMoved: (v) => { if (Services.Audio) Services.Audio.setStreamVolume(st.modelData, v / 100) }
                            }
                        }
                    }
                }
                Text {
                    visible: !Services.Audio || !Services.Audio.streams || Services.Audio.streams.length === 0
                    Layout.leftMargin: 4
                    Layout.topMargin: 6
                    text: "Nothing is playing"
                    font.pixelSize: 11
                    color: ui.faint
                }
            }

            SettingsGroup {
                title: "Feedback"
                OptSwitch {
                    label: "UI sounds"
                    checked: Services.Config ? Services.Config.soundFeedback : true
                    onToggled: (v) => { if (Services.Config) Services.Config.setSoundFeedback(v) }
                }
                OptSwitch {
                    label: "Volume tick"
                    checked: Services.Config ? Services.Config.soundVolumeFeedback : true
                    onToggled: (v) => { if (Services.Config) Services.Config.setSoundVolumeFeedback(v) }
                }
                OptSwitch {
                    label: "Notification chime"
                    checked: Services.Config ? Services.Config.soundNotifFeedback : true
                    onToggled: (v) => { if (Services.Config) Services.Config.setSoundNotifFeedback(v) }
                }
                Opt {
                    label: "Preview"
                    RowLayout {
                        spacing: 6
                        Btn {
                            text: "Notification"
                            onClicked: { if (Services.SoundFeedback && typeof Services.SoundFeedback.playNotification === "function") Services.SoundFeedback.playNotification() }
                        }
                        Btn {
                            text: "Volume"
                            onClicked: { if (Services.SoundFeedback && typeof Services.SoundFeedback.playVolumeChange === "function") Services.SoundFeedback.playVolumeChange() }
                        }
                    }
                }
                Opt {
                    label: "Mixer"
                    hint: "Open pavucontrol"
                    Btn { glyph: Services.Icons.sliders || ""; text: "Open"; onClicked: pavuProc.running = true }
                }
            }

            Item { Layout.preferredHeight: 8 }
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  PAGE 4 · LOCK & POWER
    // ═════════════════════════════════════════════════════════════════════════
    Component {
        id: pgLock

        ColumnLayout {
            spacing: 0

            Component.onCompleted: { if (Services.FaceId) Services.FaceId.checkStatus() }

            SettingsGroup {
                title: "Profile"
                Opt {
                    label: Services.OsInfo.username || Quickshell.env("USER") || "User"
                    hint: (Services.OsInfo.hostname || "local") + " · " + (Services.OsInfo.distroName || "Linux")
                    RowLayout {
                        spacing: 8
                        Btn {
                            visible: Services.OsInfo.isCustomAvatar
                            text: "Reset"
                            onClicked: Services.OsInfo.clearCustomAvatar()
                        }
                        Btn {
                            text: Services.OsInfo.isPickingAvatar ? "Opening…" : "Change photo"
                            onClicked: Services.OsInfo.pickCustomAvatar()
                        }
                        Item {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            Services.AvatarFrame {
                                anchors.fill: parent
                                source: Services.OsInfo.avatarPath
                                shapeRadius: 14
                                backgroundColor: Services.Theme.accent
                                fallbackText: {
                                    const u = (Services.OsInfo.username || Quickshell.env("USER") || "user").toUpperCase()
                                    return u.length > 0 ? u.charAt(0) : "?"
                                }
                                fallbackFontFamily: Services.Theme.fontSymbols
                                fallbackFontSize: 12
                                fallbackColor: Services.Theme.bgOnAccent
                            }
                        }
                    }
                }
            }

            SettingsGroup {
                title: "Face ID"
                OptSwitch {
                    label: "Unlock with face"
                    checked: Services.Config ? Services.Config.faceIdEnabled : true
                    onToggled: (v) => { if (Services.Config) Services.Config.setFaceIdEnabled(v) }
                }
                OptSwitch {
                    label: "Instant unlock"
                    hint: "Dismiss the lock screen as soon as a face matches"
                    checked: Services.Config ? Services.Config.faceIdAutoUnlock : true
                    onToggled: (v) => { if (Services.Config) Services.Config.setFaceIdAutoUnlock(v) }
                }
                OptPick {
                    label: "Camera"
                    model: {
                        const devs = (Services.FaceId && Services.FaceId.availableDevices && Services.FaceId.availableDevices.length > 0)
                            ? Services.FaceId.availableDevices : ["/dev/video0", "/dev/video1", "/dev/video2"]
                        const items = []
                        for (let i = 0; i < devs.length; i++) items.push({ id: devs[i], label: devs[i] })
                        return items
                    }
                    current: Services.Config ? Services.Config.faceIdCameraDevice : "/dev/video0"
                    onPicked: (id) => { if (Services.Config) Services.Config.setFaceIdCameraDevice(id) }
                }
                Opt {
                    label: {
                        if (Services.FaceId && Services.FaceId.isEnrolling) {
                            const n = Services.FaceId.enrollStepName
                            if (n && n.length > 0) return n === "Confirmation" ? "Confirming…" : ("Step " + Services.FaceId.enrollStepNumber + "/3 · " + n)
                            return "Enrolling " + Math.round(Services.FaceId.enrollProgress * 100) + "%"
                        }
                        return (Services.FaceId && Services.FaceId.isEnrolled) ? "Face enrolled" : "No face enrolled"
                    }
                    hint: (Services.FaceId && Services.FaceId.isEnrolling)
                        ? (Services.FaceId.statusMessage || "")
                        : (rootWindow.faceIdEnrollmentNotice.length > 0
                            ? rootWindow.faceIdEnrollmentNotice
                            : ((Services.FaceId && Services.FaceId.isEnrolled) ? ("For " + (Services.OsInfo.username || "user")) : ""))
                    RowLayout {
                        spacing: 6
                        Btn {
                            visible: Services.FaceId && Services.FaceId.isEnrolled && !Services.FaceId.isEnrolling
                            text: "Remove"
                            kind: "danger"
                            onClicked: { if (Services.FaceId) Services.FaceId.clearData() }
                        }
                        Btn {
                            visible: !Services.FaceId || !Services.FaceId.isEnrolling
                            text: (Services.FaceId && Services.FaceId.isEnrolled) ? "Re-enroll" : "Set up"
                            kind: "accent"
                            enabledState: Services.FaceId ? Services.FaceId.isEnabled : true
                            onClicked: {
                                rootWindow.faceIdEnrollmentNotice = ""
                                if (Services.FaceId && Services.FaceId.canEnroll) {
                                    Services.FaceId.startEnroll()
                                } else if (Services.FaceId) {
                                    Services.FaceId.checkStatus()
                                    rootWindow.faceIdEnrollmentNotice = Services.FaceId.enrollBlockReason()
                                }
                            }
                        }
                        Btn {
                            visible: Services.FaceId && Services.FaceId.isEnrolling
                            text: "Cancel"
                            onClicked: { if (Services.FaceId) Services.FaceId.cancelEnroll() }
                        }
                    }
                }
                Rectangle {
                    visible: Services.FaceId && Services.FaceId.isEnrolling
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    height: 3
                    radius: 1.5
                    color: ui.tone(0.12)
                    Rectangle {
                        width: parent.width * (Services.FaceId ? Math.max(0, Math.min(1, Services.FaceId.enrollProgress)) : 0)
                        height: parent.height
                        radius: 1.5
                        color: ui.accent
                        Behavior on width { NumberAnimation { duration: 160 } }
                    }
                }
            }

            SettingsGroup {
                title: "Lock screen"
                OptPick {
                    label: "Clock"
                    model: [
                        { id: "hero", label: "Hero" }, { id: "modern", label: "Modern stacked" },
                        { id: "minimal", label: "Minimal" }, { id: "compact", label: "Compact capsule" },
                        { id: "vertical", label: "Vertical split" }, { id: "typographic", label: "Typographic" },
                        { id: "radial", label: "Radial ring" }, { id: "cyber", label: "Cyber HUD" }
                    ]
                    current: Services.Config ? Services.Config.lockscreenClockStyle : "hero"
                    onPicked: (id) => { if (Services.Config) Services.Config.setLockscreenClockStyle(id) }
                }
                OptSeg {
                    label: "Backdrop"
                    options: [{ id: "sync", label: "Sync desktop" }, { id: "custom", label: "Custom image" }]
                    current: Services.Config ? Services.Config.lockscreenWallpaperMode : "sync"
                    onPicked: (id) => { if (Services.Config) Services.Config.setLockscreenWallpaperMode(id) }
                }
                Block {
                    visible: Services.Config && Services.Config.lockscreenWallpaperMode === "custom"
                    WpStrip {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 54
                        current: {
                            const c = Services.Config ? Services.Config.lockscreenCustomWallpaper : ""
                            return c && c.length > 0 ? c : (Services.Wallpaper ? Services.Wallpaper.currentWallpaper : "")
                        }
                        onChosen: (path) => {
                            if (!Services.Config) return
                            Services.Config.setLockscreenCustomWallpaper(path)
                            Services.Config.setLockscreenWallpaperMode("custom")
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        Btn { text: "Pick file"; onClicked: { if (Services.Wallpaper) Services.Wallpaper.pickLockscreenWallpaper() } }
                    }
                }
                OptSwitch {
                    label: "Blur backdrop"
                    checked: Services.Config ? Services.Config.lockscreenBlur : true
                    onToggled: (v) => { if (Services.Config) Services.Config.setLockscreenBlur(v) }
                }
                OptSlide {
                    label: "Dim"
                    from: 0.1; to: 0.85; step: 0.05; decimals: 2
                    value: Services.Config ? Services.Config.lockscreenDim : 0.45
                    onMoved: (v) => { if (Services.Config) Services.Config.setLockscreenDim(Number(v.toFixed(2))) }
                }
                OptSwitch {
                    label: "Disable password typing"
                    hint: "Hide password input and prevent typing on lock screen"
                    checked: Services.Config ? Services.Config.lockscreenDisablePassword : false
                    onToggled: (v) => { if (Services.Config) Services.Config.setLockscreenDisablePassword(v) }
                }
                OptSeg {
                    visible: !(Services.Config && Services.Config.lockscreenDisablePassword)
                    label: "Input style"
                    options: [{ id: "pill", label: "Pill" }, { id: "underline", label: "Underline" }, { id: "box", label: "Box" }, { id: "dots", label: "Dots" }]
                    current: Services.Config ? Services.Config.lockscreenInputStyle : "pill"
                    onPicked: (id) => { if (Services.Config) Services.Config.setLockscreenInputStyle(id) }
                }
                OptSwitch {
                    label: "Avatar"
                    checked: Services.Config ? Services.Config.lockscreenShowAvatar : true
                    onToggled: (v) => { if (Services.Config) Services.Config.setLockscreenShowAvatar(v) }
                }
                OptSeg {
                    visible: Services.Config ? Services.Config.lockscreenShowAvatar : true
                    label: "Avatar shape"
                    options: [{ id: "circle", label: "Circle" }, { id: "squircle", label: "Squircle" }, { id: "rounded", label: "Rounded" }]
                    current: Services.Config ? Services.Config.lockscreenAvatarShape : "squircle"
                    onPicked: (id) => { if (Services.Config) Services.Config.setLockscreenAvatarShape(id) }
                }
                Block {
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Chip {
                            text: "Avatar ring"
                            on: Services.Config ? Services.Config.lockscreenAvatarRing : false
                            onClicked: { if (Services.Config) Services.Config.setLockscreenAvatarRing(!on) }
                        }
                        Chip {
                            text: "Username"
                            on: Services.Config ? Services.Config.lockscreenShowGreeting : false
                            onClicked: { if (Services.Config) Services.Config.setLockscreenShowGreeting(!on) }
                        }
                        Chip {
                            text: "Status pill"
                            on: Services.Config ? Services.Config.lockscreenShowStatusPill : true
                            onClicked: { if (Services.Config) Services.Config.setLockscreenShowStatusPill(!on) }
                        }
                        Chip {
                            text: "Notifications"
                            on: Services.Config ? Services.Config.lockscreenShowNotifs : false
                            onClicked: { if (Services.Config) Services.Config.setLockscreenShowNotifs(!on) }
                        }
                        Chip {
                            text: "Media player"
                            on: Services.Config ? Services.Config.lockscreenShowMedia : true
                            onClicked: { if (Services.Config) Services.Config.setLockscreenShowMedia(!on) }
                        }
                    }
                }
            }

            SettingsGroup {
                title: "Power"
                OptSeg {
                    label: "Profile"
                    options: [{ id: "power-saver", label: "Saver" }, { id: "balanced", label: "Balanced" }, { id: "performance", label: "Performance" }]
                    current: Services.PowerProfile ? Services.PowerProfile.currentProfile : "balanced"
                    onPicked: (id) => { if (Services.PowerProfile) Services.PowerProfile.setProfile(id) }
                }
                OptSwitch {
                    label: "Low battery warnings"
                    checked: Services.Config ? Services.Config.batteryShowWarnings : true
                    onToggled: (v) => { if (Services.Config) Services.Config.setBatteryShowWarnings(v) }
                }
                OptSlide {
                    label: "Warn below"
                    from: 10; to: 35; step: 5; suffix: "%"
                    value: Services.Config ? Services.Config.batteryLowThreshold : 20
                    onMoved: (v) => { if (Services.Config) Services.Config.setBatteryLowThreshold(Math.round(v)) }
                }
                Opt {
                    label: "Session"
                    RowLayout {
                        spacing: 6
                        Btn { text: "Lock"; onClicked: { rootWindow.hide(); lockSessionProc.running = true } }
                        Btn { text: "Suspend"; onClicked: suspendProc.running = true }
                        ArmBtn { idle: "Reboot"; onConfirmed: rebootProc.running = true }
                        ArmBtn { idle: "Power off"; onConfirmed: poweroffProc.running = true }
                    }
                }
            }

            Item { Layout.preferredHeight: 8 }
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  DISPLAY STAGE · compact drag canvas (math lives in rootWindow.*)
    // ═════════════════════════════════════════════════════════════════════════
    component DisplayStage: Rectangle {
        id: stage
        implicitHeight: 150
        radius: 8
        color: ui.fill
        clip: true

        readonly property real totW: {
            let mx = 0
            const L = rootWindow.dispLocalLayout || []
            for (let i = 0; i < L.length; i++) {
                if (L[i].disabled) continue
                mx = Math.max(mx, (L[i].x || 0) + rootWindow.getDisplayLogWidth(L[i]))
            }
            return Math.max(800, mx)
        }
        readonly property real totH: {
            let mx = 0
            const L = rootWindow.dispLocalLayout || []
            for (let i = 0; i < L.length; i++) {
                if (L[i].disabled) continue
                mx = Math.max(mx, (L[i].y || 0) + rootWindow.getDisplayLogHeight(L[i]))
            }
            return Math.max(600, mx)
        }
        readonly property real sc: {
            const aw = stage.width - 40
            const ah = stage.height - 40
            if (aw <= 0 || ah <= 0) return 0.1
            return Math.min(aw / totW, ah / totH, 0.35)
        }
        readonly property real ox: Math.max(14, (stage.width - totW * sc) / 2)
        readonly property real oy: Math.max(14, (stage.height - totH * sc) / 2)

        Rectangle {
            visible: rootWindow.dispShowSnapGuideX
            x: rootWindow.dispSnapGuideX
            width: 1; height: parent.height
            color: ui.accent
            z: 90
        }
        Rectangle {
            visible: rootWindow.dispShowSnapGuideY
            y: rootWindow.dispSnapGuideY
            height: 1; width: parent.width
            color: ui.accent
            z: 90
        }
        Text {
            visible: rootWindow.dispIsDragging && rootWindow.dispDockMessage.length > 0
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: 6
            text: rootWindow.dispDockMessage
            font.pixelSize: 10
            color: ui.accent
            z: 95
        }
        Text {
            visible: !rootWindow.dispLocalLayout || rootWindow.dispLocalLayout.length === 0
            anchors.centerIn: parent
            text: "No displays detected"
            font.pixelSize: 11
            color: ui.faint
        }

        Repeater {
            model: rootWindow.dispLocalLayout
            delegate: Item {
                id: mb
                required property var modelData
                required property int index
                readonly property bool isSel: rootWindow.dispSelectedMonitorName === mb.modelData.name
                property bool dragged: false
                property real dvx: 0
                property real dvy: 0

                width: Math.max(58, rootWindow.getDisplayLogWidth(mb.modelData) * stage.sc)
                height: Math.max(36, rootWindow.getDisplayLogHeight(mb.modelData) * stage.sc)
                x: mb.dragged ? mb.dvx : stage.ox + mb.modelData.x * stage.sc
                y: mb.dragged ? mb.dvy : stage.oy + mb.modelData.y * stage.sc
                z: mb.dragged ? 100 : (mb.isSel ? 20 : 10)
                Behavior on x { enabled: !mb.dragged; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Behavior on y { enabled: !mb.dragged; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.fill: parent
                    radius: 5
                    color: mb.isSel ? ui.wash(0.16) : ui.tone(0.08)
                    border.width: mb.isSel ? 1.5 : 1
                    border.color: mb.isSel ? ui.accent : ui.tone(0.2)
                    opacity: mb.modelData.disabled ? 0.4 : 1.0
                    scale: mb.dragged ? 1.03 : 1.0
                    Column {
                        anchors.centerIn: parent
                        spacing: 1
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: mb.modelData.name + (mb.modelData.focused ? " ★" : "")
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: mb.isSel ? ui.accent : ui.fg
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: mb.modelData.width + "×" + mb.modelData.height
                            font.family: Services.Theme.fontMono
                            font.pixelSize: 9
                            color: ui.dim
                        }
                    }
                }

                MouseArea {
                    id: mbMa
                    anchors.fill: parent
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    property real gox: 0
                    property real goy: 0
                    onPressed: (m) => {
                        rootWindow.dispSelectedMonitorName = mb.modelData.name
                        rootWindow.dispIsDragging = true
                        mb.dragged = true
                        gox = m.x; goy = m.y
                        mb.dvx = mb.x; mb.dvy = mb.y
                    }
                    onPositionChanged: (m) => {
                        if (!pressed) return
                        const p = mapToItem(stage, m.x, m.y)
                        let rx = Math.max(6, Math.min(stage.width - mb.width - 6, p.x - gox))
                        let ry = Math.max(6, Math.min(stage.height - mb.height - 6, p.y - goy))
                        if (rootWindow.dispLocalLayout.length > 1) {
                            const s = rootWindow.calcDisplaySnap(mb.index, rx, ry, mb.width, mb.height, stage.ox, stage.oy, stage.sc)
                            mb.dvx = s.snappedStageX
                            mb.dvy = s.snappedStageY
                            rootWindow.dispSnapGuideX = s.guideX
                            rootWindow.dispShowSnapGuideX = s.hasGuideX
                            rootWindow.dispSnapGuideY = s.guideY
                            rootWindow.dispShowSnapGuideY = s.hasGuideY
                            rootWindow.dispDockMessage = s.dockMessage
                        } else {
                            mb.dvx = rx; mb.dvy = ry
                        }
                    }
                    function finish(commit) {
                        rootWindow.dispIsDragging = false
                        rootWindow.dispShowSnapGuideX = false
                        rootWindow.dispShowSnapGuideY = false
                        rootWindow.dispDockMessage = ""
                        if (commit && rootWindow.dispLocalLayout.length > 1)
                            rootWindow.commitDisplayDrop(mb.index, mb.dvx, mb.dvy, stage.ox, stage.oy, stage.sc)
                        mb.dragged = false
                    }
                    onReleased: finish(true)
                    onCanceled: finish(false)
                }
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  PAGE 5 · COMPOSITOR
    // ═════════════════════════════════════════════════════════════════════════
    Component {
        id: pgComp

        ColumnLayout {
            id: tab5
            spacing: 0

            // ── Hero / Status Header Card ─────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 8
                Layout.preferredHeight: 52
                radius: ui.r + 2
                color: ui.fill
                border.width: 1
                border.color: ui.line

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 12

                    Rectangle {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        Layout.alignment: Qt.AlignVCenter
                        radius: ui.r
                        color: ui.accent

                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.display || "󰍹"
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 16
                            color: ui.onAccent
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 1
                        Layout.alignment: Qt.AlignVCenter

                        RowLayout {
                            spacing: 6
                            Text {
                                text: Services.Compositor ? Services.Compositor.activeDisplayName : "Hyprland"
                                font.pixelSize: 13
                                font.weight: Font.SemiBold
                                color: ui.fg
                            }
                            Tag {
                                text: (Services.Compositor && Services.Compositor.configType ? Services.Compositor.configType.toUpperCase() : "CONF") + " CONFIG"
                                tint: ui.accent
                            }
                        }

                        Text {
                            text: {
                                const v = Services.Compositor ? Services.Compositor.activeVersion : ""
                                const cleanV = v.split(" built")[0].replace(/^hyprland\s*/i, "").trim()
                                return (cleanV ? ("v" + cleanV + " · ") : "") + "Wayland Session"
                            }
                            font.pixelSize: 10
                            color: ui.dim
                            elide: Text.ElideRight
                        }
                    }

                    Tag {
                        text: {
                            const c = Services.Compositor ? Services.Compositor.workspacesCount : 1
                            return c + (c > 1 ? " Workspaces" : " Workspace")
                        }
                    }

                    Btn {
                        glyph: Services.Icons.refresh || "↻"
                        text: "Reload"
                        onClicked: { if (Services.Compositor) Services.Compositor.reloadCompositor() }
                    }
                }
            }

            RowLayout {
                Layout.topMargin: 10
                Seg {
                    options: [
                        { id: 0, label: "Appearance" }, { id: 1, label: "Displays" }, { id: 2, label: "Input" },
                        { id: 3, label: "Power" }, { id: 4, label: "Autostart" }
                    ]
                    current: rootWindow.compSubTab
                    onPicked: (id) => {
                        rootWindow.compSubTab = id
                        if (id === 4 && Services.Compositor) Services.Compositor.loadAutostart()
                    }
                }
                Item { Layout.fillWidth: true }
            }

            // ── 0 · APPEARANCE ──
            ColumnLayout {
                visible: rootWindow.compSubTab === 0
                Layout.fillWidth: true
                spacing: 0

                SettingsGroup {
                    title: "Compositor Presets"
                    OptSeg {
                        label: "Style profile"
                        options: [
                            { id: "glass", label: "Glass" },
                            { id: "material", label: "Material" },
                            { id: "minimal", label: "Minimal" },
                            { id: "gaming", label: "Gaming" }
                        ]
                        current: Services.Compositor ? Services.Compositor.activePreset : "custom"
                        onPicked: (id) => { if (Services.Compositor) Services.Compositor.applyPreset(id) }
                    }
                }

                SettingsGroup {
                    title: "Window animation"
                    OptSwitch {
                        label: "Animations"
                        checked: Services.Compositor ? Services.Compositor.hyprAnim : true
                        onToggled: { if (Services.Compositor) Services.Compositor.toggleHyprAnim() }
                    }
                    OptPick {
                        label: "Preset"
                        model: (Services.Compositor && Services.Compositor.hyprAnimStyles && Services.Compositor.hyprAnimStyles.length > 0)
                            ? Services.Compositor.hyprAnimStyles.map(function(s) { return { id: s.id, label: s.name } })
                            : [{ id: "fluid", label: "Fluid" }, { id: "snappy", label: "Snappy" }, { id: "bouncy", label: "Bouncy" }, { id: "gentle", label: "Gentle" }, { id: "linear", label: "Linear" }, { id: "disabled", label: "Disabled" }]
                        current: Services.Compositor ? Services.Compositor.hyprAnimStyle : "fluid"
                        onPicked: (id) => { if (Services.Compositor) Services.Compositor.setHyprAnimStyle(id) }
                    }
                }

                SettingsGroup {
                    title: "Workspace transitions"
                    OptSwitch {
                        label: "Animate"
                        checked: Services.Compositor ? Services.Compositor.hyprWorkspaceAnim : true
                        onToggled: { if (Services.Compositor) Services.Compositor.toggleWorkspaceAnim() }
                    }
                    OptPick {
                        label: "Effect"
                        model: [
                            { id: "slidevert", label: "Vertical slide" }, { id: "slide", label: "Horizontal slide" },
                            { id: "slidefade", label: "Slide & fade" }, { id: "slidefadevert", label: "Vertical slide & fade" },
                            { id: "fade", label: "Crossfade" }
                        ]
                        current: Services.Compositor ? Services.Compositor.hyprWorkspaceAnimStyle : "slidevert"
                        onPicked: (id) => { if (Services.Compositor) Services.Compositor.setWorkspaceAnimStyle(id) }
                    }
                    OptPick {
                        label: "Easing"
                        model: (Services.Compositor && Services.Compositor.availableBeziers && Services.Compositor.availableBeziers.length > 0)
                            ? Services.Compositor.availableBeziers.map(function(b) { return { id: b, label: b } })
                            : [{ id: "quick", label: "quick" }, { id: "overshoot", label: "overshoot" }, { id: "easeOutQuint", label: "easeOutQuint" }, { id: "easeInOutCubic", label: "easeInOutCubic" }, { id: "almostLinear", label: "almostLinear" }, { id: "linear", label: "linear" }, { id: "default", label: "default" }]
                        current: Services.Compositor ? Services.Compositor.hyprWorkspaceAnimBezier : "quick"
                        onPicked: (id) => { if (Services.Compositor) Services.Compositor.setWorkspaceAnimBezier(id) }
                    }
                    OptSlide {
                        label: "Speed"
                        from: 1; to: 10; step: 0.5; decimals: 1; suffix: "x"
                        value: Services.Compositor ? Services.Compositor.hyprWorkspaceAnimSpeed : 2.0
                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setWorkspaceAnimSpeed(v) }
                    }
                }

                SettingsGroup {
                    title: "Blur & shadow"
                    OptSwitch {
                        label: "Blur"
                        checked: Services.Compositor ? Services.Compositor.hyprBlur : true
                        onToggled: { if (Services.Compositor) Services.Compositor.toggleHyprBlur() }
                    }
                    OptSlide {
                        label: "Blur radius"
                        from: 1; to: 16; step: 1; suffix: "px"
                        value: Services.Compositor ? Services.Compositor.hyprBlurSize : 4
                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprBlurSize(Math.round(v)) }
                    }
                    OptSlide {
                        label: "Blur passes"
                        from: 1; to: 5; step: 1; suffix: "x"
                        value: Services.Compositor ? Services.Compositor.hyprBlurPasses : 2
                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprBlurPasses(Math.round(v)) }
                    }
                    OptSwitch {
                        label: "Drop shadows"
                        checked: Services.Compositor ? Services.Compositor.hyprShadow : true
                        onToggled: { if (Services.Compositor) Services.Compositor.toggleHyprShadow() }
                    }
                    OptSlide {
                        label: "Shadow range"
                        from: 0; to: 30; step: 1; suffix: "px"
                        value: Services.Compositor ? Services.Compositor.hyprShadowRange : 4
                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprShadowRange(Math.round(v)) }
                    }
                }

                SettingsGroup {
                    title: "Opacity & Dimming"
                    OptSlide {
                        label: "Active window"
                        from: 0.5; to: 1.0; step: 0.01; decimals: 2
                        value: Services.Compositor ? Services.Compositor.hyprActiveOpacity : 0.9
                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprActiveOpacity(Number(v.toFixed(2))) }
                    }
                    OptSlide {
                        label: "Inactive window"
                        from: 0.5; to: 1.0; step: 0.01; decimals: 2
                        value: Services.Compositor ? Services.Compositor.hyprInactiveOpacity : 0.95
                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprInactiveOpacity(Number(v.toFixed(2))) }
                    }
                    OptSwitch {
                        label: "Dim inactive"
                        hint: "Dim unfocused windows to direct visual focus"
                        checked: Services.Compositor ? Services.Compositor.hyprDimInactive : false
                        onToggled: { if (Services.Compositor) Services.Compositor.toggleHyprDimInactive() }
                    }
                    OptSlide {
                        visible: Services.Compositor ? Services.Compositor.hyprDimInactive : false
                        label: "Dim strength"
                        from: 0.1; to: 1.0; step: 0.05; decimals: 2
                        value: Services.Compositor ? Services.Compositor.hyprDimStrength : 0.5
                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprDimStrength(Number(v.toFixed(2))) }
                    }
                }

                SettingsGroup {
                    title: "Geometry"
                    OptSlide {
                        label: "Corner radius"
                        from: 0; to: 28; step: 1; suffix: "px"
                        value: Services.Compositor ? Services.Compositor.hyprRounding : 10
                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprRounding(Math.round(v)) }
                    }
                    OptSlide {
                        label: "Border"
                        from: 0; to: 6; step: 1; suffix: "px"
                        value: Services.Compositor ? Services.Compositor.hyprBorderSize : 0
                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprBorderSize(Math.round(v)) }
                    }
                    OptSlide {
                        label: "Gaps in"
                        from: 0; to: 24; step: 1; suffix: "px"
                        value: Services.Compositor ? Services.Compositor.hyprGapsIn : 5
                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprGapsIn(Math.round(v)) }
                    }
                    OptSlide {
                        label: "Gaps out"
                        from: 0; to: 36; step: 1; suffix: "px"
                        value: Services.Compositor ? Services.Compositor.hyprGapsOut : 10
                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprGapsOut(Math.round(v)) }
                    }
                    OptSwitch {
                        label: "Smart gaps"
                        hint: "No gaps or borders with a single window"
                        checked: Services.Compositor ? Services.Compositor.hyprSmartGaps : false
                        onToggled: { if (Services.Compositor) Services.Compositor.toggleHyprSmartGaps() }
                    }
                }

                SettingsGroup {
                    title: "Layout"
                    OptSeg {
                        label: "Engine"
                        options: (Services.Compositor && Services.Compositor.activeCompositor === "niri")
                            ? [{ id: "scrolling", label: "Scrolling" }]
                            : [{ id: "dwindle", label: "Dwindle" }, { id: "master", label: "Master" }, { id: "scrolling", label: "Scrolling" }]
                        current: Services.Compositor ? Services.Compositor.hyprLayout : "dwindle"
                        onPicked: (id) => { if (Services.Compositor) Services.Compositor.setHyprLayout(id) }
                    }
                    OptSlide {
                        visible: Services.Compositor && (Services.Compositor.hyprLayout === "scrolling" || Services.Compositor.activeCompositor === "niri")
                        label: "Column width"
                        from: 0.3; to: 1.0; step: 0.01; decimals: 2
                        value: Services.Compositor ? Services.Compositor.hyprScrollingColumnWidth : 0.89
                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprScrollingColumnWidth(Number(v.toFixed(2))) }
                    }
                    OptSwitch {
                        visible: Services.Compositor && (Services.Compositor.hyprLayout === "scrolling" || Services.Compositor.activeCompositor === "niri")
                        label: "Fullscreen single column"
                        checked: Services.Compositor ? Services.Compositor.hyprScrollingFullscreenOnOneColumn : false
                        onToggled: { if (Services.Compositor) Services.Compositor.toggleHyprScrollingFullscreenOnOneColumn() }
                    }
                }
            }

            // ── 1 · DISPLAYS ──
            ColumnLayout {
                visible: rootWindow.compSubTab === 1
                Layout.fillWidth: true
                spacing: 0

                SettingsGroup {
                    title: "Layout"
                    DisplayStage { Layout.fillWidth: true; Layout.preferredHeight: 150 }

                    Block {
                        ruled: false
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: rootWindow.dispLocalLayout
                                delegate: Chip {
                                    required property var modelData
                                    text: modelData.name
                                    on: rootWindow.dispSelectedMonitorName === modelData.name
                                    onClicked: rootWindow.dispSelectedMonitorName = modelData.name
                                }
                            }
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Btn { text: "Identify"; onClicked: { if (Services.Compositor) Services.Compositor.identifyMonitors() } }
                            Btn { text: "Swap"; enabledState: rootWindow.dispLocalLayout.length > 1; onClicked: rootWindow.swapDisplays() }
                            Btn { text: "Row ⇄"; onClicked: rootWindow.autoAlignDisplaysHorizontal() }
                            Btn { text: "Column ⇅"; onClicked: rootWindow.autoAlignDisplaysVertical() }
                            Btn { text: "Revert"; enabledState: rootWindow.dispHasPendingChanges; onClicked: rootWindow.revertDisplayChanges() }
                            Btn { text: rootWindow.dispIsApplying ? "Applying…" : "Apply"; kind: "accent"; enabledState: rootWindow.dispHasPendingChanges && !rootWindow.dispIsApplying; onClicked: rootWindow.applyDisplayLayout(true) }
                        }
                        Text {
                            visible: rootWindow.dispStatusMessage.length > 0
                            text: rootWindow.dispStatusMessage
                            font.pixelSize: 10
                            color: ui.accent
                        }
                    }
                }

                SettingsGroup {
                    title: "Output · " + (rootWindow.currentDisplayMon ? rootWindow.currentDisplayMon.name : "none")
                    OptPick {
                        label: "Mode"
                        minW: 150
                        maxW: 230
                        model: {
                            const list = [{ id: "preferred", label: "Auto" }, { id: "highrr", label: "Max refresh" }, { id: "highres", label: "Max resolution" }]
                            const m = rootWindow.currentDisplayMon
                            if (m && m.availableModes) {
                                for (let i = 0; i < m.availableModes.length; i++) {
                                    const s = String(m.availableModes[i])
                                    list.push({ id: s, label: s.replace("@", " @ ").replace("Hz", " Hz") })
                                }
                            }
                            return list
                        }
                        current: (rootWindow.currentDisplayMon && rootWindow.currentDisplayMon.mode) ? rootWindow.currentDisplayMon.mode : "preferred"
                        onPicked: (id) => rootWindow.updateDisplayProp("mode", id, true)
                    }
                    OptSlide {
                        label: "Scale"
                        from: 0.5; to: 2.5; step: 0.05; decimals: 2; suffix: "x"
                        value: rootWindow.currentDisplayMon ? (rootWindow.currentDisplayMon.scale || 1.0) : 1.0
                        onMoved: (v) => rootWindow.updateDisplayProp("scale", Number(Number(v).toFixed(2)), true)
                    }
                    OptSeg {
                        label: "Rotation"
                        options: [{ id: "0", label: "0°" }, { id: "1", label: "90°" }, { id: "2", label: "180°" }, { id: "3", label: "270°" }]
                        current: rootWindow.currentDisplayMon ? String(rootWindow.currentDisplayMon.transform || 0) : "0"
                        onPicked: (id) => rootWindow.updateDisplayProp("transform", parseInt(id), true)
                    }
                    OptSwitch {
                        label: "Variable refresh (VRR)"
                        checked: rootWindow.currentDisplayMon ? Boolean(rootWindow.currentDisplayMon.vrr) : false
                        onToggled: (v) => rootWindow.updateDisplayProp("vrr", v, true)
                    }
                    OptSwitch {
                        label: "Output enabled"
                        checked: rootWindow.currentDisplayMon ? !Boolean(rootWindow.currentDisplayMon.disabled) : true
                        onToggled: (v) => rootWindow.updateDisplayProp("disabled", !v, true)
                    }
                    OptSwitch {
                        label: "Show bar here"
                        checked: (rootWindow.currentDisplayMon && Services.Config) ? Services.Config.isBarMonitorEnabled(rootWindow.currentDisplayMon.name) : true
                        onToggled: (v) => {
                            if (!rootWindow.currentDisplayMon || !Services.Config) return
                            if (Services.Config.barMonitorMode !== "custom") Services.Config.setBarMonitorMode("custom")
                            Services.Config.setBarMonitor(rootWindow.currentDisplayMon.name, v)
                        }
                    }
                    OptPick {
                        label: "Mirror"
                        minW: 120
                        model: {
                            const list = [{ id: "none", label: "None" }]
                            for (let i = 0; i < rootWindow.dispLocalLayout.length; i++) {
                                const m = rootWindow.dispLocalLayout[i]
                                if (rootWindow.currentDisplayMon && m.name !== rootWindow.currentDisplayMon.name) list.push({ id: m.name, label: m.name })
                            }
                            return list
                        }
                        current: (rootWindow.currentDisplayMon && rootWindow.currentDisplayMon.mirrorOf) ? rootWindow.currentDisplayMon.mirrorOf : "none"
                        onPicked: (id) => rootWindow.updateDisplayProp("mirrorOf", id, true)
                    }
                    Opt {
                        visible: rootWindow.dispLocalLayout.length > 1
                        label: "Dock next to other"
                        RowLayout {
                            spacing: 4
                            Btn { text: "◀"; onClicked: rootWindow.dockSelectedDisplay("left") }
                            Btn { text: "▲"; onClicked: rootWindow.dockSelectedDisplay("top") }
                            Btn { text: "▼"; onClicked: rootWindow.dockSelectedDisplay("bottom") }
                            Btn { text: "▶"; onClicked: rootWindow.dockSelectedDisplay("right") }
                        }
                    }
                    Opt {
                        label: "Offset"
                        hint: "Steps of 50px"
                        RowLayout {
                            spacing: 6
                            Stepper {
                                label: "X"
                                valueText: (rootWindow.currentDisplayMon ? rootWindow.currentDisplayMon.x : 0) + ""
                                onDec: rootWindow.updateDisplayProp("x", Math.max(0, (rootWindow.currentDisplayMon ? rootWindow.currentDisplayMon.x : 0) - 50), true)
                                onInc: rootWindow.updateDisplayProp("x", (rootWindow.currentDisplayMon ? rootWindow.currentDisplayMon.x : 0) + 50, true)
                            }
                            Stepper {
                                label: "Y"
                                valueText: (rootWindow.currentDisplayMon ? rootWindow.currentDisplayMon.y : 0) + ""
                                onDec: rootWindow.updateDisplayProp("y", Math.max(0, (rootWindow.currentDisplayMon ? rootWindow.currentDisplayMon.y : 0) - 50), true)
                                onInc: rootWindow.updateDisplayProp("y", (rootWindow.currentDisplayMon ? rootWindow.currentDisplayMon.y : 0) + 50, true)
                            }
                        }
                    }
                    Opt {
                        label: "Primary"
                        hint: rootWindow.currentDisplayMon
                            ? (rootWindow.currentDisplayMon.description || ((rootWindow.currentDisplayMon.make || "") + " " + (rootWindow.currentDisplayMon.model || "")))
                            : ""
                        Btn {
                            text: (rootWindow.currentDisplayMon && rootWindow.currentDisplayMon.focused) ? "Primary" : "Make primary"
                            kind: (rootWindow.currentDisplayMon && rootWindow.currentDisplayMon.focused) ? "accent" : "plain"
                            enabledState: rootWindow.currentDisplayMon && !rootWindow.currentDisplayMon.focused
                            onClicked: { if (rootWindow.currentDisplayMon) rootWindow.setDisplayAsPrimary(rootWindow.currentDisplayMon.name) }
                        }
                    }
                    Opt {
                        label: "Panel"
                        hint: {
                            const m = rootWindow.currentDisplayMon
                            if (!m) return "-"
                            const pw = m.physicalWidth || 0
                            const ph = m.physicalHeight || 0
                            const diag = Math.sqrt(pw * pw + ph * ph) / 25.4
                            return pw + " × " + ph + " mm" + (diag > 0 ? " · ~" + diag.toFixed(1) + "″" : "")
                        }
                        Tag { text: "WS " + (rootWindow.currentDisplayMon ? rootWindow.currentDisplayMon.activeWorkspace : "-") }
                    }
                }
            }

            // ── 2 · INPUT ──
            ColumnLayout {
                visible: rootWindow.compSubTab === 2
                Layout.fillWidth: true
                spacing: 0

                SettingsGroup {
                    title: "Focus"
                    OptSeg {
                        label: "Follow mouse"
                        options: [{ id: "1", label: "Hover" }, { id: "0", label: "Click" }, { id: "2", label: "Click tiled" }]
                        current: Services.Compositor ? String(Services.Compositor.hyprFollowMouse) : "1"
                        onPicked: (id) => { if (Services.Compositor) Services.Compositor.setHyprFollowMouse(id) }
                    }
                }
                SettingsGroup {
                    title: "Touchpad"
                    OptSwitch {
                        label: "Natural scrolling"
                        checked: Services.Compositor ? Services.Compositor.hyprTouchpadNatural : true
                        onToggled: (v) => { if (Services.Compositor) Services.Compositor.setHyprTouchpadNatural(v) }
                    }
                    OptSwitch {
                        label: "Tap to click"
                        checked: Services.Compositor ? Services.Compositor.hyprTouchpadTap : true
                        onToggled: (v) => { if (Services.Compositor) Services.Compositor.setHyprTouchpadTap(v) }
                    }
                    OptSwitch {
                        label: "Disable while typing"
                        checked: Services.Compositor ? Services.Compositor.hyprTouchpadDwt : true
                        onToggled: (v) => { if (Services.Compositor) Services.Compositor.setHyprTouchpadDwt(v) }
                    }
                    OptSwitch {
                        label: "3-finger workspace swipe"
                        checked: Services.Compositor ? Services.Compositor.hyprWorkspaceSwipe : true
                        onToggled: (v) => { if (Services.Compositor) Services.Compositor.setHyprWorkspaceSwipe(v) }
                    }
                    OptSlide {
                        label: "Sensitivity"
                        from: -1; to: 1; step: 0.05; decimals: 2
                        value: Services.Compositor ? Services.Compositor.hyprSensitivity : 0
                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprSensitivity(Number(v.toFixed(2))) }
                    }
                }
            }

            // ── 3 · POWER & GAMING ──
            ColumnLayout {
                visible: rootWindow.compSubTab === 3
                Layout.fillWidth: true
                spacing: 0

                SettingsGroup {
                    title: "Performance"
                    OptSwitch {
                        label: "Variable frame rate"
                        hint: "Render less when the screen is static"
                        checked: Services.Compositor ? Services.Compositor.hyprVFR : true
                        onToggled: { if (Services.Compositor) Services.Compositor.toggleHyprVFR() }
                    }
                    OptSwitch {
                        label: "Allow tearing"
                        hint: "Lower input lag in games"
                        checked: Services.Compositor ? Services.Compositor.hyprAllowTearing : false
                        onToggled: { if (Services.Compositor) Services.Compositor.toggleHyprTearing() }
                    }
                    OptSwitch {
                        label: "Resize on border"
                        checked: Services.Compositor ? Services.Compositor.hyprResizeOnBorder : false
                        onToggled: { if (Services.Compositor) Services.Compositor.toggleHyprResizeBorder() }
                    }
                    OptSwitch {
                        label: "Hide Hyprland logo"
                        checked: Services.Compositor ? Services.Compositor.hyprDisableLogo : false
                        onToggled: { if (Services.Compositor) Services.Compositor.toggleHyprDisableLogo() }
                    }
                }
            }

            // ── 4 · AUTOSTART ──
            ColumnLayout {
                id: subTab4
                visible: rootWindow.compSubTab === 4
                Layout.fillWidth: true
                spacing: 0

                property string search: ""
                property bool isAdding: false
                property string newCmd: ""
                property string newType: "exec-once"
                property string selectedPreset: ""

                                readonly property var recommendedPresets: [
                                    { id: "cliphist-text", name: "Clipboard Text", desc: "Save copy history for text and snippets", icon: "󰅍", cmd: "wl-paste --type text --watch cliphist store" },
                                    { id: "cliphist-img",  name: "Clipboard Images/Screenshots", desc: "Save screenshots and copied images in history", icon: "󰄄", cmd: "wl-paste --type image --watch cliphist store" },
                                    { id: "polkit",        name: "Polkit Agent",   desc: "System authentication privilege agent", icon: "󰌋", cmd: "systemctl enable --now --user hyprpolkitagent" },
                                    { id: "wallpaper",     name: "Wallpaper Engine", desc: "Desktop background wallpaper service", icon: "󰸉", cmd: "awww-daemon" },
                                    { id: "hypridle",      name: "Hypridle Daemon", desc: "Idle screen locking & power timeout", icon: "󰒲", cmd: "hypridle" },
                                    { id: "nm-applet",     name: "Network Applet", desc: "System tray Wi-Fi and network icon", icon: "󰤨", cmd: "nm-applet --indicator" },
                                    { id: "blueman",       name: "Bluetooth Applet", desc: "System tray Bluetooth device manager", icon: "󰂯", cmd: "blueman-applet" },
                                    { id: "spotify",       name: "Spotify",        desc: "Launch music player on login", icon: "󰓇", cmd: "spotify" },
                                    { id: "discord",       name: "Discord / Vesktop", desc: "Launch chat platform on login", icon: "󰙯", cmd: "vesktop --start-minimized" }
                                ]

                                function isPresetConfigured(presetCmd) {
                                    if (!Services.Compositor || !Services.Compositor.autostartList) return false
                                    const pLow = presetCmd.toLowerCase().trim()
                                    if (pLow.includes("wl-paste") && pLow.includes("image")) {
                                        return Services.Compositor.autostartList.some(item => {
                                            const cmd = (item.command || "").toLowerCase()
                                            return cmd.includes("wl-paste") && cmd.includes("image") && cmd.includes("cliphist") && item.enabled
                                        })
                                    }
                                    if (pLow.includes("wl-paste") && pLow.includes("text")) {
                                        return Services.Compositor.autostartList.some(item => {
                                            const cmd = (item.command || "").toLowerCase()
                                            return cmd.includes("wl-paste") && cmd.includes("text") && cmd.includes("cliphist") && item.enabled
                                        })
                                    }
                                    const cleanP = pLow.split(" ")[0].trim()
                                    return Services.Compositor.autostartList.some(item => {
                                        return item.command && item.command.toLowerCase().includes(cleanP) && item.enabled
                                    })
                                }

                                // ── Top Toolbar: Search + Stats + Add Button ────────

                readonly property var essentials: recommendedPresets.filter(function(p) { return p.id !== "spotify" && p.id !== "discord" })
                readonly property var items: {
                    const list = (Services.Compositor && Services.Compositor.autostartList) ? Services.Compositor.autostartList : []
                    const q = subTab4.search.toLowerCase().trim()
                    if (!q) return list
                    return list.filter(function(it) {
                        return (it.name && it.name.toLowerCase().includes(q)) ||
                               (it.command && it.command.toLowerCase().includes(q)) ||
                               (it.desc && it.desc.toLowerCase().includes(q)) ||
                               (it.fileName && it.fileName.toLowerCase().includes(q))
                    })
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 10
                    spacing: 6
                    Inp {
                        Layout.fillWidth: true
                        placeholder: "Search startup entries"
                        onEdited: (v) => { subTab4.search = v }
                    }
                    Btn {
                        glyph: Services.Icons.refresh || "↻"
                        onClicked: { if (Services.Compositor) Services.Compositor.loadAutostart() }
                    }
                    Btn {
                        glyph: subTab4.isAdding ? "✕" : (Services.Icons.plus || "+")
                        text: subTab4.isAdding ? "Close" : "Add"
                        kind: subTab4.isAdding ? "plain" : "accent"
                        onClicked: { subTab4.isAdding = !subTab4.isAdding; subTab4.newCmd = ""; subTab4.selectedPreset = "" }
                    }
                }

                Block {
                    visible: subTab4.isAdding
                    ruled: false
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: subTab4.recommendedPresets
                            delegate: Chip {
                                required property var modelData
                                text: modelData.name
                                glyph: modelData.icon
                                on: subTab4.selectedPreset === modelData.id
                                onClicked: { subTab4.selectedPreset = modelData.id; subTab4.newCmd = modelData.cmd }
                            }
                        }
                    }
                    Inp {
                        Layout.fillWidth: true
                        mono: true
                        placeholder: "command to run"
                        text: subTab4.newCmd
                        onEdited: (v) => { subTab4.newCmd = v; subTab4.selectedPreset = "" }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Seg {
                            options: [{ id: "exec-once", label: "exec-once" }, { id: "exec", label: "exec" }]
                            current: subTab4.newType
                            onPicked: (id) => { subTab4.newType = id }
                        }
                        Item { Layout.fillWidth: true }
                        Btn {
                            text: "Add to startup"
                            kind: "accent"
                            enabledState: subTab4.newCmd.trim().length > 0
                            onClicked: {
                                if (Services.Compositor) Services.Compositor.addAutostart(subTab4.newCmd.trim(), subTab4.newType)
                                subTab4.newCmd = ""
                                subTab4.selectedPreset = ""
                                subTab4.isAdding = false
                            }
                        }
                    }
                }

                SettingsGroup {
                    title: "Essentials"
                    Block {
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: subTab4.essentials
                                delegate: Chip {
                                    required property var modelData
                                    readonly property bool conf: subTab4.isPresetConfigured(modelData.cmd)
                                    text: modelData.name
                                    glyph: conf ? (Services.Icons.check || "✓") : "+"
                                    on: conf
                                    onClicked: { if (!conf && Services.Compositor) Services.Compositor.addAutostart(modelData.cmd, "exec-once") }
                                }
                            }
                        }
                    }
                }

                SettingsGroup {
                    title: "Startup entries (" + subTab4.items.length + ")"
                    Text {
                        visible: subTab4.items.length === 0
                        Layout.leftMargin: 4
                        Layout.topMargin: 6
                        text: subTab4.search.length > 0 ? "No entries match" : "No startup entries found"
                        font.pixelSize: 11
                        color: ui.faint
                    }
                    Repeater {
                        model: subTab4.items
                        delegate: Opt {
                            id: au
                            required property var modelData
                            label: au.modelData.name || au.modelData.command
                            hint: au.modelData.command
                            opacity: au.modelData.enabled ? 1.0 : 0.55
                            RowLayout {
                                spacing: 6
                                Tag { text: au.modelData.type || "exec-once"; tint: ui.accent }
                                Tag { text: (au.modelData.fileName || "config") + ":" + (au.modelData.line || "") }
                                Btn { glyph: "▶"; onClicked: { if (Services.Compositor) Services.Compositor.runAutostart(au.modelData.command) } }
                                Tgl {
                                    on: au.modelData.enabled
                                    onFlipped: (v) => { if (Services.Compositor) Services.Compositor.toggleAutostart(au.modelData.file, au.modelData.line, v) }
                                }
                                Btn {
                                    glyph: Services.Icons.trash || "✕"
                                    kind: "danger"
                                    onClicked: { if (Services.Compositor) Services.Compositor.deleteAutostart(au.modelData.file, au.modelData.line) }
                                }
                            }
                        }
                    }
                }
            }

            Item { Layout.preferredHeight: 8 }
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  PAGE 6 · KEYBINDINGS
    // ═════════════════════════════════════════════════════════════════════════
    Component {
        id: pgKeys

        ColumnLayout {
            id: tab6
            spacing: 0

                            property string addCategoryType: "shell" // "shell", "compositor", "apps", "custom"
                            property int currentPage: 0
                            property int itemsPerPage: 9

                            readonly property var allBinds: (Services.Compositor ? Services.Compositor.keybindsList : []) || []
                            readonly property int totalBindsCount: allBinds.length
                            readonly property int repeatBindsCount: allBinds.filter(k => Boolean(k.repeat)).length
                            readonly property int lockedBindsCount: allBinds.filter(k => Boolean(k.locked)).length
                            readonly property int mouseBindsCount: allBinds.filter(k => Boolean(k.mouse)).length

                            onFilteredBindsChanged: {
                                if (currentPage >= totalPages) currentPage = Math.max(0, totalPages - 1)
                            }

                            readonly property var actionCategories: [
                                { id: "all",         label: "All Actions & Dispatchers" },
                                { id: "shell",       label: "Quickshell Features" },
                                { id: "comp_window", label: "Compositor: Window Control" },
                                { id: "comp_nav",    label: "Compositor: Focus & Navigation" },
                                { id: "comp_move",   label: "Compositor: Move & Swap Windows" },
                                { id: "comp_resize", label: "Compositor: Resize & Layout" },
                                { id: "comp_work",   label: "Compositor: Workspaces (1–10)" },
                                { id: "comp_mon",    label: "Compositor: Monitors & Session" },
                                { id: "media",       label: "Media, Volume & Hardware" },
                                { id: "apps",        label: "Launch Applications" },
                                { id: "custom",      label: "Custom Shell Command" }
                            ]

                            readonly property var shellActions: [
                                { id: "qs ipc call launcher toggle",        label: "App Launcher",               desc: "Toggle application search & launcher",       defaultRepeat: false, defaultLocked: false },
                                { id: "qs ipc call dashboard toggle",       label: "Dashboard & Control Center", desc: "Toggle quick control center and widgets",    defaultRepeat: false, defaultLocked: false },
                                { id: "qs ipc call powermenu toggle",       label: "Power Menu",                 desc: "Toggle power, sleep, and session menu",      defaultRepeat: false, defaultLocked: true },
                                { id: "qs ipc call clipboard toggle",       label: "Clipboard Manager",          desc: "Toggle clipboard history manager",           defaultRepeat: false, defaultLocked: false },
                                { id: "qs ipc call lockscreen toggle",      label: "Lock Screen",                desc: "Lock session immediately",                   defaultRepeat: false, defaultLocked: true },
                                { id: "qs ipc call settings toggle",        label: "Settings Panel",             desc: "Toggle Quickshell system settings",          defaultRepeat: false, defaultLocked: false },
                                { id: "qs ipc call notifications toggle",   label: "Notification Center",        desc: "Toggle notification history panel",          defaultRepeat: false, defaultLocked: false },
                                { id: "qs ipc call wallpaper toggle",       label: "Wallpaper Selector",         desc: "Open wallpaper picker",                      defaultRepeat: false, defaultLocked: false },
                                { id: "qs ipc call emoji toggle",           label: "Emoji Picker",               desc: "Open emoji selection drawer",               defaultRepeat: false, defaultLocked: false },
                                { id: "~/.config/quickshell/scripts/screenshot.sh region", label: "Screenshot: Selected Area", desc: "Capture selected area to clipboard & file", defaultRepeat: false, defaultLocked: true },
                                { id: "~/.config/quickshell/scripts/screenshot.sh full",   label: "Screenshot: Full Screen",    desc: "Capture entire desktop screenshot",        defaultRepeat: false, defaultLocked: true }
                            ]

                            readonly property var compWindowActions: [
                                { id: "killactive",           label: "Close Active Window (killactive)",           desc: "Close the currently focused window",       defaultRepeat: false, defaultLocked: false },
                                { id: "togglefloating",       label: "Toggle Floating / Tiling (togglefloating)",  desc: "Switch active window between tile & float", defaultRepeat: false, defaultLocked: false },
                                { id: "fullscreen 0",         label: "Toggle Fullscreen (fullscreen 0)",           desc: "Toggle true fullscreen mode",              defaultRepeat: false, defaultLocked: false },
                                { id: "fullscreen 1",         label: "Toggle Maximize (fullscreen 1)",             desc: "Maximize window keeping bar & panels",     defaultRepeat: false, defaultLocked: false },
                                { id: "pin",                  label: "Pin Window to All Workspaces (pin)",         desc: "Show active floating window on all workspaces", defaultRepeat: false, defaultLocked: false },
                                { id: "centerwindow",         label: "Center Floating Window (centerwindow)",     desc: "Center active floating window on screen",  defaultRepeat: false, defaultLocked: false },
                                { id: "togglegroup",          label: "Toggle Window Group / Tabs (togglegroup)",   desc: "Combine or ungroup windows into tabs",     defaultRepeat: false, defaultLocked: false },
                                { id: "changegroupactive f",  label: "Next Tab in Group (changegroupactive f)",    desc: "Switch to next window in group",           defaultRepeat: true,  defaultLocked: false },
                                { id: "changegroupactive b",  label: "Prev Tab in Group (changegroupactive b)",    desc: "Switch to previous window in group",       defaultRepeat: true,  defaultLocked: false },
                                { id: "movewindoworgroup l",  label: "Move Window/Group Left",                     desc: "Move window or group leftwards",           defaultRepeat: false, defaultLocked: false },
                                { id: "movewindoworgroup r",  label: "Move Window/Group Right",                    desc: "Move window or group rightwards",          defaultRepeat: false, defaultLocked: false }
                            ]

                            readonly property var compNavActions: [
                                { id: "movefocus l",       label: "Focus Window Left (movefocus l)",       desc: "Move keyboard focus to window on left",   defaultRepeat: false, defaultLocked: false },
                                { id: "movefocus r",       label: "Focus Window Right (movefocus r)",      desc: "Move keyboard focus to window on right",  defaultRepeat: false, defaultLocked: false },
                                { id: "movefocus u",       label: "Focus Window Up (movefocus u)",         desc: "Move keyboard focus to window above",     defaultRepeat: false, defaultLocked: false },
                                { id: "movefocus d",       label: "Focus Window Down (movefocus d)",       desc: "Move keyboard focus to window below",     defaultRepeat: false, defaultLocked: false },
                                { id: "cyclenext",         label: "Cycle Focus Next (cyclenext)",          desc: "Focus next window in current workspace",  defaultRepeat: true,  defaultLocked: false },
                                { id: "cyclenext prev",    label: "Cycle Focus Previous (cyclenext prev)", desc: "Focus previous window in workspace",      defaultRepeat: true,  defaultLocked: false }
                            ]

                            readonly property var compMoveActions: [
                                { id: "swapwindow l",  label: "Swap Window Left (swapwindow l)",   desc: "Swap position with window to the left",  defaultRepeat: false, defaultLocked: false },
                                { id: "swapwindow r",  label: "Swap Window Right (swapwindow r)",  desc: "Swap position with window to the right", defaultRepeat: false, defaultLocked: false },
                                { id: "swapwindow u",  label: "Swap Window Up (swapwindow u)",     desc: "Swap position with window above",        defaultRepeat: false, defaultLocked: false },
                                { id: "swapwindow d",  label: "Swap Window Down (swapwindow d)",   desc: "Swap position with window below",        defaultRepeat: false, defaultLocked: false },
                                { id: "movewindow l",  label: "Move Window Left (movewindow l)",   desc: "Move active window leftwards",           defaultRepeat: false, defaultLocked: false },
                                { id: "movewindow r",  label: "Move Window Right (movewindow r)",  desc: "Move active window rightwards",          defaultRepeat: false, defaultLocked: false },
                                { id: "movewindow u",  label: "Move Window Up (movewindow u)",     desc: "Move active window upwards",             defaultRepeat: false, defaultLocked: false },
                                { id: "movewindow d",  label: "Move Window Down (movewindow d)",   desc: "Move active window downwards",           defaultRepeat: false, defaultLocked: false }
                            ]

                            readonly property var compResizeActions: [
                                { id: "resizeactive 25 0",    label: "Resize: Expand Width (+25px)",                 desc: "Grow active window width",                 defaultRepeat: true, defaultLocked: false },
                                { id: "resizeactive -25 0",   label: "Resize: Shrink Width (-25px)",                 desc: "Shrink active window width",               defaultRepeat: true, defaultLocked: false },
                                { id: "resizeactive 0 25",    label: "Resize: Expand Height (+25px)",                desc: "Grow active window height",                defaultRepeat: true, defaultLocked: false },
                                { id: "resizeactive 0 -25",   label: "Resize: Shrink Height (-25px)",                desc: "Shrink active window height",              defaultRepeat: true, defaultLocked: false },
                                { id: "togglesplit",          label: "Toggle Split Orientation (togglesplit)",       desc: "Toggle split orientation between H and V", defaultRepeat: false, defaultLocked: false },
                                { id: "pseudo",               label: "Toggle Pseudo-tiling (pseudo)",                desc: "Keep window floating size while tiled",    defaultRepeat: false, defaultLocked: false },
                                { id: "layoutmsg swapsplit",  label: "Swap Split Branches (layoutmsg swapsplit)",    desc: "Swap tree branches in layout",             defaultRepeat: false, defaultLocked: false }
                            ]

                            readonly property var compWorkspaceActions: [
                                { id: "workspace e+1",              label: "Next Workspace (workspace e+1)",               desc: "Switch to next workspace",               defaultRepeat: true,  defaultLocked: false },
                                { id: "workspace e-1",              label: "Prev Workspace (workspace e-1)",               desc: "Switch to previous workspace",           defaultRepeat: true,  defaultLocked: false },
                                { id: "togglespecialworkspace",     label: "Toggle Scratchpad (togglespecialworkspace)",   desc: "Show or hide dropdown scratchpad",       defaultRepeat: false, defaultLocked: false },
                                { id: "movetoworkspace special",    label: "Send to Scratchpad (movetoworkspace special)", desc: "Move active window into scratchpad",    defaultRepeat: false, defaultLocked: false },
                                { id: "workspace 1",                label: "Switch to Workspace 1",                        desc: "Jump directly to workspace 1",           defaultRepeat: false, defaultLocked: false },
                                { id: "workspace 2",                label: "Switch to Workspace 2",                        desc: "Jump directly to workspace 2",           defaultRepeat: false, defaultLocked: false },
                                { id: "workspace 3",                label: "Switch to Workspace 3",                        desc: "Jump directly to workspace 3",           defaultRepeat: false, defaultLocked: false },
                                { id: "workspace 4",                label: "Switch to Workspace 4",                        desc: "Jump directly to workspace 4",           defaultRepeat: false, defaultLocked: false },
                                { id: "workspace 5",                label: "Switch to Workspace 5",                        desc: "Jump directly to workspace 5",           defaultRepeat: false, defaultLocked: false },
                                { id: "workspace 6",                label: "Switch to Workspace 6",                        desc: "Jump directly to workspace 6",           defaultRepeat: false, defaultLocked: false },
                                { id: "workspace 7",                label: "Switch to Workspace 7",                        desc: "Jump directly to workspace 7",           defaultRepeat: false, defaultLocked: false },
                                { id: "workspace 8",                label: "Switch to Workspace 8",                        desc: "Jump directly to workspace 8",           defaultRepeat: false, defaultLocked: false },
                                { id: "workspace 9",                label: "Switch to Workspace 9",                        desc: "Jump directly to workspace 9",           defaultRepeat: false, defaultLocked: false },
                                { id: "workspace 10",               label: "Switch to Workspace 10",                       desc: "Jump directly to workspace 10",          defaultRepeat: false, defaultLocked: false },
                                { id: "movetoworkspace 1",          label: "Move Window to Workspace 1",                   desc: "Move window to workspace 1 & focus it",  defaultRepeat: false, defaultLocked: false },
                                { id: "movetoworkspace 2",          label: "Move Window to Workspace 2",                   desc: "Move window to workspace 2 & focus it",  defaultRepeat: false, defaultLocked: false },
                                { id: "movetoworkspace 3",          label: "Move Window to Workspace 3",                   desc: "Move window to workspace 3 & focus it",  defaultRepeat: false, defaultLocked: false },
                                { id: "movetoworkspace 4",          label: "Move Window to Workspace 4",                   desc: "Move window to workspace 4 & focus it",  defaultRepeat: false, defaultLocked: false },
                                { id: "movetoworkspace 5",          label: "Move Window to Workspace 5",                   desc: "Move window to workspace 5 & focus it",  defaultRepeat: false, defaultLocked: false },
                                { id: "movetoworkspace 6",          label: "Move Window to Workspace 6",                   desc: "Move window to workspace 6 & focus it",  defaultRepeat: false, defaultLocked: false },
                                { id: "movetoworkspace 7",          label: "Move Window to Workspace 7",                   desc: "Move window to workspace 7 & focus it",  defaultRepeat: false, defaultLocked: false },
                                { id: "movetoworkspace 8",          label: "Move Window to Workspace 8",                   desc: "Move window to workspace 8 & focus it",  defaultRepeat: false, defaultLocked: false },
                                { id: "movetoworkspace 9",          label: "Move Window to Workspace 9",                   desc: "Move window to workspace 9 & focus it",  defaultRepeat: false, defaultLocked: false },
                                { id: "movetoworkspace 10",         label: "Move Window to Workspace 10",                  desc: "Move window to workspace 10 & focus it", defaultRepeat: false, defaultLocked: false },
                                { id: "movetoworkspacesilent 1",    label: "Move to Workspace 1 (Silently)",               desc: "Move window to workspace 1 in background", defaultRepeat: false, defaultLocked: false },
                                { id: "movetoworkspacesilent 2",    label: "Move to Workspace 2 (Silently)",               desc: "Move window to workspace 2 in background", defaultRepeat: false, defaultLocked: false },
                                { id: "movetoworkspacesilent 3",    label: "Move to Workspace 3 (Silently)",               desc: "Move window to workspace 3 in background", defaultRepeat: false, defaultLocked: false },
                                { id: "movetoworkspacesilent 4",    label: "Move to Workspace 4 (Silently)",               desc: "Move window to workspace 4 in background", defaultRepeat: false, defaultLocked: false },
                                { id: "movetoworkspacesilent 5",    label: "Move to Workspace 5 (Silently)",               desc: "Move window to workspace 5 in background", defaultRepeat: false, defaultLocked: false }
                            ]

                            readonly property var compMonitorActions: [
                                { id: "focusmonitor +1",     label: "Focus Next Monitor (focusmonitor +1)",     desc: "Move focus to next monitor",               defaultRepeat: false, defaultLocked: false },
                                { id: "focusmonitor -1",     label: "Focus Previous Monitor (focusmonitor -1)", desc: "Move focus to previous monitor",           defaultRepeat: false, defaultLocked: false },
                                { id: "movewindow mon:+1",   label: "Move Window to Next Monitor",              desc: "Move active window to next display",       defaultRepeat: false, defaultLocked: false },
                                { id: "movewindow mon:-1",   label: "Move Window to Previous Monitor",          desc: "Move active window to previous display",   defaultRepeat: false, defaultLocked: false },
                                { id: "dpms off",            label: "Turn Off Displays (Sleep DPMS)",           desc: "Put monitors into power saving standby",   defaultRepeat: false, defaultLocked: true },
                                { id: "dpms on",             label: "Turn On Displays (Wake DPMS)",             desc: "Wake monitors from standby",               defaultRepeat: false, defaultLocked: true },
                                { id: "exit",                label: "Exit Compositor (Logout)",                 desc: "Terminate session and return to greeter",  defaultRepeat: false, defaultLocked: true },
                                { id: "forcekillactive",     label: "Force Kill Active Window (SIGKILL)",       desc: "Forcefully kill unresponsive process",     defaultRepeat: false, defaultLocked: false }
                            ]

                            readonly property var mediaActions: [
                                { id: "wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+", label: "Volume Up (+5%)",         desc: "Increase audio output volume",        defaultRepeat: true,  defaultLocked: true },
                                { id: "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-",     label: "Volume Down (-5%)",       desc: "Decrease audio output volume",        defaultRepeat: true,  defaultLocked: true },
                                { id: "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle",    label: "Toggle Audio Mute",       desc: "Mute or unmute speaker output",       defaultRepeat: false, defaultLocked: true },
                                { id: "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle",  label: "Toggle Microphone Mute",  desc: "Mute or unmute default microphone",   defaultRepeat: false, defaultLocked: true },
                                { id: "playerctl play-pause",                          label: "Media: Play / Pause",     desc: "Play or pause active media playback", defaultRepeat: false, defaultLocked: true },
                                { id: "playerctl next",                                label: "Media: Next Track",       desc: "Skip to next media track",            defaultRepeat: false, defaultLocked: true },
                                { id: "playerctl previous",                            label: "Media: Previous Track",   desc: "Skip to previous media track",        defaultRepeat: false, defaultLocked: true },
                                { id: "playerctl stop",                                label: "Media: Stop Playback",    desc: "Stop active media playback",          defaultRepeat: false, defaultLocked: true },
                                { id: "brightnessctl -e4 -n2 set 5%+",                 label: "Brightness Up (+5%)",     desc: "Increase display backlight brightness", defaultRepeat: true,  defaultLocked: true },
                                { id: "brightnessctl -e4 -n2 set 5%-",                 label: "Brightness Down (-5%)",   desc: "Decrease display backlight brightness", defaultRepeat: true,  defaultLocked: true }
                            ]

                            readonly property var appActions: [
                                { id: "kitty",         label: "Kitty Terminal",        desc: "Fast GPU-accelerated terminal",          defaultRepeat: false, defaultLocked: false },
                                { id: "ghostty",       label: "Ghostty Terminal",      desc: "Native modern terminal emulator",        defaultRepeat: false, defaultLocked: false },
                                { id: "alacritty",     label: "Alacritty Terminal",    desc: "Simple OpenGL terminal",                  defaultRepeat: false, defaultLocked: false },
                                { id: "foot",          label: "Foot Terminal",         desc: "Fast lightweight Wayland terminal",       defaultRepeat: false, defaultLocked: false },
                                { id: "nautilus",      label: "Nautilus File Manager", desc: "GNOME Files / Directory browser",         defaultRepeat: false, defaultLocked: false },
                                { id: "thunar",        label: "Thunar File Manager",   desc: "Lightweight file manager",                defaultRepeat: false, defaultLocked: false },
                                { id: "dolphin",       label: "Dolphin File Manager",  desc: "KDE Plasma advanced file manager",       defaultRepeat: false, defaultLocked: false },
                                { id: "firefox",       label: "Firefox Web Browser",   desc: "Mozilla Firefox browser",                 defaultRepeat: false, defaultLocked: false },
                                { id: "google-chrome", label: "Google Chrome",         desc: "Google Chrome web browser",               defaultRepeat: false, defaultLocked: false },
                                { id: "code",          label: "Visual Studio Code",    desc: "Code and script editor",                  defaultRepeat: false, defaultLocked: false },
                                { id: "cursor",        label: "Cursor AI Editor",      desc: "AI-first code and project editor",        defaultRepeat: false, defaultLocked: false },
                                { id: "spotify",       label: "Spotify Music",         desc: "Spotify music streaming application",     defaultRepeat: false, defaultLocked: false },
                                { id: "discord",       label: "Discord",               desc: "Chat & voice communications client",      defaultRepeat: false, defaultLocked: false }
                            ]

                            function getActionListForCategory(catId) {
                                switch (catId) {
                                    case "all":
                                        return tab6.shellActions.concat(
                                            tab6.compWindowActions,
                                            tab6.compNavActions,
                                            tab6.compMoveActions,
                                            tab6.compResizeActions,
                                            tab6.compWorkspaceActions,
                                            tab6.compMonitorActions,
                                            tab6.mediaActions,
                                            tab6.appActions
                                        )
                                    case "shell": return tab6.shellActions
                                    case "comp_window": return tab6.compWindowActions
                                    case "comp_nav": return tab6.compNavActions
                                    case "comp_move": return tab6.compMoveActions
                                    case "comp_resize": return tab6.compResizeActions
                                    case "comp_work": return tab6.compWorkspaceActions
                                    case "comp_mon": return tab6.compMonitorActions
                                    case "media": return tab6.mediaActions
                                    case "apps": return tab6.appActions
                                    default: return []
                                }
                            }

                            function findCategoryForAction(action) {
                                if (!action) return "custom"
                                const cats = ["shell", "comp_window", "comp_nav", "comp_move", "comp_resize", "comp_work", "comp_mon", "media", "apps"]
                                for (let c = 0; c < cats.length; c++) {
                                    const list = tab6.getActionListForCategory(cats[c])
                                    for (let i = 0; i < list.length; i++) {
                                        if (list[i].id === action) return cats[c]
                                    }
                                }
                                return "custom"
                            }

                            function getHumanActionTitle(action) {
                                if (!action) return "Custom Shortcut"
                                const act = action.toLowerCase().trim()
                                const cats = ["shell", "comp_window", "comp_nav", "comp_move", "comp_resize", "comp_work", "comp_mon", "media", "apps"]
                                for (let c = 0; c < cats.length; c++) {
                                    const list = tab6.getActionListForCategory(cats[c])
                                    for (let i = 0; i < list.length; i++) {
                                        if (list[i].id.toLowerCase().trim() === act) return list[i].label
                                    }
                                }
                                if (act.includes("killactive") || act === "close window") return "Close Active Window"
                                if (act.includes("togglefloating") || act === "toggle floating") return "Toggle Floating Window"
                                if (act.includes("fullscreen") || act === "toggle fullscreen") return "Toggle Fullscreen"
                                if (act.includes("set-volume") && act.includes("+")) return "Volume Up"
                                if (act.includes("set-volume") && act.includes("-")) return "Volume Down"
                                if (act.includes("set-mute") && act.includes("sink")) return "Toggle Audio Mute"
                                if (act.includes("set-mute") && act.includes("source")) return "Toggle Mic Mute"
                                if (act.includes("play-pause")) return "Media: Play / Pause"
                                if (act.includes("next")) return "Media: Next Track"
                                if (act.includes("previous") || act.includes("prev")) return "Media: Previous Track"
                                if (act.includes("brightness") && act.includes("+")) return "Brightness Up"
                                if (act.includes("brightness") && act.includes("-")) return "Brightness Down"
                                if (act.includes("workspace")) return act.replace("dispatch workspace", "Workspace").replace("workspace", "Workspace")
                                return action
                            }

                            function toggleModifier(modName) {
                                let tokens = (rootWindow.formKeys || "").split("+").map(s => s.trim()).filter(s => s.length > 0)
                                let idx = tokens.findIndex(t => t.toUpperCase() === modName.toUpperCase())
                                const modOrder = ["SUPER", "CTRL", "ALT", "SHIFT"]
                                if (idx >= 0) {
                                    tokens.splice(idx, 1)
                                } else {
                                    let nonMods = tokens.filter(t => !modOrder.includes(t.toUpperCase()))
                                    let curMods = tokens.filter(t => modOrder.includes(t.toUpperCase()))
                                    curMods.push(modName.toUpperCase())
                                    curMods.sort((a, b) => modOrder.indexOf(a) - modOrder.indexOf(b))
                                    tokens = [...curMods, ...nonMods]
                                }
                                rootWindow.formKeys = tokens.join(" + ")
                            }

                            function appendKey(kName) {
                                let tokens = (rootWindow.formKeys || "").split("+").map(s => s.trim()).filter(s => s.length > 0)
                                const modOrder = ["SUPER", "CTRL", "ALT", "SHIFT"]
                                if (tokens.length > 0 && !modOrder.includes(tokens[tokens.length - 1].toUpperCase())) {
                                    tokens[tokens.length - 1] = kName
                                } else {
                                    tokens.push(kName)
                                }
                                rootWindow.formKeys = tokens.join(" + ")
                            }

                            function checkConflict(combo) {
                                if (!combo || combo.trim().length === 0) return null
                                const norm = combo.toLowerCase().replace(/\s+/g, "")
                                for (let i = 0; i < tab6.allBinds.length; i++) {
                                    const b = tab6.allBinds[i]
                                    if (rootWindow.editingBindLine > 0 && b.startLine === rootWindow.editingBindLine) continue
                                    const bNorm = (b.keys || "").toLowerCase().replace(/\s+/g, "")
                                    if (norm === bNorm) return b
                                }
                                return null
                            }

                            function previewConfigSyntax(keys, action, repeat, locked, mouse, nonConsuming) {
                                const k = (keys || "").trim() || "Mod + Key"
                                const act = (action || "").trim() || "command"
                                const isLua = Services.Compositor ? (Services.Compositor.configType === "lua") : true
                                if (isLua) {
                                    let opts = []
                                    if (locked) opts.push("locked = true")
                                    if (repeat) opts.push("repeating = true")
                                    if (mouse) opts.push("mouse = true")
                                    if (nonConsuming) opts.push("non_consuming = true")
                                    const optStr = opts.length > 0 ? ", { " + opts.join(", ") + " }" : ""
                                    const actLow = act.toLowerCase()
                                    if (actLow === "killactive" || actLow === "close window") {
                                        return 'hl.bind("' + k + '", hl.dsp.window.close()' + (opts.length > 0 ? optStr : ', { repeating = true }') + ')'
                                    } else if (actLow === "togglefloating" || actLow === "toggle floating") {
                                        return 'hl.bind("' + k + '", hl.dsp.window.float()' + optStr + ')'
                                    } else if (actLow === "fullscreen 0" || actLow === "fullscreen 1" || actLow === "fullscreen" || actLow === "toggle fullscreen") {
                                        return 'hl.bind("' + k + '", hl.dsp.window.fullscreen()' + optStr + ')'
                                    } else if (actLow.startsWith("togglesplit")) {
                                        return 'hl.bind("' + k + '", hl.dsp.layout("togglesplit")' + optStr + ')'
                                    } else if (actLow === "workspace e+1") {
                                        return 'hl.bind("' + k + '", hl.dsp.focus({ workspace = "e+1" })' + optStr + ')'
                                    } else if (actLow === "workspace e-1") {
                                        return 'hl.bind("' + k + '", hl.dsp.focus({ workspace = "e-1" })' + optStr + ')'
                                    } else if (actLow.startsWith("workspace ")) {
                                        const ws = act.split(" ").slice(1).join(" ")
                                        return 'hl.bind("' + k + '", hl.dsp.focus({ workspace = ' + (isNaN(Number(ws)) ? ('"' + ws + '"') : ws) + ' })' + optStr + ')'
                                    } else if (actLow.startsWith("movetoworkspace ")) {
                                        const ws = act.split(" ").slice(1).join(" ")
                                        return 'hl.bind("' + k + '", hl.dsp.window.move({ workspace = ' + (isNaN(Number(ws)) ? ('"' + ws + '"') : ws) + ' })' + optStr + ')'
                                    } else if (actLow.startsWith("movefocus ")) {
                                        const d = act.split(" ")[1]
                                        const dirMap = { "l": "left", "r": "right", "u": "up", "d": "down" }
                                        return 'hl.bind("' + k + '", hl.dsp.focus({ direction = "' + (dirMap[d] || d) + '" })' + optStr + ')'
                                    } else if (actLow === "togglespecialworkspace") {
                                        return 'hl.bind("' + k + '", hl.dsp.workspace.toggle_special("magic")' + optStr + ')'
                                    } else {
                                        const firstW = act.split(" ")[0].toLowerCase()
                                        const hyprDisps = ["swapwindow", "resizeactive", "resizewindow", "cyclenext", "togglegroup", "changegroupactive", "movewindoworgroup", "centerwindow", "splitratio", "dpms", "exit", "forcekillactive", "focusmonitor"]
                                        if (hyprDisps.includes(firstW)) {
                                            return 'hl.bind("' + k + '", hl.dsp.exec_cmd("hyprctl dispatch ' + act + '")' + optStr + ')'
                                        }
                                        return 'hl.bind("' + k + '", hl.dsp.exec_cmd("' + act + '")' + optStr + ')'
                                    }
                                } else {
                                    let flags = ""
                                    if (nonConsuming) flags += "n"
                                    if (mouse) flags += "m"
                                    if (repeat && locked) flags += "el"
                                    else if (repeat) flags += "e"
                                    else if (locked) flags += "l"
                                    const firstWord = act.split(" ")[0].toLowerCase()
                                    const hyprDispatchers = ["killactive", "togglefloating", "fullscreen", "workspace", "movetoworkspace", "movetoworkspacesilent", "togglesplit", "pseudo", "pin", "movefocus", "movewindow", "swapwindow", "resizeactive", "resizewindow", "cyclenext", "togglegroup", "changegroupactive", "movewindoworgroup", "centerwindow", "togglespecialworkspace", "splitratio", "dpms", "exit", "forcekillactive", "focusmonitor"]
                                    if (hyprDispatchers.includes(firstWord)) {
                                        const argPart = act.substring(firstWord.length).trim()
                                        return "bind" + flags + " = " + k + ", " + firstWord + (argPart ? (", " + argPart) : ", ")
                                    }
                                    return "bind" + flags + " = " + k + ", exec, " + act
                                }
                            }

                            readonly property var filteredBinds: {
                                const list = tab6.allBinds
                                const cat = rootWindow.keyCategory
                                const beh = rootWindow.keyBehaviourFilter
                                const q = (rootWindow.keySearchQuery || "").trim().toLowerCase()

                                return list.filter(k => {
                                    if (cat !== "all") {
                                        if (cat === "custom" && k.category !== "custom") return false
                                        else if (cat !== "custom" && k.category !== cat) return false
                                    }

                                    if (beh === "repeat" && !k.repeat) return false
                                    if (beh === "locked" && !k.locked) return false
                                    if (beh === "mouse" && !k.mouse) return false

                                    if (q.length > 0) {
                                        const keysMatch = (k.keys || "").toLowerCase().includes(q)
                                        const actMatch = (k.action || "").toLowerCase().includes(q)
                                        const title = tab6.getHumanActionTitle(k.action).toLowerCase()
                                        const descMatch = (k.desc || "").toLowerCase().includes(q)
                                        if (!keysMatch && !actMatch && !title.includes(q) && !descMatch) return false
                                    }

                                    return true
                                })
                            }

                            readonly property int totalPages: Math.max(1, Math.ceil(filteredBinds.length / itemsPerPage))
                            readonly property var pagedBinds: {
                                let start = currentPage * itemsPerPage
                                return filteredBinds.slice(start, start + itemsPerPage)
                            }

            readonly property bool formOpen: rootWindow.isAddingKeybind || rootWindow.editingBindLine > 0

            function resetForm() {
                rootWindow.isAddingKeybind = false
                rootWindow.editingBindId = ""
                rootWindow.editingBindLine = -1
                rootWindow.formKeys = ""
                rootWindow.formAction = ""
                rootWindow.formDesc = ""
            }

            function startAdd() {
                rootWindow.isAddingKeybind = true
                rootWindow.editingBindId = ""
                rootWindow.editingBindLine = -1
                rootWindow.formKeys = ""
                tab6.addCategoryType = "shell"
                rootWindow.formAction = tab6.shellActions[0].id
                rootWindow.formDesc = tab6.shellActions[0].label
                rootWindow.formRepeat = Boolean(tab6.shellActions[0].defaultRepeat)
                rootWindow.formLocked = Boolean(tab6.shellActions[0].defaultLocked)
                rootWindow.formMouse = false
                rootWindow.formNonConsuming = false
            }

            function saveForm() {
                if (Services.Compositor) {
                    const opts = {
                        repeat: Boolean(rootWindow.formRepeat),
                        locked: Boolean(rootWindow.formLocked),
                        mouse: Boolean(rootWindow.formMouse),
                        nonConsuming: Boolean(rootWindow.formNonConsuming)
                    }
                    if (rootWindow.editingBindLine > 0) {
                        Services.Compositor.updateKeybind(rootWindow.editingBindLine, rootWindow.formKeys.trim(), rootWindow.formAction.trim(), rootWindow.formDesc.trim(), rootWindow.formFile, opts)
                    } else {
                        Services.Compositor.addKeybind(rootWindow.formKeys.trim(), rootWindow.formAction.trim(), rootWindow.formDesc.trim(), "", opts)
                    }
                }
                resetForm()
            }

            function applyPreset(id) {
                rootWindow.formAction = id
                const list = tab6.getActionListForCategory(tab6.addCategoryType)
                for (let i = 0; i < list.length; i++) {
                    if (list[i].id === id) {
                        rootWindow.formDesc = list[i].label
                        rootWindow.formRepeat = Boolean(list[i].defaultRepeat)
                        rootWindow.formLocked = Boolean(list[i].defaultLocked)
                        break
                    }
                }
            }

            // toolbar
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 10
                spacing: 6
                Inp {
                    Layout.fillWidth: true
                    placeholder: "Search shortcuts"
                    text: rootWindow.keySearchQuery
                    onEdited: (v) => { rootWindow.keySearchQuery = v; tab6.currentPage = 0 }
                }
                Btn {
                    glyph: tab6.formOpen ? "✕" : (Services.Icons.plus || "+")
                    text: tab6.formOpen ? "Close" : "New"
                    kind: tab6.formOpen ? "plain" : "accent"
                    onClicked: { if (tab6.formOpen) tab6.resetForm(); else tab6.startAdd() }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 8
                Seg {
                    options: [
                        { id: "all", label: "All" }, { id: "quickshell", label: "Shell" }, { id: "window", label: "Window" },
                        { id: "apps", label: "Apps" }, { id: "media", label: "Media" }, { id: "system", label: "System" }, { id: "custom", label: "Custom" }
                    ]
                    current: rootWindow.keyCategory
                    onPicked: (id) => { rootWindow.keyCategory = id; tab6.currentPage = 0 }
                }
                Item { Layout.fillWidth: true }
            }

            Flow {
                Layout.fillWidth: true
                Layout.topMargin: 8
                spacing: 6
                Chip { text: "All " + tab6.totalBindsCount; on: rootWindow.keyBehaviourFilter === "all"; onClicked: { rootWindow.keyBehaviourFilter = "all"; tab6.currentPage = 0 } }
                Chip { text: "Repeat " + tab6.repeatBindsCount; on: rootWindow.keyBehaviourFilter === "repeat"; onClicked: { rootWindow.keyBehaviourFilter = "repeat"; tab6.currentPage = 0 } }
                Chip { text: "Locked " + tab6.lockedBindsCount; on: rootWindow.keyBehaviourFilter === "locked"; onClicked: { rootWindow.keyBehaviourFilter = "locked"; tab6.currentPage = 0 } }
                Chip { text: "Mouse " + tab6.mouseBindsCount; on: rootWindow.keyBehaviourFilter === "mouse"; onClicked: { rootWindow.keyBehaviourFilter = "mouse"; tab6.currentPage = 0 } }
            }

            // status
            Rectangle {
                readonly property bool isErr: Services.Compositor && Services.Compositor.keybindError.length > 0
                visible: Services.Compositor && (Services.Compositor.keybindStatus.length > 0 || Services.Compositor.keybindError.length > 0)
                Layout.fillWidth: true
                Layout.topMargin: 8
                implicitHeight: stRow.implicitHeight + 12
                radius: ui.r
                color: isErr ? ui.dng(0.12) : Qt.rgba(ui.ok.r, ui.ok.g, ui.ok.b, 0.12)
                RowLayout {
                    id: stRow
                    anchors.fill: parent
                    anchors.margins: 6
                    anchors.leftMargin: 10
                    spacing: 8
                    Text {
                        Layout.fillWidth: true
                        text: Services.Compositor ? (parent.parent.isErr ? Services.Compositor.keybindError : Services.Compositor.keybindStatus) : ""
                        wrapMode: Text.WordWrap
                        font.pixelSize: 11
                        color: parent.parent.isErr ? ui.danger : ui.ok
                    }
                    Text {
                        text: "✕"
                        font.pixelSize: 10
                        color: ui.dim
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { if (Services.Compositor) { Services.Compositor.keybindStatus = ""; Services.Compositor.keybindError = "" } }
                        }
                    }
                }
            }

            // editor
            Rectangle {
                visible: tab6.formOpen
                Layout.fillWidth: true
                Layout.topMargin: 10
                implicitHeight: formCol.implicitHeight + 24
                radius: 8
                color: ui.fill

                ColumnLayout {
                    id: formCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 8

                    Text {
                        text: rootWindow.editingBindLine > 0 ? "Edit shortcut" : "New shortcut"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: ui.fg
                    }

                    KeyRec {
                        id: formRec
                        Layout.fillWidth: true
                        onRecorded: (k) => { rootWindow.formKeys = k }
                        onCleared: { rootWindow.formKeys = "" }
                    }
                    Binding { target: formRec; property: "value"; value: rootWindow.formKeys }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: ["SUPER", "CTRL", "ALT", "SHIFT"]
                            delegate: Chip {
                                required property string modelData
                                text: modelData
                                on: (rootWindow.formKeys || "").toUpperCase().split("+").map(function(s) { return s.trim() }).includes(modelData)
                                onClicked: tab6.toggleModifier(modelData)
                            }
                        }
                        Repeater {
                            model: ["Return", "Space", "Tab", "Q", "F", "Print"]
                            delegate: Chip {
                                required property string modelData
                                text: modelData
                                dimmed: true
                                onClicked: tab6.appendKey(modelData)
                            }
                        }
                    }

                    Tag {
                        readonly property var hit: tab6.checkConflict(rootWindow.formKeys)
                        visible: hit !== null && hit !== undefined
                        text: hit ? ("Already used by: " + tab6.getHumanActionTitle(hit.action)) : ""
                        tint: ui.warn
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text { text: "Action"; font.pixelSize: 11; color: ui.dim }
                        Pick {
                            model: tab6.actionCategories
                            current: tab6.addCategoryType
                            minW: 150
                            maxW: 230
                            onPicked: (id) => {
                                tab6.addCategoryType = id
                                if (id === "custom") {
                                    rootWindow.formAction = ""
                                    rootWindow.formDesc = ""
                                } else {
                                    const list = tab6.getActionListForCategory(id) || []
                                    if (list.length > 0) {
                                        rootWindow.formAction = list[0].id || ""
                                        rootWindow.formDesc = list[0].label || ""
                                        rootWindow.formRepeat = Boolean(list[0].defaultRepeat)
                                        rootWindow.formLocked = Boolean(list[0].defaultLocked)
                                    }
                                }
                            }
                        }
                        Pick {
                            visible: tab6.addCategoryType !== "custom"
                            Layout.fillWidth: true
                            searchable: true
                            minW: 150
                            maxW: 400
                            model: tab6.getActionListForCategory(tab6.addCategoryType)
                            current: rootWindow.formAction
                            onPicked: (id) => tab6.applyPreset(id)
                        }
                    }

                    Inp {
                        visible: tab6.addCategoryType === "custom"
                        Layout.fillWidth: true
                        mono: true
                        placeholder: "Command, e.g. kitty -e btop"
                        text: rootWindow.formAction
                        onEdited: (v) => { rootWindow.formAction = v }
                    }
                    Inp {
                        visible: tab6.addCategoryType === "custom"
                        Layout.fillWidth: true
                        placeholder: "Description (optional)"
                        text: rootWindow.formDesc
                        onEdited: (v) => { rootWindow.formDesc = v }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Chip { text: "Repeat"; on: rootWindow.formRepeat; onClicked: rootWindow.formRepeat = !rootWindow.formRepeat }
                        Chip { text: "Locked"; on: rootWindow.formLocked; onClicked: rootWindow.formLocked = !rootWindow.formLocked }
                        Chip { text: "Mouse"; on: rootWindow.formMouse; onClicked: rootWindow.formMouse = !rootWindow.formMouse }
                        Chip { text: "Pass-through"; on: rootWindow.formNonConsuming; onClicked: rootWindow.formNonConsuming = !rootWindow.formNonConsuming }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: tab6.previewConfigSyntax(rootWindow.formKeys, rootWindow.formAction, rootWindow.formRepeat, rootWindow.formLocked, rootWindow.formMouse, rootWindow.formNonConsuming)
                        wrapMode: Text.WrapAnywhere
                        font.family: Services.Theme.fontMono
                        font.pixelSize: 10
                        color: ui.dim
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        Btn { text: "Cancel"; onClicked: tab6.resetForm() }
                        Btn {
                            text: rootWindow.editingBindLine > 0 ? "Save" : "Add"
                            kind: "accent"
                            enabledState: rootWindow.formKeys.trim().length > 0 && rootWindow.formAction.trim().length > 0
                            onClicked: tab6.saveForm()
                        }
                    }
                }
            }

            // list
            SettingsGroup {
                title: "Shortcuts (" + tab6.filteredBinds.length + ")"
                Text {
                    visible: tab6.filteredBinds.length === 0
                    Layout.leftMargin: 4
                    Layout.topMargin: 6
                    text: "No shortcuts match"
                    font.pixelSize: 11
                    color: ui.faint
                }
                Repeater {
                    model: tab6.pagedBinds
                    delegate: Opt {
                        id: kr
                        required property var modelData
                        readonly property bool editing: rootWindow.editingBindLine > 0 && rootWindow.editingBindLine === kr.modelData.startLine
                        label: tab6.getHumanActionTitle(kr.modelData.action)
                        hint: kr.modelData.action
                        opacity: (rootWindow.editingBindLine > 0 && !kr.editing) ? 0.5 : 1.0
                        RowLayout {
                            spacing: 6
                            Tag { visible: Boolean(kr.modelData.repeat); text: "REP" }
                            Tag { visible: Boolean(kr.modelData.locked); text: "LOCK" }
                            Tag { visible: Boolean(kr.modelData.mouse); text: "MOUSE" }
                            Row {
                                spacing: 3
                                Repeater {
                                    model: (kr.modelData.keys || "").split("+").map(function(s) { return s.trim() }).filter(function(s) { return s.length > 0 })
                                    delegate: Cap { required property string modelData; text: modelData }
                                }
                            }
                            Btn {
                                glyph: "✎"
                                onClicked: {
                                    rootWindow.editingBindId = kr.modelData.id || ""
                                    rootWindow.editingBindLine = kr.modelData.startLine || -1
                                    rootWindow.formKeys = kr.modelData.keys || ""
                                    rootWindow.formAction = kr.modelData.action || ""
                                    rootWindow.formDesc = kr.modelData.desc || tab6.getHumanActionTitle(kr.modelData.action)
                                    rootWindow.formRepeat = Boolean(kr.modelData.repeat)
                                    rootWindow.formLocked = Boolean(kr.modelData.locked)
                                    rootWindow.formMouse = Boolean(kr.modelData.mouse)
                                    rootWindow.formNonConsuming = Boolean(kr.modelData.nonConsuming)
                                    rootWindow.formFile = kr.modelData.file || ""
                                    tab6.addCategoryType = tab6.findCategoryForAction(kr.modelData.action)
                                    rootWindow.isAddingKeybind = false
                                }
                            }
                            ArmBtn {
                                idle: "✕"
                                onConfirmed: { if (Services.Compositor) Services.Compositor.deleteKeybind(kr.modelData.startLine, kr.modelData.file) }
                            }
                        }
                    }
                }
            }

            RowLayout {
                visible: tab6.totalPages > 1
                Layout.fillWidth: true
                Layout.topMargin: 8
                Item { Layout.fillWidth: true }
                Btn { text: "‹"; enabledState: tab6.currentPage > 0; onClicked: tab6.currentPage-- }
                Text { text: (tab6.currentPage + 1) + " / " + tab6.totalPages; font.family: Services.Theme.fontMono; font.pixelSize: 10; color: ui.dim }
                Btn { text: "›"; enabledState: tab6.currentPage < tab6.totalPages - 1; onClicked: tab6.currentPage++ }
                Item { Layout.fillWidth: true }
            }

            Item { Layout.preferredHeight: 8 }
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  PAGE 7 · BACKUP
    // ═════════════════════════════════════════════════════════════════════════
    Component {
        id: pgBackup

        ColumnLayout {
            spacing: 0

            SettingsGroup {
                title: "Configuration"
                Opt {
                    label: "Export"
                    hint: "Save a snapshot of your settings"
                    Btn { glyph: "󰆓"; text: "Export…"; onClicked: { if (Services.Config) Services.Config.exportConfig() } }
                }
                Opt {
                    label: "Restore"
                    hint: "Load a previously exported snapshot"
                    Btn { glyph: "󰁯"; text: "Restore…"; onClicked: { if (Services.Config) Services.Config.importConfig() } }
                }
                Opt {
                    label: "Reset to defaults"
                    hint: "Restores theme, layout and configuration"
                    ArmBtn { idle: "Reset all"; onConfirmed: { if (Services.Config) Services.Config.resetToDefaults() } }
                }
            }

            SettingsGroup {
                title: "Setup"
                Opt {
                    label: "Setup wizard"
                    hint: "Re-run first-run onboarding"
                    Btn {
                        text: "Run wizard"
                        onClicked: {
                            if (Services.Config) {
                                Services.Config.setFirstRunCompleted(false)
                                Services.Config.saveConfig()
                            }
                            Services.OverlayManager.welcomeShowRequested()
                        }
                    }
                }
            }

            Item { Layout.preferredHeight: 8 }
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  PAGE 8 · ABOUT
    // ═════════════════════════════════════════════════════════════════════════
    Component {
        id: pgAbout

        ColumnLayout {
            id: tab8
            property bool copied: false
            spacing: 0

            Timer { id: copiedTimer; interval: 1800; onTriggered: tab8.copied = false }

            // identity
            RowLayout {
                Layout.topMargin: 18
                Layout.bottomMargin: 6
                spacing: 12
                Rectangle {
                    Layout.preferredWidth: 40; Layout.preferredHeight: 40; radius: 10
                    color: ui.accent
                    Text {
                        anchors.centerIn: parent
                        text: (Services.OsInfo && Services.OsInfo.logoGlyph) ? Services.OsInfo.logoGlyph : (Services.Icons.settings || "")
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 20
                        color: ui.onAccent
                    }
                }
                ColumnLayout {
                    spacing: 1
                    Text { text: Services.OsInfo.distroName || "Linux"; font.pixelSize: 15; font.weight: Font.DemiBold; color: ui.fg }
                    Text { text: (Services.OsInfo.username || "user") + "@" + (Services.OsInfo.hostname || "local"); font.family: Services.Theme.fontMono; font.pixelSize: 11; color: ui.dim }
                }
            }

            SettingsGroup {
                title: "System"
                Opt { label: "Kernel"; Text { text: Services.OsInfo.kernel || "-"; font.family: Services.Theme.fontMono; font.pixelSize: 11; color: ui.fg } }
                Opt {
                    label: "Compositor"
                    Text {
                        text: (Services.Compositor ? Services.Compositor.activeDisplayName : "Wayland") + " (" + (Services.Compositor && Services.Compositor.configType ? Services.Compositor.configType.toUpperCase() : "CONF") + ")"
                        font.pixelSize: 11
                        color: ui.fg
                    }
                }
                Opt { label: "Shell"; Text { text: "Quickshell Desktop v1.2 · " + (Services.OsInfo.shellName || "sh"); font.pixelSize: 11; color: ui.fg } }
            }

            SettingsGroup {
                title: "Tools"
                Opt {
                    label: "System info"
                    hint: "Copy a summary to the clipboard"
                    Btn {
                        glyph: tab8.copied ? (Services.Icons.check || "✓") : (Services.Icons.clipboard || "")
                        text: tab8.copied ? "Copied" : "Copy"
                        kind: tab8.copied ? "accent" : "plain"
                        onClicked: {
                            const specs = "OS: " + (Services.OsInfo.distroName || "Linux")
                                + "\nKernel: " + (Services.OsInfo.kernel || "-")
                                + "\nHost: " + (Services.OsInfo.hostname || "local")
                                + "\nCompositor: " + (Services.Compositor ? Services.Compositor.activeDisplayName : "Wayland")
                                + "\nShell: " + (Services.OsInfo.shellName || "sh")
                                + "\nUser: " + (Services.OsInfo.username || "user")
                                + "\nDesktop: Quickshell v1.2"
                            if (Services.Clipboard) Services.Clipboard.copyText(specs)
                            tab8.copied = true
                            copiedTimer.restart()
                        }
                    }
                }
                Opt {
                    label: "Terminal"
                    Btn { glyph: Services.Icons.terminal || ""; text: "Open"; onClicked: openTermProc.running = true }
                }
            }

            Item { Layout.preferredHeight: 8 }
        }
    }

    // ── helper processes ─────────────────────────────────────────────────────
    Process { id: openTermProc;   command: ["sh", "-c", "kitty || alacritty || foot || xterm || ghostty"] }
    Process { id: pavuProc;       command: ["pavucontrol"] }
    Process { id: testNotifProc;  command: ["notify-send", "-a", "Quickshell Settings", "Settings Test", "Your notification preferences are working!"] }
    Process { id: lockSessionProc; command: ["sh", "-c", "qs ipc call lockscreen lock || loginctl lock-session"] }
    Process { id: suspendProc;    command: ["systemctl", "suspend"] }
    Process { id: rebootProc;     command: ["systemctl", "reboot"] }
    Process { id: poweroffProc;   command: ["systemctl", "poweroff"] }
}
