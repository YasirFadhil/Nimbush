import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../services" as Services

PanelWindow {
    id: root
    property string overlayId: "volumePanel"
    property bool sinksExpanded: false
    property bool sourcesExpanded: false
    property bool streamsExpanded: false

    readonly property bool isBottom: Services.Config ? (Services.Config.barPosition === "bottom") : false
    readonly property string barStyle: Services.Config ? Services.Config.barStyle : "islands"
    readonly property bool isFloating: barStyle === "floating"
    readonly property int barTotalHeight: Services.Config ? (Services.Config.barStyle === "minimal" ? 30 : (Services.Config.barStyle === "unified" ? 38 : (Services.Config.barStyle === "floating" ? 46 : 36))) : 36

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusiveZone: 0
    visible: Services.OverlayManager.volumePanelVisible
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:volume"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region {
        Region {
            x: 0
            y: root.isBottom ? 0 : root.barTotalHeight
            width: root.width
            height: root.height - root.barTotalHeight
        }
    }

    readonly property bool isCenteredBar: barStyle !== "islands"

    function open() {
        Services.OverlayManager.closeAllExcept(root)
        root.sinksExpanded = false
        root.sourcesExpanded = false
        root.streamsExpanded = false
        Services.OverlayManager.volumePanelVisible = true
        Services.Audio.refreshAll()
    }
    function close() {
        Services.OverlayManager.volumePanelVisible = false
    }
    function hide() { close() }
    function show() { open() }
    function toggle() {
        if (Services.OverlayManager.volumePanelVisible) close()
        else open()
    }

    onVisibleChanged: {
        if (visible) {
            Services.Audio.refreshAll()
        }
    }

    Component.onCompleted: Services.OverlayManager.register(root)

    Item {
        id: escFocus
        focus: Services.OverlayManager.volumePanelVisible
        Keys.onEscapePressed: root.close()
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()

        Rectangle {
            id: panel
            width: 360
            implicitHeight: mainCol.implicitHeight + 32
            readonly property real targetX: Services.OverlayManager.volumeTargetX > 0 
                ? Services.OverlayManager.volumeTargetX 
                : (parent.width - 220)
            x: Math.max(12, Math.min(parent.width - width - 12, targetX - (width / 2)))
            y: root.isBottom ? (parent.height - height - 12) : 12
            radius: Services.Theme.radiusLg
            color: Services.Theme.surface
            border.color: Services.Theme.border
            border.width: 1
            clip: true

            opacity: Services.OverlayManager.volumePanelVisible ? 1 : 0
            transform: Translate {
                y: Services.OverlayManager.volumePanelVisible ? 0 : (root.isBottom ? 32 : -32)
                Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 0.5 } }
            }
            scale: Services.OverlayManager.volumePanelVisible ? 1 : 0.96
            Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent; onClicked: {} }

            ColumnLayout {
                id: mainCol
                anchors.fill: parent
                anchors.margins: 16
                spacing: 14

                // ── 1. Header ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: Services.Icons.volumeIcon(Services.Audio.volume, Services.Audio.muted, Services.Audio.isHeadphone, Services.Audio.isTws)
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 16
                        color: Services.Audio.muted ? Services.Theme.textDisabled : Services.Theme.accent
                    }

                    Text {
                        text: "Sound & Devices"
                        font.family: Services.Theme.fontPrimary
                        font.bold: true
                        font.pixelSize: Services.Theme.fontSizeXl
                        color: Services.Theme.textPrimary
                        Layout.fillWidth: true
                    }

                    // Refresh Button
                    Rectangle {
                        width: 24; height: 24; radius: 12
                        color: refreshBtnArea.containsMouse ? Services.Theme.bgHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.refresh
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 11
                            color: refreshBtnArea.containsMouse ? Services.Theme.accent : Services.Theme.textSecondary
                        }
                        MouseArea {
                            id: refreshBtnArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.Audio.refreshAll()
                        }
                    }

                    // Close Button
                    Rectangle {
                        width: 24; height: 24; radius: 12
                        color: closeBtnArea.containsMouse ? Services.Theme.bgHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.close
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 11
                            color: closeBtnArea.containsMouse ? Services.Theme.accent : Services.Theme.textSecondary
                        }
                        MouseArea {
                            id: closeBtnArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.close()
                        }
                    }
                }

                // ── 2. Output (Playback) Section ──
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Output"
                            font.bold: true
                            font.pixelSize: Services.Theme.fontSizeMd
                            color: Services.Theme.textPrimary
                        }

                        Item { Layout.fillWidth: true }

                        // Device selector menu toggle button
                        Rectangle {
                            implicitHeight: 22
                            implicitWidth: sinkMenuBtnRow.implicitWidth + 12
                            radius: 11
                            color: sinkMenuArea.containsMouse 
                                ? Qt.lighter(Services.Theme.surfaceVariant, 1.2) 
                                : Services.Theme.surfaceVariant
                            border.color: root.sinksExpanded ? Services.Theme.accent : Services.Theme.borderSubtle
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }

                            RowLayout {
                                id: sinkMenuBtnRow
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    text: Services.Icons.sinkIcon(Services.Audio.currentSink?.description)
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 10
                                    color: Services.Theme.accent
                                }

                                Text {
                                    text: Services.Audio.currentSink ? (Services.Audio.currentSink.nick || Services.Audio.currentSink.description) : "Devices"
                                    color: Services.Theme.textSecondary
                                    font.pixelSize: 9
                                    font.bold: true
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 110
                                }

                                Text {
                                    text: root.sinksExpanded ? "▴" : "▾"
                                    color: Services.Theme.textDisabled
                                    font.pixelSize: 8
                                }
                            }

                            MouseArea {
                                id: sinkMenuArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.sinksExpanded = !root.sinksExpanded
                            }
                        }

                        Text {
                            text: Services.Audio.muted ? "Muted" : (Math.round(Services.Audio.volume * 100) + "%")
                            font.family: Services.Theme.fontMono
                            font.bold: true
                            font.pixelSize: Services.Theme.fontSizeSm
                            color: Services.Audio.muted ? Services.Theme.danger : Services.Theme.textSecondary
                        }
                    }

                    // Output Slider & Mute
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        // Capsule Slider
                        Rectangle {
                            id: sinkSlider
                            Layout.fillWidth: true
                            implicitHeight: 38
                            radius: Services.Theme.radiusMd
                            color: sinkSliderMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.surfaceVariant
                            border.color: sinkSliderMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.borderSubtle
                            border.width: 1
                            clip: true

                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            Rectangle {
                                id: sinkFillBar
                                height: parent.height
                                radius: parent.radius
                                color: Services.Audio.muted ? Services.Theme.textDisabled : (sinkSliderMouse.containsMouse ? Qt.lighter(Services.Theme.accent, 1.1) : Services.Theme.accent)
                                width: Math.max(38, Math.min(parent.width, (Services.Audio.muted ? 0 : Services.Audio.volume) * parent.width))
                                Behavior on width { NumberAnimation { duration: 80 } }
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 8

                                Text {
                                    id: sinkIconText
                                    text: Services.Icons.volumeIcon(Services.Audio.volume, Services.Audio.muted, Services.Audio.isHeadphone, Services.Audio.isTws)
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 14
                                    color: (sinkFillBar.width > (sinkIconText.x + 20)) ? Services.Theme.bgOnAccent : Services.Theme.textPrimary
                                    Behavior on color { ColorAnimation { duration: 80 } }
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    id: sinkPctText
                                    text: Services.Audio.muted ? "MUTED" : (Math.round(Services.Audio.volume * 100) + "%")
                                    font.family: Services.Theme.fontMono
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: (sinkFillBar.width > (parent.width - 40)) ? Services.Theme.bgOnAccent : Services.Theme.textPrimary
                                    Behavior on color { ColorAnimation { duration: 80 } }
                                }
                            }

                            MouseArea {
                                id: sinkSliderMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onPressed: (mouse) => Services.Audio.setVolume(Math.max(0, Math.min(1, mouse.x / width)))
                                onPositionChanged: (mouse) => {
                                    if (pressed) Services.Audio.setVolume(Math.max(0, Math.min(1, mouse.x / width)))
                                }
                            }
                        }

                        // Mute Toggle Button
                        Rectangle {
                            width: 38
                            height: 38
                            radius: Services.Theme.radiusMd
                            color: Services.Audio.muted 
                                ? Qt.rgba(Services.Theme.danger.r, Services.Theme.danger.g, Services.Theme.danger.b, 0.2) 
                                : (sinkMuteMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.surfaceVariant)
                            border.color: Services.Audio.muted ? Services.Theme.danger : (sinkMuteMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.borderSubtle)
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: Services.Audio.muted ? Services.Icons.volOff : Services.Icons.speaker
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 14
                                color: Services.Audio.muted ? Services.Theme.danger : Services.Theme.textPrimary
                            }

                            MouseArea {
                                id: sinkMuteMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.Audio.toggleMute()
                            }
                        }
                    }

                    // Collapsible Sink Selection List
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: sinkListCol.implicitHeight + 8
                        radius: Services.Theme.radiusMd
                        color: Services.Theme.surfaceVariant
                        border.color: Services.Theme.borderSubtle
                        border.width: 1
                        visible: root.sinksExpanded && (Services.Audio.sinks?.length ?? 0) > 0
                        clip: true

                        ColumnLayout {
                            id: sinkListCol
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: 4

                            Repeater {
                                model: Services.Audio.sinks
                                delegate: Rectangle {
                                    id: sinkRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 36
                                    radius: Services.Theme.radiusSm
                                    readonly property bool isCurrent: sinkRow.modelData.isCurrent
                                    color: isCurrent 
                                        ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.22) 
                                        : (sinkRowArea.containsMouse ? Services.Theme.bgHover : "transparent")
                                    border.color: isCurrent ? Services.Theme.accent : "transparent"
                                    border.width: 1

                                    MouseArea {
                                        id: sinkRowArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            Services.Audio.setSink(sinkRow.modelData.name)
                                            root.sinksExpanded = false
                                        }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 8

                                        Text {
                                            text: Services.Icons.sinkIcon(sinkRow.modelData.description)
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 13
                                            color: sinkRow.isCurrent ? Services.Theme.accent : Services.Theme.textSecondary
                                        }

                                        Text {
                                            text: sinkRow.modelData.nick || sinkRow.modelData.description
                                            color: Services.Theme.textPrimary
                                            font.bold: sinkRow.isCurrent
                                            font.pixelSize: 10
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        Text {
                                            visible: sinkRow.isCurrent
                                            text: Services.Icons.check
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 11
                                            font.bold: true
                                            color: Services.Theme.accent
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── 3. Divider ──
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Services.Theme.borderSubtle
                }

                // ── 4. Input (Microphone) Section ──
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Input"
                            font.bold: true
                            font.pixelSize: Services.Theme.fontSizeMd
                            color: Services.Theme.textPrimary
                        }

                        Item { Layout.fillWidth: true }

                        // Device selector menu toggle button
                        Rectangle {
                            implicitHeight: 22
                            implicitWidth: srcMenuBtnRow.implicitWidth + 12
                            radius: 11
                            color: srcMenuArea.containsMouse 
                                ? Qt.lighter(Services.Theme.surfaceVariant, 1.2) 
                                : Services.Theme.surfaceVariant
                            border.color: root.sourcesExpanded ? Services.Theme.accent : Services.Theme.borderSubtle
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }

                            RowLayout {
                                id: srcMenuBtnRow
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    text: Services.Icons.sourceIcon(Services.Audio.currentSource?.description)
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 10
                                    color: Services.Theme.accent
                                }

                                Text {
                                    text: Services.Audio.currentSource ? (Services.Audio.currentSource.nick || Services.Audio.currentSource.description) : "Mics"
                                    color: Services.Theme.textSecondary
                                    font.pixelSize: 9
                                    font.bold: true
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 110
                                }

                                Text {
                                    text: root.sourcesExpanded ? "▴" : "▾"
                                    color: Services.Theme.textDisabled
                                    font.pixelSize: 8
                                }
                            }

                            MouseArea {
                                id: srcMenuArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.sourcesExpanded = !root.sourcesExpanded
                            }
                        }

                        Text {
                            text: Services.Audio.sourceMuted ? "Muted" : (Math.round(Services.Audio.sourceVolume * 100) + "%")
                            font.family: Services.Theme.fontMono
                            font.bold: true
                            font.pixelSize: Services.Theme.fontSizeSm
                            color: Services.Audio.sourceMuted ? Services.Theme.danger : Services.Theme.textSecondary
                        }
                    }

                    // Input Slider & Mute
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        // Capsule Slider
                        Rectangle {
                            id: srcSlider
                            Layout.fillWidth: true
                            implicitHeight: 38
                            radius: Services.Theme.radiusMd
                            color: srcSliderMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.surfaceVariant
                            border.color: srcSliderMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.borderSubtle
                            border.width: 1
                            clip: true

                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            Rectangle {
                                id: srcFillBar
                                height: parent.height
                                radius: parent.radius
                                color: Services.Audio.sourceMuted ? Services.Theme.textDisabled : (srcSliderMouse.containsMouse ? Qt.lighter(Services.Theme.accent, 1.1) : Services.Theme.accent)
                                width: Math.max(38, Math.min(parent.width, (Services.Audio.sourceMuted ? 0 : Services.Audio.sourceVolume) * parent.width))
                                Behavior on width { NumberAnimation { duration: 80 } }
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 8

                                Text {
                                    id: srcIconText
                                    text: Services.Audio.sourceMuted ? Services.Icons.micMute : Services.Icons.mic
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 14
                                    color: (srcFillBar.width > (srcIconText.x + 20)) ? Services.Theme.bgOnAccent : Services.Theme.textPrimary
                                    Behavior on color { ColorAnimation { duration: 80 } }
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    id: srcPctText
                                    text: Services.Audio.sourceMuted ? "MUTED" : (Math.round(Services.Audio.sourceVolume * 100) + "%")
                                    font.family: Services.Theme.fontMono
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: (srcFillBar.width > (parent.width - 40)) ? Services.Theme.bgOnAccent : Services.Theme.textPrimary
                                    Behavior on color { ColorAnimation { duration: 80 } }
                                }
                            }

                            MouseArea {
                                id: srcSliderMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onPressed: (mouse) => Services.Audio.setSourceVolume(Math.max(0, Math.min(1, mouse.x / width)))
                                onPositionChanged: (mouse) => {
                                    if (pressed) Services.Audio.setSourceVolume(Math.max(0, Math.min(1, mouse.x / width)))
                                }
                            }
                        }

                        // Mic Mute Toggle Button
                        Rectangle {
                            width: 38
                            height: 38
                            radius: Services.Theme.radiusMd
                            color: Services.Audio.sourceMuted 
                                ? Qt.rgba(Services.Theme.danger.r, Services.Theme.danger.g, Services.Theme.danger.b, 0.2) 
                                : (srcMuteMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.surfaceVariant)
                            border.color: Services.Audio.sourceMuted ? Services.Theme.danger : (srcMuteMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.borderSubtle)
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: Services.Audio.sourceMuted ? Services.Icons.micMute : Services.Icons.mic
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 14
                                color: Services.Audio.sourceMuted ? Services.Theme.danger : Services.Theme.textPrimary
                            }

                            MouseArea {
                                id: srcMuteMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.Audio.toggleSourceMute()
                            }
                        }
                    }

                    // Collapsible Source Selection List
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: srcListCol.implicitHeight + 8
                        radius: Services.Theme.radiusMd
                        color: Services.Theme.surfaceVariant
                        border.color: Services.Theme.borderSubtle
                        border.width: 1
                        visible: root.sourcesExpanded && (Services.Audio.sources?.length ?? 0) > 0
                        clip: true

                        ColumnLayout {
                            id: srcListCol
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: 4

                            Repeater {
                                model: Services.Audio.sources
                                delegate: Rectangle {
                                    id: srcRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 36
                                    radius: Services.Theme.radiusSm
                                    readonly property bool isCurrent: srcRow.modelData.isCurrent
                                    color: isCurrent 
                                        ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.22) 
                                        : (srcRowArea.containsMouse ? Services.Theme.bgHover : "transparent")
                                    border.color: isCurrent ? Services.Theme.accent : "transparent"
                                    border.width: 1

                                    MouseArea {
                                        id: srcRowArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            Services.Audio.setSource(srcRow.modelData.name)
                                            root.sourcesExpanded = false
                                        }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 8

                                        Text {
                                            text: Services.Icons.sourceIcon(srcRow.modelData.description)
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 13
                                            color: srcRow.isCurrent ? Services.Theme.accent : Services.Theme.textSecondary
                                        }

                                        Text {
                                            text: srcRow.modelData.nick || srcRow.modelData.description
                                            color: Services.Theme.textPrimary
                                            font.bold: srcRow.isCurrent
                                            font.pixelSize: 10
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        Text {
                                            visible: srcRow.isCurrent
                                            text: Services.Icons.check
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 11
                                            font.bold: true
                                            color: Services.Theme.accent
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── 5. App Volumes (Per-Media / Stream Volumes) ──
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: (Services.Audio.streams?.length ?? 0) > 0

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Services.Theme.borderSubtle
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "App Volumes"
                            font.bold: true
                            font.pixelSize: Services.Theme.fontSizeMd
                            color: Services.Theme.textPrimary
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            implicitHeight: 22
                            implicitWidth: streamMenuBtnRow.implicitWidth + 12
                            radius: 11
                            color: streamMenuArea.containsMouse 
                                ? Qt.lighter(Services.Theme.surfaceVariant, 1.2) 
                                : Services.Theme.surfaceVariant
                            border.color: root.streamsExpanded ? Services.Theme.accent : Services.Theme.borderSubtle
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }

                            RowLayout {
                                id: streamMenuBtnRow
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    text: "󰎈"
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 10
                                    color: Services.Theme.accent
                                }

                                Text {
                                    text: (Services.Audio.streams?.length ?? 0) + " Apps"
                                    color: Services.Theme.textSecondary
                                    font.pixelSize: 9
                                    font.bold: true
                                }

                                Text {
                                    text: root.streamsExpanded ? "▴" : "▾"
                                    color: Services.Theme.textDisabled
                                    font.pixelSize: 8
                                }
                            }

                            MouseArea {
                                id: streamMenuArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.streamsExpanded = !root.streamsExpanded
                            }
                        }
                    }

                    // Collapsible App Volume Sliders List
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: root.streamsExpanded

                        Repeater {
                            model: Services.Audio.streams
                            delegate: Rectangle {
                                id: streamItem
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 44
                                radius: Services.Theme.radiusMd
                                color: Services.Theme.surfaceVariant
                                border.color: Services.Theme.borderSubtle
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 8

                                    // App Icon / Tag
                                    Rectangle {
                                        width: 28; height: 28; radius: 6
                                        color: Services.Theme.surface
                                        Text {
                                            anchors.centerIn: parent
                                            text: Services.Icons.playerIcon(streamItem.modelData.name || streamItem.modelData.binary)
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 13
                                            color: Services.Theme.accent
                                        }
                                    }

                                    // App Name & Slider
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: streamItem.modelData.name || "App"
                                                color: Services.Theme.textPrimary
                                                font.pixelSize: 10
                                                font.bold: true
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: streamItem.modelData.muted ? "Muted" : (Math.round(streamItem.modelData.volume * 100) + "%")
                                                color: streamItem.modelData.muted ? Services.Theme.danger : Services.Theme.textSecondary
                                                font.pixelSize: 9
                                                font.family: Services.Theme.fontMono
                                                font.bold: true
                                            }
                                        }

                                        // Mini Slider Bar
                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: 12
                                            radius: 6
                                            color: Services.Theme.surface
                                            clip: true

                                            Rectangle {
                                                height: parent.height
                                                radius: parent.radius
                                                color: streamItem.modelData.muted ? Services.Theme.textDisabled : Services.Theme.accent
                                                width: Math.max(12, Math.min(parent.width, (streamItem.modelData.muted ? 0 : streamItem.modelData.volume) * parent.width))
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                anchors.margins: -4
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onPressed: (mouse) => Services.Audio.setStreamVolume(streamItem.modelData.index, Math.max(0, Math.min(1, mouse.x / width)))
                                                onPositionChanged: (mouse) => {
                                                    if (pressed) Services.Audio.setStreamVolume(streamItem.modelData.index, Math.max(0, Math.min(1, mouse.x / width)))
                                                }
                                            }
                                        }
                                    }

                                    // Mute Toggle Button
                                    Rectangle {
                                        width: 26; height: 26; radius: 6
                                        color: streamItem.modelData.muted 
                                            ? Qt.rgba(Services.Theme.danger.r, Services.Theme.danger.g, Services.Theme.danger.b, 0.2) 
                                            : (stMuteMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.surface)
                                        border.color: streamItem.modelData.muted ? Services.Theme.danger : Services.Theme.borderSubtle
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: streamItem.modelData.muted ? Services.Icons.volOff : Services.Icons.speaker
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 11
                                            color: streamItem.modelData.muted ? Services.Theme.danger : Services.Theme.textSecondary
                                        }

                                        MouseArea {
                                            id: stMuteMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Services.Audio.toggleStreamMute(streamItem.modelData.index)
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
}
