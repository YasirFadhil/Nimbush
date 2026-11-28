import QtQuick
import QtQuick.Layouts
import "../../services" as Services

Rectangle {
    id: toolbar

    required property var controller
    readonly property bool hasSelection: controller ? controller.isValidSelection : false
    readonly property bool includePointer: controller ? controller.includePointer : false

    implicitWidth: row.implicitWidth + 20
    implicitHeight: 44
    radius: 22
    color: Services.Theme.bgElevated
    border.color: Services.Theme.borderHighlight
    border.width: 1

    opacity: (controller && controller.isDragging) ? 0.25 : 1.0
    Behavior on opacity {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    component ToolbarBtn: Rectangle {
        id: btn
        property string label: ""
        property string shortcutHint: ""
        property bool active: false
        property bool enabled: true
        property bool primary: false
        property bool destructive: false
        signal clicked()

        implicitWidth: btnRow.implicitWidth + 18
        implicitHeight: 30
        radius: 15
        opacity: enabled ? 1.0 : 0.42
        color: {
            if (primary && enabled) return btnMouse.containsMouse ? Qt.lighter(Services.Theme.accent, 1.1) : Services.Theme.accent
            if (active) return Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.22)
            if (destructive && btnMouse.containsMouse) return Qt.rgba(Services.Theme.danger.r, Services.Theme.danger.g, Services.Theme.danger.b, 0.22)
            if (btnMouse.containsMouse && enabled) return Services.Theme.bgHover
            return "transparent"
        }
        border.width: active ? 1 : 0
        border.color: active ? Services.Theme.accent : "transparent"

        RowLayout {
            id: btnRow
            anchors.centerIn: parent
            spacing: 6

            Text {
                text: btn.label
                font.family: Services.Theme.fontPrimary
                font.pixelSize: Services.Theme.fontSizeLg
                font.weight: (btn.primary || btn.active) ? Font.DemiBold : Font.Medium
                color: {
                    if (btn.primary && btn.enabled) return Services.Theme.bgOnAccent
                    if (btn.active) return Services.Theme.accent
                    if (btn.destructive && btnMouse.containsMouse) return Services.Theme.danger
                    return Services.Theme.textPrimary
                }
            }

            Rectangle {
                visible: btn.shortcutHint.length > 0
                implicitWidth: hintText.implicitWidth + 8
                implicitHeight: 16
                radius: 4
                color: (btn.primary && btn.enabled)
                    ? Qt.rgba(Services.Theme.bgOnAccent.r, Services.Theme.bgOnAccent.g, Services.Theme.bgOnAccent.b, 0.18)
                    : Qt.rgba(1, 1, 1, 0.08)

                Text {
                    id: hintText
                    anchors.centerIn: parent
                    text: btn.shortcutHint
                    font.family: Services.Theme.fontMono
                    font.pixelSize: Services.Theme.fontSizeXs
                    color: (btn.primary && btn.enabled) ? Services.Theme.bgOnAccent : Services.Theme.textSecondary
                }
            }
        }

        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: btn.enabled
            cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: btn.clicked()
        }
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 4

        // Selection size or instruction badge
        Rectangle {
            implicitWidth: statusText.implicitWidth + 16
            implicitHeight: 28
            radius: 14
            color: Qt.rgba(1, 1, 1, 0.06)

            Text {
                id: statusText
                anchors.centerIn: parent
                text: toolbar.hasSelection
                    ? (Math.round(toolbar.controller.selW) + " × " + Math.round(toolbar.controller.selH))
                    : "Drag to select"
                font.family: toolbar.hasSelection ? Services.Theme.fontMono : Services.Theme.fontPrimary
                font.pixelSize: Services.Theme.fontSizeMd
                font.weight: Font.Medium
                color: toolbar.hasSelection ? Services.Theme.textPrimary : Services.Theme.textSecondary
            }
        }

        Rectangle {
            width: 1
            height: 18
            color: Services.Theme.border
        }

        ToolbarBtn {
            label: toolbar.includePointer ? "Pointer: On" : "Pointer"
            shortcutHint: "P"
            active: toolbar.includePointer
            onClicked: toolbar.controller.toggleIncludePointer()
        }

        Rectangle {
            width: 1
            height: 18
            color: Services.Theme.border
        }

        ToolbarBtn {
            label: "Swappy"
            shortcutHint: "Enter"
            primary: true
            enabled: toolbar.hasSelection
            onClicked: toolbar.controller.confirm("swappy")
        }

        ToolbarBtn {
            label: "Copy"
            shortcutHint: "Ctrl+C"
            enabled: toolbar.hasSelection
            onClicked: toolbar.controller.confirm("copy")
        }

        ToolbarBtn {
            label: "Save"
            shortcutHint: "Ctrl+S"
            enabled: toolbar.hasSelection
            onClicked: toolbar.controller.confirm("save")
        }

        ToolbarBtn {
            label: "Cancel"
            shortcutHint: "Esc"
            destructive: true
            onClicked: toolbar.controller.cancel()
        }
    }
}
