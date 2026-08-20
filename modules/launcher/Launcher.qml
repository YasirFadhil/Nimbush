import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../services" as Services

PanelWindow {
    id: launcherWindow
    visible: false

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell:launcher"
    exclusiveZone: 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    Component.onCompleted: Services.OverlayManager.register(launcherWindow)

    property bool isOpen: false

    function show() {
        Services.OverlayManager.closeAllExcept(launcherWindow)
        hideTimer.stop()
        visible = true
        isOpen = true
        Services.Applications.query = ""
        searchField.text = ""
        searchField.forceActiveFocus()
        resultList.currentIndex = 0
        if (resultList.count > 0) {
            resultList.positionViewAtIndex(0, ListView.Beginning)
        }
    }

    function hide() {
        if (!isOpen) return
        isOpen = false
        hideTimer.restart()
    }

    function toggle() { isOpen ? hide() : show() }

    Timer {
        id: hideTimer
        interval: 220
        onTriggered: {
            launcherWindow.visible = false
            Services.Applications.query = ""
        }
    }

    // Click outside panel → close
    MouseArea {
        anchors.fill: parent
        onClicked: launcherWindow.hide()
    }

    // ── Panel ─────────────────────────────────────────────────────────
    Rectangle {
        id: panel
        anchors.centerIn: parent
        anchors.verticalCenterOffset: launcherWindow.isOpen ? -40 : -20

        Behavior on anchors.verticalCenterOffset {
            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
        }

        width: 520
        height: Math.min(listCol.implicitHeight, 460)

        Behavior on height {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }

        radius: 16
        color: Services.Theme.surface
        border.color: Services.Theme.border
        border.width: 1

        opacity: launcherWindow.isOpen ? 1 : 0
        scale: launcherWindow.isOpen ? 1 : 0.96

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
        }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: listCol
            anchors { left: parent.left; right: parent.right; top: parent.top }
            spacing: 0

            // ── Search Bar ────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16; Layout.rightMargin: 16
                Layout.topMargin: 14; Layout.bottomMargin: 12
                spacing: 10

                Text {
                    text: Services.Icons.search
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: Services.Theme.fontSize2xl
                    color: searchField.activeFocus ? Services.Theme.accent : Services.Theme.textDisabled
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    background: null
                    color: Services.Theme.textPrimary
                    placeholderText: "Search applications..."
                    placeholderTextColor: Services.Theme.textDisabled
                    font.pixelSize: Services.Theme.fontSize3xl
                    leftPadding: 0
                    rightPadding: 0

                    onTextChanged: {
                        Services.Applications.query = text
                        resultList.currentIndex = 0
                    }

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Down) {
                            resultList.currentIndex = Math.min(resultList.currentIndex + 1, resultList.count - 1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Up) {
                            resultList.currentIndex = Math.max(resultList.currentIndex - 1, 0)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            const apps = resultList.model
                            if (apps && apps.length > resultList.currentIndex) {
                                const app = apps[resultList.currentIndex]
                                if (app) { app.execute(); launcherWindow.hide() }
                            }
                            event.accepted = true
                        } else if (event.key === Qt.Key_Escape) {
                            launcherWindow.hide(); event.accepted = true
                        }
                    }
                }

                // Clear button
                Text {
                    text: "✕"
                    font.pixelSize: Services.Theme.fontSizeLg
                    color: clearMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textDisabled
                    visible: searchField.text.length > 0
                    Layout.alignment: Qt.AlignVCenter

                    MouseArea {
                        id: clearMouse
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        onClicked: {
                            searchField.text = ""
                            searchField.forceActiveFocus()
                        }
                    }
                }
            }

            // Hairline divider
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Services.Theme.border
                opacity: searchField.text.length > 0 ? 0.6 : 0

                Behavior on opacity {
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }
            }

            // ── List ──────────────────────────────────────────────────
            ListView {
                id: resultList
                Layout.fillWidth: true
                Layout.preferredHeight: searchField.text.length > 0 ? (count > 0 ? Math.min(contentHeight, 380) : 100) : 0
                opacity: searchField.text.length > 0 ? 1 : 0
                visible: opacity > 0
                clip: true
                spacing: 4
                model: Services.Applications.filteredApps
                currentIndex: 0
                keyNavigationEnabled: false
                topMargin: 4; bottomMargin: 4
                leftMargin: 8; rightMargin: 8

                Behavior on Layout.preferredHeight {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }

                delegate: Rectangle {
                    id: appItem
                    required property var modelData
                    required property int index
                    width: resultList.width - 16
                    height: 48
                    radius: 10

                    readonly property bool isCurrent: appItem.index === resultList.currentIndex

                    color: isCurrent 
                        ? Services.Theme.surfaceVariant 
                        : (hoverArea.containsMouse ? Services.Theme.bgHover : "transparent")
                    border.color: isCurrent ? Services.Theme.accent : "transparent"
                    border.width: isCurrent ? 1 : 0
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Behavior on border.color { ColorAnimation { duration: 100 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12; anchors.rightMargin: 12
                        spacing: 12

                        // App Icon
                        Item {
                            Layout.preferredWidth: 30; Layout.preferredHeight: 30
                            Layout.alignment: Qt.AlignVCenter

                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: appItem.index === resultList.currentIndex ? Qt.rgba(255, 255, 255, 0.1) : Qt.rgba(255, 255, 255, 0.05)
                                visible: ico.status !== Image.Ready

                                Text {
                                    anchors.centerIn: parent
                                    text: (appItem.modelData.name || "?").charAt(0).toUpperCase()
                                    color: appItem.index === resultList.currentIndex ? Services.Theme.accent : Services.Theme.textDisabled
                                    font.pixelSize: Services.Theme.fontSizeXl
                                    font.bold: true
                                }
                            }

                            Image {
                                id: ico
                                anchors.fill: parent
                                source: {
                                    const s = appItem.modelData.icon ?? ""
                                    if (!s) return ""
                                    if (s.startsWith("/") || s.startsWith("file://")) return s
                                    return Quickshell.iconPath(s, true)
                                }
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: true
                                sourceSize: Qt.size(32, 32)
                                visible: status === Image.Ready
                                smooth: true
                                mipmap: true
                            }
                        }

                        // App Name & Description
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 1

                            Text {
                                text: appItem.modelData.name || ""
                                color: appItem.index === resultList.currentIndex ? Services.Theme.accent : Services.Theme.textPrimary
                                font.pixelSize: Services.Theme.fontSizeXl
                                font.weight: appItem.index === resultList.currentIndex ? Font.Medium : Font.Normal
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            Text {
                                property string subText: appItem.modelData.description || appItem.modelData.comment || ""
                                text: (subText.length > 0 && subText !== appItem.modelData.name) ? subText : "Application"
                                color: Services.Theme.textSecondary
                                font.pixelSize: Services.Theme.fontSizeMd
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }

                    MouseArea {
                        id: hoverArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: {
                            if (resultList.currentIndex !== appItem.index) {
                                resultList.currentIndex = appItem.index
                            }
                        }
                        onClicked: {
                            appItem.modelData.execute()
                            launcherWindow.hide()
                        }
                    }
                }

                // Empty state
                Item {
                    anchors.fill: parent
                    visible: resultList.count === 0

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: Services.Icons.search
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: Services.Theme.fontSize8xl
                            color: Services.Theme.textDisabled
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Text {
                            text: "No applications found"
                            color: Services.Theme.textDisabled
                            font.pixelSize: Services.Theme.fontSizeXl
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
            }
        }
    }
}

