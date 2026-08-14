import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import "../../../services" as Services

Rectangle {
    id: trayPill
    property var trayMenuPopup: null
    implicitHeight: 28
    implicitWidth: trayLayout.implicitWidth + 16
    radius: 14
    color: Services.Theme.surface
    border.color: Services.Theme.border
    border.width: 1
    visible: SystemTray.items.values.length > 0

    RowLayout {
        id: trayLayout
        anchors.centerIn: parent
        spacing: 4

        Repeater {
            model: SystemTray.items.values

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

                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                }

                IconImage {
                    id: trayImg
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    source: trayItem.item.icon || ""
                }

                Text {
                    anchors.centerIn: parent
                    visible: !trayImg.visible || trayImg.status === Image.Error
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
    }
}
