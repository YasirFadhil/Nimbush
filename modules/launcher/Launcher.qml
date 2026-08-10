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
    }
    function hide() {
        if (!isOpen) return
        isOpen = false
        hideTimer.restart()
    }
    function toggle() { isOpen ? hide() : show() }

    Timer {
        id: hideTimer; interval: 200
        onTriggered: { launcherWindow.visible = false; Services.Applications.query = "" }
    }

    // Klik di luar panel → tutup
    MouseArea {
        anchors.fill: parent
        onClicked: launcherWindow.hide()
    }

    // ── Panel ─────────────────────────────────────────────────────────
    Rectangle {
        id: panel
        anchors.centerIn: parent
        anchors.verticalCenterOffset: {
            if (!launcherWindow.isOpen) return 16          // animasi masuk dari bawah
            if (searchField.text.length > 0) return 0     // center saat searching
            return -90                                     // naik saat idle/kosong
        }
        Behavior on anchors.verticalCenterOffset {
            SmoothedAnimation { duration: 300; easing.type: Easing.OutQuint }
        }

        width: 520
        height: Math.min(listCol.implicitHeight, 480)
        Behavior on height {
            SmoothedAnimation { duration: 260; easing.type: Easing.OutQuint }
        }

        radius: 14
        color: Services.Theme.surface
        border.color: Services.Theme.border
        border.width: 1

        opacity: launcherWindow.isOpen ? 1 : 0
        scale:   launcherWindow.isOpen ? 1 : 0.97
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Behavior on scale   { NumberAnimation { duration: 260; easing.type: Easing.OutExpo } }

        MouseArea { anchors.fill: parent; onClicked: {} }

        ColumnLayout {
            id: listCol
            anchors { left: parent.left; right: parent.right; top: parent.top }
            spacing: 0

            // ── Search ────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16; Layout.rightMargin: 16
                Layout.topMargin: 14; Layout.bottomMargin: 12
                spacing: 10

                Text {
                    text: "\uf002"
                    font.family: "Symbols Nerd Font Mono"; font.pixelSize: 13
                    color: Services.Theme.textDisabled
                }

                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    background: null
                    color: Services.Theme.textPrimary
                    placeholderText: "Spotlight Search..."
                    placeholderTextColor: Services.Theme.textDisabled
                    font.pixelSize: 15
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
                            const app = resultList.model[resultList.currentIndex]
                            if (app) { app.execute(); launcherWindow.hide() }
                            event.accepted = true
                        } else if (event.key === Qt.Key_Escape) {
                            launcherWindow.hide(); event.accepted = true
                        }
                    }
                }
            }

            // Hairline divider — muncul saat ada teks
            Rectangle {
                Layout.fillWidth: true; height: 1
                color: Services.Theme.border
                opacity: searchField.text.length > 0 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }

            // ── List ──────────────────────────────────────────────────
            ListView {
                id: resultList
                Layout.fillWidth: true
                // Hanya tampil saat ada query
                Layout.preferredHeight: searchField.text.length > 0
                    ? Math.min(contentHeight, 420) : 0
                clip: true
                spacing: 0
                model: Services.Applications.filtered()
                currentIndex: 0
                keyNavigationEnabled: false
                topMargin: 6; bottomMargin: 6
                leftMargin: 6; rightMargin: 6

                highlight: Rectangle {
                    radius: 8; color: Services.Theme.surfaceVariant
                    x: 0; width: resultList.width
                }
                highlightMoveDuration: 130
                highlightResizeDuration: 0
                highlightMoveVelocity: -1

                delegate: Item {
                    id: appItem
                    required property var modelData
                    required property int index
                    width: resultList.width - 12
                    height: 44

                    RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: 14; rightMargin: 14
                        }
                        spacing: 10

                        // Icon
                        Item {
                            Layout.preferredWidth: 26; Layout.preferredHeight: 26
                            Layout.alignment: Qt.AlignVCenter

                            Rectangle {
                                anchors.fill: parent; radius: 6
                                color: Services.Theme.surfaceVariant
                                visible: ico.status !== Image.Ready
                                Text {
                                    anchors.centerIn: parent
                                    text: (appItem.modelData.name || "?").charAt(0).toUpperCase()
                                    color: Services.Theme.textDisabled
                                    font.pixelSize: 12; font.bold: true
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
                                visible: status === Image.Ready
                                smooth: true
                            }
                        }

                        // Name
                        Text {
                            text: appItem.modelData.name || ""
                            color: Services.Theme.textPrimary
                            font.pixelSize: 13
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    MouseArea {
                        anchors.fill: parent; hoverEnabled: true
                        onEntered: resultList.currentIndex = appItem.index
                        onClicked: { appItem.modelData.execute(); launcherWindow.hide() }
                    }
                }

                // Empty state
                Text {
                    anchors.centerIn: parent
                    text: "No results"
                    color: Services.Theme.textDisabled
                    font.pixelSize: 12
                    visible: resultList.count === 0
                }
            }
        }
    }
}
