import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../services" as Services

Scope {
    id: root

    readonly property string overlayId: "screenshot"
    readonly property bool visible: controller.overlayVisible
    readonly property bool busy: controller.busy

    function show() {
        controller.startSession()
    }

    function hide() {
        controller.cancel()
    }

    function toggle() {
        if (controller.busy) hide()
        else show()
    }

    Component.onCompleted: {
        if (Services.OverlayManager) Services.OverlayManager.register(root)
    }

    Component.onDestruction: {
        if (Services.OverlayManager) Services.OverlayManager.unregister(root)
    }

    ScreenshotController {
        id: controller
    }

    Variants {
        model: Quickshell.screens
        // qmllint disable uncreatable-type
        delegate: PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: controller.overlayVisible

            anchors { top: true; bottom: true; left: true; right: true }
            color: "#000000"
            exclusiveZone: -1
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "quickshell:screenshot"

            readonly property string screenName: modelData ? (modelData.name || "full") : "full"
            readonly property string imgPath: controller.imageForScreen(screenName)
            readonly property bool isActiveScreen: controller.activeScreenName === "" || controller.activeScreenName === screenName
            readonly property bool showSelection: controller.hasSelection && controller.activeScreenName === screenName

            onVisibleChanged: {
                if (visible) {
                    keyScope.forceActiveFocus()
                }
            }

            FocusScope {
                id: keyScope
                anchors.fill: parent
                focus: true

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        controller.cancel()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (controller.isValidSelection) {
                            controller.confirm("swappy")
                        }
                        event.accepted = true
                    } else if (event.key === Qt.Key_P && !(event.modifiers & Qt.ControlModifier)) {
                        controller.toggleIncludePointer()
                        event.accepted = true
                    } else if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
                        if (controller.isValidSelection) {
                            controller.confirm("copy")
                        }
                        event.accepted = true
                    } else if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
                        if (controller.isValidSelection) {
                            controller.confirm("save")
                        }
                        event.accepted = true
                    } else if (event.key === Qt.Key_E && !(event.modifiers & Qt.ControlModifier)) {
                        if (controller.isValidSelection) {
                            controller.confirm("swappy")
                        }
                        event.accepted = true
                    }
                }

                // Static frozen desktop preview
                Image {
                    id: frozenImage
                    anchors.fill: parent
                    source: win.imgPath.length > 0 ? ("file://" + win.imgPath) : ""
                    cache: false
                    asynchronous: false
                    fillMode: Image.Stretch
                    smooth: false
                }

                // Full-screen dim when no selection is active on this screen
                Rectangle {
                    anchors.fill: parent
                    visible: !win.showSelection
                    color: Qt.rgba(0, 0, 0, 0.36)
                }

                // 4-rect surrounding dim cutout when selection is active on this screen
                Item {
                    anchors.fill: parent
                    visible: win.showSelection

                    readonly property color dimColor: Qt.rgba(0, 0, 0, 0.45)

                    // Top
                    Rectangle {
                        x: 0; y: 0
                        width: parent.width
                        height: Math.max(0, controller.selY)
                        color: parent.dimColor
                    }
                    // Bottom
                    Rectangle {
                        x: 0; y: controller.selY + controller.selH
                        width: parent.width
                        height: Math.max(0, parent.height - (controller.selY + controller.selH))
                        color: parent.dimColor
                    }
                    // Left
                    Rectangle {
                        x: 0; y: controller.selY
                        width: Math.max(0, controller.selX)
                        height: controller.selH
                        color: parent.dimColor
                    }
                    // Right
                    Rectangle {
                        x: controller.selX + controller.selW
                        y: controller.selY
                        width: Math.max(0, parent.width - (controller.selX + controller.selW))
                        height: controller.selH
                        color: parent.dimColor
                    }
                }

                // Selection border & corner markers
                Rectangle {
                    visible: win.showSelection && controller.selW >= 1 && controller.selH >= 1
                    x: controller.selX
                    y: controller.selY
                    width: controller.selW
                    height: controller.selH
                    color: "transparent"
                    border.color: Services.Theme.accent
                    border.width: 2

                    // Subtle inner contrast border
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        color: "transparent"
                        border.color: Qt.rgba(0, 0, 0, 0.45)
                        border.width: 1
                    }
                }

                // Floating dimension pill near selection
                Rectangle {
                    visible: win.showSelection && controller.selW >= 12 && controller.selH >= 12
                    x: Math.max(12, Math.min(controller.selX, parent.width - width - 12))
                    y: controller.selY >= 34 ? (controller.selY - height - 8) : (controller.selY + controller.selH + 8)
                    implicitWidth: dimLabel.implicitWidth + 14
                    implicitHeight: 24
                    radius: 6
                    color: Services.Theme.bgElevated
                    border.color: Services.Theme.borderHighlight
                    border.width: 1

                    Text {
                        id: dimLabel
                        anchors.centerIn: parent
                        text: Math.round(controller.selW) + " × " + Math.round(controller.selH)
                            + (controller.includePointer ? "  •  Pointer" : "")
                        font.family: Services.Theme.fontMono
                        font.pixelSize: Services.Theme.fontSizeSm
                        color: Services.Theme.textPrimary
                    }
                }

                // Selection mouse interaction (compositor renders live pointer on top)
                MouseArea {
                    id: selectionArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.CrosshairCursor

                    onPressed: (mouse) => {
                        keyScope.forceActiveFocus()
                        if (mouse.button === Qt.RightButton) {
                            if (controller.hasSelection) {
                                controller.resetSelection()
                            } else {
                                controller.cancel()
                            }
                            return
                        }
                        if (mouse.button === Qt.LeftButton) {
                            controller.beginDrag(win.screenName, win.width, win.height, mouse.x, mouse.y)
                        }
                    }

                    onPositionChanged: (mouse) => {
                        controller.updatePointer(win.screenName, mouse.x, mouse.y)
                        if (controller.isDragging && (mouse.buttons & Qt.LeftButton)) {
                            controller.updateDrag(mouse.x, mouse.y)
                        }
                    }

                    onReleased: (mouse) => {
                        if (mouse.button === Qt.LeftButton && controller.isDragging) {
                            controller.endDrag(mouse.x, mouse.y)
                        }
                    }
                }

                // Floating action toolbar
                ScreenshotToolbar {
                    visible: win.isActiveScreen
                    controller: controller
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 28
                }
            }
        }
    }
}
