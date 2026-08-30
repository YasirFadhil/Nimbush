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
                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
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
                            resultList.positionViewAtIndex(resultList.currentIndex, ListView.Contain)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Up) {
                            resultList.currentIndex = Math.max(resultList.currentIndex - 1, 0)
                            resultList.positionViewAtIndex(resultList.currentIndex, ListView.Contain)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                            if (Services.Clipboard.filterType === "all") Services.Clipboard.filterType = "pinned"
                            else if (Services.Clipboard.filterType === "pinned") Services.Clipboard.filterType = "image"
                            else if (Services.Clipboard.filterType === "image") Services.Clipboard.filterType = "text"
                            else Services.Clipboard.filterType = "all"
                            resultList.currentIndex = 0
                            if (resultList.count > 0) resultList.positionViewAtIndex(0, ListView.Beginning)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Tab) {
                            if (Services.Clipboard.filterType === "all") Services.Clipboard.filterType = "text"
                            else if (Services.Clipboard.filterType === "text") Services.Clipboard.filterType = "image"
                            else if (Services.Clipboard.filterType === "image") Services.Clipboard.filterType = "pinned"
                            else Services.Clipboard.filterType = "all"
                            resultList.currentIndex = 0
                            if (resultList.count > 0) resultList.positionViewAtIndex(0, ListView.Beginning)
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

                // Liquid Glass Elastic Filter Pill Bar (Capsule Geometry)
                Rectangle {
                    id: clipFilterBar
                    height: 30
                    implicitWidth: 236
                    radius: 15
                    color: Services.Theme.surfaceVariant
                    border.color: Services.Theme.border
                    border.width: 1
                    clip: true
                    Layout.alignment: Qt.AlignVCenter

                    readonly property var filterIds: ["all", "text", "image", "pinned"]
                    readonly property int activeIdx: Math.max(0, filterIds.indexOf(Services.Clipboard.filterType))
                    readonly property int tabCount: 4
                    readonly property real itemWidth: Math.max(0, (clipFilterBar.width - 6 - (tabCount - 1) * 2) / tabCount)

                    // Sliding Liquid Glass Indicator Pill (Capsule Pill)
                    Rectangle {
                        id: clipLiquidPill
                        z: 1
                        y: 3
                        height: parent.height - 6
                        radius: 12

                        x: 3 + clipFilterBar.activeIdx * (clipFilterBar.itemWidth + 2)
                        width: clipFilterBar.itemWidth

                        // Liquid Transparent Glass Material
                        color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.24)
                        border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.55)
                        border.width: 1

                        property real stretchScaleX: 1.0
                        property real stretchScaleY: 1.0
                        transform: Scale {
                            origin.x: clipLiquidPill.width / 2
                            origin.y: clipLiquidPill.height / 2
                            xScale: clipLiquidPill.stretchScaleX
                            yScale: clipLiquidPill.stretchScaleY
                        }

                        // Top Specular Glass Line
                        Rectangle {
                            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                            anchors.topMargin: 1; anchors.leftMargin: 6; anchors.rightMargin: 6
                            height: 1; radius: 0.5
                            color: Qt.rgba(1, 1, 1, 0.40)
                        }

                        // Gloss Curved Sheen
                        Rectangle {
                            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                            anchors.topMargin: 1; anchors.leftMargin: 3; anchors.rightMargin: 3
                            height: parent.height * 0.46; radius: 10
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.16) }
                                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                            }
                        }

                        // Fluid Sliding Transitions
                        Behavior on x {
                            NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.15 }
                        }
                        Behavior on width {
                            NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.15 }
                        }
                    }

                    // Fluid Squash & Stretch Animation
                    SequentialAnimation {
                        id: clipStretchAnim
                        ParallelAnimation {
                            NumberAnimation { target: clipLiquidPill; property: "stretchScaleX"; to: 1.08; duration: 80; easing.type: Easing.OutQuad }
                            NumberAnimation { target: clipLiquidPill; property: "stretchScaleY"; to: 0.92; duration: 80; easing.type: Easing.OutQuad }
                        }
                        ParallelAnimation {
                            NumberAnimation { target: clipLiquidPill; property: "stretchScaleX"; to: 1.0; duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.28 }
                            NumberAnimation { target: clipLiquidPill; property: "stretchScaleY"; to: 1.0; duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.28 }
                        }
                    }

                    Connections {
                        target: Services.Clipboard
                        function onFilterTypeChanged() {
                            clipStretchAnim.restart()
                        }
                    }

                    RowLayout {
                        id: clipTabRow
                        anchors.fill: parent
                        anchors.margins: 3
                        spacing: 2
                        z: 2

                        Repeater {
                            id: clipTabRepeater
                            model: [
                                { id: "all",    label: "All" },
                                { id: "text",   label: "Text" },
                                { id: "image",  label: "Images" },
                                { id: "pinned", label: "Pinned" }
                            ]

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                readonly property bool isCur: Services.Clipboard.filterType === modelData.id

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 10
                                    color: tabMouse.containsMouse && !isCur ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    font.pixelSize: Services.Theme.fontSizeMd
                                    font.weight: isCur ? Font.DemiBold : Font.Normal
                                    color: isCur ? Services.Theme.textPrimary : (tabMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textDisabled)
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }

                                MouseArea {
                                    id: tabMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Services.Clipboard.filterType = modelData.id
                                        resultList.currentIndex = 0
                                    }
                                }
                            }
                        }
                    }
                }

                // Clear History Button (Circle / Capsule Styling)
                Rectangle {
                    height: 30
                    width: 30
                    radius: 15
                    color: clearHistMouse.containsMouse ? Qt.rgba(0.9, 0.2, 0.2, 0.18) : Services.Theme.surfaceVariant
                    border.color: clearHistMouse.containsMouse ? Services.Theme.danger : Services.Theme.border
                    border.width: 1
                    Layout.alignment: Qt.AlignVCenter
                    scale: clearHistMouse.pressed ? 0.94 : (clearHistMouse.containsMouse ? 1.04 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
                    Behavior on color { ColorAnimation { duration: 180 } }
                    Behavior on border.color { ColorAnimation { duration: 180 } }

                    Text {
                        anchors.centerIn: parent
                        text: Services.Icons.trash
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 12
                        color: clearHistMouse.containsMouse ? Services.Theme.danger : Services.Theme.textDisabled
                        Behavior on color { ColorAnimation { duration: 180 } }
                    }

                    MouseArea {
                        id: clearHistMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
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
                spacing: 4
                model: Services.Clipboard.filteredEntries
                currentIndex: 0
                keyNavigationEnabled: false
                topMargin: 4; bottomMargin: 4
                leftMargin: 8; rightMargin: 8

                delegate: Rectangle {
                    id: card
                    required property var modelData
                    required property int index
                    width: resultList.width - 16
                    height: 56
                    radius: 10

                    readonly property bool isCurrent: card.index === resultList.currentIndex

                    color: isCurrent 
                        ? Services.Theme.surfaceVariant 
                        : (hoverArea.containsMouse ? Services.Theme.bgHover : "transparent")
                    border.color: isCurrent ? Services.Theme.accent : "transparent"
                    border.width: isCurrent ? 1 : 0
                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

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
                                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                }

                                Text {
                                    visible: card.isImage
                                    text: "Image Content"
                                    color: card.index === resultList.currentIndex ? Services.Theme.accent : Services.Theme.textPrimary
                                    font.pixelSize: Services.Theme.fontSizeXl
                                    font.weight: card.index === resultList.currentIndex ? Font.Medium : Font.Normal
                                    Layout.fillWidth: true
                                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
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

                                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                Text {
                                    anchors.centerIn: parent
                                    text: Services.Icons.pin
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: Services.Theme.fontSizeLg
                                    color: card.isPinnedItem ? Services.Theme.accent : (pinArea.containsMouse ? Services.Theme.textPrimary : Services.Theme.textDisabled)
                                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
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

                                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                Text {
                                    anchors.centerIn: parent
                                    text: Services.Icons.trash
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: Services.Theme.fontSizeXl
                                    color: deleteArea.containsMouse ? Services.Theme.danger : Services.Theme.textDisabled
                                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
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
