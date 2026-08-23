import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../services" as Services

PanelWindow {
    id: rootWindow
    visible: false

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.namespace: "quickshell:welcome"
    exclusiveZone: 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    property string overlayId: "welcome"
    property bool isOpen: false
    property int currentStep: 0
    readonly property int totalSteps: 6

    Component.onCompleted: {
        Services.OverlayManager.register(rootWindow)
    }

    Connections {
        target: Services.Config
        function onInitialLoadFinished(isFirstRun) {
            if (isFirstRun) {
                rootWindow.show()
            }
        }
    }

    function show() {
        Services.OverlayManager.closeAllExcept(rootWindow)
        hideTimer.stop()
        currentStep = 0
        visible = true
        isOpen = true
        keyFocus.forceActiveFocus()
    }

    function hide() {
        if (!isOpen) return
        isOpen = false
        if (Services.Config && !Services.Config.firstRunCompleted) {
            Services.Config.setFirstRunCompleted(true)
        }
        hideTimer.restart()
    }

    function toggle() { isOpen ? hide() : show() }

    function finishSetup() {
        if (Services.Config) {
            Services.Config.setFirstRunCompleted(true)
            Services.Config.saveConfig()
        }
        if (Services.SoundFeedback) {
            Services.SoundFeedback.playComplete()
        }
        hide()
    }

    Timer {
        id: hideTimer
        interval: 220
        onTriggered: rootWindow.visible = false
    }

    Item {
        id: keyFocus
        focus: rootWindow.isOpen
        Keys.onEscapePressed: rootWindow.hide()
        Keys.onRightPressed: if (rootWindow.currentStep < rootWindow.totalSteps - 1) rootWindow.currentStep++
        Keys.onLeftPressed:  if (rootWindow.currentStep > 0) rootWindow.currentStep--
    }

    // Backdrop
    MouseArea {
        anchors.fill: parent
        onClicked: rootWindow.hide()

        // ── Main Wizard Container Card ───────────────────────────────────────
        Rectangle {
            id: wizardCard
            anchors.centerIn: parent
            width: 620
            height: 480
            radius: Services.Theme.radiusLg
            color: Services.Theme.surface
            border.color: Services.Theme.border
            border.width: 1
            clip: true

            opacity: rootWindow.isOpen ? 1 : 0
            scale: rootWindow.isOpen ? 1 : 0.95
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent; onClicked: {} }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 14

                // Top Header Row (Logo + Title + Step indicator dots)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        width: 28; height: 28; radius: 8
                        color: Services.Theme.accent
                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.wand
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 13
                            color: Services.Theme.bgOnAccent
                        }
                    }

                    ColumnLayout {
                        spacing: 0
                        Text {
                            text: "Welcome Setup"
                            font.family: Services.Theme.fontDisplay
                            font.pixelSize: Services.Theme.fontSizeXl
                            font.bold: true
                            color: Services.Theme.textPrimary
                        }
                        Text {
                            text: "Step " + (rootWindow.currentStep + 1) + " of " + rootWindow.totalSteps
                            font.pixelSize: Services.Theme.fontSizeXs
                            color: Services.Theme.textSecondary
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Step Dots Indicator
                    RowLayout {
                        spacing: 6
                        Repeater {
                            model: rootWindow.totalSteps
                            delegate: Rectangle {
                                required property int index
                                width: (index === rootWindow.currentStep) ? 18 : 6
                                height: 6
                                radius: 3
                                color: (index === rootWindow.currentStep) 
                                    ? Services.Theme.accent 
                                    : ((index < rootWindow.currentStep) ? Services.Theme.borderHighlight : Services.Theme.border)
                                Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                            }
                        }
                    }

                    // Close Button
                    Rectangle {
                        width: 24; height: 24; radius: 12
                        color: closeMouse.containsMouse ? Services.Theme.danger : Services.Theme.surfaceVariant
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.close
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 10
                            color: closeMouse.containsMouse ? Services.Theme.white : Services.Theme.textSecondary
                        }

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: rootWindow.hide()
                        }
                    }
                }

                // Divider
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Services.Theme.border
                    opacity: 0.6
                }

                // ═════════════════════════════════════════════════════════════
                // ── STEP PAGES VIEWPORT ──────────────────────────────────────
                // ═════════════════════════════════════════════════════════════
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    // ── PAGE 0: WELCOME & OVERVIEW ───────────────────────────
                    ColumnLayout {
                        anchors.fill: parent
                        visible: rootWindow.currentStep === 0
                        spacing: 14

                        Item { Layout.fillHeight: true }

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 68; height: 68; radius: 20
                            color: Services.Theme.surfaceVariant
                            border.color: Services.Theme.borderHighlight
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: Services.OsInfo.logoGlyph || Services.Icons.sparkles
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 36
                                color: Services.Theme.accent
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Welcome to Quickshell"
                            font.family: Services.Theme.fontDisplay
                            font.pixelSize: Services.Theme.fontSize5xl
                            font.bold: true
                            color: Services.Theme.textPrimary
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.maximumWidth: 460
                            text: "A fluid, modern, customizable Wayland desktop experience. Let's personalize your setup with your preferred themes and options."
                            font.pixelSize: Services.Theme.fontSizeMd
                            color: Services.Theme.textSecondary
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }

                        // Feature Highlights Pill Row
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 10

                            Rectangle {
                                height: 28; radius: 14
                                implicitWidth: f1Row.implicitWidth + 16
                                color: Services.Theme.surfaceVariant
                                RowLayout {
                                    id: f1Row
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text { text: Services.Icons.palette; font.family: Services.Theme.fontSymbols; font.pixelSize: 11; color: Services.Theme.accent }
                                    Text { text: "Light & Dark Schemes"; font.pixelSize: Services.Theme.fontSizeXs; color: Services.Theme.textPrimary }
                                }
                            }

                            Rectangle {
                                height: 28; radius: 14
                                implicitWidth: f2Row.implicitWidth + 16
                                color: Services.Theme.surfaceVariant
                                RowLayout {
                                    id: f2Row
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text { text: Services.Icons.controlcenter; font.family: Services.Theme.fontSymbols; font.pixelSize: 11; color: Services.Theme.accent }
                                    Text { text: "Dynamic Island HUD"; font.pixelSize: Services.Theme.fontSizeXs; color: Services.Theme.textPrimary }
                                }
                            }

                            Rectangle {
                                height: 28; radius: 14
                                implicitWidth: f3Row.implicitWidth + 16
                                color: Services.Theme.surfaceVariant
                                RowLayout {
                                    id: f3Row
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text { text: Services.Icons.undo; font.family: Services.Theme.fontSymbols; font.pixelSize: 11; color: Services.Theme.accent }
                                    Text { text: "Safe Backup & Reset"; font.pixelSize: Services.Theme.fontSizeXs; color: Services.Theme.textPrimary }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }

                    // ── PAGE 1: THEME & COLOR SCHEME ─────────────────────────
                    ColumnLayout {
                        anchors.fill: parent
                        visible: rootWindow.currentStep === 1
                        spacing: 12

                        ColumnLayout {
                            spacing: 2
                            Text { text: "Choose Your Theme Mode"; font.pixelSize: Services.Theme.fontSize3xl; font.bold: true; color: Services.Theme.textPrimary }
                            Text { text: "Select between Dark and Light mode. Colors adapt in real-time."; font.pixelSize: Services.Theme.fontSizeSm; color: Services.Theme.textSecondary }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 14

                            // Dark Mode Card
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: Services.Theme.radiusMd
                                color: (Services.Config && Services.Config.themeMode === "dark") ? Qt.rgba(0.2, 0.2, 0.2, 0.9) : Services.Theme.bgElevated
                                border.color: (Services.Config && Services.Config.themeMode === "dark") ? Services.Theme.accent : Services.Theme.border
                                border.width: (Services.Config && Services.Config.themeMode === "dark") ? 2 : 1

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 10

                                    Rectangle {
                                        Layout.alignment: Qt.AlignHCenter
                                        width: 44; height: 44; radius: 22
                                        color: "#18181b"
                                        Text { anchors.centerIn: parent; text: Services.Icons.moon; font.family: Services.Theme.fontSymbols; font.pixelSize: 20; color: "#e8e8e8" }
                                    }

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: "Dark Mode"
                                        font.pixelSize: Services.Theme.fontSizeLg
                                        font.bold: true
                                        color: "#ffffff"
                                    }

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: "Sleek obsidian with soft contrast for low-light environments."
                                        font.pixelSize: Services.Theme.fontSizeXs
                                        color: "#a1a1aa"
                                        horizontalAlignment: Text.AlignHCenter
                                        wrapMode: Text.WordWrap
                                        Layout.maximumWidth: 200
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (Services.Config) Services.Config.setThemeMode("dark")
                                }
                            }

                            // Light Mode Card
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: Services.Theme.radiusMd
                                color: (Services.Config && Services.Config.themeMode === "light") ? Qt.rgba(0.95, 0.95, 0.98, 0.95) : Services.Theme.bgElevated
                                border.color: (Services.Config && Services.Config.themeMode === "light") ? Services.Theme.accent : Services.Theme.border
                                border.width: (Services.Config && Services.Config.themeMode === "light") ? 2 : 1

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 10

                                    Rectangle {
                                        Layout.alignment: Qt.AlignHCenter
                                        width: 44; height: 44; radius: 22
                                        color: "#ffffff"
                                        border.color: "#e4e4e7"
                                        border.width: 1
                                        Text { anchors.centerIn: parent; text: Services.Icons.sun; font.family: Services.Theme.fontSymbols; font.pixelSize: 20; color: "#f59e0b" }
                                    }

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: "Light Mode"
                                        font.pixelSize: Services.Theme.fontSizeLg
                                        font.bold: true
                                        color: "#18181b"
                                    }

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: "Frosted clean surfaces with crisp text for bright daylight."
                                        font.pixelSize: Services.Theme.fontSizeXs
                                        color: "#71717a"
                                        horizontalAlignment: Text.AlignHCenter
                                        wrapMode: Text.WordWrap
                                        Layout.maximumWidth: 200
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (Services.Config) Services.Config.setThemeMode("light")
                                }
                            }
                        }
                    }

                    // ── PAGE 2: ACCENT COLOR ─────────────────────────────────
                    ColumnLayout {
                        anchors.fill: parent
                        visible: rootWindow.currentStep === 2
                        spacing: 14

                        ColumnLayout {
                            spacing: 2
                            Text { text: "Select Accent Color"; font.pixelSize: Services.Theme.fontSize3xl; font.bold: true; color: Services.Theme.textPrimary }
                            Text { text: "This color highlights active icons, sliders, buttons, and HUD indicators."; font.pixelSize: Services.Theme.fontSizeSm; color: Services.Theme.textSecondary }
                        }

                        // Grid of Accent Color Pills
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 4
                            rowSpacing: 10
                            columnSpacing: 10

                            Repeater {
                                model: Services.Config ? Services.Config.accentPresets : []
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    height: 54
                                    radius: Services.Theme.radiusSm
                                    readonly property bool isCur: Services.Config && Services.Config.accentName === modelData.name

                                    color: isCur ? Services.Theme.surfaceVariant : Services.Theme.bgElevated
                                    border.color: isCur ? Services.Theme.accent : Services.Theme.border
                                    border.width: isCur ? 2 : 1

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 8

                                        Rectangle {
                                            width: 24; height: 24; radius: 12
                                            color: (Services.Config && Services.Config.themeMode === "light") ? modelData.lightHex : modelData.darkHex
                                            border.color: Services.Theme.border
                                            border.width: 1

                                            Text {
                                                anchors.centerIn: parent
                                                text: Services.Icons.check
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 10
                                                color: Services.Theme.bgOnAccent
                                                visible: isCur
                                            }
                                        }

                                        Text {
                                            text: modelData.name
                                            font.pixelSize: Services.Theme.fontSizeSm
                                            font.bold: isCur
                                            color: Services.Theme.textPrimary
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (Services.Config) {
                                                const hex = (Services.Config.themeMode === "light") ? modelData.lightHex : modelData.darkHex
                                                Services.Config.setAccent(hex, modelData.name, modelData.isMatugen)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }

                    // ── PAGE 3: BAR & DYNAMIC ISLAND ─────────────────────────
                    ColumnLayout {
                        anchors.fill: parent
                        visible: rootWindow.currentStep === 3
                        spacing: 12

                        ColumnLayout {
                            spacing: 2
                            Text { text: "Top Bar & Dynamic Island"; font.pixelSize: Services.Theme.fontSize3xl; font.bold: true; color: Services.Theme.textPrimary }
                            Text { text: "Configure how time and notifications are presented in your bar."; font.pixelSize: Services.Theme.fontSizeSm; color: Services.Theme.textSecondary }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: bSetCol.implicitHeight + 20
                            radius: Services.Theme.radiusMd
                            color: Services.Theme.surfaceVariant
                            border.color: Services.Theme.border
                            border.width: 1

                            ColumnLayout {
                                id: bSetCol
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 14

                                // 24H Toggle
                                RowLayout {
                                    Layout.fillWidth: true
                                    ColumnLayout {
                                        spacing: 2
                                        Text { text: "24-Hour Time Format"; font.pixelSize: Services.Theme.fontSizeMd; font.bold: true; color: Services.Theme.textPrimary }
                                        Text { text: "Display time as 14:30 instead of 02:30 PM"; font.pixelSize: Services.Theme.fontSizeXs; color: Services.Theme.textSecondary }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        width: 44; height: 24; radius: 12
                                        color: (Services.Config && Services.Config.clock24h) ? Services.Theme.accent : Services.Theme.bgElevated
                                        border.color: Services.Theme.border
                                        border.width: 1

                                        Rectangle {
                                            width: 18; height: 18; radius: 9
                                            y: 2
                                            x: (Services.Config && Services.Config.clock24h) ? 23 : 3
                                            color: (Services.Config && Services.Config.clock24h) ? Services.Theme.bgOnAccent : Services.Theme.textSecondary
                                            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: if (Services.Config) Services.Config.setClock24h(!Services.Config.clock24h)
                                        }
                                    }
                                }

                                // Show Seconds Toggle
                                RowLayout {
                                    Layout.fillWidth: true
                                    ColumnLayout {
                                        spacing: 2
                                        Text { text: "Show Seconds"; font.pixelSize: Services.Theme.fontSizeMd; font.bold: true; color: Services.Theme.textPrimary }
                                        Text { text: "Display real-time seconds ticker"; font.pixelSize: Services.Theme.fontSizeXs; color: Services.Theme.textSecondary }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        width: 44; height: 24; radius: 12
                                        color: (Services.Config && Services.Config.clockShowSeconds) ? Services.Theme.accent : Services.Theme.bgElevated
                                        border.color: Services.Theme.border
                                        border.width: 1

                                        Rectangle {
                                            width: 18; height: 18; radius: 9
                                            y: 2
                                            x: (Services.Config && Services.Config.clockShowSeconds) ? 23 : 3
                                            color: (Services.Config && Services.Config.clockShowSeconds) ? Services.Theme.bgOnAccent : Services.Theme.textSecondary
                                            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: if (Services.Config) Services.Config.setClockShowSeconds(!Services.Config.clockShowSeconds)
                                        }
                                    }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }

                    // ── PAGE 4: SOUND & NOTIFICATIONS ────────────────────────
                    ColumnLayout {
                        anchors.fill: parent
                        visible: rootWindow.currentStep === 4
                        spacing: 12

                        ColumnLayout {
                            spacing: 2
                            Text { text: "Sound & Notification Alerts"; font.pixelSize: Services.Theme.fontSize3xl; font.bold: true; color: Services.Theme.textPrimary }
                            Text { text: "Control audio feedback and popup notifications."; font.pixelSize: Services.Theme.fontSizeSm; color: Services.Theme.textSecondary }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: sSetCol.implicitHeight + 20
                            radius: Services.Theme.radiusMd
                            color: Services.Theme.surfaceVariant
                            border.color: Services.Theme.border
                            border.width: 1

                            ColumnLayout {
                                id: sSetCol
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 14

                                // Sound Feedback Toggle
                                RowLayout {
                                    Layout.fillWidth: true
                                    ColumnLayout {
                                        spacing: 2
                                        Text { text: "UI Sound Feedback"; font.pixelSize: Services.Theme.fontSizeMd; font.bold: true; color: Services.Theme.textPrimary }
                                        Text { text: "Play feedback audio on volume changes and system events"; font.pixelSize: Services.Theme.fontSizeXs; color: Services.Theme.textSecondary }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        width: 44; height: 24; radius: 12
                                        color: (Services.Config && Services.Config.soundFeedback) ? Services.Theme.accent : Services.Theme.bgElevated
                                        border.color: Services.Theme.border
                                        border.width: 1

                                        Rectangle {
                                            width: 18; height: 18; radius: 9
                                            y: 2
                                            x: (Services.Config && Services.Config.soundFeedback) ? 23 : 3
                                            color: (Services.Config && Services.Config.soundFeedback) ? Services.Theme.bgOnAccent : Services.Theme.textSecondary
                                            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: if (Services.Config) Services.Config.setSoundFeedback(!Services.Config.soundFeedback)
                                        }
                                    }
                                }

                                // Play Test Sound
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 34
                                    radius: Services.Theme.radiusSm
                                    color: Services.Theme.bgElevated
                                    border.color: Services.Theme.border
                                    border.width: 1

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Text { text: Services.Icons.speaker; font.family: Services.Theme.fontSymbols; font.pixelSize: 11; color: Services.Theme.accent }
                                        Text { text: "Audition Notification Chime"; font.pixelSize: Services.Theme.fontSizeSm; color: Services.Theme.textPrimary }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (Services.SoundFeedback) Services.SoundFeedback.playNotification()
                                        }
                                    }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }

                    // ── PAGE 5: FINISH / ALL SET! ────────────────────────────
                    ColumnLayout {
                        anchors.fill: parent
                        visible: rootWindow.currentStep === 5
                        spacing: 14

                        Item { Layout.fillHeight: true }

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 60; height: 60; radius: 30
                            color: Qt.rgba(0.2, 0.8, 0.4, 0.2)
                            border.color: Services.Theme.success
                            border.width: 2

                            Text {
                                anchors.centerIn: parent
                                text: Services.Icons.check
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 26
                                color: Services.Theme.success
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "You're All Set!"
                            font.family: Services.Theme.fontDisplay
                            font.pixelSize: Services.Theme.fontSize5xl
                            font.bold: true
                            color: Services.Theme.textPrimary
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.maximumWidth: 460
                            text: "Your preferences have been saved and applied. You can always change your settings later using Preferences or the Control Center."
                            font.pixelSize: Services.Theme.fontSizeMd
                            color: Services.Theme.textSecondary
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }

                        // Shortcuts Reminder Box
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 380
                            implicitHeight: sccCol.implicitHeight + 16
                            radius: Services.Theme.radiusSm
                            color: Services.Theme.surfaceVariant
                            border.color: Services.Theme.border
                            border.width: 1

                            ColumnLayout {
                                id: sccCol
                                anchors.centerIn: parent
                                spacing: 4
                                Text { text: "Quick Keyboard Shortcuts:"; font.bold: true; font.pixelSize: Services.Theme.fontSizeXs; color: Services.Theme.accent }
                                Text { text: "• Super + D  : App Launcher"; font.pixelSize: Services.Theme.fontSizeXs; color: Services.Theme.textPrimary }
                                Text { text: "• Super + A  : System Dashboard"; font.pixelSize: Services.Theme.fontSizeXs; color: Services.Theme.textPrimary }
                                Text { text: "• Super + C  : Control Center"; font.pixelSize: Services.Theme.fontSizeXs; color: Services.Theme.textPrimary }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }

                // ═════════════════════════════════════════════════════════════
                // ── BOTTOM NAVIGATION BUTTONS ────────────────────────────────
                // ═════════════════════════════════════════════════════════════
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    // Back Button
                    Rectangle {
                        width: 90; height: 36
                        radius: Services.Theme.radiusSm
                        visible: rootWindow.currentStep > 0
                        color: backMouse.containsMouse ? Services.Theme.surfaceVariant : Services.Theme.bgElevated
                        border.color: Services.Theme.border
                        border.width: 1

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 4
                            Text { text: Services.Icons.chevLeft; font.family: Services.Theme.fontSymbols; font.pixelSize: 10; color: Services.Theme.textPrimary }
                            Text { text: "Back"; font.pixelSize: Services.Theme.fontSizeMd; color: Services.Theme.textPrimary }
                        }

                        MouseArea {
                            id: backMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (rootWindow.currentStep > 0) rootWindow.currentStep--
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Next / Finish Button
                    Rectangle {
                        height: 36
                        implicitWidth: nxtRow.implicitWidth + 24
                        radius: Services.Theme.radiusSm
                        color: Services.Theme.accent

                        RowLayout {
                            id: nxtRow
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: (rootWindow.currentStep === rootWindow.totalSteps - 1) ? "Get Started" : "Next"
                                font.pixelSize: Services.Theme.fontSizeMd
                                font.bold: true
                                color: Services.Theme.bgOnAccent
                            }

                            Text {
                                text: (rootWindow.currentStep === rootWindow.totalSteps - 1) ? Services.Icons.check : Services.Icons.chevRight
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 10
                                color: Services.Theme.bgOnAccent
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (rootWindow.currentStep < rootWindow.totalSteps - 1) {
                                    rootWindow.currentStep++
                                } else {
                                    rootWindow.finishSetup()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
