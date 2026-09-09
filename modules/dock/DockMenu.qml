import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../services" as Services

PanelWindow {
    id: root
    property string overlayId: "dockMenu"

    readonly property bool isOpen: Services.DockService ? Services.DockService.isMenuOpen : false
    readonly property var item: Services.DockService ? Services.DockService.contextMenuItem : null
    readonly property string dockPos: Services.Config ? Services.Config.dockPosition : "bottom"
    readonly property int iconSize: Services.Config ? Services.Config.dockIconSize : 48
    readonly property int dockBarH: iconSize + 16
    readonly property int floatingDist: Services.Config ? Services.Config.dockFloatingDistance : 6

    visible: root.isOpen
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:dockmenu"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusiveZone: 0

    function close() {
        if (Services.DockService) Services.DockService.closeMenu()
    }
    function hide() { close() }

    Component.onCompleted: {
        if (Services.OverlayManager) Services.OverlayManager.register(root)
    }

    // ── Keyboard Esc Focus Handler ───────────────────────────────────────────
    Item {
        id: escFocus
        focus: root.visible
        Keys.onEscapePressed: root.close()
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                root.close()
                event.accepted = true
            }
        }
    }

    // ── Backdrop Dismiss Area (Click anywhere outside to close) ──────────────
    MouseArea {
        id: dismissArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: root.close()
    }

    // ── Context Menu Card ────────────────────────────────────────────────────
    Rectangle {
        id: menuCard
        width: 224
        implicitHeight: dockMenuCol.implicitHeight + 16
        height: implicitHeight
        radius: 12

        // Liquid Glass Styling
        color: Services.Theme.bgElevated
        border.color: Services.Theme.borderHighlight
        border.width: 1

        // Consume mouse clicks within the card to prevent backdrop dismiss
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        }

        readonly property int dockReserveOffset: {
            if (Services.Config && Services.Config.dockAutoHide) {
                return root.dockBarH + root.floatingDist
            }
            return 0
        }

        // Horizontal positioning: align with icon center and constrain to screen margins
        x: {
            if (root.dockPos === "left") {
                return dockReserveOffset + 8
            } else if (root.dockPos === "right") {
                return root.width - width - dockReserveOffset - 8
            } else {
                const targetX = Services.DockService ? Services.DockService.contextMenuX : (root.width / 2)
                return Math.max(12, Math.min(targetX - width / 2, root.width - width - 12))
            }
        }

        // Vertical positioning: crisp 8px gap directly above dock
        y: {
            if (root.dockPos === "bottom") {
                return Math.max(12, root.height - height - dockReserveOffset - 8)
            } else if (root.dockPos === "top") {
                return dockReserveOffset + 8
            } else {
                const targetY = Services.DockService ? Services.DockService.contextMenuY : (root.height / 2)
                return Math.max(12, Math.min(targetY - height / 2, root.height - height - 12))
            }
        }

        // Subtle top specular highlight
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 1
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            height: 1
            color: Qt.rgba(1, 1, 1, 0.15)
        }

        // Smooth entry animation
        scale: root.isOpen ? 1.0 : 0.94
        opacity: root.isOpen ? 1.0 : 0.0
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
        Behavior on opacity { NumberAnimation { duration: 120 } }

        ColumnLayout {
            id: dockMenuCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 8
            spacing: 3

            // ── 1. App Header ────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                implicitHeight: 38
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                spacing: 10

                Item {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    implicitWidth: 30
                    implicitHeight: 30

                    Rectangle {
                        anchors.fill: parent
                        radius: 7
                        color: Services.Theme.bgHover
                        visible: !menuAppImg.source || menuAppImg.status !== Image.Ready || !menuAppImg.visible

                        Text {
                            anchors.centerIn: parent
                            text: (root.item ? (root.item.name || "?") : "?").charAt(0).toUpperCase()
                            color: Services.Theme.accent
                            font.pixelSize: 13
                            font.bold: true
                        }
                    }

                    Image {
                        id: menuAppImg
                        anchors.fill: parent
                        source: {
                            if (!root.item) return ""
                            const rawApp = root.item.app || root.item
                            const raw = rawApp ? (typeof rawApp.icon === "string" ? rawApp.icon : (rawApp.icon?.name || (typeof root.item.icon === "string" ? root.item.icon : ""))) : ""
                            if (!raw) return ""
                            if (Services.SystemTheme) {
                                const res = Services.SystemTheme.getIcon(raw)
                                if (res && res.length > 0) return res
                            }
                            if (raw.startsWith("file://") || raw.startsWith("http://") || raw.startsWith("https://")) return raw
                            if (raw.startsWith("/")) return "file://" + raw
                            let s = raw.startsWith("image://icon/") ? raw.substring(13) : raw
                            if (s.startsWith("image://")) return s
                            const qp = Quickshell.iconPath(s, true)
                            return (qp && qp.startsWith("/")) ? ("file://" + qp) : (qp || "")
                        }
                        fillMode: Image.PreserveAspectFit
                        visible: status === Image.Ready && source.toString().length > 0
                        sourceSize: Qt.size(64, 64)
                        mipmap: true
                        smooth: true
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: root.item ? (root.item.name || "") : ""
                        font.pixelSize: Services.Theme.fontSizeMd
                        font.weight: Font.DemiBold
                        color: Services.Theme.textPrimary
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    // Clean status subtitle
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        visible: Boolean(root.item && root.item.isRunning)

                        Rectangle {
                            width: 5
                            height: 5
                            radius: 2.5
                            color: Services.Theme.accent
                        }

                        Text {
                            text: (root.item && root.item.windows && root.item.windows.length > 1)
                                ? (root.item.windows.length + " windows open")
                                : "Active"
                            font.pixelSize: 10
                            color: Services.Theme.textSecondary
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    Text {
                        text: (root.item && root.item.comment) ? root.item.comment : "Application"
                        font.pixelSize: 10
                        color: Services.Theme.textDisabled
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        visible: !Boolean(root.item && root.item.isRunning)
                    }
                }
            }

            // Divider
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                implicitHeight: 1
                Layout.topMargin: 2
                Layout.bottomMargin: 2
                color: Services.Theme.border
                opacity: 0.5
            }

            // ── 2. Launch / New Window Action ────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                implicitHeight: 30
                radius: 6
                color: dockLaunchMouse.containsMouse ? Services.Theme.bgHover : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    Text {
                        text: Services.Icons.play || "▶"
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 11
                        color: Services.Theme.accent
                    }
                    Text {
                        text: (root.item && root.item.isRunning) ? "New Window" : "Launch"
                        font.pixelSize: Services.Theme.fontSizeSm
                        color: Services.Theme.textPrimary
                        Layout.fillWidth: true
                    }
                }

                MouseArea {
                    id: dockLaunchMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const target = root.item
                        if (Services.DockService) {
                            Services.DockService.closeMenu()
                            Services.DockService.launchApp(target)
                        }
                    }
                }
            }

            // ── 3. Desktop Entry Actions (e.g. New Tab, Private Window) ───────
            Repeater {
                model: (root.item && root.item.actions) ? root.item.actions : []
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    implicitHeight: 28
                    radius: 6
                    color: dActMouse.containsMouse ? Services.Theme.bgHover : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
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
                        id: dActMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (Services.DockService) Services.DockService.closeMenu()
                            if (typeof modelData.execute === "function") {
                                modelData.execute()
                            }
                        }
                    }
                }
            }

            // ── 4. Pin / Unpin Action ────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                implicitHeight: 30
                radius: 6
                readonly property bool pinned: (root.item && Services.DockService) ? Services.DockService.isPinned(root.item.desktopId) : false
                color: dockPinMouse.containsMouse ? Services.Theme.bgHover : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    Text {
                        text: Services.Icons.pin || "󰤩"
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 12
                        color: parent.parent.pinned ? Services.Theme.accent : Services.Theme.textSecondary
                    }
                    Text {
                        text: parent.parent.pinned ? "Unpin from Dock" : "Pin to Dock"
                        font.pixelSize: Services.Theme.fontSizeSm
                        color: Services.Theme.textPrimary
                        Layout.fillWidth: true
                    }
                }

                MouseArea {
                    id: dockPinMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const target = root.item
                        if (target && target.desktopId && Services.DockService) {
                            Services.DockService.togglePin(target.desktopId)
                            Services.DockService.closeMenu()
                        }
                    }
                }
            }

            // ── 5. Running Windows List ──────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? 18 : 0
                implicitHeight: visible ? 18 : 0
                color: "transparent"
                visible: Boolean(root.item && root.item.windows && root.item.windows.length > 0)

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Open Windows (" + (root.item ? root.item.windows.length : 0) + ")"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    color: Services.Theme.textDisabled
                }
            }

            Repeater {
                model: (root.item && root.item.windows) ? root.item.windows : []
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    implicitHeight: 28
                    radius: 6
                    color: winMouse.containsMouse ? Services.Theme.bgHover : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8

                        Text {
                            text: "▪"
                            font.pixelSize: 10
                            color: (modelData.address === Services.DockService.activeWindowAddress) ? Services.Theme.accent : Services.Theme.textDisabled
                        }
                        Text {
                            text: modelData.title || "Window"
                            font.pixelSize: Services.Theme.fontSizeXs
                            color: (modelData.address === Services.DockService.activeWindowAddress) ? Services.Theme.accent : Services.Theme.textPrimary
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    MouseArea {
                        id: winMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (Services.DockService) {
                                Services.DockService.focusWindow(modelData.address)
                                Services.DockService.closeMenu()
                            }
                        }
                    }
                }
            }

            // ── 6. Quit / Close All Windows (if running) ─────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? 30 : 0
                implicitHeight: visible ? 30 : 0
                radius: 6
                visible: Boolean(root.item && root.item.isRunning)
                color: quitMouse.containsMouse ? Qt.rgba(0.9, 0.2, 0.2, 0.15) : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    Text {
                        text: Services.Icons.close || "✕"
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 11
                        color: Services.Theme.danger
                    }
                    Text {
                        text: "Quit / Close All"
                        font.pixelSize: Services.Theme.fontSizeSm
                        font.weight: Font.Medium
                        color: Services.Theme.danger
                        Layout.fillWidth: true
                    }
                }

                MouseArea {
                    id: quitMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const target = root.item
                        if (Services.DockService) {
                            Services.DockService.closeMenu()
                            Services.DockService.closeApp(target)
                        }
                    }
                }
            }
        }
    }
}
