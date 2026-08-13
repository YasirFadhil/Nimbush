import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import "../../services" as Services

PanelWindow {
    id: root

    property string overlayId: "dashboard"
    property bool isOpen: false

    visible: false

    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.namespace: "quickshell:dashboard"
    exclusiveZone: 0
    anchors { top: true; bottom: true; left: true; right: true }

    Component.onCompleted: Services.OverlayManager.register(root)

    function show() {
        Services.OverlayManager.closeAllExcept(root)
        hideTimer.stop()
        visible = true
        isOpen = true
        keyFocus.forceActiveFocus()
    }

    function hide() {
        if (!isOpen) return
        isOpen = false
        hideTimer.restart()
    }

    function toggle() { isOpen ? hide() : show() }
    function open() { show() }
    function close() { hide() }

    Timer {
        id: hideTimer
        interval: 220
        onTriggered: root.visible = false
    }

    // Keyboard handler (Esc to close)
    Item {
        id: keyFocus
        focus: root.isOpen
        Keys.onEscapePressed: root.close()
    }

    // Fullscreen Backdrop (Click outside to close)
    MouseArea {
        anchors.fill: parent
        onClicked: root.close()

        // ── Dropdown Panel attached to Top-Left under Bar ─────────────────
        Rectangle {
            id: panel
            anchors { top: parent.top; left: parent.left }
            anchors.leftMargin: 12
            anchors.topMargin: 12
            width: 380
            implicitHeight: mainCol.implicitHeight + 32

            radius: Services.Theme.radiusLg
            color: Services.Theme.surface
            border.color: Services.Theme.border
            border.width: 1
            clip: true

            opacity: root.isOpen ? 1 : 0
            transform: Translate {
                y: root.isOpen ? 0 : -20
                Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }

            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            // Block click propagation to backdrop
            MouseArea {
                anchors.fill: parent
                onClicked: {}
            }

            ColumnLayout {
                id: mainCol
                anchors.fill: parent
                anchors.margins: 16
                spacing: 14

                // ── Header: User Avatar & Distro Badge ──────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    // Avatar Image or Fallback Glyph
                    Rectangle {
                        width: 48; height: 48; radius: 14
                        color: Services.Theme.surfaceVariant
                        border.color: Services.Theme.border
                        border.width: 1
                        antialiasing: true
                        smooth: true

                        Image {
                            id: avatarImg
                            anchors.fill: parent
                            anchors.margins: 1
                            source: Services.OsInfo.avatarPath
                            fillMode: Image.PreserveAspectCrop
                            visible: false
                            smooth: true
                            mipmap: true
                            antialiasing: true
                        }

                        MultiEffect {
                            anchors.fill: avatarImg
                            source: avatarImg
                            maskEnabled: true
                            maskSource: dashAvatarMask
                            visible: avatarImg.status === Image.Ready
                        }

                        Item {
                            id: dashAvatarMask
                            anchors.fill: avatarImg
                            visible: false
                            layer.enabled: true
                            layer.smooth: true
                            layer.samples: 8
                            Rectangle {
                                anchors.fill: parent
                                radius: 13
                                color: "black"
                                antialiasing: true
                                smooth: true
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: avatarImg.status !== Image.Ready
                            text: Services.OsInfo.logoGlyph !== "" ? Services.OsInfo.logoGlyph : "\uf007"
                            font.family: "Symbols Nerd Font Mono"
                            font.pixelSize: 22
                            color: Services.Theme.accent
                        }
                    }

                    ColumnLayout {
                        spacing: 2
                        Layout.fillWidth: true

                        Text {
                            text: Services.OsInfo.username.length > 0 ? Services.OsInfo.username : "User Profile"
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            color: Services.Theme.textPrimary
                            elide: Text.ElideRight
                        }

                        RowLayout {
                            spacing: 6
                            Text {
                                text: Services.OsInfo.hostname.length > 0 ? "@" + Services.OsInfo.hostname : ""
                                font.pixelSize: 11
                                color: Services.Theme.textSecondary
                                elide: Text.ElideRight
                            }
                            Text {
                                text: "•"
                                font.pixelSize: 11
                                color: Services.Theme.textDisabled
                            }
                            Text {
                                text: Services.OsInfo.distroName.length > 0 ? Services.OsInfo.distroName : "Linux"
                                font.pixelSize: 11
                                color: Services.Theme.accent
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // Close Button
                    Rectangle {
                        width: 26; height: 26; radius: 13
                        color: closeMouse.containsMouse ? Services.Theme.surfaceVariant : Services.Theme.bgHover
                        border.color: Services.Theme.border
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.close
                            font.family: "Symbols Nerd Font Mono"
                            font.pixelSize: 11
                            color: Services.Theme.textSecondary
                        }

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.close()
                        }
                    }
                }

                // Hairline Divider
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Services.Theme.border
                    opacity: 0.8
                }

                // ── System Info / Performance Metrics (RAM, Disk, CPU, Temp) ────
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "System Performance"
                            font.pixelSize: 11
                            font.bold: true
                            color: Services.Theme.textSecondary
                        }
                    }

                    // 1. CPU Usage Card
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 52
                        radius: Services.Theme.radiusMd
                        color: Services.Theme.surfaceVariant

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Text {
                                    text: Services.Icons.cpu
                                    font.family: "Symbols Nerd Font Mono"
                                    font.pixelSize: 13
                                    color: Services.Theme.accent
                                }
                                Text {
                                    text: "CPU Usage"
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: Services.Theme.textPrimary
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: Math.round(Services.Sysmon.cpuUsage) + "%"
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: Services.Theme.accent
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 5
                                radius: 2.5
                                color: Services.Theme.surfaced
                                clip: true

                                Rectangle {
                                    height: parent.height
                                    width: Math.max(0, Math.min(parent.width, parent.width * (Services.Sysmon.cpuUsage / 100.0)))
                                    radius: 2.5
                                    color: Services.Sysmon.cpuUsage > 85 ? Services.Theme.danger : Services.Theme.accent
                                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                }
                            }
                        }
                    }

                    // 2. RAM Usage Card
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 52
                        radius: Services.Theme.radiusMd
                        color: Services.Theme.surfaceVariant

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Text {
                                    text: Services.Icons.ram
                                    font.family: "Symbols Nerd Font Mono"
                                    font.pixelSize: 13
                                    color: Services.Theme.accent
                                }
                                Text {
                                    text: "RAM Usage"
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: Services.Theme.textPrimary
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: (Services.Sysmon.ramUsedStr.length > 0 ? Services.Sysmon.ramUsedStr + " / " + Services.Sysmon.ramTotalStr + " (" : "") + Math.round(Services.Sysmon.ramUsage) + "%" + (Services.Sysmon.ramUsedStr.length > 0 ? ")" : "")
                                    font.pixelSize: 10
                                    color: Services.Theme.textSecondary
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 5
                                radius: 2.5
                                color: Services.Theme.surfaced
                                clip: true

                                Rectangle {
                                    height: parent.height
                                    width: Math.max(0, Math.min(parent.width, parent.width * (Services.Sysmon.ramUsage / 100.0)))
                                    radius: 2.5
                                    color: Services.Sysmon.ramUsage > 85 ? Services.Theme.danger : Services.Theme.accent
                                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                }
                            }
                        }
                    }

                    // 3. Disk Storage Card
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 52
                        radius: Services.Theme.radiusMd
                        color: Services.Theme.surfaceVariant

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Text {
                                    text: Services.Icons.disk
                                    font.family: "Symbols Nerd Font Mono"
                                    font.pixelSize: 13
                                    color: Services.Theme.accent
                                }
                                Text {
                                    text: "Disk Storage"
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: Services.Theme.textPrimary
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: (Services.Sysmon.diskUsedStr.length > 0 ? Services.Sysmon.diskUsedStr + " / " + Services.Sysmon.diskTotalStr + " (" : "") + Math.round(Services.Sysmon.diskUsage) + "%" + (Services.Sysmon.diskUsedStr.length > 0 ? ")" : "")
                                    font.pixelSize: 10
                                    color: Services.Theme.textSecondary
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 5
                                radius: 2.5
                                color: Services.Theme.surfaced
                                clip: true

                                Rectangle {
                                    height: parent.height
                                    width: Math.max(0, Math.min(parent.width, parent.width * (Services.Sysmon.diskUsage / 100.0)))
                                    radius: 2.5
                                    color: Services.Sysmon.diskUsage > 90 ? Services.Theme.danger : Services.Theme.accent
                                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                }
                            }
                        }
                    }

                    // 4. CPU Temp Card
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 52
                        radius: Services.Theme.radiusMd
                        color: Services.Theme.surfaceVariant

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Text {
                                    text: Services.Icons.temp
                                    font.family: "Symbols Nerd Font Mono"
                                    font.pixelSize: 13
                                    color: Services.Theme.accent
                                }
                                Text {
                                    text: "CPU Temp"
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: Services.Theme.textPrimary
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: Math.round(Services.Sysmon.cpuTemp) + "°C"
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: Services.Sysmon.cpuTemp > 75 ? Services.Theme.danger : Services.Theme.accent
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 5
                                radius: 2.5
                                color: Services.Theme.surfaced
                                clip: true

                                Rectangle {
                                    height: parent.height
                                    width: Math.max(0, Math.min(parent.width, parent.width * (Services.Sysmon.cpuTemp / 100.0)))
                                    radius: 2.5
                                    color: Services.Sysmon.cpuTemp > 75 ? Services.Theme.danger : Services.Theme.accent
                                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                }
                            }
                        }
                    }
                }

                // ── Additional System Details Grid ──────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: detailsCol.implicitHeight + 16
                    radius: Services.Theme.radiusMd
                    color: Services.Theme.surfaceVariant

                    ColumnLayout {
                        id: detailsCol
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        // Kernel & Uptime Row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Text { text: Services.Icons.kernel; font.family: "Symbols Nerd Font Mono"; font.pixelSize: 12; color: Services.Theme.accent }
                                Text { text: "Kernel"; font.pixelSize: 10; color: Services.Theme.textDisabled }
                                Text { text: Services.OsInfo.kernel.length > 0 ? Services.OsInfo.kernel : "-"; font.pixelSize: 10; color: Services.Theme.textPrimary; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Text { text: Services.Icons.uptime; font.family: "Symbols Nerd Font Mono"; font.pixelSize: 12; color: Services.Theme.accent }
                                Text { text: "Uptime"; font.pixelSize: 10; color: Services.Theme.textDisabled }
                                Text { text: Services.Sysmon.uptimeStr.length > 0 ? Services.Sysmon.uptimeStr : "-"; font.pixelSize: 10; color: Services.Theme.textPrimary; elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                        }

                        // Shell & Battery Row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Text { text: Services.Icons.shell; font.family: "Symbols Nerd Font Mono"; font.pixelSize: 12; color: Services.Theme.accent }
                                Text { text: "Shell"; font.pixelSize: 10; color: Services.Theme.textDisabled }
                                Text { text: Services.OsInfo.shellName.length > 0 ? Services.OsInfo.shellName : "-"; font.pixelSize: 10; color: Services.Theme.textPrimary; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                visible: Services.Power.ready && !isNaN(Services.Power.percentage) && Services.Power.percentage > 0
                                Text {
                                    text: Services.Icons.powerIcon(Services.Power.charging, Services.Power.percentage * 100)
                                    font.family: "Symbols Nerd Font Mono"
                                    font.pixelSize: 12
                                    color: Services.Power.charging ? Services.Theme.success : (Services.Power.isLow ? Services.Theme.danger : Services.Theme.accent)
                                }
                                Text { text: "Power"; font.pixelSize: 10; color: Services.Theme.textDisabled }
                                Text { text: Math.round(Services.Power.percentage * 100) + "%"; font.pixelSize: 10; color: Services.Theme.textPrimary; elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                        }
                    }
                }

                // ── Quick Actions Row (Lock & Power Menu) ────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: Services.Theme.radiusSm
                        color: lockMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.surfaceVariant

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            Text { text: Services.Icons.lock; font.family: "Symbols Nerd Font Mono"; font.pixelSize: 12; color: Services.Theme.textSecondary }
                            Text { text: "Lock Screen"; font.pixelSize: 11; color: Services.Theme.textPrimary }
                        }

                        MouseArea {
                            id: lockMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.close()
                                lockProc.running = true
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: Services.Theme.radiusSm
                        color: pwrMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.surfaceVariant

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            Text { text: Services.Icons.power; font.family: "Symbols Nerd Font Mono"; font.pixelSize: 12; color: Services.Theme.danger }
                            Text { text: "Power Menu"; font.pixelSize: 11; color: Services.Theme.textPrimary }
                        }

                        MouseArea {
                            id: pwrMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.close()
                                pwrProc.running = true
                            }
                        }
                    }
                }
            }
        }
    }

    Process { id: lockProc; command: ["sh", "-c", "qs ipc call lockscreen lock || hyprlock || swaylock"] }
    Process { id: pwrProc; command: ["quickshell", "ipc", "call", "powermenu", "open"] }
}
