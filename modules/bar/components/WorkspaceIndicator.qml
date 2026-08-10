import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../services" as Services
import "." as Components

RowLayout {
    spacing: 10

    // OS logo — klik buat toggle launcher
    Item {
        Layout.preferredWidth: logoText.implicitWidth
        Layout.preferredHeight: logoText.implicitHeight

        Text {
            id: logoText
            anchors.fill: parent
            text: Services.OsInfo.logoGlyph
            font.family: "Liga SFMono Nerd Font"
            font.pixelSize: 16
            color: Services.Theme.accent
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Services.OverlayManager.launcherToggleRequested()
        }
    }

    // Workspace ovals — cuma render workspace yang beneran kebuka.
    RowLayout {
        id: wsRow
        spacing: 5

        readonly property var ids: Services.Workspaces.workspaceIds
        readonly property int activeIdx: ids.indexOf(Services.Workspaces.activeWorkspaceId)
        readonly property int nextWsId: (activeIdx >= 0 && activeIdx + 1 < ids.length) ? ids[activeIdx + 1] : -1

        Repeater {
            model: wsRow.ids

            Rectangle {
                id: ws
                required property int modelData
                readonly property bool isActive: modelData === Services.Workspaces.activeWorkspaceId
                readonly property bool isNext: modelData === wsRow.nextWsId

                Layout.alignment: Qt.AlignVCenter
                width: isActive ? 20 : (isNext ? 11 : 6)
                height: isActive ? 8 : (isNext ? 7 : 6)
                radius: height / 2
                color: isActive ? Services.Theme.accent
                     : isNext ? Services.Theme.accentDim
                     : Services.Theme.textDisabled
                opacity: isActive ? 1.0 : (isNext ? 0.8 : 0.4)

                Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                Behavior on opacity { NumberAnimation { duration: 180 } }
                Behavior on color { ColorAnimation { duration: 180 } }
            }
        }
    }

    Components.Separator {}

    Text {
        text: Services.Workspaces.activeWindowTitle
        font.family: "Liga SFMono Nerd Font"
        font.pixelSize: 13
        color: Services.Theme.textSecondary
        elide: Text.ElideRight
        Layout.maximumWidth: 260
        visible: text.length > 0
    }
}
