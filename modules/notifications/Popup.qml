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

    readonly property bool isFullscreen: Services.Workspaces ? Services.Workspaces.isFullscreen : false
    property bool hasBatteryPopup: false

    function updateBatteryPopupStatus() {
        if (!Services.Notifications || !Services.Notifications.popupList) {
            hasBatteryPopup = false
            return
        }
        const list = Services.Notifications.popupList
        for (let i = 0; i < list.count; i++) {
            const item = list.get(i)
            if (item && (item.isBattery || (Services.Notifications.isBatteryNotification && Services.Notifications.isBatteryNotification(item)))) {
                hasBatteryPopup = true
                return
            }
        }
        hasBatteryPopup = false
    }

    Connections {
        target: Services.Notifications ? Services.Notifications.popupList : null
        function onCountChanged() { popupWin.updateBatteryPopupStatus() }
    }
    readonly property bool fullscreenAllowed: (Services.Config && Services.Config.notificationShowInFullscreen) || hasBatteryPopup

    readonly property int cardWidth: 360
    readonly property int sideMargin: 12
    readonly property bool isRight: popupWin.notifPos === "top_right" || popupWin.notifPos === "bottom_right"
    readonly property bool isLeft: popupWin.notifPos === "top_left"
    readonly property bool isCenter: popupWin.notifPos === "top_center"

    property bool closingKeepAlive: false
    Timer {
        id: closeTimer
        interval: 250
        repeat: false
        onTriggered: popupWin.closingKeepAlive = false
    }

    onHasPopupsChanged: {
        if (!hasPopups) {
            closingKeepAlive = true
            closeTimer.restart()
        } else {
            closeTimer.stop()
            closingKeepAlive = false
        }
    }

    // In fullscreen mode, notifications always appear as popups (if enabled in settings or if battery alert).
    // In normal (non-fullscreen) mode, only show popups when NOT in dynamic island mode.
    visible: (hasPopups || closingKeepAlive) && !Services.OverlayManager.isLocked && (isFullscreen ? fullscreenAllowed : !showDynamicIsland)

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:notifpopup"
    WlrLayershell.keyboardFocus: popupWin.replyMode ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    exclusiveZone: 0
    color: "transparent"

    // Anchoring based on configuration and bar position
    anchors {
        top: !popupWin.isBottom
        bottom: popupWin.isBottom
        right: popupWin.isRight || popupWin.isCenter
        left: popupWin.isLeft
    }

    margins {
        top: 8
        bottom: 8
        right: popupWin.isCenter ? ((Screen.width - popupWin.cardWidth) / 2) : 12
        left: 12
    }

    property real lastContentHeight: 0
    Connections {
        target: popupListView
        function onContentHeightChanged() {
            if (popupListView.contentHeight > 0) {
                popupWin.lastContentHeight = popupListView.contentHeight
            }
        }
    }
    onVisibleChanged: {
        if (!visible) {
            lastContentHeight = 0
            closingKeepAlive = false
        }
    }

    implicitWidth: popupWin.cardWidth
    implicitHeight: Math.min(Screen.height - 100, Math.max(popupListView.contentHeight, lastContentHeight) + 20)

    function isReplyAction(act) {
        if (!act) return false
        const id = (act.identifier || "").toLowerCase()
        const txt = (act.text || "").toLowerCase()
        return id.includes("reply") || id.includes("inline") || id.includes("respond") ||
               txt.includes("reply") || txt.includes("balas") || txt.includes("jawab") || txt.includes("respond")
    }

    ListView {
        id: popupListView
        width: popupWin.cardWidth
        height: parent.height
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 10
        clip: false
        interactive: false
        model: Services.Notifications.popupList

        displaced: Transition {
            NumberAnimation { properties: "y"; duration: 280; easing.type: Easing.OutBack; easing.overshoot: 1.15 }
        }
        remove: Transition {
            NumberAnimation { property: "opacity"; to: 0.0; duration: 150; easing.type: Easing.OutCubic }
        }

        delegate: Rectangle {
            id: card
            required property var modelData
            property var notifItem: modelData
            property bool isReplying: popupWin.replyMode && popupWin.activeReplyNotifId === (notifItem ? notifItem.notifId : -1)
            property bool isCritical: notifItem ? notifItem.urgency === 2 : false
            readonly property bool isBattery: (Services.Notifications && notifItem) ? Services.Notifications.isBatteryNotification(notifItem) : false
            readonly property bool cardAllowed: !popupWin.isFullscreen || (Services.Config && Services.Config.notificationShowInFullscreen) || isBattery

            readonly property var cardOrigin: popupWin.isLeft ? (popupWin.isBottom ? Item.BottomLeft : Item.TopLeft) : (popupWin.isBottom ? Item.BottomRight : Item.TopRight)
            transformOrigin: cardOrigin

            property bool isDismissing: false
            property real lockedHeight: 0

            Component.onCompleted: {
                if (implicitHeight > 0) lockedHeight = implicitHeight
            }
            onImplicitHeightChanged: {
                if (implicitHeight > 0) lockedHeight = implicitHeight
            }

            visible: cardAllowed
            width: popupListView.width
            implicitHeight: cardAllowed ? (cardContent.implicitHeight + 18) : 0
            height: isDismissing ? lockedHeight : ((implicitHeight > 0) ? implicitHeight : lockedHeight)
            radius: Services.Theme.radiusMd
            color: Services.Theme.surfaced
            border.color: card.isCritical ? Services.Theme.danger : Services.Theme.border
            border.width: 1

            transform: Translate {
                id: cardTrans
                x: popupWin.isLeft ? -30 : 30
            }

            scale: 0.5
            opacity: 0.0

            ParallelAnimation {
                id: enterAnim
                NumberAnimation {
                    target: card
                    property: "scale"
                    from: 0.5
                    to: 1.0
                    duration: 280
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.2
                }
                NumberAnimation {
                    target: card
                    property: "opacity"
                    from: 0.0
                    to: 1.0
                    duration: 220
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: cardTrans
                    property: "x"
                    from: popupWin.isLeft ? -30 : 30
                    to: 0
                    duration: 280
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.15
                }
            }

            Timer {
                id: enterTimer
                interval: 35
                running: true
                repeat: false
                onTriggered: {
                    enterAnim.start()
                }
            }

            function dismissCard() {
                if (isDismissing) return
                isDismissing = true
                enterTimer.stop()
                enterAnim.stop()
                autoDismissTimer.stop()
                if (card.height > 0) lockedHeight = card.height
                exitAnim.start()
            }

            ParallelAnimation {
                id: exitAnim
                NumberAnimation {
                    target: card
                    property: "scale"
                    from: card.scale
                    to: 0.5
                    duration: 220
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.2
                }
                NumberAnimation {
                    target: card
                    property: "opacity"
                    from: card.opacity
                    to: 0.0
                    duration: 180
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: cardTrans
                    property: "x"
                    from: cardTrans.x
                    to: popupWin.isLeft ? -30 : 30
                    duration: 220
                    easing.type: Easing.OutCubic
                }
                onFinished: {
                    if (notifItem && notifItem.notifId !== undefined) {
                        Services.Notifications.dismiss(notifItem.notifId)
                    }
                }
            }

            Timer {
                id: autoDismissTimer
                interval: {
                    const sec = Services.Config ? Services.Config.notificationTimeout : 5
                    const base = (notifItem && notifItem.urgency === 2) ? 7000 : (sec * 1000)
                    return Math.max(1000, base - 250)
                }
                running: !card.isReplying && !closeMouse.containsMouse && !hoverDetector.containsMouse && !card.isDismissing
                repeat: false
                onTriggered: card.dismissCard()
            }

            MouseArea {
                id: hoverDetector
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
            }

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
                                text: (notifItem ? (notifItem.appName || "?") : "?").charAt(0).toUpperCase()
                                color: Services.Theme.textPrimary
                                font.bold: true
                                font.pixelSize: 10
                            }
                        }

                        Image {
                            id: popIcon
                            anchors.fill: parent
                            source: {
                                const icon = notifItem ? (notifItem.appIcon || "") : ""
                                if (!icon) return ""
                                if (icon.startsWith("file://") || icon.startsWith("http://") || icon.startsWith("https://") || icon.startsWith("image://"))
                                    return icon
                                if (icon.startsWith("/"))
                                    return "file://" + icon
                                if (Services.SystemTheme) {
                                    const res = Services.SystemTheme.getIcon(icon)
                                    if (res && res.length > 0) return res
                                }
                                const qp = Quickshell.iconPath(icon, true)
                                return (qp && qp.startsWith("/")) ? ("file://" + qp) : (qp || "")
                            }
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: true
                            sourceSize: Qt.size(32, 32)
                            visible: status === Image.Ready && source.toString().length > 0
                        }
                    }

                    Text {
                        text: (notifItem && notifItem.appName) ? notifItem.appName : "Notification"
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
                        scale: closeMouse.pressed ? 0.88 : (closeMouse.containsMouse ? 1.15 : 1.0)
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

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
                                card.dismissCard()
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
                        visible: imgPath.length > 0 && status === Image.Ready && source.toString().length > 0
                        Layout.preferredWidth: visible ? 30 : 0
                        Layout.preferredHeight: visible ? 30 : 0
                        source: {
                            if (!imgPath) return ""
                            if (imgPath.startsWith("file://") || imgPath.startsWith("http://") || imgPath.startsWith("https://") || imgPath.startsWith("image://"))
                                return imgPath
                            if (imgPath.startsWith("/"))
                                return "file://" + imgPath
                            if (Services.SystemTheme) {
                                const res = Services.SystemTheme.getIcon(imgPath)
                                if (res && res.length > 0) return res
                            }
                            const qp = Quickshell.iconPath(imgPath, true)
                            return (qp && qp.startsWith("/")) ? ("file://" + qp) : (qp || "")
                        }
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        sourceSize: Qt.size(60, 60)
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
