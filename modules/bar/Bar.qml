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
    WlrLayershell.keyboardFocus: dynamicIsland.replyMode ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    exclusiveZone: 36
    implicitHeight: 160

    Item {
        id: barContainer
        anchors.fill: parent

        RowLayout {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 36
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
                collapseNear: dynamicIsland.expanded
            }
          }
          
          Components.DynamicIsland {
            id: dynamicIsland
            anchors.fill: parent
            z: 999
          }
    }
}
