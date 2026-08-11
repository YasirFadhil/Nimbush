import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "../../services" as Services
import "../media" as Media

PanelWindow {
    id: centerWin
    property string overlayId: "notifCenter"
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusiveZone: 0
    visible: Services.Notifications.centerVisible
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:notifcenter"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

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

            // ── Now Playing (floats between header & list) ─────────────
            Media.NowPlaying {
                Layout.fillWidth: true
                Layout.topMargin: Services.Mpris.activePlayer !== null ? 4 : 0
                Layout.bottomMargin: Services.Mpris.activePlayer !== null ? 2 : 0
            }


            // ── Separator antara player dan notif list ──────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                // Height 0 saat tidak ada player → tidak ada jarak kosong
                height: Services.Mpris.activePlayer !== null ? 1 : 0
                color: centerWin.t.border
                opacity: 0.45
                Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
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
                    property string groupKey: group.items[0].notifId + "-" + group.items[0].time
                    property bool isMulti: group.items.length > 1
                    property bool expanded: !isMulti || centerWin.expandedGroups[groupKey] === true

                    width: historyView.width - 20
                    implicitHeight: groupContent.implicitHeight + 18
                    radius: 12
                    color: centerWin.t.surfaceVariant
                    border.color: group.items[0].urgency === 2 ? centerWin.t.danger : centerWin.t.border
                    border.width: 1

                    ColumnLayout {
                        id: groupContent
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                        spacing: 6

                        // Header — selalu keliatan
                        Item {
                            id: headerArea
                            Layout.fillWidth: true
                            implicitHeight: headerRow.implicitHeight

                            RowLayout {
                                id: headerRow
                                anchors { left: parent.left; right: parent.right }
                                spacing: 8

                                // App icon
                                Item {
                                    Layout.preferredWidth: 30
                                    Layout.preferredHeight: 30
                                    Layout.alignment: Qt.AlignTop

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 8
                                        color: centerWin.t.bgHover
                                        visible: hIcon.status !== Image.Ready

                                        Text {
                                            anchors.centerIn: parent
                                            text: (groupCard.group.appName || "?").charAt(0).toUpperCase()
                                            color: centerWin.t.textSecondary
                                            font.bold: true
                                            font.pixelSize: 13
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

                                // App name + timestamp + collapsed summary
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    RowLayout {
                                        Layout.fillWidth: true

                                        Text {
                                            text: groupCard.group.appName + (groupCard.isMulti ? "  (" + groupCard.group.items.length + ")" : "")
                                            color: centerWin.t.accent
                                            font.pixelSize: 11
                                            font.bold: true
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            text: centerWin.formatTime(groupCard.group.items[0].time)
                                            color: centerWin.t.textDisabled
                                            font.pixelSize: 10
                                        }
                                    }

                                    Text {
                                        visible: !groupCard.expanded
                                        text: groupCard.group.items[0].summary
                                        color: centerWin.t.textPrimary
                                        font.bold: true
                                        wrapMode: Text.Wrap
                                        Layout.fillWidth: true
                                        font.pixelSize: 12
                                    }
                                }

                                // Chevron expand/collapse
                                Text {
                                    visible: groupCard.isMulti
                                    text: groupCard.expanded ? "\uf077" : "\uf078"
                                    font.family: "Symbols Nerd Font Mono"
                                    color: centerWin.t.textDisabled
                                    font.pixelSize: 11
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                // Dismiss button ×
                                Item {
                                    width: 20; height: 20
                                    Layout.alignment: Qt.AlignVCenter

                                    Rectangle {
                                        anchors.fill: parent; radius: 6
                                        color: dismissBtn.containsMouse ? centerWin.t.bgHover : "transparent"
                                        Behavior on color { ColorAnimation { duration: 80 } }
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: "\u00d7"
                                        color: dismissBtn.containsMouse ? centerWin.t.textSecondary : centerWin.t.textDisabled
                                        font.pixelSize: 14
                                        Behavior on color { ColorAnimation { duration: 80 } }
                                    }
                                    MouseArea {
                                        id: dismissBtn
                                        anchors.fill: parent; hoverEnabled: true
                                        onClicked: Services.Notifications.dismissGroupFromCenter(groupCard.group.items)
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: headerRow
                                enabled: groupCard.isMulti
                                onClicked: {
                                    const copy = Object.assign({}, centerWin.expandedGroups)
                                    copy[groupCard.groupKey] = !groupCard.expanded
                                    centerWin.expandedGroups = copy
                                }
                            }
                        }

                        // Detail tiap item — keliatan kalau expanded
                        ColumnLayout {
                            visible: groupCard.expanded
                            Layout.fillWidth: true
                            Layout.topMargin: groupCard.isMulti ? 2 : 0
                            spacing: 10

                            Repeater {
                                model: groupCard.group.items
                                delegate: ColumnLayout {
                                    id: itemDelegate
                                    required property var modelData
                                    property var notifItem: modelData
                                    Layout.fillWidth: true
                                    spacing: 3

                                    Text {
                                        visible: groupCard.isMulti
                                        text: itemDelegate.notifItem.summary
                                        color: centerWin.t.textPrimary
                                        font.bold: true
                                        font.pixelSize: 12
                                        wrapMode: Text.Wrap
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        visible: itemDelegate.notifItem.body.length > 0
                                        text: itemDelegate.notifItem.body
                                        color: centerWin.t.textSecondary
                                        font.pixelSize: 12
                                        wrapMode: Text.Wrap
                                        Layout.fillWidth: true
                                    }

                                    RowLayout {
                                        visible: itemDelegate.notifItem.actions && itemDelegate.notifItem.actions.length > 0
                                        spacing: 6
                                        Layout.topMargin: 4

                                        Repeater {
                                            model: itemDelegate.notifItem.actions
                                            delegate: Rectangle {
                                                id: actBtn
                                                required property string identifier
                                                required property string text
                                                radius: 8
                                                color: actHover.containsMouse ? centerWin.t.bgHover : centerWin.t.surface
                                                border.color: centerWin.t.border
                                                border.width: 1
                                                implicitHeight: 26
                                                implicitWidth: actLabel.implicitWidth + 18
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
                                                    onClicked: Services.Notifications.invokeAction(
                                                        itemDelegate.notifItem.notifId, actBtn.identifier)
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
