import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import "../../../services" as Services

Rectangle {
    id: trayPill
    property var trayMenuPopup: null
    property var trayOverflowPopup: null
    property int maxVisibleCount: 2

    readonly property var allItems: SystemTray.items.values || []
    readonly property bool hasOverflow: allItems.length > maxVisibleCount
    readonly property var visibleItems: hasOverflow ? allItems.slice(0, maxVisibleCount) : allItems

    implicitHeight: 28
    implicitWidth: trayLayout.implicitWidth + 16
    radius: 14
    color: Services.Theme.surface
    border.color: Services.Theme.border
    border.width: 1
    visible: allItems.length > 0

    RowLayout {
        id: trayLayout
        anchors.centerIn: parent
        spacing: 4

        // Visible Tray Icons (Max 3)
        Repeater {
            model: trayPill.visibleItems

            Item {
                id: trayItem
                required property var modelData
                property var item: modelData

                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                Layout.alignment: Qt.AlignVCenter

                QsMenuAnchor {
                    id: menuAnchor
                    menu: trayItem.item.menu
                    anchor.item: itemArea
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
                }

                Image {
                    id: trayImg
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    source: {
                        const icon = trayItem.item.icon || ""
                        if (!icon) return ""
                        if (icon.startsWith("/") || icon.startsWith("file://") || icon.startsWith("http") || icon.startsWith("image://"))
                            return icon
                        return Quickshell.iconPath(icon, true)
                    }
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    sourceSize: Qt.size(32, 32)
                    visible: status === Image.Ready
                }

                Text {
                    anchors.centerIn: parent
                    visible: !trayImg.visible
                    text: "󰍹"
                    font.family: Services.Theme.fontMono
                    font.pixelSize: Services.Theme.fontSizeLg
                    color: Services.Theme.textSecondary
                }

                MouseArea {
                    id: itemArea
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        const iconCenterX = itemArea.mapToItem(null, itemArea.width / 2, 0).x
                        const toggleTrayMenu = (item) => {
                            if (trayPill.trayMenuPopup) {
                                if (trayPill.trayMenuPopup.activeItem === item) {
                                    trayPill.trayMenuPopup.close()
                                } else {
                                    trayPill.trayMenuPopup.openAt(item, iconCenterX)
                                }
                            } else {
                                menuAnchor.open()
                            }
                        }

                        if (mouse.button === Qt.RightButton) {
                            if (trayItem.item.hasMenu && trayItem.item.menu) {
                                toggleTrayMenu(trayItem.item)
                            } else if (trayItem.item.secondaryActivate) {
                                trayItem.item.secondaryActivate()
                            } else if (trayItem.item.activate) {
                                trayItem.item.activate()
                            }
                        } else if (mouse.button === Qt.MiddleButton) {
                            if (trayItem.item.secondaryActivate) {
                                trayItem.item.secondaryActivate()
                            } else if (trayItem.item.activate) {
                                trayItem.item.activate()
                            }
                        } else {
                            if (trayItem.item.onlyMenu && trayItem.item.hasMenu && trayItem.item.menu) {
                                toggleTrayMenu(trayItem.item)
                            } else if (trayItem.item.activate) {
                                trayItem.item.activate()
                            } else if (trayItem.item.hasMenu && trayItem.item.menu) {
                                toggleTrayMenu(trayItem.item)
                            }
                        }
                    }
                }
            }
        }

        // Overflow Button (Shows when > 3 items)
        Item {
            visible: trayPill.hasOverflow
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            Layout.alignment: Qt.AlignVCenter

            Rectangle {
                id: overflowBg
                anchors.fill: parent
                radius: Services.Theme.radiusSm
                color: overflowArea.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                border.color: overflowArea.containsMouse ? Services.Theme.borderHighlight : "transparent"
                border.width: 1

                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
            }

            Text {
                anchors.centerIn: parent
                text: "󰅀"
                font.family: Services.Theme.fontMono
                font.pixelSize: Services.Theme.fontSizeXl
                color: overflowArea.containsMouse ? Services.Theme.accent : Services.Theme.textSecondary
                rotation: trayPill.trayOverflowPopup && trayPill.trayOverflowPopup.visible ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: 150 } }
            }

            MouseArea {
                id: overflowArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (trayPill.trayOverflowPopup) {
                        if (trayPill.trayOverflowPopup.visible) {
                            trayPill.trayOverflowPopup.close()
                        } else {
                            const buttonCenterX = overflowBg.mapToItem(null, overflowBg.width / 2, 0).x
                            trayPill.trayOverflowPopup.openAt(buttonCenterX)
                        }
                    }
                }
            }
        }
    }
}
