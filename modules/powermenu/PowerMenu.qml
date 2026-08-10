import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../services" as Services

PanelWindow {
    id: root

    property bool menuVisible: false
    property int selectedIndex: 0

    readonly property var actions: [
        { label: "Lock",      icon: "\u{f033e}", proc: lockProc },
        { label: "Logout",    icon: "\u{f0343}", proc: logoutProc },
        { label: "Sleep",     icon: "\u{f04b2}", proc: sleepProc },
        { label: "Reboot",    icon: "\u{f0709}", proc: rebootProc },
        { label: "Power Off", icon: "\u{f0425}", proc: shutdownProc }
    ]

    function open() {
        Services.OverlayManager.closeAllExcept(root)
        menuVisible = true
        selectedIndex = 0
        keyFocus.forceActiveFocus()
    }
    function close() {
        menuVisible = false
    }
    function hide() {
        close()
    }
    function show() {
        open()
    }

    visible: menuVisible

    Component.onCompleted: {
        Services.OverlayManager.register(root)
    }

    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    anchors { top: true; bottom: true; left: true; right: true }

    // Keyboard handler
    Item {
        id: keyFocus
        focus: root.menuVisible
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                selectedIndex = Math.max(selectedIndex - 1, 0)
                event.accepted = true
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                selectedIndex = Math.min(selectedIndex + 1, root.actions.length - 1)
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.actions[selectedIndex].proc.running = true
                root.close()
                event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
                root.close()
                event.accepted = true
            } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_5) {
                selectedIndex = event.key - Qt.Key_1
                root.actions[selectedIndex].proc.running = true
                root.close()
                event.accepted = true
            }
        }
    }

    // backdrop buat klik-luar nutup, sama kayak Center.qml
    MouseArea {
        anchors.fill: parent
        onClicked: root.close()

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: 420
            height: 120
            radius: Services.Theme.radiusMd
            color: Services.Theme.surface
            border.color: Services.Theme.border
            border.width: 1

            // biar klik di dalem card gak nembus ke backdrop
            MouseArea {
                anchors.fill: parent
                onClicked: {}
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                PowerButton {
                    label: root.actions[0].label; icon: root.actions[0].icon; btnIndex: 0
                    onClicked: { root.close(); lockProc.running = true }
                }
                PowerButton {
                    label: root.actions[1].label; icon: root.actions[1].icon; btnIndex: 1
                    onClicked: { root.close(); logoutProc.running = true }
                }
                PowerButton {
                    label: root.actions[2].label; icon: root.actions[2].icon; btnIndex: 2
                    onClicked: { root.close(); sleepProc.running = true }
                }
                PowerButton {
                    label: root.actions[3].label; icon: root.actions[3].icon; btnIndex: 3
                    onClicked: { root.close(); rebootProc.running = true }
                }
                PowerButton {
                    label: root.actions[4].label; icon: root.actions[4].icon; btnIndex: 4
                    onClicked: { root.close(); shutdownProc.running = true }
                }
            }
        }
    }

    // === actions ===
    Process { id: lockProc; command: ["swaylock"] }
    Process { id: logoutProc; command: ["hyprctl", "dispatch", "exit"] }
    Process { id: sleepProc; command: ["systemctl", "suspend"] }
    Process { id: rebootProc; command: ["systemctl", "reboot"] }
    Process { id: shutdownProc; command: ["systemctl", "poweroff"] }

    component PowerButton: ColumnLayout {
        id: btn
        property string label: ""
        property string icon: ""
        property int btnIndex: -1
        signal clicked()

        readonly property bool isSelected: root.selectedIndex === btnIndex

        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 6

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 56; height: 56; radius: 28
            color: mouse.containsMouse ? Services.Theme.surfaceVariant : Services.Theme.bgHover
            border.color: btn.isSelected ? Services.Theme.accent : "transparent"
            border.width: btn.isSelected ? 2 : 0
            Behavior on color       { ColorAnimation  { duration: 100 } }
            Behavior on border.color { ColorAnimation { duration: 100 } }

            Text {
                anchors.centerIn: parent
                text: btn.icon
                font.family: "Symbols Nerd Font Mono"
                font.pixelSize: 22
                color: btn.isSelected ? Services.Theme.accent : Services.Theme.textPrimary
                Behavior on color { ColorAnimation { duration: 100 } }
            }

            MouseArea {
                id: mouse
                anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selectedIndex = btn.btnIndex
                onClicked: btn.clicked()
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: btn.label
            color: btn.isSelected ? Services.Theme.textPrimary : Services.Theme.textSecondary
            font.pixelSize: 11
            Behavior on color { ColorAnimation { duration: 100 } }
        }
    }
}