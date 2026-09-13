import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import "../../services" as Services

FloatingWindow {
    id: rootWindow

    title: "Quickshell Settings"
    visible: false
    implicitWidth: 980
    implicitHeight: 680
    minimumSize: Qt.size(480, 400)
    color: Services.Theme.isDark ? "#16161a" : "#f4f5f8"

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

    Item {
        id: keyFocus
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: (event) => {
            rootWindow.hide()
            event.accepted = true
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // REUSABLE BALANCED "MEDIUM" SETTINGS COMPONENTS
    // ═════════════════════════════════════════════════════════════════════════

    // ── 1. Section Header & Inset Grouped Card ───────────────────────────────
    component SettingsSection: ColumnLayout {
        id: secRoot
        property string title: ""
        property string icon: ""
        default property alias content: cardContent.data

        Layout.fillWidth: true
        spacing: 6

        RowLayout {
            visible: secRoot.title.length > 0
            spacing: 6
            Layout.leftMargin: 2

            Text {
                visible: secRoot.icon.length > 0
                text: secRoot.icon
                font.family: Services.Theme.fontSymbols
                font.pixelSize: 11
                color: Services.Theme.accent
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                text: secRoot.title.toUpperCase()
                font.pixelSize: 10
                font.weight: Font.DemiBold
                font.letterSpacing: 0.8
                color: Services.Theme.textSecondary
                Layout.alignment: Qt.AlignVCenter
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: cardContent.implicitHeight + 8
            radius: 12
            color: Services.Theme.isDark ? "#1c1c22" : "#ffffff"
            border.color: Services.Theme.isDark ? "#282832" : "#e2e8f0"
            border.width: 1

            ColumnLayout {
                id: cardContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 4
                spacing: 0
            }
        }
    }

    // ── 2. Settings Row (Clean Typography on Left, Control on Right) ──────────
    component SettingsRow: Rectangle {
        id: rowRoot
        property string title: ""
        property string subtitle: ""
        default property alias control: controlSlot.data

        Layout.fillWidth: true
        implicitHeight: Math.max(46, textCol.implicitHeight + 18)
        radius: 8
        color: "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 12

            ColumnLayout {
                id: textCol
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: rowRoot.title
                    font.pixelSize: Services.Theme.fontSizeMd
                    font.weight: Font.Medium
                    color: Services.Theme.textPrimary
                    elide: Text.ElideRight
                }

                Text {
                    visible: rowRoot.subtitle.length > 0
                    Layout.fillWidth: true
                    text: rowRoot.subtitle
                    font.pixelSize: Services.Theme.fontSizeXs
                    color: Services.Theme.textSecondary
                    elide: Text.ElideRight
                }
            }

            Item {
                id: controlSlot
                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                implicitWidth: childrenRect.width
                implicitHeight: childrenRect.height
            }
        }
    }

    // ── 3. Settings Dropdown / ComboBox (Native Popover) ─────────────────────
    component SettingsDropdown: Item {
        id: dropRoot
        property var model: [] // [{ id, label }]
        property var currentValue: null
        property bool searchable: false
        property string searchPlaceholder: "Search..."
        property int maxPopupHeight: 240
        property int minButtonWidth: 90
        property int maxButtonWidth: 175
        property int buttonHeight: 26
        property string searchQuery: ""
        property bool openUpwards: false
        signal selected(var val)

        function checkOpenDirection() {
            var globalPos = dropBtn.mapToItem(rootWindow.contentItem || null, 0, 0)
            if (globalPos) {
                var spaceBelow = rootWindow.height - (globalPos.y + dropBtn.height)
                var popupH = Math.min(dropRoot.maxPopupHeight, (dropRoot.searchable ? 36 : 0) + 160)
                openUpwards = (spaceBelow < popupH + 20) && (globalPos.y > popupH + 20)
            } else {
                openUpwards = false
            }
        }

        readonly property var currentItem: {
            for (let i = 0; i < model.length; i++) {
                if (model[i].id === currentValue) return model[i]
            }
            return model.length > 0 ? model[0] : { label: "Select..." }
        }

        readonly property var filteredModel: {
            if (!searchable || !searchQuery || searchQuery.trim().length === 0) return model
            const q = searchQuery.toLowerCase().trim()
            return model.filter(function(item) {
                return (item.label || "").toLowerCase().indexOf(q) !== -1 || String(item.id || "").toLowerCase().indexOf(q) !== -1
            })
        }

        implicitWidth: dropBtn.implicitWidth
        implicitHeight: dropBtn.height

        Rectangle {
            id: dropBtn
            implicitWidth: Math.min(dropRoot.maxButtonWidth, Math.max(dropRoot.minButtonWidth, dropBtnText.implicitWidth + 28))
            width: (dropRoot.width > 0 && dropRoot.width > implicitWidth) ? dropRoot.width : implicitWidth
            height: dropRoot.buttonHeight
            radius: 6
            color: (dropMenu.visible && !dropMenu.isClosing) 
                ? (Services.Theme.isDark ? "#32323e" : "#e8e8ed")
                : (dropArea.containsMouse 
                    ? (Services.Theme.isDark ? "#2e2e3a" : "#eaebee") 
                    : (Services.Theme.isDark ? "#262630" : "#f2f2f7"))
            border.color: (dropMenu.visible && !dropMenu.isClosing) 
                ? Services.Theme.accent 
                : (Services.Theme.isDark ? "#3c3c4a" : "#d0d0d8")
            border.width: 1

            // Liquid press scale
            scale: dropArea.pressed ? 0.96 : (dropArea.containsMouse ? 1.01 : 1.0)
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
            Behavior on color { ColorAnimation { duration: 150 } }
            Behavior on border.color { ColorAnimation { duration: 150 } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 6

                Text {
                    id: dropBtnText
                    Layout.fillWidth: true
                    text: dropRoot.currentItem ? dropRoot.currentItem.label : ""
                    font.pixelSize: Services.Theme.fontSizeSm
                    font.weight: Font.Normal
                    color: Services.Theme.textPrimary
                    elide: Text.ElideRight

                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }

                Text {
                    text: "▾"
                    font.pixelSize: 8
                    color: (dropMenu.visible && !dropMenu.isClosing) ? Services.Theme.accent : Services.Theme.textSecondary
                    rotation: (dropMenu.visible && !dropMenu.isClosing) ? 180 : 0
                    transformOrigin: Item.Center
                    Behavior on rotation {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.25
                        }
                    }
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }

            MouseArea {
                id: dropArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (dropMenu.visible && !dropMenu.isClosing) {
                        dropMenu.requestClose()
                    } else if (!dropMenu.visible) {
                        dropRoot.searchQuery = ""
                        dropRoot.checkOpenDirection()
                        dropMenu.open()
                    }
                }
            }

            Popup {
                id: dropMenu
                readonly property real fullHeight: {
                    var targetH = (dropRoot.searchable ? 36 : 0) + menuCol.implicitHeight + 12
                    var maxH = dropRoot.maxPopupHeight
                    var globalPos = dropBtn.mapToItem(rootWindow.contentItem || null, 0, 0)
                    if (globalPos) {
                        var space = dropRoot.openUpwards ? (globalPos.y - 12) : (rootWindow.height - (globalPos.y + dropBtn.height) - 12)
                        if (space > 60) maxH = Math.min(maxH, space)
                    }
                    return Math.max(40, Math.min(maxH, targetH))
                }

                width: Math.max(dropBtn.width, 175)
                height: fullHeight
                y: dropRoot.openUpwards ? (-fullHeight - 8) : (dropBtn.height + 6)
                x: {
                    var globalPos = dropBtn.mapToItem(rootWindow.contentItem || null, 0, 0)
                    var targetW = Math.max(dropBtn.width, 175)
                    if (globalPos) {
                        var rightEdge = globalPos.x + targetW
                        if (rightEdge > (rootWindow.width - 16)) {
                            return -(rightEdge - (rootWindow.width - 16))
                        }
                    }
                    return Math.min(0, dropBtn.width - targetW)
                }
                padding: 0
                background: null
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                modal: false
                focus: true
                enter: null

                // Liquid Panel Growth Progress (0.0 -> 1.0)
                property real panelProgress: 0.0
                property bool isClosing: false

                function requestClose() {
                    if (!dropMenu.visible || isClosing) return
                    isClosing = true
                    panelBloomAnim.stop()
                    menuCol.reverseCascade()
                    dropMenu.close()
                }

                NumberAnimation {
                    id: panelBloomAnim
                    target: dropMenu
                    property: "panelProgress"
                    from: 0.0
                    to: 1.0
                    duration: 220
                    easing.type: Easing.OutCubic
                }

                onAboutToShow: {
                    dropRoot.checkOpenDirection()
                    isClosing = false
                    panelProgress = 0.0
                    panelBloomAnim.restart()
                    menuCol.startCascade()
                }

                onAboutToHide: {
                    isClosing = true
                    panelBloomAnim.stop()
                    menuCol.reverseCascade()
                }

                onClosed: {
                    isClosing = false
                    panelProgress = 0.0
                    menuCol.resetAll()
                }

                exit: Transition {
                    NumberAnimation {
                        target: dropMenu
                        property: "panelProgress"
                        to: 0.0
                        duration: 180
                        easing.type: Easing.InOutQuad
                    }
                }

                Timer {
                    id: selectCloseTimer
                    interval: 75
                    onTriggered: dropMenu.requestClose()
                }

                contentItem: Item {
                    id: popupContainer
                    implicitWidth: Math.max(dropBtn.width, 175)
                    implicitHeight: dropMenu.fullHeight

                    // Ambient Shadow that tracks the growing card
                    Rectangle {
                        anchors.fill: menuCard
                        anchors.margins: -4
                        anchors.verticalCenterOffset: dropRoot.openUpwards ? -2 : 4
                        radius: menuCard.radius + 2
                        color: Qt.rgba(0, 0, 0, 0.30)
                        opacity: dropMenu.panelProgress
                        visible: menuCard.height > 6
                        z: -1
                    }

                    // The Card that GROWS out of the dropdown button
                    Rectangle {
                        id: menuCard
                        anchors.bottom: dropRoot.openUpwards ? parent.bottom : undefined
                        anchors.top: dropRoot.openUpwards ? undefined : parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: Math.max(0, parent.height * dropMenu.panelProgress)
                        clip: true
                        radius: 10
                        color: Services.Theme.isDark ? "#1c1c24" : "#fbfbfd"
                        border.color: Services.Theme.isDark ? Qt.rgba(255, 255, 255, 0.12) : Qt.rgba(0, 0, 0, 0.10)
                        border.width: 1

                        // Soft Inner Specular Rim
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            radius: 9
                            color: "transparent"
                            border.color: Services.Theme.isDark ? Qt.rgba(255, 255, 255, 0.06) : Qt.rgba(255, 255, 255, 0.60)
                            border.width: 1
                            z: 2
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: 4
                            opacity: Math.min(1.0, dropMenu.panelProgress * 1.5)

                    // Optional Search Bar for Large Lists (e.g. Fonts, Themes)
                    Rectangle {
                        visible: dropRoot.searchable
                        opacity: dropMenu.panelProgress
                        Layout.fillWidth: true
                        height: 26
                        radius: 5
                        color: Services.Theme.isDark ? "#282834" : "#f1f2f6"
                        border.color: searchInput.activeFocus ? Services.Theme.accent : (Services.Theme.isDark ? "#3e3e4e" : "#d8d8e2")
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            spacing: 4

                            Text {
                                text: Services.Icons.search || "🔍"
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 9
                                color: Services.Theme.textSecondary
                            }

                            TextInput {
                                id: searchInput
                                Layout.fillWidth: true
                                text: dropRoot.searchQuery
                                font.pixelSize: 11
                                color: Services.Theme.textPrimary
                                selectByMouse: true
                                onTextChanged: dropRoot.searchQuery = text
                                Component.onCompleted: {
                                    if (dropRoot.searchable && dropMenu.visible) forceActiveFocus()
                                }
                            }

                            Text {
                                visible: dropRoot.searchQuery.length > 0
                                text: "✕"
                                font.pixelSize: 9
                                color: Services.Theme.textSecondary
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { dropRoot.searchQuery = ""; searchInput.text = "" }
                                }
                            }
                        }
                    }

                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: menuCol.implicitHeight
                        clip: contentHeight > height
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        ColumnLayout {
                            id: menuCol
                            width: parent.width
                            spacing: 3

                            function startCascade() {
                                for (let i = 0; i < itemRepeater.count; i++) {
                                    let item = itemRepeater.itemAt(i)
                                    if (item && item.triggerEntrance) {
                                        item.triggerEntrance(i)
                                    }
                                }
                            }

                            function reverseCascade() {
                                let total = itemRepeater.count
                                for (let i = 0; i < total; i++) {
                                    let item = itemRepeater.itemAt(i)
                                    if (item && item.triggerExit) {
                                        let rev = dropRoot.openUpwards ? i : (total - 1 - i)
                                        item.triggerExit(rev)
                                    }
                                }
                            }

                            function resetAll() {
                                for (let i = 0; i < itemRepeater.count; i++) {
                                    let item = itemRepeater.itemAt(i)
                                    if (item && item.resetItem) {
                                        item.resetItem()
                                    }
                                }
                            }

                            Repeater {
                                id: itemRepeater
                                model: dropRoot.filteredModel
                                delegate: Rectangle {
                                    id: itemRow
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    height: 28
                                    radius: 5
                                    readonly property bool isSelected: dropRoot.currentValue === modelData.id
                                    property bool isPressed: itemArea.pressed

                                    // Staggered Cascade Waterfall Entrance & Reverse Exit
                                    property real animProgress: 0.0

                                    SequentialAnimation {
                                        id: itemEntrance
                                        property int staggerIndex: 0
                                        PauseAnimation {
                                            duration: Math.min(180, itemEntrance.staggerIndex * 22)
                                        }
                                        NumberAnimation {
                                            target: itemRow
                                            property: "animProgress"
                                            from: 0.0
                                            to: 1.0
                                            duration: 200
                                            easing.type: Easing.OutCubic
                                        }
                                    }

                                    SequentialAnimation {
                                        id: itemExit
                                        property int staggerIndex: 0
                                        PauseAnimation {
                                            duration: Math.min(80, itemExit.staggerIndex * 12)
                                        }
                                        NumberAnimation {
                                            target: itemRow
                                            property: "animProgress"
                                            to: 0.0
                                            duration: 140
                                            easing.type: Easing.InCubic
                                        }
                                    }

                                    function triggerEntrance(idx) {
                                        itemExit.stop()
                                        itemEntrance.stop()
                                        itemEntrance.staggerIndex = (idx !== undefined ? idx : itemRow.index)
                                        animProgress = 0.0
                                        itemEntrance.restart()
                                    }

                                    function triggerExit(idx) {
                                        itemEntrance.stop()
                                        itemExit.stop()
                                        itemExit.staggerIndex = (idx !== undefined ? idx : 0)
                                        itemExit.restart()
                                    }

                                    function resetItem() {
                                        itemEntrance.stop()
                                        itemExit.stop()
                                        animProgress = 0.0
                                    }

                                    Component.onCompleted: {
                                        if (dropMenu.visible) {
                                             triggerEntrance(itemRow.index)
                                        } else {
                                             animProgress = 0.0
                                        }
                                    }

                                    opacity: itemRow.animProgress
                                    scale: isPressed ? 0.96 : 1.0
                                    transform: Translate {
                                        y: (1.0 - itemRow.animProgress) * (dropRoot.openUpwards ? 8 : -8)
                                    }

                                    color: isSelected 
                                        ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.16)
                                        : (itemArea.containsMouse 
                                            ? (Services.Theme.isDark ? "#2a2a36" : "#f0f0f6") 
                                            : "transparent")
                                    border.color: isSelected 
                                        ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.35) 
                                        : (itemArea.containsMouse ? (Services.Theme.isDark ? "#383848" : "#e0e0ea") : "transparent")
                                    border.width: 1
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Behavior on border.color { ColorAnimation { duration: 120 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: itemArea.containsMouse ? 10 : 8
                                        anchors.rightMargin: 8
                                        spacing: 6
                                        Behavior on anchors.leftMargin { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.label
                                            font.pixelSize: Services.Theme.fontSizeSm
                                            font.weight: isSelected ? Font.DemiBold : Font.Normal
                                            color: isSelected ? Services.Theme.accent : (Services.Theme.isDark ? "#e4e4ec" : "#1c1c24")
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            visible: isSelected
                                            text: Services.Icons.check || "✓"
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 10
                                            font.bold: true
                                            color: Services.Theme.accent
                                            scale: isSelected ? 1.0 : 0.0
                                            Behavior on scale {
                                                NumberAnimation {
                                                    duration: 180
                                                    easing.type: Easing.OutBack
                                                    easing.overshoot: 1.40
                                                }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: itemArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            dropRoot.selected(modelData.id)
                                            selectCloseTimer.restart()
                                        }
                                    }
                                }
                            }

                            Text {
                                visible: dropRoot.filteredModel.length === 0
                                Layout.fillWidth: true
                                Layout.topMargin: 12
                                Layout.bottomMargin: 12
                                horizontalAlignment: Text.AlignHCenter
                                text: "No matching items"
                                font.pixelSize: 11
                                color: Services.Theme.textSecondary
                            }
                        }
                    }
                }
            }
        }
    }
}
}

    // ── 4. Settings Switch (Liquid Glass Bloom, Stretch & Impact Toggle) ───────────
    component SettingsSwitch: Rectangle {
        id: switchRoot
        property string title: ""
        property string subtitle: ""
        property bool checked: false
        signal toggled(bool newState)

        onCheckedChanged: {
            if (swTrack.isDragging) return
            slideAndJiggle.stop()
            const targetX = switchRoot.checked ? 24 : 2
            slideAndJiggle.destX = targetX
            slideAndJiggle.direction = targetX > swTrack.currentX ? 1.0 : -1.0
            slideAndJiggle.restart()
        }

        Layout.fillWidth: true
        implicitHeight: Math.max(44, switchTextCol.implicitHeight + 16)
        radius: Services.Theme.radiusSm
        color: "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 12

            ColumnLayout {
                id: switchTextCol
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: switchRoot.title
                    font.pixelSize: Services.Theme.fontSizeMd
                    font.weight: Font.Medium
                    color: Services.Theme.textPrimary
                    elide: Text.ElideRight
                }

                Text {
                    visible: switchRoot.subtitle.length > 0
                    Layout.fillWidth: true
                    text: switchRoot.subtitle
                    font.pixelSize: Services.Theme.fontSizeXs
                    color: Services.Theme.textSecondary
                    elide: Text.ElideRight
                }
            }

            // Capsule Track
            Rectangle {
                id: swTrack
                width: 46
                height: 24
                Layout.preferredWidth: 46
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                radius: 12

                color: switchRoot.checked 
                    ? Services.Theme.accent 
                    : (swDragArea.containsMouse 
                        ? (Services.Theme.isDark ? "#40404c" : "#dadade") 
                        : (Services.Theme.isDark ? "#35353f" : "#e2e2e7"))
                border.color: switchRoot.checked 
                    ? Services.Theme.accent 
                    : (Services.Theme.isDark ? "#4c4c5a" : "#ceced6")
                border.width: 1
                Behavior on color { ColorAnimation { duration: 180 } }
                Behavior on border.color { ColorAnimation { duration: 180 } }

                readonly property real minX: 2
                readonly property real maxX: 24
                property real currentX: 2
                property real dragX: 2
                property bool isDragging: false
                property real pressStartX: 0
                property real expansion: 0.0

                Component.onCompleted: {
                    currentX = switchRoot.checked ? 24 : 2
                    dragX = currentX
                }

                Behavior on expansion {
                    enabled: !slideAndJiggle.running && !swTrack.isDragging
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.25
                    }
                }

                SequentialAnimation {
                    id: slideAndJiggle
                    property real destX: switchRoot.checked ? 24 : 2
                    property real direction: destX > swTrack.currentX ? 1.0 : -1.0

                    onStopped: {
                        swTrack.currentX = slideAndJiggle.destX
                        swThumb.squashX = 1.0
                        swThumb.squashY = 1.0
                        swTrack.expansion = 0.0
                    }

                    // Phase 1: Ngembang, Geser & Stretch (Slide, Bloom into Liquid Glass & Stretch) (160ms)
                    ParallelAnimation {
                        NumberAnimation {
                            target: swTrack
                            property: "currentX"
                            to: slideAndJiggle.destX
                            duration: 160
                            easing.type: Easing.InOutQuad
                        }
                        NumberAnimation {
                            target: swTrack
                            property: "expansion"
                            to: 1.0
                            duration: 120
                            easing.type: Easing.OutQuad
                        }
                        NumberAnimation {
                            target: swThumb
                            property: "squashX"
                            to: 1.30
                            duration: 140
                            easing.type: Easing.OutQuad
                        }
                        NumberAnimation {
                            target: swThumb
                            property: "squashY"
                            to: 0.86
                            duration: 140
                            easing.type: Easing.OutQuad
                        }
                    }

                    // Phase 2: Gel Impact Cushion ("Kepentok Gel Natural") (85ms)
                    ParallelAnimation {
                        NumberAnimation {
                            target: swThumb
                            property: "squashX"
                            to: 0.85
                            duration: 85
                            easing.type: Easing.OutQuad
                        }
                        NumberAnimation {
                            target: swThumb
                            property: "squashY"
                            to: 1.14
                            duration: 85
                            easing.type: Easing.OutQuad
                        }
                    }

                    // Phase 3: Soft Gel Rebound ("Membal Gel Organik") (75ms)
                    ParallelAnimation {
                        NumberAnimation {
                            target: swThumb
                            property: "squashX"
                            to: 1.04
                            duration: 75
                            easing.type: Easing.InOutQuad
                        }
                        NumberAnimation {
                            target: swThumb
                            property: "squashY"
                            to: 0.98
                            duration: 75
                            easing.type: Easing.InOutQuad
                        }
                    }

                    // Phase 4: Balik Normal (Settle back to Normal Round Porcelain Knob) (130ms)
                    ParallelAnimation {
                        NumberAnimation {
                            target: swThumb
                            property: "squashX"
                            to: 1.0
                            duration: 130
                            easing.type: Easing.OutQuad
                        }
                        NumberAnimation {
                            target: swThumb
                            property: "squashY"
                            to: 1.0
                            duration: 130
                            easing.type: Easing.OutQuad
                        }
                        NumberAnimation {
                            target: swTrack
                            property: "expansion"
                            to: 0.0
                            duration: 130
                            easing.type: Easing.OutQuad
                        }
                    }
                }

                // Liquid Glass Knob (Enlarged 40x26px Liquid Drop)
                Rectangle {
                    id: swThumb
                    readonly property bool isActive: swTrack.expansion > 0.01 || swDragArea.pressed || slideAndJiggle.running
                    width: 20 + swTrack.expansion * 20
                    height: 20 + swTrack.expansion * 6
                    radius: height / 2
                    anchors.verticalCenter: parent.verticalCenter
                    x: (swTrack.isDragging ? swTrack.dragX : swTrack.currentX) - (width - 20) / 2

                    property real squashX: 1.0
                    property real squashY: 1.0
                    transform: Scale {
                        origin.x: swThumb.width / 2
                        origin.y: swThumb.height / 2
                        xScale: swThumb.squashX
                        yScale: swThumb.squashY
                    }

                    // Fluid Cross-Fade from White Porcelain (#ffffff) to Translucent Frosted Glass
                    color: Services.Theme.isDark 
                        ? Qt.rgba(1.0, 1.0, 1.0, 1.0 - swTrack.expansion * 0.70)
                        : Qt.rgba(1.0, 1.0, 1.0, 1.0 - swTrack.expansion * 0.30)
                    border.color: swTrack.expansion > 0.01
                        ? (Services.Theme.isDark ? Qt.rgba(255, 255, 255, 0.55) : Qt.rgba(255, 255, 255, 0.90))
                        : Qt.rgba(0, 0, 0, 0.08)
                    border.width: swTrack.expansion > 0.01 ? 1.2 : 1

                    // ── Optical Refraction Chamber (Pembiasan & Pembengkokan Pensil Dalam Air) ──
                    Item {
                        anchors.fill: parent
                        anchors.margins: 1.5
                        clip: true
                        opacity: swTrack.expansion

                        // Refracted Track Core (Bent upwards with convex lens curvature & optical shift)
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -2.2 // Optical Refraction Shift
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: -1
                            height: parent.height * 0.78
                            radius: height / 2
                            color: switchRoot.checked ? Services.Theme.accent : (Services.Theme.isDark ? "#3c3c4a" : "#d2d2da")
                            opacity: 0.80
                        }
                    }

                    // Soft Inner Glass Refraction Bevel
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: parent.radius - 1
                        color: "transparent"
                        border.color: Services.Theme.isDark ? Qt.rgba(255, 255, 255, 0.22) : Qt.rgba(255, 255, 255, 0.45)
                        border.width: 1
                        opacity: swTrack.expansion
                    }

                    // Top Specular Glass Crescent Flare
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 1.5
                        height: Math.max(2, parent.height * 0.45)
                        radius: height / 2
                        opacity: swTrack.expansion
                        gradient: Gradient {
                            GradientStop { 
                                position: 0.0
                                color: Services.Theme.isDark ? Qt.rgba(255, 255, 255, 0.55) : Qt.rgba(255, 255, 255, 0.80)
                            }
                            GradientStop { 
                                position: 1.0
                                color: "transparent"
                            }
                        }
                    }

                    // ── Background Optical Refraction Distortion Halo (Distorsi Latar Belakang) ──
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + 4
                        height: parent.height + 4
                        radius: height / 2
                        color: switchRoot.checked ? Services.Theme.accent : (Services.Theme.isDark ? "#4a4a5e" : "#c6c6d2")
                        opacity: swTrack.expansion * 0.40
                        z: -1
                    }

                    // Natural Soft Drop Shadow
                    Rectangle {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: 1.5
                        width: parent.width
                        height: parent.height
                        radius: parent.radius
                        color: Qt.rgba(0, 0, 0, 0.20)
                        opacity: 1.0 - swTrack.expansion * 0.45
                        z: -2
                    }
                }

                MouseArea {
                    id: swDragArea
                    anchors.fill: parent
                    anchors.margins: -10
                    preventStealing: true
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onPressed: (mouse) => {
                        swTrack.pressStartX = mouse.x
                        swTrack.isDragging = false
                        swTrack.expansion = 1.0
                    }

                    onPositionChanged: (mouse) => {
                        if (!pressed) return
                        if (Math.abs(mouse.x - swTrack.pressStartX) > 3) {
                            swTrack.isDragging = true
                        }
                        if (swTrack.isDragging) {
                            slideAndJiggle.stop()
                            const trackX = mouse.x - 10
                            const rawX = trackX - 10
                            swTrack.dragX = Math.max(swTrack.minX, Math.min(swTrack.maxX, rawX))
                            swTrack.currentX = swTrack.dragX
                            swTrack.expansion = 1.0

                            const dragDelta = mouse.x - swTrack.pressStartX
                            swThumb.squashX = Math.min(1.30, Math.max(0.85, 1.0 + Math.abs(dragDelta) * 0.012))
                            swThumb.squashY = Math.max(0.88, Math.min(1.15, 1.0 - Math.abs(dragDelta) * 0.006))
                        }
                    }

                    onReleased: (mouse) => {
                        const wasDragging = swTrack.isDragging
                        swTrack.isDragging = false
                        
                        if (wasDragging) {
                            const midX = (swTrack.minX + swTrack.maxX) / 2
                            const targetState = swTrack.currentX > midX
                            if (targetState !== switchRoot.checked) {
                                switchRoot.toggled(targetState)
                            } else {
                                slideAndJiggle.destX = switchRoot.checked ? swTrack.maxX : swTrack.minX
                                slideAndJiggle.direction = slideAndJiggle.destX > swTrack.currentX ? 1.0 : -1.0
                                slideAndJiggle.restart()
                            }
                        } else {
                            switchRoot.toggled(!switchRoot.checked)
                        }
                    }

                    onCanceled: {
                        swTrack.isDragging = false
                        slideAndJiggle.destX = switchRoot.checked ? swTrack.maxX : swTrack.minX
                        slideAndJiggle.direction = slideAndJiggle.destX > swTrack.currentX ? 1.0 : -1.0
                        slideAndJiggle.restart()
                    }
                }
            }
        }
    }

    // ── 5. Settings Slider (Inset Grouped Slider Row) ────────────────────────
    component SettingsSlider: RowLayout {
        id: sliderRoot
        property string title: ""
        property string subtitle: ""
        property real from: 0
        property real to: 100
        property real stepSize: 1
        property real value: 0
        property string valuePrefix: ""
        property string valueSuffix: ""
        property int decimals: 0
        signal moved(real newValue)

        Layout.fillWidth: true
        spacing: 12
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        Layout.topMargin: 4
        Layout.bottomMargin: 4

        // Left: Title & Subtitle
        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.alignment: Qt.AlignVCenter
            spacing: 1

            Text {
                Layout.fillWidth: true
                text: sliderRoot.title
                font.pixelSize: Services.Theme.fontSizeMd
                font.weight: Font.Medium
                color: Services.Theme.textPrimary
                elide: Text.ElideRight
            }
            Text {
                visible: sliderRoot.subtitle.length > 0
                Layout.fillWidth: true
                text: sliderRoot.subtitle
                font.pixelSize: Services.Theme.fontSizeXs
                color: Services.Theme.textSecondary
                elide: Text.ElideRight
            }
        }

        // Right: Value Badge + Compact Tahoe Slider
        RowLayout {
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            Layout.fillWidth: false
            spacing: 8

            // Value Badge
            Text {
                Layout.preferredWidth: 36
                horizontalAlignment: Text.AlignRight
                text: sliderRoot.valuePrefix + (sliderRoot.decimals > 0 ? Number(sliderRoot.value).toFixed(sliderRoot.decimals) : Math.round(sliderRoot.value)) + sliderRoot.valueSuffix
                font.family: Services.Theme.fontMono
                font.pixelSize: 11
                font.weight: Font.Medium
                color: sDrag.pressed ? Services.Theme.accent : Services.Theme.textSecondary
            }

            // Compact Tahoe Track Container
            Item {
                id: trackContainer
                Layout.preferredWidth: 120
                Layout.minimumWidth: 60
                Layout.maximumWidth: 150
                height: 24

                readonly property real valRatio: Math.max(0, Math.min(1, (sliderRoot.value - sliderRoot.from) / Math.max(0.0001, sliderRoot.to - sliderRoot.from)))
                property real displayRatio: valRatio
                Binding {
                    target: trackContainer
                    property: "displayRatio"
                    value: trackContainer.valRatio
                    when: !slideGlideAnim.running
                }

                readonly property real normalWidth: 20
                readonly property real centerPos: normalWidth / 2 + displayRatio * (trackContainer.width - normalWidth)
                
                property real rubberBandOffset: 0
                Behavior on rubberBandOffset {
                    NumberAnimation {
                        duration: 240
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.40
                    }
                }

                property real expansion: (sDrag.pressed || slideGlideAnim.running) ? 1.0 : 0.0
                Behavior on expansion {
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.25
                    }
                }

                // Click-to-Jump Smooth Glide & Fluid Stretch Animation
                SequentialAnimation {
                    id: slideGlideAnim
                    property real startRatio: 0
                    property real targetRatio: 0
                    property real targetVal: 0

                    onStopped: {
                        knob.squashX = 1.0
                        knob.squashY = 1.0
                        sliderRoot.moved(slideGlideAnim.targetVal)
                    }

                    // Phase 1: Ngembang, Geser & Stretch (Slide, Bloom into Liquid Glass & Stretch) (160ms)
                    ParallelAnimation {
                        NumberAnimation {
                            target: trackContainer
                            property: "displayRatio"
                            from: slideGlideAnim.startRatio
                            to: slideGlideAnim.targetRatio
                            duration: 160
                            easing.type: Easing.InOutQuad
                        }
                        NumberAnimation {
                            target: knob
                            property: "squashX"
                            to: 1.30
                            duration: 140
                            easing.type: Easing.OutQuad
                        }
                        NumberAnimation {
                            target: knob
                            property: "squashY"
                            to: 0.86
                            duration: 140
                            easing.type: Easing.OutQuad
                        }
                    }

                    // Phase 2: Gel Impact Cushion ("Kepentok Gel Natural") (85ms)
                    ParallelAnimation {
                        NumberAnimation {
                            target: knob
                            property: "squashX"
                            to: 0.85
                            duration: 85
                            easing.type: Easing.OutQuad
                        }
                        NumberAnimation {
                            target: knob
                            property: "squashY"
                            to: 1.14
                            duration: 85
                            easing.type: Easing.OutQuad
                        }
                    }

                    // Phase 3: Soft Gel Rebound ("Membal Gel Organik") (75ms)
                    ParallelAnimation {
                        NumberAnimation {
                            target: knob
                            property: "squashX"
                            to: 1.04
                            duration: 75
                            easing.type: Easing.InOutQuad
                        }
                        NumberAnimation {
                            target: knob
                            property: "squashY"
                            to: 0.98
                            duration: 75
                            easing.type: Easing.InOutQuad
                        }
                    }

                    // Phase 4: Balik Normal (Settle back to Normal Round Porcelain Knob) (130ms)
                    ParallelAnimation {
                        NumberAnimation {
                            target: knob
                            property: "squashX"
                            to: 1.0
                            duration: 130
                            easing.type: Easing.OutQuad
                        }
                        NumberAnimation {
                            target: knob
                            property: "squashY"
                            to: 1.0
                            duration: 130
                            easing.type: Easing.OutQuad
                        }
                    }
                }

                // Boundary Impact Squash Animation (Natural Gel Cushion)
                SequentialAnimation {
                    id: sliderJiggleAnim
                    // Phase 1: Viscous Gel Impact Cushion (85ms)
                    ParallelAnimation {
                        NumberAnimation { target: knob; property: "squashX"; to: 0.85; duration: 85; easing.type: Easing.OutQuad }
                        NumberAnimation { target: knob; property: "squashY"; to: 1.14; duration: 85; easing.type: Easing.OutQuad }
                    }
                    // Phase 2: Soft Gel Rebound (75ms)
                    ParallelAnimation {
                        NumberAnimation { target: knob; property: "squashX"; to: 1.04; duration: 75; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: knob; property: "squashY"; to: 0.98; duration: 75; easing.type: Easing.InOutQuad }
                    }
                    // Phase 3: Settle Normal (130ms)
                    ParallelAnimation {
                        NumberAnimation { target: knob; property: "squashX"; to: 1.0; duration: 130; easing.type: Easing.OutQuad }
                        NumberAnimation { target: knob; property: "squashY"; to: 1.0; duration: 130; easing.type: Easing.OutQuad }
                    }
                }

                // Track Groove (Thin 4px Capsule)
                Rectangle {
                    id: trackGroove
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 4
                    radius: 2
                    color: Services.Theme.isDark ? "#2a2a34" : "#e0e2e8"
                    border.color: Services.Theme.isDark ? Qt.rgba(255, 255, 255, 0.04) : Qt.rgba(0, 0, 0, 0.04)
                    border.width: 1

                    // Active Filled Progress Bar
                    Rectangle {
                        height: parent.height
                        radius: parent.radius
                        color: Services.Theme.accent
                        width: Math.max(0, Math.min(parent.width, trackContainer.centerPos + trackContainer.rubberBandOffset))
                    }
                }

                // Liquid Glass Knob (Enlarged 40x26px Liquid Drop - Identical to SettingsSwitch)
                Rectangle {
                    id: knob
                    readonly property bool isActive: trackContainer.expansion > 0.01 || sDrag.pressed || sliderJiggleAnim.running || slideGlideAnim.running
                    width: 20 + trackContainer.expansion * 20
                    height: 20 + trackContainer.expansion * 6
                    radius: height / 2
                    anchors.verticalCenter: trackGroove.verticalCenter
                    x: Math.max(-4, Math.min(trackContainer.width - width + 4, trackContainer.centerPos - width / 2 + trackContainer.rubberBandOffset))

                    property real targetSquashX: 1.0
                    property real targetSquashY: 1.0
                    property real squashX: targetSquashX
                    property real squashY: targetSquashY

                    Behavior on squashX {
                        enabled: !sliderJiggleAnim.running && !slideGlideAnim.running
                        NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
                    }
                    Behavior on squashY {
                        enabled: !sliderJiggleAnim.running && !slideGlideAnim.running
                        NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
                    }

                    transform: Scale {
                        origin.x: knob.width / 2
                        origin.y: knob.height / 2
                        xScale: knob.squashX
                        yScale: knob.squashY
                    }

                    // Fluid Cross-Fade from White Porcelain (#ffffff) to Translucent Frosted Glass
                    color: Services.Theme.isDark 
                        ? Qt.rgba(1.0, 1.0, 1.0, 1.0 - trackContainer.expansion * 0.70)
                        : Qt.rgba(1.0, 1.0, 1.0, 1.0 - trackContainer.expansion * 0.30)
                    border.color: trackContainer.expansion > 0.01
                        ? (Services.Theme.isDark ? Qt.rgba(255, 255, 255, 0.55) : Qt.rgba(255, 255, 255, 0.90))
                        : Qt.rgba(0, 0, 0, 0.08)
                    border.width: trackContainer.expansion > 0.01 ? 1.2 : 1

                    // ── Optical Refraction Chamber (Pembiasan & Pembengkokan Pensil Dalam Air) ──
                    Item {
                        anchors.fill: parent
                        anchors.margins: 1.5
                        clip: true
                        opacity: trackContainer.expansion

                        // Refracted Track Core (Bent upwards with convex lens curvature & optical shift, exactly like SettingsSwitch)
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -2.2
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: -1
                            height: parent.height * 0.78
                            radius: height / 2
                            color: Services.Theme.accent
                            opacity: 0.85
                        }
                    }

                    // Soft Inner Glass Refraction Bevel
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: parent.radius - 1
                        color: "transparent"
                        border.color: Services.Theme.isDark ? Qt.rgba(255, 255, 255, 0.22) : Qt.rgba(255, 255, 255, 0.45)
                        border.width: 1
                        opacity: trackContainer.expansion
                    }

                    // Top Specular Glass Crescent Flare
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 1.5
                        height: Math.max(2, parent.height * 0.45)
                        radius: height / 2
                        opacity: trackContainer.expansion
                        gradient: Gradient {
                            GradientStop { 
                                position: 0.0
                                color: Services.Theme.isDark ? Qt.rgba(255, 255, 255, 0.55) : Qt.rgba(255, 255, 255, 0.80)
                            }
                            GradientStop { 
                                position: 1.0
                                color: "transparent"
                            }
                        }
                    }

                    // ── Background Optical Refraction Distortion Halo (Distorsi Latar Belakang) ──
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + 4
                        height: parent.height + 4
                        radius: height / 2
                        color: Services.Theme.accent
                        opacity: trackContainer.expansion * 0.40
                        z: -1
                    }

                    // Natural Soft Drop Shadow
                    Rectangle {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: 1.5
                        width: parent.width
                        height: parent.height
                        radius: parent.radius
                        color: Qt.rgba(0, 0, 0, 0.20)
                        opacity: 1.0 - trackContainer.expansion * 0.45
                        z: -2
                    }
                }

                MouseArea {
                    id: sDrag
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.topMargin: -8
                    anchors.bottomMargin: -8
                    preventStealing: true
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    property bool wasAtLimit: false
                    property real lastMouseX: 0
                    property real pressStartX: 0
                    property bool isDragging: false

                    function calcVal(mouseX) {
                        const pad = trackContainer.normalWidth / 2
                        const available = trackContainer.width - trackContainer.normalWidth
                        if (available <= 0) return sliderRoot.value

                        const ratio = Math.max(0, Math.min(1, (mouseX - pad) / available))
                        let raw = sliderRoot.from + ratio * (sliderRoot.to - sliderRoot.from)
                        if (sliderRoot.stepSize > 0) {
                            raw = Math.round((raw - sliderRoot.from) / sliderRoot.stepSize) * sliderRoot.stepSize + sliderRoot.from
                        }
                        return Math.max(sliderRoot.from, Math.min(sliderRoot.to, raw))
                    }

                    function updateVal(mouseX) {
                        const pad = trackContainer.normalWidth / 2
                        const available = trackContainer.width - trackContainer.normalWidth
                        if (available <= 0) return

                        // Calm Liquid Rubber-Band Edge Resistance
                        let atLimit = false
                        if (mouseX < pad) {
                            trackContainer.rubberBandOffset = (mouseX - pad) * 0.20
                            atLimit = true
                        } else if (mouseX > pad + available) {
                            trackContainer.rubberBandOffset = (mouseX - (pad + available)) * 0.20
                            atLimit = true
                        } else {
                            trackContainer.rubberBandOffset = 0
                        }

                        if (atLimit && !wasAtLimit) {
                            sliderJiggleAnim.restart()
                        }
                        wasAtLimit = atLimit

                        const raw = calcVal(mouseX)
                        sliderRoot.moved(raw)
                    }

                    onPressed: (mouse) => {
                        wasAtLimit = false
                        pressStartX = mouse.x
                        lastMouseX = mouse.x
                        isDragging = false

                        const currentPos = trackContainer.centerPos
                        // If clicking away from knob (more than 14px away), smoothly glide with liquid gel stretch!
                        if (Math.abs(mouse.x - currentPos) > 14) {
                            const pad = trackContainer.normalWidth / 2
                            const available = trackContainer.width - trackContainer.normalWidth
                            const targetRatio = Math.max(0, Math.min(1, (mouse.x - pad) / available))
                            const targetVal = calcVal(mouse.x)

                            slideGlideAnim.stop()
                            sliderJiggleAnim.stop()
                            slideGlideAnim.startRatio = trackContainer.displayRatio
                            slideGlideAnim.targetRatio = targetRatio
                            slideGlideAnim.targetVal = targetVal
                            slideGlideAnim.restart()
                        } else {
                            slideGlideAnim.stop()
                            updateVal(mouse.x)
                        }
                    }

                    onPositionChanged: (mouse) => {
                        if (!pressed) return
                        if (Math.abs(mouse.x - pressStartX) > 4) {
                            isDragging = true
                            slideGlideAnim.stop()
                        }
                        if (isDragging) {
                            const deltaX = mouse.x - lastMouseX
                            lastMouseX = mouse.x
                            const speed = Math.abs(deltaX)
                            knob.targetSquashX = Math.min(1.28, 1.0 + speed * 0.025)
                            knob.targetSquashY = Math.max(0.88, 1.0 - speed * 0.012)
                            updateVal(mouse.x)
                        }
                    }

                    onReleased: {
                        isDragging = false
                        knob.targetSquashX = 1.0
                        knob.targetSquashY = 1.0
                        if (trackContainer.rubberBandOffset !== 0) {
                            sliderJiggleAnim.restart()
                        }
                        trackContainer.rubberBandOffset = 0
                        wasAtLimit = false
                    }

                    onCanceled: {
                        isDragging = false
                        knob.targetSquashX = 1.0
                        knob.targetSquashY = 1.0
                        trackContainer.rubberBandOffset = 0
                        wasAtLimit = false
                    }

                    onWheel: (wheel) => {
                        slideGlideAnim.stop()
                        let delta = (wheel.angleDelta.y > 0 ? 1 : -1) * (sliderRoot.stepSize || 1)
                        let raw = Math.max(sliderRoot.from, Math.min(sliderRoot.to, sliderRoot.value + delta))
                        if (raw === sliderRoot.from || raw === sliderRoot.to) {
                            sliderJiggleAnim.restart()
                        }
                        sliderRoot.moved(raw)
                    }
                }
            }
        }
    }

    // ── 6. Hairline Divider ──────────────────────────────────────────────────
    component SettingsDivider: Rectangle {
        Layout.fillWidth: true
        height: 1
        color: Services.Theme.isDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.06)
    }

    // ── 7. Settings Key Recorder (Interactive Keyboard Shortcut Grabber) ──────
    component KeyRecorder: Rectangle {
        id: recRoot
        property string value: ""
        property bool isRecording: false
        property var heldModifiers: []
        property string placeholder: "Click to record shortcut..."
        property bool showClearButton: true
        property bool compact: false
        signal recorded(string keys)
        signal cleared()

        implicitHeight: compact ? 32 : 36
        radius: compact ? 6 : Services.Theme.radiusSm
        color: isRecording 
            ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.08)
            : (recMouse.containsMouse ? Services.Theme.surfaceVariant : Services.Theme.bgDeep)
        border.color: isRecording 
            ? Services.Theme.accent 
            : (recMouse.containsMouse ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.45) : Services.Theme.border)
        border.width: isRecording ? 1.5 : 1

        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }

        // Invisible key event receiver
        Item {
            id: keyReceiver
            anchors.fill: parent
            focus: recRoot.isRecording

            Keys.onPressed: (event) => {
                if (!recRoot.isRecording) return

                // Check for cancel with Escape (only when no modifiers held)
                if (event.key === Qt.Key_Escape && event.modifiers === Qt.NoModifier) {
                    recRoot.isRecording = false
                    recRoot.heldModifiers = []
                    event.accepted = true
                    return
                }

                // Check for Backspace/Delete to clear
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

                // If purely a modifier key was pressed, update held modifiers preview
                if (event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R || event.key === Qt.Key_Meta ||
                    event.key === Qt.Key_Control || event.key === Qt.Key_Alt || event.key === Qt.Key_Shift) {
                    recRoot.heldModifiers = mods
                    event.accepted = true
                    return
                }

                // Main non-modifier key pressed
                const keyName = recRoot.resolveKeyName(event.key, event.text)
                if (keyName && keyName.length > 0) {
                    const allParts = [...mods, keyName]
                    const resultStr = allParts.join(" + ")
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
            recRoot.heldModifiers = []
            recRoot.isRecording = true
            Qt.callLater(() => keyReceiver.forceActiveFocus())
        }

        function stopRecording() {
            recRoot.isRecording = false
            recRoot.heldModifiers = []
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: recRoot.compact ? 8 : 12
            anchors.rightMargin: recRoot.compact ? 8 : 12
            spacing: 8

            // Recording Pulsing Dot / Keyboard Icon
            Item {
                Layout.preferredWidth: recRoot.compact ? 16 : 20
                Layout.preferredHeight: recRoot.compact ? 16 : 20
                Layout.alignment: Qt.AlignVCenter

                Rectangle {
                    anchors.centerIn: parent
                    width: recRoot.isRecording ? 10 : 16
                    height: width
                    radius: width / 2
                    color: recRoot.isRecording ? Services.Theme.danger : "transparent"
                    visible: recRoot.isRecording

                    SequentialAnimation on scale {
                        running: recRoot.isRecording
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 1.4; duration: 550; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 1.4; to: 1.0; duration: 550; easing.type: Easing.InOutSine }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: !recRoot.isRecording
                    text: Services.Icons.keyboard || "󰌌"
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: recRoot.compact ? 11 : 13
                    color: recRoot.value.length > 0 ? Services.Theme.accent : Services.Theme.textDisabled
                }
            }

            // Key Badges / Recording Status Area
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                // Active Recording Mode
                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: recRoot.isRecording
                    spacing: 4

                    Repeater {
                        model: recRoot.heldModifiers
                        delegate: Rectangle {
                            height: recRoot.compact ? 20 : 24
                            width: hModTxt.implicitWidth + 12
                            radius: 4
                            color: Services.Theme.accent
                            Text {
                                id: hModTxt
                                anchors.centerIn: parent
                                text: modelData
                                font.family: Services.Theme.fontMono
                                font.pixelSize: recRoot.compact ? 8 : 9
                                font.bold: true
                                color: "#ffffff"
                            }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: recRoot.heldModifiers.length > 0 ? "+ press key..." : "Press key combination on keyboard..."
                        font.pixelSize: recRoot.compact ? 9 : 11
                        font.weight: Font.Medium
                        color: Services.Theme.accent
                        elide: Text.ElideRight
                    }
                }

                // Idle with Value: Physical-style Keycaps
                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !recRoot.isRecording && recRoot.value.length > 0
                    spacing: 4

                    readonly property var tokens: {
                        const raw = (recRoot.value || "").trim()
                        if (!raw) return []
                        return raw.split("+").map(s => s.trim()).filter(s => s.length > 0)
                    }

                    Repeater {
                        model: parent.tokens
                        delegate: Row {
                            id: tokRow
                            required property string modelData
                            required property int index
                            spacing: 4
                            anchors.verticalCenter: parent.verticalCenter

                            readonly property bool isMod: (tokRow.modelData.toUpperCase() === "SUPER" || tokRow.modelData.toUpperCase() === "CTRL" || tokRow.modelData.toUpperCase() === "ALT" || tokRow.modelData.toUpperCase() === "SHIFT")

                            Rectangle {
                                height: recRoot.compact ? 20 : 24
                                width: Math.max(22, tokTxt.implicitWidth + (recRoot.compact ? 8 : 12))
                                radius: 4
                                color: Services.Theme.bgElevated
                                border.color: tokRow.isMod ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.45) : Services.Theme.border
                                border.width: 1

                                Text {
                                    id: tokTxt
                                    anchors.centerIn: parent
                                    text: tokRow.modelData
                                    font.family: Services.Theme.fontMono
                                    font.pixelSize: recRoot.compact ? 8 : 9
                                    font.bold: true
                                    color: tokRow.isMod ? Services.Theme.accent : Services.Theme.textPrimary
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: tokRow.index < (parent.parent.tokens.length - 1)
                                text: "+"
                                font.pixelSize: recRoot.compact ? 8 : 9
                                font.bold: true
                                color: Services.Theme.textDisabled
                            }
                        }
                    }
                }

                // Idle Empty State
                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: !recRoot.isRecording && recRoot.value.length === 0
                    text: recRoot.placeholder
                    font.pixelSize: recRoot.compact ? 9 : 11
                    color: Services.Theme.textDisabled
                    elide: Text.ElideRight
                }
            }

            // Right Buttons (Record / Stop / Clear)
            RowLayout {
                spacing: 4
                Layout.alignment: Qt.AlignVCenter

                Rectangle {
                    height: recRoot.compact ? 22 : 26
                    implicitWidth: rBtnTxt.implicitWidth + (recRoot.compact ? 10 : 16)
                    radius: 4
                    color: recRoot.isRecording 
                        ? Services.Theme.danger
                        : (rBtnMouse.containsMouse ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.18) : Services.Theme.surfaceVariant)
                    border.color: recRoot.isRecording ? Services.Theme.danger : Services.Theme.border
                    border.width: 1

                    RowLayout {
                        id: rBtnTxt
                        anchors.centerIn: parent
                        spacing: 4
                        Text {
                            text: recRoot.isRecording ? (Services.Icons.close || "✕") : "Record"
                            font.pixelSize: recRoot.compact ? 8 : 10
                            font.weight: Font.DemiBold
                            color: recRoot.isRecording ? "#ffffff" : Services.Theme.textPrimary
                        }
                    }

                    MouseArea {
                        id: rBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (recRoot.isRecording) recRoot.stopRecording()
                            else recRoot.startRecording()
                        }
                    }
                }

                Rectangle {
                    visible: recRoot.showClearButton && !recRoot.isRecording && recRoot.value.length > 0
                    height: recRoot.compact ? 22 : 26
                    width: height
                    radius: 4
                    color: clrBtnMouse.containsMouse ? Qt.rgba(0.9, 0.2, 0.2, 0.15) : "transparent"
                    border.color: clrBtnMouse.containsMouse ? Services.Theme.danger : "transparent"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: recRoot.compact ? 8 : 10
                        font.bold: true
                        color: clrBtnMouse.containsMouse ? Services.Theme.danger : Services.Theme.textDisabled
                    }

                    MouseArea {
                        id: clrBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            recRoot.value = ""
                            recRoot.cleared()
                        }
                    }
                }
            }
        }

        MouseArea {
            id: recMouse
            anchors.fill: parent
            z: -1
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (!recRoot.isRecording) recRoot.startRecording()
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // WINDOW ROOT LAYOUT
    // ═════════════════════════════════════════════════════════════════════════

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── WINDOW HEADERBAR ──────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 50
            color: Services.Theme.surfaceVariant

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: Services.Theme.border
            }

            RowLayout {
                anchors.fill: parent
                spacing: 0

                // Left Header (Sidebar Search)
                Item {
                    Layout.preferredWidth: 236
                    Layout.fillHeight: true

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width - 24
                        height: 30
                        radius: 8
                        color: Services.Theme.isDark ? Qt.rgba(255, 255, 255, 0.06) : Qt.rgba(0, 0, 0, 0.04)
                        border.color: searchFocus.activeFocus ? Services.Theme.accent : (Services.Theme.isDark ? Qt.rgba(255, 255, 255, 0.08) : Qt.rgba(0, 0, 0, 0.08))
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6

                            Text {
                                text: Services.Icons.search || "󰍉"
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 12
                                color: searchFocus.activeFocus ? Services.Theme.accent : Services.Theme.textDisabled
                                Layout.alignment: Qt.AlignVCenter
                            }

                            TextInput {
                                id: searchFocus
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                text: rootWindow.sidebarSearchQuery
                                font.pixelSize: 12
                                color: Services.Theme.textPrimary
                                clip: true
                                selectByMouse: true
                                onTextChanged: rootWindow.sidebarSearchQuery = text

                                Text {
                                    visible: searchFocus.text.length === 0
                                    text: "Search Settings..."
                                    font.pixelSize: 12
                                    color: Services.Theme.textDisabled
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Text {
                                visible: searchFocus.text.length > 0
                                text: "✕"
                                font.pixelSize: 10
                                color: Services.Theme.textSecondary
                                Layout.alignment: Qt.AlignVCenter

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: searchFocus.text = ""
                                }
                            }
                        }
                    }
                }

                // Vertical Header Separator
                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    color: Services.Theme.border
                }

                // Right Header (Breadcrumb, Tab Title & Esc Badge)
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    spacing: 10

                    Text {
                        text: {
                            const icons = [
                                Services.Icons.palette,
                                Services.Icons.controlcenter,
                                Services.Icons.bell,
                                Services.Icons.speaker,
                                Services.Icons.power,
                                Services.Icons.display,
                                Services.Icons.keyboard,
                                Services.Icons.undo,
                                Services.Icons.info
                            ]
                            return icons[rootWindow.currentTab] || Services.Icons.settings
                        }
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 14
                        color: Services.Theme.accent
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Text {
                        text: "Settings"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: Services.Theme.textPrimary
                    }

                    Text {
                        text: "›"
                        font.pixelSize: 14
                        color: Services.Theme.textDisabled
                    }

                    Text {
                        text: {
                            const tabs = ["Appearance", "Bar & Dock", "Notifications", "Sound & Audio", "Lock & Power", "Compositor", "Keybindings", "Backup & Reset", "About"]
                            return tabs[rootWindow.currentTab] || "Preferences"
                        }
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: Services.Theme.accent
                    }

                    Item { Layout.fillWidth: true }

                    // Esc key badge
                    Rectangle {
                        implicitHeight: 20
                        implicitWidth: escText.implicitWidth + 12
                        radius: 5
                        color: Services.Theme.bgElevated
                        border.color: Services.Theme.border
                        border.width: 1
                        Text {
                            id: escText
                            anchors.centerIn: parent
                            text: "Esc"
                            font.family: Services.Theme.fontMono
                            font.pixelSize: 9
                            color: Services.Theme.textDisabled
                        }
                    }

                    // Minimal Close Button
                    Rectangle {
                        width: 26; height: 26; radius: 6
                        color: closeMouse.containsMouse ? Qt.rgba(0.9, 0.2, 0.2, 0.15) : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.close || "✕"
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 12
                            color: closeMouse.containsMouse ? Services.Theme.danger : Services.Theme.textSecondary
                        }
                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: rootWindow.hide()
                        }
                    }
                }
            }
        }

        // ── MAIN BODY: SIDEBAR + CONTENT PANE ─────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // ── LEFT SIDEBAR (Adaptive 190px - 236px) ───────────────────────
            Rectangle {
                Layout.preferredWidth: (rootWindow.width < 750) ? 190 : 236
                Layout.fillHeight: true
                color: Services.Theme.surfaceVariant

                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 1
                    color: Services.Theme.border
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    // User Profile Banner (Profile Card Style)
                    Rectangle {
                        id: sidebarUserBanner
                        Layout.fillWidth: true
                        height: 48
                        radius: 8
                        color: bannerMouse.containsMouse ? (Services.Theme.isDark ? Qt.rgba(255, 255, 255, 0.08) : Qt.rgba(0, 0, 0, 0.06)) : (Services.Theme.isDark ? Qt.rgba(255, 255, 255, 0.04) : Qt.rgba(0, 0, 0, 0.03))
                        border.color: bannerMouse.containsMouse ? Services.Theme.accent : Services.Theme.borderSubtle
                        border.width: 1

                        MouseArea {
                            id: bannerMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                rootWindow.currentTab = 4 // Jump to Lock & Power / User Profile & Avatar
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 8

                            // Avatar Squircle with Live Avatar
                            Services.AvatarFrame {
                                Layout.preferredWidth: 34
                                Layout.preferredHeight: 34
                                source: Services.OsInfo.avatarPath
                                shapeRadius: 8
                                backgroundColor: Services.Theme.accent
                                fallbackText: {
                                    const u = (Services.OsInfo.username || Quickshell.env("USER") || "user").toUpperCase()
                                    return u.length > 0 ? u.charAt(0) : "󰌽"
                                }
                                fallbackFontFamily: Services.Theme.fontSymbols
                                fallbackFontSize: 14
                                fallbackColor: Services.Theme.bgOnAccent
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 1

                                Text {
                                    Layout.fillWidth: true
                                    text: Services.OsInfo.username || Quickshell.env("USER") || "User"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    color: Services.Theme.textPrimary
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: Services.OsInfo.distroName || "Quickshell Desktop"
                                    font.pixelSize: 10
                                    color: Services.Theme.textSecondary
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    // Navigation Category List
                    ListView {
                        id: navList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 3
                        clip: false
                        interactive: false

                        readonly property var allNavTabs: [
                            { id: 0, title: "Appearance",    icon: Services.Icons.palette,       color: "#3b82f6", cat: "Personalization", kw: "appearance theme dark light wallpaper accent color font gtk icon cursor scale radius matugen compositor typography hinting antialiasing" },
                            { id: 1, title: "Bar & Dock",     icon: Services.Icons.controlcenter, color: "#8b5cf6", cat: "Personalization", kw: "bar dock application running pinned magnification island dynamic island notch workspaces clock date format pills dashboard weather cuaca widgets metrics hardware" },
                            { id: 2, title: "Notifications",  icon: Services.Icons.bell,          color: "#f97316", cat: "Personalization", kw: "notifications dnd do not disturb timeout retention banner history" },
                            { id: 3, title: "Sound & Audio",  icon: Services.Icons.speaker,       color: "#ec4899", cat: "Personalization", kw: "sound audio volume feedback clicks effects mute" },
                            { id: 4, title: "Lock & Power",   icon: Services.Icons.power,         color: "#ef4444", cat: "System",          kw: "lock screen power battery sleep timeout auth media clock blur faceid biometric face camera webcam" },
                            { id: 5, title: "Compositor",     icon: Services.Icons.display,       color: "#06b6d4", cat: "System",          kw: "compositor window blur borders animations displays monitors scaling input touchpad gestures power gaming" },
                            { id: 6, title: "Keybindings",    icon: Services.Icons.keyboard,      color: "#eab308", cat: "System",          kw: "keybindings shortcuts hotkeys binds compositor hyprland super mod" },
                            { id: 7, title: "Backup & Reset", icon: Services.Icons.undo,          color: "#10b981", cat: "Maintenance",     kw: "backup restore reset defaults export import config" },
                            { id: 8, title: "About",          icon: Services.Icons.info,          color: "#64748b", cat: "Maintenance",     kw: "about system os kernel quickshell version compositor distro info" }
                        ]

                        model: {
                            const q = (rootWindow.sidebarSearchQuery || "").toLowerCase().trim()
                            if (!q || q.length === 0) return allNavTabs
                            return allNavTabs.filter(item => {
                                return item.title.toLowerCase().indexOf(q) !== -1 || (item.kw && item.kw.indexOf(q) !== -1)
                            })
                        }

                        delegate: Rectangle {
                            width: navList.width
                            height: 38
                            radius: 8
                            readonly property bool isCur: rootWindow.currentTab === modelData.id
                            scale: tabMouse.pressed ? 0.98 : 1.0
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                            color: isCur 
                                ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.18)
                                : (tabMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.06) : "transparent")
                            border.color: isCur 
                                ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.45) 
                                : (tabMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.08) : "transparent")
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            // Top Specular Glass Highlight Line
                            Rectangle {
                                visible: isCur
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.topMargin: 1
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                height: 1
                                radius: 0.5
                                color: Qt.rgba(1, 1, 1, 0.35)
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 10
                                spacing: 10

                                // Squircle Icon Container (Unified Static Styling)
                                Rectangle {
                                    Layout.preferredWidth: 26
                                    Layout.preferredHeight: 26
                                    Layout.alignment: Qt.AlignVCenter
                                    radius: 7
                                    color: isCur ? Services.Theme.accent : Qt.rgba(1, 1, 1, 0.08)
                                    border.color: isCur ? Services.Theme.accent : Qt.rgba(1, 1, 1, 0.06)
                                    border.width: 1
                                    scale: isCur ? 1.06 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
                                    Behavior on color { ColorAnimation { duration: 180 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.icon
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: 13
                                        color: isCur ? (Services.Theme.bgOnAccent || "#ffffff") : (tabMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary)
                                        Behavior on color { ColorAnimation { duration: 180 } }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    text: modelData.title
                                    font.pixelSize: 13
                                    font.weight: isCur ? Font.DemiBold : Font.Normal
                                    color: isCur ? Services.Theme.textPrimary : (tabMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary)
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: isCur || tabMouse.containsMouse
                                    text: "›"
                                    font.pixelSize: 13
                                    color: isCur ? Services.Theme.accent : Services.Theme.textDisabled
                                    Layout.alignment: Qt.AlignVCenter
                                    scale: isCur ? 1.1 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
                                }
                            }

                            MouseArea {
                                id: tabMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (rootWindow.currentTab !== modelData.id) {
                                        if (modelData.id === 5) rootWindow.compSubTab = 0
                                        rootWindow.currentTab = modelData.id
                                    }
                                    if (modelData.id === 5 && Services.Compositor) {
                                        Services.Compositor.refreshState()
                                        Services.Compositor.loadAutostart()
                                    }
                                    if (modelData.id === 6 && Services.Compositor) Services.Compositor.loadKeybinds()
                                }
                            }
                        }
                    }

                    // Sidebar Footer: Distro & Protocol Badge
                    Rectangle {
                        Layout.fillWidth: true
                        height: 32
                        radius: 6
                        color: Services.Theme.bgElevated
                        border.color: Services.Theme.border
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6

                            Text {
                                text: Services.OsInfo.logoGlyph || Services.Icons.kernel || "󰌽"
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 13
                                color: Services.Theme.accent
                            }

                            Text {
                                Layout.fillWidth: true
                                text: Services.OsInfo.distroName || "Linux"
                                font.pixelSize: 10
                                font.weight: Font.Medium
                                color: Services.Theme.textSecondary
                                elide: Text.ElideRight
                            }

                            Text {
                                text: "Wayland"
                                font.pixelSize: 9
                                font.family: Services.Theme.fontMono
                                color: Services.Theme.textDisabled
                            }
                        }
                    }
                }
            }

            // ── RIGHT SETTINGS CONTENT PANE ──────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Services.Theme.bg
                clip: true

                Flickable {
                    id: contentFlick
                    anchors.fill: parent
                    anchors.margins: (rootWindow.width < 750) ? 12 : 18
                    contentHeight: Math.max(contentFlick.height, tabStack.currentContentHeight + 40)
                    contentWidth: width
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    StackLayout {
                        id: tabStack
                        width: contentFlick.width - 10
                        currentIndex: rootWindow.currentTab

                        readonly property var tabItems: [tab0, tab1, tab2, tab3, tab4, tab5, tab6, tab7, tab8]
                        readonly property Item currentItem: (currentIndex >= 0 && currentIndex < tabItems.length) ? tabItems[currentIndex] : null
                        readonly property real currentContentHeight: currentItem ? currentItem.implicitHeight : implicitHeight

                        height: currentContentHeight

                        // ═════════════════════════════════════════════
                        // TAB 0: APPEARANCE & THEMING (GNOME 47 / TAHOE PRO STYLE)
                        // ═════════════════════════════════════════════
                        ColumnLayout {
                            id: tab0
                            Layout.fillWidth: true
                            spacing: 16

                            // ── 1. Style & Accent Colors (GNOME 47 Style Visual Cards) ──
                            SettingsSection {
                                title: "Style & Colors"
                                icon: Services.Icons.palette || "󰏘"

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.margins: 12
                                    spacing: 12

                                    // Visual Theme Cards Row
                                    RowLayout {
                                        Layout.alignment: Qt.AlignHCenter
                                        spacing: 24

                                        // Light Mode Mockup Card
                                        Rectangle {
                                            Layout.preferredWidth: 136
                                            Layout.preferredHeight: 114
                                            color: "transparent"

                                            ColumnLayout {
                                                id: lightCol
                                                anchors.fill: parent
                                                spacing: 8
                                                Layout.alignment: Qt.AlignHCenter

                                                Rectangle {
                                                    width: 136
                                                    height: 84
                                                    radius: 8
                                                    color: "#f5f6f9"
                                                    border.color: (Services.Config && Services.Config.themeMode === "light") ? Services.Theme.accent : (lightMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.border)
                                                    border.width: (Services.Config && Services.Config.themeMode === "light") ? 2 : 1
                                                    clip: true
                                                    scale: (Services.Config && Services.Config.themeMode === "light") ? 1.03 : (lightMouse.pressed ? 0.95 : (lightMouse.containsMouse ? 1.02 : 1.0))
                                                    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.35 } }

                                                    // Mini Window Mockup
                                                    ColumnLayout {
                                                        anchors.fill: parent
                                                        spacing: 0

                                                        // Mockup Titlebar
                                                        Rectangle {
                                                            Layout.fillWidth: true
                                                            height: 18
                                                            color: "#e8eaef"

                                                            Rectangle {
                                                                anchors.left: parent.left
                                                                anchors.leftMargin: 8
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                width: 24; height: 4; radius: 2
                                                                color: "#c8ccd6"
                                                            }
                                                        }

                                                        // Mockup Body
                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            Layout.fillHeight: true
                                                            spacing: 0

                                                            // Mockup Sidebar
                                                            Rectangle {
                                                                Layout.preferredWidth: 36
                                                                Layout.fillHeight: true
                                                                color: "#e2e5eb"

                                                                ColumnLayout {
                                                                    anchors.fill: parent
                                                                    anchors.margins: 4
                                                                    spacing: 3
                                                                    Rectangle { Layout.fillWidth: true; height: 4; radius: 2; color: "#0071e3" }
                                                                    Rectangle { Layout.fillWidth: true; height: 4; radius: 2; color: "#cbd1db" }
                                                                    Rectangle { Layout.fillWidth: true; height: 4; radius: 2; color: "#cbd1db" }
                                                                }
                                                            }

                                                            // Mockup Content Card
                                                            Rectangle {
                                                                Layout.fillWidth: true
                                                                Layout.fillHeight: true
                                                                color: "#f5f6f9"

                                                                Rectangle {
                                                                    anchors.centerIn: parent
                                                                    width: parent.width - 10
                                                                    height: parent.height - 10
                                                                    radius: 4
                                                                    color: "#ffffff"
                                                                    border.color: "#e2e5eb"
                                                                    border.width: 1
                                                                }
                                                            }
                                                        }
                                                    }
                                                }

                                                // Radio Selector
                                                RowLayout {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    spacing: 6

                                                    Rectangle {
                                                        width: 14; height: 14; radius: 7
                                                        color: "transparent"
                                                        border.color: (Services.Config && Services.Config.themeMode === "light") ? Services.Theme.accent : Services.Theme.border
                                                        border.width: 1.5

                                                        Rectangle {
                                                            anchors.centerIn: parent
                                                            width: 6; height: 6; radius: 3
                                                            color: Services.Theme.accent
                                                            scale: (Services.Config && Services.Config.themeMode === "light") ? 1.0 : 0.0
                                                            opacity: (Services.Config && Services.Config.themeMode === "light") ? 1.0 : 0.0
                                                            Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.5 } }
                                                            Behavior on opacity { NumberAnimation { duration: 180 } }
                                                        }
                                                    }

                                                    Text {
                                                        text: "Light"
                                                        font.pixelSize: 12
                                                        font.weight: (Services.Config && Services.Config.themeMode === "light") ? Font.DemiBold : Font.Normal
                                                        color: (Services.Config && Services.Config.themeMode === "light") ? Services.Theme.textPrimary : Services.Theme.textSecondary
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                id: lightMouse
                                                anchors.fill: parent
                                                z: 50
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (Services.Config) Services.Config.setThemeMode("light")
                                                    if (Services.SystemTheme) Services.SystemTheme.setColorScheme("prefer-light")
                                                }
                                            }
                                        }

                                        // Dark Mode Mockup Card
                                        Rectangle {
                                            Layout.preferredWidth: 136
                                            Layout.preferredHeight: 114
                                            color: "transparent"

                                            ColumnLayout {
                                                id: darkCol
                                                anchors.fill: parent
                                                spacing: 8
                                                Layout.alignment: Qt.AlignHCenter

                                                Rectangle {
                                                    width: 136
                                                    height: 84
                                                    radius: 8
                                                    color: "#18181c"
                                                    border.color: (Services.Config && Services.Config.themeMode === "dark") ? Services.Theme.accent : (darkMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.border)
                                                    border.width: (Services.Config && Services.Config.themeMode === "dark") ? 2 : 1
                                                    clip: true
                                                    scale: (Services.Config && Services.Config.themeMode === "dark") ? 1.03 : (darkMouse.pressed ? 0.95 : (darkMouse.containsMouse ? 1.02 : 1.0))
                                                    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.35 } }

                                                    // Mini Window Mockup
                                                    ColumnLayout {
                                                        anchors.fill: parent
                                                        spacing: 0

                                                        // Mockup Titlebar
                                                        Rectangle {
                                                            Layout.fillWidth: true
                                                            height: 18
                                                            color: "#222228"

                                                            Rectangle {
                                                                anchors.left: parent.left
                                                                anchors.leftMargin: 8
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                width: 24; height: 4; radius: 2
                                                                color: "#383844"
                                                            }
                                                        }

                                                        // Mockup Body
                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            Layout.fillHeight: true
                                                            spacing: 0

                                                            // Mockup Sidebar
                                                            Rectangle {
                                                                Layout.preferredWidth: 36
                                                                Layout.fillHeight: true
                                                                color: "#1d1d24"

                                                                ColumnLayout {
                                                                    anchors.fill: parent
                                                                    anchors.margins: 4
                                                                    spacing: 3
                                                                    Rectangle { Layout.fillWidth: true; height: 4; radius: 2; color: Services.Theme.accent }
                                                                    Rectangle { Layout.fillWidth: true; height: 4; radius: 2; color: "#32323e" }
                                                                    Rectangle { Layout.fillWidth: true; height: 4; radius: 2; color: "#32323e" }
                                                                }
                                                            }

                                                            // Mockup Content Card
                                                            Rectangle {
                                                                Layout.fillWidth: true
                                                                Layout.fillHeight: true
                                                                color: "#141418"

                                                                Rectangle {
                                                                    anchors.centerIn: parent
                                                                    width: parent.width - 10
                                                                    height: parent.height - 10
                                                                    radius: 4
                                                                    color: "#24242e"
                                                                    border.color: "#32323e"
                                                                    border.width: 1
                                                                }
                                                            }
                                                        }
                                                    }
                                                }

                                                // Radio Selector
                                                RowLayout {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    spacing: 6

                                                    Rectangle {
                                                        width: 14; height: 14; radius: 7
                                                        color: "transparent"
                                                        border.color: (Services.Config && Services.Config.themeMode === "dark") ? Services.Theme.accent : Services.Theme.border
                                                        border.width: 1.5

                                                        Rectangle {
                                                            anchors.centerIn: parent
                                                            width: 6; height: 6; radius: 3
                                                            color: Services.Theme.accent
                                                            scale: (Services.Config && Services.Config.themeMode === "dark") ? 1.0 : 0.0
                                                            opacity: (Services.Config && Services.Config.themeMode === "dark") ? 1.0 : 0.0
                                                            Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.5 } }
                                                            Behavior on opacity { NumberAnimation { duration: 180 } }
                                                        }
                                                    }

                                                    Text {
                                                        text: "Dark"
                                                        font.pixelSize: 12
                                                        font.weight: (Services.Config && Services.Config.themeMode === "dark") ? Font.DemiBold : Font.Normal
                                                        color: (Services.Config && Services.Config.themeMode === "dark") ? Services.Theme.textPrimary : Services.Theme.textSecondary
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                id: darkMouse
                                                anchors.fill: parent
                                                z: 50
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (Services.Config) Services.Config.setThemeMode("dark")
                                                    if (Services.SystemTheme) Services.SystemTheme.setColorScheme("prefer-dark")
                                                }
                                            }
                                        }
                                    }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Matugen Dynamic Theme"
                                    subtitle: "Extract harmonious palette directly from wallpaper"
                                    checked: Services.Config ? Services.Config.useMatugen : false
                                    onToggled: (st) => {
                                        if (Services.Config) {
                                            Services.Config.setUseMatugen(st, Services.Wallpaper ? Services.Wallpaper.currentWallpaper : "")
                                        }
                                    }
                                }

                                SettingsDivider {}

                                // Accent Colors Sub-Section
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.margins: 10
                                    spacing: 10

                                    // Circular Color Chips Row
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignHCenter
                                        spacing: 12

                                        Repeater {
                                            model: Services.Config ? Services.Config.accentPresets : []
                                            delegate: Item {
                                                required property var modelData
                                                width: 32; height: 32
                                                readonly property bool isCur: Services.Config && Services.Config.accentName === modelData.name
                                                scale: isCur ? 1.14 : (dotMouse.pressed ? 0.92 : (dotMouse.containsMouse ? 1.08 : 1.0))
                                                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.55 } }

                                                // Concentric Selection Ring
                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: 16
                                                    color: "transparent"
                                                    border.color: isCur ? Services.Theme.accent : (dotMouse.containsMouse ? Services.Theme.borderHighlight : "transparent")
                                                    border.width: isCur ? 2 : 1
                                                    Behavior on border.color { ColorAnimation { duration: 150 } }
                                                }

                                                // Color Dot
                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: 22; height: 22
                                                    radius: 11
                                                    color: modelData.preview || (Services.Config && Services.Config.themeMode === "light" ? modelData.lightHex : modelData.darkHex)

                                                    // Matugen multicolor ring or sparkle icon
                                                    Text {
                                                        visible: modelData.isMatugen === true && !isCur
                                                        anchors.centerIn: parent
                                                        text: "✦"
                                                        font.pixelSize: 10
                                                        color: "#ffffff"
                                                    }

                                                    // Active Checkmark Icon
                                                    Text {
                                                        visible: isCur
                                                        anchors.centerIn: parent
                                                        text: Services.Icons.check || "✓"
                                                        font.family: Services.Theme.fontSymbols
                                                        font.pixelSize: 10
                                                        font.bold: true
                                                        color: Services.Theme.bgOnAccent
                                                    }
                                                }

                                                MouseArea {
                                                    id: dotMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (Services.Config) {
                                                            const hex = (Services.Config.themeMode === "light") ? modelData.lightHex : modelData.darkHex
                                                            Services.Config.setAccent(hex, modelData.name, modelData.isMatugen)
                                                            if (modelData.isMatugen && Services.Wallpaper) Services.Config.generateMatugen(Services.Wallpaper.currentWallpaper)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Active Palette Subtitle
                                    RowLayout {
                                        Layout.alignment: Qt.AlignHCenter
                                        spacing: 6

                                        Text {
                                            text: "Current Accent:"
                                            font.pixelSize: 11
                                            color: Services.Theme.textSecondary
                                        }

                                        Text {
                                            text: Services.Config ? Services.Config.accentName : "Default"
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            color: Services.Theme.accent
                                        }
                                    }
                                }
                            }

                            // ── 2. Desktop Wallpaper Section ──
                            SettingsSection {
                                title: "Desktop Wallpaper"
                                icon: Services.Icons.image || "󰋩"

                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: 90
                                    Layout.margins: 10

                                    Flickable {
                                        anchors.fill: parent
                                        contentWidth: wpListRow.implicitWidth
                                        contentHeight: parent.height
                                        clip: true
                                        boundsBehavior: Flickable.StopAtBounds

                                        RowLayout {
                                            id: wpListRow
                                            spacing: 10

                                            Repeater {
                                                model: Services.Wallpaper ? Services.Wallpaper.allWallpapers : []
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    width: (rootWindow.width < 750) ? 104 : 116
                                                    height: (rootWindow.width < 750) ? 68 : 76
                                                    radius: 8
                                                    clip: true
                                                    readonly property bool isCur: Services.Wallpaper && Services.Wallpaper.currentWallpaper === modelData.path
                                                    border.color: isCur ? Services.Theme.accent : (wCardMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.border)
                                                    border.width: isCur ? 2 : 1
                                                    color: Services.Theme.bgDeep
                                                    scale: isCur ? 1.03 : (wCardMouse.pressed ? 0.96 : (wCardMouse.containsMouse ? 1.02 : 1.0))
                                                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.35 } }

                                                    Image {
                                                        anchors.fill: parent
                                                        source: modelData.path.startsWith("/") ? ("file://" + modelData.path) : modelData.path
                                                        sourceSize: Qt.size(232, 152)
                                                        fillMode: Image.PreserveAspectCrop
                                                        asynchronous: true
                                                        cache: true
                                                        smooth: true
                                                        opacity: isCur || wCardMouse.containsMouse ? 1.0 : 0.8
                                                    }

                                                    Rectangle {
                                                        visible: isCur
                                                        anchors.top: parent.top; anchors.right: parent.right
                                                        anchors.margins: 5
                                                        width: 18; height: 18; radius: 9
                                                        color: Services.Theme.accent
                                                        Text { anchors.centerIn: parent; text: Services.Icons.check || "✓"; font.family: Services.Theme.fontSymbols; font.pixelSize: 9; color: Services.Theme.bgOnAccent }
                                                    }

                                                    Rectangle {
                                                        visible: (modelData.isCustom === true) && (wCardMouse.containsMouse || delMouse.containsMouse)
                                                        anchors.top: parent.top; anchors.left: parent.left
                                                        anchors.margins: 5
                                                        width: 18; height: 18; radius: 9
                                                        color: delMouse.containsMouse ? Services.Theme.danger : Qt.rgba(0, 0, 0, 0.65)
                                                        border.color: Qt.rgba(1, 1, 1, 0.2)
                                                        border.width: 1
                                                        z: 2

                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: Services.Icons.trash || ""
                                                            font.family: Services.Theme.fontSymbols
                                                            font.pixelSize: 9
                                                            color: "#ffffff"
                                                        }

                                                        MouseArea {
                                                            id: delMouse
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (Services.Wallpaper) {
                                                                    Services.Wallpaper.removeCustomWallpaper(modelData.path)
                                                                }
                                                            }
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: wCardMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (Services.Wallpaper) {
                                                                Services.Wallpaper.setWallpaper(modelData.path)
                                                                if (Services.Config && Services.Config.useMatugen) Services.Config.generateMatugen(modelData.path)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Custom Wallpaper"
                                    subtitle: "Add image file from local storage"

                                    Rectangle {
                                        implicitHeight: 28
                                        implicitWidth: addBtnText.implicitWidth + 16
                                        radius: 6
                                        color: addWpMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Services.Theme.bgElevated
                                        border.color: Services.Theme.border
                                        border.width: 1
                                        scale: addWpMouse.pressed ? 0.95 : (addWpMouse.containsMouse ? 1.03 : 1.0)
                                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }

                                        Text {
                                            id: addBtnText
                                            anchors.centerIn: parent
                                            text: "+ Add Image..."
                                            font.pixelSize: 11
                                            font.weight: Font.Medium
                                            color: Services.Theme.textPrimary
                                        }

                                        MouseArea {
                                            id: addWpMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: { if (Services.Wallpaper) Services.Wallpaper.pickCustomWallpaper() }
                                        }
                                    }
                                }
                            }

                            // ── 3. Application & Desktop Themes (GTK, Icons, Cursors) ──
                            SettingsSection {
                                title: "Application & Desktop Theming"
                                icon: Services.Icons.sparkle || "󰮄"

                                SettingsRow {
                                    title: "GTK Application Theme"
                                    subtitle: "Visual style applied to GTK3, GTK4 & Libadwaita applications"

                                    SettingsDropdown {
                                        minButtonWidth: 160
                                        searchable: true
                                        currentValue: Services.SystemTheme ? Services.SystemTheme.currentGtkTheme : "Tahoe-Dark"
                                        model: Services.SystemTheme ? Services.SystemTheme.gtkThemes : []
                                        onSelected: (val) => {
                                            if (Services.SystemTheme) Services.SystemTheme.setGtkTheme(val)
                                        }
                                    }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Icon Theme"
                                    subtitle: "System-wide application and folder icon pack"

                                    SettingsDropdown {
                                        minButtonWidth: 160
                                        searchable: true
                                        currentValue: Services.SystemTheme ? Services.SystemTheme.currentIconTheme : "MacTahoe-dark"
                                        model: Services.SystemTheme ? Services.SystemTheme.iconThemes : []
                                        onSelected: (val) => {
                                            if (Services.SystemTheme) Services.SystemTheme.setIconTheme(val)
                                        }
                                    }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Cursor Theme"
                                    subtitle: "Mouse pointer theme for Wayland session and apps"

                                    SettingsDropdown {
                                        minButtonWidth: 160
                                        searchable: true
                                        currentValue: Services.SystemTheme ? Services.SystemTheme.currentCursorTheme : "MacTahoe-dark"
                                        model: Services.SystemTheme ? Services.SystemTheme.cursorThemes : []
                                        onSelected: (val) => {
                                            if (Services.SystemTheme) Services.SystemTheme.setCursorTheme(val)
                                        }
                                    }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Cursor Size"
                                    subtitle: "Physical cursor size in pixels"

                                    SettingsDropdown {
                                        minButtonWidth: 130
                                        currentValue: Services.SystemTheme ? Services.SystemTheme.currentCursorSize : 24
                                        model: Services.SystemTheme ? Services.SystemTheme.cursorSizes : []
                                        onSelected: (val) => {
                                            if (Services.SystemTheme) Services.SystemTheme.setCursorSize(val)
                                        }
                                    }
                                }
                            }

                            // ── 4. Quickshell Desktop Typography ──
                            SettingsSection {
                                title: "Quickshell Desktop Typography"
                                icon: Services.Icons.font || "󰛄"

                                SettingsRow {
                                    title: "Primary Shell UI Font"
                                    subtitle: "Typography for panel widgets, menus, launcher, and control center"

                                    SettingsDropdown {
                                        minButtonWidth: 210
                                        searchable: true
                                        currentValue: Services.Config ? Services.Config.fontFamily : "Liga SFMono Nerd Font, monospace"
                                        model: Services.SystemTheme ? Services.SystemTheme.systemFonts : []
                                        onSelected: (val) => {
                                            if (Services.Config) Services.Config.setFontFamily(val)
                                        }
                                    }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Monospace & Metrics Font"
                                    subtitle: "Fixed-width font for clock, hardware sysmon gauges, and battery"

                                    SettingsDropdown {
                                        minButtonWidth: 210
                                        searchable: true
                                        currentValue: Services.Config ? Services.Config.fontMono : "Liga SFMono Nerd Font, monospace"
                                        model: Services.SystemTheme ? Services.SystemTheme.monospaceFonts : []
                                        onSelected: (val) => {
                                            if (Services.Config) Services.Config.setFontMono(val)
                                        }
                                    }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Display & Header Font"
                                    subtitle: "Stylized font for hero lockscreen clocks, large widget titles, and card headers"

                                    SettingsDropdown {
                                        minButtonWidth: 210
                                        searchable: true
                                        currentValue: Services.Config ? Services.Config.fontDisplay : "SF Pro Display, Inter, Sans-Serif"
                                        model: Services.SystemTheme ? Services.SystemTheme.systemFonts : []
                                        onSelected: (val) => {
                                            if (Services.Config) Services.Config.setFontDisplay(val)
                                        }
                                    }
                                }
                            }

                            // ── 5. System & GTK Typography (GNOME & Applications) ──
                            SettingsSection {
                                title: "System & GTK Application Typography"
                                icon: Services.Icons.sliders || "󰛄"

                                SettingsRow {
                                    title: "Interface Font"
                                    subtitle: "Primary typography for UI labels, widgets, and clock"

                                    RowLayout {
                                        spacing: 8
                                        Layout.alignment: Qt.AlignVCenter

                                        SettingsDropdown {
                                            minButtonWidth: 155
                                            searchable: true
                                            currentValue: Services.SystemTheme ? Services.SystemTheme.currentFontFamily : "Liga SFMonoNerdFont"
                                            model: Services.SystemTheme ? Services.SystemTheme.systemFonts : []
                                            onSelected: (val) => {
                                                if (Services.SystemTheme) Services.SystemTheme.setFont("interface", val, Services.SystemTheme.currentFontSize)
                                            }
                                        }

                                        SettingsDropdown {
                                            minButtonWidth: 70
                                            currentValue: Services.SystemTheme ? Services.SystemTheme.currentFontSize : 11
                                            model: [8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 20].map(s => ({ id: s, label: s + " pt" }))
                                            onSelected: (sz) => {
                                                if (Services.SystemTheme) Services.SystemTheme.setFont("interface", Services.SystemTheme.currentFontFamily, sz)
                                            }
                                        }
                                    }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Document Font"
                                    subtitle: "Standard reading font for documents and previewers"

                                    RowLayout {
                                        spacing: 8
                                        Layout.alignment: Qt.AlignVCenter

                                        SettingsDropdown {
                                            minButtonWidth: 155
                                            searchable: true
                                            currentValue: Services.SystemTheme ? Services.SystemTheme.currentDocFontFamily : "Adwaita Sans"
                                            model: Services.SystemTheme ? Services.SystemTheme.systemFonts : []
                                            onSelected: (val) => {
                                                if (Services.SystemTheme) Services.SystemTheme.setFont("document", val, Services.SystemTheme.currentDocFontSize)
                                            }
                                        }

                                        SettingsDropdown {
                                            minButtonWidth: 70
                                            currentValue: Services.SystemTheme ? Services.SystemTheme.currentDocFontSize : 12
                                            model: [8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 20].map(s => ({ id: s, label: s + " pt" }))
                                            onSelected: (sz) => {
                                                if (Services.SystemTheme) Services.SystemTheme.setFont("document", Services.SystemTheme.currentDocFontFamily, sz)
                                            }
                                        }
                                    }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Monospace / Terminal Font"
                                    subtitle: "Fixed-width font for terminals, code editors, and logs"

                                    RowLayout {
                                        spacing: 8
                                        Layout.alignment: Qt.AlignVCenter

                                        SettingsDropdown {
                                            minButtonWidth: 155
                                            searchable: true
                                            currentValue: Services.SystemTheme ? Services.SystemTheme.currentMonoFontFamily : "Adwaita Mono"
                                            model: Services.SystemTheme ? Services.SystemTheme.monospaceFonts : []
                                            onSelected: (val) => {
                                                if (Services.SystemTheme) Services.SystemTheme.setFont("monospace", val, Services.SystemTheme.currentMonoFontSize)
                                            }
                                        }

                                        SettingsDropdown {
                                            minButtonWidth: 70
                                            currentValue: Services.SystemTheme ? Services.SystemTheme.currentMonoFontSize : 11
                                            model: [8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 20].map(s => ({ id: s, label: s + " pt" }))
                                            onSelected: (sz) => {
                                                if (Services.SystemTheme) Services.SystemTheme.setFont("monospace", Services.SystemTheme.currentMonoFontFamily, sz)
                                            }
                                        }
                                    }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Font Hinting"
                                    subtitle: "Glyph outline alignment to pixel grid for crisp rendering"

                                    SettingsDropdown {
                                        minButtonWidth: 140
                                        currentValue: Services.SystemTheme ? Services.SystemTheme.currentFontHinting : "slight"
                                        model: [
                                            { id: "none",   label: "None" },
                                            { id: "slight", label: "Slight (Default)" },
                                            { id: "medium", label: "Medium" },
                                            { id: "full",   label: "Full" }
                                        ]
                                        onSelected: (val) => {
                                            if (Services.SystemTheme) Services.SystemTheme.setFontHinting(val)
                                        }
                                    }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Font Antialiasing"
                                    subtitle: "Subpixel smoothing technique for display sharpness"

                                    SettingsDropdown {
                                        minButtonWidth: 155
                                        currentValue: Services.SystemTheme ? Services.SystemTheme.currentFontAntialiasing : "grayscale"
                                        model: [
                                            { id: "rgba",      label: "Subpixel (RGBA / LCD)" },
                                            { id: "grayscale", label: "Standard (Grayscale)" },
                                            { id: "none",      label: "None" }
                                        ]
                                        onSelected: (val) => {
                                            if (Services.SystemTheme) Services.SystemTheme.setFontAntialiasing(val)
                                        }
                                    }
                                }

                                SettingsDivider {}

                                SettingsSlider {
                                    title: "Text Scaling Factor"
                                    subtitle: "System-wide text size multiplier across GTK and Wayland"
                                    from: 0.75; to: 1.75; stepSize: 0.05; decimals: 2; valueSuffix: "x"
                                    value: Services.SystemTheme ? Services.SystemTheme.currentTextScaling : 1.0
                                    onMoved: (v) => {
                                        if (Services.SystemTheme) Services.SystemTheme.setTextScaling(Number(v.toFixed(2)))
                                    }
                                }
                            }

                            // ── 6. Shell Geometry & Scaling ──
                            SettingsSection {
                                title: "Shell Geometry & Scaling"
                                icon: Services.Icons.sliders || "󰛄"

                                SettingsSlider {
                                    title: "Corner Rounding"
                                    subtitle: "Radius for quickshell panels, widgets, and popup overlays"
                                    from: 0; to: 32; stepSize: 1; valueSuffix: "px"
                                    value: Services.Config ? Services.Config.cornerRadius : 16
                                    onMoved: (v) => { if (Services.Config) Services.Config.setCornerRadius(Math.round(v)) }
                                }

                                SettingsDivider {}

                                SettingsSlider {
                                    title: "Surface Glass Opacity"
                                    subtitle: "Transparency level of quickshell overlay cards and panels"
                                    from: 0.50; to: 1.00; stepSize: 0.05; decimals: 2
                                    value: Services.Config ? Services.Config.glassOpacity : 0.85
                                    onMoved: (v) => { if (Services.Config) Services.Config.setGlassOpacity(Number(v.toFixed(2))) }
                                }

                                SettingsDivider {}

                                SettingsSlider {
                                    title: "Quickshell UI Scale"
                                    subtitle: "Proportional scaling factor for all shell overlays"
                                    from: 75; to: 135; stepSize: 5; valueSuffix: "%"
                                    value: Services.Config ? Math.round(Services.Config.uiScale * 100) : 100
                                    onMoved: (v) => { if (Services.Config) Services.Config.setUiScale(v / 100) }
                                }
                            }
                        }

                        // ═════════════════════════════════════════════
                        // TAB 1: BAR & DOCK (SEGMENTED)
                        // ═════════════════════════════════════════════
                        ColumnLayout {
                            id: tab1
                            Layout.fillWidth: true
                            spacing: 14

                            property int barSubTab: 0 // 0: Status Bar & Island, 1: Application Dock
                            property string appSearchText: ""
                            property bool isAddingApp: false

                            // ── Segmented Switcher: [ Status Bar & Island | Application Dock ] ──
                            Rectangle {
                                id: barSubTabBar
                                Layout.fillWidth: true
                                height: 38
                                radius: 8
                                color: Services.Theme.isDark ? "#16161c" : "#e8ecf2"
                                border.color: Services.Theme.border
                                border.width: 1
                                clip: true

                                readonly property int subTabCount: 2
                                readonly property real itemWidth: Math.max(0, (barSubTabBar.width - 6 - (subTabCount - 1) * 3) / subTabCount)

                                Rectangle {
                                    id: barLiquidPill
                                    z: 1
                                    y: 3
                                    height: parent.height - 6
                                    radius: 6
                                    x: 3 + tab1.barSubTab * (barSubTabBar.itemWidth + 3)
                                    width: barSubTabBar.itemWidth
                                    color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.22)
                                    border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.55)
                                    border.width: 1

                                    Behavior on x {
                                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                                    }
                                }

                                Row {
                                    anchors.fill: parent
                                    anchors.margins: 3
                                    spacing: 3
                                    z: 2

                                    Item {
                                        width: barSubTabBar.itemWidth
                                        height: parent.height

                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: 8
                                            Text {
                                                text: Services.Icons.controlcenter || "󰕮"
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 13
                                                color: tab1.barSubTab === 0 ? Services.Theme.accent : Services.Theme.textSecondary
                                            }
                                            Text {
                                                text: "Status Bar & Island"
                                                font.pixelSize: 12
                                                font.weight: tab1.barSubTab === 0 ? Font.DemiBold : Font.Normal
                                                color: tab1.barSubTab === 0 ? Services.Theme.textPrimary : Services.Theme.textSecondary
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: tab1.barSubTab = 0
                                        }
                                    }

                                    Item {
                                        width: barSubTabBar.itemWidth
                                        height: parent.height

                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: 8
                                            Text {
                                                text: Services.Icons.pin || "󰤩"
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 13
                                                color: tab1.barSubTab === 1 ? Services.Theme.accent : Services.Theme.textSecondary
                                            }
                                            Text {
                                                text: "Application Dock"
                                                font.pixelSize: 12
                                                font.weight: tab1.barSubTab === 1 ? Font.DemiBold : Font.Normal
                                                color: tab1.barSubTab === 1 ? Services.Theme.textPrimary : Services.Theme.textSecondary
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: tab1.barSubTab = 1
                                        }
                                    }
                                }
                            }

                            // ── SUBTAB 0: STATUS BAR & DYNAMIC ISLAND ─────────────────
                            ColumnLayout {
                                id: barIslandContent
                                Layout.fillWidth: true
                                spacing: 14
                                visible: tab1.barSubTab === 0

                                SettingsSection {
                                    title: "Bar Architecture & Position"
                                    icon: Services.Icons.controlcenter

                                SettingsRow {
                                    title: "Bar Architecture Preset"
                                    subtitle: "Overall layout and visual style"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.barStyle : "islands"
                                        model: [
                                            { id: "islands",  label: "Islands" },
                                            { id: "floating", label: "Floating Bar" },
                                            { id: "unified",  label: "Unified Full" },
                                            { id: "minimal",  label: "Minimal" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setBarStyle(val) }
                                    }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Screen Placement"
                                    subtitle: "Dock to top or bottom edge"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.barPosition : "top"
                                        model: [
                                            { id: "top",    label: "Top Status Bar" },
                                            { id: "bottom", label: "Bottom Dock Bar" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setBarPosition(val) }
                                    }
                                }
                            }

                            SettingsSection {
                                title: "Display & Monitor Assignment"
                                icon: Services.Icons.display

                                SettingsRow {
                                    title: "Target Monitors"
                                    subtitle: "Choose which connected display(s) render the QuickShell bar"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.barMonitorMode : "all"
                                        model: [
                                            { id: "all",     label: "All Connected Displays" },
                                            { id: "primary", label: "Primary / Focused Display Only" },
                                            { id: "custom",  label: "Custom Display Selection" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setBarMonitorMode(val) }
                                    }
                                }

                                SettingsDivider {
                                    visible: (Services.Config ? Services.Config.barMonitorMode : "all") === "custom"
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    visible: (Services.Config ? Services.Config.barMonitorMode : "all") === "custom"

                                    Repeater {
                                        model: (Services.Compositor && Services.Compositor.monitorsList) ? Services.Compositor.monitorsList : []
                                        delegate: SettingsSwitch {
                                            required property var modelData
                                            title: (modelData.name || "Display") + (modelData.focused ? " (Primary)" : "")
                                            subtitle: (modelData.width + "×" + modelData.height + " @ " + modelData.refreshRate + "Hz · " + (modelData.description || modelData.model || "Display Output"))
                                            checked: Services.Config ? Services.Config.isBarMonitorEnabled(modelData.name) : true
                                            onToggled: (st) => {
                                                if (Services.Config) Services.Config.setBarMonitor(modelData.name, st)
                                            }
                                        }
                                    }
                                }
                            }

                            SettingsSection {
                                title: "Dynamic Island HUD"
                                icon: Services.Icons.bell

                                SettingsRow {
                                    title: "Notch Display Mode"
                                    subtitle: "Interactive media & status pill in bar center"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.islandStyle : "expanded"
                                        model: [
                                            { id: "expanded", label: "Full Dynamic Island" },
                                            { id: "compact",  label: "Compact HUD Notch" },
                                            { id: "hidden",   label: "Hidden / Off" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setIslandStyle(val) }
                                    }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Live CAVA Wave Visualizer"
                                    subtitle: "Visualize audio frequencies in real time using CAVA when media is playing"
                                    checked: Services.Config ? Services.Config.islandCavaWave : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setIslandCavaWave(st) }
                                }
                            }

                            SettingsSection {
                                title: "Workspaces Pager"
                                icon: Services.Icons.grid

                                SettingsRow {
                                    title: "Pager Style"
                                    subtitle: "Visual representation of workspaces"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.workspaceStyle : "pills"
                                        model: [
                                            { id: "pills",   label: "Dynamic Pills" },
                                            { id: "numbers", label: "Numbered (1, 2, 3...)" },
                                            { id: "dots",    label: "Minimal Dots" },
                                            { id: "icons",   label: "Context Icons" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setWorkspaceStyle(val) }
                                    }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Always Show Primary Workspaces (1–5)"
                                    subtitle: "Keep primary workspaces visible even when inactive"
                                    checked: Services.Config ? Services.Config.workspaceShowAll : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setWorkspaceShowAll(st) }
                                }
                            }

                            SettingsSection {
                                title: "Clock & Date Typography"
                                icon: Services.Icons.clock

                                SettingsRow {
                                    title: "Date Format"
                                    subtitle: "Display format for calendar date"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.clockDateFormat : "short"
                                        model: [
                                            { id: "short", label: "Short (Thu, 20 Aug)" },
                                            { id: "full",  label: "Full (Thursday, 20 August)" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setClockDateFormat(val) }
                                    }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "24-Hour Time Format"
                                    subtitle: "Use 24h clock instead of 12h AM/PM"
                                    checked: Services.Config ? Services.Config.clock24h : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setClock24h(st) }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Display Live Seconds"
                                    subtitle: "Render real-time ticking seconds"
                                    checked: Services.Config ? Services.Config.clockShowSeconds : false
                                    onToggled: (st) => { if (Services.Config) Services.Config.setClockShowSeconds(st) }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Display Date Text"
                                    subtitle: "Show current day and date prefix in the bar"
                                    checked: Services.Config ? Services.Config.clockShowDate : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setClockShowDate(st) }
                                }
                            }

                            SettingsSection {
                                title: "Bar Modules Visibility"
                                icon: Services.Icons.eyeOpen || Services.Icons.eye

                                SettingsSwitch {
                                    title: "Workspaces Pager"
                                    checked: Services.Config ? Services.Config.showWorkspaces : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setShowWorkspaces(st) }
                                }
                                SettingsDivider {}
                                SettingsSwitch {
                                    title: "System Tray (SNI)"
                                    checked: Services.Config ? Services.Config.showSysTray : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setShowSysTray(st) }
                                }
                                SettingsDivider {}
                                SettingsSwitch {
                                    title: "System Resource Monitor"
                                    checked: Services.Config ? Services.Config.showSysmonTray : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setShowSysmonTray(st) }
                                }
                                SettingsDivider {}
                                SettingsSwitch {
                                    title: "Volume & Audio Pill"
                                    checked: Services.Config ? Services.Config.showVolumeTray : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setShowVolumeTray(st) }
                                }
                                SettingsDivider {}
                                SettingsSwitch {
                                    title: "Battery & Power Indicator"
                                    checked: Services.Config ? Services.Config.showBatteryTray : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setShowBatteryTray(st) }
                                }
                                SettingsDivider {}
                                SettingsSwitch {
                                    title: "Control Center Trigger Pill"
                                    checked: Services.Config ? Services.Config.showControlCenterTray : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setShowControlCenterTray(st) }
                                }
                                SettingsDivider {}
                                SettingsSwitch {
                                    title: "Clock & Calendar Pill"
                                    checked: Services.Config ? Services.Config.showClockTray : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setShowClockTray(st) }
                                }
                            }

                            SettingsSection {
                                title: "Dashboard & Weather Widgets"
                                icon: Services.Icons.dashboard || Services.Icons.cloud

                                SettingsRow {
                                    title: "Dashboard Main Widget"
                                    subtitle: "Primary module displayed in the dashboard panel"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.dashboardWidget : "weather"
                                        model: [
                                            { id: "weather",   label: "Live Weather Card" },
                                            { id: "wallpaper", label: "Wallpaper Strip" },
                                            { id: "both",      label: "Both (Tabbed Switcher)" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setDashboardWidget(val) }
                                    }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Weather Location Mode"
                                    subtitle: "Auto-detect location or enter custom city / coordinates"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.weatherLocationMode : "auto"
                                        model: [
                                            { id: "auto",   label: "Auto (IP Geolocation)" },
                                            { id: "custom", label: "Custom City / Coordinates" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setWeatherLocationMode(val) }
                                    }
                                }

                                SettingsDivider {
                                    visible: Services.Config && Services.Config.weatherLocationMode === "custom"
                                }

                                SettingsRow {
                                    visible: Services.Config && Services.Config.weatherLocationMode === "custom"
                                    title: "Custom City or Coordinates"
                                    subtitle: "City name (e.g. Jakarta) or GPS coordinates (e.g. -7.55, 110.82)"

                                    RowLayout {
                                        spacing: 6

                                        Rectangle {
                                            width: 195
                                            height: 30
                                            radius: 6
                                            color: Services.Theme.isDark ? "#121216" : "#f1f5f9"
                                            border.color: cityInput.activeFocus ? Services.Theme.accent : (Services.Theme.isDark ? "#2a2a34" : "#cbd5e1")
                                            border.width: 1

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.margins: 6
                                                spacing: 4

                                                TextInput {
                                                    id: cityInput
                                                    Layout.fillWidth: true
                                                    text: Services.Config ? Services.Config.weatherCustomCity : ""
                                                    font.pixelSize: 11
                                                    color: Services.Theme.textPrimary
                                                    selectByMouse: true
                                                    clip: true
                                                    onAccepted: {
                                                        if (Services.Config) Services.Config.setWeatherCustomCity(cityInput.text)
                                                    }

                                                    Text {
                                                        visible: cityInput.text.length === 0
                                                        text: "City or lat, lon..."
                                                        font.pixelSize: 11
                                                        color: Services.Theme.textDisabled
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                }
                                            }
                                        }

                                        Rectangle {
                                            width: 52
                                            height: 30
                                            radius: 6
                                            color: applyCityMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.surfaceVariant
                                            border.color: Services.Theme.border
                                            border.width: 1

                                            Text {
                                                anchors.centerIn: parent
                                                text: "Apply"
                                                font.pixelSize: 10
                                                font.weight: Font.Medium
                                                color: Services.Theme.accent
                                            }

                                            MouseArea {
                                                id: applyCityMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (Services.Config) Services.Config.setWeatherCustomCity(cityInput.text)
                                                }
                                            }
                                        }
                                    }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Temperature Unit"
                                    subtitle: "Unit scale for weather readings"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.weatherUnit : "celsius"
                                        model: [
                                            { id: "celsius",    label: "Celsius (°C)" },
                                            { id: "fahrenheit", label: "Fahrenheit (°F)" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setWeatherUnit(val) }
                                    }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Hardware Resource Monitors"
                                    subtitle: "Show CPU, RAM, Disk & Temperature meters in Dashboard"
                                    checked: Services.Config ? Services.Config.dashboardShowMetrics : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setDashboardShowMetrics(st) }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "System Specifications Bar"
                                    subtitle: "Show Uptime, Kernel, Shell & Battery capsule bar"
                                    checked: Services.Config ? Services.Config.dashboardShowSpecs : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setDashboardShowSpecs(st) }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Quick Session Actions"
                                    subtitle: "Show Lock, Reload, and Power buttons in Dashboard"
                                    checked: Services.Config ? Services.Config.dashboardShowActions : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setDashboardShowActions(st) }
                                }
                            }
                        }

                        // ── SUBTAB 1: APPLICATION DOCK ────────────────────────────
                        ColumnLayout {
                            id: dockContent
                            Layout.fillWidth: true
                            spacing: 14
                            visible: tab1.barSubTab === 1

                            // 1. General & Behavior Section
                            SettingsSection {
                                title: "Dock General & Behavior"
                                icon: Services.Icons.controlcenter

                                SettingsSwitch {
                                    title: "Enable Application Dock"
                                    subtitle: "Display floating application dock"
                                    checked: Services.Config ? Services.Config.dockEnabled : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setDockEnabled(st) }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Screen Placement"
                                    subtitle: "Position dock along the screen edge"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.dockPosition : "bottom"
                                        model: [
                                            { id: "bottom", label: "Bottom Edge (Default)" },
                                            { id: "left",   label: "Left Edge" },
                                            { id: "right",  label: "Right Edge" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setDockPosition(val) }
                                    }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Auto-Hide Dock"
                                    subtitle: "Slide dock away when cursor leaves the edge"
                                    checked: Services.Config ? Services.Config.dockAutoHide : false
                                    onToggled: (st) => { if (Services.Config) Services.Config.setDockAutoHide(st) }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Display Assignment"
                                    subtitle: "Choose which connected monitor(s) render the dock"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.dockMonitorMode : "all"
                                        model: [
                                            { id: "all",     label: "All Connected Displays" },
                                            { id: "primary", label: "Primary / Focused Display Only" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setDockMonitorMode(val) }
                                    }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Screen Edge Distance"
                                    subtitle: "Margin offset between dock and screen edge"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.dockFloatingDistance : 6
                                        model: [
                                            { id: 0,  label: "0px (Attached / Flush)" },
                                            { id: 6,  label: "6px (Standard Floating)" },
                                            { id: 12, label: "12px (Spacious Floating)" },
                                            { id: 18, label: "18px (High Floating)" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setDockFloatingDistance(Number(val)) }
                                    }
                                }
                            }

                            // 2. Appearance & Magnification Section
                            SettingsSection {
                                title: "Appearance & Magnification"
                                icon: Services.Icons.palette

                                SettingsRow {
                                    title: "Icon Size"
                                    subtitle: "Base dimension of application icons in pixels"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.dockIconSize : 48
                                        model: [
                                            { id: 36, label: "36px (Compact)" },
                                            { id: 44, label: "44px (Medium)" },
                                            { id: 48, label: "48px (Standard)" },
                                            { id: 56, label: "56px (Large)" },
                                            { id: 64, label: "64px (Extra Large)" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setDockIconSize(Number(val)) }
                                    }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Hover Magnification"
                                    subtitle: "Smoothly zoom icons as mouse cursor approaches"
                                    checked: Services.Config ? Services.Config.dockMagnification : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setDockMagnification(st) }
                                }

                                SettingsDivider {
                                    visible: Services.Config ? Services.Config.dockMagnification : true
                                }

                                SettingsRow {
                                    visible: Services.Config ? Services.Config.dockMagnification : true
                                    title: "Magnification Scale"
                                    subtitle: "Peak zoom factor on hover"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.dockMagnificationScale : 1.35
                                        model: [
                                            { id: 1.20, label: "1.20x (Subtle)" },
                                            { id: 1.35, label: "1.35x (Balanced)" },
                                            { id: 1.50, label: "1.50x (Prominent)" },
                                            { id: 1.75, label: "1.75x (Dramatic)" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setDockMagnificationScale(Number(val)) }
                                    }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Running App Indicators"
                                    subtitle: "Display status marker beneath active applications"
                                    checked: Services.Config ? Services.Config.dockShowIndicators : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setDockShowIndicators(st) }
                                }

                                SettingsDivider {
                                    visible: Services.Config ? Services.Config.dockShowIndicators : true
                                }

                                SettingsRow {
                                    visible: Services.Config ? Services.Config.dockShowIndicators : true
                                    title: "Indicator Style"
                                    subtitle: "Visual style of the active application marker"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.dockIndicatorStyle : "dot"
                                        model: [
                                            { id: "dot",  label: "Dot (Classic Circle)" },
                                            { id: "line", label: "Line (Horizontal Bar)" },
                                            { id: "pill", label: "Pill (Rounded Dash)" },
                                            { id: "glow", label: "Glow (Underglow Bar)" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setDockIndicatorStyle(val) }
                                    }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Application Name Tooltips"
                                    subtitle: "Display floating title pill when hovering over an application"
                                    checked: Services.Config ? Services.Config.dockShowTooltips : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setDockShowTooltips(st) }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Window Count Badges"
                                    subtitle: "Show badge indicator when an app has multiple open windows"
                                    checked: Services.Config ? Services.Config.dockShowWindowCount : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setDockShowWindowCount(st) }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Launch Bounce Animation"
                                    subtitle: "Tactile spring bounce effect when launching or switching to an app"
                                    checked: Services.Config ? Services.Config.dockBounceOnClick : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setDockBounceOnClick(st) }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Pinned Apps Separator"
                                    subtitle: "Display hairline divider separating pinned favorites from running apps"
                                    checked: Services.Config ? Services.Config.dockShowSeparator : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setDockShowSeparator(st) }
                                }
                            }

                            // 3. Pinned Applications Management Section
                            SettingsSection {
                                title: "Pinned Applications (" + ((Services.Config && Services.Config.dockPinnedApps) ? Services.Config.dockPinnedApps.length : 0) + ")"
                                icon: Services.Icons.pin || "󰤩"

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.margins: 12
                                    spacing: 8

                                    // Top Action Header
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Text {
                                            text: "Manage pinned favorites on your Dock"
                                            font.pixelSize: Services.Theme.fontSizeSm
                                            color: Services.Theme.textSecondary
                                            Layout.fillWidth: true
                                        }

                                        Rectangle {
                                            implicitWidth: resetPinnedBtnText.implicitWidth + 20
                                            height: 28
                                            radius: 6
                                            color: resetPinnedMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.surfaceVariant
                                            border.color: Services.Theme.border
                                            border.width: 1

                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: 4
                                                Text {
                                                    text: "↺"
                                                    font.pixelSize: 11
                                                    color: Services.Theme.textSecondary
                                                }
                                                Text {
                                                    id: resetPinnedBtnText
                                                    text: "Reset Defaults"
                                                    font.pixelSize: 11
                                                    color: Services.Theme.textSecondary
                                                }
                                            }

                                            MouseArea {
                                                id: resetPinnedMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (Services.DockService) Services.DockService.resetToDefaultPinned()
                                                }
                                            }
                                        }

                                        Rectangle {
                                            implicitWidth: addAppBtnText.implicitWidth + 24
                                            height: 28
                                            radius: 6
                                            color: tab1.isAddingApp ? Services.Theme.surfaceVariant : Services.Theme.accent
                                            border.color: Services.Theme.accent
                                            border.width: 1

                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: 6
                                                Text {
                                                    text: tab1.isAddingApp ? "✕" : "+"
                                                    font.pixelSize: 12
                                                    font.bold: true
                                                    color: tab1.isAddingApp ? Services.Theme.textPrimary : Services.Theme.bgOnAccent
                                                }
                                                Text {
                                                    id: addAppBtnText
                                                    text: tab1.isAddingApp ? "Close Picker" : "Add Application"
                                                    font.pixelSize: 11
                                                    font.weight: Font.DemiBold
                                                    color: tab1.isAddingApp ? Services.Theme.textPrimary : Services.Theme.bgOnAccent
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    tab1.isAddingApp = !tab1.isAddingApp
                                                    tab1.appSearchText = ""
                                                }
                                            }
                                        }
                                    }

                                    // Quick App Picker Search Box
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: addAppCol.implicitHeight + 16
                                        visible: tab1.isAddingApp
                                        radius: 10
                                        color: Services.Theme.bgElevated
                                        border.color: Services.Theme.borderHighlight
                                        border.width: 1

                                        ColumnLayout {
                                            id: addAppCol
                                            anchors.fill: parent
                                            anchors.margins: 10
                                            spacing: 8

                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: 32
                                                radius: 6
                                                color: Services.Theme.surface
                                                border.color: appSearchInput.activeFocus ? Services.Theme.accent : Services.Theme.border
                                                border.width: 1

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8; anchors.rightMargin: 8
                                                    spacing: 6

                                                    Text {
                                                        text: Services.Icons.search || "🔍"
                                                        font.family: Services.Theme.fontSymbols
                                                        font.pixelSize: 11
                                                        color: Services.Theme.textSecondary
                                                    }

                                                    TextInput {
                                                        id: appSearchInput
                                                        Layout.fillWidth: true
                                                        text: tab1.appSearchText
                                                        font.pixelSize: 12
                                                        color: Services.Theme.textPrimary
                                                        selectByMouse: true
                                                        onTextChanged: tab1.appSearchText = text
                                                    }

                                                    Text {
                                                        visible: tab1.appSearchText.length > 0
                                                        text: "✕"
                                                        font.pixelSize: 10
                                                        color: Services.Theme.textSecondary
                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: { tab1.appSearchText = ""; appSearchInput.text = "" }
                                                        }
                                                    }
                                                }
                                            }

                                            Flow {
                                                Layout.fillWidth: true
                                                spacing: 6

                                                readonly property var candidates: {
                                                    const raw = (DesktopEntries.applications && DesktopEntries.applications.values) ? DesktopEntries.applications.values : []
                                                    const q = tab1.appSearchText.toLowerCase().trim()
                                                    const res = []
                                                    for (let i = 0; i < raw.length && res.length < 24; i++) {
                                                        const a = raw[i]
                                                        if (!a || !a.id) continue
                                                        if (Services.DockService && Services.DockService.isPinned(a.id)) continue
                                                        if (q.length === 0 || (a.name && a.name.toLowerCase().includes(q)) || (a.id && a.id.toLowerCase().includes(q))) {
                                                            res.push(a)
                                                        }
                                                    }
                                                    return res
                                                }

                                                Repeater {
                                                    model: parent.candidates
                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        implicitWidth: addAppRow.implicitWidth + 16
                                                        height: 32
                                                        radius: 6
                                                        color: candMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.surface
                                                        border.color: candMouse.containsMouse ? Services.Theme.accent : Services.Theme.border
                                                        border.width: 1

                                                        RowLayout {
                                                            id: addAppRow
                                                            anchors.centerIn: parent
                                                            spacing: 6

                                                            Text {
                                                                text: modelData.name || modelData.id
                                                                font.pixelSize: 11
                                                                color: Services.Theme.textPrimary
                                                            }

                                                            Text {
                                                                text: "+"
                                                                font.pixelSize: 12
                                                                font.bold: true
                                                                color: Services.Theme.accent
                                                            }
                                                        }

                                                        MouseArea {
                                                            id: candMouse
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (Services.DockService && modelData.id) {
                                                                    Services.DockService.pinApp(modelData.id)
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Visual List of Currently Pinned Apps
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 4

                                        Repeater {
                                            model: (Services.Config && Services.Config.dockPinnedApps) ? Services.Config.dockPinnedApps : []

                                            delegate: Rectangle {
                                                id: pinnedCard
                                                required property var modelData
                                                required property int index
                                                Layout.fillWidth: true
                                                height: 44
                                                radius: 8
                                                color: Services.Theme.bgElevated
                                                border.color: Services.Theme.border
                                                border.width: 1

                                                readonly property var appObj: Services.DockService ? Services.DockService.findAppByDesktopId(pinnedCard.modelData) : null
                                                readonly property string appName: appObj ? (appObj.name || pinnedCard.modelData) : pinnedCard.modelData.replace(/\.desktop$/, '')

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 12
                                                    anchors.rightMargin: 12
                                                    spacing: 12

                                                    Image {
                                                        Layout.preferredWidth: 26
                                                        Layout.preferredHeight: 26
                                                        source: {
                                                            const raw = pinnedCard.appObj ? (typeof pinnedCard.appObj.icon === "string" ? pinnedCard.appObj.icon : pinnedCard.appObj.icon?.name) : ""
                                                            if (!raw) return ""
                                                            if (Services.SystemTheme) {
                                                                const res = Services.SystemTheme.getIcon(raw)
                                                                if (res && res.length > 0) return res
                                                            }
                                                            const qp = Quickshell.iconPath(raw, true)
                                                            return (qp && qp.startsWith("/")) ? ("file://" + qp) : (qp || "")
                                                        }
                                                        fillMode: Image.PreserveAspectFit
                                                        asynchronous: true
                                                        smooth: true
                                                    }

                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 1

                                                        Text {
                                                            text: pinnedCard.appName
                                                            font.pixelSize: 12
                                                            font.weight: Font.Medium
                                                            color: Services.Theme.textPrimary
                                                            elide: Text.ElideRight
                                                            Layout.fillWidth: true
                                                        }

                                                        Text {
                                                            text: pinnedCard.modelData
                                                            font.family: Services.Theme.fontMono
                                                            font.pixelSize: 10
                                                            color: Services.Theme.textDisabled
                                                            elide: Text.ElideRight
                                                            Layout.fillWidth: true
                                                        }
                                                    }

                                                    // Remove / Unpin Button
                                                    Rectangle {
                                                        width: 24; height: 24; radius: 5
                                                        color: unpinMouse.containsMouse ? Qt.rgba(0.9, 0.2, 0.2, 0.15) : "transparent"
                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: "✕"
                                                            font.pixelSize: 11
                                                            color: unpinMouse.containsMouse ? Services.Theme.danger : Services.Theme.textSecondary
                                                        }
                                                        MouseArea {
                                                            id: unpinMouse
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (Services.DockService) {
                                                                    Services.DockService.unpinApp(pinnedCard.modelData)
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                        // ═════════════════════════════════════════════
                        // TAB 2: NOTIFICATIONS
                        // ═════════════════════════════════════════════
                        ColumnLayout {
                            id: tab2
                            Layout.fillWidth: true
                            spacing: 14

                            SettingsSection {
                                title: "Notification Alerts"
                                icon: Services.Icons.bell

                                SettingsSwitch {
                                    title: "Do Not Disturb"
                                    subtitle: "Mute all popups and banner alerts"
                                    checked: Services.Notifications.doNotDisturb
                                    onToggled: (st) => { Services.Notifications.doNotDisturb = st }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Popup Placement"
                                    subtitle: "Screen corner for notification toasts"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.notificationPosition : "top_right"
                                        model: [
                                            { id: "top_right",    label: "Top Right Corner" },
                                            { id: "top_center",   label: "Top Center (Notch)" },
                                            { id: "top_left",     label: "Top Left Corner" },
                                            { id: "bottom_right", label: "Bottom Right Corner" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setNotificationPosition(val) }
                                    }
                                }

                                SettingsDivider {}

                                SettingsSlider {
                                    title: "Popup Duration"
                                    subtitle: "How long bubble popups remain on screen"
                                    from: 2; to: 15; stepSize: 1; valueSuffix: "s"
                                    value: Services.Config ? Services.Config.notificationTimeout : 5
                                    onMoved: (v) => { if (Services.Config) Services.Config.setNotificationTimeout(Math.round(v)) }
                                }

                                SettingsDivider {}

                                SettingsSlider {
                                    title: "History Retention"
                                    subtitle: "Days before history entries expire"
                                    from: 1; to: 7; stepSize: 1; valueSuffix: " days"
                                    value: Services.Config ? Services.Config.notificationRetentionDays : 7
                                    onMoved: (v) => { if (Services.Config) Services.Config.setNotificationRetentionDays(Math.round(v)) }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Show in Fullscreen"
                                    subtitle: "Display notification popups over fullscreen apps (battery alerts always appear)"
                                    checked: Services.Config ? Services.Config.notificationShowInFullscreen : false
                                    onToggled: (st) => { if (Services.Config) Services.Config.setNotificationShowInFullscreen(st) }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Test & Actions"

                                    RowLayout {
                                        spacing: 8

                                        Rectangle {
                                            height: 28
                                            implicitWidth: testNotifTxt.implicitWidth + 16
                                            radius: 5
                                            color: tNotifMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Services.Theme.bgElevated
                                            border.color: Services.Theme.border
                                            border.width: 1
                                            Text { id: testNotifTxt; anchors.centerIn: parent; text: "Send Test"; font.pixelSize: 11; font.weight: Font.Medium; color: Services.Theme.textPrimary }
                                            MouseArea {
                                                id: tNotifMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: testNotifProc.running = true
                                            }
                                        }

                                        Rectangle {
                                            height: 28
                                            implicitWidth: clrNotifTxt.implicitWidth + 16
                                            radius: 5
                                            color: clrNotifMouse.containsMouse ? Qt.rgba(0.9, 0.2, 0.2, 0.15) : Services.Theme.bgElevated
                                            border.color: Services.Theme.border
                                            border.width: 1
                                            Text { id: clrNotifTxt; anchors.centerIn: parent; text: "Clear History"; font.pixelSize: 11; font.weight: Font.Medium; color: Services.Theme.danger }
                                            MouseArea {
                                                id: clrNotifMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: { if (Services.Notifications) Services.Notifications.clearHistory() }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ═════════════════════════════════════════════
                        // TAB 3: SOUND & AUDIO
                        // ═════════════════════════════════════════════
                        ColumnLayout {
                            id: tab3
                            Layout.fillWidth: true
                            spacing: 14

                            SettingsSection {
                                title: "Audio Feedback"
                                icon: Services.Icons.speaker

                                SettingsSwitch {
                                    title: "UI Sound Effects"
                                    subtitle: "Audible feedback for volume adjustments and alerts"
                                    checked: Services.Config ? Services.Config.soundFeedback : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setSoundFeedback(st) }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Volume Adjustment Feedback"
                                    subtitle: "Tick chime on volume step change"
                                    checked: Services.Config ? Services.Config.soundVolumeFeedback : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setSoundVolumeFeedback(st) }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Notification Chime Sound"
                                    subtitle: "Audible alert on incoming notification"
                                    checked: Services.Config ? Services.Config.soundNotifFeedback : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setSoundNotifFeedback(st) }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Audition Sounds"

                                    RowLayout {
                                        spacing: 6

                                        Rectangle {
                                            height: 26
                                            implicitWidth: s1Txt.implicitWidth + 12
                                            radius: 4
                                            color: s1Mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Services.Theme.bgElevated
                                            border.color: Services.Theme.border; border.width: 1
                                            Text { id: s1Txt; anchors.centerIn: parent; text: "Notification"; font.pixelSize: 10; color: Services.Theme.textPrimary }
                                            MouseArea {
                                                id: s1Mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: { if (Services.SoundFeedback && typeof Services.SoundFeedback.playNotification === "function") Services.SoundFeedback.playNotification() }
                                            }
                                        }

                                        Rectangle {
                                            height: 26
                                            implicitWidth: s2Txt.implicitWidth + 12
                                            radius: 4
                                            color: s2Mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Services.Theme.bgElevated
                                            border.color: Services.Theme.border; border.width: 1
                                            Text { id: s2Txt; anchors.centerIn: parent; text: "Volume Step"; font.pixelSize: 10; color: Services.Theme.textPrimary }
                                            MouseArea {
                                                id: s2Mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: { if (Services.SoundFeedback && typeof Services.SoundFeedback.playVolumeChange === "function") Services.SoundFeedback.playVolumeChange() }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ═════════════════════════════════════════════
                        // TAB 4: LOCKSCREEN & POWER
                        // ═════════════════════════════════════════════
                        ColumnLayout {
                            id: tab4
                            Layout.fillWidth: true
                            spacing: 14

                            // User Profile & Avatar Styling Section (Top Priority)
                            SettingsSection {
                                title: "User Profile & Avatar"
                                icon: Services.Icons.user

                                // Interactive Profile Picture Card (Minimal Clean Profile)
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.margins: 10
                                    height: 84
                                    radius: 8
                                    color: Services.Theme.bgElevated
                                    border.color: Services.Theme.border
                                    border.width: 1

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 12
                                        spacing: 14

                                        // Live Avatar Frame with Shape & Camera Hover
                                        Item {
                                            id: profilePreviewFrame
                                            Layout.preferredWidth: 60
                                            Layout.preferredHeight: 60
                                            Layout.alignment: Qt.AlignVCenter

                                            Services.AvatarFrame {
                                                anchors.fill: parent
                                                source: Services.OsInfo.avatarPath
                                                shapeRadius: 16
                                                backgroundColor: Services.Theme.surfaceVariant
                                                borderColor: Services.Theme.border
                                                borderWidth: 1
                                                fallbackText: {
                                                    const u = (Services.OsInfo.username || Quickshell.env("USER") || "user").toUpperCase()
                                                    return u.length > 0 ? u.charAt(0) : "󰌽"
                                                }
                                                fallbackFontFamily: Services.Theme.fontSymbols
                                                fallbackFontSize: 24
                                                fallbackColor: Services.Theme.accent
                                            }

                                            // Camera badge overlay on hover
                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 16
                                                color: Qt.rgba(0, 0, 0, 0.45)
                                                visible: previewCardMouse.containsMouse
                                                antialiasing: true

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "󰄀"
                                                    font.family: Services.Theme.fontSymbols
                                                    font.pixelSize: 18
                                                    color: "white"
                                                }
                                            }

                                            // Reset custom photo icon on corner
                                            Rectangle {
                                                visible: Services.OsInfo.isCustomAvatar && previewCardMouse.containsMouse
                                                anchors.top: parent.top
                                                anchors.right: parent.right
                                                anchors.topMargin: -3
                                                anchors.rightMargin: -3
                                                width: 18; height: 18
                                                radius: 9
                                                color: Services.Theme.danger || "#ef4444"
                                                z: 10

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "✕"
                                                    font.pixelSize: 9
                                                    font.weight: Font.Bold
                                                    color: "#ffffff"
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: Services.OsInfo.clearCustomAvatar()
                                                }
                                            }

                                            MouseArea {
                                                id: previewCardMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Services.OsInfo.pickCustomAvatar()
                                            }
                                        }

                                        // User Info & Status (hugging avatar)
                                        ColumnLayout {
                                            spacing: 2
                                            Layout.alignment: Qt.AlignVCenter

                                            Text {
                                                text: Services.OsInfo.username || Quickshell.env("USER") || "User"
                                                font.pixelSize: 15
                                                font.weight: Font.DemiBold
                                                color: Services.Theme.textPrimary
                                            }

                                            Text {
                                                text: (Services.OsInfo.username || "user") + "@" + (Services.OsInfo.hostname || "local") + "  ·  " + (Services.OsInfo.shellName || "sh")
                                                font.pixelSize: 11
                                                font.weight: Font.Medium
                                                color: Services.Theme.textSecondary
                                            }

                                            Text {
                                                text: (Services.OsInfo.distroName || "Linux") + "  ·  Kernel " + (Services.OsInfo.kernel || "")
                                                font.family: Services.Theme.fontMono
                                                font.pixelSize: 9
                                                color: Services.Theme.textDisabled
                                            }
                                        }

                                        // Spacer pushing content to the left
                                        Item { Layout.fillWidth: true }
                                    }
                                }
                            }

                            // Face ID & Biometrics Section
                            SettingsSection {
                                title: "Face ID & Biometrics"
                                icon: "󰄀"

                                SettingsSwitch {
                                    title: "Face ID Unlock"
                                    subtitle: "Unlock your desktop using webcam facial recognition"
                                    checked: Services.Config ? Services.Config.faceIdEnabled : true
                                    onToggled: (newState) => {
                                        if (Services.Config) Services.Config.setFaceIdEnabled(newState)
                                    }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Instant Auto-Unlock"
                                    subtitle: "Automatically dismiss lockscreen when face is recognized"
                                    checked: Services.Config ? Services.Config.faceIdAutoUnlock : true
                                    onToggled: (newState) => {
                                        if (Services.Config) Services.Config.setFaceIdAutoUnlock(newState)
                                    }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Biometric Data"
                                    subtitle: (Services.FaceId && Services.FaceId.isEnrolling)
                                        ? (Services.FaceId.statusMessage || "Enrolling face...")
                                        : ((Services.FaceId && Services.FaceId.isEnrolled)
                                            ? "Face registered for " + (Services.OsInfo.username || Quickshell.env("USER") || "user")
                                            : "No face registered yet")

                                    RowLayout {
                                        spacing: 8
                                        Layout.alignment: Qt.AlignVCenter

                                        // Status Pill Badge
                                        Rectangle {
                                            height: 24
                                            implicitWidth: statusPillTxt.implicitWidth + 14
                                            radius: 12
                                            color: (Services.FaceId && Services.FaceId.isEnrolled)
                                                ? Qt.rgba(48/255, 209/255, 88/255, 0.15)
                                                : Qt.rgba(1, 1, 1, 0.06)
                                            border.color: (Services.FaceId && Services.FaceId.isEnrolled)
                                                ? Qt.rgba(48/255, 209/255, 88/255, 0.4)
                                                : Services.Theme.border
                                            border.width: 1

                                            Text {
                                                id: statusPillTxt
                                                anchors.centerIn: parent
                                                text: (Services.FaceId && Services.FaceId.isEnrolling)
                                                    ? ((Services.FaceId.enrollStepName && Services.FaceId.enrollStepName.length > 0)
                                                        ? (Services.FaceId.enrollStepName === "Confirmation"
                                                            ? "Reviewing..."
                                                            : ("Step " + Services.FaceId.enrollStepNumber + "/3: " + Services.FaceId.enrollStepName))
                                                        : ("Enrolling " + Math.round((Services.FaceId ? Services.FaceId.enrollProgress : 0) * 100) + "%"))
                                                    : ((Services.FaceId && Services.FaceId.isEnrolled) ? "Enrolled" : "Not Set Up")
                                                font.pixelSize: 11
                                                font.weight: Font.Medium
                                                color: (Services.FaceId && Services.FaceId.isEnrolling)
                                                    ? Services.Theme.accent
                                                    : ((Services.FaceId && Services.FaceId.isEnrolled) ? "#30d158" : Services.Theme.textSecondary)
                                            }
                                        }

                                        // Enroll / Re-enroll Button
                                        Rectangle {
                                            visible: !Services.FaceId || !Services.FaceId.isEnrolling
                                            height: 28
                                            implicitWidth: enrollBtnTxt.implicitWidth + 20
                                            radius: 6
                                            color: enrollMouse.containsMouse
                                                ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.25)
                                                : Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.14)
                                            border.color: Services.Theme.accent
                                            border.width: 1

                                            Text {
                                                id: enrollBtnTxt
                                                anchors.centerIn: parent
                                                text: (Services.FaceId && Services.FaceId.isEnrolled) ? "Re-enroll" : "Set Up..."
                                                font.pixelSize: 11
                                                font.weight: Font.DemiBold
                                                color: Services.Theme.accent
                                            }

                                            MouseArea {
                                                id: enrollMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (Services.FaceId) Services.FaceId.startEnroll()
                                                }
                                            }
                                        }

                                        // Cancel Button
                                        Rectangle {
                                            visible: Services.FaceId && Services.FaceId.isEnrolling
                                            height: 28
                                            implicitWidth: cancelBtnTxt.implicitWidth + 18
                                            radius: 6
                                            color: cancelMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Services.Theme.bgElevated
                                            border.color: Services.Theme.border
                                            border.width: 1

                                            Text {
                                                id: cancelBtnTxt
                                                anchors.centerIn: parent
                                                text: "Cancel"
                                                font.pixelSize: 11
                                                font.weight: Font.Medium
                                                color: Services.Theme.textPrimary
                                            }

                                            MouseArea {
                                                id: cancelMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (Services.FaceId) Services.FaceId.cancelEnroll()
                                                }
                                            }
                                        }

                                        // Remove Button
                                        Rectangle {
                                            visible: Services.FaceId && Services.FaceId.isEnrolled && !Services.FaceId.isEnrolling
                                            height: 28
                                            implicitWidth: clearBtnTxt.implicitWidth + 18
                                            radius: 6
                                            color: clearMouse.containsMouse ? Qt.rgba(0.95, 0.25, 0.25, 0.15) : "transparent"
                                            border.color: clearMouse.containsMouse ? Qt.rgba(0.95, 0.25, 0.25, 0.4) : Services.Theme.border
                                            border.width: 1

                                            Text {
                                                id: clearBtnTxt
                                                anchors.centerIn: parent
                                                text: "Remove"
                                                font.pixelSize: 11
                                                font.weight: Font.Medium
                                                color: Services.Theme.danger || "#ef4444"
                                            }

                                            MouseArea {
                                                id: clearMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (Services.FaceId) Services.FaceId.clearData()
                                                }
                                            }
                                        }
                                    }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Camera Device"
                                    subtitle: "Webcam sensor for facial scanning"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.faceIdCameraDevice : "/dev/video0"
                                        model: {
                                            var devs = (Services.FaceId && Services.FaceId.availableDevices && Services.FaceId.availableDevices.length > 0)
                                                ? Services.FaceId.availableDevices
                                                : ["/dev/video0", "/dev/video1", "/dev/video2"]
                                            var items = []
                                            for (var i = 0; i < devs.length; i++) {
                                                items.push({ id: devs[i], label: devs[i] })
                                            }
                                            return items
                                        }
                                        onSelected: (val) => {
                                            if (Services.Config) Services.Config.setFaceIdCameraDevice(val)
                                        }
                                    }
                                }
                            }

                            SettingsSection {
                                title: "Lockscreen Display"
                                icon: Services.Icons.lock

                                SettingsRow {
                                    title: "Clock Presentation Style"
                                    subtitle: "Visual typography layout of lockscreen clock"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.lockscreenClockStyle : "hero"
                                        model: [
                                            { id: "hero",        label: "Hero Large (96px)" },
                                            { id: "modern",      label: "Modern Stacked (HH / MM)" },
                                            { id: "minimal",     label: "Minimal Thin" },
                                            { id: "compact",     label: "Compact Capsule" },
                                            { id: "vertical",    label: "Vertical Split" },
                                            { id: "typographic", label: "Typographic Words" },
                                            { id: "radial",      label: "Radial Ring Gauge" },
                                            { id: "cyber",       label: "Cyberpunk HUD" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setLockscreenClockStyle(val) }
                                    }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Wallpaper Backdrop Source"
                                    subtitle: "Sync with active desktop or choose custom image"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.lockscreenWallpaperMode : "sync"
                                        model: [
                                            { id: "sync",   label: "Sync Desktop Wallpaper" },
                                            { id: "custom", label: "Custom Dedicated Image" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setLockscreenWallpaperMode(val) }
                                    }
                                }

                                // Dedicated Lockscreen Wallpaper Selector (Visible when Custom is selected)
                                ColumnLayout {
                                    visible: Services.Config && Services.Config.lockscreenWallpaperMode === "custom"
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 10
                                    Layout.rightMargin: 10
                                    Layout.topMargin: 2
                                    Layout.bottomMargin: 6
                                    spacing: 8

                                    // Header with "Choose Image..." button
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Text {
                                            text: "Select Lockscreen Wallpaper"
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            color: Services.Theme.textPrimary
                                        }

                                        Item { Layout.fillWidth: true }

                                        // Choose File Button
                                        Rectangle {
                                            height: 26
                                            implicitWidth: pickLwTxt.implicitWidth + 22
                                            radius: 6
                                            color: pickLwMouse.containsMouse 
                                                ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.28)
                                                : Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15)
                                            border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.45)
                                            border.width: 1

                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: 5
                                                Text {
                                                    text: Services.Icons.image || "󰋩"
                                                    font.family: Services.Theme.fontSymbols
                                                    font.pixelSize: 10
                                                    color: Services.Theme.accent
                                                }
                                                Text {
                                                    id: pickLwTxt
                                                    text: "Browse Image..."
                                                    font.pixelSize: 10
                                                    font.weight: Font.DemiBold
                                                    color: Services.Theme.accent
                                                }
                                            }

                                            MouseArea {
                                                id: pickLwMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (Services.Wallpaper) {
                                                        Services.Wallpaper.pickLockscreenWallpaper()
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Wallpaper thumbnails flickable row
                                    Item {
                                        Layout.fillWidth: true
                                        implicitHeight: (rootWindow.width < 750) ? 72 : 80

                                        Flickable {
                                            anchors.fill: parent
                                            contentWidth: lockWpListRow.implicitWidth
                                            contentHeight: parent.height
                                            clip: true
                                            boundsBehavior: Flickable.StopAtBounds

                                            RowLayout {
                                                id: lockWpListRow
                                                spacing: 8

                                                Repeater {
                                                    model: Services.Wallpaper ? Services.Wallpaper.allWallpapers : []
                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        width: (rootWindow.width < 750) ? 96 : 108
                                                        height: (rootWindow.width < 750) ? 62 : 70
                                                        radius: 7
                                                        clip: true
                                                        readonly property string curCustomWp: Services.Config ? Services.Config.lockscreenCustomWallpaper : ""
                                                        readonly property bool isCur: curCustomWp === modelData.path || (curCustomWp === "" && Services.Wallpaper && Services.Wallpaper.currentWallpaper === modelData.path)
                                                        border.color: isCur ? Services.Theme.accent : (lwCardMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.border)
                                                        border.width: isCur ? 2 : 1
                                                        color: Services.Theme.bgDeep
                                                        scale: isCur ? 1.02 : (lwCardMouse.pressed ? 0.96 : (lwCardMouse.containsMouse ? 1.02 : 1.0))
                                                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }

                                                        Image {
                                                            anchors.fill: parent
                                                            source: modelData.path.startsWith("/") ? ("file://" + modelData.path) : modelData.path
                                                            sourceSize: Qt.size(216, 140)
                                                            fillMode: Image.PreserveAspectCrop
                                                            asynchronous: true
                                                            cache: true
                                                            smooth: true
                                                            opacity: isCur || lwCardMouse.containsMouse ? 1.0 : 0.75
                                                        }

                                                        Rectangle {
                                                            visible: isCur
                                                            anchors.top: parent.top
                                                            anchors.right: parent.right
                                                            anchors.margins: 4
                                                            width: 16; height: 16; radius: 8
                                                            color: Services.Theme.accent
                                                            Text { anchors.centerIn: parent; text: Services.Icons.check || "✓"; font.family: Services.Theme.fontSymbols; font.pixelSize: 8; color: Services.Theme.bgOnAccent }
                                                        }

                                                        MouseArea {
                                                            id: lwCardMouse
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (Services.Config) {
                                                                    Services.Config.setLockscreenCustomWallpaper(modelData.path)
                                                                    Services.Config.setLockscreenWallpaperMode("custom")
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Blur Wallpaper on Lockscreen"
                                    subtitle: "Gaussian blur backdrop on locked screen"
                                    checked: Services.Config ? Services.Config.lockscreenBlur : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setLockscreenBlur(st) }
                                }

                                SettingsDivider {}

                                SettingsSlider {
                                    title: "Dimming Level"
                                    subtitle: "Backdrop darkness percentage"
                                    from: 0.10; to: 0.85; stepSize: 0.05; decimals: 2
                                    value: Services.Config ? Services.Config.lockscreenDim : 0.45
                                    onMoved: (v) => { if (Services.Config) Services.Config.setLockscreenDim(Number(v.toFixed(2))) }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Show Status Pill (Battery, Wi-Fi)"
                                    checked: Services.Config ? Services.Config.lockscreenShowStatusPill : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setLockscreenShowStatusPill(st) }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Show System Uptime Tag"
                                    checked: Services.Config ? Services.Config.lockscreenShowUptime : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setLockscreenShowUptime(st) }
                                }
                            }

                            // Password Input & Authentication Styling Section
                            SettingsSection {
                                title: "Password Authentication & Media"
                                icon: Services.Icons.keyboard

                                SettingsRow {
                                    title: "Input Field Design"
                                    subtitle: "Visual style of password entry field"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.lockscreenInputStyle : "pill"
                                        model: [
                                            { id: "pill",      label: "Capsule Pill" },
                                            { id: "underline", label: "Underline" },
                                            { id: "box",       label: "Inset Box" },
                                            { id: "dots",      label: "Dot Slots" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setLockscreenInputStyle(val) }
                                    }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Show Media Player"
                                    subtitle: "Display corner media playback controls when audio is playing"
                                    checked: Services.Config ? Services.Config.lockscreenShowMedia : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setLockscreenShowMedia(st) }
                                }
                            }

                            SettingsSection {
                                title: "Power Profile & Battery"
                                icon: Services.Icons.power

                                SettingsRow {
                                    title: "CPU Governor Profile"
                                    subtitle: "Performance vs battery consumption strategy"

                                    SettingsDropdown {
                                        currentValue: Services.PowerProfile ? Services.PowerProfile.currentProfile : "balanced"
                                        model: [
                                            { id: "power-saver", label: "Power Saver (Battery)" },
                                            { id: "balanced",    label: "Balanced (Dynamic)" },
                                            { id: "performance", label: "Performance (Max Clocks)" }
                                        ]
                                        onSelected: (val) => { if (Services.PowerProfile) Services.PowerProfile.setProfile(val) }
                                    }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Low Battery Warning Alerts"
                                    subtitle: "Notify when charge level drops critically low"
                                    checked: Services.Config ? Services.Config.batteryShowWarnings : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setBatteryShowWarnings(st) }
                                }

                                SettingsDivider {}

                                SettingsSlider {
                                    title: "Low Battery Alert Threshold"
                                    from: 10; to: 35; stepSize: 5; valueSuffix: "%"
                                    value: Services.Config ? Services.Config.batteryLowThreshold : 20
                                    onMoved: (v) => { if (Services.Config) Services.Config.setBatteryLowThreshold(Math.round(v)) }
                                }
                            }

                            SettingsSection {
                                title: "Quick Power Actions"
                                icon: Services.Icons.refresh || Services.Icons.reboot

                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: 36
                                    Layout.margins: 6

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 6

                                        Rectangle {
                                            Layout.fillWidth: true; Layout.fillHeight: true; radius: 4
                                            color: p1Mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Services.Theme.bgElevated
                                            border.color: Services.Theme.border; border.width: 1
                                            Text { anchors.centerIn: parent; text: "Lock Screen"; font.pixelSize: 11; font.weight: Font.Medium; color: Services.Theme.textPrimary }
                                            MouseArea { id: p1Mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { rootWindow.hide(); lockSessionProc.running = true } }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true; Layout.fillHeight: true; radius: 4
                                            color: p2Mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Services.Theme.bgElevated
                                            border.color: Services.Theme.border; border.width: 1
                                            Text { anchors.centerIn: parent; text: "Suspend"; font.pixelSize: 11; font.weight: Font.Medium; color: Services.Theme.textPrimary }
                                            MouseArea { id: p2Mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: suspendProc.running = true }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true; Layout.fillHeight: true; radius: 4
                                            color: p3Mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Services.Theme.bgElevated
                                            border.color: Services.Theme.border; border.width: 1
                                            Text { anchors.centerIn: parent; text: "Reboot"; font.pixelSize: 11; font.weight: Font.Medium; color: Services.Theme.warning }
                                            MouseArea { id: p3Mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rebootProc.running = true }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true; Layout.fillHeight: true; radius: 4
                                            color: p4Mouse.containsMouse ? Qt.rgba(0.9, 0.2, 0.2, 0.15) : Services.Theme.bgElevated
                                            border.color: Services.Theme.border; border.width: 1
                                            Text { anchors.centerIn: parent; text: "Power Off"; font.pixelSize: 11; font.weight: Font.Medium; color: Services.Theme.danger }
                                            MouseArea { id: p4Mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: poweroffProc.running = true }
                                        }
                                    }
                                }
                            }
                        }

                        // ═════════════════════════════════════════════
                        // TAB 5: COMPOSITOR & DISPLAYS
                        // ═════════════════════════════════════════════
                        ColumnLayout {
                            id: tab5
                            Layout.fillWidth: true
                            spacing: 12

                            // ── Hero / Status Header Card (Luxurious Compositor Glass Hero) ───────────────
                            Rectangle {
                                Layout.fillWidth: true
                                height: 70
                                radius: Services.Theme.radiusLg || 12
                                color: Services.Theme.surfaceVariant
                                border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.35)
                                border.width: 1

                                // Ambient Glass Refractive Glow
                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.14) }
                                        GradientStop { position: 0.45; color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.02) }
                                        GradientStop { position: 1.0; color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.08) }
                                    }
                                }

                                // Top Specular Glass Line
                                Rectangle {
                                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                    anchors.leftMargin: 8; anchors.rightMargin: 8; anchors.topMargin: 1
                                    height: 1; radius: 0.5
                                    color: Qt.rgba(1, 1, 1, 0.30)
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    spacing: 14

                                    // Desktop / Compositor Icon Squircle Badge
                                    Rectangle {
                                        Layout.preferredWidth: 44
                                        Layout.preferredHeight: 44
                                        Layout.alignment: Qt.AlignVCenter
                                        radius: 11
                                        color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.18)
                                        border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.45)
                                        border.width: 1.2

                                        Text {
                                            anchors.centerIn: parent
                                            text: Services.Icons.display
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 20
                                            color: Services.Theme.accent
                                        }

                                        // Pulsing live indicator dot
                                        Rectangle {
                                            anchors.top: parent.top; anchors.right: parent.right
                                            anchors.topMargin: 3; anchors.rightMargin: 3
                                            width: 7; height: 7; radius: 3.5
                                            color: "#10b981"
                                            border.color: Services.Theme.surfaceVariant
                                            border.width: 1
                                            SequentialAnimation on opacity {
                                                running: true; loops: Animation.Infinite
                                                NumberAnimation { to: 0.3; duration: 900; easing.type: Easing.InOutSine }
                                                NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
                                            }
                                        }
                                    }

                                    // Title & Version Column
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        spacing: 2
                                        Layout.alignment: Qt.AlignVCenter

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6
                                            Text {
                                                text: Services.Compositor ? Services.Compositor.activeDisplayName : "Hyprland"
                                                font.pixelSize: 14
                                                font.weight: Font.Bold
                                                color: Services.Theme.textPrimary
                                            }

                                            // Config Type Pill
                                            Rectangle {
                                                height: 18
                                                implicitWidth: cfgTypeBadge.implicitWidth + 12
                                                radius: 4
                                                color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15)
                                                border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.40)
                                                border.width: 1
                                                RowLayout {
                                                    anchors.centerIn: parent; spacing: 4
                                                    Text { text: Services.Icons.code || "󰅍"; font.family: Services.Theme.fontSymbols; font.pixelSize: 8; color: Services.Theme.accent }
                                                    Text { id: cfgTypeBadge; text: (Services.Compositor && Services.Compositor.configType ? Services.Compositor.configType.toUpperCase() : "LUA") + " CONFIG"; font.pixelSize: 8; font.weight: Font.Bold; color: Services.Theme.accent; font.letterSpacing: 0.5 }
                                                }
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: {
                                                const v = Services.Compositor ? Services.Compositor.activeVersion : ""
                                                const cleanV = v.split(" built")[0].replace(/^hyprland\s*/i, "").trim()
                                                return (cleanV ? ("v" + cleanV + " · ") : "") + "Wayland Session"
                                            }
                                            font.pixelSize: 10
                                            color: Services.Theme.textSecondary
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    // Badges & Actions Group (Balanced Heights & Spacing)
                                    RowLayout {
                                        spacing: 6
                                        Layout.alignment: Qt.AlignVCenter

                                        // Display count badge
                                        Rectangle {
                                            height: 28
                                            implicitWidth: heroMonRow.implicitWidth + 12
                                            radius: 6
                                            color: Services.Theme.bgElevated
                                            border.color: Services.Theme.border
                                            border.width: 1
                                            RowLayout {
                                                id: heroMonRow
                                                anchors.centerIn: parent; spacing: 4
                                                Text { text: Services.Icons.display; font.family: Services.Theme.fontSymbols; font.pixelSize: 10; color: Services.Theme.textSecondary }
                                                Text {
                                                    text: {
                                                        const c = Services.Compositor ? Services.Compositor.monitorsCount : 1
                                                        return c + (c > 1 ? " Displays" : " Display")
                                                    }
                                                    font.pixelSize: 9; font.weight: Font.Medium; color: Services.Theme.textPrimary
                                                }
                                            }
                                        }

                                        // Workspace count badge
                                        Rectangle {
                                            visible: rootWindow.width > 700
                                            height: 28
                                            implicitWidth: heroWsRow.implicitWidth + 12
                                            radius: 6
                                            color: Services.Theme.bgElevated
                                            border.color: Services.Theme.border
                                            border.width: 1
                                            RowLayout {
                                                id: heroWsRow
                                                anchors.centerIn: parent; spacing: 4
                                                Text { text: Services.Icons.grid; font.family: Services.Theme.fontSymbols; font.pixelSize: 10; color: Services.Theme.textSecondary }
                                                Text {
                                                    text: {
                                                        const c = Services.Compositor ? Services.Compositor.workspacesCount : 1
                                                        return c + (c > 1 ? " Workspaces" : " Workspace")
                                                    }
                                                    font.pixelSize: 9; font.weight: Font.Medium; color: Services.Theme.textPrimary
                                                }
                                            }
                                        }

                                        // Reload button
                                        Rectangle {
                                            height: 32
                                            implicitWidth: heroRlRow.implicitWidth + 18
                                            radius: 6
                                            color: heroRlMouse.containsMouse ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.28) : Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.14)
                                            border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.50)
                                            border.width: 1
                                            scale: heroRlMouse.pressed ? 0.96 : (heroRlMouse.containsMouse ? 1.02 : 1.0)
                                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
                                            Behavior on color { ColorAnimation { duration: 150 } }

                                            RowLayout {
                                                id: heroRlRow
                                                anchors.centerIn: parent
                                                spacing: 6
                                                Text { text: Services.Icons.refresh; font.family: Services.Theme.fontSymbols; font.pixelSize: 12; color: Services.Theme.accent }
                                                Text { text: "Reload"; font.pixelSize: 11; font.weight: Font.Bold; color: Services.Theme.accent }
                                            }
                                            MouseArea {
                                                id: heroRlMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: { if (Services.Compositor) Services.Compositor.reloadCompositor() }
                                            }
                                        }
                                    }
                                }
                            }

                            // ── Segment Switcher Pill Bar (Liquid Glass Elastic Tabs) ──────────────────────────
                            Rectangle {
                                id: compTabBar
                                Layout.fillWidth: true
                                height: 38
                                radius: 8
                                color: Services.Theme.surfaceVariant
                                border.color: Services.Theme.border
                                border.width: 1
                                clip: true

                                // Liquid Glass Sliding Indicator Pill
                                Rectangle {
                                    id: liquidPill
                                    z: 1
                                    y: 3
                                    height: parent.height - 6
                                    radius: 6

                                    readonly property int tabCount: 5
                                    readonly property real itemWidth: Math.max(0, (compTabBar.width - 6 - (tabCount - 1) * 3) / tabCount)
                                    x: 3 + rootWindow.compSubTab * (itemWidth + 3)
                                    width: itemWidth

                                    // Liquid Transparent Glass Material
                                    color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.22)
                                    border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.55)
                                    border.width: 1

                                    property real stretchScaleX: 1.0
                                    property real stretchScaleY: 1.0
                                    transform: Scale {
                                        origin.x: liquidPill.width / 2
                                        origin.y: liquidPill.height / 2
                                        xScale: liquidPill.stretchScaleX
                                        yScale: liquidPill.stretchScaleY
                                    }

                                    // Top Specular Glass Highlight Line
                                    Rectangle {
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.topMargin: 1
                                        anchors.leftMargin: 4
                                        anchors.rightMargin: 4
                                        height: 1
                                        radius: 0.5
                                        color: Qt.rgba(1, 1, 1, 0.40)
                                    }

                                    // Liquid Gloss Curved Sheen
                                    Rectangle {
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.topMargin: 1
                                        anchors.leftMargin: 2
                                        anchors.rightMargin: 2
                                        height: parent.height * 0.46
                                        radius: 5
                                        gradient: Gradient {
                                            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.16) }
                                            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                                        }
                                    }

                                    // Fluid Sliding Transitions
                                    Behavior on x {
                                        NumberAnimation {
                                            duration: 320
                                            easing.type: Easing.OutBack
                                            easing.overshoot: 1.15
                                        }
                                    }
                                    Behavior on width {
                                        NumberAnimation {
                                            duration: 320
                                            easing.type: Easing.OutBack
                                            easing.overshoot: 1.15
                                        }
                                    }
                                    Behavior on color { ColorAnimation { duration: 250 } }
                                    Behavior on border.color { ColorAnimation { duration: 250 } }
                                }

                                // Fluid Elastic Squash & Stretch Animation
                                SequentialAnimation {
                                    id: fluidStretchAnim
                                    ParallelAnimation {
                                        NumberAnimation { target: liquidPill; property: "stretchScaleX"; to: 1.08; duration: 85; easing.type: Easing.OutQuad }
                                        NumberAnimation { target: liquidPill; property: "stretchScaleY"; to: 0.92; duration: 85; easing.type: Easing.OutQuad }
                                    }
                                    ParallelAnimation {
                                        NumberAnimation { target: liquidPill; property: "stretchScaleX"; to: 1.0; duration: 235; easing.type: Easing.OutBack; easing.overshoot: 1.28 }
                                        NumberAnimation { target: liquidPill; property: "stretchScaleY"; to: 1.0; duration: 235; easing.type: Easing.OutBack; easing.overshoot: 1.28 }
                                    }
                                }

                                Connections {
                                    target: rootWindow
                                    function onCompSubTabChanged() {
                                        fluidStretchAnim.restart()
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 3
                                    spacing: 3
                                    z: 2

                                    Repeater {
                                        model: [
                                            { id: 0, label: (compTabBar.width < 520 ? "Styling" : "Window Styling"),  icon: Services.Icons.sparkles },
                                            { id: 1, label: "Displays",                                                icon: Services.Icons.display },
                                            { id: 2, label: (compTabBar.width < 520 ? "Input" : "Input & Gestures"),   icon: Services.Icons.sliders },
                                            { id: 3, label: (compTabBar.width < 520 ? "Power" : "Power & Gaming"),     icon: Services.Icons.speed },
                                            { id: 4, label: (compTabBar.width < 520 ? "Autostart" : "Autostart Apps"), icon: Services.Icons.rocket || "󰐥" }
                                        ]

                                        delegate: Item {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            readonly property bool isCur: rootWindow.compSubTab === modelData.id
                                            readonly property bool isHyprOnly: modelData.id !== 1 && modelData.id !== 4
                                            readonly property bool nonHypr: isHyprOnly && !(Services.Compositor && (Services.Compositor.activeCompositor === "hyprland" || Services.Compositor.activeCompositor === "niri"))

                                            // Hover effect for unselected tabs
                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 5
                                                color: subMouse.containsMouse && !isCur ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                            }

                                            RowLayout {
                                                anchors.centerIn: parent
                                                width: Math.min(parent.width - 6, implicitWidth)
                                                spacing: 5
                                                z: 2
                                                Text {
                                                    text: modelData.icon
                                                    font.family: Services.Theme.fontSymbols; font.pixelSize: 11
                                                    color: isCur ? Services.Theme.accent : (subMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary)
                                                    Behavior on color { ColorAnimation { duration: 200 } }
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData.label
                                                    font.pixelSize: 11
                                                    font.weight: isCur ? Font.DemiBold : Font.Normal
                                                    color: isCur ? Services.Theme.textPrimary : (subMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary)
                                                    elide: Text.ElideRight
                                                    Behavior on color { ColorAnimation { duration: 200 } }
                                                }
                                            }
                                            MouseArea {
                                                id: subMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    rootWindow.compSubTab = modelData.id
                                                    if (modelData.id === 4 && Services.Compositor) {
                                                        Services.Compositor.loadAutostart()
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ── SUB-TAB 0: WINDOW STYLING & GLASS ──────────────────
                            ColumnLayout {
                                visible: rootWindow.compSubTab === 0
                                Layout.fillWidth: true
                                spacing: 10

                                SettingsSection {
                                    title: "Window Animations"
                                    icon: Services.Icons.sparkle

                                    SettingsSwitch {
                                        title: "Window Animations"
                                        subtitle: "Enable window open, close and resize animations"
                                        checked: Services.Compositor ? Services.Compositor.hyprAnim : true
                                        onToggled: () => { if (Services.Compositor) Services.Compositor.toggleHyprAnim() }
                                    }

                                    SettingsDivider {}

                                    SettingsRow {
                                        title: "Animation Preset"
                                        subtitle: "Select easing curve profile and global motion speed"

                                        SettingsDropdown {
                                            minButtonWidth: 140
                                            maxButtonWidth: 190
                                            model: (Services.Compositor && Services.Compositor.hyprAnimStyles && Services.Compositor.hyprAnimStyles.length > 0)
                                                ? Services.Compositor.hyprAnimStyles.map(function(s) {
                                                    return { id: s.id, label: s.name }
                                                })
                                                : [
                                                    { id: "fluid", label: "Fluid" },
                                                    { id: "snappy", label: "Snappy" },
                                                    { id: "bouncy", label: "Bouncy" },
                                                    { id: "gentle", label: "Gentle" },
                                                    { id: "linear", label: "Linear" },
                                                    { id: "disabled", label: "Disabled" }
                                                ]
                                            currentValue: Services.Compositor ? Services.Compositor.hyprAnimStyle : "fluid"
                                            onSelected: function(val) {
                                                if (Services.Compositor) Services.Compositor.setHyprAnimStyle(val)
                                            }
                                        }
                                    }
                                }

                                SettingsSection {
                                    title: "Workspace Animations"
                                    icon: Services.Icons.grid

                                    SettingsSwitch {
                                        title: "Workspace Transitions"
                                        subtitle: "Animate transitions when switching or swiping workspaces"
                                        checked: Services.Compositor ? Services.Compositor.hyprWorkspaceAnim : true
                                        onToggled: () => { if (Services.Compositor) Services.Compositor.toggleWorkspaceAnim() }
                                    }

                                    SettingsDivider {}

                                    SettingsRow {
                                        title: "Transition Effect"
                                        subtitle: "Movement style and direction for workspace transitions"

                                        SettingsDropdown {
                                            minButtonWidth: 160
                                            maxButtonWidth: 220
                                            model: [
                                                { id: "slidevert", label: "Vertical Slide" },
                                                { id: "slide", label: "Horizontal Slide" },
                                                { id: "slidefade", label: "Slide & Fade" },
                                                { id: "slidefadevert", label: "Vertical Slide & Fade" },
                                                { id: "fade", label: "Crossfade" }
                                            ]
                                            currentValue: Services.Compositor ? Services.Compositor.hyprWorkspaceAnimStyle : "slidevert"
                                            onSelected: function(val) {
                                                if (Services.Compositor) Services.Compositor.setWorkspaceAnimStyle(val)
                                            }
                                        }
                                    }

                                    SettingsDivider {}

                                    SettingsRow {
                                        title: "Easing Curve (Bezier)"
                                        subtitle: "Motion curve and momentum deceleration"

                                        SettingsDropdown {
                                            minButtonWidth: 160
                                            maxButtonWidth: 220
                                            model: (Services.Compositor && Services.Compositor.availableBeziers && Services.Compositor.availableBeziers.length > 0)
                                                ? Services.Compositor.availableBeziers.map(function(b) {
                                                    return { id: b, label: b }
                                                })
                                                : [
                                                    { id: "quick", label: "quick" },
                                                    { id: "overshoot", label: "overshoot" },
                                                    { id: "easeOutQuint", label: "easeOutQuint" },
                                                    { id: "easeInOutCubic", label: "easeInOutCubic" },
                                                    { id: "almostLinear", label: "almostLinear" },
                                                    { id: "linear", label: "linear" },
                                                    { id: "default", label: "default" }
                                                ]
                                            currentValue: Services.Compositor ? Services.Compositor.hyprWorkspaceAnimBezier : "quick"
                                            onSelected: function(val) {
                                                if (Services.Compositor) Services.Compositor.setWorkspaceAnimBezier(val)
                                            }
                                        }
                                    }

                                    SettingsDivider {}

                                    SettingsSlider {
                                        title: "Transition Speed"
                                        from: 1; to: 10; stepSize: 0.5; decimals: 1; valueSuffix: "x"
                                        value: Services.Compositor ? Services.Compositor.hyprWorkspaceAnimSpeed : 2.0
                                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setWorkspaceAnimSpeed(v) }
                                    }
                                }

                                SettingsSection {
                                    title: "Blur & Drop Shadows"
                                    icon: Services.Icons.eye

                                    SettingsSwitch {
                                        title: "Blur"
                                        subtitle: "Background blur for transparent windows and panels"
                                        checked: Services.Compositor ? Services.Compositor.hyprBlur : true
                                        onToggled: () => { if (Services.Compositor) Services.Compositor.toggleHyprBlur() }
                                    }

                                    SettingsDivider {}

                                    SettingsSlider {
                                        title: "Blur Radius (Size)"
                                        from: 1; to: 16; stepSize: 1; valueSuffix: "px"
                                        value: Services.Compositor ? Services.Compositor.hyprBlurSize : 4
                                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprBlurSize(Math.round(v)) }
                                    }

                                    SettingsDivider {}

                                    SettingsSlider {
                                        title: "Blur Iterations (Passes)"
                                        from: 1; to: 5; stepSize: 1; valueSuffix: "x"
                                        value: Services.Compositor ? Services.Compositor.hyprBlurPasses : 2
                                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprBlurPasses(Math.round(v)) }
                                    }

                                    SettingsDivider {}

                                    SettingsSwitch {
                                        title: "Window Drop Shadows"
                                        subtitle: "Render soft ambient depth shadows behind active and floating windows"
                                        checked: Services.Compositor ? Services.Compositor.hyprShadow : true
                                        onToggled: () => { if (Services.Compositor) Services.Compositor.toggleHyprShadow() }
                                    }

                                    SettingsDivider {}

                                    SettingsSlider {
                                        title: "Shadow Range / Blur"
                                        from: 0; to: 30; stepSize: 1; valueSuffix: "px"
                                        value: Services.Compositor ? Services.Compositor.hyprShadowRange : 4
                                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprShadowRange(Math.round(v)) }
                                    }
                                }

                                SettingsSection {
                                    title: "Window Opacity & Dimming"
                                    icon: Services.Icons.contrast

                                    SettingsSlider {
                                        title: "Active Window Opacity"
                                        from: 0.50; to: 1.00; stepSize: 0.01; decimals: 2
                                        value: Services.Compositor ? Services.Compositor.hyprActiveOpacity : 0.90
                                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprActiveOpacity(Number(v.toFixed(2))) }
                                    }

                                    SettingsDivider {}

                                    SettingsSlider {
                                        title: "Inactive Window Opacity"
                                        from: 0.50; to: 1.00; stepSize: 0.01; decimals: 2
                                        value: Services.Compositor ? Services.Compositor.hyprInactiveOpacity : 0.95
                                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprInactiveOpacity(Number(v.toFixed(2))) }
                                    }
                                }

                                SettingsSection {
                                    title: "Window Geometry, Gaps & Layout"
                                    icon: Services.Icons.layout

                                    SettingsSlider {
                                        title: "Window Corner Radius"
                                        from: 0; to: 28; stepSize: 1; valueSuffix: "px"
                                        value: Services.Compositor ? Services.Compositor.hyprRounding : 10
                                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprRounding(Math.round(v)) }
                                    }

                                    SettingsDivider {}

                                    SettingsSlider {
                                        title: "Border Thickness"
                                        from: 0; to: 6; stepSize: 1; valueSuffix: "px"
                                        value: Services.Compositor ? Services.Compositor.hyprBorderSize : 0
                                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprBorderSize(Math.round(v)) }
                                    }

                                    SettingsDivider {}

                                    SettingsSlider {
                                        title: "Gaps In (Between Windows)"
                                        from: 0; to: 24; stepSize: 1; valueSuffix: "px"
                                        value: Services.Compositor ? Services.Compositor.hyprGapsIn : 5
                                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprGapsIn(Math.round(v)) }
                                    }

                                    SettingsDivider {}

                                    SettingsSlider {
                                        title: "Gaps Out (Screen Margins)"
                                        from: 0; to: 36; stepSize: 1; valueSuffix: "px"
                                        value: Services.Compositor ? Services.Compositor.hyprGapsOut : 10
                                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprGapsOut(Math.round(v)) }
                                    }

                                    SettingsDivider {}

                                    SettingsSwitch {
                                        title: "Smart Gaps (No Gaps When Only)"
                                        subtitle: "Automatically remove gaps and borders if only one window is open"
                                        checked: Services.Compositor ? Services.Compositor.hyprSmartGaps : false
                                        onToggled: () => { if (Services.Compositor) Services.Compositor.toggleHyprSmartGaps() }
                                    }

                                    SettingsDivider {}

                                    SettingsRow {
                                        title: "Tiling Layout Engine"
                                        subtitle: "Select active window tiling algorithm"

                                        SettingsDropdown {
                                            currentValue: Services.Compositor ? Services.Compositor.hyprLayout : "dwindle"
                                            model: (Services.Compositor && Services.Compositor.activeCompositor === "niri")
                                                ? [ { id: "scrolling", label: "Scrolling" } ]
                                                : [
                                                    { id: "dwindle",   label: "Dwindle" },
                                                    { id: "master",    label: "Master" },
                                                    { id: "scrolling", label: "Scrolling" }
                                                ]
                                            onSelected: (val) => { if (Services.Compositor) Services.Compositor.setHyprLayout(val) }
                                        }
                                    }

                                    SettingsDivider {
                                        visible: Services.Compositor && (Services.Compositor.hyprLayout === "scrolling" || Services.Compositor.activeCompositor === "niri")
                                    }

                                    SettingsSlider {
                                        visible: Services.Compositor && (Services.Compositor.hyprLayout === "scrolling" || Services.Compositor.activeCompositor === "niri")
                                        title: "Scrolling Column Width"
                                        subtitle: "Default viewport ratio allocated per window column"
                                        from: 0.30; to: 1.00; stepSize: 0.01; decimals: 2
                                        value: Services.Compositor ? Services.Compositor.hyprScrollingColumnWidth : 0.89
                                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprScrollingColumnWidth(Number(v.toFixed(2))) }
                                    }

                                    SettingsDivider {
                                        visible: Services.Compositor && (Services.Compositor.hyprLayout === "scrolling" || Services.Compositor.activeCompositor === "niri")
                                    }

                                    SettingsSwitch {
                                        visible: Services.Compositor && (Services.Compositor.hyprLayout === "scrolling" || Services.Compositor.activeCompositor === "niri")
                                        title: "Fullscreen Single Column"
                                        subtitle: "Automatically expand column to fullscreen if only one column exists"
                                        checked: Services.Compositor ? Services.Compositor.hyprScrollingFullscreenOnOneColumn : false
                                        onToggled: () => { if (Services.Compositor) Services.Compositor.toggleHyprScrollingFullscreenOnOneColumn() }
                                    }
                                }
                            }

                            // ── SUB-TAB 1: DISPLAYS & MONITORS ─────────────────────
                            ColumnLayout {
                                visible: rootWindow.compSubTab === 1
                                Layout.fillWidth: true
                                spacing: 10

                                // ── 1. SPATIAL TOPOLOGY CARD ────────────────────────
                                SettingsSection {
                                    title: "Display Layout & Canvas"
                                    icon: Services.Icons.display

                                    // Canvas Toolbar Row
                                    SettingsRow {
                                        title: "Display Arrangement"
                                        subtitle: "Drag screens to arrange · Magnetic edge snapping (Zero Overlap)"

                                        RowLayout {
                                            spacing: 6

                                            // Identify Displays
                                            Rectangle {
                                                height: 26
                                                implicitWidth: idRow.implicitWidth + 14
                                                radius: 4
                                                color: idMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Services.Theme.bgElevated
                                                border.color: Services.Theme.border; border.width: 1
                                                RowLayout {
                                                    id: idRow; anchors.centerIn: parent; spacing: 4
                                                    Text { text: "󰍹"; font.family: Services.Theme.fontSymbols; font.pixelSize: 11; color: Services.Theme.accent }
                                                    Text { text: "Identify"; font.pixelSize: 11; color: Services.Theme.textPrimary }
                                                }
                                                MouseArea {
                                                    id: idMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: { if (Services.Compositor) Services.Compositor.identifyMonitors() }
                                                }
                                            }

                                            // Swap (if 2+ monitors)
                                            Rectangle {
                                                visible: rootWindow.dispLocalLayout.length >= 2
                                                height: 26
                                                implicitWidth: swpRow.implicitWidth + 12
                                                radius: 4
                                                color: swpMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Services.Theme.bgElevated
                                                border.color: Services.Theme.border; border.width: 1
                                                RowLayout {
                                                    id: swpRow; anchors.centerIn: parent; spacing: 4
                                                    Text { text: "⇄"; font.pixelSize: 11; color: Services.Theme.textPrimary }
                                                    Text { text: "Swap"; font.pixelSize: 11; color: Services.Theme.textPrimary }
                                                }
                                                MouseArea {
                                                    id: swpMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: rootWindow.swapDisplays()
                                                }
                                            }

                                            // Align Horizontal (Side by Side)
                                            Rectangle {
                                                height: 26
                                                implicitWidth: ahRow.implicitWidth + 10
                                                radius: 4
                                                color: ahMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Services.Theme.bgElevated
                                                border.color: Services.Theme.border; border.width: 1
                                                RowLayout {
                                                    id: ahRow; anchors.centerIn: parent; spacing: 3
                                                    Text { text: "⊞"; font.pixelSize: 11; color: Services.Theme.textPrimary }
                                                    Text { text: "Side by Side"; font.pixelSize: 10; color: Services.Theme.textPrimary }
                                                }
                                                MouseArea {
                                                    id: ahMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: rootWindow.autoAlignDisplaysHorizontal()
                                                }
                                            }

                                            // Align Vertical (Stacked)
                                            Rectangle {
                                                height: 26
                                                implicitWidth: avRow.implicitWidth + 10
                                                radius: 4
                                                color: avMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Services.Theme.bgElevated
                                                border.color: Services.Theme.border; border.width: 1
                                                RowLayout {
                                                    id: avRow; anchors.centerIn: parent; spacing: 3
                                                    Text { text: "⊟"; font.pixelSize: 11; color: Services.Theme.textPrimary }
                                                    Text { text: "Stacked"; font.pixelSize: 10; color: Services.Theme.textPrimary }
                                                }
                                                MouseArea {
                                                    id: avMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: rootWindow.autoAlignDisplaysVertical()
                                                }
                                            }

                                            // Revert
                                            Rectangle {
                                                visible: rootWindow.dispHasPendingChanges
                                                height: 26
                                                implicitWidth: rvtRow.implicitWidth + 12
                                                radius: 4
                                                color: rvtMouse.containsMouse ? Qt.rgba(0.9, 0.2, 0.2, 0.15) : Services.Theme.bgElevated
                                                border.color: Services.Theme.border; border.width: 1
                                                RowLayout {
                                                    id: rvtRow; anchors.centerIn: parent; spacing: 4
                                                    Text { text: "󰕌"; font.family: Services.Theme.fontSymbols; font.pixelSize: 10; color: Services.Theme.danger }
                                                    Text { text: "Revert"; font.pixelSize: 10; color: Services.Theme.danger }
                                                }
                                                MouseArea {
                                                    id: rvtMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: rootWindow.revertDisplayChanges()
                                                }
                                            }

                                            // Save & Apply
                                            Rectangle {
                                                height: 26
                                                implicitWidth: savRow.implicitWidth + 14
                                                radius: 4
                                                color: rootWindow.dispHasPendingChanges ? Services.Theme.accent : (savMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Services.Theme.bgElevated)
                                                border.color: rootWindow.dispHasPendingChanges ? Services.Theme.accent : Services.Theme.border
                                                border.width: 1
                                                RowLayout {
                                                    id: savRow; anchors.centerIn: parent; spacing: 4
                                                    Text {
                                                        text: rootWindow.dispIsApplying ? "󰑮" : (rootWindow.dispHasPendingChanges ? "󰄬" : "󰆓")
                                                        font.family: Services.Theme.fontSymbols
                                                        font.pixelSize: 11
                                                        color: rootWindow.dispHasPendingChanges ? Services.Theme.bgOnAccent : Services.Theme.textSecondary
                                                    }
                                                    Text {
                                                        text: rootWindow.dispIsApplying ? "Saving..." : (rootWindow.dispHasPendingChanges ? "Save Layout" : "Saved")
                                                        font.pixelSize: 11
                                                        font.weight: rootWindow.dispHasPendingChanges ? Font.Bold : Font.Normal
                                                        color: rootWindow.dispHasPendingChanges ? Services.Theme.bgOnAccent : Services.Theme.textSecondary
                                                    }
                                                }
                                                MouseArea {
                                                    id: savMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: rootWindow.applyDisplayLayout(true)
                                                }
                                            }
                                        }
                                    }

                                    SettingsDivider {}

                                    // Canvas Stage Box (Refined High-Precision Spatial Canvas)
                                    Rectangle {
                                        id: stageBox
                                        Layout.fillWidth: true
                                        Layout.margins: 8
                                        height: 285
                                        radius: Services.Theme.radiusSm || 8
                                        color: Services.Theme.isDark ? "#101014" : "#e8ebf0"
                                        border.color: Services.Theme.border
                                        border.width: 1
                                        clip: true

                                        // Subtle Luxury Coordinate Blueprint Grid
                                        Canvas {
                                            anchors.fill: parent
                                            opacity: Services.Theme.isDark ? 0.35 : 0.45
                                            onPaint: {
                                                var ctx = getContext("2d")
                                                ctx.clearRect(0, 0, width, height)
                                                ctx.strokeStyle = Services.Theme.isDark ? "#282834" : "#d1d5db"
                                                ctx.lineWidth = 0.75
                                                var step = 24
                                                for (var x = 0; x < width; x += step) {
                                                    ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke()
                                                }
                                                for (var y = 0; y < height; y += step) {
                                                    ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke()
                                                }
                                            }
                                        }

                                        readonly property real totalVirtWidth: {
                                            if (!rootWindow.dispLocalLayout || rootWindow.dispLocalLayout.length === 0) return 1920
                                            var maxX = 0
                                            for (var i = 0; i < rootWindow.dispLocalLayout.length; i++) {
                                                var m = rootWindow.dispLocalLayout[i]
                                                if (m.disabled) continue
                                                var logW = rootWindow.getDisplayLogWidth(m)
                                                var endX = (m.x || 0) + logW
                                                if (endX > maxX) maxX = endX
                                            }
                                            return Math.max(800, maxX)
                                        }

                                        readonly property real totalVirtHeight: {
                                            if (!rootWindow.dispLocalLayout || rootWindow.dispLocalLayout.length === 0) return 1080
                                            var maxY = 0
                                            for (var i = 0; i < rootWindow.dispLocalLayout.length; i++) {
                                                var m = rootWindow.dispLocalLayout[i]
                                                if (m.disabled) continue
                                                var logH = rootWindow.getDisplayLogHeight(m)
                                                var endY = (m.y || 0) + logH
                                                if (endY > maxY) maxY = endY
                                            }
                                            return Math.max(600, maxY)
                                        }

                                        readonly property real stageScale: {
                                            var availW = stageBox.width - 64
                                            var availH = stageBox.height - 64
                                            if (availW <= 0 || availH <= 0) return 0.20
                                            return Math.min(availW / totalVirtWidth, availH / totalVirtHeight, 0.35)
                                        }

                                        readonly property real originStageX: {
                                            var contentW = totalVirtWidth * stageScale
                                            return Math.max(20, (stageBox.width - contentW) / 2)
                                        }

                                        readonly property real originStageY: {
                                            var contentH = totalVirtHeight * stageScale
                                            return Math.max(20, (stageBox.height - contentH) / 2)
                                        }

                                        // Snap laser guidelines
                                        Rectangle {
                                            visible: rootWindow.dispShowSnapGuideX
                                            x: rootWindow.dispSnapGuideX
                                            anchors.top: parent.top; anchors.bottom: parent.bottom
                                            width: 1.5; color: Services.Theme.accent; z: 90
                                        }
                                        Rectangle {
                                            visible: rootWindow.dispShowSnapGuideY
                                            y: rootWindow.dispSnapGuideY
                                            anchors.left: parent.left; anchors.right: parent.right
                                            height: 1.5; color: Services.Theme.accent; z: 90
                                        }

                                        // Floating Magnetic Snap Badge Hint
                                        Rectangle {
                                            visible: rootWindow.dispIsDragging && rootWindow.dispDockMessage.length > 0
                                            anchors.top: parent.top
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.topMargin: 8
                                            height: 24
                                            implicitWidth: snapMsgTxt.implicitWidth + 24
                                            radius: 12
                                            color: Services.Theme.accent
                                            z: 200
                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: 6
                                                Text { text: "󰄬"; font.family: Services.Theme.fontSymbols; font.pixelSize: 11; color: Services.Theme.bgOnAccent || "#ffffff" }
                                                Text { id: snapMsgTxt; text: "Magnetic Snap: " + rootWindow.dispDockMessage; font.pixelSize: 11; font.weight: Font.Bold; color: Services.Theme.bgOnAccent || "#ffffff" }
                                            }
                                        }

                                        // Monitor screen cards
                                        Repeater {
                                            model: rootWindow.dispLocalLayout

                                            delegate: Item {
                                                id: mBox
                                                required property var modelData
                                                required property int index

                                                property real dragVisualX: 0
                                                property real dragVisualY: 0
                                                property bool isBeingDragged: false

                                                readonly property bool isSelected: rootWindow.dispSelectedMonitorName === modelData.name
                                                readonly property real effLogW: rootWindow.getDisplayLogWidth(modelData)
                                                readonly property real effLogH: rootWindow.getDisplayLogHeight(modelData)
                                                readonly property real cardW: Math.max(120, effLogW * stageBox.stageScale)
                                                readonly property real cardH: Math.max(80, effLogH * stageBox.stageScale)

                                                readonly property real baseX: stageBox.originStageX + (modelData.x * stageBox.stageScale)
                                                readonly property real baseY: stageBox.originStageY + (modelData.y * stageBox.stageScale)

                                                x: isBeingDragged ? dragVisualX : baseX
                                                y: isBeingDragged ? dragVisualY : baseY
                                                width: cardW
                                                height: cardH
                                                z: isBeingDragged ? 100 : (isSelected ? 20 : 10)

                                                Behavior on x { enabled: !mBox.isBeingDragged; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                Behavior on y { enabled: !mBox.isBeingDragged; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: 8
                                                    color: mBox.isSelected ? Services.Theme.bgElevated : Services.Theme.surfaceVariant
                                                    border.color: mBox.isSelected ? Services.Theme.accent : (mDrag.containsMouse ? Services.Theme.borderHighlight : Services.Theme.border)
                                                    border.width: mBox.isSelected ? 2 : 1
                                                    opacity: mBox.modelData.disabled ? 0.45 : (mBox.isBeingDragged ? 0.95 : 1.0)
                                                    scale: mBox.isBeingDragged ? 1.04 : (mDrag.containsMouse ? 1.02 : 1.0)
                                                    Behavior on scale { NumberAnimation { duration: 120 } }

                                                    // Drag Grip Dots Indicator (Top Right)
                                                    Text {
                                                        anchors.top: parent.top
                                                        anchors.right: parent.right
                                                        anchors.margins: 6
                                                        text: "⠿"
                                                        font.pixelSize: 10
                                                        color: mBox.isSelected ? Services.Theme.accent : Services.Theme.textDisabled
                                                    }

                                                    ColumnLayout {
                                                        anchors.centerIn: parent
                                                        spacing: 3

                                                        RowLayout {
                                                            Layout.alignment: Qt.AlignHCenter
                                                            spacing: 5
                                                            Text {
                                                                text: mBox.modelData.name.toLowerCase().includes("edp") ? "󰌢" : "󰍹"
                                                                font.family: Services.Theme.fontSymbols
                                                                font.pixelSize: 12
                                                                color: mBox.isSelected ? Services.Theme.accent : Services.Theme.textSecondary
                                                            }
                                                            Text {
                                                                text: mBox.modelData.name + (mBox.modelData.focused ? " ★" : "")
                                                                font.pixelSize: 11
                                                                font.weight: Font.DemiBold
                                                                color: mBox.isSelected ? Services.Theme.accent : Services.Theme.textPrimary
                                                            }
                                                        }

                                                        Text {
                                                            Layout.alignment: Qt.AlignHCenter
                                                            text: mBox.modelData.width + "×" + mBox.modelData.height
                                                            font.family: Services.Theme.fontMono
                                                            font.pixelSize: 10
                                                            color: Services.Theme.textSecondary
                                                        }

                                                        RowLayout {
                                                            Layout.alignment: Qt.AlignHCenter
                                                            spacing: 4
                                                            Text {
                                                                text: mBox.modelData.refreshRate + "Hz"
                                                                font.pixelSize: 9
                                                                color: Services.Theme.accent
                                                            }
                                                            Text { text: "·"; font.pixelSize: 9; color: Services.Theme.textDisabled }
                                                            Text {
                                                                text: (mBox.modelData.scale || 1.0) + "x"
                                                                font.pixelSize: 9
                                                                color: Services.Theme.textSecondary
                                                            }
                                                        }

                                                        Text {
                                                            Layout.alignment: Qt.AlignHCenter
                                                            text: "(" + mBox.modelData.x + ", " + mBox.modelData.y + ")"
                                                            font.family: Services.Theme.fontMono
                                                            font.pixelSize: 8
                                                            color: Services.Theme.textDisabled
                                                        }
                                                    }
                                                }

                                                // Floating Live Coordinate Tooltip while dragging
                                                Rectangle {
                                                    visible: mBox.isBeingDragged
                                                    anchors.bottom: parent.top
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    anchors.bottomMargin: 6
                                                    height: 22
                                                    implicitWidth: liveTipTxt.implicitWidth + 14
                                                    radius: 4
                                                    color: Services.Theme.bgElevated
                                                    border.color: Services.Theme.accent
                                                    border.width: 1
                                                    z: 110

                                                    Text {
                                                        id: liveTipTxt
                                                        anchors.centerIn: parent
                                                        text: mBox.modelData.name + " · X: " + Math.max(0, Math.round((mBox.x - stageBox.originStageX) / stageBox.stageScale)) + "  Y: " + Math.max(0, Math.round((mBox.y - stageBox.originStageY) / stageBox.stageScale))
                                                        font.family: Services.Theme.fontMono
                                                        font.pixelSize: 10
                                                        font.weight: Font.Bold
                                                        color: Services.Theme.accent
                                                    }
                                                }

                                                MouseArea {
                                                    id: mDrag
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                                                    property real grabOffsetX: 0
                                                    property real grabOffsetY: 0

                                                    onPressed: (mouse) => {
                                                        rootWindow.dispSelectedMonitorName = mBox.modelData.name
                                                        rootWindow.dispIsDragging = true
                                                        mBox.isBeingDragged = true

                                                        grabOffsetX = mouse.x
                                                        grabOffsetY = mouse.y

                                                        mBox.dragVisualX = mBox.x
                                                        mBox.dragVisualY = mBox.y
                                                    }

                                                    onPositionChanged: (mouse) => {
                                                        if (!pressed) return

                                                        var curMouseStage = mapToItem(stageBox, mouse.x, mouse.y)
                                                        var rawVisualX = curMouseStage.x - grabOffsetX
                                                        var rawVisualY = curMouseStage.y - grabOffsetY

                                                        rawVisualX = Math.max(6, Math.min(stageBox.width - mBox.width - 6, rawVisualX))
                                                        rawVisualY = Math.max(6, Math.min(stageBox.height - mBox.height - 6, rawVisualY))

                                                        if (rootWindow.dispLocalLayout.length > 1) {
                                                            var snap = rootWindow.calcDisplaySnap(mBox.index, rawVisualX, rawVisualY, mBox.width, mBox.height, stageBox.originStageX, stageBox.originStageY, stageBox.stageScale)
                                                            mBox.dragVisualX = snap.snappedStageX
                                                            mBox.dragVisualY = snap.snappedStageY

                                                            rootWindow.dispSnapGuideX = snap.guideX
                                                            rootWindow.dispShowSnapGuideX = snap.hasGuideX
                                                            rootWindow.dispSnapGuideY = snap.guideY
                                                            rootWindow.dispShowSnapGuideY = snap.hasGuideY
                                                            rootWindow.dispDockMessage = snap.dockMessage
                                                        } else {
                                                            mBox.dragVisualX = rawVisualX
                                                            mBox.dragVisualY = rawVisualY
                                                            rootWindow.dispShowSnapGuideX = false
                                                            rootWindow.dispShowSnapGuideY = false
                                                            rootWindow.dispDockMessage = ""
                                                        }
                                                    }

                                                    onReleased: (mouse) => {
                                                        rootWindow.dispIsDragging = false
                                                        rootWindow.dispShowSnapGuideX = false
                                                        rootWindow.dispShowSnapGuideY = false
                                                        rootWindow.dispDockMessage = ""

                                                        if (rootWindow.dispLocalLayout.length > 1) {
                                                            rootWindow.commitDisplayDrop(mBox.index, mBox.dragVisualX, mBox.dragVisualY, stageBox.originStageX, stageBox.originStageY, stageBox.stageScale)
                                                        }
                                                        mBox.isBeingDragged = false
                                                    }

                                                    onCanceled: {
                                                        rootWindow.dispIsDragging = false
                                                        rootWindow.dispShowSnapGuideX = false
                                                        rootWindow.dispShowSnapGuideY = false
                                                        rootWindow.dispDockMessage = ""
                                                        mBox.isBeingDragged = false
                                                    }
                                                }
                                            }
                                        }

                                        // Empty state
                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            visible: !rootWindow.dispLocalLayout || rootWindow.dispLocalLayout.length === 0
                                            spacing: 6
                                            Text { Layout.alignment: Qt.AlignHCenter; text: Services.Icons.display; font.family: Services.Theme.fontSymbols; font.pixelSize: 24; color: Services.Theme.textDisabled }
                                            Text { Layout.alignment: Qt.AlignHCenter; text: "Detecting connected displays..."; font.pixelSize: 11; color: Services.Theme.textSecondary }
                                        }
                                    }
                                }

                                // ── 2. STATUS TOAST BANNER ──────────────────────────
                                Rectangle {
                                    visible: rootWindow.dispStatusMessage.length > 0
                                    Layout.fillWidth: true
                                    height: 32
                                    radius: Services.Theme.radiusSm || 4
                                    color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15)
                                    border.color: Services.Theme.accent
                                    border.width: 1

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 8
                                        Text { text: "󰄬"; font.family: Services.Theme.fontSymbols; font.pixelSize: 11; color: Services.Theme.accent }
                                        Text { text: rootWindow.dispStatusMessage; font.pixelSize: 11; font.weight: Font.Medium; color: Services.Theme.textPrimary; Layout.fillWidth: true }
                                    }
                                }

                                // ── 3. DISPLAY SELECTOR SEGMENT PILLS ───────────────
                                Rectangle {
                                    visible: rootWindow.dispLocalLayout.length > 1
                                    Layout.fillWidth: true
                                    height: 36
                                    radius: Services.Theme.radiusSm || 6
                                    color: Services.Theme.surfaceVariant
                                    border.color: Services.Theme.border
                                    border.width: 1

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 3
                                        spacing: 3

                                        Repeater {
                                            model: rootWindow.dispLocalLayout

                                            delegate: Rectangle {
                                                required property var modelData
                                                required property int index
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                radius: 4

                                                readonly property bool isCur: rootWindow.dispSelectedMonitorName === modelData.name

                                                color: isCur ? Services.Theme.bgElevated : (pMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
                                                border.color: isCur ? Services.Theme.border : "transparent"
                                                border.width: 1

                                                RowLayout {
                                                    anchors.centerIn: parent
                                                    spacing: 6
                                                    Text {
                                                        text: modelData.name.toLowerCase().includes("edp") ? "󰌢" : "󰍹"
                                                        font.family: Services.Theme.fontSymbols
                                                        font.pixelSize: 11
                                                        color: parent.parent.isCur ? Services.Theme.accent : Services.Theme.textSecondary
                                                    }
                                                    Text {
                                                        text: (modelData.name || "Display") + (modelData.focused ? " ★" : "")
                                                        font.pixelSize: 11
                                                        font.weight: parent.parent.isCur ? Font.DemiBold : Font.Normal
                                                        color: parent.parent.isCur ? Services.Theme.textPrimary : Services.Theme.textSecondary
                                                    }
                                                    Text {
                                                        text: modelData.width + "×" + modelData.height
                                                        font.family: Services.Theme.fontMono
                                                        font.pixelSize: 9
                                                        color: Services.Theme.textDisabled
                                                    }
                                                }

                                                MouseArea {
                                                    id: pMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: rootWindow.dispSelectedMonitorName = modelData.name
                                                }
                                            }
                                        }
                                    }
                                }

                                // ── 4. DISPLAY CONFIGURATION (100% Native Settings Components) ──
                                SettingsSection {
                                    title: "Display Output & Scaling · " + (rootWindow.currentDisplayMon ? rootWindow.currentDisplayMon.name : "Active Output")
                                    icon: Services.Icons.sliders

                                    SettingsRow {
                                        title: "Resolution & Refresh Rate"
                                        subtitle: "Active display resolution and refresh rate mode"

                                        SettingsDropdown {
                                            currentValue: (rootWindow.currentDisplayMon && rootWindow.currentDisplayMon.mode) ? rootWindow.currentDisplayMon.mode : "preferred"
                                            minButtonWidth: 200
                                            model: {
                                                var list = [
                                                    { id: "preferred", label: "Auto (Preferred)" },
                                                    { id: "highrr",     label: "Max Refresh Rate" },
                                                    { id: "highres",   label: "Max Resolution" }
                                                ]
                                                if (rootWindow.currentDisplayMon && rootWindow.currentDisplayMon.availableModes) {
                                                    var modes = rootWindow.currentDisplayMon.availableModes
                                                    for (var i = 0; i < modes.length; i++) {
                                                        var mStr = String(modes[i])
                                                        list.push({ id: mStr, label: mStr.replace("@", " @ ").replace("Hz", " Hz") })
                                                    }
                                                }
                                                return list
                                            }
                                            onSelected: (val) => rootWindow.updateDisplayProp("mode", val, true)
                                        }
                                    }

                                    SettingsDivider {}

                                    SettingsSlider {
                                        title: "Display Scale Factor"
                                        subtitle: "Scale UI elements for high-density monitors or low-resolution screens"
                                        from: 0.50
                                        to: 2.50
                                        stepSize: 0.05
                                        decimals: 2
                                        valueSuffix: "x"
                                        value: rootWindow.currentDisplayMon ? (rootWindow.currentDisplayMon.scale || 1.0) : 1.0
                                        onMoved: (v) => rootWindow.updateDisplayProp("scale", Number(Number(v).toFixed(2)), true)
                                    }

                                    SettingsDivider {}

                                    SettingsRow {
                                        title: "Display Orientation"
                                        subtitle: "Rotate screen layout for vertical monitors or flipped setups"

                                        SettingsDropdown {
                                            currentValue: rootWindow.currentDisplayMon ? String(rootWindow.currentDisplayMon.transform || 0) : "0"
                                            minButtonWidth: 160
                                            model: [
                                                { id: "0", label: "0° (Standard Landscape)" },
                                                { id: "1", label: "90° (Portrait Left)" },
                                                { id: "2", label: "180° (Inverted Landscape)" },
                                                { id: "3", label: "270° (Portrait Right)" }
                                            ]
                                            onSelected: (val) => rootWindow.updateDisplayProp("transform", parseInt(val), true)
                                        }
                                    }

                                    SettingsDivider {}

                                    SettingsSwitch {
                                        title: "Variable Refresh Rate (VRR / FreeSync)"
                                        subtitle: "Eliminate tearing and stuttering during gaming and high frame rates"
                                        checked: rootWindow.currentDisplayMon ? Boolean(rootWindow.currentDisplayMon.vrr) : false
                                        onToggled: (st) => rootWindow.updateDisplayProp("vrr", st, true)
                                    }

                                    SettingsDivider {}

                                    SettingsSwitch {
                                        title: "Display Power Output"
                                        subtitle: "Turn monitor output on or off via DPMS"
                                        checked: rootWindow.currentDisplayMon ? !Boolean(rootWindow.currentDisplayMon.disabled) : true
                                        onToggled: (st) => rootWindow.updateDisplayProp("disabled", !st, true)
                                    }

                                    SettingsDivider {}

                                    SettingsSwitch {
                                        title: "Show Status Bar on this Monitor"
                                        subtitle: "Display QuickShell top bar on this screen"
                                        checked: (rootWindow.currentDisplayMon && Services.Config) ? Services.Config.isBarMonitorEnabled(rootWindow.currentDisplayMon.name) : true
                                        onToggled: (st) => {
                                            if (!rootWindow.currentDisplayMon || !Services.Config) return
                                            if (Services.Config.barMonitorMode !== "custom") Services.Config.setBarMonitorMode("custom")
                                            Services.Config.setBarMonitor(rootWindow.currentDisplayMon.name, st)
                                        }
                                    }

                                    SettingsDivider {}

                                    SettingsRow {
                                        title: "Quick Screen Docking"
                                        subtitle: "Instantly attach " + (rootWindow.currentDisplayMon ? rootWindow.currentDisplayMon.name : "display") + " next to adjacent screen"
                                        visible: rootWindow.dispLocalLayout.length > 1

                                        RowLayout {
                                            spacing: 6

                                            Rectangle {
                                                height: 26; implicitWidth: 74; radius: 4
                                                color: dockLMouse.containsMouse ? Qt.rgba(1,1,1,0.08) : Services.Theme.bgElevated
                                                border.color: Services.Theme.border; border.width: 1
                                                RowLayout {
                                                    anchors.centerIn: parent; spacing: 4
                                                    Text { text: "◀"; font.pixelSize: 9; color: Services.Theme.accent }
                                                    Text { text: "Left"; font.pixelSize: 10; color: Services.Theme.textPrimary }
                                                }
                                                MouseArea { id: dockLMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rootWindow.dockSelectedDisplay("left") }
                                            }

                                            Rectangle {
                                                height: 26; implicitWidth: 74; radius: 4
                                                color: dockRMouse.containsMouse ? Qt.rgba(1,1,1,0.08) : Services.Theme.bgElevated
                                                border.color: Services.Theme.border; border.width: 1
                                                RowLayout {
                                                    anchors.centerIn: parent; spacing: 4
                                                    Text { text: "Right"; font.pixelSize: 10; color: Services.Theme.textPrimary }
                                                    Text { text: "▶"; font.pixelSize: 9; color: Services.Theme.accent }
                                                }
                                                MouseArea { id: dockRMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rootWindow.dockSelectedDisplay("right") }
                                            }

                                            Rectangle {
                                                height: 26; implicitWidth: 74; radius: 4
                                                color: dockTMouse.containsMouse ? Qt.rgba(1,1,1,0.08) : Services.Theme.bgElevated
                                                border.color: Services.Theme.border; border.width: 1
                                                RowLayout {
                                                    anchors.centerIn: parent; spacing: 4
                                                    Text { text: "▲"; font.pixelSize: 9; color: Services.Theme.accent }
                                                    Text { text: "Above"; font.pixelSize: 10; color: Services.Theme.textPrimary }
                                                }
                                                MouseArea { id: dockTMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rootWindow.dockSelectedDisplay("top") }
                                            }

                                            Rectangle {
                                                height: 26; implicitWidth: 74; radius: 4
                                                color: dockBMouse.containsMouse ? Qt.rgba(1,1,1,0.08) : Services.Theme.bgElevated
                                                border.color: Services.Theme.border; border.width: 1
                                                RowLayout {
                                                    anchors.centerIn: parent; spacing: 4
                                                    Text { text: "▼"; font.pixelSize: 9; color: Services.Theme.accent }
                                                    Text { text: "Below"; font.pixelSize: 10; color: Services.Theme.textPrimary }
                                                }
                                                MouseArea { id: dockBMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rootWindow.dockSelectedDisplay("bottom") }
                                            }
                                        }
                                    }

                                    SettingsDivider { visible: rootWindow.dispLocalLayout.length > 1 }

                                    SettingsRow {
                                        title: "Manual Spatial Offsets"
                                        subtitle: "Fine-tune precise X and Y pixel positions"

                                        RowLayout {
                                            spacing: 10

                                            // X Stepper
                                            RowLayout {
                                                spacing: 4
                                                Text { text: "X:"; font.family: Services.Theme.fontMono; font.pixelSize: 11; font.weight: Font.Bold; color: Services.Theme.textSecondary }
                                                Rectangle {
                                                    height: 26; implicitWidth: 84; radius: 4
                                                    color: Services.Theme.bgElevated; border.color: Services.Theme.border; border.width: 1
                                                    RowLayout {
                                                        anchors.fill: parent; anchors.margins: 2; spacing: 2
                                                        Rectangle {
                                                            width: 20; height: 20; radius: 3
                                                            color: xMinMouse.containsMouse ? Qt.rgba(1,1,1,0.1) : "transparent"
                                                            Text { anchors.centerIn: parent; text: "−"; font.pixelSize: 12; color: Services.Theme.textPrimary }
                                                            MouseArea { id: xMinMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rootWindow.updateDisplayProp("x", Math.max(0, (rootWindow.currentDisplayMon ? rootWindow.currentDisplayMon.x : 0) - 50), true) }
                                                        }
                                                        Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: (rootWindow.currentDisplayMon ? rootWindow.currentDisplayMon.x : 0) + "px"; font.family: Services.Theme.fontMono; font.pixelSize: 10; color: Services.Theme.textPrimary }
                                                        Rectangle {
                                                            width: 20; height: 20; radius: 3
                                                            color: xPlusMouse.containsMouse ? Qt.rgba(1,1,1,0.1) : "transparent"
                                                            Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 12; color: Services.Theme.textPrimary }
                                                            MouseArea { id: xPlusMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rootWindow.updateDisplayProp("x", (rootWindow.currentDisplayMon ? rootWindow.currentDisplayMon.x : 0) + 50, true) }
                                                        }
                                                    }
                                                }
                                            }

                                            // Y Stepper
                                            RowLayout {
                                                spacing: 4
                                                Text { text: "Y:"; font.family: Services.Theme.fontMono; font.pixelSize: 11; font.weight: Font.Bold; color: Services.Theme.textSecondary }
                                                Rectangle {
                                                    height: 26; implicitWidth: 84; radius: 4
                                                    color: Services.Theme.bgElevated; border.color: Services.Theme.border; border.width: 1
                                                    RowLayout {
                                                        anchors.fill: parent; anchors.margins: 2; spacing: 2
                                                        Rectangle {
                                                            width: 20; height: 20; radius: 3
                                                            color: yMinMouse.containsMouse ? Qt.rgba(1,1,1,0.1) : "transparent"
                                                            Text { anchors.centerIn: parent; text: "−"; font.pixelSize: 12; color: Services.Theme.textPrimary }
                                                            MouseArea { id: yMinMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rootWindow.updateDisplayProp("y", Math.max(0, (rootWindow.currentDisplayMon ? rootWindow.currentDisplayMon.y : 0) - 50), true) }
                                                        }
                                                        Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: (rootWindow.currentDisplayMon ? rootWindow.currentDisplayMon.y : 0) + "px"; font.family: Services.Theme.fontMono; font.pixelSize: 10; color: Services.Theme.textPrimary }
                                                        Rectangle {
                                                            width: 20; height: 20; radius: 3
                                                            color: yPlusMouse.containsMouse ? Qt.rgba(1,1,1,0.1) : "transparent"
                                                            Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 12; color: Services.Theme.textPrimary }
                                                            MouseArea { id: yPlusMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rootWindow.updateDisplayProp("y", (rootWindow.currentDisplayMon ? rootWindow.currentDisplayMon.y : 0) + 50, true) }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    SettingsDivider {}

                                    SettingsRow {
                                        title: "Mirror Display"
                                        subtitle: "Clone another connected monitor's screen output"

                                        SettingsDropdown {
                                            currentValue: (rootWindow.currentDisplayMon && rootWindow.currentDisplayMon.mirrorOf) ? rootWindow.currentDisplayMon.mirrorOf : "none"
                                            minButtonWidth: 160
                                            model: {
                                                var list = [{ id: "none", label: "None (Extend Display)" }]
                                                for (var i = 0; i < rootWindow.dispLocalLayout.length; i++) {
                                                    var m = rootWindow.dispLocalLayout[i]
                                                    if (rootWindow.currentDisplayMon && m.name !== rootWindow.currentDisplayMon.name) {
                                                        list.push({ id: m.name, label: "Mirror " + m.name })
                                                    }
                                                }
                                                return list
                                            }
                                            onSelected: (val) => rootWindow.updateDisplayProp("mirrorOf", val, true)
                                        }
                                    }

                                    SettingsDivider {}

                                    SettingsRow {
                                        title: "Primary Display Target"
                                        subtitle: "Designate as active target for new windows and primary bar"

                                        Rectangle {
                                            height: 26
                                            implicitWidth: primTxt.implicitWidth + 14
                                            radius: 4
                                            readonly property bool isPrim: rootWindow.currentDisplayMon && rootWindow.currentDisplayMon.focused
                                            color: isPrim ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.18) : (primMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Services.Theme.bgElevated)
                                            border.color: isPrim ? Services.Theme.accent : Services.Theme.border
                                            border.width: 1

                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: 4
                                                Text { text: parent.parent.isPrim ? "★" : "☆"; font.pixelSize: 10; color: Services.Theme.accent }
                                                Text { id: primTxt; text: parent.parent.isPrim ? "Primary Display" : "Set as Primary"; font.pixelSize: 11; font.weight: parent.parent.isPrim ? Font.Bold : Font.Normal; color: parent.parent.isPrim ? Services.Theme.accent : Services.Theme.textPrimary }
                                            }
                                            MouseArea {
                                                id: primMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (rootWindow.currentDisplayMon) rootWindow.setDisplayAsPrimary(rootWindow.currentDisplayMon.name)
                                                }
                                            }
                                        }
                                    }
                                }

                                // ── 5. HARDWARE DIAGNOSTICS SECTION ─────────────────
                                SettingsSection {
                                    title: "Hardware Specifications & Diagnostics"
                                    icon: Services.Icons.info

                                    SettingsRow {
                                        title: "Panel Model & Description"
                                        subtitle: (rootWindow.currentDisplayMon ? (rootWindow.currentDisplayMon.description || (rootWindow.currentDisplayMon.make + " " + rootWindow.currentDisplayMon.model) || rootWindow.currentDisplayMon.name) : "No Display Detected")

                                        Text {
                                            text: "Port: " + (rootWindow.currentDisplayMon ? rootWindow.currentDisplayMon.name : "-")
                                            font.family: Services.Theme.fontMono
                                            font.pixelSize: 11
                                            color: Services.Theme.textSecondary
                                        }
                                    }

                                    SettingsDivider {}

                                    SettingsRow {
                                        title: "Physical Dimensions & Workspace"
                                        subtitle: {
                                            if (!rootWindow.currentDisplayMon) return "-"
                                            var pw = rootWindow.currentDisplayMon.physicalWidth || 0
                                            var ph = rootWindow.currentDisplayMon.physicalHeight || 0
                                            var diag = Math.sqrt(pw * pw + ph * ph) / 25.4
                                            return pw + " mm × " + ph + " mm" + (diag > 0 ? (" (~" + diag.toFixed(1) + "″ diagonal)") : "")
                                        }

                                        Rectangle {
                                            height: 22
                                            implicitWidth: wsTxt.implicitWidth + 10
                                            radius: 4
                                            color: Services.Theme.bgElevated
                                            border.color: Services.Theme.border; border.width: 1
                                            Text {
                                                id: wsTxt; anchors.centerIn: parent
                                                text: "Workspace " + (rootWindow.currentDisplayMon ? rootWindow.currentDisplayMon.activeWorkspace : "1")
                                                font.pixelSize: 10; color: Services.Theme.accent
                                            }
                                        }
                                    }
                                }
                            }


                            // ── SUB-TAB 2: INPUT & TOUCHPAD GESTURES ───────────────
                            ColumnLayout {
                                visible: rootWindow.compSubTab === 2
                                Layout.fillWidth: true
                                spacing: 10

                                // Hyprland-only content
                                ColumnLayout {
                                    visible: Services.Compositor && Services.Compositor.activeCompositor === "hyprland"
                                    Layout.fillWidth: true
                                    spacing: 10

                                    SettingsSection {
                                        title: "Window Focus Behavior"
                                        icon: Services.Icons.sliders

                                        SettingsRow {
                                            title: "Focus Follows Mouse"
                                            subtitle: "How window focus is shifted when moving the cursor"

                                            SettingsDropdown {
                                                currentValue: Services.Compositor ? String(Services.Compositor.hyprFollowMouse) : "1"
                                                model: [
                                                    { id: "1", label: "Hover Focus (Continuous)" },
                                                    { id: "0", label: "Click to Focus (Strict)" },
                                                    { id: "2", label: "Click on Tiled, Hover on Floating" }
                                                ]
                                                onSelected: (val) => { if (Services.Compositor) Services.Compositor.setHyprFollowMouse(val) }
                                            }
                                        }
                                    }

                                    SettingsSection {
                                        title: "Touchpad & Gestures"
                                        icon: Services.Icons.touchpad || Services.Icons.sliders

                                        SettingsSwitch {
                                            title: "Natural Scrolling"
                                            subtitle: "Reverse scrolling direction (swipe up scrolls content up)"
                                            checked: Services.Compositor ? Services.Compositor.hyprTouchpadNatural : true
                                            onToggled: (val) => { if (Services.Compositor) Services.Compositor.setHyprTouchpadNatural(val) }
                                        }

                                        SettingsDivider {}

                                        SettingsSwitch {
                                            title: "Tap to Click"
                                            subtitle: "Tap touchpad surface to trigger primary click"
                                            checked: Services.Compositor ? Services.Compositor.hyprTouchpadTap : true
                                            onToggled: (val) => { if (Services.Compositor) Services.Compositor.setHyprTouchpadTap(val) }
                                        }

                                        SettingsDivider {}

                                        SettingsSwitch {
                                            title: "Disable While Typing (DWT)"
                                            subtitle: "Prevent accidental palm clicks when typing on the keyboard"
                                            checked: Services.Compositor ? Services.Compositor.hyprTouchpadDwt : true
                                            onToggled: (val) => { if (Services.Compositor) Services.Compositor.setHyprTouchpadDwt(val) }
                                        }

                                        SettingsDivider {}

                                        SettingsSwitch {
                                            title: "Touchpad 3-Finger Workspace Swipe"
                                            subtitle: "Smooth 1:1 trackpad swipe gesture to switch active workspace"
                                            checked: Services.Compositor ? Services.Compositor.hyprWorkspaceSwipe : true
                                            onToggled: (val) => { if (Services.Compositor) Services.Compositor.setHyprWorkspaceSwipe(val) }
                                        }

                                        SettingsDivider {}

                                        SettingsSlider {
                                            title: "Touchpad Pointer Sensitivity"
                                            from: -1.0; to: 1.0; stepSize: 0.05; decimals: 2
                                            value: Services.Compositor ? Services.Compositor.hyprSensitivity : 0.0
                                            onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprSensitivity(Number(v.toFixed(2))) }
                                        }
                                    }
                                }

                                // Non-Hyprland fallback card
                                Rectangle {
                                    visible: !(Services.Compositor && Services.Compositor.activeCompositor === "hyprland")
                                    Layout.fillWidth: true
                                    implicitHeight: noHyprInput.implicitHeight + 40
                                    radius: Services.Theme.radiusMd
                                    color: Services.Theme.surfaceVariant
                                    border.color: Services.Theme.border; border.width: 1

                                    ColumnLayout {
                                        id: noHyprInput
                                        anchors.centerIn: parent
                                        spacing: 8
                                        Text { Layout.alignment: Qt.AlignHCenter; text: Services.Icons.sliders; font.family: Services.Theme.fontSymbols; font.pixelSize: 24; color: Services.Theme.textDisabled }
                                        Text { Layout.alignment: Qt.AlignHCenter; text: "Input & gesture controls require Hyprland"; font.pixelSize: 12; font.weight: Font.Medium; color: Services.Theme.textSecondary }
                                        Text { Layout.alignment: Qt.AlignHCenter; text: "Detected compositor: " + (Services.Compositor ? Services.Compositor.activeDisplayName : "Unknown"); font.pixelSize: 10; color: Services.Theme.textDisabled }
                                    }
                                }
                            }

                            // ── SUB-TAB 3: POWER & GAMING ──────────────────────────
                            ColumnLayout {
                                visible: rootWindow.compSubTab === 3
                                Layout.fillWidth: true
                                spacing: 10

                                // Hyprland-only content
                                ColumnLayout {
                                    visible: Services.Compositor && Services.Compositor.activeCompositor === "hyprland"
                                    Layout.fillWidth: true
                                    spacing: 10

                                    SettingsSection {
                                        title: "Battery & Performance Optimizations"
                                        icon: Services.Icons.speed

                                        SettingsSwitch {
                                            title: "Variable Frame Rate (VFR)"
                                            subtitle: "Lower rendering refresh rate when the screen is static to conserve laptop battery"
                                            checked: Services.Compositor ? Services.Compositor.hyprVFR : true
                                            onToggled: () => { if (Services.Compositor) Services.Compositor.toggleHyprVFR() }
                                        }

                                        SettingsDivider {}

                                        SettingsSwitch {
                                            title: "Allow Screen Tearing (Gaming Low-Latency)"
                                            subtitle: "Enable direct scanout tearing for competitive games to reduce input lag"
                                            checked: Services.Compositor ? Services.Compositor.hyprAllowTearing : false
                                            onToggled: () => { if (Services.Compositor) Services.Compositor.toggleHyprTearing() }
                                        }

                                        SettingsDivider {}

                                        SettingsSwitch {
                                            title: "Resize Windows on Border"
                                            subtitle: "Allow dragging window borders directly to resize tiled windows"
                                            checked: Services.Compositor ? Services.Compositor.hyprResizeOnBorder : false
                                            onToggled: () => { if (Services.Compositor) Services.Compositor.toggleHyprResizeBorder() }
                                        }

                                        SettingsDivider {}

                                        SettingsSwitch {
                                            title: "Disable Hyprland Default Splash & Logo"
                                            subtitle: "Suppress anime mascot splash screen on session start"
                                            checked: Services.Compositor ? Services.Compositor.hyprDisableLogo : false
                                            onToggled: () => { if (Services.Compositor) Services.Compositor.toggleHyprDisableLogo() }
                                        }
                                    }
                                }

                                // Non-Hyprland fallback card
                                Rectangle {
                                    visible: !(Services.Compositor && Services.Compositor.activeCompositor === "hyprland")
                                    Layout.fillWidth: true
                                    implicitHeight: noHyprPower.implicitHeight + 40
                                    radius: Services.Theme.radiusMd
                                    color: Services.Theme.surfaceVariant
                                    border.color: Services.Theme.border; border.width: 1

                                    ColumnLayout {
                                        id: noHyprPower
                                        anchors.centerIn: parent
                                        spacing: 8
                                        Text { Layout.alignment: Qt.AlignHCenter; text: Services.Icons.speed; font.family: Services.Theme.fontSymbols; font.pixelSize: 24; color: Services.Theme.textDisabled }
                                        Text { Layout.alignment: Qt.AlignHCenter; text: "Power & gaming controls require Hyprland"; font.pixelSize: 12; font.weight: Font.Medium; color: Services.Theme.textSecondary }
                                        Text { Layout.alignment: Qt.AlignHCenter; text: "Detected compositor: " + (Services.Compositor ? Services.Compositor.activeDisplayName : "Unknown"); font.pixelSize: 10; color: Services.Theme.textDisabled }
                                    }
                                }
                            }

                            // ── SUB-TAB 4: AUTOSTART APPS & DAEMONS ─────────────────
                            ColumnLayout {
                                id: subTab4
                                visible: rootWindow.compSubTab === 4
                                Layout.fillWidth: true
                                spacing: 14

                                Component.onCompleted: {
                                    if (Services.Compositor) {
                                        Services.Compositor.loadAutostart()
                                    }
                                }

                                property string autostartSearchText: ""
                                property bool isAdding: false
                                property string newCmd: ""
                                property string newType: "exec-once" // "exec-once", "exec"
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
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    // Search input box
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 38
                                        implicitHeight: 38
                                        radius: Services.Theme.radiusSm || 8
                                        color: Services.Theme.surfaceVariant
                                        border.color: autoSearchInput.activeFocus ? Services.Theme.accent : Services.Theme.border
                                        border.width: autoSearchInput.activeFocus ? 1.5 : 1

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 10
                                            spacing: 8

                                            Text {
                                                text: Services.Icons.search || "󰍉"
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 12
                                                color: autoSearchInput.activeFocus ? Services.Theme.accent : Services.Theme.textDisabled
                                            }

                                            TextField {
                                                id: autoSearchInput
                                                Layout.fillWidth: true
                                                placeholderText: "Search startup programs, commands, daemons..."
                                                placeholderTextColor: Services.Theme.textDisabled
                                                text: subTab4.autostartSearchText
                                                onTextChanged: subTab4.autostartSearchText = text
                                                color: Services.Theme.textPrimary
                                                font.pixelSize: 12
                                                background: null
                                                verticalAlignment: TextInput.AlignVCenter
                                            }

                                            // Clear Button
                                            Rectangle {
                                                visible: autoSearchInput.text.length > 0
                                                width: 20
                                                height: 20
                                                radius: 10
                                                color: autoClearMouse.containsMouse ? Qt.rgba(1,1,1,0.15) : "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "✕"
                                                    font.pixelSize: 9
                                                    color: Services.Theme.textSecondary
                                                }
                                                MouseArea {
                                                    id: autoClearMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: autoSearchInput.text = ""
                                                }
                                            }
                                        }
                                    }

                                    // Quick Stats Pill
                                    Rectangle {
                                        Layout.preferredHeight: 38
                                        implicitHeight: 38
                                        implicitWidth: autoStatsRow.implicitWidth + 24
                                        radius: Services.Theme.radiusSm || 8
                                        color: Services.Theme.surfaceVariant
                                        border.color: Services.Theme.border
                                        border.width: 1

                                        RowLayout {
                                            id: autoStatsRow
                                            anchors.centerIn: parent
                                            spacing: 6
                                            Rectangle {
                                                width: 7; height: 7; radius: 3.5
                                                color: "#10b981"
                                                SequentialAnimation on opacity {
                                                    running: true; loops: Animation.Infinite
                                                    NumberAnimation { to: 0.3; duration: 900; easing.type: Easing.InOutSine }
                                                    NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
                                                }
                                            }
                                            Text {
                                                text: {
                                                    const list = (Services.Compositor && Services.Compositor.autostartList) ? Services.Compositor.autostartList : []
                                                    const enabledCount = list.filter(i => i.enabled).length
                                                    return enabledCount + " Active / " + list.length + " Total"
                                                }
                                                font.pixelSize: 11
                                                font.weight: Font.Medium
                                                color: Services.Theme.textPrimary
                                            }
                                        }
                                    }

                                    // Add Program Button (Hero Accent)
                                    Rectangle {
                                        Layout.preferredHeight: 38
                                        implicitHeight: 38
                                        implicitWidth: autoAddRow.implicitWidth + 24
                                        radius: Services.Theme.radiusSm || 8
                                        color: autoAddMouse.containsMouse ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.28) : Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.16)
                                        border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.50)
                                        border.width: 1
                                        scale: autoAddMouse.pressed ? 0.96 : (autoAddMouse.containsMouse ? 1.02 : 1.0)
                                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
                                        Behavior on color { ColorAnimation { duration: 150 } }

                                        RowLayout {
                                            id: autoAddRow
                                            anchors.centerIn: parent
                                            spacing: 6
                                            Text {
                                                text: subTab4.isAdding ? "✕" : (Services.Icons.plus || "+")
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 12
                                                color: Services.Theme.accent
                                            }
                                            Text {
                                                text: subTab4.isAdding ? "Cancel" : "Add Startup"
                                                font.pixelSize: 11
                                                font.weight: Font.Bold
                                                color: Services.Theme.accent
                                            }
                                        }
                                        MouseArea {
                                            id: autoAddMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                subTab4.isAdding = !subTab4.isAdding
                                                if (subTab4.isAdding) {
                                                    subTab4.newCmd = ""
                                                    subTab4.selectedPreset = ""
                                                }
                                            }
                                        }
                                    }

                                    // Refresh Button
                                    Rectangle {
                                        Layout.preferredHeight: 38
                                        Layout.preferredWidth: 38
                                        implicitHeight: 38
                                        implicitWidth: 38
                                        radius: Services.Theme.radiusSm || 8
                                        color: autoRfMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Services.Theme.surfaceVariant
                                        border.color: Services.Theme.border
                                        border.width: 1
                                        scale: autoRfMouse.pressed ? 0.94 : (autoRfMouse.containsMouse ? 1.04 : 1.0)
                                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: Services.Icons.refresh || "󰑐"
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 14
                                            color: Services.Theme.textPrimary

                                            NumberAnimation on rotation {
                                                id: autoSpinAnim
                                                running: Services.Compositor && Services.Compositor.isLoadingAutostart
                                                loops: Animation.Infinite
                                                from: 0; to: 360; duration: 800
                                            }
                                        }

                                        MouseArea {
                                            id: autoRfMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (Services.Compositor) Services.Compositor.loadAutostart()
                                            }
                                        }
                                    }
                                }

                                // ── Add Custom Program Form (Expandable Glass Card) ──
                                Rectangle {
                                    visible: subTab4.isAdding
                                    Layout.fillWidth: true
                                    implicitHeight: autoAddFormCol.implicitHeight + 28
                                    radius: Services.Theme.radiusMd || 12
                                    color: Services.Theme.surfaceVariant
                                    border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.40)
                                    border.width: 1.2

                                    ColumnLayout {
                                        id: autoAddFormCol
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 12

                                        // Form Header
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8
                                            Rectangle {
                                                Layout.preferredWidth: 28; Layout.preferredHeight: 28
                                                implicitWidth: 28; implicitHeight: 28
                                                radius: 7
                                                color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.20)
                                                Text { anchors.centerIn: parent; text: "󰐥"; font.family: Services.Theme.fontSymbols; font.pixelSize: 14; color: Services.Theme.accent }
                                            }
                                            ColumnLayout {
                                                spacing: 2
                                                Text { text: "Add New Startup Application / Daemon"; font.pixelSize: 12; font.weight: Font.Bold; color: Services.Theme.textPrimary }
                                                Text { text: "Pick a popular preset below or type any command to run automatically on session boot"; font.pixelSize: 10; color: Services.Theme.textSecondary }
                                            }
                                        }

                                        // Quick Presets Chip Bar
                                        Text { text: "POPULAR PRESETS"; font.pixelSize: 9; font.weight: Font.Bold; color: Services.Theme.accent; font.letterSpacing: 0.5 }

                                        GridLayout {
                                            Layout.fillWidth: true
                                            columns: subTab4.width > 600 ? 4 : 2
                                            columnSpacing: 6
                                            rowSpacing: 6

                                            Repeater {
                                                model: subTab4.recommendedPresets

                                                delegate: Rectangle {
                                                    required property var modelData
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 28
                                                    implicitHeight: 28
                                                    radius: 6
                                                    readonly property bool isSel: subTab4.selectedPreset === modelData.id
                                                    color: isSel ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.25) : (autoPresetMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Services.Theme.bgElevated)
                                                    border.color: isSel ? Services.Theme.accent : Services.Theme.border
                                                    border.width: 1
                                                    Behavior on color { ColorAnimation { duration: 150 } }

                                                    RowLayout {
                                                        anchors.centerIn: parent
                                                        spacing: 5
                                                        Text { text: modelData.icon; font.family: Services.Theme.fontSymbols; font.pixelSize: 11; color: isSel ? Services.Theme.accent : Services.Theme.textSecondary }
                                                        Text { text: modelData.name; font.pixelSize: 10; font.weight: isSel ? Font.Bold : Font.Medium; color: isSel ? Services.Theme.accent : Services.Theme.textPrimary; elide: Text.ElideRight }
                                                    }

                                                    MouseArea {
                                                        id: autoPresetMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            subTab4.selectedPreset = modelData.id
                                                            subTab4.newCmd = modelData.cmd
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // Command Input Row
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 4
                                            Text { text: "EXECUTION COMMAND"; font.pixelSize: 9; font.weight: Font.Bold; color: Services.Theme.textSecondary; font.letterSpacing: 0.5 }

                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 38
                                                implicitHeight: 38
                                                radius: Services.Theme.radiusSm || 8
                                                color: Services.Theme.bgElevated
                                                border.color: autoCmdInputField.activeFocus ? Services.Theme.accent : Services.Theme.border
                                                border.width: 1

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 12
                                                    anchors.rightMargin: 10
                                                    spacing: 8

                                                    Text { text: "󰅍"; font.family: Services.Theme.fontSymbols; font.pixelSize: 12; color: Services.Theme.textDisabled }

                                                    TextField {
                                                        id: autoCmdInputField
                                                        Layout.fillWidth: true
                                                        placeholderText: "e.g. wl-paste --type text --watch cliphist store, spotify, vesktop"
                                                        placeholderTextColor: Services.Theme.textDisabled
                                                        text: subTab4.newCmd
                                                        onTextChanged: subTab4.newCmd = text
                                                        color: Services.Theme.textPrimary
                                                        font.family: Services.Theme.fontMono || "Monospace"
                                                        font.pixelSize: 11
                                                        background: null
                                                        verticalAlignment: TextInput.AlignVCenter
                                                    }
                                                }
                                            }
                                        }

                                        // Options Row (Type & Buttons)
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 12

                                            // Startup Type (exec-once vs exec)
                                            RowLayout {
                                                spacing: 6
                                                Text { text: "Mode:"; font.pixelSize: 10; color: Services.Theme.textSecondary }

                                                Rectangle {
                                                    Layout.preferredHeight: 26
                                                    implicitHeight: 26
                                                    implicitWidth: autoTypeRow1.implicitWidth + 14
                                                    radius: 5
                                                    color: subTab4.newType === "exec-once" ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.22) : Services.Theme.bgElevated
                                                    border.color: subTab4.newType === "exec-once" ? Services.Theme.accent : Services.Theme.border
                                                    border.width: 1
                                                    RowLayout {
                                                        id: autoTypeRow1
                                                        anchors.centerIn: parent; spacing: 4
                                                        Text { text: "exec-once (Boot only)"; font.pixelSize: 9; font.weight: subTab4.newType === "exec-once" ? Font.Bold : Font.Normal; color: subTab4.newType === "exec-once" ? Services.Theme.accent : Services.Theme.textSecondary }
                                                    }
                                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: subTab4.newType = "exec-once" }
                                                }

                                                Rectangle {
                                                    Layout.preferredHeight: 26
                                                    implicitHeight: 26
                                                    implicitWidth: autoTypeRow2.implicitWidth + 14
                                                    radius: 5
                                                    color: subTab4.newType === "exec" ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.22) : Services.Theme.bgElevated
                                                    border.color: subTab4.newType === "exec" ? Services.Theme.accent : Services.Theme.border
                                                    border.width: 1
                                                    RowLayout {
                                                        id: autoTypeRow2
                                                        anchors.centerIn: parent; spacing: 4
                                                        Text { text: "exec (Every reload)"; font.pixelSize: 9; font.weight: subTab4.newType === "exec" ? Font.Bold : Font.Normal; color: subTab4.newType === "exec" ? Services.Theme.accent : Services.Theme.textSecondary }
                                                    }
                                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: subTab4.newType = "exec" }
                                                }
                                            }

                                            Item { Layout.fillWidth: true }

                                            // Save / Add Action Button
                                            Rectangle {
                                                Layout.preferredHeight: 32
                                                implicitHeight: 32
                                                implicitWidth: autoSaveBtnRow.implicitWidth + 20
                                                radius: 6
                                                color: subTab4.newCmd.trim().length > 0 ? Services.Theme.accent : Qt.rgba(1, 1, 1, 0.10)
                                                scale: autoSaveBtnMouse.pressed ? 0.96 : (autoSaveBtnMouse.containsMouse ? 1.02 : 1.0)
                                                Behavior on scale { NumberAnimation { duration: 150 } }

                                                RowLayout {
                                                    id: autoSaveBtnRow
                                                    anchors.centerIn: parent
                                                    spacing: 6
                                                    Text { text: "󰄬"; font.family: Services.Theme.fontSymbols; font.pixelSize: 11; color: subTab4.newCmd.trim().length > 0 ? Services.Theme.bgPure : Services.Theme.textDisabled }
                                                    Text { text: "Add to Autostart"; font.pixelSize: 10; font.weight: Font.Bold; color: subTab4.newCmd.trim().length > 0 ? Services.Theme.bgPure : Services.Theme.textDisabled }
                                                }

                                                MouseArea {
                                                    id: autoSaveBtnMouse
                                                    anchors.fill: parent
                                                    enabled: subTab4.newCmd.trim().length > 0
                                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                    onClicked: {
                                                        if (Services.Compositor && subTab4.newCmd.trim().length > 0) {
                                                            Services.Compositor.addAutostart(subTab4.newCmd.trim(), subTab4.newType)
                                                            subTab4.isAdding = false
                                                            subTab4.newCmd = ""
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // ── Recommended Essential Daemons Section (1-Click Status) ──
                                SettingsSection {
                                    title: "Essential Desktop Daemons"
                                    icon: Services.Icons.sparkles || "󰏘"

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Text {
                                            text: "Status of core desktop services. Click '+ Add' on any missing daemon to configure it in startup immediately."
                                            font.pixelSize: 10
                                            color: Services.Theme.textSecondary
                                            Layout.leftMargin: 4
                                        }

                                        GridLayout {
                                            Layout.fillWidth: true
                                            columns: subTab4.width > 620 ? 2 : 1
                                            columnSpacing: 8
                                            rowSpacing: 8

                                            Repeater {
                                                model: [
                                                    { id: "cliphist-text", name: "Clipboard Text", desc: "wl-paste text cliphist watcher", icon: "󰅍", cmd: "wl-paste --type text --watch cliphist store" },
                                                    { id: "cliphist-img",  name: "Clipboard Images", desc: "wl-paste screenshot & image watcher", icon: "󰄄", cmd: "wl-paste --type image --watch cliphist store" },
                                                    { id: "polkit",        name: "Polkit Agent",   desc: "hyprpolkitagent system auth", icon: "󰌋", cmd: "systemctl enable --now --user hyprpolkitagent" },
                                                    { id: "wallpaper",     name: "Wallpaper Engine", desc: "awww / swaybg background", icon: "󰸉", cmd: "awww-daemon" },
                                                    { id: "hypridle",      name: "Hypridle Daemon", desc: "idle & lock timeout manager", icon: "󰒲", cmd: "hypridle" },
                                                    { id: "nm-applet",     name: "Network Applet", desc: "nm-applet tray indicator", icon: "󰤨", cmd: "nm-applet --indicator" },
                                                    { id: "blueman",       name: "Bluetooth Applet", desc: "blueman-applet tray manager", icon: "󰂯", cmd: "blueman-applet" }
                                                ]

                                                delegate: Rectangle {
                                                    required property var modelData
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 52
                                                    implicitHeight: 52
                                                    radius: 8
                                                    readonly property bool isConf: subTab4.isPresetConfigured(modelData.cmd)
                                                    color: Services.Theme.isDark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03)
                                                    border.color: isConf ? Qt.rgba(16/255, 185/255, 129/255, 0.40) : Services.Theme.border
                                                    border.width: 1

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.margins: 8
                                                        spacing: 8

                                                        // Squircle Icon
                                                        Rectangle {
                                                            Layout.preferredWidth: 34
                                                            Layout.preferredHeight: 34
                                                            implicitWidth: 34
                                                            implicitHeight: 34
                                                            radius: 8
                                                            color: isConf ? Qt.rgba(16/255, 185/255, 129/255, 0.15) : Qt.rgba(1, 1, 1, 0.06)
                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: modelData.icon
                                                                font.family: Services.Theme.fontSymbols
                                                                font.pixelSize: 15
                                                                color: isConf ? "#10b981" : Services.Theme.textSecondary
                                                            }
                                                        }

                                                        ColumnLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 1
                                                            Text { text: modelData.name; font.pixelSize: 11; font.weight: Font.Bold; color: Services.Theme.textPrimary; elide: Text.ElideRight }
                                                            Text { text: modelData.desc; font.pixelSize: 9; color: Services.Theme.textSecondary; elide: Text.ElideRight }
                                                        }

                                                        // Status / Add Action
                                                        Rectangle {
                                                            Layout.preferredHeight: 24
                                                            implicitHeight: 24
                                                            implicitWidth: autoStatusRow.implicitWidth + 12
                                                            radius: 4
                                                            color: isConf ? Qt.rgba(16/255, 185/255, 129/255, 0.15) : Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15)
                                                            border.color: isConf ? Qt.rgba(16/255, 185/255, 129/255, 0.35) : Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.40)
                                                            border.width: 1

                                                            RowLayout {
                                                                id: autoStatusRow
                                                                anchors.centerIn: parent; spacing: 3
                                                                Text {
                                                                    text: isConf ? "󰄬" : "+"
                                                                    font.family: Services.Theme.fontSymbols; font.pixelSize: 9
                                                                    color: isConf ? "#10b981" : Services.Theme.accent
                                                                }
                                                                Text {
                                                                    text: isConf ? "Configured" : "Add"
                                                                    font.pixelSize: 9; font.weight: Font.Bold
                                                                    color: isConf ? "#10b981" : Services.Theme.accent
                                                                }
                                                            }

                                                            MouseArea {
                                                                anchors.fill: parent
                                                                enabled: !isConf
                                                                cursorShape: !isConf ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                                onClicked: {
                                                                    if (Services.Compositor) {
                                                                        Services.Compositor.addAutostart(modelData.cmd, "exec-once")
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // ── Active Configured Startup Programs List ───────────
                                SettingsSection {
                                    title: "Configured Startup Applications"
                                    icon: Services.Icons.rocket || "󰐥"

                                    ColumnLayout {
                                        id: autostartListCol
                                        Layout.fillWidth: true
                                        spacing: 8

                                        // Filtered autostart list
                                        readonly property var filteredList: {
                                            const list = (Services.Compositor && Services.Compositor.autostartList) ? Services.Compositor.autostartList : []
                                            const q = subTab4.autostartSearchText.toLowerCase().trim()
                                            if (!q) return list
                                            return list.filter(item => {
                                                return (item.name && item.name.toLowerCase().includes(q)) ||
                                                       (item.command && item.command.toLowerCase().includes(q)) ||
                                                       (item.desc && item.desc.toLowerCase().includes(q)) ||
                                                       (item.fileName && item.fileName.toLowerCase().includes(q))
                                            })
                                        }

                                        // Empty State Card
                                        Rectangle {
                                            visible: (autostartListCol.filteredList || []).length === 0
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 110
                                            implicitHeight: 110
                                            radius: 8
                                            color: Services.Theme.isDark ? Qt.rgba(1, 1, 1, 0.03) : Qt.rgba(0, 0, 0, 0.02)
                                            border.color: Services.Theme.border
                                            border.width: 1

                                            ColumnLayout {
                                                anchors.centerIn: parent
                                                spacing: 6
                                                Text { Layout.alignment: Qt.AlignHCenter; text: "󰐥"; font.family: Services.Theme.fontSymbols; font.pixelSize: 24; color: Services.Theme.textDisabled }
                                                Text { Layout.alignment: Qt.AlignHCenter; text: subTab4.autostartSearchText.length > 0 ? "No startup programs matching your search" : "No autostart programs found in compositor config"; font.pixelSize: 11; font.weight: Font.Medium; color: Services.Theme.textSecondary }
                                                Text { Layout.alignment: Qt.AlignHCenter; text: "Click '+ Add Startup' above to configure a startup program"; font.pixelSize: 9; color: Services.Theme.textDisabled }
                                            }
                                        }

                                        // Startup Program Cards
                                        Repeater {
                                            model: autostartListCol.filteredList

                                            delegate: Rectangle {
                                                id: autoItemCard
                                                required property var modelData
                                                required property int index

                                                Layout.fillWidth: true
                                                Layout.preferredHeight: autoItemCardRow.implicitHeight + 18
                                                implicitHeight: autoItemCardRow.implicitHeight + 18
                                                radius: 8
                                                color: modelData.enabled ? (Services.Theme.isDark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03)) : (Services.Theme.isDark ? Qt.rgba(1, 1, 1, 0.015) : Qt.rgba(0, 0, 0, 0.015))
                                                border.color: modelData.enabled ? Services.Theme.border : Qt.rgba(Services.Theme.border.r, Services.Theme.border.g, Services.Theme.border.b, 0.40)
                                                border.width: 1
                                                opacity: modelData.enabled ? 1.0 : 0.65
                                                Behavior on opacity { NumberAnimation { duration: 200 } }

                                                RowLayout {
                                                    id: autoItemCardRow
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 12
                                                    anchors.rightMargin: 12
                                                    anchors.topMargin: 9
                                                    anchors.bottomMargin: 9
                                                    spacing: 12

                                                    // Program Squircle Icon
                                                    Rectangle {
                                                        Layout.preferredWidth: 38
                                                        Layout.preferredHeight: 38
                                                        implicitWidth: 38
                                                        implicitHeight: 38
                                                        radius: 9
                                                        color: {
                                                            if (!modelData.enabled) return Qt.rgba(1, 1, 1, 0.05)
                                                            const cat = (modelData.category || "").toLowerCase()
                                                            if (cat === "system") return Qt.rgba(59/255, 130/255, 246/255, 0.18)
                                                            if (cat === "service") return Qt.rgba(16/255, 185/255, 129/255, 0.18)
                                                            if (cat === "shell") return Qt.rgba(139/255, 92/255, 246/255, 0.18)
                                                            if (cat === "power") return Qt.rgba(239/255, 68/255, 68/255, 0.18)
                                                            if (cat === "network") return Qt.rgba(6/255, 182/255, 212/255, 0.18)
                                                            if (cat === "bluetooth") return Qt.rgba(14/255, 165/255, 233/255, 0.18)
                                                            return Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.18)
                                                        }
                                                        border.color: modelData.enabled ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.35) : Services.Theme.border
                                                        border.width: 1

                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: modelData.icon || "󰐥"
                                                            font.family: Services.Theme.fontSymbols
                                                            font.pixelSize: 17
                                                            color: modelData.enabled ? Services.Theme.accent : Services.Theme.textDisabled
                                                        }
                                                    }

                                                    // Details Column
                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        Layout.minimumWidth: 0
                                                        spacing: 3

                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 6

                                                            Text {
                                                                text: modelData.name
                                                                font.pixelSize: 12
                                                                font.weight: Font.Bold
                                                                color: modelData.enabled ? Services.Theme.textPrimary : Services.Theme.textSecondary
                                                                elide: Text.ElideRight
                                                            }

                                                            // Type Badge (exec-once)
                                                            Rectangle {
                                                                Layout.preferredHeight: 16
                                                                implicitHeight: 16
                                                                implicitWidth: autoTypeTxt.implicitWidth + 8
                                                                radius: 3
                                                                color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.12)
                                                                Text { id: autoTypeTxt; anchors.centerIn: parent; text: modelData.type || "exec-once"; font.pixelSize: 8; font.weight: Font.Bold; color: Services.Theme.accent }
                                                            }

                                                            // File Source Pill
                                                            Rectangle {
                                                                Layout.preferredHeight: 16
                                                                implicitHeight: 16
                                                                implicitWidth: autoFileTxt.implicitWidth + 8
                                                                radius: 3
                                                                color: Qt.rgba(1, 1, 1, 0.06)
                                                                Text { id: autoFileTxt; anchors.centerIn: parent; text: (modelData.fileName || "config") + ":" + (modelData.line || ""); font.pixelSize: 8; color: Services.Theme.textDisabled }
                                                            }
                                                        }

                                                        // Monospaced Command Pill
                                                        Rectangle {
                                                            Layout.fillWidth: true
                                                            Layout.preferredHeight: 22
                                                            implicitHeight: 22
                                                            radius: 4
                                                            color: Services.Theme.bgElevated
                                                            border.color: Services.Theme.border
                                                            border.width: 1
                                                            clip: true

                                                            RowLayout {
                                                                anchors.fill: parent
                                                                anchors.leftMargin: 6
                                                                anchors.rightMargin: 6
                                                                spacing: 4
                                                                Text { text: "$"; font.pixelSize: 9; font.weight: Font.Bold; color: Services.Theme.accent }
                                                                Text {
                                                                    Layout.fillWidth: true
                                                                    text: modelData.command
                                                                    font.family: Services.Theme.fontMono || "Monospace"
                                                                    font.pixelSize: 10
                                                                    color: modelData.enabled ? Services.Theme.textPrimary : Services.Theme.textDisabled
                                                                    elide: Text.ElideRight
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // Action Controls Group
                                                    RowLayout {
                                                        spacing: 8
                                                        Layout.alignment: Qt.AlignVCenter

                                                        // Run Now Button
                                                        Rectangle {
                                                            Layout.preferredHeight: 28
                                                            implicitHeight: 28
                                                            implicitWidth: autoRunRow.implicitWidth + 14
                                                            radius: 5
                                                            color: autoRunMouse.containsMouse ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.25) : Qt.rgba(1, 1, 1, 0.06)
                                                            border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.35)
                                                            border.width: 1
                                                            scale: autoRunMouse.pressed ? 0.94 : (autoRunMouse.containsMouse ? 1.04 : 1.0)
                                                            Behavior on scale { NumberAnimation { duration: 120 } }

                                                            RowLayout {
                                                                id: autoRunRow
                                                                anchors.centerIn: parent; spacing: 4
                                                                Text { text: "▶"; font.pixelSize: 8; color: Services.Theme.accent }
                                                                Text { text: "Run"; font.pixelSize: 9; font.weight: Font.Bold; color: Services.Theme.accent }
                                                            }

                                                            MouseArea {
                                                                id: autoRunMouse
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: {
                                                                    if (Services.Compositor) {
                                                                        Services.Compositor.runAutostart(modelData.command)
                                                                    }
                                                                }
                                                            }
                                                        }

                                                        // Enable / Disable Switch Toggle
                                                        Rectangle {
                                                            Layout.preferredWidth: 36
                                                            Layout.preferredHeight: 20
                                                            implicitWidth: 36
                                                            implicitHeight: 20
                                                            radius: 10
                                                            color: modelData.enabled ? Services.Theme.accent : Qt.rgba(1, 1, 1, 0.15)
                                                            Behavior on color { ColorAnimation { duration: 180 } }

                                                            Rectangle {
                                                                width: 14
                                                                height: 14
                                                                radius: 7
                                                                color: "#ffffff"
                                                                y: 3
                                                                x: modelData.enabled ? 19 : 3
                                                                Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                                                            }

                                                            MouseArea {
                                                                anchors.fill: parent
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: {
                                                                    if (Services.Compositor) {
                                                                        Services.Compositor.toggleAutostart(modelData.file, modelData.line, !modelData.enabled)
                                                                    }
                                                                }
                                                            }
                                                        }

                                                        // Delete Button
                                                        Rectangle {
                                                            Layout.preferredWidth: 28
                                                            Layout.preferredHeight: 28
                                                            implicitWidth: 28
                                                            implicitHeight: 28
                                                            radius: 6
                                                            color: autoDelMouse.containsMouse ? Qt.rgba(239/255, 68/255, 68/255, 0.22) : "transparent"
                                                            border.color: autoDelMouse.containsMouse ? Qt.rgba(239/255, 68/255, 68/255, 0.50) : "transparent"
                                                            border.width: 1
                                                            Behavior on color { ColorAnimation { duration: 150 } }

                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: Services.Icons.trash || "󰆴"
                                                                font.family: Services.Theme.fontSymbols
                                                                font.pixelSize: 12
                                                                color: autoDelMouse.containsMouse ? "#ef4444" : Services.Theme.textDisabled
                                                            }

                                                            MouseArea {
                                                                id: autoDelMouse
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: {
                                                                    if (Services.Compositor) {
                                                                        Services.Compositor.deleteAutostart(modelData.file, modelData.line)
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ═════════════════════════════════════════════
                        // TAB 6: KEYBINDINGS (LIVE FROM COMPOSITOR CONFIG)
                        // ═════════════════════════════════════════════
                        ColumnLayout {
                            id: tab6
                            Layout.fillWidth: true
                            spacing: 14

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

                            // ── Top Header Row ──────────────────────────────────
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    RowLayout {
                                        spacing: 8
                                        Text {
                                            text: "Compositor Keybindings"
                                            font.pixelSize: Services.Theme.fontSizeLg
                                            font.weight: Font.Bold
                                            color: Services.Theme.textPrimary
                                        }

                                        // Total Count Badge
                                        Rectangle {
                                            radius: 10
                                            implicitHeight: 20
                                            implicitWidth: kb_totalTxt.implicitWidth + 12
                                            color: Services.Theme.isDark ? "#26262e" : "#e5e7eb"
                                            Text {
                                                id: kb_totalTxt
                                                anchors.centerIn: parent
                                                text: tab6.totalBindsCount + " Binds"
                                                font.pixelSize: 10
                                                font.weight: Font.DemiBold
                                                color: Services.Theme.textSecondary
                                            }
                                        }
                                    }

                                    Text {
                                        text: "Manage active keyboard and mouse shortcuts directly in your compositor configuration"
                                        font.pixelSize: Services.Theme.fontSizeSm
                                        color: Services.Theme.textSecondary
                                    }
                                }

                                // "+ New Shortcut" Button
                                Rectangle {
                                    implicitHeight: 36
                                    implicitWidth: kb_addBtnRow.implicitWidth + 24
                                    radius: 8
                                    color: (rootWindow.isAddingKeybind || rootWindow.editingBindLine > 0)
                                        ? (Services.Theme.isDark ? "#2a2a34" : "#e2e8f0")
                                        : Services.Theme.accent
                                    border.color: (rootWindow.isAddingKeybind || rootWindow.editingBindLine > 0)
                                        ? Services.Theme.border : "transparent"
                                    border.width: 1

                                    RowLayout {
                                        id: kb_addBtnRow
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Text {
                                            text: (rootWindow.isAddingKeybind || rootWindow.editingBindLine > 0) ? "✕" : "+"
                                            font.pixelSize: 13
                                            font.bold: true
                                            color: (rootWindow.isAddingKeybind || rootWindow.editingBindLine > 0)
                                                ? Services.Theme.textPrimary
                                                : Services.Theme.bgOnAccent
                                        }
                                        Text {
                                            text: (rootWindow.isAddingKeybind || rootWindow.editingBindLine > 0) ? "Close Studio" : "Add Keybind"
                                            font.pixelSize: Services.Theme.fontSizeSm
                                            font.weight: Font.DemiBold
                                            color: (rootWindow.isAddingKeybind || rootWindow.editingBindLine > 0)
                                                ? Services.Theme.textPrimary
                                                : Services.Theme.bgOnAccent
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        hoverEnabled: true
                                        onClicked: {
                                            if (rootWindow.isAddingKeybind || rootWindow.editingBindLine > 0) {
                                                rootWindow.isAddingKeybind = false
                                                rootWindow.editingBindId = ""
                                                rootWindow.editingBindLine = -1
                                                rootWindow.formKeys = ""
                                                rootWindow.formAction = ""
                                                rootWindow.formDesc = ""
                                            } else {
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
                                        }
                                    }
                                }
                            }

                            // ── Status / Feedback Notification Banner ────────────
                            Rectangle {
                                visible: (Services.Compositor && (Services.Compositor.keybindStatus.length > 0 || Services.Compositor.keybindError.length > 0))
                                Layout.fillWidth: true
                                implicitHeight: kb_notifRow.implicitHeight + 16
                                radius: 8
                                color: (Services.Compositor && Services.Compositor.keybindError.length > 0)
                                    ? (Services.Theme.isDark ? "#3f1414" : "#fef2f2")
                                    : (Services.Theme.isDark ? "#143324" : "#f0fdf4")
                                border.color: (Services.Compositor && Services.Compositor.keybindError.length > 0)
                                    ? "#ef4444" : "#10b981"
                                border.width: 1

                                RowLayout {
                                    id: kb_notifRow
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 8

                                    Text {
                                        text: (Services.Compositor && Services.Compositor.keybindError.length > 0) ? "󰅚" : "󰄬"
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: 13
                                        color: (Services.Compositor && Services.Compositor.keybindError.length > 0) ? "#ef4444" : "#10b981"
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: (Services.Compositor && Services.Compositor.keybindError.length > 0)
                                            ? Services.Compositor.keybindError
                                            : (Services.Compositor ? Services.Compositor.keybindStatus : "")
                                        font.pixelSize: Services.Theme.fontSizeSm
                                        color: Services.Theme.textPrimary
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        text: "✕"
                                        font.pixelSize: 11
                                        color: Services.Theme.textSecondary
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (Services.Compositor) {
                                                    Services.Compositor.keybindStatus = ""
                                                    Services.Compositor.keybindError = ""
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ═════════════════════════════════════════════════
                            // ── KEYBIND STUDIO CARD (Clean, Simple Flat, Fun) ──
                            // ═════════════════════════════════════════════════
                            Rectangle {
                                id: kb_studioCard
                                visible: rootWindow.isAddingKeybind || rootWindow.editingBindLine > 0
                                Layout.fillWidth: true
                                implicitHeight: kb_studioContent.implicitHeight + 24
                                radius: 12
                                color: Services.Theme.isDark ? "#1a1a20" : "#ffffff"
                                border.color: (rootWindow.editingBindLine > 0) ? Services.Theme.accent : (Services.Theme.isDark ? "#2a2a36" : "#e2e8f0")
                                border.width: 1

                                ColumnLayout {
                                    id: kb_studioContent
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 14
                                    spacing: 12

                                    // Studio Header
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Text {
                                            text: rootWindow.editingBindLine > 0 ? "󰏫" : "󰐕"
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 14
                                            color: Services.Theme.accent
                                        }

                                        Text {
                                            text: rootWindow.editingBindLine > 0 ? ("Edit Keybind (Line " + rootWindow.editingBindLine + ")") : "Create New Keybind"
                                            font.pixelSize: Services.Theme.fontSizeMd
                                            font.weight: Font.Bold
                                            color: Services.Theme.textPrimary
                                        }

                                        Item { Layout.fillWidth: true }

                                        // Cancel Studio
                                        Text {
                                            text: "Cancel"
                                            font.pixelSize: Services.Theme.fontSizeXs
                                            font.weight: Font.Medium
                                            color: Services.Theme.textSecondary
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    rootWindow.isAddingKeybind = false
                                                    rootWindow.editingBindId = ""
                                                    rootWindow.editingBindLine = -1
                                                    rootWindow.formKeys = ""
                                                    rootWindow.formAction = ""
                                                    rootWindow.formDesc = ""
                                                }
                                            }
                                        }
                                    }

                                    // Studio Divider
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 1
                                        color: Services.Theme.isDark ? "#252530" : "#f1f5f9"
                                    }

                                    // ── Section 1: Shortcut Keys Combination ────
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        RowLayout {
                                            id: conflictHeaderRow
                                            spacing: 6
                                            readonly property var conflictItem: tab6.checkConflict(rootWindow.formKeys)

                                            Text {
                                                text: "KEY COMBINATION"
                                                font.pixelSize: 10
                                                font.weight: Font.Bold
                                                font.letterSpacing: 0.6
                                                color: Services.Theme.textSecondary
                                            }

                                            // Conflict Warning Badge
                                            Rectangle {
                                                visible: conflictHeaderRow.conflictItem !== null
                                                radius: 4
                                                implicitHeight: 18
                                                implicitWidth: kb_confTxt.implicitWidth + 10
                                                color: Services.Theme.isDark ? "#451a03" : "#fef3c7"
                                                border.color: "#f59e0b"; border.width: 1
                                                Text {
                                                    id: kb_confTxt
                                                    anchors.centerIn: parent
                                                    text: "󰀦 Already in use: " + (conflictHeaderRow.conflictItem ? tab6.getHumanActionTitle(conflictHeaderRow.conflictItem.action) : "")
                                                    font.pixelSize: 9
                                                    font.bold: true
                                                    color: "#f59e0b"
                                                }
                                            }
                                        }

                                        // Key Recorder + Clear Button
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            KeyRecorder {
                                                id: kb_addKeyRec
                                                Layout.fillWidth: true
                                                height: 36
                                                compact: false
                                                value: rootWindow.formKeys
                                                placeholder: "Click here and press key combo on your keyboard..."
                                                onRecorded: (k) => { rootWindow.formKeys = k }
                                                onCleared: { rootWindow.formKeys = "" }
                                            }

                                            Rectangle {
                                                visible: (rootWindow.formKeys || "").length > 0
                                                height: 36; width: 36; radius: 6
                                                color: kb_clrRecMouse.containsMouse ? (Services.Theme.isDark ? "#282832" : "#e2e8f0") : (Services.Theme.isDark ? "#202026" : "#f1f5f9")
                                                border.color: Services.Theme.border; border.width: 1
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "󰩹"
                                                    font.family: Services.Theme.fontSymbols
                                                    font.pixelSize: 13
                                                    color: Services.Theme.textSecondary
                                                }
                                                MouseArea {
                                                    id: kb_clrRecMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: rootWindow.formKeys = ""
                                                }
                                            }
                                        }

                                        // Quick Modifiers (Click to toggle)
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            Text {
                                                text: "Modifiers:"
                                                font.pixelSize: 10
                                                color: Services.Theme.textSecondary
                                                Layout.alignment: Qt.AlignVCenter
                                            }

                                            Repeater {
                                                model: ["SUPER", "CTRL", "ALT", "SHIFT"]
                                                delegate: Rectangle {
                                                    id: kb_modBtn
                                                    readonly property bool isActive: (rootWindow.formKeys || "").toUpperCase().split("+").map(s => s.trim()).includes(modelData)
                                                    implicitHeight: 24
                                                    implicitWidth: kb_modLabel.implicitWidth + 14
                                                    radius: 5
                                                    color: isActive ? Services.Theme.accent : (kb_modBtnMouse.containsMouse ? (Services.Theme.isDark ? "#2a2a34" : "#e5e7eb") : (Services.Theme.isDark ? "#1f1f26" : "#f3f4f6"))
                                                    border.color: isActive ? "transparent" : Services.Theme.border
                                                    border.width: 1

                                                    Text {
                                                        id: kb_modLabel
                                                        anchors.centerIn: parent
                                                        text: modelData
                                                        font.pixelSize: 10
                                                        font.weight: Font.DemiBold
                                                        color: kb_modBtn.isActive ? Services.Theme.bgOnAccent : Services.Theme.textPrimary
                                                    }

                                                    MouseArea {
                                                        id: kb_modBtnMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                        onClicked: tab6.toggleModifier(kb_modBtn.modelData)
                                                    }
                                                }
                                            }

                                            Item { Layout.fillWidth: true }

                                            // Common Key quick-clicks
                                            Text {
                                                text: "Common Keys:"
                                                font.pixelSize: 10
                                                color: Services.Theme.textSecondary
                                                Layout.alignment: Qt.AlignVCenter
                                            }

                                            Repeater {
                                                model: ["Return", "Space", "Tab", "Q", "F", "Print"]
                                                delegate: Rectangle {
                                                    implicitHeight: 24
                                                    implicitWidth: kb_keyLabel.implicitWidth + 12
                                                    radius: 5
                                                    color: kb_keyQuickMouse.containsMouse ? (Services.Theme.isDark ? "#2a2a34" : "#e5e7eb") : (Services.Theme.isDark ? "#1f1f26" : "#f3f4f6")
                                                    border.color: Services.Theme.border
                                                    border.width: 1

                                                    Text {
                                                        id: kb_keyLabel
                                                        anchors.centerIn: parent
                                                        text: modelData
                                                        font.pixelSize: 10
                                                        color: Services.Theme.textPrimary
                                                    }

                                                    MouseArea {
                                                        id: kb_keyQuickMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                        onClicked: tab6.appendKey(modelData)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // ── Section 2: Action / Command Selection (Dropdowns) ────
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Text {
                                            text: "ACTION & DISPATCHER"
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            font.letterSpacing: 0.6
                                            color: Services.Theme.textSecondary
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: kb_actionCardCol.implicitHeight + 20
                                            radius: 8
                                            color: Services.Theme.isDark ? "#141418" : "#f8fafc"
                                            border.color: Services.Theme.isDark ? "#22222a" : "#e2e8f0"
                                            border.width: 1

                                            ColumnLayout {
                                                id: kb_actionCardCol
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                anchors.margins: 10
                                                spacing: 10

                                                // Row of Dropdowns: Category + Action / Dispatcher
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 10

                                                    // Dropdown 1: Category
                                                    ColumnLayout {
                                                        Layout.preferredWidth: 230
                                                        spacing: 4

                                                        Text {
                                                            text: "Category"
                                                            font.pixelSize: 10
                                                            font.weight: Font.DemiBold
                                                            color: Services.Theme.textSecondary
                                                        }

                                                        SettingsDropdown {
                                                            Layout.fillWidth: true
                                                            minButtonWidth: 220
                                                            maxButtonWidth: 260
                                                            buttonHeight: 32
                                                            currentValue: tab6.addCategoryType
                                                            model: tab6.actionCategories
                                                            onSelected: (val) => {
                                                                tab6.addCategoryType = val
                                                                if (val === "custom") {
                                                                    rootWindow.formAction = ""
                                                                    rootWindow.formDesc = ""
                                                                } else {
                                                                    const list = tab6.getActionListForCategory(val) || []
                                                                    if (list.length > 0 && list[0]) {
                                                                        rootWindow.formAction = list[0].id || ""
                                                                        rootWindow.formDesc = list[0].label || ""
                                                                        rootWindow.formRepeat = Boolean(list[0].defaultRepeat)
                                                                        rootWindow.formLocked = Boolean(list[0].defaultLocked)
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // Dropdown 2: Action / Dispatcher (visible when not custom)
                                                    ColumnLayout {
                                                        visible: tab6.addCategoryType !== "custom"
                                                        Layout.fillWidth: true
                                                        spacing: 4

                                                        RowLayout {
                                                            spacing: 6
                                                            Text {
                                                                text: "Action / Dispatcher Preset"
                                                                font.pixelSize: 10
                                                                font.weight: Font.DemiBold
                                                                color: Services.Theme.textSecondary
                                                            }
                                                            Text {
                                                                text: "(" + tab6.getActionListForCategory(tab6.addCategoryType).length + " available)"
                                                                font.pixelSize: 9
                                                                color: Services.Theme.textSecondary
                                                            }
                                                        }

                                                        SettingsDropdown {
                                                            Layout.fillWidth: true
                                                            minButtonWidth: 280
                                                            maxButtonWidth: 600
                                                            buttonHeight: 32
                                                            searchable: true
                                                            searchPlaceholder: "Search action / dispatcher..."
                                                            currentValue: rootWindow.formAction
                                                            model: tab6.getActionListForCategory(tab6.addCategoryType)
                                                            onSelected: (val) => {
                                                                rootWindow.formAction = val
                                                                const list = tab6.getActionListForCategory(tab6.addCategoryType)
                                                                for (let i = 0; i < list.length; i++) {
                                                                    if (list[i].id === val) {
                                                                        rootWindow.formDesc = list[i].label
                                                                        rootWindow.formRepeat = Boolean(list[i].defaultRepeat)
                                                                        rootWindow.formLocked = Boolean(list[i].defaultLocked)
                                                                        break
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }

                                                // Selected Preset Information / Description Box
                                                Rectangle {
                                                    visible: tab6.addCategoryType !== "custom" && (rootWindow.formAction || "").length > 0
                                                    Layout.fillWidth: true
                                                    implicitHeight: kb_sumRow.implicitHeight + 12
                                                    radius: 6
                                                    color: Services.Theme.isDark ? "#1b1b22" : "#edf0f5"
                                                    border.color: Services.Theme.isDark ? "#282834" : "#d8dde6"
                                                    border.width: 1

                                                    RowLayout {
                                                        id: kb_sumRow
                                                        anchors.fill: parent
                                                        anchors.margins: 8
                                                        spacing: 8

                                                        Text {
                                                            text: "󰅂"
                                                            font.family: Services.Theme.fontSymbols
                                                            font.pixelSize: 12
                                                            color: Services.Theme.accent
                                                        }

                                                        ColumnLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 2

                                                            Text {
                                                                text: rootWindow.formDesc || tab6.getHumanActionTitle(rootWindow.formAction)
                                                                font.pixelSize: 11
                                                                font.weight: Font.DemiBold
                                                                color: Services.Theme.textPrimary
                                                            }

                                                            Text {
                                                                text: {
                                                                    const list = tab6.getActionListForCategory(tab6.addCategoryType)
                                                                    for (let i = 0; i < list.length; i++) {
                                                                        if (list[i].id === rootWindow.formAction && list[i].desc) return list[i].desc
                                                                    }
                                                                    return rootWindow.formAction
                                                                }
                                                                font.pixelSize: 10
                                                                color: Services.Theme.textSecondary
                                                                elide: Text.ElideRight
                                                            }
                                                        }

                                                        Rectangle {
                                                            implicitHeight: 20
                                                            implicitWidth: kb_sumCmd.implicitWidth + 12
                                                            radius: 4
                                                            color: Services.Theme.isDark ? "#242430" : "#e2e6ed"

                                                            Text {
                                                                id: kb_sumCmd
                                                                anchors.centerIn: parent
                                                                text: rootWindow.formAction
                                                                font.pixelSize: 9
                                                                font.family: "Monospace"
                                                                color: Services.Theme.accent
                                                            }
                                                        }
                                                    }
                                                }

                                                // Custom Command Inputs (visible when Category is 'custom')
                                                ColumnLayout {
                                                    visible: tab6.addCategoryType === "custom"
                                                    Layout.fillWidth: true
                                                    spacing: 8

                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 3

                                                        Text {
                                                            text: "Command / Dispatcher to Execute"
                                                            font.pixelSize: 10
                                                            font.weight: Font.DemiBold
                                                            color: Services.Theme.textSecondary
                                                        }

                                                        Rectangle {
                                                            Layout.fillWidth: true
                                                            height: 34
                                                            radius: 6
                                                            color: Services.Theme.isDark ? "#15151a" : "#ffffff"
                                                            border.color: Services.Theme.border; border.width: 1

                                                            TextInput {
                                                                anchors.fill: parent
                                                                anchors.margins: 8
                                                                text: rootWindow.formAction
                                                                color: Services.Theme.textPrimary
                                                                font.pixelSize: Services.Theme.fontSizeSm
                                                                font.family: "Monospace"
                                                                selectByMouse: true
                                                                verticalAlignment: TextInput.AlignVCenter
                                                                onTextChanged: rootWindow.formAction = text

                                                                Text {
                                                                    anchors.fill: parent
                                                                    text: "Type custom command, e.g. kitty -e btop or hyprctl dispatch ..."
                                                                    color: Services.Theme.textSecondary
                                                                    font.pixelSize: Services.Theme.fontSizeSm
                                                                    visible: parent.text.length === 0
                                                                    verticalAlignment: Text.AlignVCenter
                                                                }
                                                            }
                                                        }
                                                    }

                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 3

                                                        Text {
                                                            text: "Friendly Description (Optional)"
                                                            font.pixelSize: 10
                                                            font.weight: Font.DemiBold
                                                            color: Services.Theme.textSecondary
                                                        }

                                                        Rectangle {
                                                            Layout.fillWidth: true
                                                            height: 32
                                                            radius: 6
                                                            color: Services.Theme.isDark ? "#15151a" : "#ffffff"
                                                            border.color: Services.Theme.border; border.width: 1

                                                            TextInput {
                                                                anchors.fill: parent
                                                                anchors.margins: 8
                                                                text: rootWindow.formDesc
                                                                color: Services.Theme.textPrimary
                                                                font.pixelSize: Services.Theme.fontSizeXs
                                                                selectByMouse: true
                                                                verticalAlignment: TextInput.AlignVCenter
                                                                onTextChanged: rootWindow.formDesc = text

                                                                Text {
                                                                    anchors.fill: parent
                                                                    text: "Friendly shortcut description (e.g. Launch Task Manager)"
                                                                    color: Services.Theme.textSecondary
                                                                    font.pixelSize: Services.Theme.fontSizeXs
                                                                    visible: parent.text.length === 0
                                                                    verticalAlignment: Text.AlignVCenter
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // ── Section 3: Behaviour Configuration Switches ────
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Text {
                                            text: "KEYBIND BEHAVIOUR & FLAGS"
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            font.letterSpacing: 0.6
                                            color: Services.Theme.textSecondary
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: kb_behLayout.implicitHeight + 8
                                            radius: 8
                                            color: Services.Theme.isDark ? "#141418" : "#f8fafc"
                                            border.color: Services.Theme.isDark ? "#22222a" : "#e2e8f0"
                                            border.width: 1

                                            ColumnLayout {
                                                id: kb_behLayout
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                anchors.margins: 4
                                                spacing: 0

                                                // 1. Repeat Switch
                                                SettingsSwitch {
                                                    title: "Repeat on Hold (repeating)"
                                                    subtitle: "Continuously triggers action while key is held (Volume, brightness, workspace resize)"
                                                    checked: rootWindow.formRepeat
                                                    onToggled: (st) => { rootWindow.formRepeat = st }
                                                }

                                                Rectangle { Layout.fillWidth: true; height: 1; color: Services.Theme.isDark ? "#202028" : "#f1f5f9" }

                                                // 2. Locked Switch
                                                SettingsSwitch {
                                                    title: "Active on Lockscreen (locked)"
                                                    subtitle: "Works even when screen locker is active (Media keys, volume, mute, power)"
                                                    checked: rootWindow.formLocked
                                                    onToggled: (st) => { rootWindow.formLocked = st }
                                                }

                                                Rectangle { Layout.fillWidth: true; height: 1; color: Services.Theme.isDark ? "#202028" : "#f1f5f9" }

                                                // 3. Mouse Binding Switch
                                                SettingsSwitch {
                                                    title: "Mouse Button Trigger (mouse)"
                                                    subtitle: "Binds shortcut to a mouse click or drag event"
                                                    checked: rootWindow.formMouse
                                                    onToggled: (st) => { rootWindow.formMouse = st }
                                                }

                                                Rectangle { Layout.fillWidth: true; height: 1; color: Services.Theme.isDark ? "#202028" : "#f1f5f9" }

                                                // 4. Non-consuming Switch
                                                SettingsSwitch {
                                                    title: "Pass-through Event (non_consuming)"
                                                    subtitle: "Does not consume the key press, passing it through to the active window"
                                                    checked: rootWindow.formNonConsuming
                                                    onToggled: (st) => { rootWindow.formNonConsuming = st }
                                                }
                                            }
                                        }
                                    }

                                    // ── Section 4: Live Config Syntax Preview ────
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Text {
                                            text: "Syntax:"
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                            color: Services.Theme.textSecondary
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 26
                                            radius: 5
                                            color: Services.Theme.isDark ? "#121216" : "#f1f5f9"
                                            border.color: Services.Theme.border; border.width: 1

                                            Text {
                                                anchors.fill: parent
                                                anchors.leftMargin: 8
                                                anchors.rightMargin: 8
                                                text: tab6.previewConfigSyntax(rootWindow.formKeys, rootWindow.formAction, rootWindow.formRepeat, rootWindow.formLocked, rootWindow.formMouse, rootWindow.formNonConsuming)
                                                font.pixelSize: 9
                                                font.family: "Monospace"
                                                color: Services.Theme.textSecondary
                                                verticalAlignment: Text.AlignVCenter
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }

                                    // ── Studio Bottom Actions ────────────────────
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Item { Layout.fillWidth: true }

                                        // Cancel Button
                                        Rectangle {
                                            implicitHeight: 32
                                            implicitWidth: kb_cancelTxt.implicitWidth + 20
                                            radius: 6
                                            color: kb_cancelMouse.containsMouse ? (Services.Theme.isDark ? "#252530" : "#e2e8f0") : "transparent"
                                            border.color: Services.Theme.border; border.width: 1

                                            Text {
                                                id: kb_cancelTxt
                                                anchors.centerIn: parent
                                                text: "Cancel"
                                                font.pixelSize: Services.Theme.fontSizeSm
                                                color: Services.Theme.textSecondary
                                            }

                                            MouseArea {
                                                id: kb_cancelMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    rootWindow.isAddingKeybind = false
                                                    rootWindow.editingBindId = ""
                                                    rootWindow.editingBindLine = -1
                                                    rootWindow.formKeys = ""
                                                    rootWindow.formAction = ""
                                                    rootWindow.formDesc = ""
                                                }
                                            }
                                        }

                                        // Save / Apply Button
                                        Rectangle {
                                            readonly property bool isValid: (rootWindow.formKeys.trim().length > 0) && (rootWindow.formAction.trim().length > 0)
                                            implicitHeight: 32
                                            implicitWidth: kb_saveTxt.implicitWidth + 24
                                            radius: 6
                                            color: isValid ? Services.Theme.accent : (Services.Theme.isDark ? "#2a2a34" : "#cbd5e1")
                                            opacity: isValid ? 1.0 : 0.6

                                            Text {
                                                id: kb_saveTxt
                                                anchors.centerIn: parent
                                                text: rootWindow.editingBindLine > 0 ? "Update Keybind" : "Add Keybind"
                                                font.pixelSize: Services.Theme.fontSizeSm
                                                font.bold: true
                                                color: parent.isValid ? Services.Theme.bgOnAccent : Services.Theme.textDisabled
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: parent.isValid ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: {
                                                    if (!parent.isValid) return
                                                    if (Services.Compositor) {
                                                        const opts = {
                                                            repeat: Boolean(rootWindow.formRepeat),
                                                            locked: Boolean(rootWindow.formLocked),
                                                            mouse: Boolean(rootWindow.formMouse),
                                                            nonConsuming: Boolean(rootWindow.formNonConsuming)
                                                        }

                                                        if (rootWindow.editingBindLine > 0) {
                                                            Services.Compositor.updateKeybind(
                                                                rootWindow.editingBindLine,
                                                                rootWindow.formKeys.trim(),
                                                                rootWindow.formAction.trim(),
                                                                rootWindow.formDesc.trim(),
                                                                rootWindow.formFile,
                                                                opts
                                                            )
                                                        } else {
                                                            Services.Compositor.addKeybind(
                                                                rootWindow.formKeys.trim(),
                                                                rootWindow.formAction.trim(),
                                                                rootWindow.formDesc.trim(),
                                                                "",
                                                                opts
                                                            )
                                                        }
                                                    }

                                                    rootWindow.isAddingKeybind = false
                                                    rootWindow.editingBindId = ""
                                                    rootWindow.editingBindLine = -1
                                                    rootWindow.formKeys = ""
                                                    rootWindow.formAction = ""
                                                    rootWindow.formDesc = ""
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ═════════════════════════════════════════════════
                            // ── SEARCH & BEHAVIOUR FILTERS ("Kurangi Listnya") ─
                            // ═════════════════════════════════════════════════
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                // Row 1: Search Bar + Behaviour Filter Pills
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    // Search Bar
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 36
                                        radius: 8
                                        color: Services.Theme.isDark ? "#1a1a20" : "#ffffff"
                                        border.color: kb_searchInput.activeFocus ? Services.Theme.accent : (Services.Theme.isDark ? "#282834" : "#e2e8f0")
                                        border.width: 1

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 10
                                            spacing: 8

                                            Text {
                                                text: "󰍉"
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 13
                                                color: Services.Theme.textSecondary
                                            }

                                            TextInput {
                                                id: kb_searchInput
                                                Layout.fillWidth: true
                                                text: rootWindow.keySearchQuery
                                                font.pixelSize: Services.Theme.fontSizeSm
                                                color: Services.Theme.textPrimary
                                                selectByMouse: true
                                                onTextChanged: {
                                                    rootWindow.keySearchQuery = text
                                                    tab6.currentPage = 0
                                                }

                                                Text {
                                                    anchors.fill: parent
                                                    text: "Search shortcut, command, or action..."
                                                    font.pixelSize: Services.Theme.fontSizeSm
                                                    color: Services.Theme.textSecondary
                                                    visible: parent.text.length === 0
                                                    verticalAlignment: Text.AlignVCenter
                                                }
                                            }

                                            Text {
                                                visible: rootWindow.keySearchQuery.length > 0
                                                text: "✕"
                                                font.pixelSize: 11
                                                color: Services.Theme.textSecondary
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        rootWindow.keySearchQuery = ""
                                                        tab6.currentPage = 0
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Behaviour Filter Chips: All, Repeat, Locked, Mouse
                                    RowLayout {
                                        spacing: 4

                                        Repeater {
                                            model: [
                                                { id: "all",    label: "All",    icon: "󰌌", count: tab6.totalBindsCount },
                                                { id: "repeat", label: "Repeat", icon: "󰑖", count: tab6.repeatBindsCount },
                                                { id: "locked", label: "Locked", icon: "󰌾", count: tab6.lockedBindsCount },
                                                { id: "mouse",  label: "Mouse",  icon: "󰍽", count: tab6.mouseBindsCount }
                                            ]
                                            delegate: Rectangle {
                                                readonly property bool isSelected: rootWindow.keyBehaviourFilter === modelData.id
                                                implicitHeight: 36
                                                implicitWidth: kb_behChipRow.implicitWidth + 16
                                                radius: 8
                                                color: isSelected ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15) : (kb_behChipMouse.containsMouse ? (Services.Theme.isDark ? "#252530" : "#e5e7eb") : (Services.Theme.isDark ? "#1a1a20" : "#ffffff"))
                                                border.color: isSelected ? Services.Theme.accent : (Services.Theme.isDark ? "#282834" : "#e2e8f0")
                                                border.width: isSelected ? 1.5 : 1

                                                RowLayout {
                                                    id: kb_behChipRow
                                                    anchors.centerIn: parent
                                                    spacing: 5

                                                    Text {
                                                        text: modelData.icon
                                                        font.family: Services.Theme.fontSymbols
                                                        font.pixelSize: 11
                                                        color: isSelected ? Services.Theme.accent : Services.Theme.textSecondary
                                                    }

                                                    Text {
                                                        text: modelData.label
                                                        font.pixelSize: Services.Theme.fontSizeXs
                                                        font.weight: isSelected ? Font.Bold : Font.Normal
                                                        color: isSelected ? Services.Theme.textPrimary : Services.Theme.textSecondary
                                                    }

                                                    Text {
                                                        text: String(modelData.count)
                                                        font.pixelSize: 9
                                                        font.bold: true
                                                        color: isSelected ? Services.Theme.accent : Services.Theme.textSecondary
                                                    }
                                                }

                                                MouseArea {
                                                    id: kb_behChipMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        rootWindow.keyBehaviourFilter = modelData.id
                                                        tab6.currentPage = 0
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Row 2: Category Segment Switcher Bar (Unified with Tab 5 subtabs, without icons)
                                Rectangle {
                                    id: kbCategoryTabBar
                                    Layout.fillWidth: true
                                    height: 38
                                    radius: 8
                                    color: Services.Theme.surfaceVariant
                                    border.color: Services.Theme.border
                                    border.width: 1
                                    clip: true

                                    // Liquid Glass Sliding Indicator Pill
                                    Rectangle {
                                        id: kbCatPill
                                        z: 1
                                        y: 3
                                        height: parent.height - 6
                                        radius: 6

                                        readonly property var catKeys: ["all", "quickshell", "window", "apps", "media", "system", "custom"]
                                        readonly property int activeIdx: {
                                            const idx = catKeys.indexOf(rootWindow.keyCategory)
                                            return idx >= 0 ? idx : 0
                                        }
                                        readonly property int tabCount: 7
                                        readonly property real itemWidth: Math.max(0, (kbCategoryTabBar.width - 6 - (tabCount - 1) * 3) / tabCount)

                                        x: 3 + activeIdx * (itemWidth + 3)
                                        width: itemWidth

                                        // Liquid Transparent Glass Material
                                        color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.22)
                                        border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.55)
                                        border.width: 1

                                        // Top Specular Glass Highlight Line
                                        Rectangle {
                                            anchors.top: parent.top
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.topMargin: 1
                                            anchors.leftMargin: 4
                                            anchors.rightMargin: 4
                                            height: 1
                                            radius: 0.5
                                            color: Qt.rgba(1, 1, 1, 0.40)
                                        }

                                        // Liquid Gloss Curved Sheen
                                        Rectangle {
                                            anchors.top: parent.top
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.topMargin: 1
                                            anchors.leftMargin: 2
                                            anchors.rightMargin: 2
                                            height: parent.height * 0.46
                                            radius: 5
                                            gradient: Gradient {
                                                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.16) }
                                                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                                            }
                                        }

                                        // Fluid Sliding Transitions
                                        Behavior on x {
                                            NumberAnimation {
                                                duration: 260
                                                easing.type: Easing.OutBack
                                                easing.overshoot: 1.15
                                            }
                                        }
                                        Behavior on width {
                                            NumberAnimation {
                                                duration: 260
                                                easing.type: Easing.OutBack
                                                easing.overshoot: 1.15
                                            }
                                        }
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                        Behavior on border.color { ColorAnimation { duration: 200 } }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 3
                                        spacing: 3
                                        z: 2

                                        Repeater {
                                            model: [
                                                { id: "all",        label: "All" },
                                                { id: "quickshell", label: "Quickshell" },
                                                { id: "window",     label: "Window" },
                                                { id: "apps",       label: "Apps" },
                                                { id: "media",      label: "Media" },
                                                { id: "system",     label: "System" },
                                                { id: "custom",     label: "Custom" }
                                            ]

                                            delegate: Item {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true

                                                readonly property bool isCur: rootWindow.keyCategory === modelData.id

                                                // Hover effect for unselected tabs
                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: 5
                                                    color: subMouse.containsMouse && !isCur ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                }

                                                Text {
                                                    anchors.centerIn: parent
                                                    width: Math.min(parent.width - 6, implicitWidth)
                                                    text: modelData.label
                                                    font.pixelSize: 11
                                                    font.weight: isCur ? Font.DemiBold : Font.Normal
                                                    color: isCur ? Services.Theme.textPrimary : (keySubMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary)
                                                    horizontalAlignment: Text.AlignHCenter
                                                    elide: Text.ElideRight
                                                    Behavior on color { ColorAnimation { duration: 200 } }
                                                }

                                                MouseArea {
                                                    id: keySubMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        rootWindow.keyCategory = modelData.id
                                                        tab6.currentPage = 0
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ═════════════════════════════════════════════════
                            // ── THE KEYBINDINGS LIST (Clean Flat Cards, No 3D) ─
                            // ═════════════════════════════════════════════════
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                // Empty State
                                Rectangle {
                                    visible: tab6.filteredBinds.length === 0
                                    Layout.fillWidth: true
                                    implicitHeight: 120
                                    radius: 10
                                    color: Services.Theme.isDark ? "#18181f" : "#f9fafb"
                                    border.color: Services.Theme.isDark ? "#24242e" : "#e5e7eb"
                                    border.width: 1

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: "󰌌"
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 24
                                            color: Services.Theme.textSecondary
                                        }
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: "No keybindings matched your filter or search"
                                            font.pixelSize: Services.Theme.fontSizeSm
                                            color: Services.Theme.textSecondary
                                        }
                                    }
                                }

                                // Keybind Items Repeater (Paginated)
                                Repeater {
                                    model: tab6.pagedBinds
                                    delegate: Rectangle {
                                        id: kb_bindItemRoot
                                        Layout.fillWidth: true
                                        implicitHeight: 52
                                        radius: 8
                                        color: kb_bindMouse.containsMouse ? (Services.Theme.isDark ? "#202028" : "#f8fafc") : (Services.Theme.isDark ? "#17171d" : "#ffffff")
                                        border.color: (rootWindow.editingBindLine > 0 && rootWindow.editingBindLine === modelData.startLine)
                                            ? Services.Theme.accent
                                            : (Services.Theme.isDark ? "#252530" : "#e2e8f0")
                                        border.width: 1

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            spacing: 12

                                            // 1. Flat Keycaps (Simple, NO 3D)
                                            RowLayout {
                                                spacing: 4
                                                Layout.minimumWidth: 150
                                                Layout.preferredWidth: 180

                                                readonly property var tokens: (modelData.keys || "").split("+").map(s => s.trim()).filter(s => s.length > 0)

                                                Repeater {
                                                    model: parent.tokens
                                                    delegate: RowLayout {
                                                        spacing: 4
                                                        Rectangle {
                                                            implicitHeight: 24
                                                            implicitWidth: kb_keyCapTxt.implicitWidth + 12
                                                            radius: 5
                                                            color: Services.Theme.isDark ? "#252530" : "#f1f5f9"
                                                            border.color: Services.Theme.isDark ? "#363644" : "#cbd5e1"
                                                            border.width: 1

                                                            Text {
                                                                id: kb_keyCapTxt
                                                                anchors.centerIn: parent
                                                                text: modelData
                                                                font.pixelSize: 10
                                                                font.weight: Font.DemiBold
                                                                color: Services.Theme.textPrimary
                                                            }
                                                        }

                                                        Text {
                                                            visible: index < (parent.parent.tokens.length - 1)
                                                            text: "+"
                                                            font.pixelSize: 10
                                                            font.bold: true
                                                            color: Services.Theme.textSecondary
                                                        }
                                                    }
                                                }
                                            }

                                            // 2. Action Title & Subtitle
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1

                                                RowLayout {
                                                    spacing: 6
                                                    Text {
                                                        text: tab6.getHumanActionTitle(modelData.action)
                                                        font.pixelSize: Services.Theme.fontSizeSm
                                                        font.weight: Font.Medium
                                                        color: Services.Theme.textPrimary
                                                        elide: Text.ElideRight
                                                    }

                                                    // Category Badge
                                                    Rectangle {
                                                        visible: (modelData.category || "").length > 0
                                                        radius: 4
                                                        implicitHeight: 16
                                                        implicitWidth: kb_catTagTxt.implicitWidth + 8
                                                        color: Services.Theme.isDark ? "#202028" : "#f1f5f9"
                                                        Text {
                                                            id: kb_catTagTxt
                                                            anchors.centerIn: parent
                                                            text: (modelData.category || "custom").toUpperCase()
                                                            font.pixelSize: 8
                                                            font.weight: Font.DemiBold
                                                            color: Services.Theme.textSecondary
                                                        }
                                                    }
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData.action
                                                    font.pixelSize: 10
                                                    font.family: "Monospace"
                                                    color: Services.Theme.textSecondary
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            // 3. Behaviour Badges (Repeat, Locked, Mouse)
                                            RowLayout {
                                                spacing: 4

                                                // Repeat Badge
                                                Rectangle {
                                                    visible: Boolean(modelData.repeat)
                                                    radius: 4
                                                    implicitHeight: 20
                                                    implicitWidth: kb_repTagRow.implicitWidth + 10
                                                    color: Services.Theme.isDark ? "#2e1065" : "#f3e8ff"
                                                    border.color: "#a855f7"; border.width: 1

                                                    RowLayout {
                                                        id: kb_repTagRow
                                                        anchors.centerIn: parent
                                                        spacing: 3
                                                        Text { text: "󰑖"; font.family: Services.Theme.fontSymbols; font.pixelSize: 9; color: "#c084fc" }
                                                        Text { text: "Repeat"; font.pixelSize: 9; font.bold: true; color: "#c084fc" }
                                                    }
                                                }

                                                // Locked Badge
                                                Rectangle {
                                                    visible: Boolean(modelData.locked)
                                                    radius: 4
                                                    implicitHeight: 20
                                                    implicitWidth: kb_lkTagRow.implicitWidth + 10
                                                    color: Services.Theme.isDark ? "#064e3b" : "#ecfdf5"
                                                    border.color: "#10b981"; border.width: 1

                                                    RowLayout {
                                                        id: kb_lkTagRow
                                                        anchors.centerIn: parent
                                                        spacing: 3
                                                        Text { text: "󰌾"; font.family: Services.Theme.fontSymbols; font.pixelSize: 9; color: "#34d399" }
                                                        Text { text: "Locked"; font.pixelSize: 9; font.bold: true; color: "#34d399" }
                                                    }
                                                }

                                                // Mouse Badge
                                                Rectangle {
                                                    visible: Boolean(modelData.mouse)
                                                    radius: 4
                                                    implicitHeight: 20
                                                    implicitWidth: kb_msTagRow.implicitWidth + 10
                                                    color: Services.Theme.isDark ? "#451a03" : "#fef3c7"
                                                    border.color: "#f59e0b"; border.width: 1

                                                    RowLayout {
                                                        id: kb_msTagRow
                                                        anchors.centerIn: parent
                                                        spacing: 3
                                                        Text { text: "󰍽"; font.family: Services.Theme.fontSymbols; font.pixelSize: 9; color: "#fbbf24" }
                                                        Text { text: "Mouse"; font.pixelSize: 9; font.bold: true; color: "#fbbf24" }
                                                    }
                                                }
                                            }

                                            // 4. Quick Action Buttons (Edit & Delete)
                                            RowLayout {
                                                spacing: 4

                                                // Edit Button
                                                Rectangle {
                                                    implicitHeight: 28; implicitWidth: 28; radius: 5
                                                    color: kb_editMouse.containsMouse ? (Services.Theme.isDark ? "#2c2c38" : "#e2e8f0") : "transparent"
                                                    border.color: kb_editMouse.containsMouse ? Services.Theme.border : "transparent"
                                                    border.width: 1

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "󰏫"
                                                        font.family: Services.Theme.fontSymbols
                                                        font.pixelSize: 12
                                                        color: kb_editMouse.containsMouse ? Services.Theme.accent : Services.Theme.textSecondary
                                                    }

                                                    MouseArea {
                                                        id: kb_editMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            rootWindow.editingBindId = modelData.id || ""
                                                            rootWindow.editingBindLine = modelData.startLine || -1
                                                            rootWindow.formKeys = modelData.keys || ""
                                                            rootWindow.formAction = modelData.action || ""
                                                            rootWindow.formDesc = modelData.desc || tab6.getHumanActionTitle(modelData.action)
                                                            rootWindow.formRepeat = Boolean(modelData.repeat)
                                                            rootWindow.formLocked = Boolean(modelData.locked)
                                                            rootWindow.formMouse = Boolean(modelData.mouse)
                                                            rootWindow.formNonConsuming = Boolean(modelData.nonConsuming)
                                                            rootWindow.formFile = modelData.file || ""
                                                            tab6.addCategoryType = tab6.findCategoryForAction(modelData.action)
                                                            rootWindow.isAddingKeybind = false
                                                        }
                                                    }
                                                }

                                                // Delete Button
                                                Rectangle {
                                                    implicitHeight: 28; implicitWidth: 28; radius: 5
                                                    color: kb_delMouse.containsMouse ? (Services.Theme.isDark ? "#3b1717" : "#fee2e2") : "transparent"
                                                    border.color: kb_delMouse.containsMouse ? "#ef4444" : "transparent"
                                                    border.width: 1

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "󰆴"
                                                        font.family: Services.Theme.fontSymbols
                                                        font.pixelSize: 12
                                                        color: kb_delMouse.containsMouse ? "#ef4444" : Services.Theme.textSecondary
                                                    }

                                                    MouseArea {
                                                        id: kb_delMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (Services.Compositor) {
                                                                Services.Compositor.deleteKeybind(modelData.startLine, modelData.file)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: kb_bindMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            z: -1
                                        }
                                    }
                                }
                            }

                            // ═════════════════════════════════════════════════
                            // ── PAGINATION CONTROLS ("Kurangi Listnya") ──────
                            // ═════════════════════════════════════════════════
                            RowLayout {
                                visible: tab6.filteredBinds.length > 0
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    text: "Showing " + ((tab6.currentPage * tab6.itemsPerPage) + 1) + "–" + Math.min((tab6.currentPage + 1) * tab6.itemsPerPage, tab6.filteredBinds.length) + " of " + tab6.filteredBinds.length + " keybindings"
                                    font.pixelSize: Services.Theme.fontSizeXs
                                    color: Services.Theme.textSecondary
                                }

                                Text {
                                    visible: Boolean(Services.Compositor && Services.Compositor.configPath)
                                    text: "• " + ((Services.Compositor && Services.Compositor.configPath) ? Services.Compositor.configPath.split("/").pop() : "")
                                    font.pixelSize: 10
                                    font.family: "Monospace"
                                    color: Services.Theme.textDisabled
                                }

                                Item { Layout.fillWidth: true }

                                RowLayout {
                                    spacing: 6

                                    // Previous Button
                                    Rectangle {
                                        readonly property bool canPrev: tab6.currentPage > 0
                                        implicitHeight: 26
                                        implicitWidth: kb_prevTxt.implicitWidth + 16
                                        radius: 5
                                        color: canPrev ? (kb_prevMouse.containsMouse ? (Services.Theme.isDark ? "#282834" : "#e2e8f0") : (Services.Theme.isDark ? "#1c1c24" : "#f1f5f9")) : "transparent"
                                        border.color: Services.Theme.border; border.width: 1
                                        opacity: canPrev ? 1.0 : 0.4

                                        Text {
                                            id: kb_prevTxt
                                            anchors.centerIn: parent
                                            text: "‹ Previous"
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                            color: Services.Theme.textPrimary
                                        }

                                        MouseArea {
                                            id: kb_prevMouse; anchors.fill: parent; hoverEnabled: parent.canPrev
                                            cursorShape: parent.canPrev ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: {
                                                if (parent.canPrev) tab6.currentPage--
                                            }
                                        }
                                    }

                                    // Page Number Indicator
                                    Rectangle {
                                        implicitHeight: 26
                                        implicitWidth: kb_pageNumTxt.implicitWidth + 14
                                        radius: 5
                                        color: Services.Theme.isDark ? "#16161c" : "#e5e7eb"

                                        Text {
                                            id: kb_pageNumTxt
                                            anchors.centerIn: parent
                                            text: "Page " + (tab6.currentPage + 1) + " of " + tab6.totalPages
                                            font.pixelSize: 10
                                            font.bold: true
                                            color: Services.Theme.textPrimary
                                        }
                                    }

                                    // Next Button
                                    Rectangle {
                                        readonly property bool canNext: tab6.currentPage < (tab6.totalPages - 1)
                                        implicitHeight: 26
                                        implicitWidth: kb_nextTxt.implicitWidth + 16
                                        radius: 5
                                        color: canNext ? (kb_nextMouse.containsMouse ? (Services.Theme.isDark ? "#282834" : "#e2e8f0") : (Services.Theme.isDark ? "#1c1c24" : "#f1f5f9")) : "transparent"
                                        border.color: Services.Theme.border; border.width: 1
                                        opacity: canNext ? 1.0 : 0.4

                                        Text {
                                            id: kb_nextTxt
                                            anchors.centerIn: parent
                                            text: "Next ›"
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                            color: Services.Theme.textPrimary
                                        }

                                        MouseArea {
                                            id: kb_nextMouse; anchors.fill: parent; hoverEnabled: parent.canNext
                                            cursorShape: parent.canNext ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: {
                                                if (parent.canNext) tab6.currentPage++
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ═════════════════════════════════════════════
                        // TAB 7: BACKUP & RESET
                        // ═════════════════════════════════════════════
                        ColumnLayout {
                            id: tab7
                            Layout.fillWidth: true
                            spacing: 14

                            SettingsSection {
                                title: "Configuration Management"
                                icon: Services.Icons.undo

                                SettingsRow {
                                    title: "Export Configuration"
                                    subtitle: "Save a backup snapshot of your current settings"

                                    Rectangle {
                                        height: 26
                                        implicitWidth: expTxt.implicitWidth + 14
                                        radius: 4
                                        color: expMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Services.Theme.bgElevated
                                        border.color: Services.Theme.border; border.width: 1
                                        Text { id: expTxt; anchors.centerIn: parent; text: "Backup..."; font.pixelSize: 11; color: Services.Theme.textPrimary }
                                        MouseArea {
                                            id: expMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: { if (Services.Config) Services.Config.exportConfig() }
                                        }
                                    }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Import Configuration"
                                    subtitle: "Restore previously exported settings snapshot"

                                    Rectangle {
                                        height: 26
                                        implicitWidth: impTxt.implicitWidth + 14
                                        radius: 4
                                        color: impMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Services.Theme.bgElevated
                                        border.color: Services.Theme.border; border.width: 1
                                        Text { id: impTxt; anchors.centerIn: parent; text: "Restore..."; font.pixelSize: 11; color: Services.Theme.textPrimary }
                                        MouseArea {
                                            id: impMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: { if (Services.Config) Services.Config.importConfig() }
                                        }
                                    }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Reset to Defaults"
                                    subtitle: "Restore factory theme, layout, and configuration"

                                    Rectangle {
                                        height: 26
                                        implicitWidth: rstTxt.implicitWidth + 14
                                        radius: 4
                                        color: rstMouse.containsMouse ? Qt.rgba(0.9, 0.2, 0.2, 0.15) : Services.Theme.bgElevated
                                        border.color: Services.Theme.border; border.width: 1
                                        Text { id: rstTxt; anchors.centerIn: parent; text: "Reset All"; font.pixelSize: 11; color: Services.Theme.danger }
                                        MouseArea {
                                            id: rstMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: { if (Services.Config) Services.Config.resetToDefaults() }
                                        }
                                    }
                                }
                            }
                        }

                        // ═════════════════════════════════════════════
                        // ═════════════════════════════════════════════
                        // TAB 8: ABOUT & SYSTEM INFORMATION (Calm, Subtle & Minimalist)
                        // ═════════════════════════════════════════════
                        ColumnLayout {
                            id: tab8
                            Layout.fillWidth: true
                            spacing: 12

                            // ── User Profile Hero Banner (Refined Minimal Card) ────────
                            Rectangle {
                                Layout.fillWidth: true
                                height: 84
                                radius: Services.Theme.radiusSm || 8
                                color: Services.Theme.surfaceVariant
                                border.color: Services.Theme.border
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 16
                                    anchors.rightMargin: 16
                                    anchors.topMargin: 12
                                    anchors.bottomMargin: 12
                                    spacing: 16

                                    // Interactive Avatar Frame with Live Photo & Camera Hover
                                    Item {
                                        id: aboutHeroAvatarFrame
                                        Layout.preferredWidth: 60
                                        Layout.preferredHeight: 60
                                        Layout.alignment: Qt.AlignVCenter

                                        Services.AvatarFrame {
                                            anchors.fill: parent
                                            source: Services.OsInfo.avatarPath
                                            shapeRadius: 16
                                            backgroundColor: Services.Theme.bgElevated
                                            borderColor: Services.Theme.border
                                            borderWidth: 1
                                            fallbackText: {
                                                const u = (Services.OsInfo.username || Quickshell.env("USER") || "user").toUpperCase()
                                                return u.length > 0 ? u.charAt(0) : "󰌽"
                                            }
                                            fallbackFontFamily: Services.Theme.fontSymbols
                                            fallbackFontSize: 24
                                            fallbackColor: Services.Theme.accent
                                        }

                                        // Camera overlay on hover (indicates clicking changes avatar)
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 16
                                            color: Qt.rgba(0, 0, 0, 0.45)
                                            visible: aboutHeroAvatarMouse.containsMouse
                                            antialiasing: true

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰄀"
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 18
                                                color: "white"
                                            }
                                        }

                                        // Reset button if custom avatar
                                        Rectangle {
                                            visible: Services.OsInfo.isCustomAvatar && aboutHeroAvatarMouse.containsMouse
                                            anchors.top: parent.top
                                            anchors.right: parent.right
                                            anchors.topMargin: -3
                                            anchors.rightMargin: -3
                                            width: 18; height: 18
                                            radius: 9
                                            color: Services.Theme.danger || "#ef4444"
                                            z: 10

                                            Text {
                                                anchors.centerIn: parent
                                                text: "✕"
                                                font.pixelSize: 9
                                                font.weight: Font.Bold
                                                color: "#ffffff"
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Services.OsInfo.clearCustomAvatar()
                                            }
                                        }

                                        MouseArea {
                                            id: aboutHeroAvatarMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Services.OsInfo.pickCustomAvatar()
                                        }
                                    }

                                    // User & Host Information Column (hugging avatar)
                                    ColumnLayout {
                                        spacing: 2
                                        Layout.alignment: Qt.AlignVCenter

                                        Text {
                                            text: Services.OsInfo.username || Quickshell.env("USER") || "User"
                                            font.pixelSize: 15
                                            font.weight: Font.DemiBold
                                            color: Services.Theme.textPrimary
                                        }

                                        Text {
                                            text: (Services.OsInfo.username || "user") + "@" + (Services.OsInfo.hostname || "local") + "  ·  " + (Services.OsInfo.shellName || "sh")
                                            font.pixelSize: 11
                                            font.weight: Font.Medium
                                            color: Services.Theme.textSecondary
                                        }

                                        Text {
                                            text: (Services.OsInfo.distroName || "Linux") + "  ·  Kernel " + (Services.OsInfo.kernel || "")
                                            font.family: Services.Theme.fontMono
                                            font.pixelSize: 9
                                            color: Services.Theme.textDisabled
                                        }
                                    }

                                    // Spacer pushing content to the left
                                    Item { Layout.fillWidth: true }
                                }
                            }

                            // ── System Hardware & Environment Grid ────────────────
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                rowSpacing: 8
                                columnSpacing: 8

                                // Tile 1: OS Distro
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 50
                                    radius: 6
                                    color: Services.Theme.surfaceVariant
                                    border.color: Services.Theme.border
                                    border.width: 1

                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 10
                                        Rectangle {
                                            Layout.preferredWidth: 28; Layout.preferredHeight: 28; radius: 5
                                            color: Services.Theme.bgElevated
                                            border.color: Services.Theme.border
                                            border.width: 1
                                            Text { anchors.centerIn: parent; text: (Services.OsInfo && Services.OsInfo.logoGlyph) ? Services.OsInfo.logoGlyph : "󰌽"; font.family: Services.Theme.fontSymbols; font.pixelSize: 13; color: Services.Theme.textSecondary }
                                        }
                                        ColumnLayout {
                                            spacing: 1; Layout.fillWidth: true
                                            Text { text: "Distribution"; font.pixelSize: 8; font.weight: Font.Bold; color: Services.Theme.textDisabled }
                                            Text { text: Services.OsInfo.distroName || "Linux"; font.pixelSize: 11; font.weight: Font.Medium; color: Services.Theme.textPrimary; elide: Text.ElideRight; Layout.fillWidth: true }
                                        }
                                    }
                                }

                                // Tile 2: Kernel
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 50
                                    radius: 6
                                    color: Services.Theme.surfaceVariant
                                    border.color: Services.Theme.border
                                    border.width: 1

                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 10
                                        Rectangle {
                                            Layout.preferredWidth: 28; Layout.preferredHeight: 28; radius: 5
                                            color: Services.Theme.bgElevated
                                            border.color: Services.Theme.border
                                            border.width: 1
                                            Text { anchors.centerIn: parent; text: "󰌽"; font.family: Services.Theme.fontSymbols; font.pixelSize: 13; color: Services.Theme.textSecondary }
                                        }
                                        ColumnLayout {
                                            spacing: 1; Layout.fillWidth: true
                                            Text { text: "Linux Kernel"; font.pixelSize: 8; font.weight: Font.Bold; color: Services.Theme.textDisabled }
                                            Text { text: Services.OsInfo.kernel || "-"; font.family: Services.Theme.fontMono; font.pixelSize: 10.5 ? 10 : 10; font.weight: Font.Medium; color: Services.Theme.textPrimary; elide: Text.ElideRight; Layout.fillWidth: true }
                                        }
                                    }
                                }

                                // Tile 3: Compositor
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 50
                                    radius: 6
                                    color: Services.Theme.surfaceVariant
                                    border.color: Services.Theme.border
                                    border.width: 1

                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 10
                                        Rectangle {
                                            Layout.preferredWidth: 28; Layout.preferredHeight: 28; radius: 5
                                            color: Services.Theme.bgElevated
                                            border.color: Services.Theme.border
                                            border.width: 1
                                            Text { anchors.centerIn: parent; text: Services.Icons.display; font.family: Services.Theme.fontSymbols; font.pixelSize: 13; color: Services.Theme.textSecondary }
                                        }
                                        ColumnLayout {
                                            spacing: 1; Layout.fillWidth: true
                                            Text { text: "Window Compositor"; font.pixelSize: 8; font.weight: Font.Bold; color: Services.Theme.textDisabled }
                                            Text { text: (Services.Compositor ? Services.Compositor.activeDisplayName : "Wayland") + " (" + (Services.Compositor && Services.Compositor.configType ? Services.Compositor.configType.toUpperCase() : "CONF") + ")"; font.pixelSize: 11; font.weight: Font.Medium; color: Services.Theme.textPrimary; elide: Text.ElideRight; Layout.fillWidth: true }
                                        }
                                    }
                                }

                                // Tile 4: Desktop & Shell (Green Area in Screenshot)
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 50
                                    radius: 6
                                    color: Services.Theme.surfaceVariant
                                    border.color: Services.Theme.border
                                    border.width: 1

                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 10
                                        Rectangle {
                                            Layout.preferredWidth: 28; Layout.preferredHeight: 28; radius: 5
                                            color: Services.Theme.bgElevated
                                            border.color: Services.Theme.border
                                            border.width: 1
                                            Text { anchors.centerIn: parent; text: Services.Icons.terminal || Services.Icons.sparkle || "󰞷"; font.family: Services.Theme.fontSymbols; font.pixelSize: 13; color: Services.Theme.textSecondary }
                                        }
                                        ColumnLayout {
                                            spacing: 1; Layout.fillWidth: true
                                            Text { text: "Desktop & Shell"; font.pixelSize: 8; font.weight: Font.Bold; color: Services.Theme.textDisabled }
                                            Text { text: "Quickshell Desktop v1.2 · " + (Services.OsInfo.shellName || "sh"); font.pixelSize: 11; font.weight: Font.Medium; color: Services.Theme.textPrimary; elide: Text.ElideRight; Layout.fillWidth: true }
                                        }
                                    }
                                }
                            }

                            // ── Interactive Actions Bar ───────────────────────────
                            SettingsSection {
                                title: "Quick Actions & Tools"
                                icon: Services.Icons.sliders

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.margins: 10
                                    spacing: 8

                                    // Copy System Specs Button
                                    Rectangle {
                                        property bool justCopied: false
                                        Layout.fillWidth: true
                                        height: 32
                                        radius: 5
                                        color: justCopied ? Qt.rgba(0.2, 0.8, 0.3, 0.15) : (copyMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.bgElevated)
                                        border.color: justCopied ? (Services.Theme.success || "#10b981") : Services.Theme.border
                                        border.width: 1

                                        RowLayout {
                                            anchors.centerIn: parent; spacing: 6
                                            Text { text: parent.parent.justCopied ? (Services.Icons.check || "✓") : (Services.Icons.clipboard || "󰅌"); font.family: Services.Theme.fontSymbols; font.pixelSize: 10; color: parent.parent.justCopied ? (Services.Theme.success || "#10b981") : Services.Theme.textSecondary }
                                            Text { text: parent.parent.justCopied ? "Copied to Clipboard!" : "Copy System Specs"; font.pixelSize: 10; font.weight: Font.Medium; color: parent.parent.justCopied ? (Services.Theme.success || "#10b981") : Services.Theme.textPrimary }
                                        }

                                        Timer {
                                            id: copySpecsTimer
                                            interval: 1800
                                            onTriggered: parent.justCopied = false
                                        }

                                        MouseArea {
                                            id: copyMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                const specs = `OS: ${Services.OsInfo.distroName || "Linux"}\nKernel: ${Services.OsInfo.kernel || "-"}\nHost: ${Services.OsInfo.hostname || "local"}\nCompositor: ${Services.Compositor ? Services.Compositor.activeDisplayName : "Wayland"}\nShell: ${Services.OsInfo.shellName || "sh"}\nUser: ${Services.OsInfo.username || "user"}\nDesktop: Quickshell v1.2`
                                                if (Services.Clipboard) Services.Clipboard.copyText(specs)
                                                parent.justCopied = true
                                                copySpecsTimer.restart()
                                            }
                                        }
                                    }

                                    // Open Terminal Button
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 32
                                        radius: 5
                                        color: termMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.bgElevated
                                        border.color: Services.Theme.border
                                        border.width: 1

                                        RowLayout {
                                            anchors.centerIn: parent; spacing: 6
                                            Text { text: Services.Icons.terminal || "󰞷"; font.family: Services.Theme.fontSymbols; font.pixelSize: 10; color: Services.Theme.textSecondary }
                                            Text { text: "Open Terminal"; font.pixelSize: 10; font.weight: Font.Medium; color: Services.Theme.textPrimary }
                                        }

                                        MouseArea {
                                            id: termMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                openTermProc.running = true
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Helper Processes ─────────────────────────────────────────────────────
    Process {
        id: openTermProc
        command: ["sh", "-c", "kitty || alacritty || foot || xterm || ghostty"]
    }
    Process {
        id: testNotifProc
        command: ["notify-send", "-a", "Quickshell Settings", "Settings Test", "Your notification preferences are working!"]
    }
    Process {
        id: lockSessionProc
        command: ["sh", "-c", "qs ipc call lockscreen lock || loginctl lock-session"]
    }
    Process {
        id: suspendProc
        command: ["systemctl", "suspend"]
    }
    Process {
        id: rebootProc
        command: ["systemctl", "reboot"]
    }
    Process {
        id: poweroffProc
        command: ["systemctl", "poweroff"]
    }
}
