import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../services" as Services

PanelWindow {
    id: emojiPickerWindow
    visible: false

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell:emojipicker"
    exclusiveZone: 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    Component.onCompleted: Services.OverlayManager.register(emojiPickerWindow)

    property bool isOpen: false
    property string searchQuery: ""
    property var emojiResults: []
    property int currentIndex: 0
    readonly property int columnsCount: 10

    function show() {
        Services.OverlayManager.closeAllExcept(emojiPickerWindow)
        hideTimer.stop()
        visible = true
        isOpen = true
        searchQuery = ""
        searchField.text = ""
        currentIndex = 0
        if (Services.Emojis) {
            emojiResults = Services.Emojis.search("")
        }
        searchField.forceActiveFocus()
        if (emojiGridView && emojiGridView.count > 0) {
            emojiGridView.positionViewAtIndex(0, GridView.Beginning)
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
            emojiPickerWindow.visible = false
            searchQuery = ""
            emojiResults = []
        }
    }

    // Click outside panel → close
    MouseArea {
        anchors.fill: parent
        onClicked: emojiPickerWindow.hide()
    }

    // ── Panel ─────────────────────────────────────────────────────────
    Rectangle {
        id: panel
        anchors.centerIn: parent
        anchors.verticalCenterOffset: emojiPickerWindow.isOpen ? -30 : -10

        Behavior on anchors.verticalCenterOffset {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        width: 580
        height: 480
        clip: true

        radius: 16
        color: Services.Theme.surface
        border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.3)
        border.width: 1

        opacity: emojiPickerWindow.isOpen ? 1 : 0
        scale: emojiPickerWindow.isOpen ? 1 : 0.97

        Behavior on opacity {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ── Header Bar ────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 58
                Layout.leftMargin: 16; Layout.rightMargin: 16
                spacing: 12

                Text {
                    text: "😀"
                    font.pixelSize: 22
                    font.family: Services.Theme.fontEmoji
                    Layout.alignment: Qt.AlignVCenter
                }

                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    background: null
                    color: Services.Theme.textPrimary
                    placeholderText: "Search 1,800+ emojis... (e.g. fire, cat, laugh, heart)"
                    placeholderTextColor: Services.Theme.textDisabled
                    font.pixelSize: Services.Theme.fontSizeXl
                    leftPadding: 0
                    rightPadding: 0

                    onTextChanged: {
                        emojiPickerWindow.searchQuery = text
                        if (Services.Emojis) {
                            emojiPickerWindow.emojiResults = Services.Emojis.search(text)
                        }
                        emojiPickerWindow.currentIndex = 0
                        if (emojiGridView && emojiGridView.count > 0) {
                            emojiGridView.positionViewAtIndex(0, GridView.Beginning)
                        }
                    }

                    Keys.onPressed: (event) => {
                        const count = emojiPickerWindow.emojiResults ? emojiPickerWindow.emojiResults.length : 0

                        if (event.key === Qt.Key_Right) {
                            emojiPickerWindow.currentIndex = Math.min(emojiPickerWindow.currentIndex + 1, count - 1)
                            if (emojiGridView) emojiGridView.positionViewAtIndex(emojiPickerWindow.currentIndex, GridView.Contain)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Left) {
                            emojiPickerWindow.currentIndex = Math.max(emojiPickerWindow.currentIndex - 1, 0)
                            if (emojiGridView) emojiGridView.positionViewAtIndex(emojiPickerWindow.currentIndex, GridView.Contain)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Down) {
                            emojiPickerWindow.currentIndex = Math.min(emojiPickerWindow.currentIndex + emojiPickerWindow.columnsCount, count - 1)
                            if (emojiGridView) emojiGridView.positionViewAtIndex(emojiPickerWindow.currentIndex, GridView.Contain)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Up) {
                            emojiPickerWindow.currentIndex = Math.max(emojiPickerWindow.currentIndex - emojiPickerWindow.columnsCount, 0)
                            if (emojiGridView) emojiGridView.positionViewAtIndex(emojiPickerWindow.currentIndex, GridView.Contain)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Home) {
                            emojiPickerWindow.currentIndex = 0
                            if (emojiGridView) emojiGridView.positionViewAtIndex(0, GridView.Beginning)
                            event.accepted = true
                        } else if (event.key === Qt.Key_End) {
                            emojiPickerWindow.currentIndex = Math.max(0, count - 1)
                            if (emojiGridView) emojiGridView.positionViewAtIndex(emojiPickerWindow.currentIndex, GridView.End)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                            if (count > 0) {
                                emojiPickerWindow.currentIndex = (emojiPickerWindow.currentIndex - 1 + count) % count
                                if (emojiGridView) emojiGridView.positionViewAtIndex(emojiPickerWindow.currentIndex, GridView.Contain)
                            }
                            event.accepted = true
                        } else if (event.key === Qt.Key_Tab) {
                            if (count > 0) {
                                emojiPickerWindow.currentIndex = (emojiPickerWindow.currentIndex + 1) % count
                                if (emojiGridView) emojiGridView.positionViewAtIndex(emojiPickerWindow.currentIndex, GridView.Contain)
                            }
                            event.accepted = true
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (emojiPickerWindow.emojiResults && emojiPickerWindow.emojiResults.length > emojiPickerWindow.currentIndex) {
                                const em = emojiPickerWindow.emojiResults[emojiPickerWindow.currentIndex]
                                if (em && Services.Emojis) {
                                    Services.Emojis.insert(em)
                                    emojiPickerWindow.hide()
                                }
                            }
                            event.accepted = true
                        } else if (event.key === Qt.Key_Escape) {
                            emojiPickerWindow.hide()
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

                // Close Button
                Rectangle {
                    width: 28; height: 28; radius: 6
                    color: closeBtnMouse.containsMouse ? Qt.rgba(239, 68, 68, 0.15) : "transparent"
                    Layout.alignment: Qt.AlignVCenter
                    Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: Services.Theme.fontSizeMd
                        color: closeBtnMouse.containsMouse ? "#ef4444" : Services.Theme.textDisabled
                        Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    }

                    MouseArea {
                        id: closeBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: emojiPickerWindow.hide()
                    }
                }
            }

            // Hairline divider
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Services.Theme.border
            }

            // ── Emoji Grid View ───────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                GridView {
                    id: emojiGridView
                    anchors.fill: parent
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: 1200
                    cellWidth: (emojiGridView.width - 20) / emojiPickerWindow.columnsCount
                    cellHeight: 46
                    topMargin: 8; bottomMargin: 8
                    leftMargin: 10; rightMargin: 10

                    model: emojiPickerWindow.emojiResults
                    currentIndex: emojiPickerWindow.currentIndex

                    delegate: Item {
                        id: emojiCell
                        required property var modelData
                        required property int index

                        width: emojiGridView.cellWidth
                        height: emojiGridView.cellHeight

                        readonly property bool isSelected: emojiCell.index === emojiPickerWindow.currentIndex

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
                                font.family: Services.Theme.fontEmoji
                                renderType: Text.NativeRendering
                            }
                        }

                        MouseArea {
                            id: cellMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: {
                                emojiPickerWindow.currentIndex = emojiCell.index
                            }
                            onClicked: {
                                if (Services.Emojis) {
                                    Services.Emojis.insert(emojiCell.modelData)
                                    emojiPickerWindow.hide()
                                }
                            }
                        }
                    }
                }

                // Empty state
                Item {
                    anchors.fill: parent
                    visible: emojiPickerWindow.emojiResults.length === 0

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
                            text: "No emojis found for \"" + emojiPickerWindow.searchQuery + "\""
                            color: Services.Theme.textDisabled
                            font.pixelSize: Services.Theme.fontSizeLg
                            Layout.alignment: Qt.AlignHCenter
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

            // ── Bottom Preview & Info Strip ───────────────────────────
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
                    readonly property var currentEmojiObj: (emojiPickerWindow.emojiResults && emojiPickerWindow.emojiResults.length > emojiPickerWindow.currentIndex)
                        ? emojiPickerWindow.emojiResults[emojiPickerWindow.currentIndex]
                        : null

                    Text {
                        text: parent.currentEmojiObj ? parent.currentEmojiObj.emoji : "-"
                        font.pixelSize: 18
                        font.family: Services.Theme.fontEmoji
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

                    // Instruction badge
                    Rectangle {
                        radius: 4
                        color: Qt.rgba(255, 255, 255, 0.08)
                        implicitWidth: copyHintText.implicitWidth + 8
                        implicitHeight: 20
                        Layout.alignment: Qt.AlignVCenter

                        Text {
                            id: copyHintText
                            anchors.centerIn: parent
                            text: "↵ Enter to Insert / Copy"
                            color: Services.Theme.textSecondary
                            font.pixelSize: Services.Theme.fontSizeXs
                        }
                    }
                }
            }
        }
    }
}
