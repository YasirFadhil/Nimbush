import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../services" as Services
import "../common" as Common

PanelWindow {
    id: root
    property string overlayId: "dockMenu"

    readonly property bool isOpen: Services.DockService ? Services.DockService.isMenuOpen : false
    readonly property var item: Services.DockService ? Services.DockService.contextMenuItem : null
    readonly property string dockPos: Services.Config ? Services.Config.dockPosition : "bottom"
    readonly property int iconSize: Services.Config ? Services.Config.dockIconSize : 48
    // Must match Dock.qml's dockBarHeight (iconSize + 24)
    readonly property int dockBarH: iconSize + 24
    readonly property int floatingDist: Services.Config ? Services.Config.dockFloatingDistance : 6

    // Keep the last non-null item so the card doesn't collapse/blank while it fades out
    property var cachedItem: null
    onItemChanged: { if (item) cachedItem = item }
    readonly property var shownItem: item ? item : cachedItem

    // ── macOS Menu Material Tokens ───────────────────────────────────────────
    // Menus are a bit more opaque than the dock for legibility. Blur comes from the
    // compositor (layer rule on "quickshell:dockmenu"); keep ignore_alpha below menuFill alpha.
    readonly property bool dark: Services.Theme.isDark
    readonly property color menuFill: dark ? Qt.rgba(0.14, 0.14, 0.15, 0.80) : Qt.rgba(1, 1, 1, 0.88)
    readonly property color menuBorder: dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.14)
    readonly property color menuSpecular: dark ? Qt.rgba(1, 1, 1, 0.24) : Qt.rgba(1, 1, 1, 0.80)
    readonly property color menuDivider: dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.14)
    readonly property color textPrimary: dark ? Qt.rgba(1, 1, 1, 0.97) : Qt.rgba(0, 0, 0, 0.90)
    readonly property color textSecondary: dark ? Qt.rgba(1, 1, 1, 0.75) : Qt.rgba(0, 0, 0, 0.65)
    readonly property color textTertiary: dark ? Qt.rgba(1, 1, 1, 0.52) : Qt.rgba(0, 0, 0, 0.45)

    // Stay mapped while the card is still fading out, otherwise the fade never plays
    visible: root.isOpen || menuCard.opacity > 0.01
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:dockmenu" // Hyprland layer rule: blur + ignore_alpha
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
        focus: root.isOpen
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
        enabled: root.isOpen
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: root.close()
    }

    // ── Context Menu Card ────────────────────────────────────────────────────
    Rectangle {
        id: menuCard
        width: 224
        implicitHeight: dockMenuCol.implicitHeight + 12
        height: implicitHeight
        radius: 11

        // macOS menu material
        color: root.menuFill
        border.color: root.menuBorder
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

        // Smooth entry / exit animation (fade handled here, not by the compositor)
        scale: root.isOpen ? 1.0 : 0.96
        opacity: root.isOpen ? 1.0 : 0.0
        transformOrigin: root.dockPos === "bottom" ? Item.Bottom : Item.Center
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 120 } }

        ColumnLayout {
            id: dockMenuCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 6
            spacing: 2

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
                        color: root.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
                        visible: !menuAppImg.source || menuAppImg.status !== Image.Ready || !menuAppImg.visible

                        Text {
                            anchors.centerIn: parent
                            text: (root.shownItem ? (root.shownItem.name || "?") : "?").charAt(0).toUpperCase()
                            color: root.textPrimary
                            font.pixelSize: 13
                            font.bold: true
                        }
                    }

                    Image {
                        id: menuAppImg
                        anchors.fill: parent
                        source: {
                            if (!root.shownItem) return ""
                            const rawApp = root.shownItem.app || root.shownItem
                            const raw = rawApp ? (typeof rawApp.icon === "string" ? rawApp.icon : (rawApp.icon?.name || (typeof root.shownItem.icon === "string" ? root.shownItem.icon : ""))) : ""
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
                        text: root.shownItem ? (root.shownItem.name || "") : ""
                        font.pixelSize: Services.Theme.fontSizeMd
                        font.weight: Font.DemiBold
                        color: root.textPrimary
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    // Clean status subtitle
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        visible: Boolean(root.shownItem && root.shownItem.isRunning)

                        Rectangle {
                            width: 5
                            height: 5
                            radius: 2.5
                            color: root.textSecondary
                        }

                        Text {
                            text: (root.shownItem && root.shownItem.windows && root.shownItem.windows.length > 1)
                                ? (root.shownItem.windows.length + " windows open")
                                : "Active"
                            font.pixelSize: 10
                            color: root.textSecondary
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    Text {
                        text: (root.shownItem && root.shownItem.comment) ? root.shownItem.comment : "Application"
                        font.pixelSize: 10
                        color: root.textTertiary
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        visible: !Boolean(root.shownItem && root.shownItem.isRunning)
                    }
                }
            }

            // Divider
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                implicitHeight: 1
                Layout.topMargin: 3
                Layout.bottomMargin: 3
                Layout.leftMargin: 6
                Layout.rightMargin: 6
                color: root.menuDivider
            }

            // ── 2. Launch / New Window Action ────────────────────────────────
            Common.MenuRow {
                glyph: Services.Icons.play || "▶"
                label: (root.shownItem && root.shownItem.isRunning) ? "New Window" : "Launch"
                onTriggered: {
                    const target = root.shownItem
                    if (Services.DockService) {
                        Services.DockService.closeMenu()
                        Services.DockService.launchApp(target)
                    }
                }
            }

            // ── 3. Desktop Entry Actions (e.g. New Tab, Private Window) ───────
            Repeater {
                model: (root.shownItem && root.shownItem.actions) ? root.shownItem.actions : []
                delegate: Common.MenuRow {
                    required property var modelData
                    label: modelData.name || "Action"
                    onTriggered: {
                        if (Services.DockService) Services.DockService.closeMenu()
                        if (typeof modelData.execute === "function") {
                            Services.Applications.launch(modelData)
                        }
                    }
                }
            }

            // ── 4. Pin / Unpin Action ────────────────────────────────────────
            Common.MenuRow {
                readonly property bool pinned: (root.shownItem && Services.DockService) ? Services.DockService.isPinned(root.shownItem.desktopId) : false
                glyph: Services.Icons.pin || "󰤩"
                label: pinned ? "Unpin from Dock" : "Pin to Dock"
                onTriggered: {
                    const target = root.shownItem
                    if (target && target.desktopId && Services.DockService) {
                        Services.DockService.togglePin(target.desktopId)
                        Services.DockService.closeMenu()
                    }
                }
            }

            // ── 5. Running Windows List ──────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? 22 : 0
                implicitHeight: visible ? 22 : 0
                visible: Boolean(root.shownItem && root.shownItem.windows && root.shownItem.windows.length > 0)

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 2
                    text: "Open Windows (" + (root.shownItem && root.shownItem.windows ? root.shownItem.windows.length : 0) + ")"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    color: root.textTertiary
                }
            }

            Repeater {
                model: (root.shownItem && root.shownItem.windows) ? root.shownItem.windows : []
                delegate: Common.MenuRow {
                    required property var modelData
                    labelSize: Services.Theme.fontSizeXs
                    label: modelData.title || "Window"
                    emphasized: Boolean(Services.DockService && modelData.address === Services.DockService.activeWindowAddress)
                    onTriggered: {
                        if (Services.DockService) {
                            Services.DockService.focusWindow(modelData.address)
                            Services.DockService.closeMenu()
                        }
                    }
                }
            }

            // ── 6. Quit / Close All Windows (if running) ─────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? 1 : 0
                implicitHeight: visible ? 1 : 0
                Layout.topMargin: 3
                Layout.bottomMargin: 3
                Layout.leftMargin: 6
                Layout.rightMargin: 6
                color: root.menuDivider
                visible: Boolean(root.shownItem && root.shownItem.isRunning)
            }

            Common.MenuRow {
                visible: Boolean(root.shownItem && root.shownItem.isRunning)
                Layout.preferredHeight: visible ? 28 : 0
                glyph: Services.Icons.close || "✕"
                label: "Quit"
                onTriggered: {
                    const target = root.shownItem
                    if (Services.DockService) {
                        Services.DockService.closeMenu()
                        Services.DockService.closeApp(target)
                    }
                }
            }
        }
    }
}
