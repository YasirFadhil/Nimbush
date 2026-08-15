import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "../../services" as Services

PanelWindow {
    id: centerWin
    property string overlayId: "notifCenter"
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusiveZone: 0
    visible: Services.Notifications.centerVisible
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:notifcenter"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

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

    // Group sequential notifications with same appName
    property var groupedHistory: {
        const count = Services.Notifications.historyList.count
        const groups = []
        let current = null
        for (let i = 0; i < count; i++) {
            const item = Services.Notifications.historyList.get(i)
            if (current && current.appName === item.appName) {
                current.items.push(item)
            } else {
                current = { appName: item.appName, appIcon: item.appIcon, items: [item] }
                groups.push(current)
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
        anchors { top: parent.top; right: parent.right }
        anchors.rightMargin: 12
        anchors.topMargin: 12
        width: 390
        height: Math.max(480, Math.min(mainCol.implicitHeight + 20, 690))
        radius: 16
        color: centerWin.t.surface
        border.color: centerWin.t.border
        border.width: 1

        opacity: Services.Notifications.centerVisible ? 1 : 0
        y: Services.Notifications.centerVisible ? 0 : -20
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 0.5 } }

        MouseArea { anchors.fill: parent; onClicked: {} }

        ColumnLayout {
            id: mainCol
            anchors.fill: parent
            spacing: 0

            // ── Header ──────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 14
                Layout.bottomMargin: 12
                Layout.leftMargin: 16
                Layout.rightMargin: 14
                spacing: 10

                RowLayout {
                    spacing: 8
                    Layout.fillWidth: true

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

                    Behavior on color { ColorAnimation { duration: 120 } }

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

                    Behavior on color { ColorAnimation { duration: 120 } }

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
                clip: true
                spacing: 8
                topMargin: 10
                bottomMargin: 12
                leftMargin: 12
                rightMargin: 12
                model: centerWin.groupedHistory

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle {
                        implicitWidth: 4
                        radius: 2
                        color: centerWin.t.borderHighlight
                    }
                }

                delegate: Rectangle {
                    id: groupCard
                    required property var modelData
                    property var group: modelData
                    property bool isMulti: group.items.length > 1
                    property bool expanded: !isMulti || centerWin.expandedGroups[group.appName] === true
                    property bool isBatteryGroup: centerWin.isBatteryNotification(group.items[0])
                    property bool isCritical: group.items[0].urgency === 2 || isBatteryGroup
                    property bool singleReplyMode: false
                    property string singleReplyActionId: ""

                    width: historyView.width - 24
                    implicitHeight: groupCard.isMulti ? (groupContent.implicitHeight + 20) : (singleContent.implicitHeight + 20)
                    radius: 12
                    color: centerWin.t.surfaceVariant
                    border.color: isBatteryGroup ? centerWin.t.warning : (groupCard.isCritical ? centerWin.t.danger : centerWin.t.border)
                    border.width: 1

                    // Left strip for system warnings & critical alerts
                    Rectangle {
                        visible: groupCard.isCritical || groupCard.isBatteryGroup
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        width: 3.5
                        radius: 2
                        color: groupCard.isBatteryGroup ? centerWin.t.warning : centerWin.t.danger
                    }

                    // ── 1. SINGLE NOTIFICATION CARD (When !isMulti) ──────────────────
                    ColumnLayout {
                        id: singleContent
                        visible: !groupCard.isMulti
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                        spacing: 6

                        // Header Row: App Icon + App Name + Warning Tag + Time + Dismiss ×
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

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
                                    visible: sIcon.status !== Image.Ready

                                    Text {
                                        anchors.centerIn: parent
                                        text: (groupCard.group.appName || "?").charAt(0).toUpperCase()
                                        color: centerWin.t.textPrimary
                                        font.bold: true
                                        font.pixelSize: 10
                                    }
                                }

                                Image {
                                    id: sIcon
                                    anchors.fill: parent
                                    source: {
                                        const icon = groupCard.group.appIcon
                                        if (!icon) return ""
                                        if (icon.startsWith("/") || icon.startsWith("file://") || icon.startsWith("http"))
                                            return icon
                                        return Quickshell.iconPath(icon, true)
                                    }
                                    fillMode: Image.PreserveAspectFit
                                    visible: status === Image.Ready
                                }
                            }

                            Text {
                                text: groupCard.group.appName
                                color: centerWin.t.textPrimary
                                font.pixelSize: 11
                                font.bold: true
                            }

                            // System Warning Pill Tag (for Battery Warning)
                            Rectangle {
                                visible: groupCard.isBatteryGroup
                                implicitWidth: sWarnTxt.implicitWidth + 8
                                implicitHeight: 16
                                radius: 8
                                color: Qt.rgba(centerWin.t.warning.r, centerWin.t.warning.g, centerWin.t.warning.b, 0.2)
                                border.color: centerWin.t.warning
                                border.width: 1

                                RowLayout {
                                    id: sWarnTxt
                                    anchors.centerIn: parent
                                    spacing: 3

                                    Text { text: "󰂃"; color: centerWin.t.warning; font.pixelSize: 10 }
                                    Text { text: "System Warning"; color: centerWin.t.warning; font.pixelSize: 9; font.bold: true }
                                }
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: centerWin.formatTime(groupCard.group.items[0].time)
                                color: centerWin.t.textDisabled
                                font.pixelSize: 10
                                Layout.alignment: Qt.AlignVCenter
                            }

                            // Dismiss Button ×
                            Item {
                                width: 20
                                height: 20
                                Layout.alignment: Qt.AlignVCenter

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 5
                                    color: sDismissBtn.containsMouse ? centerWin.t.bgHover : "transparent"
                                    Behavior on color { ColorAnimation { duration: 80 } }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: "\u00d7"
                                    color: sDismissBtn.containsMouse ? centerWin.t.textPrimary : centerWin.t.textDisabled
                                    font.pixelSize: 15
                                    font.bold: true
                                }
                                MouseArea {
                                    id: sDismissBtn
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Services.Notifications.dismissFromCenter(groupCard.group.items[0].notifId)
                                    }
                                }
                            }
                        }

                        // Content Row: Image + Summary + Body
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Image {
                                id: sImg
                                property string imgPath: groupCard.group.items[0].image || ""
                                visible: imgPath.length > 0 && status === Image.Ready
                                source: {
                                    if (!imgPath) return ""
                                    if (imgPath.startsWith("/") || imgPath.startsWith("file://") || imgPath.startsWith("http"))
                                        return imgPath
                                    return Quickshell.iconPath(imgPath, true)
                                }
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 40
                                fillMode: Image.PreserveAspectCrop
                                clip: true
                                Layout.alignment: Qt.AlignTop
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3

                                Text {
                                    text: groupCard.group.items[0].summary || ""
                                    color: centerWin.t.textPrimary
                                    font.bold: true
                                    font.pixelSize: 12
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }

                                Text {
                                    visible: (groupCard.group.items[0].body || "").length > 0
                                    text: groupCard.group.items[0].body || ""
                                    color: centerWin.t.textSecondary
                                    font.pixelSize: 11
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                        }

                        // Actions Row for Single Notification
                        RowLayout {
                            readonly property var actList: groupCard.group.items[0].actions
                            readonly property int actCount: actList ? (actList.count !== undefined ? actList.count : (actList.length !== undefined ? actList.length : 0)) : 0
                            visible: actCount > 0 && !groupCard.singleReplyMode
                            spacing: 6
                            Layout.topMargin: 2

                            Repeater {
                                model: parent.actList
                                delegate: Rectangle {
                                    id: sActBtn
                                    required property string identifier
                                    required property string text
                                    radius: 6
                                    color: sActHover.containsMouse ? centerWin.t.bgHover : centerWin.t.surface
                                    border.color: centerWin.t.border
                                    border.width: 1
                                    implicitHeight: 24
                                    implicitWidth: sActLabel.implicitWidth + 16
                                    Behavior on color { ColorAnimation { duration: 80 } }

                                    Text {
                                        id: sActLabel
                                        anchors.centerIn: parent
                                        text: sActBtn.text
                                        color: centerWin.t.textPrimary
                                        font.pixelSize: 11
                                    }
                                    MouseArea {
                                        id: sActHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (centerWin.isReplyAction(sActBtn)) {
                                                groupCard.singleReplyActionId = sActBtn.identifier
                                                groupCard.singleReplyMode = true
                                                Qt.callLater(() => sReplyInput.forceActiveFocus())
                                            } else {
                                                Services.Notifications.invokeAction(groupCard.group.items[0].notifId, sActBtn.identifier)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Inline Reply Area for Single Notification
                        ColumnLayout {
                            visible: groupCard.singleReplyMode
                            Layout.fillWidth: true
                            spacing: 6
                            Layout.topMargin: 2

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 32
                                radius: 7
                                color: centerWin.t.bgHover
                                border.color: sReplyInput.activeFocus ? centerWin.t.accent : centerWin.t.border
                                border.width: 1

                                TextInput {
                                    id: sReplyInput
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    color: centerWin.t.textPrimary
                                    font.pixelSize: 11
                                    clip: true
                                    focus: groupCard.singleReplyMode

                                    Text {
                                        text: "Write a reply..."
                                        color: centerWin.t.textDisabled
                                        font.pixelSize: 11
                                        visible: sReplyInput.text.length === 0 && !sReplyInput.activeFocus
                                    }

                                    Keys.onReturnPressed: {
                                        if (sReplyInput.text.trim().length > 0) {
                                            Services.Notifications.invokeAction(
                                                groupCard.group.items[0].notifId,
                                                groupCard.singleReplyActionId,
                                                sReplyInput.text.trim()
                                            )
                                            groupCard.singleReplyMode = false
                                            sReplyInput.text = ""
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
                                    implicitWidth: sCancelTxt.implicitWidth + 14
                                    radius: 6
                                    color: sCancelMouse.containsMouse ? centerWin.t.bgHover : centerWin.t.surface
                                    border.color: centerWin.t.border
                                    border.width: 1

                                    Text {
                                        id: sCancelTxt
                                        anchors.centerIn: parent
                                        text: "Cancel"
                                        color: centerWin.t.textSecondary
                                        font.pixelSize: 10
                                        font.bold: true
                                    }

                                    MouseArea {
                                        id: sCancelMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            groupCard.singleReplyMode = false
                                            sReplyInput.text = ""
                                        }
                                    }
                                }

                                Rectangle {
                                    implicitHeight: 22
                                    implicitWidth: sSendTxt.implicitWidth + 14
                                    radius: 6
                                    color: sSendMouse.containsMouse ? centerWin.t.textPrimary : centerWin.t.accent

                                    Text {
                                        id: sSendTxt
                                        anchors.centerIn: parent
                                        text: "Send 󰏲"
                                        color: Services.Theme.bgDeep
                                        font.pixelSize: 10
                                        font.bold: true
                                    }

                                    MouseArea {
                                        id: sSendMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (sReplyInput.text.trim().length > 0) {
                                                Services.Notifications.invokeAction(
                                                    groupCard.group.items[0].notifId,
                                                    groupCard.singleReplyActionId,
                                                    sReplyInput.text.trim()
                                                )
                                                groupCard.singleReplyMode = false
                                                sReplyInput.text = ""
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── 2. MULTI NOTIFICATION GROUP CARD (When isMulti) ──────────────
                    ColumnLayout {
                        id: groupContent
                        visible: groupCard.isMulti
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                        spacing: 8

                        // ── Group Header Row ────────────────────────────────────
                        RowLayout {
                            id: headerRow
                            Layout.fillWidth: true
                            spacing: 8

                            // Expandable Header Info Zone
                            MouseArea {
                                id: headerClickArea
                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const copy = Object.assign({}, centerWin.expandedGroups)
                                    copy[groupCard.group.appName] = !groupCard.expanded
                                    centerWin.expandedGroups = copy
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 8

                                    // App Icon Squircle Container
                                    Item {
                                        Layout.preferredWidth: 26
                                        Layout.preferredHeight: 26
                                        Layout.alignment: Qt.AlignVCenter

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 7
                                            color: centerWin.t.bgHover
                                            border.color: centerWin.t.border
                                            border.width: 1
                                            visible: hIcon.status !== Image.Ready

                                            Text {
                                                anchors.centerIn: parent
                                                text: (groupCard.group.appName || "?").charAt(0).toUpperCase()
                                                color: centerWin.t.textPrimary
                                                font.bold: true
                                                font.pixelSize: 11
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
                                                return Quickshell.iconPath(icon, true)
                                            }
                                            fillMode: Image.PreserveAspectFit
                                            visible: status === Image.Ready
                                        }
                                    }

                                    // App Name
                                    Text {
                                        text: groupCard.group.appName
                                        color: centerWin.t.textPrimary
                                        font.pixelSize: 12
                                        font.bold: true
                                    }

                                    // System Warning Pill Tag (for Battery Warning)
                                    Rectangle {
                                        visible: groupCard.isBatteryGroup
                                        implicitWidth: sysWarnTxt.implicitWidth + 10
                                        implicitHeight: 16
                                        radius: 8
                                        color: Qt.rgba(centerWin.t.warning.r, centerWin.t.warning.g, centerWin.t.warning.b, 0.2)
                                        border.color: centerWin.t.warning
                                        border.width: 1

                                        RowLayout {
                                            id: sysWarnTxt
                                            anchors.centerIn: parent
                                            spacing: 4

                                            Text { text: "󰂃"; color: centerWin.t.warning; font.pixelSize: 10 }
                                            Text { text: "System Warning"; color: centerWin.t.warning; font.pixelSize: 9; font.bold: true }
                                        }
                                    }

                                    // Group Multi Count Badge
                                    Rectangle {
                                        height: 16
                                        implicitWidth: badgeText.implicitWidth + 10
                                        radius: 8
                                        color: centerWin.t.surface
                                        border.color: centerWin.t.border
                                        border.width: 1

                                        Text {
                                            id: badgeText
                                            anchors.centerIn: parent
                                            text: groupCard.group.items.length
                                            color: centerWin.t.accent
                                            font.pixelSize: 10
                                            font.bold: true
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    // Time of latest notification item
                                    Text {
                                        text: centerWin.formatTime(groupCard.group.items[0].time)
                                        color: centerWin.t.textDisabled
                                        font.pixelSize: 10
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    // Chevron expand/collapse icon
                                    Text {
                                        text: groupCard.expanded ? "󰅀" : "󰅁"
                                        color: centerWin.t.textDisabled
                                        font.pixelSize: 13
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
                                    Behavior on color { ColorAnimation { duration: 80 } }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: "\u00d7"
                                    color: groupDismissBtn.containsMouse ? centerWin.t.textPrimary : centerWin.t.textDisabled
                                    font.pixelSize: 16
                                    font.bold: true
                                }
                                MouseArea {
                                    id: groupDismissBtn
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Services.Notifications.dismissGroupFromCenter(groupCard.group.items)
                                    }
                                }
                            }
                        }

                        // ── Collapsed Content Preview (when !groupCard.expanded) ──────────
                        ColumnLayout {
                            visible: !groupCard.expanded
                            Layout.fillWidth: true
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                // Thumbnail/Image if present
                                Image {
                                    id: collapsedImg
                                    property string imgPath: groupCard.group.items[0].image || ""
                                    visible: imgPath.length > 0 && status === Image.Ready
                                    source: {
                                        if (!imgPath) return ""
                                        if (imgPath.startsWith("/") || imgPath.startsWith("file://") || imgPath.startsWith("http"))
                                            return imgPath
                                        return Quickshell.iconPath(imgPath, true)
                                    }
                                    Layout.preferredWidth: 42
                                    Layout.preferredHeight: 42
                                    fillMode: Image.PreserveAspectCrop
                                    clip: true
                                    Layout.alignment: Qt.AlignTop
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        text: groupCard.group.items[0].summary || ""
                                        color: centerWin.t.textPrimary
                                        font.bold: true
                                        font.pixelSize: 12
                                        wrapMode: Text.Wrap
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        visible: (groupCard.group.items[0].body || "").length > 0
                                        text: groupCard.group.items[0].body || ""
                                        color: centerWin.t.textSecondary
                                        font.pixelSize: 11
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                        wrapMode: Text.Wrap
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            // Stacked preview pill when collapsed with multiple items
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: stackPreviewRow.implicitHeight + 8
                                radius: 8
                                color: centerWin.t.surface
                                border.color: centerWin.t.border
                                border.width: 1

                                RowLayout {
                                    id: stackPreviewRow
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 4; leftMargin: 8; rightMargin: 8 }
                                    spacing: 6

                                    Text {
                                        text: "󰅟"
                                        color: centerWin.t.textDisabled
                                        font.pixelSize: 11
                                    }

                                    Text {
                                        text: (groupCard.group && groupCard.group.items && groupCard.group.items.length > 1 && groupCard.group.items[1]) ? (groupCard.group.items[1].summary || "") : ""
                                        color: centerWin.t.textSecondary
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        visible: groupCard.group.items.length > 2
                                        text: "+" + (groupCard.group.items.length - 1) + " more"
                                        color: centerWin.t.accent
                                        font.pixelSize: 10
                                        font.bold: true
                                    }
                                }
                            }
                        }

                        // ── Expanded Items List (when groupCard.expanded) ──────────
                        ColumnLayout {
                            visible: groupCard.expanded
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: groupCard.group.items
                                delegate: Rectangle {
                                    id: itemDelegate
                                    required property var modelData
                                    property var notifItem: modelData
                                    property bool replyMode: false
                                    property string activeReplyActionId: ""
                                    property bool isBatteryItem: centerWin.isBatteryNotification(notifItem)
                                    property bool isItemCritical: notifItem.urgency === 2 || isBatteryItem

                                    Layout.fillWidth: true
                                    implicitHeight: itemContent.implicitHeight + 14
                                    radius: 9
                                    color: centerWin.t.surface
                                    border.color: itemDelegate.isBatteryItem ? centerWin.t.warning : (itemDelegate.isItemCritical ? centerWin.t.danger : centerWin.t.border)
                                    border.width: 1

                                    // Left strip for item (warning or critical)
                                    Rectangle {
                                        visible: itemDelegate.isItemCritical || itemDelegate.isBatteryItem
                                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                        width: 3
                                        radius: 2
                                        color: itemDelegate.isBatteryItem ? centerWin.t.warning : centerWin.t.danger
                                    }

                                    ColumnLayout {
                                        id: itemContent
                                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8; leftMargin: 10; rightMargin: 10 }
                                        spacing: 6

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            // Notification Image / Avatar
                                            Image {
                                                id: notifImg
                                                property string imgPath: itemDelegate.notifItem.image || ""
                                                visible: imgPath.length > 0 && status === Image.Ready
                                                source: {
                                                    if (!imgPath) return ""
                                                    if (imgPath.startsWith("/") || imgPath.startsWith("file://") || imgPath.startsWith("http"))
                                                        return imgPath
                                                    return Quickshell.iconPath(imgPath, true)
                                                }
                                                Layout.preferredWidth: 40
                                                Layout.preferredHeight: 40
                                                fillMode: Image.PreserveAspectCrop
                                                clip: true
                                                Layout.alignment: Qt.AlignTop
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 3

                                                // Item Header Row: Summary + Timestamp + Dismiss ×
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 6

                                                    Text {
                                                        text: itemDelegate.notifItem.summary || ""
                                                        color: centerWin.t.textPrimary
                                                        font.bold: true
                                                        font.pixelSize: 12
                                                        wrapMode: Text.Wrap
                                                        Layout.fillWidth: true
                                                    }

                                                    Text {
                                                        text: centerWin.formatTime(itemDelegate.notifItem.time)
                                                        color: centerWin.t.textDisabled
                                                        font.pixelSize: 10
                                                        Layout.alignment: Qt.AlignTop
                                                    }

                                                    // Individual Dismiss Button ×
                                                    Item {
                                                        width: 18
                                                        height: 18
                                                        Layout.alignment: Qt.AlignTop

                                                        Rectangle {
                                                            anchors.fill: parent
                                                            radius: 5
                                                            color: itemDismissBtn.containsMouse ? centerWin.t.bgHover : "transparent"
                                                            Behavior on color { ColorAnimation { duration: 80 } }
                                                        }
                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: "\u00d7"
                                                            color: itemDismissBtn.containsMouse ? centerWin.t.textPrimary : centerWin.t.textDisabled
                                                            font.pixelSize: 14
                                                            font.bold: true
                                                        }
                                                        MouseArea {
                                                            id: itemDismissBtn
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                Services.Notifications.dismissFromCenter(itemDelegate.notifItem.notifId)
                                                            }
                                                        }
                                                    }
                                                }

                                                // Item Body
                                                Text {
                                                    visible: (itemDelegate.notifItem.body || "").length > 0
                                                    text: itemDelegate.notifItem.body || ""
                                                    color: centerWin.t.textSecondary
                                                    font.pixelSize: 11
                                                    wrapMode: Text.Wrap
                                                    Layout.fillWidth: true
                                                }
                                            }
                                        }

                                        // Actions Row
                                        RowLayout {
                                            readonly property var actList: itemDelegate.notifItem.actions
                                            readonly property int actCount: actList ? (actList.count !== undefined ? actList.count : (actList.length !== undefined ? actList.length : 0)) : 0
                                            visible: actCount > 0 && !itemDelegate.replyMode
                                            spacing: 6
                                            Layout.topMargin: 2

                                            Repeater {
                                                model: parent.actList
                                                delegate: Rectangle {
                                                    id: actBtn
                                                    required property string identifier
                                                    required property string text
                                                    radius: 6
                                                    color: actHover.containsMouse ? centerWin.t.bgHover : centerWin.t.surfaceVariant
                                                    border.color: centerWin.t.border
                                                    border.width: 1
                                                    implicitHeight: 24
                                                    implicitWidth: actLabel.implicitWidth + 16
                                                    Behavior on color { ColorAnimation { duration: 80 } }

                                                    Text {
                                                        id: actLabel
                                                        anchors.centerIn: parent
                                                        text: actBtn.text
                                                        color: centerWin.t.textPrimary
                                                        font.pixelSize: 11
                                                    }
                                                    MouseArea {
                                                        id: actHover
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (centerWin.isReplyAction(actBtn)) {
                                                                itemDelegate.activeReplyActionId = actBtn.identifier
                                                                itemDelegate.replyMode = true
                                                                Qt.callLater(() => cardReplyInput.forceActiveFocus())
                                                            } else {
                                                                Services.Notifications.invokeAction(
                                                                    itemDelegate.notifItem.notifId, actBtn.identifier)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // Inline Reply Area
                                        ColumnLayout {
                                            visible: itemDelegate.replyMode
                                            Layout.fillWidth: true
                                            spacing: 6
                                            Layout.topMargin: 2

                                            Rectangle {
                                                Layout.fillWidth: true
                                                implicitHeight: 32
                                                radius: 7
                                                color: centerWin.t.bgHover
                                                border.color: cardReplyInput.activeFocus ? centerWin.t.accent : centerWin.t.border
                                                border.width: 1

                                                TextInput {
                                                    id: cardReplyInput
                                                    anchors.fill: parent
                                                    anchors.margins: 6
                                                    color: centerWin.t.textPrimary
                                                    font.pixelSize: 11
                                                    clip: true
                                                    focus: itemDelegate.replyMode

                                                    Text {
                                                        text: "Write a reply..."
                                                        color: centerWin.t.textDisabled
                                                        font.pixelSize: 11
                                                        visible: cardReplyInput.text.length === 0 && !cardReplyInput.activeFocus
                                                    }

                                                    Keys.onReturnPressed: {
                                                        if (cardReplyInput.text.trim().length > 0) {
                                                            Services.Notifications.invokeAction(
                                                                itemDelegate.notifItem.notifId,
                                                                itemDelegate.activeReplyActionId,
                                                                cardReplyInput.text.trim()
                                                            )
                                                            itemDelegate.replyMode = false
                                                            cardReplyInput.text = ""
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
                                                    implicitWidth: cancelTxt.implicitWidth + 14
                                                    radius: 6
                                                    color: cancelMouse.containsMouse ? centerWin.t.bgHover : centerWin.t.surfaceVariant
                                                    border.color: centerWin.t.border
                                                    border.width: 1

                                                    Text {
                                                        id: cancelTxt
                                                        anchors.centerIn: parent
                                                        text: "Cancel"
                                                        color: centerWin.t.textSecondary
                                                        font.pixelSize: 10
                                                        font.bold: true
                                                    }

                                                    MouseArea {
                                                        id: cancelMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            itemDelegate.replyMode = false
                                                            cardReplyInput.text = ""
                                                        }
                                                    }
                                                }

                                                // Send Button
                                                Rectangle {
                                                    implicitHeight: 22
                                                    implicitWidth: sendTxt.implicitWidth + 14
                                                    radius: 6
                                                    color: sendMouse.containsMouse ? centerWin.t.textPrimary : centerWin.t.accent

                                                    Text {
                                                        id: sendTxt
                                                        anchors.centerIn: parent
                                                        text: "Send 󰏲"
                                                        color: Services.Theme.bgDeep
                                                        font.pixelSize: 10
                                                        font.bold: true
                                                    }

                                                    MouseArea {
                                                        id: sendMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (cardReplyInput.text.trim().length > 0) {
                                                                Services.Notifications.invokeAction(
                                                                    itemDelegate.notifItem.notifId,
                                                                    itemDelegate.activeReplyActionId,
                                                                    cardReplyInput.text.trim()
                                                                )
                                                                itemDelegate.replyMode = false
                                                                cardReplyInput.text = ""
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
