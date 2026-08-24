import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "../../services" as Services

PanelWindow {
    id: centerWin
    property string overlayId: "notifCenter"
    readonly property bool isBottom: Services.Config ? (Services.Config.barPosition === "bottom") : false
    readonly property int barTotalHeight: Services.Config ? (Services.Config.barStyle === "minimal" ? 30 : (Services.Config.barStyle === "unified" ? 38 : (Services.Config.barStyle === "floating" ? 46 : 36))) : 36

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusiveZone: 0
    visible: Services.Notifications.centerVisible
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:notifcenter"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region {
        Region {
            x: 0
            y: centerWin.isBottom ? 0 : centerWin.barTotalHeight
            width: centerWin.width
            height: centerWin.height - centerWin.barTotalHeight
        }
    }

    function hide() { Services.Notifications.centerVisible = false }
    function close() { hide() }

    Component.onCompleted: Services.OverlayManager.register(centerWin)

    Item {
        id: escFocus
        focus: centerWin.visible
        Keys.onEscapePressed: centerWin.hide()
    }
    // Local theme shorthand
    readonly property var t: Services.Theme

    // key: appName -> bool
    property var expandedGroups: ({})

    function isReplyAction(act) {
        if (!act) return false
        const id = (act.identifier || "").toLowerCase()
        const txt = (act.text || "").toLowerCase()
        return id.includes("reply") || id.includes("inline") || id.includes("respond") ||
               txt.includes("reply") || txt.includes("balas") || txt.includes("jawab") || txt.includes("respond")
    }

    function isBatteryNotification(item) {
        if (!item) return false
        const app = (item.appName || "").toLowerCase()
        const sum = (item.summary || "").toLowerCase()
        const bdy = (item.body || "").toLowerCase()
        return app.includes("battery") || app.includes("baterai") || app.includes("power") || app.includes("upower") || app.includes("system warning") ||
               sum.includes("battery") || sum.includes("baterai") || sum.includes("power") ||
               bdy.includes("battery") || bdy.includes("baterai")
    }

    function formatTime(ts) {
        if (!ts) return ""
        const d = new Date(ts)
        const now = new Date()
        const diffSec = Math.floor((now - d) / 1000)
        if (diffSec < 15) return "Just now"
        if (diffSec < 60) return Math.floor(diffSec) + "s ago"
        if (diffSec < 3600) return Math.floor(diffSec / 60) + "m ago"
        if (diffSec < 86400 && d.getDate() === now.getDate()) return Qt.formatTime(d, "hh:mm")
        const yesterday = new Date(now)
        yesterday.setDate(now.getDate() - 1)
        if (d.toDateString() === yesterday.toDateString())
            return "Yesterday " + Qt.formatTime(d, "hh:mm")
        return Qt.formatDateTime(d, "dd/MM hh:mm")
    }

    // Group notifications by appName (ordered by most recent notification per app)
    property var groupedHistory: {
        const count = Services.Notifications.historyList.count
        const groups = []
        const appMap = {}
        for (let i = 0; i < count; i++) {
            const item = Services.Notifications.historyList.get(i)
            if (!item) continue
            const app = item.appName || "Unknown"
            if (appMap[app] !== undefined) {
                const grp = groups[appMap[app]]
                grp.items.push(item)
                if (!grp.appIcon && item.appIcon) grp.appIcon = item.appIcon
            } else {
                const grp = {
                    appName: app,
                    appIcon: item.appIcon || "",
                    items: [item]
                }
                appMap[app] = groups.length
                groups.push(grp)
            }
        }
        return groups
    }

    // Backdrop click overlay
    MouseArea {
        anchors.fill: parent
        onClicked: Services.Notifications.centerVisible = false
    }

    Rectangle {
        id: panel
        anchors.right: parent.right
        anchors.rightMargin: 12
        y: centerWin.isBottom ? (parent.height - height - 12) : 12
        width: 390
        height: Math.max(480, Math.min(mainCol.implicitHeight + 20, Math.min(690, parent.height - 24)))
        radius: 16
        color: centerWin.t.surface
        border.color: centerWin.t.border
        border.width: 1
        clip: true

        opacity: Services.Notifications.centerVisible ? 1 : 0
        transform: Translate {
            y: Services.Notifications.centerVisible ? 0 : (centerWin.isBottom ? 32 : -32)
            Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 0.5 } }
        }
        scale: Services.Notifications.centerVisible ? 1 : 0.96
        Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent; onClicked: {} }

        ColumnLayout {
            id: mainCol
            anchors.fill: parent
            spacing: 0

            // ── Header ──────────────────────────────────────────────
            RowLayout {
                id: headerSection
                Layout.fillWidth: true
                Layout.topMargin: 14
                Layout.bottomMargin: 12
                Layout.leftMargin: 16
                Layout.rightMargin: 14
                spacing: 8

                RowLayout {
                    spacing: 8

                    Text {
                        text: "Notifications"
                        color: centerWin.t.textPrimary
                        font.bold: true
                        font.pixelSize: 15
                        font.letterSpacing: 0.2
                    }

                    // Total notification count badge
                    Rectangle {
                        visible: Services.Notifications.historyList.count > 0
                        implicitWidth: totalCountTxt.implicitWidth + 10
                        implicitHeight: 18
                        radius: 9
                        color: centerWin.t.surfaceVariant
                        border.color: centerWin.t.border
                        border.width: 1

                        Text {
                            id: totalCountTxt
                            anchors.centerIn: parent
                            text: Services.Notifications.historyList.count
                            color: centerWin.t.accent
                            font.pixelSize: 10
                            font.bold: true
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // DnD Toggle Button
                Rectangle {
                    implicitWidth: 32
                    implicitHeight: 32
                    radius: 9
                    color: dndHover.containsMouse
                        ? (Services.Notifications.doNotDisturb ? "#d94a60" : centerWin.t.bgHover)
                        : (Services.Notifications.doNotDisturb ? centerWin.t.danger : centerWin.t.surfaceVariant)
                    border.color: Services.Notifications.doNotDisturb ? centerWin.t.danger : centerWin.t.border
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                    Text {
                        anchors.centerIn: parent
                        text: Services.Notifications.doNotDisturb ? "󰂛" : "󰂚"
                        color: Services.Notifications.doNotDisturb ? "#ffffff" : centerWin.t.textPrimary
                        font.pixelSize: 14
                    }

                    MouseArea {
                        id: dndHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Services.Notifications.doNotDisturb = !Services.Notifications.doNotDisturb
                    }
                }

                // Clear All Button
                Rectangle {
                    implicitWidth: 32
                    implicitHeight: 32
                    radius: 9
                    color: clearHover.containsMouse ? centerWin.t.bgHover : centerWin.t.surfaceVariant
                    border.color: centerWin.t.border
                    border.width: 1
                    opacity: Services.Notifications.historyList.count > 0 ? 1 : 0.4
                    enabled: Services.Notifications.historyList.count > 0

                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰎟"
                        color: clearHover.containsMouse ? centerWin.t.textPrimary : centerWin.t.textSecondary
                        font.pixelSize: 14
                    }

                    MouseArea {
                        id: clearHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Services.Notifications.clearHistory()
                            centerWin.expandedGroups = ({})
                        }
                    }
                }
            }

            // Header Separator
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: centerWin.t.border
                opacity: 0.6
            }

            // ── Notification List ───────────────────────────────────
            ListView {
                id: historyView
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.bottomMargin: 12
                clip: true
                spacing: 8
                topMargin: 8
                bottomMargin: 6
                leftMargin: 12
                rightMargin: 12
                boundsBehavior: Flickable.StopAtBounds
                model: centerWin.groupedHistory

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle {
                        implicitWidth: 4
                        radius: 2
                        color: centerWin.t.borderHighlight
                    }
                }

                displaced: Transition {
                    NumberAnimation { properties: "y"; duration: 380; easing.type: Easing.OutExpo }
                }

                delegate: Rectangle {
                    id: groupCard
                    required property var modelData
                    property var group: modelData
                    property var primaryItem: (group && group.items && group.items.length > 0) ? group.items[0] : null
                    property bool isMulti: group && group.items && group.items.length > 1
                    property bool expanded: isMulti && centerWin.expandedGroups[group.appName] === true
                    property bool isBatteryGroup: primaryItem ? centerWin.isBatteryNotification(primaryItem) : false
                    property bool isCritical: primaryItem ? (primaryItem.urgency === 2 || isBatteryGroup) : false
                    property bool replyMode: false
                    property string activeReplyActionId: ""

                    property real expandProgress: expanded ? 1.0 : 0.0
                    Behavior on expandProgress { NumberAnimation { duration: 380; easing.type: Easing.OutExpo } }

                    width: historyView.width - 24
                    implicitHeight: cardContent.implicitHeight + 20
                    height: implicitHeight
                    radius: 14
                    color: centerWin.t.surfaceVariant
                    border.color: isBatteryGroup ? centerWin.t.warning : (groupCard.isCritical ? centerWin.t.danger : centerWin.t.border)
                    border.width: 1
                    clip: true

                    // Left strip for system warnings & critical alerts
                    Rectangle {
                        visible: groupCard.isCritical || groupCard.isBatteryGroup
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        width: 3.5
                        radius: 2
                        color: groupCard.isBatteryGroup ? centerWin.t.warning : centerWin.t.danger
                    }

                    ColumnLayout {
                        id: cardContent
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                        spacing: 8

                        // ── 1. UNIFIED HEADER ROW ──────────────────────────────
                        RowLayout {
                            id: headerRow
                            Layout.fillWidth: true
                            spacing: 6

                            // Expandable Header Pill (interactive button if multi-item)
                            Rectangle {
                                id: headerPill
                                Layout.fillWidth: true
                                Layout.preferredHeight: 28
                                radius: 8
                                color: (headerMouse.containsMouse && groupCard.isMulti) ? centerWin.t.bgHover : "transparent"
                                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                MouseArea {
                                    id: headerMouse
                                    anchors.fill: parent
                                    enabled: groupCard.isMulti
                                    hoverEnabled: groupCard.isMulti
                                    cursorShape: groupCard.isMulti ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        if (!groupCard.isMulti) return
                                        const copy = Object.assign({}, centerWin.expandedGroups)
                                        copy[groupCard.group.appName] = !groupCard.expanded
                                        centerWin.expandedGroups = copy
                                    }
                                }

                                RowLayout {
                                    anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
                                    spacing: 7

                                    // App Icon Squircle Container
                                    Item {
                                        Layout.preferredWidth: 22
                                        Layout.preferredHeight: 22
                                        Layout.alignment: Qt.AlignVCenter

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 6
                                            color: centerWin.t.bgHover
                                            border.color: centerWin.t.border
                                            border.width: 1
                                            visible: hIcon.status !== Image.Ready

                                            Text {
                                                anchors.centerIn: parent
                                                text: (groupCard.group.appName || "?").charAt(0).toUpperCase()
                                                color: centerWin.t.textPrimary
                                                font.bold: true
                                                font.pixelSize: 10
                                            }
                                        }

                                        Image {
                                            id: hIcon
                                            anchors.fill: parent
                                            source: {
                                                const icon = groupCard.group.appIcon
                                                if (!icon) return ""
                                                if (icon.startsWith("/") || icon.startsWith("file://") || icon.startsWith("http"))
                                                    return icon
                                                if (Services.SystemTheme) {
                                                    const res = Services.SystemTheme.getIcon(icon)
                                                    if (res) return res
                                                }
                                                return Quickshell.iconPath(icon, true)
                                            }
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true
                                            cache: false
                                            sourceSize: Qt.size(32, 32)
                                            visible: status === Image.Ready
                                        }
                                    }

                                    // App Name
                                    Text {
                                        text: groupCard.group.appName
                                        color: centerWin.t.textPrimary
                                        font.pixelSize: 11
                                        font.bold: true
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    // System Warning Pill Tag (for Battery Warning)
                                    Rectangle {
                                        visible: groupCard.isBatteryGroup
                                        implicitWidth: sysWarnTxt.implicitWidth + 8
                                        implicitHeight: 16
                                        radius: 8
                                        color: Qt.rgba(centerWin.t.warning.r, centerWin.t.warning.g, centerWin.t.warning.b, 0.2)
                                        border.color: centerWin.t.warning
                                        border.width: 1
                                        Layout.alignment: Qt.AlignVCenter

                                        RowLayout {
                                            id: sysWarnTxt
                                            anchors.centerIn: parent
                                            spacing: 3

                                            Text { text: "󰂃"; color: centerWin.t.warning; font.pixelSize: 10 }
                                            Text { text: "System Warning"; color: centerWin.t.warning; font.pixelSize: 9; font.bold: true }
                                        }
                                    }

                                    // Multi-item Count Badge (only if isMulti)
                                    Rectangle {
                                        visible: groupCard.isMulti
                                        height: 18
                                        implicitWidth: badgeText.implicitWidth + 10
                                        radius: 9
                                        color: groupCard.expanded
                                            ? centerWin.t.accent
                                            : Qt.rgba(centerWin.t.accent.r, centerWin.t.accent.g, centerWin.t.accent.b, 0.15)
                                        border.color: groupCard.expanded
                                            ? centerWin.t.accent
                                            : Qt.rgba(centerWin.t.accent.r, centerWin.t.accent.g, centerWin.t.accent.b, 0.3)
                                        border.width: 1
                                        Layout.alignment: Qt.AlignVCenter
                                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                        Text {
                                            id: badgeText
                                            anchors.centerIn: parent
                                            text: groupCard.group.items.length
                                            color: groupCard.expanded ? centerWin.t.bgOnAccent : centerWin.t.accent
                                            font.pixelSize: 10
                                            font.bold: true
                                            Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                        }
                                    }

                                    // Chevron expand/collapse icon (only if isMulti)
                                    Item {
                                        visible: groupCard.isMulti
                                        Layout.preferredWidth: 14
                                        Layout.preferredHeight: 14
                                        Layout.alignment: Qt.AlignVCenter

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰅀"
                                            color: groupCard.expanded ? centerWin.t.accent : centerWin.t.textDisabled
                                            font.pixelSize: 12
                                            transformOrigin: Item.Center
                                            rotation: -90 * (1.0 - groupCard.expandProgress)
                                            Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    // Timestamp of latest notification
                                    Text {
                                        text: groupCard.primaryItem ? centerWin.formatTime(groupCard.primaryItem.time) : ""
                                        color: centerWin.t.textDisabled
                                        font.pixelSize: 10
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }
                            }

                            // Dismiss Group Button ×
                            Item {
                                width: 22
                                height: 22
                                Layout.alignment: Qt.AlignVCenter

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 6
                                    color: groupDismissBtn.containsMouse ? centerWin.t.bgHover : "transparent"
                                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: "\u00d7"
                                    color: groupDismissBtn.containsMouse ? centerWin.t.textPrimary : centerWin.t.textDisabled
                                    font.pixelSize: 15
                                    font.bold: true
                                }
                                MouseArea {
                                    id: groupDismissBtn
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (groupCard.isMulti) {
                                            Services.Notifications.dismissGroupFromCenter(groupCard.group.items)
                                        } else if (groupCard.primaryItem) {
                                            Services.Notifications.dismissFromCenter(groupCard.primaryItem.notifId)
                                        }
                                    }
                                }
                            }
                        }

                        // ── 2. PRIMARY NOTIFICATION (Item 0) ────────────────────
                        ColumnLayout {
                            id: primaryNotifCol
                            visible: groupCard.primaryItem !== null
                            Layout.fillWidth: true
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                // Thumbnail / Image if present
                                Image {
                                    id: primaryImg
                                    property string imgPath: (groupCard.primaryItem && groupCard.primaryItem.image) ? groupCard.primaryItem.image : ""
                                    visible: imgPath.length > 0 && status === Image.Ready
                                    source: {
                                        if (!imgPath) return ""
                                        if (imgPath.startsWith("/") || imgPath.startsWith("file://") || imgPath.startsWith("http"))
                                            return imgPath
                                        return Quickshell.iconPath(imgPath, true)
                                    }
                                    Layout.preferredWidth: 38
                                    Layout.preferredHeight: 38
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    sourceSize: Qt.size(76, 76)
                                    clip: true
                                    Layout.alignment: Qt.AlignTop
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Text {
                                            visible: groupCard.primaryItem && (groupCard.primaryItem.summary || "").length > 0
                                            text: groupCard.primaryItem ? (groupCard.primaryItem.summary || "") : ""
                                            color: centerWin.t.textPrimary
                                            font.bold: true
                                            font.pixelSize: 12
                                            wrapMode: Text.Wrap
                                            Layout.fillWidth: true
                                        }

                                        // "Latest" pill tag when group is expanded
                                        Rectangle {
                                            visible: groupCard.isMulti && groupCard.expanded
                                            height: 15
                                            implicitWidth: latestTagTxt.implicitWidth + 8
                                            radius: 4
                                            color: Qt.rgba(centerWin.t.accent.r, centerWin.t.accent.g, centerWin.t.accent.b, 0.12)
                                            Layout.alignment: Qt.AlignTop
                                            Text {
                                                id: latestTagTxt
                                                anchors.centerIn: parent
                                                text: "Latest"
                                                color: centerWin.t.accent
                                                font.pixelSize: 9
                                                font.bold: true
                                            }
                                        }

                                        // Individual Dismiss Button for Item 0 (only when expanded in multi-group)
                                        Item {
                                            visible: groupCard.isMulti && groupCard.expanded
                                            width: 18
                                            height: 18
                                            Layout.alignment: Qt.AlignTop

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 5
                                                color: pItemDismissBtn.containsMouse ? centerWin.t.bgHover : "transparent"
                                                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                            }
                                            Text {
                                                anchors.centerIn: parent
                                                text: "\u00d7"
                                                color: pItemDismissBtn.containsMouse ? centerWin.t.textPrimary : centerWin.t.textDisabled
                                                font.pixelSize: 14
                                                font.bold: true
                                            }
                                            MouseArea {
                                                id: pItemDismissBtn
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    Services.Notifications.dismissFromCenter(groupCard.primaryItem.notifId)
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        visible: groupCard.primaryItem && (groupCard.primaryItem.body || "").length > 0
                                        text: groupCard.primaryItem ? (groupCard.primaryItem.body || "") : ""
                                        color: centerWin.t.textSecondary
                                        font.pixelSize: 11
                                        maximumLineCount: (groupCard.isMulti && !groupCard.expanded) ? 2 : 4
                                        elide: Text.ElideRight
                                        wrapMode: Text.Wrap
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            // Primary Notification Actions Row (when not replying)
                            RowLayout {
                                readonly property var actList: groupCard.primaryItem ? groupCard.primaryItem.actions : null
                                readonly property int actCount: actList ? (actList.count !== undefined ? actList.count : (actList.length !== undefined ? actList.length : 0)) : 0
                                visible: actCount > 0 && !groupCard.replyMode
                                spacing: 6
                                Layout.topMargin: 2

                                Repeater {
                                    model: parent.actList
                                    delegate: Rectangle {
                                        id: pActBtn
                                        required property string identifier
                                        required property string text
                                        radius: 6
                                        color: pActHover.containsMouse ? centerWin.t.bgHover : centerWin.t.surface
                                        border.color: centerWin.t.border
                                        border.width: 1
                                        implicitHeight: 24
                                        implicitWidth: pActLabel.implicitWidth + 16
                                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                        Text {
                                            id: pActLabel
                                            anchors.centerIn: parent
                                            text: pActBtn.text
                                            color: centerWin.t.textPrimary
                                            font.pixelSize: 11
                                        }
                                        MouseArea {
                                            id: pActHover
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (centerWin.isReplyAction(pActBtn)) {
                                                    groupCard.activeReplyActionId = pActBtn.identifier
                                                    groupCard.replyMode = true
                                                    Qt.callLater(() => pReplyInput.forceActiveFocus())
                                                } else {
                                                    Services.Notifications.invokeAction(
                                                        groupCard.primaryItem.notifId, pActBtn.identifier)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Primary Notification Inline Reply Area
                            ColumnLayout {
                                visible: groupCard.replyMode
                                Layout.fillWidth: true
                                spacing: 6
                                Layout.topMargin: 2

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 32
                                    radius: 7
                                    color: centerWin.t.bgHover
                                    border.color: pReplyInput.activeFocus ? centerWin.t.accent : centerWin.t.border
                                    border.width: 1

                                    TextInput {
                                        id: pReplyInput
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        color: centerWin.t.textPrimary
                                        font.pixelSize: 11
                                        clip: true
                                        focus: groupCard.replyMode

                                        Text {
                                            text: "Write a reply..."
                                            color: centerWin.t.textDisabled
                                            font.pixelSize: 11
                                            visible: pReplyInput.text.length === 0 && !pReplyInput.activeFocus
                                        }

                                        Keys.onReturnPressed: {
                                            if (pReplyInput.text.trim().length > 0) {
                                                Services.Notifications.invokeAction(
                                                    groupCard.primaryItem.notifId,
                                                    groupCard.activeReplyActionId,
                                                    pReplyInput.text.trim()
                                                )
                                                groupCard.replyMode = false
                                                pReplyInput.text = ""
                                            }
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Item { Layout.fillWidth: true }

                                    // Cancel Button
                                    Rectangle {
                                        implicitHeight: 22
                                        implicitWidth: pCancelTxt.implicitWidth + 14
                                        radius: 6
                                        color: pCancelMouse.containsMouse ? centerWin.t.bgHover : centerWin.t.surface
                                        border.color: centerWin.t.border
                                        border.width: 1

                                        Text {
                                            id: pCancelTxt
                                            anchors.centerIn: parent
                                            text: "Cancel"
                                            color: centerWin.t.textSecondary
                                            font.pixelSize: 10
                                            font.bold: true
                                        }

                                        MouseArea {
                                            id: pCancelMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                groupCard.replyMode = false
                                                pReplyInput.text = ""
                                            }
                                        }
                                    }

                                    // Send Button
                                    Rectangle {
                                        implicitHeight: 22
                                        implicitWidth: pSendRow.implicitWidth + 16
                                        radius: 6
                                        color: pSendMouse.containsMouse ? Qt.lighter(centerWin.t.accent, 1.1) : centerWin.t.accent

                                        RowLayout {
                                            id: pSendRow
                                            anchors.centerIn: parent
                                            spacing: 4

                                            Text {
                                                text: "Send"
                                                font.family: Services.Theme.fontMono
                                                color: Services.Theme.bgOnAccent
                                                font.pixelSize: 10
                                                font.bold: true
                                            }

                                            Text {
                                                text: Services.Icons.send || "\uf1d8"
                                                font.family: Services.Theme.fontSymbols
                                                color: Services.Theme.bgOnAccent
                                                font.pixelSize: 10
                                            }
                                        }

                                        MouseArea {
                                            id: pSendMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (pReplyInput.text.trim().length > 0) {
                                                    const msg = pReplyInput.text.trim()
                                                    const nId = groupCard.primaryItem.notifId
                                                    const aId = groupCard.activeReplyActionId
                                                    groupCard.replyMode = false
                                                    pReplyInput.text = ""
                                                    Services.Notifications.invokeAction(nId, aId, msg)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ── 3. MULTI-ITEM ACCORDION (Peek Pill + Thread History) ──
                        Item {
                            id: groupAccordion
                            visible: groupCard.isMulti
                            Layout.fillWidth: true
                            Layout.preferredHeight: implicitHeight
                            implicitHeight: Math.round(
                                (1.0 - groupCard.expandProgress) * (stackPeekPill.implicitHeight) +
                                groupCard.expandProgress * olderItemsCol.implicitHeight
                            )
                            clip: true

                            // 1. Collapsed Peek Pill (smooth crossfade out)
                            Rectangle {
                                id: stackPeekPill
                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                height: stackPeekContent.implicitHeight + 8
                                implicitHeight: height
                                radius: 8
                                color: peekMouse.containsMouse ? centerWin.t.bgHover : centerWin.t.surface
                                border.color: centerWin.t.border
                                border.width: 1
                                opacity: Math.max(0.0, 1.0 - groupCard.expandProgress * 2.2)
                                visible: opacity > 0.01
                                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                RowLayout {
                                    id: stackPeekContent
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 4; leftMargin: 8; rightMargin: 8 }
                                    spacing: 6

                                    Text {
                                        text: "󰅟"
                                        color: centerWin.t.textDisabled
                                        font.pixelSize: 11
                                    }

                                    Text {
                                        text: (groupCard.group && groupCard.group.items && groupCard.group.items.length > 1 && groupCard.group.items[1]) ? (groupCard.group.items[1].summary || groupCard.group.items[1].body || "") : ""
                                        color: centerWin.t.textSecondary
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Rectangle {
                                        implicitWidth: olderCountTxt.implicitWidth + 8
                                        implicitHeight: 16
                                        radius: 4
                                        color: Qt.rgba(centerWin.t.accent.r, centerWin.t.accent.g, centerWin.t.accent.b, 0.12)

                                        Text {
                                            id: olderCountTxt
                                            anchors.centerIn: parent
                                            text: "+" + (groupCard.group.items.length - 1) + " older"
                                            color: centerWin.t.accent
                                            font.pixelSize: 10
                                            font.bold: true
                                        }
                                    }
                                }

                                MouseArea {
                                    id: peekMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const copy = Object.assign({}, centerWin.expandedGroups)
                                        copy[groupCard.group.appName] = true
                                        centerWin.expandedGroups = copy
                                    }
                                }
                            }

                            // 2. Expanded Older Items Thread (smooth slide & fade in)
                            ColumnLayout {
                                id: olderItemsCol
                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                spacing: 6
                                opacity: Math.min(1.0, Math.max(0.0, (groupCard.expandProgress - 0.15) / 0.85))
                                visible: groupCard.expandProgress > 0.02
                                transform: Translate { y: (1.0 - groupCard.expandProgress) * -12 }

                                Repeater {
                                    model: groupCard.isMulti ? groupCard.group.items.slice(1) : []
                                    delegate: ColumnLayout {
                                        id: olderItemDelegate
                                        required property var modelData
                                        property var notifItem: modelData
                                        property bool itemReplyMode: false
                                        property string itemReplyActionId: ""
                                        property bool isBatteryItem: centerWin.isBatteryNotification(notifItem)
                                        property bool isItemCritical: notifItem.urgency === 2 || isBatteryItem

                                        Layout.fillWidth: true
                                        spacing: 6

                                        // Hairline Divider between thread messages
                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 1
                                            color: centerWin.t.border
                                            opacity: 0.65
                                            Layout.topMargin: 4
                                            Layout.bottomMargin: 4
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            Image {
                                                id: olderNotifImg
                                                property string imgPath: olderItemDelegate.notifItem.image || ""
                                                visible: imgPath.length > 0 && status === Image.Ready
                                                source: {
                                                    if (!imgPath) return ""
                                                    if (imgPath.startsWith("/") || imgPath.startsWith("file://") || imgPath.startsWith("http"))
                                                        return imgPath
                                                    return Quickshell.iconPath(imgPath, true)
                                                }
                                                Layout.preferredWidth: 34
                                                Layout.preferredHeight: 34
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true
                                                cache: true
                                                sourceSize: Qt.size(68, 68)
                                                clip: true
                                                Layout.alignment: Qt.AlignTop
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 6

                                                    Text {
                                                        text: olderItemDelegate.notifItem.summary || ""
                                                        color: centerWin.t.textPrimary
                                                        font.bold: true
                                                        font.pixelSize: 12
                                                        wrapMode: Text.Wrap
                                                        Layout.fillWidth: true
                                                    }

                                                    Text {
                                                        text: centerWin.formatTime(olderItemDelegate.notifItem.time)
                                                        color: centerWin.t.textDisabled
                                                        font.pixelSize: 10
                                                        Layout.alignment: Qt.AlignTop
                                                    }

                                                    Item {
                                                        width: 18
                                                        height: 18
                                                        Layout.alignment: Qt.AlignTop

                                                        Rectangle {
                                                            anchors.fill: parent
                                                            radius: 5
                                                            color: olderDismissBtn.containsMouse ? centerWin.t.bgHover : "transparent"
                                                            Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                                        }
                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: "\u00d7"
                                                            color: olderDismissBtn.containsMouse ? centerWin.t.textPrimary : centerWin.t.textDisabled
                                                            font.pixelSize: 14
                                                            font.bold: true
                                                        }
                                                        MouseArea {
                                                            id: olderDismissBtn
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                Services.Notifications.dismissFromCenter(olderItemDelegate.notifItem.notifId)
                                                            }
                                                        }
                                                    }
                                                }

                                                Text {
                                                    visible: (olderItemDelegate.notifItem.body || "").length > 0
                                                    text: olderItemDelegate.notifItem.body || ""
                                                    color: centerWin.t.textSecondary
                                                    font.pixelSize: 11
                                                    wrapMode: Text.Wrap
                                                    Layout.fillWidth: true
                                                }
                                            }
                                        }

                                        // Older Item Actions Row
                                        RowLayout {
                                            readonly property var actList: olderItemDelegate.notifItem.actions
                                            readonly property int actCount: actList ? (actList.count !== undefined ? actList.count : (actList.length !== undefined ? actList.length : 0)) : 0
                                            visible: actCount > 0 && !olderItemDelegate.itemReplyMode
                                            spacing: 6
                                            Layout.topMargin: 2

                                            Repeater {
                                                model: parent.actList
                                                delegate: Rectangle {
                                                    id: oActBtn
                                                    required property string identifier
                                                    required property string text
                                                    radius: 6
                                                    color: oActHover.containsMouse ? centerWin.t.bgHover : centerWin.t.surface
                                                    border.color: centerWin.t.border
                                                    border.width: 1
                                                    implicitHeight: 24
                                                    implicitWidth: oActLabel.implicitWidth + 16
                                                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                                    Text {
                                                        id: oActLabel
                                                        anchors.centerIn: parent
                                                        text: oActBtn.text
                                                        color: centerWin.t.textPrimary
                                                        font.pixelSize: 11
                                                    }
                                                    MouseArea {
                                                        id: oActHover
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (centerWin.isReplyAction(oActBtn)) {
                                                                olderItemDelegate.itemReplyActionId = oActBtn.identifier
                                                                olderItemDelegate.itemReplyMode = true
                                                                Qt.callLater(() => oReplyInput.forceActiveFocus())
                                                            } else {
                                                                Services.Notifications.invokeAction(
                                                                    olderItemDelegate.notifItem.notifId, oActBtn.identifier)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // Older Item Inline Reply Area
                                        ColumnLayout {
                                            visible: olderItemDelegate.itemReplyMode
                                            Layout.fillWidth: true
                                            spacing: 6
                                            Layout.topMargin: 2

                                            Rectangle {
                                                Layout.fillWidth: true
                                                implicitHeight: 32
                                                radius: 7
                                                color: centerWin.t.bgHover
                                                border.color: oReplyInput.activeFocus ? centerWin.t.accent : centerWin.t.border
                                                border.width: 1

                                                TextInput {
                                                    id: oReplyInput
                                                    anchors.fill: parent
                                                    anchors.margins: 6
                                                    color: centerWin.t.textPrimary
                                                    font.pixelSize: 11
                                                    clip: true
                                                    focus: olderItemDelegate.itemReplyMode

                                                    Text {
                                                        text: "Write a reply..."
                                                        color: centerWin.t.textDisabled
                                                        font.pixelSize: 11
                                                        visible: oReplyInput.text.length === 0 && !oReplyInput.activeFocus
                                                    }

                                                    Keys.onReturnPressed: {
                                                        if (oReplyInput.text.trim().length > 0) {
                                                            Services.Notifications.invokeAction(
                                                                olderItemDelegate.notifItem.notifId,
                                                                olderItemDelegate.itemReplyActionId,
                                                                oReplyInput.text.trim()
                                                            )
                                                            olderItemDelegate.itemReplyMode = false
                                                            oReplyInput.text = ""
                                                        }
                                                    }
                                                }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 6

                                                Item { Layout.fillWidth: true }

                                                Rectangle {
                                                    implicitHeight: 22
                                                    implicitWidth: oCancelTxt.implicitWidth + 14
                                                    radius: 6
                                                    color: oCancelMouse.containsMouse ? centerWin.t.bgHover : centerWin.t.surface
                                                    border.color: centerWin.t.border
                                                    border.width: 1

                                                    Text {
                                                        id: oCancelTxt
                                                        anchors.centerIn: parent
                                                        text: "Cancel"
                                                        color: centerWin.t.textSecondary
                                                        font.pixelSize: 10
                                                        font.bold: true
                                                    }

                                                    MouseArea {
                                                        id: oCancelMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            olderItemDelegate.itemReplyMode = false
                                                            oReplyInput.text = ""
                                                        }
                                                    }
                                                }

                                                Rectangle {
                                                    implicitHeight: 22
                                                    implicitWidth: oSendRow.implicitWidth + 16
                                                    radius: 6
                                                    color: oSendMouse.containsMouse ? Qt.lighter(centerWin.t.accent, 1.1) : centerWin.t.accent

                                                    RowLayout {
                                                        id: oSendRow
                                                        anchors.centerIn: parent
                                                        spacing: 4

                                                        Text {
                                                            text: "Send"
                                                            font.family: Services.Theme.fontMono
                                                            color: Services.Theme.bgOnAccent
                                                            font.pixelSize: 10
                                                            font.bold: true
                                                        }

                                                        Text {
                                                            text: Services.Icons.send || "\uf1d8"
                                                            font.family: Services.Theme.fontSymbols
                                                            color: Services.Theme.bgOnAccent
                                                            font.pixelSize: 10
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: oSendMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (oReplyInput.text.trim().length > 0) {
                                                                Services.Notifications.invokeAction(
                                                                    olderItemDelegate.notifItem.notifId,
                                                                    olderItemDelegate.itemReplyActionId,
                                                                    oReplyInput.text.trim()
                                                                )
                                                                olderItemDelegate.itemReplyMode = false
                                                                oReplyInput.text = ""
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

                // ── Empty State ─────────────────────────────────────
                ColumnLayout {
                    visible: historyView.count === 0
                    anchors.centerIn: parent
                    spacing: 12

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 56
                        implicitHeight: 56
                        radius: 28
                        color: centerWin.t.surfaceVariant
                        border.color: centerWin.t.border
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "󰂚"
                            color: centerWin.t.textDisabled
                            font.pixelSize: 26
                        }
                    }

                    ColumnLayout {
                        spacing: 3
                        Layout.alignment: Qt.AlignHCenter

                        Text {
                            text: "No Notifications"
                            color: centerWin.t.textPrimary
                            font.pixelSize: 13
                            font.bold: true
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Text {
                            text: "You're all caught up!"
                            color: centerWin.t.textDisabled
                            font.pixelSize: 11
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
            }
        }
    }
}
