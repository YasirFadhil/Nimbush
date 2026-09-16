import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray
import "../../../services" as Services
import "." as Components

RowLayout {
    id: root
    spacing: 0

    // ── Input dari Bar ────────────────────────────────────────────
    property real barWidth: 1920
    property real rightMargin: 12
    property real centerReservedWidth: 0
    property string islandDemand: "idle"

    // ── Konstanta tuning ──────────────────────────────────────────
    readonly property real safetyGap: 20      // jarak napas minimum island↔tray
    readonly property real hysteresisPx: 20   // beda ambang naik vs turun tier
    readonly property int  restoreDelayMs: 80

    // ── Ruang yang tersedia ───────────────────────────────────────
    readonly property real centerRightEdge: (barWidth + centerReservedWidth) / 2
    readonly property real availableWidth:
        Math.max(0, barWidth - rightMargin - centerRightEdge - safetyGap)

    readonly property string barStyle: Services.Config ? Services.Config.barStyle : "islands"
    readonly property bool isIslands: barStyle === "islands"
    readonly property bool isMinimal: barStyle === "minimal"
    readonly property bool isFloating: barStyle === "floating"
    readonly property bool isUnified: barStyle === "unified"

    readonly property int pillHeight: isMinimal ? 24 : 28
    readonly property int pillRadius: isMinimal ? 6 : (isIslands ? 14 : 10)
    readonly property int innerSpacing: isMinimal ? 4 : 6

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

    // ── Daftar item dan urutan mengalah ───────────────────────────
    readonly property var yieldOrder: [volPill, sysmonInd, sysTrayIcons, batPill, ctrlPill, clockCenterPill]
    readonly property var compactables: [volPill, sysmonInd]

    // ── Tier Spacing & Width ──────────────────────────────────────
    readonly property int itemSpacing: isMinimal ? 4 : 8

    function widthAtTier(tier) {
        // tier 0 = full
        // tier 1 = compact (volPill & sysmonInd only)
        // tier 2+ = compact + yield bertahap
        const spacing = itemSpacing
        const compact = tier >= 1
        let total = 0
        let yieldCount = Math.max(0, tier - 1)

        for (let i = 0; i < yieldOrder.length; i++) {
            const item = yieldOrder[i]
            if (!item || !item.visible) continue
            if (i < yieldCount) continue   // item ini mengalah pada tier ini
            const isCompactable = compactables.indexOf(item) !== -1
            const useCompact = compact && isCompactable
            total += (useCompact ? item.trayWidthCompact : item.trayWidthFull) + spacing
        }
        return Math.max(0, total - spacing)
    }

    // ── State Machine & Histeresis ────────────────────────────────
    property int layoutTier: 0
    readonly property int maxTier: 1 + yieldOrder.length

    function recomputeLayout() {
        const avail = availableWidth
        let tier = layoutTier

        // Naik tier (perketat) — langsung, tanpa histeresis
        while (tier < maxTier && widthAtTier(tier) > avail) {
            tier++
        }

        // Turun tier (longgarkan) — butuh margin histeresis
        while (tier > 0 && widthAtTier(tier - 1) + hysteresisPx <= avail) {
            tier--
        }

        layoutTier = tier
    }

    Timer {
        id: restoreTimer
        interval: root.restoreDelayMs
        onTriggered: root.recomputeLayout()
    }

    function requestLayout() {
        if (widthAtTier(layoutTier) > availableWidth) {
            restoreTimer.stop()
            recomputeLayout()
        } else {
            restoreTimer.restart()
        }
    }

    onAvailableWidthChanged: requestLayout()
    onIslandDemandChanged: requestLayout()
    Component.onCompleted: recomputeLayout()

    Connections {
        target: Services.Config
        function onConfigChanged() {
            root.requestLayout()
        }
    }

    // ── 1. System Tray App Icons ───────────────────────────────────────────
    Components.SystemTrayIcons {
        id: sysTrayIcons
        trayMenuPopup: trayMenuPopup
        trayOverflowPopup: trayOverflowPopup

        readonly property int yieldIndex: root.yieldOrder.indexOf(sysTrayIcons)
        readonly property bool isYielded: Services.OverlayManager.isLocked || (root.layoutTier >= 2 && yieldIndex < (root.layoutTier - 1))
        readonly property bool isCompact: false

        trayCompact: false
        trayYielded: isYielded

        Layout.preferredWidth: isYielded ? 0 : trayWidthFull
        Layout.preferredHeight: implicitHeight
        Layout.rightMargin: isYielded ? 0 : root.itemSpacing
        Layout.alignment: Qt.AlignVCenter
        clip: true
        opacity: isYielded ? 0.0 : 1.0
        visible: Services.Config ? Services.Config.showSysTray : true
        enabled: opacity > 0.5

        onVisibleChanged: root.requestLayout()

        Behavior on Layout.preferredWidth { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
        Behavior on Layout.rightMargin { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
    }

    Components.TrayMenuPopup {
        id: trayMenuPopup
    }

    Components.TrayOverflowPopup {
        id: trayOverflowPopup
        trayMenuPopup: trayMenuPopup
        maxVisibleCount: sysTrayIcons.maxVisibleCount
    }

    // ── 2. CPU / Sysmon Indicator ─────────────────────────────────────────
    Components.SysmonIndicator {
        id: sysmonInd
        hPadOverride: -1

        readonly property int yieldIndex: root.yieldOrder.indexOf(sysmonInd)
        readonly property bool isYielded: Services.OverlayManager.isLocked || (root.layoutTier >= 2 && yieldIndex < (root.layoutTier - 1))
        readonly property bool isCompact: root.layoutTier >= 1 && root.compactables.indexOf(sysmonInd) !== -1

        trayCompact: isCompact
        trayYielded: isYielded

        Layout.preferredWidth: isYielded ? 0 : (isCompact ? trayWidthCompact : trayWidthFull)
        Layout.preferredHeight: implicitHeight
        Layout.rightMargin: isYielded ? 0 : root.itemSpacing
        Layout.alignment: Qt.AlignVCenter
        clip: true
        opacity: isYielded ? 0.0 : 1.0
        visible: Services.Config ? Services.Config.showSysmonTray : true
        enabled: opacity > 0.5

        Behavior on Layout.preferredWidth { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
        Behavior on Layout.rightMargin { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
    }

    // ── 3. Volume Pill ────────────────────────────────────────────────────
    Rectangle {
        id: volPill

        readonly property int yieldIndex: root.yieldOrder.indexOf(volPill)
        readonly property bool isYielded: Services.OverlayManager.isLocked || (root.layoutTier >= 2 && yieldIndex < (root.layoutTier - 1))
        readonly property bool isCompact: root.layoutTier >= 1 && root.compactables.indexOf(volPill) !== -1

        property bool trayCompact: isCompact
        property bool trayYielded: isYielded

        readonly property int baseHPad: root.isMinimal ? 12 : 20
        readonly property int innerSpacing: root.isMinimal ? 4 : 6

        TextMetrics {
            id: mVolPct
            font.family: Services.Theme.fontMono
            font.pixelSize: root.isMinimal ? Services.Theme.fontSizeSm : Services.Theme.fontSizeMd
            text: "100%"
        }
        TextMetrics {
            id: mVolIcon
            font.family: Services.Theme.fontSymbols
            font.pixelSize: root.isMinimal ? Services.Theme.fontSizeMd : Services.Theme.fontSizeXl
            text: Services.Icons.volumeIcon(Services.Audio.volume, Services.Audio.muted, Services.Audio.isHeadphone, Services.Audio.isTws)
        }

        readonly property real trayWidthCompact: Math.ceil(mVolIcon.width) + baseHPad
        readonly property real trayWidthFull: trayWidthCompact + innerSpacing + Math.ceil(mVolPct.width)

        implicitHeight: root.pillHeight
        implicitWidth: trayWidthFull
        Layout.preferredWidth: isYielded ? 0 : (isCompact ? trayWidthCompact : trayWidthFull)
        Layout.preferredHeight: implicitHeight
        Layout.rightMargin: isYielded ? 0 : root.itemSpacing
        Layout.alignment: Qt.AlignVCenter
        clip: true
        radius: root.pillRadius
        color: root.getPillBg(volMouse.containsMouse || Services.OverlayManager.volumePanelVisible)
        border.color: root.getPillBorder(volMouse.containsMouse || Services.OverlayManager.volumePanelVisible)
        border.width: root.isMinimal ? 0 : 1
        
        opacity: isYielded ? 0.0 : 1.0
        visible: Services.Config ? Services.Config.showVolumeTray : true
        enabled: opacity > 0.5

        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on Layout.preferredWidth { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
        Behavior on Layout.rightMargin { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

        Item {
            id: volIconBox
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: root.isMinimal ? 6 : 10

            property string icon: Services.Icons.volumeIcon(Services.Audio.volume, Services.Audio.muted, Services.Audio.isHeadphone, Services.Audio.isTws)
            property string oldIcon: ""
            property color iconColor: (volMouse.containsMouse || Services.OverlayManager.volumePanelVisible) ? Services.Theme.accent : Services.Theme.textPrimary
            Behavior on iconColor { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

            implicitWidth: mainVolText.implicitWidth
            implicitHeight: mainVolText.implicitHeight

            onIconChanged: {
                if (icon !== mainVolText.text) {
                    oldIcon = mainVolText.text
                    oldVolText.opacity = 1.0
                    mainVolText.text = icon
                    mainVolText.opacity = 0.0
                    volCrossFade.restart()
                }
            }

            Component.onCompleted: mainVolText.text = icon

            Text {
                id: oldVolText
                anchors.centerIn: parent
                text: volIconBox.oldIcon
                font.family: Services.Theme.fontSymbols
                font.pixelSize: root.isMinimal ? Services.Theme.fontSizeMd : Services.Theme.fontSizeXl
                color: volIconBox.iconColor
                opacity: 0.0
                visible: opacity > 0
            }

            Text {
                id: mainVolText
                anchors.centerIn: parent
                font.family: Services.Theme.fontSymbols
                font.pixelSize: root.isMinimal ? Services.Theme.fontSizeMd : Services.Theme.fontSizeXl
                color: volIconBox.iconColor
                opacity: 1.0
            }

            ParallelAnimation {
                id: volCrossFade
                NumberAnimation { target: oldVolText; property: "opacity"; to: 0.0; duration: 200; easing.type: Easing.OutCubic }
                NumberAnimation { target: mainVolText; property: "opacity"; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
            }
        }

        Text {
            id: volPctText
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: volIconBox.right
            anchors.leftMargin: root.innerSpacing
            text: Math.round(Services.Audio.volume * 100) + "%"
            font.family: Services.Theme.fontMono
            font.pixelSize: root.isMinimal ? Services.Theme.fontSizeSm : Services.Theme.fontSizeMd
            color: (volMouse.containsMouse || Services.OverlayManager.volumePanelVisible) ? Services.Theme.accent : Services.Theme.textSecondary
            opacity: volPill.trayCompact ? 0.0 : 1.0
            visible: opacity > 0.01
            clip: true
            Behavior on opacity { NumberAnimation { duration: volPill.trayCompact ? 160 : 260; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            id: volMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                const centerX = volPill.mapToItem(null, volPill.width / 2, 0).x
                Services.OverlayManager.volumeTargetX = centerX
                const newState = !Services.OverlayManager.volumePanelVisible
                if (newState) Services.OverlayManager.closeAllExcept("volumePanel")
                Services.OverlayManager.volumePanelVisible = newState
            }
        }
    }

    // ── 4. Battery Pill (Anchor) ──────────────────────────────────────────
    Rectangle {
        id: batPill

        readonly property int yieldIndex: root.yieldOrder.indexOf(batPill)
        readonly property bool isYielded: Services.OverlayManager.isLocked || (root.layoutTier >= 2 && yieldIndex < (root.layoutTier - 1))

        property bool trayCompact: false
        property bool trayYielded: isYielded

        readonly property int baseHPad: root.isMinimal ? 12 : 20
        readonly property int innerSpacing: root.isMinimal ? 4 : 6

        TextMetrics {
            id: mBatPct
            font.family: Services.Theme.fontMono
            font.pixelSize: root.isMinimal ? Services.Theme.fontSizeSm : Services.Theme.fontSizeMd
            text: "100%"
        }
        TextMetrics {
            id: mBatIcon
            font.family: Services.Theme.fontSymbols
            font.pixelSize: root.isMinimal ? Services.Theme.fontSizeMd : Services.Theme.fontSizeXl
            text: Services.Icons.powerIcon(Services.Power.charging, Services.Power.percentage * 100)
        }

        readonly property real trayWidthFull: Math.ceil(mBatIcon.width) + baseHPad + innerSpacing + Math.ceil(mBatPct.width)
        readonly property real trayWidthCompact: trayWidthFull

        implicitHeight: root.pillHeight
        implicitWidth: trayWidthFull
        Layout.preferredWidth: isYielded ? 0 : trayWidthFull
        Layout.preferredHeight: implicitHeight
        Layout.rightMargin: isYielded ? 0 : root.itemSpacing
        Layout.alignment: Qt.AlignVCenter
        clip: true
        radius: root.pillRadius
        color: root.getPillBg(batMouse.containsMouse || Services.OverlayManager.batteryPanelVisible)
        border.color: root.getPillBorder(batMouse.containsMouse || Services.OverlayManager.batteryPanelVisible)
        border.width: root.isMinimal ? 0 : 1

        opacity: isYielded ? 0.0 : 1.0
        visible: Services.Config ? Services.Config.showBatteryTray : true
        enabled: opacity > 0.5

        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on Layout.preferredWidth { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
        Behavior on Layout.rightMargin { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

        RowLayout {
            id: batLayout
            anchors.centerIn: parent
            spacing: root.innerSpacing

            Text {
                id: batIconText
                text: Services.Icons.powerIcon(Services.Power.charging, Services.Power.percentage * 100)
                font.family: Services.Theme.fontSymbols
                font.pixelSize: root.isMinimal ? Services.Theme.fontSizeMd : Services.Theme.fontSizeXl
                color: Services.Power.isLow ? "#ff4444" : (Services.Power.isWarning ? "#e06c75" : (Services.PowerProfile.saverEnabled ? "#ff9800" : ((batMouse.containsMouse || Services.OverlayManager.batteryPanelVisible) ? Services.Theme.accent : Services.Theme.textPrimary)))
                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                SequentialAnimation {
                    id: blinkAnim
                    running: Services.Power.isLow
                    loops: Animation.Infinite
                    NumberAnimation { target: batIconText; property: "opacity"; to: 0.2; duration: 500; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: batIconText; property: "opacity"; to: 1.0; duration: 500; easing.type: Easing.InOutQuad }
                }

                Connections {
                    target: Services.Power
                    function onIsLowChanged() {
                        if (!Services.Power.isLow) {
                            batIconText.opacity = 1.0
                        }
                    }
                }
            }
            Text {
                id: batPctText
                text: Math.round(Services.Power.percentage * 100) + "%"
                font.family: Services.Theme.fontMono
                font.pixelSize: root.isMinimal ? Services.Theme.fontSizeSm : Services.Theme.fontSizeMd
                color: Services.Power.isLow ? "#ff4444" : (Services.Power.isWarning ? "#e06c75" : (Services.PowerProfile.saverEnabled ? "#ff9800" : ((batMouse.containsMouse || Services.OverlayManager.batteryPanelVisible) ? Services.Theme.accent : Services.Theme.textSecondary)))
                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
            }
        }

        MouseArea {
            id: batMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                const centerX = batPill.mapToItem(null, batPill.width / 2, 0).x
                Services.OverlayManager.batteryTargetX = centerX
                const newState = !Services.OverlayManager.batteryPanelVisible
                if (newState) Services.OverlayManager.closeAllExcept("batteryPanel")
                Services.OverlayManager.batteryPanelVisible = newState
            }
        }
    }

    // ── 5. Notification Bell & Control Center Pill ────────────────────────
    Rectangle {
        id: ctrlPill

        readonly property int yieldIndex: root.yieldOrder.indexOf(ctrlPill)
        readonly property bool isYielded: Services.OverlayManager.isLocked || (root.layoutTier >= 2 && yieldIndex < (root.layoutTier - 1))
        readonly property bool isCompact: false

        property bool trayCompact: false
        property bool trayYielded: isYielded

        readonly property real trayWidthFull: ctrlLayout.implicitWidth + (root.isMinimal ? 12 : 20)
        readonly property real trayWidthCompact: trayWidthFull

        implicitHeight: root.pillHeight
        implicitWidth: ctrlLayout.implicitWidth + (root.isMinimal ? 12 : 20)
        Layout.preferredWidth: isYielded ? 0 : trayWidthFull
        Layout.preferredHeight: implicitHeight
        Layout.rightMargin: isYielded ? 0 : root.itemSpacing
        Layout.alignment: Qt.AlignVCenter
        clip: true
        radius: root.pillRadius
        color: root.getPillBg(Services.OverlayManager.controlCenterVisible || Services.Notifications.centerVisible)
        border.color: root.getPillBorder(Services.OverlayManager.controlCenterVisible || Services.Notifications.centerVisible)
        border.width: root.isMinimal ? 0 : 1

        opacity: isYielded ? 0.0 : 1.0
        visible: Services.Config ? Services.Config.showControlCenterTray : true
        enabled: opacity > 0.5

        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on Layout.preferredWidth { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
        Behavior on Layout.rightMargin { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

        RowLayout {
            id: ctrlLayout
            anchors.centerIn: parent
            spacing: root.isMinimal ? 6 : 10

            Components.NotificationIndicator {}

            Rectangle {
                width: 1
                height: root.isMinimal ? 10 : 12
                color: Services.Theme.border
                opacity: 0.8
            }

            Components.ControlCenterToggle {}
        }
    }

    // ── 6. Clock & Date Pill ──────────────────────────────────────────────
    Components.ClockCenter {
        id: clockCenterPill
        hPadOverride: -1

        readonly property int yieldIndex: root.yieldOrder.indexOf(clockCenterPill)
        readonly property bool isYielded: Services.OverlayManager.isLocked || (root.layoutTier >= 2 && yieldIndex < (root.layoutTier - 1))

        trayCompact: false
        trayYielded: isYielded

        Layout.preferredWidth: isYielded ? 0 : trayWidthFull
        Layout.preferredHeight: implicitHeight
        Layout.rightMargin: 0
        Layout.alignment: Qt.AlignVCenter
        clip: true
        opacity: isYielded ? 0.0 : 1.0
        visible: root.isIslands && (Services.Config ? Services.Config.showClockTray : true)
        enabled: opacity > 0.5

        Behavior on Layout.preferredWidth { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
    }
}
