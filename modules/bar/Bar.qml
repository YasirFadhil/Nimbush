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

    exclusiveZone: implicitHeight
    implicitHeight: 36

    Item {
        id: barContainer
        anchors.fill: parent

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.topMargin: 4
            anchors.bottomMargin: 4
            spacing: 12

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
    }
}
