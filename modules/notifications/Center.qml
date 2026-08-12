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
    // Shorthand lokal biar tidak terlalu verbose
    readonly property var t: Services.Theme

    // key: notifId item pertama di grup -> bool
    property var expandedGroups: ({})

    function isReplyAction(act) {
        if (!act) return false
        const id = (act.identifier || "").toLowerCase()
        const txt = (act.text || "").toLowerCase()
        return id.includes("reply") || id.includes("inline") || id.includes("respond") ||
               txt.includes("reply") || txt.includes("balas") || txt.includes("jawab") || txt.includes("respond")
    }

    function formatTime(ts) {
        const d = new Date(ts)
        const now = new Date()
        if (d.toDateString() === now.toDateString())
            return Qt.formatTime(d, "hh:mm")
        const yesterday = new Date(now)
        yesterday.setDate(now.getDate() - 1)
        if (d.toDateString() === yesterday.toDateString())
            return "Yesterday " + Qt.formatTime(d, "hh:mm")
        return Qt.formatDateTime(d, "dd/MM hh:mm")
    }

    // Group notif berurutan yg appName-nya sama
    property var groupedHistory: {
        const dep = Services.Notifications.historyList.count
        const groups = []
        let current = null
        for (let i = 0; i < Services.Notifications.historyList.count; i++) {
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

    MouseArea {
        anchors.fill: parent
        onClicked: Services.Notifications.centerVisible = false
    }

    Rectangle {
        id: panel
        anchors { top: parent.top; right: parent.right }
        anchors.rightMargin: 12
        anchors.topMargin: 12
        width: 380
        height: Math.max(480, Math.min(mainCol.implicitHeight + 24, 680))
        radius: 16
        color: centerWin.t.surface
        border.color: centerWin.t.border
        border.width: 1

        layer.enabled: true
        layer.effect: null

        opacity: Services.Notifications.centerVisible ? 1 : 0
        scale: 1
        y: Services.Notifications.centerVisible ? 0 : -24
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 0.6 } }

        MouseArea { anchors.fill: parent; onClicked: {} }

        ColumnLayout {
            id: mainCol
            anchors.fill: parent
            spacing: 0

            // ── Header ──────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 14
                Layout.bottomMargin: 10
                Layout.leftMargin: 16
                Layout.rightMargin: 12

                Text {
                    text: "Notifications"
                    color: centerWin.t.textPrimary
                    font.bold: true
                    font.pixelSize: 15
                    Layout.fillWidth: true
                }

                // DnD toggle
                Rectangle {
                    width: 30; height: 30; radius: 8
                    color: dndHover.containsMouse
                        ? (Services.Notifications.doNotDisturb ? "#e05c7a" : centerWin.t.bgHover)
                        : (Services.Notifications.doNotDisturb ? centerWin.t.danger : centerWin.t.surfaceVariant)

                    Behavior on color { ColorAnimation { duration: 100 } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰂛"
                        color: Services.Notifications.doNotDisturb ? centerWin.t.surface : centerWin.t.textSecondary
                        font.pixelSize: 13
                    }
                    MouseArea {
                        id: dndHover
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: Services.Notifications.doNotDisturb = !Services.Notifications.doNotDisturb
                    }
                }

                // Clear all
                Rectangle {
                    width: 30; height: 30; radius: 8
                    color: clearHover.containsMouse ? centerWin.t.bgHover : centerWin.t.surfaceVariant
                    Behavior on color { ColorAnimation { duration: 100 } }

                    Text { anchors.centerIn: parent; text: "󰎟"; color: centerWin.t.textSecondary; font.pixelSize: 13 }
                    MouseArea {
                        id: clearHover
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            Services.Notifications.clearHistory()
                            centerWin.expandedGroups = ({})
                        }
                    }
                }
            }

            // ── Header bottom divider ──────────────────────────────
            Rectangle {
                Layout.fillWidth: true; height: 1
                color: centerWin.t.border; opacity: 0.5
            }

            // ── Notification list ───────────────────────────────────
            ListView {
                id: historyView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 6
                topMargin: 8; bottomMargin: 10; leftMargin: 10; rightMargin: 10
                model: centerWin.groupedHistory

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle {
                        implicitWidth: 4
                        radius: 2
                        color: centerWin.t.bgHover
                    }
                }

                delegate: Rectangle {
                    id: groupCard
                    required property var modelData
                    property var group: modelData
                    property bool isMulti: group.items.length > 1
                    property bool expanded: !isMulti || centerWin.expandedGroups[group.appName] === true

                    width: historyView.width - 20
                    implicitHeight: groupContent.implicitHeight + 20
                    radius: 12
                    color: centerWin.t.surfaceVariant
                    border.color: group.items[0].urgency === 2 ? centerWin.t.danger : centerWin.t.border
                    border.width: 1

                    ColumnLayout {
                        id: groupContent
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                        spacing: 8

                        // ── Group Header Row ────────────────────────────────────
                        RowLayout {
                            id: headerRow
                            Layout.fillWidth: true
                            spacing: 8

                            // Clickable header info area (toggles expand/collapse)
                            MouseArea {
                                id: headerClickArea
                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                hoverEnabled: groupCard.isMulti
                                cursorShape: groupCard.isMulti ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (groupCard.isMulti) {
                                        const copy = Object.assign({}, centerWin.expandedGroups)
                                        copy[groupCard.group.appName] = !groupCard.expanded
                                        centerWin.expandedGroups = copy
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 8

                                    // App Icon
                                    Item {
                                        Layout.preferredWidth: 26
                                        Layout.preferredHeight: 26
                                        Layout.alignment: Qt.AlignVCenter

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 7
                                            color: centerWin.t.bgHover
                                            visible: hIcon.status !== Image.Ready

                                            Text {
                                                anchors.centerIn: parent
                                                text: (groupCard.group.appName || "?").charAt(0).toUpperCase()
                                                color: centerWin.t.textSecondary
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

                                    // App Name & Count Badge
                                    Text {
                                        text: groupCard.group.appName
                                        color: centerWin.t.accent
                                        font.pixelSize: 12
                                        font.bold: true
                                    }

                                    Rectangle {
                                        visible: groupCard.isMulti
                                        height: 16
                                        implicitWidth: badgeText.implicitWidth + 10
                                        radius: 8
                                        color: centerWin.t.bgHover
                                        border.color: centerWin.t.border
                                        border.width: 1

                                        Text {
                                            id: badgeText
                                            anchors.centerIn: parent
                                            text: groupCard.group.items.length
                                            color: centerWin.t.textSecondary
                                            font.pixelSize: 10
                                            font.bold: true
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    // Time of newest item
                                    Text {
                                        text: centerWin.formatTime(groupCard.group.items[0].time)
                                        color: centerWin.t.textDisabled
                                        font.pixelSize: 10
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    // Chevron expand icon
                                    Text {
                                        visible: groupCard.isMulti
                                        text: groupCard.expanded ? "\uf077" : "\uf078"
                                        font.family: "Symbols Nerd Font Mono"
                                        color: centerWin.t.textDisabled
                                        font.pixelSize: 11
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }
                            }

                            // Dismiss Group Button × (Distinct from expand area)
                            Item {
                                width: 22; height: 22
                                Layout.alignment: Qt.AlignVCenter

                                Rectangle {
                                    anchors.fill: parent; radius: 6
                                    color: groupDismissBtn.containsMouse ? centerWin.t.bgHover : "transparent"
                                    Behavior on color { ColorAnimation { duration: 80 } }
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
                                    anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Services.Notifications.dismissGroupFromCenter(groupCard.group.items)
                                    }
                                }
                            }
                        }

                        // ── Collapsed Content Preview (when !groupCard.expanded) ────
                        ColumnLayout {
                            visible: !groupCard.expanded
                            Layout.fillWidth: true
                            spacing: 6

                            // Primary (latest) item preview
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: groupCard.group.items[0].summary
                                    color: centerWin.t.textPrimary
                                    font.bold: true
                                    font.pixelSize: 12
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }

                                Text {
                                    visible: (groupCard.group.items[0].body || "").length > 0
                                    text: groupCard.group.items[0].body
                                    color: centerWin.t.textSecondary
                                    font.pixelSize: 11
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }

                            // Stacked preview pill when grouped
                            Rectangle {
                                visible: groupCard.isMulti
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
                                        text: "\uf0c9" // list icon
                                        font.family: "Symbols Nerd Font Mono"
                                        color: centerWin.t.textDisabled
                                        font.pixelSize: 10
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
                                        color: centerWin.t.accentDim
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
                            spacing: 8

                            Repeater {
                                model: groupCard.group.items
                                delegate: Rectangle {
                                    id: itemDelegate
                                    required property var modelData
                                    property var notifItem: modelData
                                    property bool replyMode: false
                                    property string activeReplyActionId: ""

                                    Layout.fillWidth: true
                                    implicitHeight: itemContent.implicitHeight + 14
                                    radius: 8
                                    color: centerWin.t.surface
                                    border.color: centerWin.t.border
                                    border.width: 1

                                    ColumnLayout {
                                        id: itemContent
                                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                                        spacing: 4

                                        // Item Header: Summary + Timestamp + Individual Delete Button ×
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            Text {
                                                text: itemDelegate.notifItem.summary
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
                                                width: 18; height: 18
                                                Layout.alignment: Qt.AlignTop

                                                Rectangle {
                                                    anchors.fill: parent; radius: 5
                                                    color: itemDismissBtn.containsMouse ? centerWin.t.bgHover : "transparent"
                                                    Behavior on color { ColorAnimation { duration: 80 } }
                                                }
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "\u00d7"
                                                    color: itemDismissBtn.containsMouse ? centerWin.t.textPrimary : centerWin.t.textDisabled
                                                    font.pixelSize: 13
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    id: itemDismissBtn
                                                    anchors.fill: parent; hoverEnabled: true
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
                                            text: itemDelegate.notifItem.body
                                            color: centerWin.t.textSecondary
                                            font.pixelSize: 11
                                            wrapMode: Text.Wrap
                                            Layout.fillWidth: true
                                        }

                                        // Actions Row
                                        RowLayout {
                                            readonly property var actList: itemDelegate.notifItem.actions
                                            readonly property int actCount: actList ? (actList.count !== undefined ? actList.count : (actList.length !== undefined ? actList.length : 0)) : 0
                                            visible: actCount > 0 && !itemDelegate.replyMode
                                            spacing: 6
                                            Layout.topMargin: 4

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
                                                    implicitWidth: actLabel.implicitWidth + 14
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
                                                        anchors.fill: parent; hoverEnabled: true
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

                                        // Type Zone (Inline Reply Mode for Center)
                                        ColumnLayout {
                                            visible: itemDelegate.replyMode
                                            Layout.fillWidth: true
                                            spacing: 6
                                            Layout.topMargin: 4

                                            Rectangle {
                                                Layout.fillWidth: true
                                                implicitHeight: 32
                                                radius: 8
                                                color: centerWin.t.bgHover
                                                border.color: cardReplyInput.activeFocus ? centerWin.t.accent : centerWin.t.border
                                                border.width: 1

                                                TextInput {
                                                    id: cardReplyInput
                                                    anchors.fill: parent
                                                    anchors.margins: 6
                                                    color: centerWin.t.textPrimary
                                                    font.pixelSize: 12
                                                    clip: true
                                                    focus: itemDelegate.replyMode

                                                    Text {
                                                        text: "Tulis balasan..."
                                                        color: centerWin.t.textDisabled
                                                        font.pixelSize: 12
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
                                                spacing: 8

                                                Item { Layout.fillWidth: true }

                                                // Cancel Button
                                                Rectangle {
                                                    implicitHeight: 22
                                                    implicitWidth: cancelTxt.implicitWidth + 14
                                                    radius: 6
                                                    color: cancelMouse.containsMouse ? centerWin.t.bgHover : centerWin.t.surfaceVariant

                                                    Text {
                                                        id: cancelTxt
                                                        anchors.centerIn: parent
                                                        text: "Batal"
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
                                                    color: sendMouse.containsMouse ? Qt.lighter(centerWin.t.accent, 1.1) : centerWin.t.accent

                                                    Text {
                                                        id: sendTxt
                                                        anchors.centerIn: parent
                                                        text: "Kirim 󰏲"
                                                        font.family: "Liga SFMono Nerd Font"
                                                        color: "#0a0a0a"
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

                // Empty state
                ColumnLayout {
                    visible: historyView.count === 0
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        text: "\uf0f3"
                        font.family: "Symbols Nerd Font Mono"
                        color: centerWin.t.border
                        font.pixelSize: 36
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Text {
                        text: "All clear"
                        color: centerWin.t.textDisabled
                        font.pixelSize: 12
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }
        }
    }
}
