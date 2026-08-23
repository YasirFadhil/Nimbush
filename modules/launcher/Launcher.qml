import Quickshell
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
    property var emojiResults: []
    property int emojiCurrentIndex: 0
    readonly property int emojiColumns: 10

    function show() {
        Services.OverlayManager.closeAllExcept(launcherWindow)
        hideTimer.stop()
        visible = true
        isOpen = true
        Services.Applications.query = ""
        searchField.text = ""
        emojiResults = []
        emojiCurrentIndex = 0
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
            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
        }

        width: launcherWindow.isEmojiMode ? 560 : 520
        height: launcherWindow.isEmojiMode 
            ? (launcherWindow.isOpen ? 460 : 64) 
            : (searchField.text.length > 0 ? Math.min(listCol.implicitHeight, 460) : 64)

        Behavior on width {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on height {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }

        radius: 16
        color: Services.Theme.surface
        border.color: launcherWindow.isEmojiMode ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.4) : Services.Theme.border
        border.width: 1

        opacity: launcherWindow.isOpen ? 1 : 0
        scale: launcherWindow.isOpen ? 1 : 0.96

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
        }
        Behavior on border.color {
            ColorAnimation { duration: 250; easing.type: Easing.OutCubic }
        }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: listCol
            anchors { left: parent.left; right: parent.right; top: parent.top }
            spacing: 0

            // ── Search Bar ────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16; Layout.rightMargin: 16
                Layout.topMargin: 14; Layout.bottomMargin: 12
                spacing: 10

                Text {
                    text: Services.Icons.search
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: Services.Theme.fontSize2xl
                    color: launcherWindow.isEmojiMode ? Services.Theme.accent : (searchField.activeFocus ? Services.Theme.accent : Services.Theme.textDisabled)
                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                }

                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    background: null
                    color: Services.Theme.textPrimary
                    placeholderText: launcherWindow.isEmojiMode 
                        ? (launcherWindow.emojiQuery.length === 0 ? "Search 1,800+ emojis... (e.g. fire, cat, laugh, heart)" : "") 
                        : "Search applications... (Type >E for emoji)"
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
                        } else {
                            Services.Applications.query = text
                            resultList.currentIndex = 0
                        }
                    }

                    Keys.onPressed: (event) => {
                        if (launcherWindow.isEmojiMode) {
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
                                event.accepted = true
                            } else if (event.key === Qt.Key_Up) {
                                resultList.currentIndex = Math.max(resultList.currentIndex - 1, 0)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                const apps = resultList.model
                                if (apps && apps.length > resultList.currentIndex) {
                                    const app = apps[resultList.currentIndex]
                                    if (app) { app.execute(); launcherWindow.hide() }
                                }
                                event.accepted = true
                            } else if (event.key === Qt.Key_Escape) {
                                launcherWindow.hide(); event.accepted = true
                            }
                        }
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

                // Helper Hint when search field is empty
                Rectangle {
                    radius: 6
                    color: Qt.rgba(255, 255, 255, 0.04)
                    border.color: Services.Theme.borderSubtle
                    border.width: 1
                    implicitWidth: hintBadgeText.implicitWidth + 10
                    implicitHeight: 20
                    visible: !launcherWindow.isEmojiMode && searchField.text.length === 0
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        id: hintBadgeText
                        anchors.centerIn: parent
                        text: ">E for Emoji"
                        color: Services.Theme.textDisabled
                        font.pixelSize: Services.Theme.fontSizeXs
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
            }

            // Hairline divider
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Services.Theme.border
                opacity: (searchField.text.length > 0 || launcherWindow.isEmojiMode) ? 0.6 : 0

                Behavior on opacity {
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }
            }

            // ═════════════════════════════════════════════════════════════════
            // ── APPLICATIONS LIST VIEW (Default Mode) ────────────────────────
            // ═════════════════════════════════════════════════════════════════
            ListView {
                id: resultList
                Layout.fillWidth: true
                Layout.preferredHeight: (!launcherWindow.isEmojiMode && searchField.text.length > 0) ? (count > 0 ? Math.min(contentHeight, 380) : 100) : 0
                opacity: (!launcherWindow.isEmojiMode && searchField.text.length > 0) ? 1 : 0
                visible: opacity > 0
                clip: true
                spacing: 4
                model: Services.Applications.filteredApps
                currentIndex: 0
                keyNavigationEnabled: false
                topMargin: 4; bottomMargin: 4
                leftMargin: 8; rightMargin: 8

                Behavior on Layout.preferredHeight {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }

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
                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12; anchors.rightMargin: 12
                        spacing: 12

                        // App Icon
                        Item {
                            Layout.preferredWidth: 30; Layout.preferredHeight: 30
                            Layout.alignment: Qt.AlignVCenter

                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: appItem.index === resultList.currentIndex ? Qt.rgba(255, 255, 255, 0.1) : Qt.rgba(255, 255, 255, 0.05)
                                visible: ico.status !== Image.Ready

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
                                    const s = appItem.modelData.icon ?? ""
                                    if (!s) return ""
                                    if (s.startsWith("/") || s.startsWith("file://")) return s
                                    return Quickshell.iconPath(s, true)
                                }
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: true
                                sourceSize: Qt.size(32, 32)
                                visible: status === Image.Ready
                                smooth: true
                                mipmap: true
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
                                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
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
                        onEntered: {
                            if (resultList.currentIndex !== appItem.index) {
                                resultList.currentIndex = appItem.index
                            }
                        }
                        onClicked: {
                            appItem.modelData.execute()
                            launcherWindow.hide()
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

            // ═════════════════════════════════════════════════════════════════
            // ── EMOJI PICKER GRID VIEW (>E Mode) ──────────────────────────────
            // ═════════════════════════════════════════════════════════════════
            ColumnLayout {
                id: emojiContainer
                Layout.fillWidth: true
                Layout.preferredHeight: launcherWindow.isEmojiMode ? 388 : 0
                opacity: launcherWindow.isEmojiMode ? 1 : 0
                visible: opacity > 0
                spacing: 0

                Behavior on Layout.preferredHeight {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }

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
