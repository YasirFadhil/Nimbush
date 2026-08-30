import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../services" as Services

PanelWindow {
    id: wallpaperSelectorWindow
    visible: false

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell:wallpaperselector"
    exclusiveZone: 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    Component.onCompleted: Services.OverlayManager.register(wallpaperSelectorWindow)

    property bool isOpen: false
    property string searchQuery: ""
    property string activeCategory: "all" // "all" | "dynamic" | "custom"
    property int currentIndex: 0

    readonly property bool isBottom: Services.Config ? (Services.Config.barPosition === "bottom") : false

    // Full wallpaper list filtered by category and search query
    readonly property var wallpaperList: {
        const all = (Services.Wallpaper && Services.Wallpaper.allWallpapers) ? Services.Wallpaper.allWallpapers : []
        const q = searchQuery.trim().toLowerCase()
        const cat = activeCategory

        let filtered = all.filter(w => {
            // Category filter
            if (cat === "dynamic" && !w.isDynamic) return false
            if (cat === "custom" && (w.isDynamic || (!w.isCustom && w.path.indexOf("wallbler") !== -1))) return false

            // Search filter
            if (q.length > 0) {
                const name = (w.name || "").toLowerCase()
                const path = (w.path || "").toLowerCase()
                if (name.indexOf(q) === -1 && path.indexOf(q) === -1) return false
            }
            return true
        })

        // Append interactive "Add Wallpaper" card at end when not actively searching
        if (q.length === 0 && cat !== "dynamic") {
            filtered = filtered.concat([{ isAddAction: true }])
        }

        return filtered
    }

    // Currently focused / previewed item
    readonly property var selectedItem: {
        const list = wallpaperList || []
        if (list.length > 0 && currentIndex >= 0 && currentIndex < list.length) {
            return list[currentIndex]
        }
        return null
    }

    // Counts for tab badges
    readonly property int totalCount: (Services.Wallpaper && Services.Wallpaper.allWallpapers) ? Services.Wallpaper.allWallpapers.length : 0
    readonly property int dynamicCount: {
        const all = (Services.Wallpaper && Services.Wallpaper.allWallpapers) ? Services.Wallpaper.allWallpapers : []
        return all.filter(w => w.isDynamic === true).length
    }
    readonly property int customCount: {
        const all = (Services.Wallpaper && Services.Wallpaper.allWallpapers) ? Services.Wallpaper.allWallpapers : []
        return all.filter(w => w.isDynamic !== true).length
    }

    function show() {
        Services.OverlayManager.closeAllExcept(wallpaperSelectorWindow)
        hideTimer.stop()
        visible = true
        isOpen = true
        searchQuery = ""
        activeCategory = "all"
        searchField.text = ""
        currentIndex = 0

        // Focus current active wallpaper index if found
        if (Services.Wallpaper && Services.Wallpaper.currentWallpaper) {
            const cur = Services.Wallpaper.currentWallpaper
            const list = wallpaperList || []
            for (let i = 0; i < list.length; i++) {
                if (list[i].path === cur || (list[i].isDynamic && Services.Wallpaper.isWallblerActive)) {
                    currentIndex = i
                    break
                }
            }
        }

        searchField.forceActiveFocus()
        if (wallpaperGridView && wallpaperGridView.count > 0) {
            wallpaperGridView.positionViewAtIndex(currentIndex, GridView.Contain)
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
            wallpaperSelectorWindow.visible = false
            searchQuery = ""
        }
    }

    // ── Semi-transparent Dimmed Backdrop ──────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Services.Theme.overlayDim
        opacity: wallpaperSelectorWindow.isOpen ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: wallpaperSelectorWindow.hide()
        }
    }

    // ── Dynamic Island Expanded Capsule Hub ───────────────────────────
    Rectangle {
        id: islandHub
        anchors.horizontalCenter: parent.horizontalCenter
        y: wallpaperSelectorWindow.isOpen
            ? (wallpaperSelectorWindow.isBottom ? (parent.height - height - 12) : 10)
            : (wallpaperSelectorWindow.isBottom ? parent.height : -height - 20)

        Behavior on y {
            NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.06 }
        }

        width: 880
        height: 520
        clip: true

        radius: 24
        color: Services.Theme.isDark ? "#0c0c10" : "#f8f9fc"
        border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.28)
        border.width: 1

        opacity: wallpaperSelectorWindow.isOpen ? 1 : 0
        scale: wallpaperSelectorWindow.isOpen ? 1 : 0.94

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.05 }
        }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ── Top Island Handle & Navigation Header ──────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 68
                color: "transparent"

                // Top Island Capsule Notch Glow
                Rectangle {
                    anchors.top: parent.top
                    anchors.topMargin: 4
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 48
                    height: 4
                    radius: 2
                    color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.4)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 18
                    anchors.topMargin: 6
                    spacing: 12

                    // Dynamic Island Pill Badge & Title
                    RowLayout {
                        spacing: 8

                        Rectangle {
                            height: 32
                            radius: 16
                            color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15)
                            border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.3)
                            border.width: 1
                            implicitWidth: islandBadgeRow.implicitWidth + 16

                            RowLayout {
                                id: islandBadgeRow
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    text: Services.Icons.image || "󰋩"
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 14
                                    color: Services.Theme.accent
                                }

                                Text {
                                    text: "Dynamic Island"
                                    color: Services.Theme.textPrimary
                                    font.pixelSize: Services.Theme.fontSizeSm
                                    font.bold: true
                                }
                            }
                        }

                        Text {
                            text: "•"
                            color: Services.Theme.textDisabled
                            font.pixelSize: 12
                        }

                        Text {
                            text: "Wallpaper Hub"
                            color: Services.Theme.textSecondary
                            font.pixelSize: Services.Theme.fontSizeMd
                            font.weight: Font.DemiBold
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Category Segmented Tabs
                    Rectangle {
                        height: 32
                        radius: 16
                        color: Services.Theme.bgElevated
                        border.color: Services.Theme.borderSubtle
                        border.width: 1
                        implicitWidth: filterRow.implicitWidth + 6

                        RowLayout {
                            id: filterRow
                            anchors.centerIn: parent
                            spacing: 2

                            Repeater {
                                model: [
                                    { id: "all", label: "All", count: totalCount },
                                    { id: "dynamic", label: "Dynamic", count: dynamicCount },
                                    { id: "custom", label: "Custom", count: customCount }
                                ]

                                delegate: Rectangle {
                                    id: catBtn
                                    required property var modelData
                                    height: 26
                                    implicitWidth: catRow.implicitWidth + 14
                                    radius: 13
                                    color: wallpaperSelectorWindow.activeCategory === modelData.id
                                        ? Services.Theme.accent
                                        : (catMouse.containsMouse ? Services.Theme.bgHover : "transparent")

                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    RowLayout {
                                        id: catRow
                                        anchors.centerIn: parent
                                        spacing: 5

                                        Text {
                                            text: catBtn.modelData.label
                                            color: wallpaperSelectorWindow.activeCategory === catBtn.modelData.id
                                                ? Services.Theme.bgOnAccent
                                                : Services.Theme.textSecondary
                                            font.pixelSize: Services.Theme.fontSizeSm
                                            font.weight: wallpaperSelectorWindow.activeCategory === catBtn.modelData.id ? Font.Bold : Font.Medium
                                        }

                                        Rectangle {
                                            width: Math.max(16, countText.implicitWidth + 6)
                                            height: 16
                                            radius: 8
                                            color: wallpaperSelectorWindow.activeCategory === catBtn.modelData.id
                                                ? Qt.rgba(0, 0, 0, 0.2)
                                                : Qt.rgba(255, 255, 255, 0.08)

                                            Text {
                                                id: countText
                                                anchors.centerIn: parent
                                                text: catBtn.modelData.count
                                                color: wallpaperSelectorWindow.activeCategory === catBtn.modelData.id
                                                    ? Services.Theme.bgOnAccent
                                                    : Services.Theme.textDisabled
                                                font.pixelSize: 9
                                                font.bold: true
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: catMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            wallpaperSelectorWindow.activeCategory = catBtn.modelData.id
                                            wallpaperSelectorWindow.currentIndex = 0
                                            if (wallpaperGridView && wallpaperGridView.count > 0) {
                                                wallpaperGridView.positionViewAtIndex(0, GridView.Beginning)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Add Custom Wallpaper Button
                    Rectangle {
                        id: addBtn
                        height: 32
                        radius: 10
                        color: addWallMouse.containsMouse
                            ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.25)
                            : Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.14)
                        border.color: addWallMouse.containsMouse
                            ? Services.Theme.accent
                            : Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.35)
                        border.width: 1
                        implicitWidth: addWallRow.implicitWidth + 16
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        RowLayout {
                            id: addWallRow
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: "+"
                                color: Services.Theme.accent
                                font.pixelSize: 15
                                font.bold: true
                            }
                            Text {
                                text: "Add Wallpaper"
                                color: Services.Theme.textPrimary
                                font.pixelSize: Services.Theme.fontSizeSm
                                font.weight: Font.DemiBold
                            }
                        }

                        MouseArea {
                            id: addWallMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                wallpaperSelectorWindow.hide()
                                if (Services.Wallpaper) Services.Wallpaper.pickCustomWallpaper()
                            }
                        }
                    }

                    // Settings Button
                    Rectangle {
                        width: 32; height: 32; radius: 8
                        color: setBtnMouse.containsMouse ? Services.Theme.bgHover : "transparent"
                        border.color: setBtnMouse.containsMouse ? Services.Theme.border : "transparent"
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.settings || "󰒓"
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: Services.Theme.fontSizeLg
                            color: setBtnMouse.containsMouse ? Services.Theme.accent : Services.Theme.textSecondary
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        MouseArea {
                            id: setBtnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                wallpaperSelectorWindow.hide()
                                Services.OverlayManager.openSettings(0)
                            }
                        }
                    }

                    // Close Button
                    Rectangle {
                        width: 32; height: 32; radius: 8
                        color: closeBtnMouse.containsMouse ? Qt.rgba(239, 68, 68, 0.15) : "transparent"
                        border.color: closeBtnMouse.containsMouse ? Qt.rgba(239, 68, 68, 0.3) : "transparent"
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            font.pixelSize: Services.Theme.fontSizeLg
                            color: closeBtnMouse.containsMouse ? "#ef4444" : Services.Theme.textDisabled
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        MouseArea {
                            id: closeBtnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: wallpaperSelectorWindow.hide()
                        }
                    }
                }
            }

            // ── Search Input Row ──────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                color: "transparent"

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    anchors.bottomMargin: 8
                    radius: 10
                    color: Services.Theme.bgElevated
                    border.color: searchField.activeFocus
                        ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.45)
                        : Services.Theme.borderSubtle
                    border.width: 1
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10

                        Text {
                            text: Services.Icons.search || "󰍉"
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: Services.Theme.fontSizeXl
                            color: searchField.activeFocus ? Services.Theme.accent : Services.Theme.textDisabled
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        TextField {
                            id: searchField
                            Layout.fillWidth: true
                            background: null
                            color: Services.Theme.textPrimary
                            placeholderText: "Search wallpapers..."
                            placeholderTextColor: Services.Theme.textDisabled
                            font.pixelSize: Services.Theme.fontSizeLg
                            leftPadding: 0
                            rightPadding: 0

                            onTextChanged: {
                                wallpaperSelectorWindow.searchQuery = text
                                wallpaperSelectorWindow.currentIndex = 0
                                if (wallpaperGridView && wallpaperGridView.count > 0) {
                                    wallpaperGridView.positionViewAtIndex(0, GridView.Beginning)
                                }
                            }

                            Keys.onPressed: (event) => {
                                const count = wallpaperSelectorWindow.wallpaperList ? wallpaperSelectorWindow.wallpaperList.length : 0

                                if (event.key === Qt.Key_Right) {
                                    wallpaperSelectorWindow.currentIndex = Math.min(wallpaperSelectorWindow.currentIndex + 1, count - 1)
                                    if (wallpaperGridView) wallpaperGridView.positionViewAtIndex(wallpaperSelectorWindow.currentIndex, GridView.Contain)
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Left) {
                                    wallpaperSelectorWindow.currentIndex = Math.max(wallpaperSelectorWindow.currentIndex - 1, 0)
                                    if (wallpaperGridView) wallpaperGridView.positionViewAtIndex(wallpaperSelectorWindow.currentIndex, GridView.Contain)
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Down) {
                                    wallpaperSelectorWindow.currentIndex = Math.min(wallpaperSelectorWindow.currentIndex + 3, count - 1)
                                    if (wallpaperGridView) wallpaperGridView.positionViewAtIndex(wallpaperSelectorWindow.currentIndex, GridView.Contain)
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Up) {
                                    wallpaperSelectorWindow.currentIndex = Math.max(wallpaperSelectorWindow.currentIndex - 3, 0)
                                    if (wallpaperGridView) wallpaperGridView.positionViewAtIndex(wallpaperSelectorWindow.currentIndex, GridView.Contain)
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Home) {
                                    wallpaperSelectorWindow.currentIndex = 0
                                    if (wallpaperGridView) wallpaperGridView.positionViewAtIndex(0, GridView.Beginning)
                                    event.accepted = true
                                } else if (event.key === Qt.Key_End) {
                                    wallpaperSelectorWindow.currentIndex = Math.max(0, count - 1)
                                    if (wallpaperGridView) wallpaperGridView.positionViewAtIndex(wallpaperSelectorWindow.currentIndex, GridView.End)
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                                    if (wallpaperSelectorWindow.activeCategory === "all") wallpaperSelectorWindow.activeCategory = "custom"
                                    else if (wallpaperSelectorWindow.activeCategory === "custom") wallpaperSelectorWindow.activeCategory = "dynamic"
                                    else wallpaperSelectorWindow.activeCategory = "all"
                                    wallpaperSelectorWindow.currentIndex = 0
                                    if (wallpaperGridView && wallpaperGridView.count > 0) {
                                        wallpaperGridView.positionViewAtIndex(0, GridView.Beginning)
                                    }
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Tab) {
                                    if (wallpaperSelectorWindow.activeCategory === "all") wallpaperSelectorWindow.activeCategory = "dynamic"
                                    else if (wallpaperSelectorWindow.activeCategory === "dynamic") wallpaperSelectorWindow.activeCategory = "custom"
                                    else wallpaperSelectorWindow.activeCategory = "all"
                                    wallpaperSelectorWindow.currentIndex = 0
                                    if (wallpaperGridView && wallpaperGridView.count > 0) {
                                        wallpaperGridView.positionViewAtIndex(0, GridView.Beginning)
                                    }
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                                    const list = wallpaperSelectorWindow.wallpaperList
                                    if (list && list.length > wallpaperSelectorWindow.currentIndex) {
                                        const item = list[wallpaperSelectorWindow.currentIndex]
                                        if (item && item.isAddAction) {
                                            wallpaperSelectorWindow.hide()
                                            if (Services.Wallpaper) Services.Wallpaper.pickCustomWallpaper()
                                        } else if (item && item.path && Services.Wallpaper) {
                                            Services.Wallpaper.setWallpaper(item.path)
                                            wallpaperSelectorWindow.hide()
                                        }
                                    }
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace && (event.modifiers & Qt.ShiftModifier)) {
                                    const list = wallpaperSelectorWindow.wallpaperList
                                    if (list && list.length > wallpaperSelectorWindow.currentIndex) {
                                        const item = list[wallpaperSelectorWindow.currentIndex]
                                        if (item && item.isCustom && !item.isDynamic && item.path && Services.Wallpaper) {
                                            Services.Wallpaper.removeCustomWallpaper(item.path)
                                            event.accepted = true
                                        }
                                    }
                                } else if (event.key === Qt.Key_Escape) {
                                    if (searchField.text.length > 0) {
                                        searchField.text = ""
                                    } else {
                                        wallpaperSelectorWindow.hide()
                                    }
                                    event.accepted = true
                                } else if ((event.modifiers & Qt.ControlModifier && event.key === Qt.Key_O) || event.key === Qt.Key_Plus) {
                                    if (Services.Wallpaper) {
                                        wallpaperSelectorWindow.hide()
                                        Services.Wallpaper.pickCustomWallpaper()
                                    }
                                    event.accepted = true
                                }
                            }
                        }

                        // Clear search button
                        Rectangle {
                            width: 22; height: 22; radius: 11
                            color: clearSearchMouse.containsMouse ? Services.Theme.bgHover : "transparent"
                            visible: searchField.text.length > 0

                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                font.pixelSize: Services.Theme.fontSizeSm
                                color: clearSearchMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textDisabled
                            }

                            MouseArea {
                                id: clearSearchMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    searchField.text = ""
                                    searchField.forceActiveFocus()
                                }
                            }
                        }
                    }
                }
            }

            // Hairline divider
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Services.Theme.borderSubtle
            }

            // ── Wallpaper Grid View ───────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                GridView {
                    id: wallpaperGridView
                    anchors.fill: parent
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: 900
                    cellWidth: wallpaperGridView.width / 3
                    cellHeight: 168
                    topMargin: 10; bottomMargin: 10
                    leftMargin: 12; rightMargin: 12

                    model: wallpaperSelectorWindow.wallpaperList
                    currentIndex: wallpaperSelectorWindow.currentIndex

                    delegate: Item {
                        id: wallCell
                        required property var modelData
                        required property int index

                        width: wallpaperGridView.cellWidth
                        height: wallpaperGridView.cellHeight

                        readonly property bool isAddCard: wallCell.modelData && wallCell.modelData.isAddAction === true
                        readonly property bool isSelected: wallCell.index === wallpaperSelectorWindow.currentIndex
                        readonly property bool isActiveWall: !isAddCard && Services.Wallpaper && (
                            Services.Wallpaper.currentWallpaper === wallCell.modelData.path ||
                            (wallCell.modelData.isDynamic === true && Services.Wallpaper.isWallblerActive)
                        )
                        readonly property bool isCustomWall: !isAddCard && (wallCell.modelData.isCustom === true || (
                            wallCell.modelData.isDynamic !== true &&
                            wallCell.modelData.path !== Services.Wallpaper.darkWallbler &&
                            wallCell.modelData.path !== Services.Wallpaper.lightWallbler
                        ))

                        // Normal Wallpaper Card
                        Rectangle {
                            id: cardRect
                            anchors.fill: parent
                            anchors.margins: 6
                            radius: 14
                            color: Services.Theme.bgElevated
                            border.color: wallCell.isSelected
                                ? Services.Theme.accent
                                : (wallCell.isActiveWall
                                    ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.7)
                                    : (wallMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.borderSubtle))
                            border.width: wallCell.isSelected ? 2 : (wallCell.isActiveWall ? 1.5 : 1)
                            clip: true
                            scale: wallMouse.containsMouse || wallCell.isSelected ? 1.025 : 1.0
                            visible: !wallCell.isAddCard

                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }

                            // Image Preview
                            Image {
                                anchors.fill: parent
                                source: (wallCell.modelData && wallCell.modelData.path) ? ("file://" + wallCell.modelData.path) : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                                sourceSize: Qt.size(480, 320)
                                opacity: wallMouse.containsMouse || wallCell.isSelected ? 1.0 : 0.88
                                scale: wallMouse.containsMouse ? 1.04 : 1.0

                                Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                            }

                            // Dynamic Pill (Top-Left)
                            Rectangle {
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.margins: 8
                                height: 22
                                implicitWidth: dynRow.implicitWidth + 14
                                radius: 11
                                color: Qt.rgba(0, 0, 0, 0.72)
                                border.color: Qt.rgba(255, 255, 255, 0.2)
                                border.width: 1
                                visible: wallCell.modelData && wallCell.modelData.isDynamic === true

                                RowLayout {
                                    id: dynRow
                                    anchors.centerIn: parent
                                    spacing: 4

                                    Text {
                                        text: "󰖔"
                                        color: "#38bdf8"
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: 11
                                    }
                                    Text {
                                        text: "Dynamic"
                                        color: Services.Theme.white
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }

                            // Active Tag Pill (Top-Right)
                            Rectangle {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 8
                                height: 22
                                implicitWidth: activeRow.implicitWidth + 14
                                radius: 11
                                color: Services.Theme.accent
                                border.color: Qt.rgba(255, 255, 255, 0.4)
                                border.width: 1
                                visible: wallCell.isActiveWall

                                RowLayout {
                                    id: activeRow
                                    anchors.centerIn: parent
                                    spacing: 4

                                    Text {
                                        text: "✓"
                                        color: Services.Theme.bgOnAccent
                                        font.pixelSize: 10
                                        font.bold: true
                                    }
                                    Text {
                                        text: "Active"
                                        color: Services.Theme.bgOnAccent
                                        font.pixelSize: 10
                                        font.bold: true
                                    }
                                }
                            }

                            // Delete Button for Custom Wallpapers (Top-Right on Hover)
                            Rectangle {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 8
                                width: 24; height: 24
                                radius: 12
                                color: delMouse.containsMouse ? Services.Theme.danger : Qt.rgba(0, 0, 0, 0.75)
                                border.color: Qt.rgba(255, 255, 255, 0.25)
                                border.width: 1
                                visible: wallCell.isCustomWall && !wallCell.isActiveWall && (wallMouse.containsMouse || wallCell.isSelected)
                                Behavior on color { ColorAnimation { duration: 150 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "✕"
                                    color: Services.Theme.white
                                    font.pixelSize: 11
                                    font.bold: true
                                }

                                MouseArea {
                                    id: delMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (Services.Wallpaper && wallCell.modelData && wallCell.modelData.path) {
                                            Services.Wallpaper.removeCustomWallpaper(wallCell.modelData.path)
                                        }
                                    }
                                }
                            }

                            // Smooth Gradient Bottom Overlay for Title
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 50
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: "transparent" }
                                    GradientStop { position: 0.35; color: Qt.rgba(0, 0, 0, 0.45) }
                                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.90) }
                                }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    anchors.bottomMargin: 6
                                    anchors.topMargin: 14
                                    spacing: 1

                                    Text {
                                        Layout.fillWidth: true
                                        text: (wallCell.modelData && wallCell.modelData.name) ? wallCell.modelData.name : "Wallpaper"
                                        color: Services.Theme.white
                                        font.pixelSize: 12
                                        font.weight: (wallCell.isSelected || wallCell.isActiveWall) ? Font.Bold : Font.DemiBold
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: (wallCell.modelData && wallCell.modelData.isDynamic === true)
                                            ? "Day / Night Adaptive"
                                            : ((wallCell.modelData && wallCell.modelData.isCustom === true) ? "Custom Image" : "Built-in Preset")
                                        color: Qt.rgba(255, 255, 255, 0.65)
                                        font.pixelSize: Services.Theme.fontSizeXs
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }

                        // "+ Add Wallpaper" Card (in grid)
                        Rectangle {
                            id: addCardRect
                            anchors.fill: parent
                            anchors.margins: 6
                            radius: 14
                            color: addCardMouse.containsMouse
                                ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.10)
                                : Qt.rgba(255, 255, 255, 0.02)
                            border.color: addCardMouse.containsMouse || wallCell.isSelected
                                ? Services.Theme.accent
                                : Services.Theme.borderSubtle
                            border.width: addCardMouse.containsMouse || wallCell.isSelected ? 2 : 1
                            visible: wallCell.isAddCard
                            scale: addCardMouse.containsMouse || wallCell.isSelected ? 1.025 : 1.0

                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 8

                                Rectangle {
                                    Layout.alignment: Qt.AlignHCenter
                                    width: 44; height: 44
                                    radius: 22
                                    color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15)
                                    border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.35)
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: "+"
                                        font.pixelSize: 24
                                        font.bold: true
                                        color: Services.Theme.accent
                                    }
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "Add Wallpaper"
                                    color: Services.Theme.textPrimary
                                    font.pixelSize: Services.Theme.fontSizeMd
                                    font.bold: true
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "Browse image files"
                                    color: Services.Theme.textDisabled
                                    font.pixelSize: Services.Theme.fontSizeXs
                                }
                            }

                            MouseArea {
                                id: addCardMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: wallpaperSelectorWindow.currentIndex = wallCell.index
                                onClicked: {
                                    wallpaperSelectorWindow.hide()
                                    if (Services.Wallpaper) Services.Wallpaper.pickCustomWallpaper()
                                }
                            }
                        }

                        // MouseArea for Normal Wallpaper Card
                        MouseArea {
                            id: wallMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            visible: !wallCell.isAddCard
                            onEntered: wallpaperSelectorWindow.currentIndex = wallCell.index
                            onClicked: {
                                if (wallCell.modelData && wallCell.modelData.path && Services.Wallpaper) {
                                    Services.Wallpaper.setWallpaper(wallCell.modelData.path)
                                    wallpaperSelectorWindow.hide()
                                }
                            }
                        }
                    }
                }

                // Empty State when search produces 0 results
                Item {
                    anchors.fill: parent
                    visible: wallpaperSelectorWindow.wallpaperList.length === 0

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 12

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 60; height: 60
                            radius: 30
                            color: Services.Theme.bgElevated
                            border.color: Services.Theme.borderSubtle
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: Services.Icons.image || "󰋩"
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 28
                                color: Services.Theme.textDisabled
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "No wallpapers found"
                            color: Services.Theme.textPrimary
                            font.pixelSize: Services.Theme.fontSize2xl
                            font.bold: true
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "No results matching \"" + wallpaperSelectorWindow.searchQuery + "\""
                            color: Services.Theme.textDisabled
                            font.pixelSize: Services.Theme.fontSizeSm
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            radius: 8
                            color: Services.Theme.bgElevated
                            border.color: Services.Theme.border
                            border.width: 1
                            implicitWidth: clearBtnText.implicitWidth + 24
                            implicitHeight: 32

                            Text {
                                id: clearBtnText
                                anchors.centerIn: parent
                                text: "Clear Search"
                                color: Services.Theme.accent
                                font.pixelSize: Services.Theme.fontSizeSm
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    searchField.text = ""
                                    searchField.forceActiveFocus()
                                }
                            }
                        }
                    }
                }
            }

            // Hairline divider
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Services.Theme.borderSubtle
            }

            // ── Bottom Action & Info Strip ────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                color: Services.Theme.isDark ? "#08080a" : "#f0f2f6"
                radius: 16
                border.width: 0

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 18; anchors.rightMargin: 18
                    spacing: 12

                    // Active wallpaper name indicator
                    RowLayout {
                        spacing: 6

                        Rectangle {
                            width: 6; height: 6; radius: 3
                            color: Services.Theme.accent
                        }

                        Text {
                            text: {
                                const list = wallpaperSelectorWindow.wallpaperList ? wallpaperSelectorWindow.wallpaperList.length : 0
                                return list + " wallpaper" + (list === 1 ? "" : "s") + " shown"
                            }
                            color: Services.Theme.textSecondary
                            font.pixelSize: Services.Theme.fontSizeSm
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Navigation Hints with Modern Key Badge Look
                    RowLayout {
                        spacing: 10

                        // Navigate Key Hint
                        RowLayout {
                            spacing: 4
                            Rectangle {
                                height: 20; implicitWidth: navKeyText.implicitWidth + 8; radius: 4
                                color: Services.Theme.bgElevated; border.color: Services.Theme.borderSubtle; border.width: 1
                                Text { id: navKeyText; anchors.centerIn: parent; text: "↑↓←→"; color: Services.Theme.textPrimary; font.pixelSize: Services.Theme.fontSizeXs; font.family: Services.Theme.fontMono }
                            }
                            Text { text: "Select"; color: Services.Theme.textDisabled; font.pixelSize: Services.Theme.fontSizeXs }
                        }

                        // Apply Key Hint
                        RowLayout {
                            spacing: 4
                            Rectangle {
                                height: 20; implicitWidth: enterKeyText.implicitWidth + 8; radius: 4
                                color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15)
                                border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.35); border.width: 1
                                Text { id: enterKeyText; anchors.centerIn: parent; text: "↵ Enter / Click"; color: Services.Theme.accent; font.pixelSize: Services.Theme.fontSizeXs; font.weight: Font.Bold }
                            }
                            Text { text: "Apply"; color: Services.Theme.textDisabled; font.pixelSize: Services.Theme.fontSizeXs }
                        }

                        // Add Key Hint
                        RowLayout {
                            spacing: 4
                            Rectangle {
                                height: 20; implicitWidth: addKeyText.implicitWidth + 8; radius: 4
                                color: Services.Theme.bgElevated; border.color: Services.Theme.borderSubtle; border.width: 1
                                Text { id: addKeyText; anchors.centerIn: parent; text: "Ctrl+O / +"; color: Services.Theme.textPrimary; font.pixelSize: Services.Theme.fontSizeXs; font.family: Services.Theme.fontMono }
                            }
                            Text { text: "Add"; color: Services.Theme.textDisabled; font.pixelSize: Services.Theme.fontSizeXs }
                        }

                        // Tab Key Hint
                        RowLayout {
                            spacing: 4
                            Rectangle {
                                height: 20; implicitWidth: tabKeyText.implicitWidth + 8; radius: 4
                                color: Services.Theme.bgElevated; border.color: Services.Theme.borderSubtle; border.width: 1
                                Text { id: tabKeyText; anchors.centerIn: parent; text: "Tab"; color: Services.Theme.textPrimary; font.pixelSize: Services.Theme.fontSizeXs; font.family: Services.Theme.fontMono }
                            }
                            Text { text: "Filter"; color: Services.Theme.textDisabled; font.pixelSize: Services.Theme.fontSizeXs }
                        }

                        // Esc Key Hint
                        RowLayout {
                            spacing: 4
                            Rectangle {
                                height: 20; implicitWidth: escKeyText.implicitWidth + 8; radius: 4
                                color: Services.Theme.bgElevated; border.color: Services.Theme.borderSubtle; border.width: 1
                                Text { id: escKeyText; anchors.centerIn: parent; text: "Esc"; color: Services.Theme.textPrimary; font.pixelSize: Services.Theme.fontSizeXs; font.family: Services.Theme.fontMono }
                            }
                            Text { text: "Close"; color: Services.Theme.textDisabled; font.pixelSize: Services.Theme.fontSizeXs }
                        }
                    }
                }
            }
        }
    }
}
