import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import "../../../services" as Services

PanelWindow {
    id: root
    property string overlayId: "trayOverflow"
    property var trayMenuPopup: null
    property real targetX: parent ? parent.width - 200 : 0
    readonly property bool isBottom: Services.Config ? (Services.Config.barPosition === "bottom") : false

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusiveZone: 0
    visible: false
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:trayoverflow"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    property int maxVisibleCount: 2

    readonly property var hiddenItems: {
        const items = SystemTray.items.values || []
        return items.length > root.maxVisibleCount ? items.slice(root.maxVisibleCount) : []
    }

    function openAt(xPos) {
        Services.OverlayManager.closeAllExcept(root)
        targetX = xPos
        visible = true
    }

    function close() {
        visible = false
    }
    function hide() { close() }

    Component.onCompleted: Services.OverlayManager.register(root)

    Item {
        id: escFocus
        focus: root.visible
        Keys.onEscapePressed: root.close()
    }

    // Backdrop: clicking anywhere outside closes the popup
    MouseArea {
        anchors.fill: parent
        onClicked: root.close()

        Rectangle {
            id: popupCard
            y: root.isBottom ? (parent.height - height - 12) : 12
            x: Math.max(12, Math.min(parent.width - width - 12, root.targetX - (width / 2)))
            implicitWidth: Math.max(200, contentColumn.implicitWidth + 24)
            implicitHeight: contentColumn.implicitHeight + 24
            radius: Services.Theme.radiusLg
            color: Services.Theme.bgElevated
            border.color: Services.Theme.border
            border.width: 1
            clip: true

            opacity: root.visible ? 1 : 0
            transform: Translate {
                y: root.visible ? 0 : (root.isBottom ? 24 : -24)
                Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 0.5 } }
            }
            scale: root.visible ? 1 : 0.96
            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            // Prevent clicks inside card from closing backdrop
            MouseArea { anchors.fill: parent; onClicked: {} }

            ColumnLayout {
                id: contentColumn
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "󰍹"
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: Services.Theme.fontSizeXl
                        color: Services.Theme.accent
                    }

                    Text {
                        text: "System Tray"
                        font.family: Services.Theme.fontMono
                        font.pixelSize: Services.Theme.fontSizeLg
                        font.bold: true
                        color: Services.Theme.textPrimary
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        implicitWidth: badgeText.implicitWidth + 10
                        implicitHeight: 18
                        radius: 9
                        color: Services.Theme.surfaceVariant

                        Text {
                            id: badgeText
                            anchors.centerIn: parent
                            text: root.hiddenItems.length + " hidden"
                            font.family: Services.Theme.fontMono
                            font.pixelSize: Services.Theme.fontSizeSm
                            color: Services.Theme.textSecondary
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Services.Theme.border
                }

                // Hidden Tray Items List
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Repeater {
                        model: root.hiddenItems

                        Item {
                            id: overflowItem
                            required property var modelData
                            property var item: modelData

                            Layout.fillWidth: true
                            Layout.preferredHeight: 32

                            QsMenuAnchor {
                                id: menuAnchor
                                menu: overflowItem.item.menu
                                anchor.item: itemBg
                            }

                            Rectangle {
                                id: itemBg
                                anchors.fill: parent
                                radius: Services.Theme.radiusSm
                                color: itemArea.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                                border.color: itemArea.containsMouse ? Services.Theme.borderHighlight : "transparent"
                                border.width: 1

                                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 8

                                    Image {
                                        id: itemImg
                                        Layout.preferredWidth: 18
                                        Layout.preferredHeight: 18
                                        source: {
                                            const icon = overflowItem.item.icon || ""
                                            if (!icon) return ""
                                            if (Services.SystemTheme) {
                                                const res = Services.SystemTheme.getIcon(icon)
                                                if (res && res.length > 0) return res
                                            }
                                            if (icon.startsWith("file://") || icon.startsWith("http") || icon.startsWith("image://"))
                                                return icon
                                            if (icon.startsWith("/"))
                                                return "file://" + icon
                                            const qp = Quickshell.iconPath(icon, false)
                                            return (qp && qp.startsWith("/")) ? ("file://" + qp) : (qp || "")
                                        }
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                        cache: true
                                        sourceSize: Qt.size(36, 36)
                                        visible: status === Image.Ready && source.toString().length > 0
                                    }

                                    Text {
                                        visible: !itemImg.visible
                                        text: "󰍹"
                                        font.family: Services.Theme.fontMono
                                        font.pixelSize: Services.Theme.fontSizeLg
                                        color: Services.Theme.textSecondary
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: overflowItem.item.title || overflowItem.item.id || "Tray App"
                                        font.family: Services.Theme.fontMono
                                        font.pixelSize: Services.Theme.fontSizeMd
                                        color: Services.Theme.textPrimary
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    id: itemArea
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => {
                                        const iconCenterX = itemBg.mapToItem(null, itemBg.width / 2, 0).x
                                        const toggleMenu = () => {
                                            if (root.trayMenuPopup) {
                                                root.trayMenuPopup.openAt(overflowItem.item, iconCenterX)
                                            } else {
                                                menuAnchor.open()
                                            }
                                        }

                                        if (mouse.button === Qt.RightButton) {
                                            if (overflowItem.item.hasMenu && overflowItem.item.menu) {
                                                toggleMenu()
                                            } else if (overflowItem.item.secondaryActivate) {
                                                overflowItem.item.secondaryActivate()
                                            } else if (overflowItem.item.activate) {
                                                overflowItem.item.activate()
                                            }
                                        } else if (mouse.button === Qt.MiddleButton) {
                                            if (overflowItem.item.secondaryActivate) {
                                                overflowItem.item.secondaryActivate()
                                            } else if (overflowItem.item.activate) {
                                                overflowItem.item.activate()
                                            }
                                        } else {
                                            if (overflowItem.item.onlyMenu && overflowItem.item.hasMenu && overflowItem.item.menu) {
                                                toggleMenu()
                                            } else if (overflowItem.item.activate) {
                                                overflowItem.item.activate()
                                            } else if (overflowItem.item.hasMenu && overflowItem.item.menu) {
                                                toggleMenu()
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
}
