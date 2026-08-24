import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
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

    // ── Mode detection ───────────────────────────────────────────────────
    readonly property bool isEmojiMode: searchField.text.startsWith(">E") || searchField.text.startsWith(">e")
    readonly property string emojiQuery: isEmojiMode ? searchField.text.substring(2).trim() : ""

    readonly property bool isWallpaperMode: searchField.text.startsWith(">W") || searchField.text.startsWith(">w")
    readonly property string wallpaperQuery: isWallpaperMode ? searchField.text.substring(2).trim().toLowerCase() : ""

    readonly property bool isSettingsMode: {
        const t = searchField.text.trim().toLowerCase()
        return t === ">s" || t === ">setting" || t === ">settings" || t === ">config" || t === ">set"
    }

    readonly property bool hasQuery: searchField.text.trim().length > 0
    readonly property bool isExpanded: isEmojiMode || isWallpaperMode || isSettingsMode || hasQuery
    property var emojiResults: []
    property int emojiCurrentIndex: 0
    readonly property int emojiColumns: 10

    property int wallpaperCurrentIndex: 0
    readonly property var wallpaperList: {
        const all = (Services.Wallpaper && Services.Wallpaper.allWallpapers) ? Services.Wallpaper.allWallpapers : []
        if (!isWallpaperMode || wallpaperQuery.length === 0) return all
        return all.filter(w => {
            const name = (w.name || "").toLowerCase()
            const path = (w.path || "").toLowerCase()
            return name.indexOf(wallpaperQuery) !== -1 || path.indexOf(wallpaperQuery) !== -1
        })
    }

    function show() {
        Services.OverlayManager.closeAllExcept(launcherWindow)
        hideTimer.stop()
        visible = true
        isOpen = true
        Services.Applications.query = ""
        searchField.text = ""
        emojiResults = []
        emojiCurrentIndex = 0
        wallpaperCurrentIndex = 0
        searchField.forceActiveFocus()
        resultList.currentIndex = 0
        if (resultList.count > 0) {
            resultList.positionViewAtIndex(0, ListView.Beginning)
        }
    }

    function hide() {
        if (!isOpen) return
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

        width: launcherWindow.isWallpaperMode ? 620 : (launcherWindow.isEmojiMode ? 560 : 540)
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
        border.color: (launcherWindow.isEmojiMode || launcherWindow.isWallpaperMode) ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.4) : Services.Theme.border
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

        MouseArea { anchors.fill: parent }

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
                    color: (launcherWindow.isEmojiMode || launcherWindow.isWallpaperMode) ? Services.Theme.accent : (searchField.activeFocus ? Services.Theme.accent : Services.Theme.textDisabled)
                    Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }

                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    background: null
                    color: Services.Theme.textPrimary
                    placeholderText: launcherWindow.isEmojiMode 
                        ? (launcherWindow.emojiQuery.length === 0 ? "Search 1,800+ emojis... (e.g. fire, cat, laugh, heart)" : "") 
                        : (launcherWindow.isWallpaperMode
                            ? (launcherWindow.wallpaperQuery.length === 0 ? "Select wallpaper... (↵ Apply, Esc Close)" : "")
                            : "Search applications... (Type >E for emoji, >W for wallpaper)")
                    placeholderTextColor: Services.Theme.textDisabled
                    font.pixelSize: Services.Theme.fontSize3xl
                    leftPadding: 0
                    rightPadding: 0

                    onTextChanged: {
                        if (launcherWindow.isEmojiMode) {
                            if (Services.Emojis) {
                                launcherWindow.emojiResults = Services.Emojis.search(launcherWindow.emojiQuery)
                            }
                            launcherWindow.emojiCurrentIndex = 0
                            if (emojiGridView.count > 0) {
                                emojiGridView.positionViewAtIndex(0, GridView.Beginning)
                            }
                        } else if (launcherWindow.isWallpaperMode) {
                            launcherWindow.wallpaperCurrentIndex = 0
                            if (wallpaperGridView && wallpaperGridView.count > 0) {
                                wallpaperGridView.positionViewAtIndex(0, GridView.Beginning)
                            }
                        } else {
                            Services.Applications.query = text
                            resultList.currentIndex = 0
                            if (resultList.count > 0) {
                                resultList.positionViewAtIndex(0, ListView.Beginning)
                            }
                        }
                    }

                    Keys.onPressed: (event) => {
                        // Global Settings Shortcut: Ctrl+, or Ctrl+S or Alt+S
                        if ((event.modifiers & Qt.ControlModifier && (event.key === Qt.Key_Comma || event.key === Qt.Key_S)) ||
                            (event.modifiers & Qt.AltModifier && event.key === Qt.Key_S)) {
                            launcherWindow.hide()
                            Services.OverlayManager.openSettings(0)
                            event.accepted = true
                            return
                        }

                        if (launcherWindow.isSettingsMode && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                            launcherWindow.hide()
                            Services.OverlayManager.openSettings(0)
                            event.accepted = true
                            return
                        }

                        if (launcherWindow.isWallpaperMode) {
                            const wList = launcherWindow.wallpaperList
                            const count = wList ? wList.length : 0
                            if (event.key === Qt.Key_Right) {
                                launcherWindow.wallpaperCurrentIndex = Math.min(launcherWindow.wallpaperCurrentIndex + 1, count - 1)
                                if (wallpaperGridView) wallpaperGridView.positionViewAtIndex(launcherWindow.wallpaperCurrentIndex, GridView.Contain)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Left) {
                                launcherWindow.wallpaperCurrentIndex = Math.max(launcherWindow.wallpaperCurrentIndex - 1, 0)
                                if (wallpaperGridView) wallpaperGridView.positionViewAtIndex(launcherWindow.wallpaperCurrentIndex, GridView.Contain)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Down) {
                                launcherWindow.wallpaperCurrentIndex = Math.min(launcherWindow.wallpaperCurrentIndex + 3, count - 1)
                                if (wallpaperGridView) wallpaperGridView.positionViewAtIndex(launcherWindow.wallpaperCurrentIndex, GridView.Contain)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Up) {
                                launcherWindow.wallpaperCurrentIndex = Math.max(launcherWindow.wallpaperCurrentIndex - 3, 0)
                                if (wallpaperGridView) wallpaperGridView.positionViewAtIndex(launcherWindow.wallpaperCurrentIndex, GridView.Contain)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                if (wList && wList.length > launcherWindow.wallpaperCurrentIndex) {
                                    const item = wList[launcherWindow.wallpaperCurrentIndex]
                                    if (item && item.path && Services.Wallpaper) {
                                        Services.Wallpaper.setWallpaper(item.path)
                                        launcherWindow.hide()
                                    }
                                }
                                event.accepted = true
                            } else if (event.key === Qt.Key_Escape) {
                                launcherWindow.hide(); event.accepted = true
                            }
                        } else if (launcherWindow.isEmojiMode) {
                            const count = launcherWindow.emojiResults ? launcherWindow.emojiResults.length : 0
                            if (event.key === Qt.Key_Right) {
                                launcherWindow.emojiCurrentIndex = Math.min(launcherWindow.emojiCurrentIndex + 1, count - 1)
                                emojiGridView.positionViewAtIndex(launcherWindow.emojiCurrentIndex, GridView.Contain)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Left) {
                                launcherWindow.emojiCurrentIndex = Math.max(launcherWindow.emojiCurrentIndex - 1, 0)
                                emojiGridView.positionViewAtIndex(launcherWindow.emojiCurrentIndex, GridView.Contain)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Down) {
                                launcherWindow.emojiCurrentIndex = Math.min(launcherWindow.emojiCurrentIndex + launcherWindow.emojiColumns, count - 1)
                                emojiGridView.positionViewAtIndex(launcherWindow.emojiCurrentIndex, GridView.Contain)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Up) {
                                launcherWindow.emojiCurrentIndex = Math.max(launcherWindow.emojiCurrentIndex - launcherWindow.emojiColumns, 0)
                                emojiGridView.positionViewAtIndex(launcherWindow.emojiCurrentIndex, GridView.Contain)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                if (launcherWindow.emojiResults && launcherWindow.emojiResults.length > launcherWindow.emojiCurrentIndex) {
                                    const em = launcherWindow.emojiResults[launcherWindow.emojiCurrentIndex]
                                    if (em && Services.Emojis) {
                                        Services.Emojis.insert(em)
                                        launcherWindow.hide()
                                    }
                                }
                                event.accepted = true
                            } else if (event.key === Qt.Key_Escape) {
                                launcherWindow.hide(); event.accepted = true
                            }
                        } else {
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
                                launcherWindow.hide(); event.accepted = true
                            }
                        }
                    }
                }

                // Settings Mode Badge
                Rectangle {
                    radius: 6
                    color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15)
                    border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.4)
                    border.width: 1
                    implicitWidth: settingsBadgeText.implicitWidth + 12
                    implicitHeight: 22
                    visible: launcherWindow.isSettingsMode
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        id: settingsBadgeText
                        anchors.centerIn: parent
                        text: "SETTINGS"
                        color: Services.Theme.accent
                        font.pixelSize: Services.Theme.fontSizeXs
                        font.weight: Font.Bold
                    }
                }

                // Wallpaper Mode Badge
                Rectangle {
                    radius: 6
                    color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15)
                    border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.4)
                    border.width: 1
                    implicitWidth: wallpaperBadgeText.implicitWidth + 12
                    implicitHeight: 22
                    visible: launcherWindow.isWallpaperMode
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        id: wallpaperBadgeText
                        anchors.centerIn: parent
                        text: "WALLPAPER"
                        color: Services.Theme.accent
                        font.pixelSize: Services.Theme.fontSizeXs
                        font.weight: Font.Bold
                    }
                }

                // Emoji Mode Badge
                Rectangle {
                    radius: 6
                    color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15)
                    border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.4)
                    border.width: 1
                    implicitWidth: emojiBadgeText.implicitWidth + 12
                    implicitHeight: 22
                    visible: launcherWindow.isEmojiMode
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        id: emojiBadgeText
                        anchors.centerIn: parent
                        text: "EMOJI"
                        color: Services.Theme.accent
                        font.pixelSize: Services.Theme.fontSizeXs
                        font.weight: Font.Bold
                    }
                }

                // Helper Hints when search field is empty
                RowLayout {
                    spacing: 6
                    visible: !launcherWindow.isEmojiMode && !launcherWindow.isWallpaperMode && !launcherWindow.isSettingsMode && searchField.text.length === 0
                    Layout.alignment: Qt.AlignVCenter

                    Rectangle {
                        radius: 6
                        color: Qt.rgba(255, 255, 255, 0.04)
                        border.color: Services.Theme.borderSubtle
                        border.width: 1
                        implicitWidth: emojiHintText.implicitWidth + 10
                        implicitHeight: 20

                        Text {
                            id: emojiHintText
                            anchors.centerIn: parent
                            text: ">E Emoji"
                            color: Services.Theme.textDisabled
                            font.pixelSize: Services.Theme.fontSizeXs
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                searchField.text = ">E "
                                searchField.forceActiveFocus()
                            }
                        }
                    }

                    Rectangle {
                        radius: 6
                        color: Qt.rgba(255, 255, 255, 0.04)
                        border.color: Services.Theme.borderSubtle
                        border.width: 1
                        implicitWidth: wallHintText.implicitWidth + 10
                        implicitHeight: 20

                        Text {
                            id: wallHintText
                            anchors.centerIn: parent
                            text: ">W Wallpaper"
                            color: Services.Theme.textDisabled
                            font.pixelSize: Services.Theme.fontSizeXs
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                searchField.text = ">W "
                                searchField.forceActiveFocus()
                            }
                        }
                    }

                    Rectangle {
                        radius: 6
                        color: Qt.rgba(255, 255, 255, 0.04)
                        border.color: Services.Theme.borderSubtle
                        border.width: 1
                        implicitWidth: settingsHintText.implicitWidth + 10
                        implicitHeight: 20

                        Text {
                            id: settingsHintText
                            anchors.centerIn: parent
                            text: ">S Settings"
                            color: Services.Theme.textDisabled
                            font.pixelSize: Services.Theme.fontSizeXs
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                launcherWindow.hide()
                                Services.OverlayManager.openSettings(0)
                            }
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
                            Services.OverlayManager.openSettings(0)
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
            // ── APPLICATIONS LIST VIEW (Default Mode) ────────────────────────
            // ═════════════════════════════════════════════════════════════════
            ListView {
                id: resultList
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !launcherWindow.isEmojiMode && !launcherWindow.isWallpaperMode && launcherWindow.isExpanded
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
                                visible: !ico.source || ico.status === Image.Error

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
                                    const rev = Services.SystemTheme ? Services.SystemTheme.iconThemeRev : 0
                                    const s = appItem.modelData.icon ?? ""
                                    if (!s) return ""
                                    if (Services.SystemTheme) {
                                        const res = Services.SystemTheme.getIcon(s)
                                        if (res && res.length > 0) return res
                                    }
                                    if (s.startsWith("file://")) return s
                                    if (s.startsWith("/")) return "file://" + s
                                    const qp = Quickshell.iconPath(s, true)
                                    return (qp && qp.startsWith("/")) ? ("file://" + qp) : (qp || "")
                                }
                                fillMode: Image.PreserveAspectFit
                                asynchronous: false
                                cache: true
                                sourceSize: Qt.size(64, 64)
                                mipmap: true
                                smooth: true
                                visible: ico.status !== Image.Error
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
                        cursorShape: Qt.PointingHandCursor
                        onPositionChanged: {
                            if (resultList.currentIndex !== appItem.index) {
                                resultList.currentIndex = appItem.index
                            }
                        }
                        onClicked: {
                            launcherWindow.hide()
                            if (typeof appItem.modelData.execute === "function") {
                                appItem.modelData.execute()
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

            // Bottom Action Strip for App Mode
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                color: Services.Theme.bgDeep
                radius: 12
                border.width: 0
                visible: !launcherWindow.isEmojiMode && !launcherWindow.isWallpaperMode && launcherWindow.isExpanded

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

            // ═════════════════════════════════════════════════════════════════
            // ── WALLPAPER SELECTOR GRID VIEW (>W Mode) ────────────────────────
            // ═════════════════════════════════════════════════════════════════
            ColumnLayout {
                id: wallpaperContainer
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: launcherWindow.isWallpaperMode
                spacing: 0

                GridView {
                    id: wallpaperGridView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: 800
                    cellWidth: (wallpaperGridView.width - 24) / 3
                    cellHeight: 110
                    topMargin: 8; bottomMargin: 8
                    leftMargin: 12; rightMargin: 12

                    model: launcherWindow.wallpaperList
                    currentIndex: launcherWindow.wallpaperCurrentIndex

                    delegate: Item {
                        id: wallCell
                        required property var modelData
                        required property int index

                        width: wallpaperGridView.cellWidth
                        height: wallpaperGridView.cellHeight

                        readonly property bool isSelected: wallCell.index === launcherWindow.wallpaperCurrentIndex
                        readonly property bool isActiveWall: Services.Wallpaper && Services.Wallpaper.currentWallpaper === wallCell.modelData.path

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 4
                            radius: 10
                            color: Services.Theme.bgElevated
                            border.color: wallCell.isSelected 
                                ? Services.Theme.accent 
                                : (isActiveWall ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.5) : (wallMouse.containsMouse ? Services.Theme.border : Services.Theme.borderSubtle))
                            border.width: wallCell.isSelected ? 2 : (isActiveWall ? 1.5 : 1)
                            clip: true

                            Behavior on border.color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }

                            Image {
                                anchors.fill: parent
                                source: wallCell.modelData.path ? ("file://" + wallCell.modelData.path) : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                                sourceSize: Qt.size(180, 120)
                                opacity: wallMouse.containsMouse || wallCell.isSelected ? 1.0 : 0.85
                            }

                            // Dark gradient bottom overlay for label
                            Rectangle {
                                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                height: 26
                                color: Qt.rgba(0, 0, 0, 0.65)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8; anchors.rightMargin: 8
                                    spacing: 4

                                    Text {
                                        Layout.fillWidth: true
                                        text: wallCell.modelData.name || "Wallpaper"
                                        color: Services.Theme.white
                                        font.pixelSize: 10
                                        font.bold: wallCell.isSelected || isActiveWall
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        visible: isActiveWall
                                        text: "✓"
                                        color: Services.Theme.accent
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: wallMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: launcherWindow.wallpaperCurrentIndex = wallCell.index
                            onClicked: {
                                if (wallCell.modelData && wallCell.modelData.path && Services.Wallpaper) {
                                    Services.Wallpaper.setWallpaper(wallCell.modelData.path)
                                    launcherWindow.hide()
                                }
                            }
                        }
                    }
                }

                // Divider
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Services.Theme.borderSubtle
                }

                // Bottom strip for Wallpaper Mode
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    color: Services.Theme.bgDeep
                    radius: 12

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14; anchors.rightMargin: 14
                        spacing: 10

                        Text {
                            text: "Wallpapers (" + (launcherWindow.wallpaperList ? launcherWindow.wallpaperList.length : 0) + ")"
                            color: Services.Theme.textDisabled
                            font.pixelSize: Services.Theme.fontSizeSm
                        }

                        Item { Layout.fillWidth: true }

                        // Add custom wallpaper button
                        Rectangle {
                            radius: 6
                            color: addWallMouse.containsMouse ? Services.Theme.surfaceVariant : Qt.rgba(255, 255, 255, 0.06)
                            border.color: Services.Theme.borderSubtle
                            border.width: 1
                            implicitWidth: addWallText.implicitWidth + 14
                            implicitHeight: 24

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 4
                                Text {
                                    text: "+"
                                    color: Services.Theme.accent
                                    font.pixelSize: 12
                                    font.bold: true
                                }
                                Text {
                                    id: addWallText
                                    text: "Add Wallpaper"
                                    color: Services.Theme.textPrimary
                                    font.pixelSize: Services.Theme.fontSizeXs
                                }
                            }

                            MouseArea {
                                id: addWallMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    launcherWindow.hide()
                                    if (Services.Wallpaper) Services.Wallpaper.pickCustomWallpaper()
                                }
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
                                text: "Apply"
                                color: Services.Theme.textDisabled
                                font.pixelSize: Services.Theme.fontSizeXs
                            }
                        }
                    }
                }
            }

            // ═════════════════════════════════════════════════════════════════
            // ── EMOJI PICKER GRID VIEW (>E Mode) ──────────────────────────────
            // ═════════════════════════════════════════════════════════════════
            ColumnLayout {
                id: emojiContainer
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: launcherWindow.isEmojiMode
                spacing: 0

                // Emoji Grid
                GridView {
                    id: emojiGridView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: 1200
                    cellWidth: (emojiGridView.width - 24) / launcherWindow.emojiColumns
                    cellHeight: 46
                    topMargin: 8; bottomMargin: 8
                    leftMargin: 12; rightMargin: 12

                    model: launcherWindow.emojiResults
                    currentIndex: launcherWindow.emojiCurrentIndex

                    delegate: Item {
                        id: emojiCell
                        required property var modelData
                        required property int index

                        width: emojiGridView.cellWidth
                        height: emojiGridView.cellHeight

                        readonly property bool isSelected: emojiCell.index === launcherWindow.emojiCurrentIndex

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: 8
                            color: emojiCell.isSelected 
                                ? Services.Theme.surfaceVariant 
                                : (cellMouse.containsMouse ? Services.Theme.bgHover : "transparent")
                            border.color: emojiCell.isSelected 
                                ? Services.Theme.accent 
                                : (cellMouse.containsMouse ? Services.Theme.borderSubtle : "transparent")
                            border.width: emojiCell.isSelected ? 1.5 : 1

                            Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }

                            Text {
                                anchors.centerIn: parent
                                text: emojiCell.modelData.emoji || ""
                                font.pixelSize: 22
                                font.family: "Noto Color Emoji, Apple Color Emoji, Segoe UI Emoji, sans-serif"
                                renderType: Text.NativeRendering
                            }
                        }

                        MouseArea {
                            id: cellMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: {
                                launcherWindow.emojiCurrentIndex = emojiCell.index
                            }
                            onClicked: {
                                if (Services.Emojis) {
                                    Services.Emojis.insert(emojiCell.modelData)
                                    launcherWindow.hide()
                                }
                            }
                        }
                    }

                    // Empty state when no emojis match
                    Item {
                        anchors.fill: parent
                        visible: emojiGridView.count === 0

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 8

                            Text {
                                text: Services.Icons.search
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 36
                                color: Services.Theme.textDisabled
                                Layout.alignment: Qt.AlignHCenter
                            }

                            Text {
                                text: "No emojis found for \"" + launcherWindow.emojiQuery + "\""
                                color: Services.Theme.textDisabled
                                font.pixelSize: Services.Theme.fontSizeLg
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }
                }

                // Hairline Divider for Preview Strip
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Services.Theme.borderSubtle
                }

                // Bottom Preview & Status Strip
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    color: Services.Theme.bgDeep
                    radius: 12
                    border.width: 0

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14; anchors.rightMargin: 14
                        spacing: 10

                        // Active emoji preview & name
                        readonly property var currentEmojiObj: (launcherWindow.emojiResults && launcherWindow.emojiResults.length > launcherWindow.emojiCurrentIndex)
                            ? launcherWindow.emojiResults[launcherWindow.emojiCurrentIndex]
                            : null

                        Text {
                            text: parent.currentEmojiObj ? parent.currentEmojiObj.emoji : "-"
                            font.pixelSize: 18
                            font.family: "Noto Color Emoji, Apple Color Emoji, Segoe UI Emoji, sans-serif"
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Text {
                            text: parent.currentEmojiObj ? parent.currentEmojiObj.name : "Select an emoji"
                            color: Services.Theme.textPrimary
                            font.pixelSize: Services.Theme.fontSizeMd
                            font.weight: Font.Medium
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Text {
                            text: parent.currentEmojiObj ? ("•  " + (parent.currentEmojiObj.category || "Emoji")) : ""
                            color: Services.Theme.textDisabled
                            font.pixelSize: Services.Theme.fontSizeSm
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                        }

                        // Use instruction badge
                        Rectangle {
                            radius: 4
                            color: Qt.rgba(255, 255, 255, 0.08)
                            implicitWidth: copyHintText.implicitWidth + 8
                            implicitHeight: 20
                            Layout.alignment: Qt.AlignVCenter

                            Text {
                                id: copyHintText
                                anchors.centerIn: parent
                                text: "↵ Enter to Insert"
                                color: Services.Theme.textSecondary
                                font.pixelSize: Services.Theme.fontSizeXs
                            }
                        }
                    }
                }
            }
        }
    }
}
