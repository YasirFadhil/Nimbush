// DynamicIsland.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Mpris
import "../../../services" as Services

Item {
    id: root

    // ----- Public API & State -----
    property bool pinned: false
    property bool autoExpanded: false
    property int activeNotifIndex: 0

    // Inline Reply Type Zone State
    property bool replyMode: false
    property string activeReplyActionId: ""

    // Island visual dimensions for window masking
    readonly property int islandWidth: island.width
    readonly property int islandHeight: island.height

    // Notification model shortcuts
    readonly property var popupList: Services.Notifications.popupList
    readonly property int notifCount: popupList ? popupList.count : 0
    readonly property bool notifActive: notifCount > 0

    // System HUD Alert State (Mute, DnD, Charging)
    property bool sysHudActive: false
    property string sysHudIcon: ""
    property string sysHudTitle: ""
    property string sysHudDetail: ""
    property color sysHudColor: Services.Theme.accent
    property bool hudReady: false

    function showSysHud(icon, title, detail, iconColor) {
        sysHudIcon = icon
        sysHudTitle = title
        sysHudDetail = detail || ""
        sysHudColor = iconColor || Services.Theme.accent
        sysHudActive = true
        sysHudTimer.restart()
    }

    Timer {
        id: sysHudTimer
        interval: 2200
        onTriggered: root.sysHudActive = false
    }

    Timer {
        id: hudInitTimer
        interval: 2000
        running: true
        repeat: false
        onTriggered: root.hudReady = true
    }

    // Connections for System Events
    Connections {
        target: Services.Audio
        function onMutedChanged() {
            if (!root.hudReady || !Services.Audio.sink) return
            const isMuted = Services.Audio.muted
            const vol = Services.Audio.volume || 0
            const icon = Services.Icons.volumeIcon(vol, isMuted)
            const title = isMuted ? "Audio Muted" : "Audio Unmuted"
            const detail = Math.round(vol * 100) + "%"
            root.showSysHud(icon, title, detail, isMuted ? Services.Theme.danger : Services.Theme.success)
        }
    }

    Connections {
        target: Services.Notifications
        function onDoNotDisturbChanged() {
            if (!root.hudReady) return
            const dnd = Services.Notifications.doNotDisturb
            const icon = dnd ? "󰂛" : "󰂚"
            const title = dnd ? "Do Not Disturb" : "Notifications On"
            const detail = dnd ? "On" : "Off"
            root.showSysHud(icon, title, detail, dnd ? Services.Theme.danger : Services.Theme.accent)
        }
    }

    Connections {
        target: Services.Power
        function onChargingChanged() {
            if (!root.hudReady) return
            const isCharging = Services.Power.charging
            const rawPct = Services.Power.percentage || 0
            const pct = Math.round(rawPct > 1 ? rawPct : rawPct * 100)
            const icon = Services.Icons.powerIcon(isCharging, pct)
            const title = isCharging ? "Charging" : "Discharging"
            const detail = pct + "%"
            root.showSysHud(icon, title, detail, isCharging ? Services.Theme.success : Services.Theme.accent)
        }
    }

    // MPRIS shortcuts
    readonly property var activePlayer: Services.Mpris.activePlayer
    readonly property bool mediaPlaying: activePlayer !== null && activePlayer.isPlaying
    readonly property bool hasMedia: activePlayer !== null && (activePlayer.trackTitle !== "" || mediaPlaying)

    readonly property bool expanded: pinned || autoExpanded || notifActive || sysHudActive

    property int autoExpandDuration: 2000
    property int notifDuration: 5000

    // Safe retrieval of current notification entry
    readonly property var currentNotif: {
        if (!popupList || notifCount === 0) return null
        const idx = Math.max(0, Math.min(activeNotifIndex, notifCount - 1))
        return popupList.get(idx)
    }

    onCurrentNotifChanged: {
        replyMode = false
        activeReplyActionId = ""
    }

    onReplyModeChanged: {
        if (replyMode) {
            Qt.callLater(() => replyInput.forceActiveFocus())
        }
    }

    function isReplyAction(act) {
        if (!act) return false
        const id = (act.identifier || "").toLowerCase()
        const txt = (act.text || "").toLowerCase()
        return id.includes("reply") || id.includes("inline") || id.includes("respond") ||
               txt.includes("reply") || txt.includes("balas") || txt.includes("jawab") || txt.includes("respond")
    }

    readonly property bool isCritical: currentNotif !== null && currentNotif.urgency === 2
    readonly property bool hasNotifBody: currentNotif !== null && currentNotif.body !== undefined && currentNotif.body.length > 0
    readonly property bool hasNotifActions: currentNotif !== null && currentNotif.actions !== undefined && currentNotif.actions.count > 0

    // Island Dimensions
    property int collapsedWidth: 140
    property int collapsedHeight: 32

    readonly property int calculatedExpandedWidth: {
        if (notifActive) return replyMode ? 390 : 360
        if (sysHudActive) return 280
        if (hasMedia) return 360
        return 260
    }

    readonly property int calculatedExpandedHeight: {
        if (notifActive) {
            if (replyMode) return 146
            let h = 72
            if (hasNotifBody) h += 24
            if (hasNotifActions) h += 32
            return h
        }
        if (sysHudActive) return 54
        if (hasMedia) return 120
        return 52
    }

    // Format seconds → "m:ss"
    function fmtTime(sec) {
        const s = Math.max(0, Math.floor(sec ?? 0))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    function pulse() {
        autoExpanded = true
        autoCollapseTimer.restart()
    }

    function togglePin() {
        pinned = !pinned
        if (!pinned) autoExpanded = false
    }

    function collapse() {
        pinned = false
        autoExpanded = false
        replyMode = false
        if (notifActive && currentNotif) {
            Services.Notifications.dismiss(currentNotif.notifId)
        }
    }

    function nextNotif() {
        if (notifCount > 0) {
            activeNotifIndex = (activeNotifIndex + 1) % notifCount
            notifTimer.restart()
        }
    }

    function prevNotif() {
        if (notifCount > 0) {
            activeNotifIndex = (activeNotifIndex - 1 + notifCount) % notifCount
            notifTimer.restart()
        }
    }

    Timer {
        id: mprisRefreshTimer
        interval: 1000
        running: root.mediaPlaying
        repeat: true
        onTriggered: root.activePlayer?.refreshPosition?.()
    }

    Timer {
        id: autoCollapseTimer
        interval: root.autoExpandDuration
        onTriggered: root.autoExpanded = false
    }

    Timer {
        id: notifTimer
        interval: root.notifDuration
        repeat: false
        onTriggered: {
            if (root.replyMode) return
            if (root.notifCount > 1 && root.activeNotifIndex < root.notifCount - 1) {
                root.activeNotifIndex++
                notifTimer.restart()
            }
        }
    }

    Connections {
        target: Services.Notifications
        function onNewNotification(entry) {
            root.activeNotifIndex = 0
            root.replyMode = false
            notifTimer.restart()
        }
    }

    Connections {
        target: Services.Mpris
        function onActivePlayerChanged() {
            if (root.hudReady && Services.Mpris.activePlayer && Services.Mpris.activePlayer.isPlaying && root.notifCount === 0) {
                root.pulse()
            }
        }
    }

    // Click outside area to collapse expanded island
    MouseArea {
        id: outsideMouseArea
        anchors.fill: parent
        enabled: root.expanded
        z: -1
        onClicked: root.collapse()
    }

    Rectangle {
        id: island
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 4
        clip: true

        width: root.expanded ? root.calculatedExpandedWidth : root.collapsedWidth
        height: root.expanded ? root.calculatedExpandedHeight : root.collapsedHeight
        radius: root.expanded ? Services.Theme.radiusLg : (height / 2)
        color: "#0c0c0c"
        border.color: root.isCritical ? Services.Theme.danger : (root.expanded ? Services.Theme.borderHighlight : "#222222")
        border.width: root.isCritical ? 1.5 : 1

        Behavior on width  { NumberAnimation { duration: 420; easing.type: Easing.OutExpo } }
        Behavior on height { NumberAnimation { duration: 420; easing.type: Easing.OutExpo } }
        Behavior on radius { NumberAnimation { duration: 420; easing.type: Easing.OutExpo } }
        Behavior on border.color { ColorAnimation { duration: 250 } }

        MouseArea {
            id: islandMouseArea
            anchors.fill: parent
            z: 0
            onClicked: root.togglePin()
        }

        // ==================== Collapsed State ====================
        RowLayout {
            anchors.centerIn: parent
            spacing: 8
            visible: !root.expanded
            opacity: root.expanded ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 200 } }

            // Animated Status / Music Icon
            Item {
                implicitWidth: 16
                implicitHeight: 16
                Layout.alignment: Qt.AlignVCenter

                Text {
                    id: statusIconTxt
                    anchors.centerIn: parent
                    text: root.notifActive ? "󰂚" : (root.mediaPlaying ? "󰎈" : "●")
                    font.family: "Liga SFMono Nerd Font"
                    font.pixelSize: 13
                    color: root.notifActive ? Services.Theme.accent : (root.mediaPlaying ? Services.Theme.success : Services.Theme.textDisabled)

                    RotationAnimation on rotation {
                        from: 0; to: 360
                        duration: 3000
                        loops: Animation.Infinite
                        running: root.mediaPlaying && !root.expanded
                    }
                }
            }

            // Marquee Scrolling Track Title / Notif Text Container
            Item {
                id: collapsedTextContainer
                implicitWidth: collapsedText.text.length > 0 ? Math.min(collapsedText.implicitWidth, 96) : 0
                implicitHeight: 16
                clip: true
                visible: collapsedText.text.length > 0
                Layout.alignment: Qt.AlignVCenter

                Text {
                    id: collapsedText
                    text: root.notifActive ? ("Notif (" + root.notifCount + ")") : (root.mediaPlaying ? (root.activePlayer.trackTitle || "Playing") : "")
                    font.pixelSize: 11
                    font.bold: true
                    color: Services.Theme.textPrimary

                    SequentialAnimation on x {
                        running: root.mediaPlaying && !root.expanded && collapsedText.implicitWidth > collapsedTextContainer.width
                        loops: Animation.Infinite

                        PauseAnimation { duration: 1200 }
                        NumberAnimation {
                            to: -(collapsedText.implicitWidth - collapsedTextContainer.width + 4)
                            duration: Math.max(2000, (collapsedText.implicitWidth - collapsedTextContainer.width) * 35)
                            easing.type: Easing.InOutQuad
                        }
                        PauseAnimation { duration: 1200 }
                        NumberAnimation {
                            to: 0
                            duration: Math.max(2000, (collapsedText.implicitWidth - collapsedTextContainer.width) * 35)
                            easing.type: Easing.InOutQuad
                        }
                    }
                }
            }
        }

        // ==================== Expanded: Notifications ====================
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4
            visible: root.expanded && root.notifActive
            opacity: visible ? 1 : 0
            z: 1
            Behavior on opacity { NumberAnimation { duration: 200 } }

            // Header: Icon, AppName, Queue Indicator, Controls & Close
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                // App Icon / Image
                Item {
                    implicitWidth: 20
                    implicitHeight: 20
                    Layout.alignment: Qt.AlignVCenter

                    IconImage {
                        id: appIconImg
                        anchors.fill: parent
                        source: root.currentNotif ? (root.currentNotif.image || root.currentNotif.appIcon || "") : ""
                        visible: status === Image.Ready
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "󰂚"
                        font.family: "Liga SFMono Nerd Font"
                        font.pixelSize: 14
                        color: Services.Theme.accent
                        visible: !appIconImg.visible
                    }
                }

                // App Name
                Text {
                    text: root.currentNotif ? root.currentNotif.appName : ""
                    color: Services.Theme.textSecondary
                    font.pixelSize: 11
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                // Queue indicator & Navigation if multiple notifications
                RowLayout {
                    spacing: 4
                    visible: root.notifCount > 1 && !root.replyMode
                    Layout.alignment: Qt.AlignVCenter

                    Rectangle {
                        color: Services.Theme.surfaceVariant
                        radius: 8
                        implicitWidth: queueText.implicitWidth + 10
                        implicitHeight: 18

                        Text {
                            id: queueText
                            anchors.centerIn: parent
                            text: (root.activeNotifIndex + 1) + "/" + root.notifCount
                            color: Services.Theme.textSecondary
                            font.pixelSize: 10
                            font.bold: true
                        }
                    }

                    // Prev Notif Button
                    Rectangle {
                        implicitWidth: 20; implicitHeight: 20
                        radius: 10
                        color: prevMouse.containsMouse ? Services.Theme.borderHighlight : "transparent"
                        Text { anchors.centerIn: parent; text: "‹"; color: Services.Theme.textPrimary; font.pixelSize: 14; font.bold: true }
                        MouseArea {
                            id: prevMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: (mouse) => { root.prevNotif(); mouse.accepted = true }
                        }
                    }

                    // Next Notif Button
                    Rectangle {
                        implicitWidth: 20; implicitHeight: 20
                        radius: 10
                        color: nextMouse.containsMouse ? Services.Theme.borderHighlight : "transparent"
                        Text { anchors.centerIn: parent; text: "›"; color: Services.Theme.textPrimary; font.pixelSize: 14; font.bold: true }
                        MouseArea {
                            id: nextMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: (mouse) => { root.nextNotif(); mouse.accepted = true }
                        }
                    }
                }

                // Dismiss Button (X)
                Rectangle {
                    implicitWidth: 20; implicitHeight: 20
                    radius: 10
                    color: dismissBtnMouse.containsMouse ? Services.Theme.danger : Services.Theme.surfaceVariant
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: Services.Theme.textPrimary
                        font.pixelSize: 10
                        font.bold: true
                    }

                    MouseArea {
                        id: dismissBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: (mouse) => {
                            if (root.currentNotif) {
                                root.replyMode = false
                                Services.Notifications.dismiss(root.currentNotif.notifId)
                            }
                            mouse.accepted = true
                        }
                    }
                }
            }

            // Summary & Body (Only when NOT in Reply Mode)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                visible: !root.replyMode

                Text {
                    text: root.currentNotif ? (root.currentNotif.summary || "") : ""
                    color: Services.Theme.textPrimary
                    font.pixelSize: 13
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Text {
                    visible: root.hasNotifBody
                    text: root.currentNotif ? (root.currentNotif.body || "") : ""
                    color: Services.Theme.textSecondary
                    font.pixelSize: 11
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            // Action Buttons (Only when NOT in Reply Mode)
            RowLayout {
                id: notifActionsRow
                visible: root.hasNotifActions && !root.replyMode
                spacing: 6
                Layout.topMargin: 2
                Layout.fillWidth: true

                Repeater {
                    model: root.currentNotif ? root.currentNotif.actions : null
                    delegate: Rectangle {
                        id: actBtn
                        required property string identifier
                        required property string text

                        implicitHeight: 24
                        implicitWidth: actLabel.implicitWidth + 16
                        radius: Services.Theme.radiusSm
                        color: actMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.surfaceVariant

                        Text {
                            id: actLabel
                            anchors.centerIn: parent
                            text: actBtn.text
                            color: Services.Theme.textPrimary
                            font.pixelSize: 11
                            font.bold: true
                        }

                        MouseArea {
                            id: actMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: (mouse) => {
                                if (root.currentNotif) {
                                    if (root.isReplyAction(actBtn)) {
                                        root.activeReplyActionId = actBtn.identifier
                                        root.replyMode = true
                                    } else {
                                        Services.Notifications.invokeAction(root.currentNotif.notifId, actBtn.identifier)
                                    }
                                }
                                mouse.accepted = true
                            }
                        }
                    }
                }
            }

            // ==================== Type Zone (Inline Reply Mode) ====================
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: root.replyMode

                Text {
                    text: root.currentNotif ? ("Balas: " + (root.currentNotif.summary || root.currentNotif.appName)) : "Balas Notifikasi"
                    color: Services.Theme.textSecondary
                    font.pixelSize: 11
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: 8
                    color: Services.Theme.surfaceVariant
                    border.color: replyInput.activeFocus ? Services.Theme.accent : Services.Theme.border
                    border.width: 1

                    TextInput {
                        id: replyInput
                        anchors.fill: parent
                        anchors.margins: 6
                        color: Services.Theme.textPrimary
                        font.pixelSize: 12
                        clip: true
                        focus: root.replyMode

                        Text {
                            text: "Tulis balasan..."
                            color: Services.Theme.textDisabled
                            font.pixelSize: 12
                            visible: replyInput.text.length === 0 && !replyInput.activeFocus
                        }

                        Keys.onReturnPressed: {
                            if (root.currentNotif && replyInput.text.trim().length > 0) {
                                Services.Notifications.invokeAction(root.currentNotif.notifId, root.activeReplyActionId, replyInput.text.trim())
                                root.replyMode = false
                                replyInput.text = ""
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
                        color: cancelMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.surfaceVariant

                        Text {
                            id: cancelTxt
                            anchors.centerIn: parent
                            text: "Batal"
                            color: Services.Theme.textSecondary
                            font.pixelSize: 10
                            font.bold: true
                        }

                        MouseArea {
                            id: cancelMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: (mouse) => {
                                root.replyMode = false
                                replyInput.text = ""
                                mouse.accepted = true
                            }
                        }
                    }

                    // Send Button
                    Rectangle {
                        implicitHeight: 22
                        implicitWidth: sendTxt.implicitWidth + 14
                        radius: 6
                        color: sendMouse.containsMouse ? Qt.lighter(Services.Theme.accent, 1.1) : Services.Theme.accent

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
                            onClicked: (mouse) => {
                                if (root.currentNotif && replyInput.text.trim().length > 0) {
                                    Services.Notifications.invokeAction(root.currentNotif.notifId, root.activeReplyActionId, replyInput.text.trim())
                                    root.replyMode = false
                                    replyInput.text = ""
                                }
                                mouse.accepted = true
                            }
                        }
                    }
                }
            }
        }

        // ==================== Expanded: System HUD Alert (Mute, DnD, Charging) ====================
        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10
            visible: root.expanded && !root.notifActive && root.sysHudActive
            opacity: visible ? 1 : 0
            z: 1
            Behavior on opacity { NumberAnimation { duration: 200 } }

            Rectangle {
                implicitWidth: 32
                implicitHeight: 32
                radius: 16
                color: Services.Theme.surfaceVariant
                Layout.alignment: Qt.AlignVCenter

                Text {
                    anchors.centerIn: parent
                    text: root.sysHudIcon
                    font.family: "Liga SFMono Nerd Font"
                    font.pixelSize: 15
                    color: root.sysHudColor
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                Text {
                    text: root.sysHudTitle
                    color: Services.Theme.textPrimary
                    font.pixelSize: 12
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Text {
                    visible: root.sysHudDetail.length > 0
                    text: root.sysHudDetail
                    color: Services.Theme.textSecondary
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }

        // ==================== Expanded: Media Controls (Full Control) ====================
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6
            visible: root.expanded && !root.notifActive && !root.sysHudActive && root.hasMedia
            opacity: visible ? 1 : 0
            z: 1
            Behavior on opacity { NumberAnimation { duration: 200 } }

            // Row 1: Track Art + Info + Player Badge
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                // Artwork
                Rectangle {
                    implicitWidth: 40
                    implicitHeight: 40
                    radius: 8
                    color: Services.Theme.surfaceVariant
                    clip: true
                    Layout.alignment: Qt.AlignVCenter

                    Image {
                        id: albumArtImg
                        anchors.fill: parent
                        source: root.activePlayer ? (root.activePlayer.trackArtUrl || root.activePlayer.artUrl || "") : ""
                        fillMode: Image.PreserveAspectCrop
                        visible: status === Image.Ready
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "󰎈"
                        font.family: "Liga SFMono Nerd Font"
                        font.pixelSize: 20
                        color: Services.Theme.accent
                        visible: !albumArtImg.visible
                    }
                }

                // Info (Title, Artist, Identity)
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 1

                    RowLayout {
                        spacing: 6
                        visible: (root.activePlayer?.identity ?? "").length > 0

                        Rectangle {
                            implicitHeight: 14
                            implicitWidth: Math.min(identityTxt.implicitWidth + 8, 80)
                            radius: 4
                            color: Services.Theme.surfaceVariant

                            Text {
                                id: identityTxt
                                anchors.centerIn: parent
                                text: root.activePlayer ? (root.activePlayer.identity || "") : ""
                                color: Services.Theme.textDisabled
                                font.pixelSize: 8
                                font.bold: true
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Text {
                        text: root.activePlayer ? (root.activePlayer.trackTitle || "Unknown Track") : "—"
                        color: Services.Theme.textPrimary
                        font.pixelSize: 12
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: root.activePlayer ? (root.activePlayer.trackArtist || "") : ""
                        color: Services.Theme.textSecondary
                        font.pixelSize: 10
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        visible: text.length > 0
                    }
                }
            }

            // Row 2: Progress Bar & Timers
            Item {
                Layout.fillWidth: true
                implicitHeight: 16
                visible: root.activePlayer !== null

                Text {
                    id: posLabel
                    anchors { left: parent.left; top: parent.top }
                    text: root.fmtTime(root.activePlayer?.position)
                    color: Services.Theme.textDisabled
                    font.pixelSize: 9
                }

                Text {
                    id: durLabel
                    anchors { right: parent.right; top: parent.top }
                    text: {
                        const len = root.activePlayer?.length ?? 0
                        return len > 0 ? root.fmtTime(len) : "--:--"
                    }
                    color: Services.Theme.textDisabled
                    font.pixelSize: 9
                }

                Rectangle {
                    id: progressBg
                    anchors {
                        left: posLabel.right; right: durLabel.left
                        leftMargin: 8; rightMargin: 8
                        verticalCenter: parent.verticalCenter
                    }
                    height: 4
                    radius: 2
                    color: Services.Theme.surfaceVariant

                    Rectangle {
                        id: progressFill
                        height: parent.height
                        radius: 2
                        color: Services.Theme.accent
                        width: {
                            const len = root.activePlayer?.length ?? 0
                            const pos = root.activePlayer?.position ?? 0
                            return len > 0 ? Math.max(0, Math.min(1, pos / len)) * parent.width : 0
                        }
                        Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.Linear } }
                    }
                }

                MouseArea {
                    id: seekArea
                    anchors.fill: progressBg
                    hoverEnabled: true
                    onClicked: (mouse) => {
                        const ratio = mouse.x / width
                        const len = root.activePlayer?.length ?? 0
                        if (len > 0 && (root.activePlayer?.positionSupported ?? false))
                            root.activePlayer.position = ratio * len
                    }
                }
            }

            // Row 3: Full Controls (Shuffle, Prev, Play/Pause, Next, Repeat)
            RowLayout {
                Layout.fillWidth: true
                spacing: 0

                // Shuffle
                Item {
                    implicitWidth: 28; implicitHeight: 28
                    opacity: (root.activePlayer?.shuffleSupported ?? false) ? 1 : 0.2
                    Rectangle { anchors.fill: parent; radius: 6; color: shArea.containsMouse ? Services.Theme.surfaceVariant : "transparent" }
                    Text {
                        anchors.centerIn: parent
                        text: "\uf074"
                        font.family: "Symbols Nerd Font Mono"
                        font.pixelSize: 11
                        color: (root.activePlayer?.shuffle ?? false) ? Services.Theme.accent : Services.Theme.textSecondary
                    }
                    MouseArea {
                        id: shArea; anchors.fill: parent; hoverEnabled: true
                        enabled: root.activePlayer?.shuffleSupported ?? false
                        onClicked: (mouse) => { root.activePlayer.shuffle = !root.activePlayer.shuffle; mouse.accepted = true }
                    }
                }

                Item { Layout.fillWidth: true }

                // Previous
                Item {
                    implicitWidth: 28; implicitHeight: 28
                    opacity: (root.activePlayer?.canGoPrevious ?? false) ? 1 : 0.3
                    Rectangle { anchors.fill: parent; radius: 6; color: prvArea.containsMouse ? Services.Theme.surfaceVariant : "transparent" }
                    Text {
                        anchors.centerIn: parent
                        text: "\uf04a"
                        font.family: "Symbols Nerd Font Mono"
                        font.pixelSize: 12
                        color: Services.Theme.textPrimary
                    }
                    MouseArea {
                        id: prvArea; anchors.fill: parent; hoverEnabled: true
                        enabled: root.activePlayer?.canGoPrevious ?? false
                        onClicked: (mouse) => { root.activePlayer.previous(); mouse.accepted = true }
                    }
                }

                // Play / Pause (Filled button)
                Rectangle {
                    implicitWidth: 30; implicitHeight: 30
                    radius: 8
                    color: playArea.containsMouse ? Qt.lighter(Services.Theme.accent, 1.1) : Services.Theme.accent

                    Text {
                        anchors.centerIn: parent
                        text: root.mediaPlaying ? "\uf04c" : "\uf04b"
                        font.family: "Symbols Nerd Font Mono"
                        font.pixelSize: 12
                        color: "#0a0a0a"
                    }
                    MouseArea {
                        id: playArea; anchors.fill: parent; hoverEnabled: true
                        enabled: root.activePlayer?.canTogglePlaying ?? true
                        onClicked: (mouse) => { root.activePlayer.playPause(); mouse.accepted = true }
                    }
                }

                // Next
                Item {
                    implicitWidth: 28; implicitHeight: 28
                    opacity: (root.activePlayer?.canGoNext ?? false) ? 1 : 0.3
                    Rectangle { anchors.fill: parent; radius: 6; color: nxtArea.containsMouse ? Services.Theme.surfaceVariant : "transparent" }
                    Text {
                        anchors.centerIn: parent
                        text: "\uf04e"
                        font.family: "Symbols Nerd Font Mono"
                        font.pixelSize: 12
                        color: Services.Theme.textPrimary
                    }
                    MouseArea {
                        id: nxtArea; anchors.fill: parent; hoverEnabled: true
                        enabled: root.activePlayer?.canGoNext ?? false
                        onClicked: (mouse) => { root.activePlayer.next(); mouse.accepted = true }
                    }
                }

                Item { Layout.fillWidth: true }

                // Repeat
                Item {
                    implicitWidth: 28; implicitHeight: 28
                    opacity: (root.activePlayer?.loopSupported ?? false) ? 1 : 0.2
                    Rectangle { anchors.fill: parent; radius: 6; color: rpArea.containsMouse ? Services.Theme.surfaceVariant : "transparent" }
                    Text {
                        anchors.centerIn: parent
                        font.family: "Symbols Nerd Font Mono"
                        font.pixelSize: 11
                        text: (root.activePlayer?.loop ?? MprisLoopState.None) === MprisLoopState.Track ? "\uf365" : "\uf364"
                        color: (root.activePlayer?.loop ?? MprisLoopState.None) !== MprisLoopState.None ? Services.Theme.accent : Services.Theme.textSecondary
                    }
                    MouseArea {
                        id: rpArea; anchors.fill: parent; hoverEnabled: true
                        enabled: root.activePlayer?.loopSupported ?? false
                        onClicked: (mouse) => {
                            const l = root.activePlayer?.loop ?? MprisLoopState.None
                            if (l === MprisLoopState.None)           root.activePlayer.loop = MprisLoopState.Playlist
                            else if (l === MprisLoopState.Playlist)  root.activePlayer.loop = MprisLoopState.Track
                            else                                     root.activePlayer.loop = MprisLoopState.None
                            mouse.accepted = true
                        }
                    }
                }
            }
        }

        // ==================== Expanded: Pinned Fallback ====================
        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8
            visible: root.expanded && !root.notifActive && !root.sysHudActive && !root.hasMedia
            opacity: visible ? 1 : 0
            z: 1
            Behavior on opacity { NumberAnimation { duration: 200 } }

            Text {
                text: "󰐃"
                font.family: "Liga SFMono Nerd Font"
                font.pixelSize: 16
                color: Services.Theme.accent
            }

            Text {
                text: "Pinned"
                color: Services.Theme.textPrimary
                font.pixelSize: 12
                font.bold: true
                Layout.fillWidth: true
            }
        }
    }
}




