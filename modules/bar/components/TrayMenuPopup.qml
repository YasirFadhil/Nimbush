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

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusiveZone: 0
    visible: activeMenu !== null
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:traymenu"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    function openAt(item, xPos) {
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
            anchors.top: parent.top
            // anchors.topMargin: 40
            x: Math.max(12, Math.min(parent.width - width - 12, root.targetX - (width / 2)))
            implicitWidth: Math.max(180, menuColumn.implicitWidth + 24)
            implicitHeight: menuColumn.implicitHeight + 24
            radius: Services.Theme.radiusLg
            color: Services.Theme.bgElevated
            border.color: Services.Theme.border
            border.width: 1
            clip: true

            opacity: root.visible ? 1 : 0
            scale: root.visible ? 1 : 0.95
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

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
                        font.family: "Liga SFMono Nerd Font"
                        font.pixelSize: 12
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

                        Layout.fillWidth: true
                        Layout.preferredHeight: modelData.isSeparator ? 9 : 30

                        // Separator Line
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width
                            height: 1
                            color: Services.Theme.border
                            visible: menuItem.modelData.isSeparator
                        }

                        // Regular Menu Entry
                        Rectangle {
                            anchors.fill: parent
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
                                    font.family: "Liga SFMono Nerd Font"
                                    font.pixelSize: 12
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
                                    font.family: "Liga SFMono Nerd Font"
                                    font.pixelSize: 12
                                    color: menuItem.modelData.enabled ? Services.Theme.textPrimary : Services.Theme.textDisabled
                                    elide: Text.ElideRight
                                }

                                // Submenu Arrow
                                Text {
                                    visible: menuItem.modelData.hasChildren
                                    text: "›"
                                    font.family: "Liga SFMono Nerd Font"
                                    font.pixelSize: 14
                                    color: Services.Theme.textSecondary
                                }
                            }

                            MouseArea {
                                id: itemMouseArea
                                anchors.fill: parent
                                enabled: menuItem.modelData.enabled
                                hoverEnabled: true
                                cursorShape: menuItem.modelData.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    menuItem.modelData.triggered()
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
