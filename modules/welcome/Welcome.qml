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
    readonly property int totalSteps: 7

    // Font tab active index for Step 3: 0=UI Font, 1=Monospace, 2=Display Font
    property int activeFontTab: 0

    // Staged state for fonts (applied on Next when leaving Typography step)
    property string wizardSelectedFontFamily: ""
    property string wizardSelectedFontMono: ""
    property string wizardSelectedFontDisplay: ""
    property bool wizardThemeStageInited: false

    readonly property var stepTitles: [
        "Welcome",
        "Appearance",
        "Accent Color",
        "Typography",
        "Status Bar",
        "Audio & Alerts",
        "Complete"
    ]

    onCurrentStepChanged: {
        // Initialize staged values when entering Typography step
        if (currentStep === 3 && !wizardThemeStageInited) {
            wizardSelectedFontFamily = Services.Config ? Services.Config.fontFamily : ""
            wizardSelectedFontMono = Services.Config ? Services.Config.fontMono : ""
            wizardSelectedFontDisplay = Services.Config ? Services.Config.fontDisplay : ""
            wizardThemeStageInited = true
        }
    }

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
        if (Services.OverlayManager) Services.OverlayManager.wizardOpen = true
        hideTimer.stop()
        currentStep = 0
        activeFontTab = 0
        wizardThemeStageInited = false
        wizardSelectedFontFamily = ""
        wizardSelectedFontMono = ""
        wizardSelectedFontDisplay = ""
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
        isOpen = false
        hideTimer.restart()
    }

    Timer {
        id: hideTimer
        interval: 280
        onTriggered: {
            rootWindow.visible = false
            if (Services.OverlayManager) {
                Services.OverlayManager.wizardOpen = false
            }
        }
    }

    Item {
        id: keyFocus
        focus: rootWindow.isOpen
        Keys.onEscapePressed: {
            if (Services.Config && Services.Config.firstRunCompleted) {
                rootWindow.hide()
            }
        }
        Keys.onRightPressed: {
            if (rootWindow.currentStep < rootWindow.totalSteps - 1) {
                applyCurrentStaged()
                rootWindow.currentStep++
            }
        }
        Keys.onLeftPressed: {
            if (rootWindow.currentStep > 0) {
                rootWindow.currentStep--
            }
        }
    }

    function applyCurrentStaged() {
        // Apply fonts when leaving Typography step (step 3)
        if (rootWindow.currentStep === 3) {
            if (Services.Config) {
                if (rootWindow.wizardSelectedFontFamily && rootWindow.wizardSelectedFontFamily !== Services.Config.fontFamily)
                    Services.Config.setFontFamily(rootWindow.wizardSelectedFontFamily)
                if (rootWindow.wizardSelectedFontMono && rootWindow.wizardSelectedFontMono !== Services.Config.fontMono)
                    Services.Config.setFontMono(rootWindow.wizardSelectedFontMono)
                if (rootWindow.wizardSelectedFontDisplay && rootWindow.wizardSelectedFontDisplay !== Services.Config.fontDisplay)
                    Services.Config.setFontDisplay(rootWindow.wizardSelectedFontDisplay)
            }
        }
    }

    // ── Backdrop Dimming ──────────────────────────────────────────────────────
    Rectangle {
        id: backdropDim
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.58)
        opacity: rootWindow.isOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    }

    // Backdrop click area
    MouseArea {
        anchors.fill: parent
        onClicked: {
            // Only allow clicking backdrop to dismiss if not first-run
            if (Services.Config && Services.Config.firstRunCompleted) {
                rootWindow.hide()
            }
        }

        // ── Main Wizard Container Card (760 x 540) ───────────────────────────
        Rectangle {
            id: wizardCard
            anchors.centerIn: parent
            width: 760
            height: 540
            radius: 20
            color: Services.Theme.surface
            border.color: Qt.rgba(1, 1, 1, 0.12)
            border.width: 1
            clip: true

            opacity: rootWindow.isOpen ? 1 : 0
            scale: rootWindow.isOpen ? 1 : 0.95
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 270; easing.type: Easing.OutCubic } }

            // Swallow clicks inside the card
            MouseArea { anchors.fill: parent; onClicked: {} }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 22
                anchors.topMargin: 20
                spacing: 16

                // ═════════════════════════════════════════════════════════════
                // ── HEADER ROW: Brand Badge + Step Title + Step Badge + Skip ─
                // ═════════════════════════════════════════════════════════════
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    // Brand Icon Pill
                    Rectangle {
                        width: 32; height: 32; radius: 10
                        color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.18)
                        border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.4)
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.sparkles || "󰌽"
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 15
                            color: Services.Theme.accent
                        }
                    }

                    ColumnLayout {
                        spacing: 1
                        Text {
                            text: "Nimbush Setup"
                            font.family: Services.Theme.fontDisplay
                            font.pixelSize: 14
                            font.bold: true
                            color: Services.Theme.textPrimary
                        }
                        Text {
                            text: rootWindow.stepTitles[rootWindow.currentStep] || ""
                            font.pixelSize: 11
                            color: Services.Theme.accent
                            font.bold: true
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Clean Integrated Step Count Badge & Progress Bar
                    Rectangle {
                        height: 26
                        implicitWidth: stepBadgeRow.implicitWidth + 20
                        radius: 13
                        color: Services.Theme.surfaceVariant
                        border.color: Services.Theme.border
                        border.width: 1

                        RowLayout {
                            id: stepBadgeRow
                            anchors.centerIn: parent
                            spacing: 8

                            // Mini Progress Track
                            Rectangle {
                                width: 36
                                height: 4
                                radius: 2
                                color: Qt.rgba(1, 1, 1, 0.12)

                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    anchors.left: parent.left
                                    width: Math.max(4, parent.width * ((rootWindow.currentStep + 1) / rootWindow.totalSteps))
                                    radius: 2
                                    color: Services.Theme.accent
                                    Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                }
                            }

                            Text {
                                text: "Step " + (rootWindow.currentStep + 1) + " of " + rootWindow.totalSteps
                                font.pixelSize: 11
                                font.bold: true
                                color: Services.Theme.textPrimary
                            }
                        }
                    }

                    // Skip button (visible on steps 0-5)
                    Rectangle {
                        visible: rootWindow.currentStep < rootWindow.totalSteps - 1
                        height: 26
                        implicitWidth: skipTxt.implicitWidth + 18
                        radius: 13
                        color: skipMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                        border.color: skipMouse.containsMouse ? Services.Theme.border : "transparent"
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            id: skipTxt
                            anchors.centerIn: parent
                            text: "Skip"
                            font.pixelSize: 11
                            font.bold: true
                            color: skipMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary
                        }

                        MouseArea {
                            id: skipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: rootWindow.hide()
                        }
                    }

                    // Close Button
                    Rectangle {
                        width: 26; height: 26; radius: 13
                        color: closeMouse.containsMouse ? Services.Theme.danger : Services.Theme.surfaceVariant
                        border.color: Services.Theme.border
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.close || "✕"
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 11
                            color: closeMouse.containsMouse ? "#ffffff" : Services.Theme.textSecondary
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

                // Divider line
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Services.Theme.border
                    opacity: 0.7
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
                        spacing: 16

                        Item { Layout.fillHeight: true }

                        // Glowing Hero Badge
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 76; height: 76; radius: 24
                            color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.18)
                            border.color: Services.Theme.accent
                            border.width: 2

                            Text {
                                anchors.centerIn: parent
                                text: Services.OsInfo.logoGlyph || Services.Icons.sparkles || "󰌽"
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 36
                                color: Services.Theme.accent
                            }
                        }

                        ColumnLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 4
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Welcome to Nimbush"
                                font.family: Services.Theme.fontDisplay
                                font.pixelSize: 26
                                font.bold: true
                                color: Services.Theme.textPrimary
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.maximumWidth: 540
                                text: "A fluid, minimalist, and deeply customizable Wayland desktop experience. Let's personalize your themes, fonts, and appearance in a few simple steps."
                                font.pixelSize: Services.Theme.fontSizeSm
                                color: Services.Theme.textSecondary
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                            }
                        }

                        // 4 Feature Highlight Bento Chips (2x2 Grid)
                        GridLayout {
                            Layout.alignment: Qt.AlignHCenter
                            columns: 2
                            columnSpacing: 12
                            rowSpacing: 12

                            // Bento 1: Adaptive Theming
                            Rectangle {
                                width: 270; height: 60; radius: Services.Theme.radiusSm
                                color: Services.Theme.surfaceVariant
                                border.color: Services.Theme.border; border.width: 1
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: 10; spacing: 10
                                    Rectangle {
                                        width: 34; height: 34; radius: 8
                                        color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.16)
                                        Text { anchors.centerIn: parent; text: Services.Icons.palette || "󰮄"; font.family: Services.Theme.fontSymbols; font.pixelSize: 15; color: Services.Theme.accent }
                                    }
                                    ColumnLayout {
                                        spacing: 1
                                        Text { text: "Adaptive Theming"; font.bold: true; font.pixelSize: Services.Theme.fontSizeSm; color: Services.Theme.textPrimary }
                                        Text { text: "Dark/Light & Matugen palettes"; font.pixelSize: 11; color: Services.Theme.textSecondary; elide: Text.ElideRight; Layout.maximumWidth: 200 }
                                    }
                                }
                            }

                            // Bento 2: Shell Typography
                            Rectangle {
                                width: 270; height: 60; radius: Services.Theme.radiusSm
                                color: Services.Theme.surfaceVariant
                                border.color: Services.Theme.border; border.width: 1
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: 10; spacing: 10
                                    Rectangle {
                                        width: 34; height: 34; radius: 8
                                        color: Qt.rgba(0.8, 0.4, 1.0, 0.16)
                                        Text { anchors.centerIn: parent; text: Services.Icons.font || "󰛄"; font.family: Services.Theme.fontSymbols; font.pixelSize: 15; color: "#c084fc" }
                                    }
                                    ColumnLayout {
                                        spacing: 1
                                        Text { text: "Shell Typography"; font.bold: true; font.pixelSize: Services.Theme.fontSizeSm; color: Services.Theme.textPrimary }
                                        Text { text: "UI, Mono, & Display fonts"; font.pixelSize: 11; color: Services.Theme.textSecondary; elide: Text.ElideRight; Layout.maximumWidth: 200 }
                                    }
                                }
                            }

                            // Bento 3: Status Bar & Island
                            Rectangle {
                                width: 270; height: 60; radius: Services.Theme.radiusSm
                                color: Services.Theme.surfaceVariant
                                border.color: Services.Theme.border; border.width: 1
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: 10; spacing: 10
                                    Rectangle {
                                        width: 34; height: 34; radius: 8
                                        color: Qt.rgba(0.2, 0.6, 1.0, 0.16)
                                        Text { anchors.centerIn: parent; text: Services.Icons.clock || "󱑂"; font.family: Services.Theme.fontSymbols; font.pixelSize: 15; color: "#38bdf8" }
                                    }
                                    ColumnLayout {
                                        spacing: 1
                                        Text { text: "Status Bar & Island"; font.bold: true; font.pixelSize: Services.Theme.fontSizeSm; color: Services.Theme.textPrimary }
                                        Text { text: "Clock formats & status pills"; font.pixelSize: 11; color: Services.Theme.textSecondary; elide: Text.ElideRight; Layout.maximumWidth: 200 }
                                    }
                                }
                            }

                            // Bento 4: Dynamic Island & Audio
                            Rectangle {
                                width: 270; height: 60; radius: Services.Theme.radiusSm
                                color: Services.Theme.surfaceVariant
                                border.color: Services.Theme.border; border.width: 1
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: 10; spacing: 10
                                    Rectangle {
                                        width: 34; height: 34; radius: 8
                                        color: Qt.rgba(0.2, 0.8, 0.5, 0.16)
                                        Text { anchors.centerIn: parent; text: Services.Icons.speaker || "󰕾"; font.family: Services.Theme.fontSymbols; font.pixelSize: 15; color: "#34d399" }
                                    }
                                    ColumnLayout {
                                        spacing: 1
                                        Text { text: "Audio Feedback"; font.bold: true; font.pixelSize: Services.Theme.fontSizeSm; color: Services.Theme.textPrimary }
                                        Text { text: "Tactile chimes & sound effects"; font.pixelSize: 11; color: Services.Theme.textSecondary; elide: Text.ElideRight; Layout.maximumWidth: 200 }
                                    }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }

                    // ── PAGE 1: THEME & COLOR SCHEME ─────────────────────────
                    ColumnLayout {
                        anchors.fill: parent
                        visible: rootWindow.currentStep === 1
                        spacing: 14

                        ColumnLayout {
                            spacing: 2
                            Text { text: "Choose Your Appearance"; font.pixelSize: 22; font.bold: true; color: Services.Theme.textPrimary }
                            Text { text: "Select your preferred base mode. The shell and applications adapt in real-time."; font.pixelSize: Services.Theme.fontSizeSm; color: Services.Theme.textSecondary }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 16

                            // Dark Mode Card with Visual Mockup
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: Services.Theme.radiusMd
                                readonly property bool isSel: Services.Config && Services.Config.themeMode === "dark"
                                color: isSel ? Qt.rgba(0.12, 0.12, 0.16, 0.95) : Services.Theme.bgElevated
                                border.color: isSel ? Services.Theme.accent : Services.Theme.border
                                border.width: isSel ? 2 : 1
                                Behavior on border.color { ColorAnimation { duration: 180 } }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    spacing: 10

                                    // Mini Desktop Mockup (Dark)
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 120
                                        radius: 10
                                        color: "#0a0a0d"
                                        border.color: "#27272a"
                                        border.width: 1
                                        clip: true

                                        // Mini Top Bar
                                        Rectangle {
                                            anchors.top: parent.top
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            height: 18
                                            color: "#18181b"
                                            RowLayout {
                                                anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                                                Rectangle { width: 8; height: 8; radius: 4; color: Services.Theme.accent }
                                                Item { Layout.fillWidth: true }
                                                Rectangle { width: 36; height: 6; radius: 3; color: "#27272a" }
                                                Item { Layout.fillWidth: true }
                                                Rectangle { width: 14; height: 6; radius: 3; color: "#3f3f46" }
                                            }
                                        }

                                        // Mini Window
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 190; height: 62
                                            radius: 6
                                            color: "#1c1c21"
                                            border.color: "#3f3f46"
                                            border.width: 1
                                            RowLayout {
                                                anchors.fill: parent; anchors.margins: 6; spacing: 6
                                                Rectangle { width: 38; Layout.fillHeight: true; radius: 4; color: "#27272a" }
                                                ColumnLayout {
                                                    Layout.fillWidth: true; spacing: 4
                                                    Rectangle { width: 70; height: 6; radius: 3; color: Services.Theme.accent }
                                                    Rectangle { width: 110; height: 5; radius: 2; color: "#3f3f46" }
                                                    Rectangle { width: 85; height: 5; radius: 2; color: "#27272a" }
                                                }
                                            }
                                        }

                                        // Mini Dock
                                        Rectangle {
                                            anchors.bottom: parent.bottom; anchors.bottomMargin: 4
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: 100; height: 12; radius: 6
                                            color: Qt.rgba(1, 1, 1, 0.12)
                                            RowLayout {
                                                anchors.centerIn: parent; spacing: 4
                                                Repeater {
                                                    model: 5
                                                    delegate: Rectangle { width: 6; height: 6; radius: 3; color: (index === 0) ? Services.Theme.accent : "#71717a" }
                                                }
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text { text: Services.Icons.moon || "󰃭"; font.family: Services.Theme.fontSymbols; font.pixelSize: 18; color: Services.Theme.accent }
                                        Text { text: "Dark Mode"; font.pixelSize: 15; font.bold: true; color: Services.Theme.textPrimary }
                                        Item { Layout.fillWidth: true }
                                        Rectangle {
                                            visible: isSel
                                            height: 20; implicitWidth: dSelTxt.implicitWidth + 12; radius: 10
                                            color: Services.Theme.accent
                                            Text { id: dSelTxt; anchors.centerIn: parent; text: "✓ Active"; font.pixelSize: 10; font.bold: true; color: Services.Theme.bgOnAccent }
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Deep obsidian surfaces with refined contrast for low-light focus."
                                        font.pixelSize: 11
                                        color: Services.Theme.textSecondary
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (Services.Config) Services.Config.setThemeMode("dark")
                                }
                            }

                            // Light Mode Card with Visual Mockup
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: Services.Theme.radiusMd
                                readonly property bool isSel: Services.Config && Services.Config.themeMode === "light"
                                color: isSel ? Qt.rgba(0.95, 0.95, 0.98, 0.95) : Services.Theme.bgElevated
                                border.color: isSel ? Services.Theme.accent : Services.Theme.border
                                border.width: isSel ? 2 : 1
                                Behavior on border.color { ColorAnimation { duration: 180 } }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    spacing: 10

                                    // Mini Desktop Mockup (Light)
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 120
                                        radius: 10
                                        color: "#e2e8f0"
                                        border.color: "#cbd5e1"
                                        border.width: 1
                                        clip: true

                                        // Mini Top Bar
                                        Rectangle {
                                            anchors.top: parent.top
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            height: 18
                                            color: "#ffffff"
                                            RowLayout {
                                                anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                                                Rectangle { width: 8; height: 8; radius: 4; color: Services.Theme.accent }
                                                Item { Layout.fillWidth: true }
                                                Rectangle { width: 36; height: 6; radius: 3; color: "#cbd5e1" }
                                                Item { Layout.fillWidth: true }
                                                Rectangle { width: 14; height: 6; radius: 3; color: "#94a3b8" }
                                            }
                                        }

                                        // Mini Window
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 190; height: 62
                                            radius: 6
                                            color: "#ffffff"
                                            border.color: "#cbd5e1"
                                            border.width: 1
                                            RowLayout {
                                                anchors.fill: parent; anchors.margins: 6; spacing: 6
                                                Rectangle { width: 38; Layout.fillHeight: true; radius: 4; color: "#f1f5f9" }
                                                ColumnLayout {
                                                    Layout.fillWidth: true; spacing: 4
                                                    Rectangle { width: 70; height: 6; radius: 3; color: Services.Theme.accent }
                                                    Rectangle { width: 110; height: 5; radius: 2; color: "#94a3b8" }
                                                    Rectangle { width: 85; height: 5; radius: 2; color: "#cbd5e1" }
                                                }
                                            }
                                        }

                                        // Mini Dock
                                        Rectangle {
                                            anchors.bottom: parent.bottom; anchors.bottomMargin: 4
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: 100; height: 12; radius: 6
                                            color: Qt.rgba(0, 0, 0, 0.08)
                                            RowLayout {
                                                anchors.centerIn: parent; spacing: 4
                                                Repeater {
                                                    model: 5
                                                    delegate: Rectangle { width: 6; height: 6; radius: 3; color: (index === 0) ? Services.Theme.accent : "#94a3b8" }
                                                }
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text { text: Services.Icons.sun || "󰃠"; font.family: Services.Theme.fontSymbols; font.pixelSize: 18; color: "#f59e0b" }
                                        Text { text: "Light Mode"; font.pixelSize: 15; font.bold: true; color: isSel ? "#0f172a" : Services.Theme.textPrimary }
                                        Item { Layout.fillWidth: true }
                                        Rectangle {
                                            visible: isSel
                                            height: 20; implicitWidth: lSelTxt.implicitWidth + 12; radius: 10
                                            color: Services.Theme.accent
                                            Text { id: lSelTxt; anchors.centerIn: parent; text: "✓ Active"; font.pixelSize: 10; font.bold: true; color: Services.Theme.bgOnAccent }
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Frosted clean surfaces with crisp text for bright daylight environments."
                                        font.pixelSize: 11
                                        color: isSel ? "#475569" : Services.Theme.textSecondary
                                        wrapMode: Text.WordWrap
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
                        spacing: 12

                        ColumnLayout {
                            spacing: 2
                            Text { text: "Select Accent Color"; font.pixelSize: 22; font.bold: true; color: Services.Theme.textPrimary }
                            Text { text: "Accents color buttons, active indicators, sliders, and the Dynamic Island."; font.pixelSize: Services.Theme.fontSizeSm; color: Services.Theme.textSecondary }
                        }

                        // Matugen Wallpaper Dynamic Accent Card (Hero)
                        Rectangle {
                            Layout.fillWidth: true
                            height: 64
                            radius: Services.Theme.radiusSm
                            readonly property bool isMatugenCur: Services.Config && Services.Config.useMatugen
                            color: isMatugenCur ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.16) : Services.Theme.surfaceVariant
                            border.color: isMatugenCur ? Services.Theme.accent : Services.Theme.border
                            border.width: isMatugenCur ? 2 : 1
                            Behavior on border.color { ColorAnimation { duration: 180 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14; anchors.rightMargin: 14
                                spacing: 12

                                Rectangle {
                                    width: 38; height: 38; radius: 19
                                    color: Services.Theme.accent
                                    border.color: Qt.rgba(1, 1, 1, 0.2); border.width: 1
                                    Text {
                                        anchors.centerIn: parent
                                        text: Services.Icons.wallpaper || "󰸉"
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: 16
                                        color: Services.Theme.bgOnAccent
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    RowLayout {
                                        spacing: 8
                                        Text { text: "Matugen Dynamic Accent"; font.bold: true; font.pixelSize: Services.Theme.fontSizeSm; color: Services.Theme.textPrimary }
                                        Rectangle {
                                            height: 18; implicitWidth: autoBadgeTxt.implicitWidth + 10; radius: 9
                                            color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.25)
                                            Text { id: autoBadgeTxt; anchors.centerIn: parent; text: "Wallpaper Extracted"; font.pixelSize: 9; font.bold: true; color: Services.Theme.accent }
                                        }
                                    }
                                    Text { text: "Automatically extracts harmonized tones directly from your active desktop wallpaper."; font.pixelSize: 11; color: Services.Theme.textSecondary }
                                }

                                Rectangle {
                                    visible: isMatugenCur
                                    width: 24; height: 24; radius: 12
                                    color: Services.Theme.accent
                                    Text { anchors.centerIn: parent; text: "✓"; font.pixelSize: 12; font.bold: true; color: Services.Theme.bgOnAccent }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (Services.Config) {
                                        Services.Config.setAccent("", "Matugen (Wallpaper)", true)
                                    }
                                }
                            }
                        }

                        // Preset Accents Grid
                        GridLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            columns: 4
                            rowSpacing: 10
                            columnSpacing: 10

                            Repeater {
                                model: Services.Config ? Services.Config.accentPresets : []
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: Services.Theme.radiusSm
                                    readonly property bool isCur: Services.Config && !Services.Config.useMatugen && Services.Config.accentName === modelData.name

                                    color: isCur ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.16) : (pMouse.containsMouse ? Services.Theme.surfaceVariant : Services.Theme.bgElevated)
                                    border.color: isCur ? Services.Theme.accent : (pMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.border)
                                    border.width: isCur ? 2 : 1
                                    Behavior on border.color { ColorAnimation { duration: 150 } }

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 8

                                        Rectangle {
                                            width: 26; height: 26; radius: 13
                                            color: (Services.Config && Services.Config.themeMode === "light") ? modelData.lightHex : modelData.darkHex
                                            border.color: Qt.rgba(1, 1, 1, 0.2); border.width: 1

                                            Text {
                                                anchors.centerIn: parent
                                                text: "✓"
                                                font.pixelSize: 11
                                                font.bold: true
                                                color: Services.Theme.bgOnAccent
                                                visible: isCur
                                            }
                                        }

                                        Text {
                                            text: modelData.name
                                            font.pixelSize: Services.Theme.fontSizeSm
                                            font.bold: isCur
                                            color: isCur ? Services.Theme.accent : Services.Theme.textPrimary
                                        }
                                    }

                                    MouseArea {
                                        id: pMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
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
                    }

                    // ── PAGE 3: FONTS (SEGMENTED TABS + LIVE PLAYGROUND) ─────
                    ColumnLayout {
                        anchors.fill: parent
                        visible: rootWindow.currentStep === 3
                        spacing: 12

                        RowLayout {
                            Layout.fillWidth: true
                            ColumnLayout {
                                spacing: 2
                                Text { text: "Shell Typography"; font.pixelSize: 22; font.bold: true; color: Services.Theme.textPrimary }
                                Text { text: "Fine-tune UI, Monospace, and Display fonts with live preview."; font.pixelSize: Services.Theme.fontSizeSm; color: Services.Theme.textSecondary }
                            }

                            Item { Layout.fillWidth: true }

                            // Segmented Font Tabs [ UI Font | Monospace | Display ]
                            Rectangle {
                                height: 32
                                implicitWidth: tabsRow.implicitWidth + 8
                                radius: 8
                                color: Services.Theme.surfaceVariant
                                border.color: Services.Theme.border
                                border.width: 1

                                RowLayout {
                                    id: tabsRow
                                    anchors.centerIn: parent
                                    spacing: 4

                                    // Tab 0: Primary UI Font
                                    Rectangle {
                                        height: 24; implicitWidth: t0Txt.implicitWidth + 16; radius: 6
                                        color: (rootWindow.activeFontTab === 0) ? Services.Theme.accent : "transparent"
                                        Text {
                                            id: t0Txt; anchors.centerIn: parent; text: "󰛄 Primary UI"
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 11; font.bold: rootWindow.activeFontTab === 0
                                            color: (rootWindow.activeFontTab === 0) ? Services.Theme.bgOnAccent : Services.Theme.textPrimary
                                        }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: rootWindow.activeFontTab = 0 }
                                    }

                                    // Tab 1: Monospace Font
                                    Rectangle {
                                        height: 24; implicitWidth: t1Txt.implicitWidth + 16; radius: 6
                                        color: (rootWindow.activeFontTab === 1) ? Services.Theme.accent : "transparent"
                                        Text {
                                            id: t1Txt; anchors.centerIn: parent; text: "󰌌 Monospace"
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 11; font.bold: rootWindow.activeFontTab === 1
                                            color: (rootWindow.activeFontTab === 1) ? Services.Theme.bgOnAccent : Services.Theme.textPrimary
                                        }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: rootWindow.activeFontTab = 1 }
                                    }

                                    // Tab 2: Display Font
                                    Rectangle {
                                        height: 24; implicitWidth: t2Txt.implicitWidth + 16; radius: 6
                                        color: (rootWindow.activeFontTab === 2) ? Services.Theme.accent : "transparent"
                                        Text {
                                            id: t2Txt; anchors.centerIn: parent; text: "󰈙 Display"
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 11; font.bold: rootWindow.activeFontTab === 2
                                            color: (rootWindow.activeFontTab === 2) ? Services.Theme.bgOnAccent : Services.Theme.textPrimary
                                        }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: rootWindow.activeFontTab = 2 }
                                    }
                                }
                            }
                        }

                        // Split 2-Column: Left = Font List, Right = Live Typography Preview Playground
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 12

                            // Left Column: Scrollable Font List (width 320)
                            Rectangle {
                                Layout.preferredWidth: 320
                                Layout.fillHeight: true
                                radius: Services.Theme.radiusSm
                                color: Services.Theme.surfaceVariant
                                border.color: Services.Theme.border
                                border.width: 1
                                clip: true

                                ListView {
                                    id: fontActiveList
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 3
                                    clip: true

                                    model: {
                                        if (rootWindow.activeFontTab === 1) {
                                            return Services.SystemTheme ? Services.SystemTheme.monospaceFonts : []
                                        } else {
                                            return Services.SystemTheme ? Services.SystemTheme.systemFonts : []
                                        }
                                    }

                                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 6 }

                                    delegate: Rectangle {
                                        required property var modelData
                                        required property int index
                                        width: fontActiveList.width - 10
                                        height: 34
                                        radius: 6

                                        readonly property string fontName: (typeof modelData === "string") ? modelData : (modelData.id || modelData.label || String(modelData))
                                        readonly property bool isSelected: {
                                            if (rootWindow.activeFontTab === 0) return rootWindow.wizardSelectedFontFamily === fontName
                                            if (rootWindow.activeFontTab === 1) return rootWindow.wizardSelectedFontMono === fontName
                                            return rootWindow.wizardSelectedFontDisplay === fontName
                                        }

                                        color: isSelected
                                            ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.2)
                                            : (flMouse.containsMouse ? Services.Theme.bgElevated : "transparent")
                                        border.color: isSelected ? Services.Theme.accent : "transparent"
                                        border.width: 1

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10; anchors.rightMargin: 10
                                            spacing: 8

                                            Text {
                                                text: fontName
                                                font.pixelSize: 12
                                                font.bold: isSelected
                                                font.family: fontName
                                                color: isSelected ? Services.Theme.accent : Services.Theme.textPrimary
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }

                                            Rectangle {
                                                width: 16; height: 16; radius: 8
                                                visible: isSelected
                                                color: Services.Theme.accent
                                                Text { anchors.centerIn: parent; text: "✓"; font.pixelSize: 8; font.bold: true; color: Services.Theme.bgOnAccent }
                                            }
                                        }

                                        MouseArea {
                                            id: flMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (rootWindow.activeFontTab === 0) {
                                                    rootWindow.wizardSelectedFontFamily = fontName
                                                } else if (rootWindow.activeFontTab === 1) {
                                                    rootWindow.wizardSelectedFontMono = fontName
                                                } else {
                                                    rootWindow.wizardSelectedFontDisplay = fontName
                                                }
                                            }
                                        }

                                        Component.onCompleted: {
                                            if (isSelected) fontActiveList.positionViewAtIndex(index, ListView.Center)
                                        }
                                    }
                                }
                            }

                            // Right Column: Live Typography Preview Playground
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: Services.Theme.radiusSm
                                color: Services.Theme.bgElevated
                                border.color: Services.Theme.border
                                border.width: 1
                                clip: true

                                property string currentPreviewFont: {
                                    if (rootWindow.activeFontTab === 0) return rootWindow.wizardSelectedFontFamily || "SF Pro Display"
                                    if (rootWindow.activeFontTab === 1) return rootWindow.wizardSelectedFontMono || "Liga SFMono Nerd Font"
                                    return rootWindow.wizardSelectedFontDisplay || "SF Pro Display"
                                }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 12

                                    // Active Font Header Info
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Rectangle {
                                            height: 22; implicitWidth: catBadge.implicitWidth + 12; radius: 11
                                            color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.2)
                                            Text {
                                                id: catBadge; anchors.centerIn: parent
                                                text: (rootWindow.activeFontTab === 0) ? "UI Font" : ((rootWindow.activeFontTab === 1) ? "Monospace" : "Display")
                                                font.pixelSize: 10; font.bold: true; color: Services.Theme.accent
                                            }
                                        }
                                        Text {
                                            text: parent.parent.currentPreviewFont
                                            font.pixelSize: 13; font.bold: true; color: Services.Theme.textPrimary
                                            elide: Text.ElideRight; Layout.fillWidth: true
                                        }
                                    }

                                    Rectangle { Layout.fillWidth: true; height: 1; color: Services.Theme.border; opacity: 0.6 }

                                    // Big Alphabet Display
                                    Text {
                                        text: "Aa Bb Gg 123"
                                        font.family: parent.currentPreviewFont
                                        font.pixelSize: 32
                                        font.bold: true
                                        color: Services.Theme.textPrimary
                                    }

                                    // Pangram Sample
                                    Text {
                                        Layout.fillWidth: true
                                        text: "The quick brown fox jumps over the lazy dog."
                                        font.family: parent.currentPreviewFont
                                        font.pixelSize: 15
                                        color: Services.Theme.textPrimary
                                        wrapMode: Text.WordWrap
                                    }

                                    // Numbers & Symbols
                                    Text {
                                        Layout.fillWidth: true
                                        text: "0123456789 • !@#$%^&*()_+"
                                        font.family: parent.currentPreviewFont
                                        font.pixelSize: 12
                                        color: Services.Theme.textSecondary
                                        wrapMode: Text.WordWrap
                                    }

                                    Item { Layout.fillHeight: true }

                                    // Mini UI Mockup inside Playground
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 48
                                        radius: 8
                                        color: Services.Theme.surfaceVariant
                                        border.color: Services.Theme.border
                                        border.width: 1

                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: 12
                                            Rectangle {
                                                height: 28; implicitWidth: mbTxt.implicitWidth + 16; radius: 6
                                                color: Services.Theme.accent
                                                Text {
                                                    id: mbTxt; anchors.centerIn: parent; text: "Sample Button"
                                                    font.family: parent.parent.parent.parent.currentPreviewFont
                                                    font.pixelSize: 11; font.bold: true; color: Services.Theme.bgOnAccent
                                                }
                                            }
                                            Text {
                                                text: "UI Sample Text • 12pt"
                                                font.family: parent.parent.parent.parent.currentPreviewFont
                                                font.pixelSize: 11; color: Services.Theme.textSecondary
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── PAGE 4: BAR & DYNAMIC ISLAND ─────────────────────────
                    ColumnLayout {
                        anchors.fill: parent
                        visible: rootWindow.currentStep === 4
                        spacing: 14

                        ColumnLayout {
                            spacing: 2
                            Text { text: "Top Bar & Dynamic Island"; font.pixelSize: 22; font.bold: true; color: Services.Theme.textPrimary }
                            Text { text: "Configure how time, dates, and live status pills are presented in your bar."; font.pixelSize: Services.Theme.fontSizeSm; color: Services.Theme.textSecondary }
                        }

                        // Settings Container
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: bSetCol.implicitHeight + 28
                            radius: Services.Theme.radiusMd
                            color: Services.Theme.surfaceVariant
                            border.color: Services.Theme.border
                            border.width: 1

                            ColumnLayout {
                                id: bSetCol
                                anchors.fill: parent
                                anchors.margins: 18
                                spacing: 18

                                // 24H Toggle Card
                                RowLayout {
                                    Layout.fillWidth: true
                                    Rectangle {
                                        width: 38; height: 38; radius: 10
                                        color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.16)
                                        Text { anchors.centerIn: parent; text: Services.Icons.clock || "󱑂"; font.family: Services.Theme.fontSymbols; font.pixelSize: 18; color: Services.Theme.accent }
                                    }
                                    ColumnLayout {
                                        spacing: 2
                                        Text { text: "24-Hour Time Format"; font.pixelSize: Services.Theme.fontSizeMd; font.bold: true; color: Services.Theme.textPrimary }
                                        Text { text: (Services.Config && Services.Config.clock24h) ? "Displaying as 14:30 (24-Hour format)" : "Displaying as 02:30 PM (12-Hour format)"; font.pixelSize: Services.Theme.fontSizeXs; color: Services.Theme.textSecondary }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        width: 48; height: 26; radius: 13
                                        color: (Services.Config && Services.Config.clock24h) ? Services.Theme.accent : Services.Theme.bgElevated
                                        border.color: Services.Theme.border; border.width: 1

                                        Rectangle {
                                            width: 20; height: 20; radius: 10
                                            y: 2
                                            x: (Services.Config && Services.Config.clock24h) ? 25 : 3
                                            color: (Services.Config && Services.Config.clock24h) ? Services.Theme.bgOnAccent : Services.Theme.textSecondary
                                            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: if (Services.Config) Services.Config.setClock24h(!Services.Config.clock24h)
                                        }
                                    }
                                }

                                Rectangle { Layout.fillWidth: true; height: 1; color: Services.Theme.border; opacity: 0.5 }

                                // Show Seconds Toggle Card
                                RowLayout {
                                    Layout.fillWidth: true
                                    Rectangle {
                                        width: 38; height: 38; radius: 10
                                        color: Qt.rgba(0.2, 0.6, 1.0, 0.16)
                                        Text { anchors.centerIn: parent; text: "󱫌"; font.family: Services.Theme.fontSymbols; font.pixelSize: 18; color: "#38bdf8" }
                                    }
                                    ColumnLayout {
                                        spacing: 2
                                        Text { text: "Show Seconds Ticker"; font.pixelSize: Services.Theme.fontSizeMd; font.bold: true; color: Services.Theme.textPrimary }
                                        Text { text: "Display real-time seconds ticking in the status bar clock"; font.pixelSize: Services.Theme.fontSizeXs; color: Services.Theme.textSecondary }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        width: 48; height: 26; radius: 13
                                        color: (Services.Config && Services.Config.clockShowSeconds) ? Services.Theme.accent : Services.Theme.bgElevated
                                        border.color: Services.Theme.border; border.width: 1

                                        Rectangle {
                                            width: 20; height: 20; radius: 10
                                            y: 2
                                            x: (Services.Config && Services.Config.clockShowSeconds) ? 25 : 3
                                            color: (Services.Config && Services.Config.clockShowSeconds) ? Services.Theme.bgOnAccent : Services.Theme.textSecondary
                                            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
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

                    // ── PAGE 5: SOUND & NOTIFICATIONS ────────────────────────
                    ColumnLayout {
                        anchors.fill: parent
                        visible: rootWindow.currentStep === 5
                        spacing: 14

                        ColumnLayout {
                            spacing: 2
                            Text { text: "Audio Feedback & Alerts"; font.pixelSize: 22; font.bold: true; color: Services.Theme.textPrimary }
                            Text { text: "Fine-tune UI audio chimes and system event sound effects."; font.pixelSize: Services.Theme.fontSizeSm; color: Services.Theme.textSecondary }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: sSetCol.implicitHeight + 28
                            radius: Services.Theme.radiusMd
                            color: Services.Theme.surfaceVariant
                            border.color: Services.Theme.border
                            border.width: 1

                            ColumnLayout {
                                id: sSetCol
                                anchors.fill: parent
                                anchors.margins: 18
                                spacing: 18

                                // Sound Feedback Toggle
                                RowLayout {
                                    Layout.fillWidth: true
                                    Rectangle {
                                        width: 38; height: 38; radius: 10
                                        color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.16)
                                        Text { anchors.centerIn: parent; text: Services.Icons.speaker || "󰕾"; font.family: Services.Theme.fontSymbols; font.pixelSize: 18; color: Services.Theme.accent }
                                    }
                                    ColumnLayout {
                                        spacing: 2
                                        Text { text: "UI Audio Feedback"; font.pixelSize: Services.Theme.fontSizeMd; font.bold: true; color: Services.Theme.textPrimary }
                                        Text { text: "Play tactile sound chimes on volume adjustment, device plugins, and system events"; font.pixelSize: Services.Theme.fontSizeXs; color: Services.Theme.textSecondary }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        width: 48; height: 26; radius: 13
                                        color: (Services.Config && Services.Config.soundFeedback) ? Services.Theme.accent : Services.Theme.bgElevated
                                        border.color: Services.Theme.border; border.width: 1

                                        Rectangle {
                                            width: 20; height: 20; radius: 10
                                            y: 2
                                            x: (Services.Config && Services.Config.soundFeedback) ? 25 : 3
                                            color: (Services.Config && Services.Config.soundFeedback) ? Services.Theme.bgOnAccent : Services.Theme.textSecondary
                                            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: if (Services.Config) Services.Config.setSoundFeedback(!Services.Config.soundFeedback)
                                        }
                                    }
                                }

                                Rectangle { Layout.fillWidth: true; height: 1; color: Services.Theme.border; opacity: 0.5 }

                                // Interactive Audition Sound Button
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 42
                                    radius: Services.Theme.radiusSm
                                    color: audMouse.containsMouse ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15) : Services.Theme.bgElevated
                                    border.color: audMouse.containsMouse ? Services.Theme.accent : Services.Theme.border
                                    border.width: 1
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 8
                                        Text { text: "󰓃"; font.family: Services.Theme.fontSymbols; font.pixelSize: 15; color: Services.Theme.accent }
                                        Text { text: "Audition Notification Chime"; font.pixelSize: Services.Theme.fontSizeSm; font.bold: true; color: Services.Theme.textPrimary }
                                    }

                                    MouseArea {
                                        id: audMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
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

                    // ── PAGE 6: FINISH / ALL SET! ────────────────────────────
                    ColumnLayout {
                        anchors.fill: parent
                        visible: rootWindow.currentStep === 6
                        spacing: 16

                        Item { Layout.fillHeight: true }

                        // Glowing Success Badge
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 72; height: 72; radius: 36
                            color: Qt.rgba(0.1, 0.8, 0.4, 0.18)
                            border.color: Services.Theme.success
                            border.width: 2

                            Text {
                                anchors.centerIn: parent
                                text: "✓"
                                font.pixelSize: 32
                                font.bold: true
                                color: Services.Theme.success
                            }
                        }

                        ColumnLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 4
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "You're All Set!"
                                font.family: Services.Theme.fontDisplay
                                font.pixelSize: 26
                                font.bold: true
                                color: Services.Theme.textPrimary
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.maximumWidth: 540
                                text: "Your personal preferences have been saved and applied. You can modify any option anytime through Settings or the Control Center."
                                font.pixelSize: Services.Theme.fontSizeSm
                                color: Services.Theme.textSecondary
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                            }
                        }

                        // Summary Bento Box: Highlights user's choices
                        GridLayout {
                            Layout.alignment: Qt.AlignHCenter
                            columns: 2
                            columnSpacing: 10
                            rowSpacing: 10

                            Rectangle {
                                width: 260; height: 42; radius: 8
                                color: Services.Theme.surfaceVariant
                                border.color: Services.Theme.border; border.width: 1
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: 10; spacing: 8
                                    Text { text: "🌓"; font.pixelSize: 13 }
                                    Text { text: "Mode:"; font.pixelSize: 11; color: Services.Theme.textSecondary }
                                    Text { text: (Services.Config && Services.Config.themeMode === "light") ? "Light Mode" : "Dark Mode"; font.pixelSize: 11; font.bold: true; color: Services.Theme.textPrimary; elide: Text.ElideRight }
                                }
                            }

                            Rectangle {
                                width: 260; height: 42; radius: 8
                                color: Services.Theme.surfaceVariant
                                border.color: Services.Theme.border; border.width: 1
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: 10; spacing: 8
                                    Rectangle { width: 12; height: 12; radius: 6; color: Services.Theme.accent }
                                    Text { text: "Accent:"; font.pixelSize: 11; color: Services.Theme.textSecondary }
                                    Text { text: Services.Config ? Services.Config.accentName : "Default"; font.pixelSize: 11; font.bold: true; color: Services.Theme.textPrimary; elide: Text.ElideRight }
                                }
                            }

                            Rectangle {
                                width: 260; height: 42; radius: 8
                                color: Services.Theme.surfaceVariant
                                border.color: Services.Theme.border; border.width: 1
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: 10; spacing: 8
                                    Text { text: "󰛄"; font.family: Services.Theme.fontSymbols; font.pixelSize: 13; color: Services.Theme.accent }
                                    Text { text: "Font:"; font.pixelSize: 11; color: Services.Theme.textSecondary }
                                    Text { text: rootWindow.wizardSelectedFontFamily || (Services.Config ? Services.Config.fontFamily : "Default"); font.pixelSize: 11; font.bold: true; color: Services.Theme.textPrimary; elide: Text.ElideRight }
                                }
                            }

                            Rectangle {
                                width: 260; height: 42; radius: 8
                                color: Services.Theme.surfaceVariant
                                border.color: Services.Theme.border; border.width: 1
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: 10; spacing: 8
                                    Text { text: "󱑂"; font.family: Services.Theme.fontSymbols; font.pixelSize: 13; color: Services.Theme.accent }
                                    Text { text: "Clock:"; font.pixelSize: 11; color: Services.Theme.textSecondary }
                                    Text { text: (Services.Config && Services.Config.clock24h) ? "24-Hour Format" : "12-Hour Format"; font.pixelSize: 11; font.bold: true; color: Services.Theme.textPrimary; elide: Text.ElideRight }
                                }
                            }
                        }

                        // Shortcuts Quick Reference
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 530
                            implicitHeight: sccCol.implicitHeight + 16
                            radius: Services.Theme.radiusSm
                            color: Services.Theme.bgElevated
                            border.color: Services.Theme.border
                            border.width: 1

                            RowLayout {
                                id: sccCol
                                anchors.centerIn: parent
                                spacing: 20
                                RowLayout {
                                    spacing: 6
                                    Rectangle { height: 18; implicitWidth: k1.implicitWidth + 8; radius: 4; color: Services.Theme.surfaceVariant; border.color: Services.Theme.border; border.width: 1; Text { id: k1; anchors.centerIn: parent; text: "Super + D"; font.pixelSize: 10; font.bold: true; color: Services.Theme.accent } }
                                    Text { text: "Launcher"; font.pixelSize: 11; color: Services.Theme.textSecondary }
                                }
                                RowLayout {
                                    spacing: 6
                                    Rectangle { height: 18; implicitWidth: k2.implicitWidth + 8; radius: 4; color: Services.Theme.surfaceVariant; border.color: Services.Theme.border; border.width: 1; Text { id: k2; anchors.centerIn: parent; text: "Super + A"; font.pixelSize: 10; font.bold: true; color: Services.Theme.accent } }
                                    Text { text: "Dashboard"; font.pixelSize: 11; color: Services.Theme.textSecondary }
                                }
                                RowLayout {
                                    spacing: 6
                                    Rectangle { height: 18; implicitWidth: k3.implicitWidth + 8; radius: 4; color: Services.Theme.surfaceVariant; border.color: Services.Theme.border; border.width: 1; Text { id: k3; anchors.centerIn: parent; text: "Super + C"; font.pixelSize: 10; font.bold: true; color: Services.Theme.accent } }
                                    Text { text: "Control Center"; font.pixelSize: 11; color: Services.Theme.textSecondary }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }

                // Divider line
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Services.Theme.border
                    opacity: 0.7
                }

                // ═════════════════════════════════════════════════════════════
                // ── BOTTOM NAVIGATION FOOTER ─────────────────────────────────
                // ═════════════════════════════════════════════════════════════
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    // Back Button
                    Rectangle {
                        width: 96; height: 38
                        radius: 8
                        visible: rootWindow.currentStep > 0
                        color: backMouse.containsMouse ? Services.Theme.surfaceVariant : Services.Theme.bgElevated
                        border.color: backMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.border
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            Text { text: Services.Icons.chevLeft || "‹"; font.family: Services.Theme.fontSymbols; font.pixelSize: 12; color: Services.Theme.textPrimary }
                            Text { text: "Back"; font.pixelSize: Services.Theme.fontSizeSm; font.bold: true; color: Services.Theme.textPrimary }
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
                        height: 38
                        implicitWidth: nxtRow.implicitWidth + 28
                        radius: 8
                        color: nxtMouse.containsMouse
                            ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.88)
                            : Services.Theme.accent
                        Behavior on color { ColorAnimation { duration: 150 } }

                        RowLayout {
                            id: nxtRow
                            anchors.centerIn: parent
                            spacing: 8

                            Text {
                                text: (rootWindow.currentStep === 0)
                                    ? "Start Setup"
                                    : ((rootWindow.currentStep === rootWindow.totalSteps - 1) ? "Finish & Launch Nimbush" : "Next")
                                font.pixelSize: Services.Theme.fontSizeSm
                                font.bold: true
                                color: Services.Theme.bgOnAccent
                            }

                            Text {
                                text: (rootWindow.currentStep === rootWindow.totalSteps - 1) ? (Services.Icons.check || "✓") : (Services.Icons.chevRight || "›")
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 11
                                font.bold: true
                                color: Services.Theme.bgOnAccent
                            }
                        }

                        MouseArea {
                            id: nxtMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                // Apply staged settings when advancing
                                rootWindow.applyCurrentStaged()

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
