import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "../../services" as Services

PanelWindow {
    id: popupWin

    property string overlayId: "notifPopup"
    property bool replyMode: false
    property string activeReplyActionId: ""
    property int activeReplyNotifId: -1

    readonly property bool isBottom: Services.Config ? (Services.Config.barPosition === "bottom") : false
    readonly property string notifPos: Services.Config ? Services.Config.notificationPosition : "top_right"
    readonly property bool isIslandMode: (Services.Config ? Services.Config.barStyle : "islands") === "islands"
    readonly property bool isIslandVisible: (Services.Config ? Services.Config.islandStyle : "expanded") !== "hidden"
    readonly property bool showDynamicIsland: isIslandMode && isIslandVisible
    readonly property bool hasPopups: Services.Notifications.popupList.count > 0

    // Only show popup window when NOT in island mode, popups exist, and lockscreen is not locked
    visible: !showDynamicIsland && hasPopups && !Services.OverlayManager.isLocked

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:notifpopup"
    WlrLayershell.keyboardFocus: popupWin.replyMode ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    exclusiveZone: 0
    color: "transparent"

    // Anchoring based on configuration and bar position
    anchors {
        top: !popupWin.isBottom
        bottom: popupWin.isBottom
        right: (popupWin.notifPos === "top_right" || popupWin.notifPos === "bottom_right" || popupWin.notifPos === "top_center")
        left: (popupWin.notifPos === "top_left")
    }

    margins {
        top: 8
        bottom: 8
        right: (popupWin.notifPos === "top_center") ? ((Screen.width - 360) / 2) : 12
        left: 12
    }

    implicitWidth: 360
    implicitHeight: Math.min(Screen.height - 100, popupListView.contentHeight + 20)

    function isReplyAction(act) {
        if (!act) return false
        const id = (act.identifier || "").toLowerCase()
        const txt = (act.text || "").toLowerCase()
        return id.includes("reply") || id.includes("inline") || id.includes("respond") ||
               txt.includes("reply") || txt.includes("balas") || txt.includes("jawab") || txt.includes("respond")
    }

    ListView {
        id: popupListView
        anchors.fill: parent
        spacing: 10
        clip: false
        interactive: false
        model: Services.Notifications.popupList

        // Animated add and remove
        add: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.9; to: 1.0; duration: 240; easing.type: Easing.OutBack }
            NumberAnimation { property: "x"; from: popupWin.notifPos === "top_left" ? -40 : 40; to: 0; duration: 240; easing.type: Easing.OutCubic }
        }
        remove: Transition {
            NumberAnimation { property: "opacity"; to: 0; duration: 180; easing.type: Easing.InCubic }
            NumberAnimation { property: "scale"; to: 0.92; duration: 180; easing.type: Easing.InCubic }
            NumberAnimation { property: "x"; to: popupWin.notifPos === "top_left" ? -60 : 60; duration: 180; easing.type: Easing.InCubic }
        }
        displaced: Transition {
            NumberAnimation { properties: "y"; duration: 200; easing.type: Easing.OutCubic }
        }

        delegate: Rectangle {
            id: card
            required property var modelData
            property var notifItem: modelData
            property bool isReplying: popupWin.replyMode && popupWin.activeReplyNotifId === notifItem.notifId
            property bool isCritical: notifItem.urgency === 2

            width: popupListView.width
            implicitHeight: cardContent.implicitHeight + 18
            radius: Services.Theme.radiusMd
            color: Services.Theme.surfaced
            border.color: card.isCritical ? Services.Theme.danger : Services.Theme.border
            border.width: 1

            // Subtle glow
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.color: Qt.rgba(1, 1, 1, Services.Theme.isDark ? 0.08 : 0.2)
                border.width: 1
            }

            // Left accent bar
            Rectangle {
                visible: card.isCritical
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: 3.5
                radius: 2
                color: Services.Theme.danger
            }

            ColumnLayout {
                id: cardContent
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                spacing: 6

                // Header Row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // App Icon
                    Item {
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                        Layout.alignment: Qt.AlignVCenter

                        Rectangle {
                            anchors.fill: parent
                            radius: 5
                            color: Services.Theme.bgHover
                            border.color: Services.Theme.border
                            border.width: 1
                            visible: popIcon.status !== Image.Ready

                            Text {
                                anchors.centerIn: parent
                                text: (notifItem.appName || "?").charAt(0).toUpperCase()
                                color: Services.Theme.textPrimary
                                font.bold: true
                                font.pixelSize: 10
                            }
                        }

                        Image {
                            id: popIcon
                            anchors.fill: parent
                            source: {
                                const icon = notifItem.appIcon
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
                            cache: true
                            sourceSize: Qt.size(32, 32)
                            visible: status === Image.Ready
                        }
                    }

                    Text {
                        text: notifItem.appName || "Notification"
                        color: Services.Theme.textDisabled
                        font.pixelSize: 10
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    // Dismiss '×' Button
                    Rectangle {
                        width: 18
                        height: 18
                        radius: 5
                        color: closeMouse.containsMouse ? Services.Theme.danger : "transparent"
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                        Text {
                            anchors.centerIn: parent
                            text: "\u00d7"
                            font.pixelSize: 14
                            font.bold: true
                            color: closeMouse.containsMouse ? Services.Theme.white : Services.Theme.textDisabled
                        }

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Services.Notifications.dismiss(notifItem.notifId)
                            }
                        }
                    }
                }

                // Content Row: Thumbnail + Summary & Body
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Image {
                        id: popThumb
                        property string imgPath: notifItem.image || ""
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
                        asynchronous: true
                        cache: true
                        sourceSize: Qt.size(80, 80)
                        clip: true
                        Layout.alignment: Qt.AlignTop
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            visible: (notifItem.summary || "").length > 0
                            text: notifItem.summary || ""
                            color: Services.Theme.textPrimary
                            font.bold: true
                            font.pixelSize: 12
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }

                        Text {
                            visible: (notifItem.body || "").length > 0
                            text: notifItem.body || ""
                            color: Services.Theme.textSecondary
                            font.pixelSize: 11
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                    }
                }

                // Actions Row (when not replying)
                RowLayout {
                    readonly property var actList: notifItem.actions
                    readonly property int actCount: actList ? (actList.count !== undefined ? actList.count : (actList.length !== undefined ? actList.length : 0)) : 0
                    visible: actCount > 0 && !card.isReplying
                    spacing: 6
                    Layout.topMargin: 2

                    Repeater {
                        model: parent.actList
                        delegate: Rectangle {
                            id: actBtn
                            required property string identifier
                            required property string text
                            radius: 6
                            color: actHover.containsMouse ? Services.Theme.bgHover : Services.Theme.surfaceVariant
                            border.color: Services.Theme.border
                            border.width: 1
                            implicitHeight: 24
                            implicitWidth: actLabel.implicitWidth + 16
                            Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                            Text {
                                id: actLabel
                                anchors.centerIn: parent
                                text: actBtn.text
                                color: Services.Theme.textPrimary
                                font.pixelSize: 11
                                font.bold: true
                            }

                            MouseArea {
                                id: actHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (popupWin.isReplyAction(actBtn)) {
                                        popupWin.activeReplyActionId = actBtn.identifier
                                        popupWin.activeReplyNotifId = notifItem.notifId
                                        popupWin.replyMode = true
                                        Services.Notifications.replyingNotifId = notifItem.notifId
                                        Qt.callLater(() => popReplyInput.forceActiveFocus())
                                    } else {
                                        Services.Notifications.invokeAction(notifItem.notifId, actBtn.identifier)
                                    }
                                }
                            }
                        }
                    }
                }

                // Inline Reply Area (when replying)
                ColumnLayout {
                    visible: card.isReplying
                    Layout.fillWidth: true
                    spacing: 6
                    Layout.topMargin: 2

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: 7
                        color: Services.Theme.bgHover
                        border.color: popReplyInput.activeFocus ? Services.Theme.accent : Services.Theme.border
                        border.width: 1

                        TextInput {
                            id: popReplyInput
                            anchors.fill: parent
                            anchors.margins: 6
                            color: Services.Theme.textPrimary
                            font.pixelSize: 11
                            clip: true
                            focus: card.isReplying

                            Text {
                                text: (notifItem.inlineReplyPlaceholder && notifItem.inlineReplyPlaceholder.length > 0) ? notifItem.inlineReplyPlaceholder : "Write a reply..."
                                color: Services.Theme.textDisabled
                                font.pixelSize: 11
                                visible: popReplyInput.text.length === 0 && !popReplyInput.activeFocus
                            }

                            Keys.onReturnPressed: {
                                if (popReplyInput.text.trim().length > 0) {
                                    const msg = popReplyInput.text.trim()
                                    const nId = notifItem.notifId
                                    const aId = popupWin.activeReplyActionId
                                    popupWin.replyMode = false
                                    popupWin.activeReplyNotifId = -1
                                    Services.Notifications.replyingNotifId = -1
                                    popReplyInput.text = ""
                                    Services.Notifications.invokeAction(nId, aId, msg)
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
                            implicitWidth: cancelTxt.implicitWidth + 14
                            radius: 6
                            color: cancelMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.surfaceVariant
                            border.color: Services.Theme.border
                            border.width: 1

                            Text {
                                id: cancelTxt
                                anchors.centerIn: parent
                                text: "Cancel"
                                color: Services.Theme.textSecondary
                                font.pixelSize: 10
                                font.bold: true
                            }

                            MouseArea {
                                id: cancelMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    popupWin.replyMode = false
                                    popupWin.activeReplyNotifId = -1
                                    Services.Notifications.replyingNotifId = -1
                                    popReplyInput.text = ""
                                }
                            }
                        }

                        Rectangle {
                            implicitHeight: 22
                            implicitWidth: popSendRow.implicitWidth + 16
                            radius: 6
                            color: sendMouse.containsMouse ? Qt.lighter(Services.Theme.accent, 1.1) : Services.Theme.accent

                            RowLayout {
                                id: popSendRow
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
                                id: sendMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (popReplyInput.text.trim().length > 0) {
                                        const msg = popReplyInput.text.trim()
                                        const nId = notifItem.notifId
                                        const aId = popupWin.activeReplyActionId
                                        popupWin.replyMode = false
                                        popupWin.activeReplyNotifId = -1
                                        Services.Notifications.replyingNotifId = -1
                                        popReplyInput.text = ""
                                        Services.Notifications.invokeAction(nId, aId, msg)
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
