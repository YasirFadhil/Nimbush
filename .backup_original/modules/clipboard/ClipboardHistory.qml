import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../services" as Services

PanelWindow {
    id: clipboardWindow
    visible: false

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell:clipboard"
    exclusiveZone: 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    Component.onCompleted: Services.OverlayManager.register(clipboardWindow)

    property bool isOpen: false

    function show() {
        Services.OverlayManager.closeAllExcept(clipboardWindow)
        hideTimer.stop()
        visible = true
        isOpen = true
        Services.Clipboard.query = ""
        Services.Clipboard.filterType = "all"
        searchField.text = ""
        Services.Clipboard.refresh()
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
            clipboardWindow.visible = false
            Services.Clipboard.query = ""
        }
    }

    // Click outside panel → close
    MouseArea {
        anchors.fill: parent
        onClicked: clipboardWindow.hide()
    }

    // ── Panel ─────────────────────────────────────────────────────────
    Rectangle {
        id: panel
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -40

        width: 600
        height: 480

        radius: 16
        color: Services.Theme.surface
        border.color: Services.Theme.border
        border.width: 1

        opacity: clipboardWindow.isOpen ? 1 : 0
        scale: clipboardWindow.isOpen ? 1 : 0.96

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
        }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: listCol
            anchors.fill: parent
            spacing: 0

            // ── Search & Filter Header ────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16; Layout.rightMargin: 16
                Layout.topMargin: 14; Layout.bottomMargin: 12
                spacing: 10

                Text {
                    text: Services.Icons.clipboard
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: Services.Theme.fontSize3xl
                    color: searchField.activeFocus ? Services.Theme.accent : Services.Theme.textDisabled
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    background: null
                    color: Services.Theme.textPrimary
                    placeholderText: "Search clipboard history..."
                    placeholderTextColor: Services.Theme.textDisabled
                    font.pixelSize: Services.Theme.fontSize3xl
                    leftPadding: 0
                    rightPadding: 0

                    onTextChanged: {
                        Services.Clipboard.query = text
                        resultList.currentIndex = 0
                    }

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Down) {
                            resultList.currentIndex = Math.min(resultList.currentIndex + 1, resultList.count - 1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Up) {
                            resultList.currentIndex = Math.max(resultList.currentIndex - 1, 0)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Tab) {
                            if (Services.Clipboard.filterType === "all") Services.Clipboard.filterType = "text"
                            else if (Services.Clipboard.filterType === "text") Services.Clipboard.filterType = "image"
                            else if (Services.Clipboard.filterType === "image") Services.Clipboard.filterType = "pinned"
                            else Services.Clipboard.filterType = "all"
                            resultList.currentIndex = 0
                            event.accepted = true
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            const list = Services.Clipboard.filtered()
                            if (list && list.length > resultList.currentIndex) {
                                const selected = list[resultList.currentIndex]
                                if (selected) {
                                    Services.Clipboard.select(selected)
                                    clipboardWindow.hide()
                                }
                            }
                            event.accepted = true
                        } else if (event.key === Qt.Key_Delete) {
                            if (event.modifiers & Qt.ShiftModifier) {
                                Services.Clipboard.clearAll()
                            } else {
                                const list = Services.Clipboard.filtered()
                                if (list && list.length > resultList.currentIndex) {
                                    const toDelete = list[resultList.currentIndex]
                                    if (toDelete) Services.Clipboard.deleteEntry(toDelete)
                                }
                            }
                            event.accepted = true
                        } else if (event.key === Qt.Key_Escape) {
                            clipboardWindow.hide()
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

                // Filter Pill Tabs
                RowLayout {
                    spacing: 4
                    Layout.alignment: Qt.AlignVCenter

                    Repeater {
                        model: [
                            { id: "all", label: "All" },
                            { id: "text", label: "Text" },
                            { id: "image", label: "Images" },
                            { id: "pinned", label: "Pinned" }
                        ]

                        Rectangle {
                            required property var modelData
                            height: 24
                            width: filterText.implicitWidth + 14
                            radius: 7
                            color: Services.Clipboard.filterType === modelData.id ? Services.Theme.surfaceVariant : (tabMouse.containsMouse ? Services.Theme.bgHover : "transparent")
                            border.color: Services.Clipboard.filterType === modelData.id ? Services.Theme.borderHighlight : "transparent"
                            border.width: 1

                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                id: filterText
                                anchors.centerIn: parent
                                text: parent.modelData.label
                                font.pixelSize: Services.Theme.fontSizeMd
                                font.weight: Services.Clipboard.filterType === parent.modelData.id ? Font.Medium : Font.Normal
                                color: Services.Clipboard.filterType === parent.modelData.id ? Services.Theme.accent : Services.Theme.textDisabled
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            MouseArea {
                                id: tabMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    Services.Clipboard.filterType = parent.modelData.id
                                    resultList.currentIndex = 0
                                }
                            }
                        }
                    }
                }

                // Clear History Button
                Rectangle {
                    height: 24
                    width: 24
                    radius: 7
                    color: clearHistMouse.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                    border.color: clearHistMouse.containsMouse ? Services.Theme.danger : "transparent"
                    border.width: 1
                    Layout.alignment: Qt.AlignVCenter

                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on border.color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: Services.Icons.trash
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: Services.Theme.fontSizeLg
                        color: clearHistMouse.containsMouse ? Services.Theme.danger : Services.Theme.textDisabled
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    MouseArea {
                        id: clearHistMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: Services.Clipboard.clearAll()
                    }
                }
            }

            // Hairline divider
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Services.Theme.border
                opacity: 0.6
            }

            // ── List View ─────────────────────────────────────────────
            ListView {
                id: resultList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: Services.Clipboard.filteredEntries
                currentIndex: 0
                keyNavigationEnabled: false
                topMargin: 6; bottomMargin: 6
                leftMargin: 6; rightMargin: 6

                highlight: Rectangle {
                    radius: 10
                    color: Services.Theme.surfaceSolid
                    border.color: Services.Theme.borderHighlight
                    border.width: 1
                    x: 6
                    width: resultList.width - 12
                    z: 1
                }
                highlightMoveDuration: 130
                highlightResizeDuration: 0
                highlightFollowsCurrentItem: true

                delegate: Item {
                    id: card
                    required property var modelData
                    required property int index
                    width: resultList.width - 12
                    height: 56

                    property bool isImage: Services.Clipboard.isImageEntry(modelData)
                    property bool isPinnedItem: Services.Clipboard.isPinned(modelData)
                    property string thumbPath: ""

                    Process {
                        id: thumbProc
                        property string pendingPath: ""
                        onExited: card.thumbPath = pendingPath
                    }

                    Component.onCompleted: {
                        if (isImage) {
                            const m = modelData.preview.match(/\b(png|jpe?g|gif|bmp|webp)\b/i)
                            const ext = m ? m[1].toLowerCase() : "png"
                            const path = "/tmp/qs-clip-" + modelData.id + "." + ext
                            thumbProc.pendingPath = path
                            thumbProc.command = ["sh", "-c",
                                "test -f '" + path + "' || cliphist decode " + modelData.id + " > '" + path + "'"]
                            thumbProc.running = true
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12; anchors.rightMargin: 12
                        spacing: 12
                        z: 2

                        // Entry Type Badge / Thumbnail
                        Item {
                            Layout.preferredWidth: card.isImage ? 80 : 34
                            Layout.preferredHeight: card.isImage ? 40 : 34
                            Layout.alignment: Qt.AlignVCenter

                            // Text badge
                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: card.index === resultList.currentIndex ? Qt.rgba(255, 255, 255, 0.1) : Qt.rgba(255, 255, 255, 0.05)
                                visible: !card.isImage

                                Text {
                                    anchors.centerIn: parent
                                    text: Services.Icons.file
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: Services.Theme.fontSizeXl
                                    color: card.index === resultList.currentIndex ? Services.Theme.accent : Services.Theme.textDisabled
                                }
                            }

                            // Image thumbnail
                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: card.index === resultList.currentIndex ? Qt.rgba(255, 255, 255, 0.1) : Qt.rgba(255, 255, 255, 0.05)
                                border.color: Services.Theme.border
                                border.width: 1
                                clip: true
                                visible: card.isImage

                                Image {
                                    anchors.fill: parent
                                    source: card.isImage && card.thumbPath.length > 0
                                        ? "file://" + card.thumbPath : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    sourceSize: Qt.size(160, 100)
                                    smooth: true
                                }
                            }
                        }

                        // Content Information
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 1

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    visible: !card.isImage
                                    text: card.modelData.preview || ""
                                    color: card.index === resultList.currentIndex ? Services.Theme.accent : Services.Theme.textPrimary
                                    font.pixelSize: Services.Theme.fontSizeXl
                                    font.weight: card.index === resultList.currentIndex ? Font.Medium : Font.Normal
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                    maximumLineCount: 1
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                Text {
                                    visible: card.isImage
                                    text: "Image Content"
                                    color: card.index === resultList.currentIndex ? Services.Theme.accent : Services.Theme.textPrimary
                                    font.pixelSize: Services.Theme.fontSizeXl
                                    font.weight: card.index === resultList.currentIndex ? Font.Medium : Font.Normal
                                    Layout.fillWidth: true
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                Text {
                                    text: Services.Icons.pin
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: Services.Theme.fontSizeSm
                                    color: Services.Theme.accent
                                    visible: card.isPinnedItem
                                }
                            }

                            Text {
                                visible: !card.isImage
                                text: {
                                    const p = card.modelData.preview || ""
                                    const lines = p.split("\n").length
                                    const chars = p.length
                                    return lines > 1 ? (lines + " lines • " + chars + " characters") : (chars + " characters")
                                }
                                color: Services.Theme.textSecondary
                                font.pixelSize: Services.Theme.fontSizeMd
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Text {
                                visible: card.isImage
                                text: {
                                    const dim = card.modelData.preview.match(/\b\d+x\d+\b/)?.[0]
                                    return dim ? ("Dimensions: " + dim) : "Image entry"
                                }
                                color: Services.Theme.textSecondary
                                font.pixelSize: Services.Theme.fontSizeMd
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        // Action buttons row (Pin & Delete)
                        RowLayout {
                            spacing: 4

                            // Pin action button
                            Rectangle {
                                Layout.preferredWidth: 28; Layout.preferredHeight: 28
                                radius: 7
                                color: card.isPinnedItem ? Services.Theme.surfaceVariant : (pinArea.containsMouse ? Services.Theme.surfaceVariant : "transparent")

                                Behavior on color { ColorAnimation { duration: 120 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: Services.Icons.pin
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: Services.Theme.fontSizeLg
                                    color: card.isPinnedItem ? Services.Theme.accent : (pinArea.containsMouse ? Services.Theme.textPrimary : Services.Theme.textDisabled)
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                MouseArea {
                                    id: pinArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: Services.Clipboard.togglePin(card.modelData)
                                }
                            }

                            // Delete action button
                            Rectangle {
                                Layout.preferredWidth: 28; Layout.preferredHeight: 28
                                radius: 7
                                color: deleteArea.containsMouse ? Services.Theme.surfaceVariant : "transparent"

                                Behavior on color { ColorAnimation { duration: 120 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: Services.Icons.trash
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: Services.Theme.fontSizeXl
                                    color: deleteArea.containsMouse ? Services.Theme.danger : Services.Theme.textDisabled
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                MouseArea {
                                    id: deleteArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: Services.Clipboard.deleteEntry(card.modelData)
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: hoverArea
                        anchors.fill: parent
                        anchors.rightMargin: 70
                        hoverEnabled: true
                        onEntered: {
                            if (resultList.currentIndex !== card.index) {
                                resultList.currentIndex = card.index
                            }
                        }
                        onClicked: {
                            Services.Clipboard.select(card.modelData)
                            clipboardWindow.hide()
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
                            text: Services.Clipboard.filterType === "pinned" ? Services.Icons.pin : Services.Icons.clipboard
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: Services.Theme.fontSize9xl
                            color: Services.Theme.textDisabled
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Text {
                            text: {
                                if (Services.Clipboard.filterType === "pinned") return "No pinned clipboard items yet"
                                if (Services.Clipboard.query.length > 0) return "No matching clipboard items"
                                return "Clipboard history is empty"
                            }
                            color: Services.Theme.textDisabled
                            font.pixelSize: Services.Theme.fontSizeXl
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
            }

            // ── Footer Keyboard Hints ─────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                height: 34
                color: "transparent"

                Rectangle {
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    height: 1
                    color: Services.Theme.border
                    opacity: 0.5
                }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 16

                    RowLayout {
                        spacing: 4
                        Rectangle {
                            width: 18; height: 16; radius: 4
                            color: Services.Theme.surfaceVariant
                            Text { anchors.centerIn: parent; text: "↵"; color: Services.Theme.textSecondary; font.pixelSize: Services.Theme.fontSizeSm }
                        }
                        Text { text: "Copy"; color: Services.Theme.textDisabled; font.pixelSize: Services.Theme.fontSizeMd }
                    }

                    RowLayout {
                        spacing: 4
                        Rectangle {
                            width: 28; height: 16; radius: 4
                            color: Services.Theme.surfaceVariant
                            Text { anchors.centerIn: parent; text: "Tab"; color: Services.Theme.textSecondary; font.pixelSize: Services.Theme.fontSizeSm }
                        }
                        Text { text: "Filter"; color: Services.Theme.textDisabled; font.pixelSize: Services.Theme.fontSizeMd }
                    }

                    RowLayout {
                        spacing: 4
                        Rectangle {
                            width: 24; height: 16; radius: 4
                            color: Services.Theme.surfaceVariant
                            Text { anchors.centerIn: parent; text: "Del"; color: Services.Theme.textSecondary; font.pixelSize: Services.Theme.fontSizeSm }
                        }
                        Text { text: "Delete"; color: Services.Theme.textDisabled; font.pixelSize: Services.Theme.fontSizeMd }
                    }

                    RowLayout {
                        spacing: 4
                        Rectangle {
                            width: 52; height: 16; radius: 4
                            color: Services.Theme.surfaceVariant
                            Text { anchors.centerIn: parent; text: "Shift+Del"; color: Services.Theme.textSecondary; font.pixelSize: Services.Theme.fontSizeSm }
                        }
                        Text { text: "Clear All"; color: Services.Theme.textDisabled; font.pixelSize: Services.Theme.fontSizeMd }
                    }

                    RowLayout {
                        spacing: 4
                        Rectangle {
                            width: 22; height: 16; radius: 4
                            color: Services.Theme.surfaceVariant
                            Text { anchors.centerIn: parent; text: "Esc"; color: Services.Theme.textSecondary; font.pixelSize: Services.Theme.fontSizeSm }
                        }
                        Text { text: "Close"; color: Services.Theme.textDisabled; font.pixelSize: Services.Theme.fontSizeMd }
                    }
                }
            }
        }
    }
}
