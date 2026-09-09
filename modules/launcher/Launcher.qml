import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../services" as Services

PanelWindow {
    id: launcherWindow
    visible: false

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell:launcher"
    exclusiveZone: 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    Component.onCompleted: Services.OverlayManager.register(launcherWindow)

    property bool isOpen: false
    readonly property bool hasQuery: searchField.text.trim().length > 0
    readonly property bool isExpanded: hasQuery

    property var contextMenuApp: null
    property real contextMenuX: 0
    property real contextMenuY: 0
    readonly property bool isContextMenuOpen: contextMenuApp !== null

    function openContextMenu(app, x, y) {
        contextMenuApp = app
        const menuWidth = 220
        const menuHeight = 180
        contextMenuX = Math.max(10, Math.min(x, panel.width - menuWidth - 10))
        contextMenuY = Math.max(10, Math.min(y, panel.height - menuHeight - 10))
    }

    function closeContextMenu() {
        contextMenuApp = null
    }

    function show() {
        closeContextMenu()
        Services.OverlayManager.closeAllExcept(launcherWindow)
        hideTimer.stop()
        visible = true
        isOpen = true
        Services.Applications.query = ""
        searchField.text = ""
        searchField.forceActiveFocus()
        resultList.currentIndex = 0
        if (resultList.count > 0) {
            resultList.positionViewAtIndex(0, ListView.Beginning)
        }
    }

    function hide() {
        if (!isOpen) return
        closeContextMenu()
        isOpen = false
        hideTimer.restart()
    }

    function toggle() { isOpen ? hide() : show() }

    Timer {
        id: hideTimer
        interval: 220
        onTriggered: {
            launcherWindow.visible = false
            Services.Applications.query = ""
        }
    }

    // Click outside panel → close
    MouseArea {
        anchors.fill: parent
        onClicked: launcherWindow.hide()
    }

    // ── Panel ─────────────────────────────────────────────────────────
    Rectangle {
        id: panel
        anchors.centerIn: parent
        anchors.verticalCenterOffset: launcherWindow.isOpen ? -40 : -20

        Behavior on anchors.verticalCenterOffset {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        width: 540
        height: launcherWindow.isExpanded ? 460 : 58
        clip: true

        Behavior on width {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
        Behavior on height {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        radius: 16
        color: Services.Theme.surface
        border.color: Services.Theme.border
        border.width: 1

        opacity: launcherWindow.isOpen ? 1 : 0
        scale: launcherWindow.isOpen ? 1 : 0.97

        Behavior on opacity {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
        Behavior on border.color {
            ColorAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        MouseArea { 
            anchors.fill: parent 
            onClicked: {
                if (launcherWindow.isContextMenuOpen) {
                    launcherWindow.closeContextMenu()
                }
            }
        }

        // ── Floating App Context Menu ────────────────────────────────────────
        MouseArea {
            anchors.fill: parent
            visible: launcherWindow.isContextMenuOpen
            z: 98
            onClicked: launcherWindow.closeContextMenu()
        }

        Rectangle {
            id: contextMenuBox
            visible: launcherWindow.isContextMenuOpen
            z: 99
            x: launcherWindow.contextMenuX
            y: launcherWindow.contextMenuY
            width: 220
            height: menuCol.implicitHeight + 16
            radius: 12
            color: Services.Theme.bgElevated
            border.color: Services.Theme.borderHighlight
            border.width: 1

            // Specular top highlight
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 1
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                height: 1
                color: Qt.rgba(1, 1, 1, 0.15)
            }

            ColumnLayout {
                id: menuCol
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 8
                spacing: 4

                // Header with App Title & Desktop ID
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.margins: 4
                    spacing: 2

                    Text {
                        text: launcherWindow.contextMenuApp ? (launcherWindow.contextMenuApp.name || "") : ""
                        font.pixelSize: Services.Theme.fontSizeMd
                        font.weight: Font.DemiBold
                        color: Services.Theme.textPrimary
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: launcherWindow.contextMenuApp ? (launcherWindow.contextMenuApp.id || "Desktop Application") : ""
                        font.family: Services.Theme.fontMono
                        font.pixelSize: 10
                        color: Services.Theme.textDisabled
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Services.Theme.border
                    opacity: 0.6
                }

                // 1. Launch Action
                Rectangle {
                    Layout.fillWidth: true
                    height: 30
                    radius: 6
                    color: launchMouse.containsMouse ? Services.Theme.bgHover : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8; anchors.rightMargin: 8
                        spacing: 8

                        Text {
                            text: Services.Icons.play || "▶"
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 12
                            color: Services.Theme.accent
                        }
                        Text {
                            text: "Launch"
                            font.pixelSize: Services.Theme.fontSizeSm
                            color: Services.Theme.textPrimary
                            Layout.fillWidth: true
                        }
                    }

                    MouseArea {
                        id: launchMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const app = launcherWindow.contextMenuApp
                            launcherWindow.closeContextMenu()
                            launcherWindow.hide()
                            if (app && typeof app.execute === "function") {
                                app.execute()
                            }
                        }
                    }
                }

                // 2. Pin / Unpin Action
                Rectangle {
                    Layout.fillWidth: true
                    height: 30
                    radius: 6
                    readonly property bool pinned: (launcherWindow.contextMenuApp && Services.DockService) ? Services.DockService.isPinned(launcherWindow.contextMenuApp.id) : false
                    color: pinMouse.containsMouse ? Services.Theme.bgHover : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8; anchors.rightMargin: 8
                        spacing: 8

                        Text {
                            text: Services.Icons.pin || "󰤩"
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 12
                            color: parent.parent.pinned ? Services.Theme.danger : Services.Theme.accent
                        }
                        Text {
                            text: parent.parent.pinned ? "Unpin from Dock" : "Pin to Dock"
                            font.pixelSize: Services.Theme.fontSizeSm
                            color: parent.parent.pinned ? Services.Theme.danger : Services.Theme.textPrimary
                            Layout.fillWidth: true
                        }
                    }

                    MouseArea {
                        id: pinMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const app = launcherWindow.contextMenuApp
                            if (app && app.id && Services.DockService) {
                                Services.DockService.togglePin(app.id)
                            }
                            launcherWindow.closeContextMenu()
                        }
                    }
                }

                // 3. Desktop Entry Actions (e.g. New Window, Private Window)
                Repeater {
                    model: (launcherWindow.contextMenuApp && launcherWindow.contextMenuApp.actions) ? launcherWindow.contextMenuApp.actions : []
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        height: 30
                        radius: 6
                        color: actMouse.containsMouse ? Services.Theme.bgHover : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8; anchors.rightMargin: 8
                            spacing: 8

                            Text {
                                text: "✦"
                                font.pixelSize: 10
                                color: Services.Theme.textSecondary
                            }
                            Text {
                                text: modelData.name || "Action"
                                font.pixelSize: Services.Theme.fontSizeSm
                                color: Services.Theme.textPrimary
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        MouseArea {
                            id: actMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                launcherWindow.closeContextMenu()
                                launcherWindow.hide()
                                if (typeof modelData.execute === "function") {
                                    modelData.execute()
                                }
                            }
                        }
                    }
                }

                // 4. Copy Desktop ID
                Rectangle {
                    Layout.fillWidth: true
                    height: 28
                    radius: 6
                    color: copyMouse.containsMouse ? Services.Theme.bgHover : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8; anchors.rightMargin: 8
                        spacing: 8

                        Text {
                            text: Services.Icons.disk || "📋"
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 11
                            color: Services.Theme.textSecondary
                        }
                        Text {
                            text: "Copy App ID"
                            font.pixelSize: Services.Theme.fontSizeXs
                            color: Services.Theme.textSecondary
                            Layout.fillWidth: true
                        }
                    }

                    Process {
                        id: copyProc
                        command: []
                    }

                    MouseArea {
                        id: copyMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const app = launcherWindow.contextMenuApp
                            if (app && app.id) {
                                copyProc.command = ["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", app.id]
                                copyProc.running = true
                            }
                            launcherWindow.closeContextMenu()
                        }
                    }
                }
            }
        }

        ColumnLayout {
            id: listCol
            anchors.fill: parent
            spacing: 0

            // ── Search Bar ────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 58
                Layout.leftMargin: 16; Layout.rightMargin: 16
                spacing: 10

                Text {
                    text: Services.Icons.search
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: Services.Theme.fontSize2xl
                    color: searchField.activeFocus ? Services.Theme.accent : Services.Theme.textDisabled
                    Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }

                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    background: null
                    color: Services.Theme.textPrimary
                    placeholderText: "Search applications..."
                    placeholderTextColor: Services.Theme.textDisabled
                    font.pixelSize: Services.Theme.fontSize3xl
                    leftPadding: 0
                    rightPadding: 0

                    onTextChanged: {
                        Services.Applications.query = text
                        resultList.currentIndex = 0
                        if (resultList.count > 0) {
                            resultList.positionViewAtIndex(0, ListView.Beginning)
                        }
                    }

                    Keys.onPressed: (event) => {
                        // Global Settings Shortcut: Ctrl+, or Ctrl+S or Alt+S
                        if ((event.modifiers & Qt.ControlModifier && (event.key === Qt.Key_Comma || event.key === Qt.Key_S)) ||
                            (event.modifiers & Qt.AltModifier && event.key === Qt.Key_S)) {
                            launcherWindow.hide()
                            Services.OverlayManager.openSettings()
                            event.accepted = true
                            return
                        }

                        if (event.key === Qt.Key_Down) {
                            resultList.currentIndex = Math.min(resultList.currentIndex + 1, resultList.count - 1)
                            resultList.positionViewAtIndex(resultList.currentIndex, ListView.Contain)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Up) {
                            resultList.currentIndex = Math.max(resultList.currentIndex - 1, 0)
                            resultList.positionViewAtIndex(resultList.currentIndex, ListView.Contain)
                            event.accepted = true
                        } else if (event.key === Qt.Key_PageDown) {
                            resultList.currentIndex = Math.min(resultList.currentIndex + 5, resultList.count - 1)
                            resultList.positionViewAtIndex(resultList.currentIndex, ListView.Contain)
                            event.accepted = true
                        } else if (event.key === Qt.Key_PageUp) {
                            resultList.currentIndex = Math.max(resultList.currentIndex - 5, 0)
                            resultList.positionViewAtIndex(resultList.currentIndex, ListView.Contain)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            const apps = resultList.model
                            if (apps && apps.length > resultList.currentIndex) {
                                const app = apps[resultList.currentIndex]
                                if (app) {
                                    launcherWindow.hide()
                                    if (typeof app.execute === "function") {
                                        app.execute()
                                    }
                                }
                            }
                            event.accepted = true
                        } else if (event.key === Qt.Key_Escape) {
                            if (launcherWindow.isContextMenuOpen) {
                                launcherWindow.closeContextMenu()
                                event.accepted = true
                                return
                            }
                            launcherWindow.hide()
                            event.accepted = true
                        }
                    }
                }

                // Clear button
                Text {
                    text: "✕"
                    font.pixelSize: Services.Theme.fontSizeLg
                    color: clearMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textDisabled
                    visible: searchField.text.length > 0
                    Layout.alignment: Qt.AlignVCenter

                    MouseArea {
                        id: clearMouse
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        onClicked: {
                            searchField.text = ""
                            searchField.forceActiveFocus()
                        }
                    }
                }

                // Dedicated Quick Settings Button
                Rectangle {
                    width: 26; height: 26; radius: 6
                    color: settingsBtnMouse.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                    Layout.alignment: Qt.AlignVCenter
                    Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }

                    Text {
                        anchors.centerIn: parent
                        text: Services.Icons.settings
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: Services.Theme.fontSizeMd
                        color: settingsBtnMouse.containsMouse ? Services.Theme.accent : Services.Theme.textDisabled
                        Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    }

                    MouseArea {
                        id: settingsBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            launcherWindow.hide()
                            Services.OverlayManager.openSettings()
                        }
                    }
                }
            }

            // Hairline divider
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Services.Theme.border
                opacity: launcherWindow.isExpanded ? 0.6 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
            }

            // ═════════════════════════════════════════════════════════════════
            // ── APPLICATIONS LIST VIEW ───────────────────────────────────────
            // ═════════════════════════════════════════════════════════════════
            ListView {
                id: resultList
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: launcherWindow.isExpanded
                clip: true
                spacing: 3
                model: Services.Applications.filteredApps
                currentIndex: 0
                keyNavigationEnabled: false
                reuseItems: true
                cacheBuffer: 600
                topMargin: 6; bottomMargin: 6
                leftMargin: 8; rightMargin: 8
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: appItem
                    required property var modelData
                    required property int index
                    width: resultList.width - 16
                    height: 48
                    radius: 10

                    readonly property bool isCurrent: appItem.index === resultList.currentIndex

                    color: isCurrent 
                        ? Services.Theme.surfaceVariant 
                        : (hoverArea.containsMouse ? Services.Theme.bgHover : "transparent")
                    border.color: isCurrent ? Services.Theme.accent : "transparent"
                    border.width: isCurrent ? 1 : 0
                    Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    Behavior on border.color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12; anchors.rightMargin: 12
                        spacing: 12

                        // App Icon
                        Item {
                            Layout.preferredWidth: 32; Layout.preferredHeight: 32
                            Layout.alignment: Qt.AlignVCenter

                            // Fallback letter if icon cannot be loaded
                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: appItem.index === resultList.currentIndex ? Qt.rgba(255, 255, 255, 0.1) : Qt.rgba(255, 255, 255, 0.05)
                                visible: !ico.source || ico.status !== Image.Ready || !ico.visible

                                Text {
                                    anchors.centerIn: parent
                                    text: (appItem.modelData.name || "?").charAt(0).toUpperCase()
                                    color: appItem.index === resultList.currentIndex ? Services.Theme.accent : Services.Theme.textDisabled
                                    font.pixelSize: Services.Theme.fontSizeXl
                                    font.bold: true
                                }
                            }

                            Image {
                                id: ico
                                anchors.fill: parent
                                source: {
                                    const rawIcon = appItem.modelData ? (typeof appItem.modelData.icon === "string" ? appItem.modelData.icon : (appItem.modelData.icon?.name || "")) : ""
                                    if (!rawIcon) return ""
                                    if (Services.SystemTheme) {
                                        const res = Services.SystemTheme.getIcon(rawIcon)
                                        if (res && res.length > 0) return res
                                    }
                                    if (rawIcon.startsWith("file://") || rawIcon.startsWith("http://") || rawIcon.startsWith("https://")) return rawIcon
                                    if (rawIcon.startsWith("/")) return "file://" + rawIcon
                                    let s = rawIcon.startsWith("image://icon/") ? rawIcon.substring(13) : rawIcon
                                    if (s.startsWith("image://")) return s
                                    const qp = Quickshell.iconPath(s, true)
                                    return (qp && qp.startsWith("/")) ? ("file://" + qp) : (qp || "")
                                }
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: true
                                sourceSize: Qt.size(64, 64)
                                mipmap: true
                                smooth: true
                                visible: ico.status === Image.Ready && ico.source.toString().length > 0
                            }
                        }

                        // App Name & Description
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 1

                            Text {
                                text: appItem.modelData.name || ""
                                color: appItem.index === resultList.currentIndex ? Services.Theme.accent : Services.Theme.textPrimary
                                font.pixelSize: Services.Theme.fontSizeXl
                                font.weight: appItem.index === resultList.currentIndex ? Font.Medium : Font.Normal
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            }

                            Text {
                                property string subText: appItem.modelData.description || appItem.modelData.comment || ""
                                text: (subText.length > 0 && subText !== appItem.modelData.name) ? subText : "Application"
                                color: Services.Theme.textSecondary
                                font.pixelSize: Services.Theme.fontSizeMd
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }

                    MouseArea {
                        id: hoverArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onPositionChanged: {
                            if (resultList.currentIndex !== appItem.index) {
                                resultList.currentIndex = appItem.index
                            }
                        }
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton) {
                                const pt = mapToItem(panel, mouse.x, mouse.y)
                                launcherWindow.openContextMenu(appItem.modelData, pt.x, pt.y)
                            } else {
                                launcherWindow.closeContextMenu()
                                launcherWindow.hide()
                                if (typeof appItem.modelData.execute === "function") {
                                    appItem.modelData.execute()
                                }
                            }
                        }
                    }
                }

                // Empty state
                Item {
                    anchors.fill: parent
                    visible: resultList.count === 0

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: Services.Icons.search
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: Services.Theme.fontSize8xl
                            color: Services.Theme.textDisabled
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Text {
                            text: "No applications found"
                            color: Services.Theme.textDisabled
                            font.pixelSize: Services.Theme.fontSizeXl
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
            }

            // Bottom Action Strip
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                color: Services.Theme.bgDeep
                radius: 12
                border.width: 0
                visible: launcherWindow.isExpanded

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14; anchors.rightMargin: 14
                    spacing: 12

                    // App count info
                    Text {
                        text: {
                            const count = Services.Applications.filteredApps ? Services.Applications.filteredApps.length : 0
                            return count + " application" + (count === 1 ? "" : "s")
                        }
                        color: Services.Theme.textDisabled
                        font.pixelSize: Services.Theme.fontSizeSm
                    }

                    Item { Layout.fillWidth: true }

                    // Navigation Hints
                    RowLayout {
                        spacing: 10

                        RowLayout {
                            spacing: 4
                            Text {
                                text: "↑↓"
                                color: Services.Theme.textSecondary
                                font.pixelSize: Services.Theme.fontSizeXs
                                font.family: Services.Theme.fontMono
                            }
                            Text {
                                text: "Navigate"
                                color: Services.Theme.textDisabled
                                font.pixelSize: Services.Theme.fontSizeXs
                            }
                        }

                        RowLayout {
                            spacing: 4
                            Text {
                                text: "↵"
                                color: Services.Theme.accent
                                font.pixelSize: Services.Theme.fontSizeSm
                                font.bold: true
                            }
                            Text {
                                text: "Launch"
                                color: Services.Theme.textDisabled
                                font.pixelSize: Services.Theme.fontSizeXs
                            }
                        }

                        RowLayout {
                            spacing: 4
                            Text {
                                text: "Ctrl+,"
                                color: Services.Theme.textSecondary
                                font.pixelSize: Services.Theme.fontSizeXs
                                font.family: Services.Theme.fontMono
                            }
                            Text {
                                text: "Settings"
                                color: Services.Theme.textDisabled
                                font.pixelSize: Services.Theme.fontSizeXs
                            }
                        }

                        RowLayout {
                            spacing: 4
                            Text {
                                text: "Esc"
                                color: Services.Theme.textSecondary
                                font.pixelSize: Services.Theme.fontSizeXs
                                font.family: Services.Theme.fontMono
                            }
                            Text {
                                text: "Close"
                                color: Services.Theme.textDisabled
                                font.pixelSize: Services.Theme.fontSizeXs
                            }
                        }
                    }
                }
            }
        }
    }
}
