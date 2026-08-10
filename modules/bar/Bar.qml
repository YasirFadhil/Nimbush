import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "components" as Components
import "../../services" as Services

PanelWindow {
    id: root

    anchors {
        top: true
        left: true
        right: true
    }

    color: "transparent"
    WlrLayershell.namespace: "quickshell:bar"

    // Reserve space for the bar (no floating margin — flush against top edge)
    exclusiveZone: implicitHeight
    implicitHeight: 30

    Rectangle {
        id: barBg
        anchors.fill: parent
        radius: 0
        color: Services.Theme.bgElevated
        // color: "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16

            Components.WorkspaceIndicator {
                Layout.alignment: Qt.AlignVCenter
            }

            Item {
                Layout.fillWidth: true
            }

            Components.StatusTray {
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // Sibling of RowLayout, anchored directly to the bar so it stays
        // absolute-center regardless of left/right section widths.
    }
}
