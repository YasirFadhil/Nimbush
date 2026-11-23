import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../../services" as Services
import "../../common" as Common

PanelWindow {
    id: root
    property string overlayId: "appMenu"

    property bool isOpen: false
    property var activeMenuData: null
    property real targetX: 20
    property bool isFallback: false

    readonly property bool isBottom: Services.Config ? (Services.Config.barPosition === "bottom") : false
    readonly property int barTotalHeight: Services.Config ? (Services.Config.barStyle === "minimal" ? 30 : (Services.Config.barStyle === "unified" ? 38 : (Services.Config.barStyle === "floating" ? 46 : 36))) : 36

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusiveZone: 0
    visible: isOpen || (popupCard && popupCard.opacity > 0.01)
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:appmenu"
    WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    mask: Region {
        Region {
            x: 0
            y: root.isBottom ? 0 : root.barTotalHeight
            width: root.width
            height: root.height - root.barTotalHeight
        }
    }

    // Active submenu state
    property var activeSubmenuItem: null
    property real activeSubmenuY: 12

    // ── macOS Menu Material Tokens (Matching DockMenu.qml) ───────────────────
    readonly property bool dark: Services.Theme.isDark
    readonly property color menuFill: dark ? Qt.rgba(0.14, 0.14, 0.15, 0.80) : Qt.rgba(1, 1, 1, 0.88)
    readonly property color menuBorder: dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.14)
    readonly property color menuSpecular: dark ? Qt.rgba(1, 1, 1, 0.24) : Qt.rgba(1, 1, 1, 0.80)
    readonly property color menuDivider: dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.14)
    readonly property color textPrimary: dark ? Qt.rgba(1, 1, 1, 0.97) : Qt.rgba(0, 0, 0, 0.90)
    readonly property color textSecondary: dark ? Qt.rgba(1, 1, 1, 0.75) : Qt.rgba(0, 0, 0, 0.65)
    readonly property color textTertiary: dark ? Qt.rgba(1, 1, 1, 0.52) : Qt.rgba(0, 0, 0, 0.45)

    function getAppIcon() {
        if (!Services.ActiveApp) return ""
        if (Services.ActiveApp.icon && Services.ActiveApp.icon.length > 0) {
            return Services.ActiveApp.icon
        }
        var raw = Services.ActiveApp.windowClass || ""
        if (!raw) return ""
        if (Services.SystemTheme) {
            var res = Services.SystemTheme.getIcon(raw)
            if (res && res.length > 0) return res
        }
        var qp = Quickshell.iconPath(raw, true)
        return (qp && qp.startsWith("/")) ? ("file://" + qp) : (qp || "")
    }

    function handleStandardAction(type) {
        if (!type) return
        switch (type) {
            case "closeWindow":
                if (Services.Compositor) Services.Compositor.dispatch("close")
                break
            case "quitApp":
                if (Services.Compositor) Services.Compositor.dispatch("quit")
                break
            case "fullscreen":
                if (Services.Compositor) Services.Compositor.dispatch("fullscreen")
                break
            case "float":
                if (Services.Compositor) Services.Compositor.dispatch("float")
                break
            case "center":
                if (Services.Compositor) Services.Compositor.dispatch("center")
                break
            case "minimize":
                if (Services.Compositor) Services.Compositor.dispatch("minimize")
                break
            case "nextWindow":
                if (Services.Compositor) Services.Compositor.dispatch("cyclenext")
                break
            case "pin":
                if (Services.Compositor) Services.Compositor.dispatch("pin")
                break
            case "cut":
                if (Services.Compositor) Services.Compositor.sendKey("x", ["ctrl"])
                break
            case "copy":
                if (Services.Compositor) Services.Compositor.sendKey("c", ["ctrl"])
                break
            case "paste":
                if (Services.Compositor) Services.Compositor.sendKey("v", ["ctrl"])
                break
            case "selectAll":
                if (Services.Compositor) Services.Compositor.sendKey("a", ["ctrl"])
                break
            case "newWindow":
                if (Services.ActiveApp && Services.ActiveApp.windowClass) {
                    var proc = Qt.createQmlObject('import Quickshell.Io; Process {}', root)
                    proc.command = ["hyprctl", "dispatch", "hl.dsp.exec_cmd('" + Services.ActiveApp.windowClass + "')"]
                    proc.onExited.connect(() => proc.destroy())
                    proc.running = true
                }
                break
            case "keybinds":
                if (Services.OverlayManager) Services.OverlayManager.dashboardToggleRequested()
                break
            case "aboutApp":
                break
        }
    }

    function openAt(menuData, xPos, fallback) {
        if (Services.OverlayManager) Services.OverlayManager.closeAllExcept(root)
        activeMenuData = menuData
        targetX = Math.max(12, xPos)
        isFallback = Boolean(fallback)
        activeSubmenuItem = null
        isOpen = true
    }

    function close() {
        isOpen = false
        activeSubmenuItem = null
    }

    function hide() { close() }

    Component.onCompleted: {
        if (Services.OverlayManager) Services.OverlayManager.register(root)
    }

    Item {
        id: escFocus
        focus: root.isOpen
        Keys.onEscapePressed: root.close()
    }

    // Dismiss on outside click
    MouseArea {
        anchors.fill: parent
        enabled: root.isOpen
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: root.close()

        // ── Main Popup Card ──────────────────────────────────────────────────
        Rectangle {
            id: popupCard
            x: Math.max(12, Math.min(parent.width - width - 12, root.targetX))
            y: root.isBottom ? (parent.height - height - 12) : 12
            width: Math.max(224, menuColumn.implicitWidth + 12)
            height: menuColumn.implicitHeight + 12
            radius: 11
            color: root.menuFill
            border.color: root.menuBorder
            border.width: 1

            // Smooth macOS entry animation
            scale: root.isOpen ? 1.0 : 0.96
            opacity: root.isOpen ? 1.0 : 0.0
            transformOrigin: root.isBottom ? Item.Bottom : Item.Top
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 120 } }

            // Prevent backdrop click inside card
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: (mouse) => mouse.accepted = true
            }

            ColumnLayout {
                id: menuColumn
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 6
                spacing: 2

                // ── Case 1: Real AT-SPI or Standard Fallback Menu Items ──────
                Repeater {
                    model: (!root.isFallback && root.activeMenuData && root.activeMenuData.children) ? root.activeMenuData.children : []
                    delegate: Item {
                        id: itemDelegate
                        required property var modelData
                        property var item: modelData
                        readonly property bool isSep: Boolean(item.separator || item.role === "separator" || item.label === "-")
                        readonly property bool hasKids: Boolean(item.children && item.children.length > 0)

                        Layout.fillWidth: true
                        Layout.preferredHeight: isSep ? 7 : 28
                        implicitHeight: Layout.preferredHeight

                        // Separator line (Identical to DockMenu.qml)
                        Rectangle {
                            visible: itemDelegate.isSep
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            height: 1
                            color: root.menuDivider
                        }

                        // Menu Row (Shared Common.MenuRow)
                        Common.MenuRow {
                            visible: !itemDelegate.isSep
                            anchors.fill: parent
                            label: itemDelegate.item.label || ""
                            shortcut: itemDelegate.item.shortcut || ""
                            enabled: itemDelegate.item.enabled !== false
                            hasSubmenu: itemDelegate.hasKids
                            glyph: itemDelegate.item.checked ? "\uf00c" : "" // checkmark

                            onHoveredChanged: {
                                if (hovered && itemDelegate.hasKids) {
                                    root.activeSubmenuItem = itemDelegate.item
                                    root.activeSubmenuY = popupCard.y + itemDelegate.y
                                }
                            }

                            onTriggered: {
                                if (itemDelegate.hasKids) {
                                    root.activeSubmenuItem = itemDelegate.item
                                    root.activeSubmenuY = popupCard.y + itemDelegate.y
                                } else {
                                    if (itemDelegate.item.actionType) {
                                        root.handleStandardAction(itemDelegate.item.actionType)
                                    } else if (itemDelegate.item.path && Services.AppMenu) {
                                        Services.AppMenu.trigger(itemDelegate.item.path)
                                    }
                                    root.close()
                                }
                            }
                        }
                    }
                }

                // ── Case 2: App Name Pill Dropdown (Identical to DockMenu.qml Header) ─
                ColumnLayout {
                    visible: root.isFallback
                    Layout.fillWidth: true
                    spacing: 2

                    // ── 1. App Header (Matching DockMenu.qml Lines 150-252) ──
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
                                    text: ((Services.ActiveApp && Services.ActiveApp.appName) ? Services.ActiveApp.appName : "?").charAt(0).toUpperCase()
                                    color: root.textPrimary
                                    font.pixelSize: 13
                                    font.bold: true
                                }
                            }

                            Image {
                                id: menuAppImg
                                anchors.fill: parent
                                source: {
                                    var raw = root.getAppIcon()
                                    if (!raw) return ""
                                    if (raw.startsWith("file://") || raw.startsWith("http://") || raw.startsWith("https://")) return raw
                                    if (raw.startsWith("/")) return "file://" + raw
                                    var s = raw.startsWith("image://icon/") ? raw.substring(13) : raw
                                    if (s.startsWith("image://")) return s
                                    var qp = Quickshell.iconPath(s, true)
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
                                text: (Services.ActiveApp && Services.ActiveApp.appName) ? Services.ActiveApp.appName : "Application"
                                font.pixelSize: Services.Theme.fontSizeMd
                                font.weight: Font.DemiBold
                                color: root.textPrimary
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                visible: Boolean(Services.ActiveApp && Services.ActiveApp.hasWindow)

                                Rectangle {
                                    width: 5
                                    height: 5
                                    radius: 2.5
                                    color: (Services.ActiveApp && Services.ActiveApp.hasWindow) ? Services.Theme.accent : root.textSecondary
                                }

                                Text {
                                    text: (Services.ActiveApp && Services.ActiveApp.hasWindow) ? "Active Window" : "Desktop"
                                    font.pixelSize: 10
                                    color: root.textSecondary
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    // Divider (Identical to DockMenu.qml)
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

                    // Window Control Actions
                    Common.MenuRow {
                        glyph: "\uf2d1" // minimize
                        label: "Minimize Window"
                        shortcut: "Super+H"
                        onTriggered: {
                            root.close()
                            if (Services.Compositor) Services.Compositor.dispatch("minimize")
                        }
                    }

                    Common.MenuRow {
                        glyph: (Services.ActiveApp && Services.ActiveApp.isFullscreen) ? "\uf066" : "\uf2d0"
                        label: (Services.ActiveApp && Services.ActiveApp.isFullscreen) ? "Exit Fullscreen" : "Fullscreen"
                        shortcut: "Super+F"
                        onTriggered: {
                            root.close()
                            if (Services.Compositor) Services.Compositor.dispatch("fullscreen")
                        }
                    }

                    Common.MenuRow {
                        glyph: "\uf0b2" // float
                        label: (Services.ActiveApp && Services.ActiveApp.isFloating) ? "Tile Window" : "Float Window"
                        shortcut: "Super+T"
                        onTriggered: {
                            root.close()
                            if (Services.Compositor) Services.Compositor.dispatch("float")
                        }
                    }

                    Common.MenuRow {
                        glyph: "\uf047" // center
                        label: "Center Window"
                        onTriggered: {
                            root.close()
                            if (Services.Compositor) Services.Compositor.dispatch("center")
                        }
                    }

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

                    Common.MenuRow {
                        glyph: "\uf00d" // close
                        label: "Close Window"
                        shortcut: "Super+Q"
                        onTriggered: {
                            root.close()
                            if (Services.Compositor) Services.Compositor.dispatch("close")
                        }
                    }

                    Common.MenuRow {
                        glyph: "\uf011" // quit
                        label: "Quit " + (Services.ActiveApp ? Services.ActiveApp.appName : "App")
                        shortcut: "Super+Shift+Q"
                        onTriggered: {
                            root.close()
                            if (Services.Compositor) Services.Compositor.dispatch("quit")
                        }
                    }
                }
            }
        }

        // ── Submenu Popup Card (Cascading, Identical Styling) ────────────────
        Rectangle {
            id: submenuCard
            visible: Boolean(root.activeSubmenuItem && root.activeSubmenuItem.children && root.activeSubmenuItem.children.length > 0)
            x: Math.min(parent.width - width - 12, popupCard.x + popupCard.width + 4)
            y: Math.max(12, Math.min(parent.height - height - 12, root.activeSubmenuY))
            width: Math.max(200, submenuColumn.implicitWidth + 12)
            height: submenuColumn.implicitHeight + 12
            radius: 11
            color: root.menuFill
            border.color: root.menuBorder
            border.width: 1

            scale: submenuCard.visible ? 1.0 : 0.96
            opacity: submenuCard.visible ? 1.0 : 0.0
            transformOrigin: Item.TopLeft
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 120 } }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: (mouse) => mouse.accepted = true
            }

            ColumnLayout {
                id: submenuColumn
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 6
                spacing: 2

                Repeater {
                    model: (root.activeSubmenuItem && root.activeSubmenuItem.children) ? root.activeSubmenuItem.children : []
                    delegate: Item {
                        id: subItemDelegate
                        required property var modelData
                        property var item: modelData
                        readonly property bool isSep: Boolean(item.separator || item.role === "separator" || item.label === "-")

                        Layout.fillWidth: true
                        Layout.preferredHeight: isSep ? 7 : 28
                        implicitHeight: Layout.preferredHeight

                        Rectangle {
                            visible: subItemDelegate.isSep
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            height: 1
                            color: root.menuDivider
                        }

                        Common.MenuRow {
                            visible: !subItemDelegate.isSep
                            anchors.fill: parent
                            label: subItemDelegate.item.label || ""
                            shortcut: subItemDelegate.item.shortcut || ""
                            enabled: subItemDelegate.item.enabled !== false
                            glyph: subItemDelegate.item.checked ? "\uf00c" : ""

                            onTriggered: {
                                if (subItemDelegate.item.actionType) {
                                    root.handleStandardAction(subItemDelegate.item.actionType)
                                } else if (subItemDelegate.item.path && Services.AppMenu) {
                                    Services.AppMenu.trigger(subItemDelegate.item.path)
                                }
                                root.close()
                            }
                        }
                    }
                }
            }
        }
    }
}
