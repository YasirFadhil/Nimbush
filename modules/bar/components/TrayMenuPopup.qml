import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "../../../services" as Services

PanelWindow {
    id: root
    property string overlayId: "trayMenu"

    property var activeItem: null
    property var activeMenu: activeItem ? activeItem.menu : null
    property real targetX: parent ? parent.width - 150 : 0
    readonly property bool isBottom: Services.Config ? (Services.Config.barPosition === "bottom") : false

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusiveZone: 0
    visible: activeMenu !== null
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:traymenu"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    function openAt(item, xPos) {
        Services.OverlayManager.closeAllExcept(root)
        targetX = xPos
        activeItem = item
    }

    function close() {
        activeItem = null
    }
    function hide() { close() }

    Component.onCompleted: Services.OverlayManager.register(root)

    QsMenuOpener {
        id: menuOpener
        menu: root.activeMenu
    }

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
            implicitWidth: Math.max(180, menuColumn.implicitWidth + 24)
            implicitHeight: menuColumn.implicitHeight + 24
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
                id: menuColumn
                anchors.fill: parent
                anchors.margins: 12
                spacing: 4

                // Header with App Title
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.activeItem !== null && (root.activeItem.title || root.activeItem.id)
                    spacing: 8

                    IconImage {
                        Layout.preferredWidth: 16
                        Layout.preferredHeight: 16
                        source: root.activeItem ? (root.activeItem.icon || "") : ""
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.activeItem ? (root.activeItem.title || root.activeItem.id || "") : ""
                        font.family: Services.Theme.fontMono
                        font.pixelSize: Services.Theme.fontSizeLg
                        font.bold: true
                        color: Services.Theme.textSecondary
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Services.Theme.border
                    visible: root.activeItem !== null && (root.activeItem.title || root.activeItem.id)
                }

                // Menu Items
                Repeater {
                    model: menuOpener.children

                    Item {
                        id: menuItem
                        required property var modelData
                        required property int index
                        property bool expanded: false

                        Layout.fillWidth: true
                        Layout.preferredHeight: modelData.isSeparator ? 9 : (30 + (expanded && subMenuOpener.children ? subMenuColumn.implicitHeight + 4 : 0))

                        Behavior on Layout.preferredHeight { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                        QsMenuOpener {
                            id: subMenuOpener
                            menu: menuItem.modelData.hasChildren && menuItem.expanded ? menuItem.modelData : null
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 4

                            // Separator Line
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 1
                                Layout.alignment: Qt.AlignVCenter
                                color: Services.Theme.border
                                visible: menuItem.modelData.isSeparator
                            }

                            // Main Entry Row
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                visible: !menuItem.modelData.isSeparator
                                radius: Services.Theme.radiusSm
                                color: itemMouseArea.containsMouse && menuItem.modelData.enabled ? Services.Theme.surfaceVariant : "transparent"
                                border.color: itemMouseArea.containsMouse && menuItem.modelData.enabled ? Services.Theme.borderHighlight : "transparent"
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 8

                                    // Checkbox / Radio state icon
                                    Text {
                                        visible: menuItem.modelData.buttonType !== 0
                                        text: menuItem.modelData.checkState === 2 ? "✓" : " "
                                        font.family: Services.Theme.fontMono
                                        font.pixelSize: Services.Theme.fontSizeLg
                                        font.bold: true
                                        color: Services.Theme.accent
                                    }

                                    // Entry Icon
                                    IconImage {
                                        visible: menuItem.modelData.icon && menuItem.modelData.icon.length > 0
                                        Layout.preferredWidth: 14
                                        Layout.preferredHeight: 14
                                        source: menuItem.modelData.icon || ""
                                    }

                                    // Entry Label
                                    Text {
                                        Layout.fillWidth: true
                                        text: menuItem.modelData.text ? menuItem.modelData.text.replace(/&/g, "") : ""
                                        font.family: Services.Theme.fontMono
                                        font.pixelSize: Services.Theme.fontSizeLg
                                        color: menuItem.modelData.enabled ? Services.Theme.textPrimary : Services.Theme.textDisabled
                                        elide: Text.ElideRight
                                    }

                                    // Submenu Arrow
                                    Text {
                                        visible: menuItem.modelData.hasChildren
                                        text: "›"
                                        font.family: Services.Theme.fontMono
                                        font.pixelSize: Services.Theme.fontSize2xl
                                        color: Services.Theme.textSecondary
                                        rotation: menuItem.expanded ? 90 : 0
                                        Behavior on rotation { NumberAnimation { duration: 150 } }
                                    }
                                }

                                MouseArea {
                                    id: itemMouseArea
                                    anchors.fill: parent
                                    enabled: menuItem.modelData.enabled
                                    hoverEnabled: true
                                    cursorShape: menuItem.modelData.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        if (menuItem.modelData.hasChildren) {
                                            menuItem.expanded = !menuItem.expanded
                                        } else {
                                            menuItem.modelData.triggered()
                                            root.close()
                                        }
                                    }
                                }
                            }

                            // Submenu Items (Expanded Inline)
                            ColumnLayout {
                                id: subMenuColumn
                                Layout.fillWidth: true
                                Layout.leftMargin: 12
                                visible: menuItem.expanded && subMenuOpener.children !== null
                                spacing: 2

                                Repeater {
                                    model: subMenuOpener.children

                                    Item {
                                        id: subItem
                                        required property var modelData
                                        required property int index

                                        Layout.fillWidth: true
                                        Layout.preferredHeight: modelData.isSeparator ? 9 : 28

                                        // Separator Line for Submenu
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: parent.width
                                            height: 1
                                            color: Services.Theme.border
                                            visible: subItem.modelData.isSeparator
                                        }

                                        // Submenu Entry Row
                                        Rectangle {
                                            anchors.fill: parent
                                            visible: !subItem.modelData.isSeparator
                                            radius: Services.Theme.radiusSm
                                            color: subItemMouseArea.containsMouse && subItem.modelData.enabled ? Services.Theme.surfaceVariant : "transparent"
                                            border.color: subItemMouseArea.containsMouse && subItem.modelData.enabled ? Services.Theme.borderHighlight : "transparent"
                                            border.width: 1

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 6
                                                anchors.rightMargin: 6
                                                spacing: 6

                                                Text {
                                                    visible: subItem.modelData.buttonType !== 0
                                                    text: subItem.modelData.checkState === 2 ? "✓" : " "
                                                    font.family: Services.Theme.fontMono
                                                    font.pixelSize: Services.Theme.fontSizeMd
                                                    font.bold: true
                                                    color: Services.Theme.accent
                                                }

                                                IconImage {
                                                    visible: subItem.modelData.icon && subItem.modelData.icon.length > 0
                                                    Layout.preferredWidth: 12
                                                    Layout.preferredHeight: 12
                                                    source: subItem.modelData.icon || ""
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: subItem.modelData.text ? subItem.modelData.text.replace(/&/g, "") : ""
                                                    font.family: Services.Theme.fontMono
                                                    font.pixelSize: Services.Theme.fontSizeMd
                                                    color: subItem.modelData.enabled ? Services.Theme.textPrimary : Services.Theme.textDisabled
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            MouseArea {
                                                id: subItemMouseArea
                                                anchors.fill: parent
                                                enabled: subItem.modelData.enabled
                                                hoverEnabled: true
                                                cursorShape: subItem.modelData.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: {
                                                    subItem.modelData.triggered()
                                                    root.close()
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
}
