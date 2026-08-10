import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../services" as Services

PanelWindow {
    id: clipboardWindow
    visible: false

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusiveZone: 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    Component.onCompleted: Services.OverlayManager.register(clipboardWindow)

    function show() {
        Services.OverlayManager.closeAllExcept(clipboardWindow)
        visible = true
        Services.Clipboard.query = ""
        searchField.text = ""
        Services.Clipboard.refresh()
        searchField.forceActiveFocus()
        resultList.currentIndex = 0
    }
    function hide() {
        visible = false
    }
    function toggle() { visible ? hide() : show() }

    MouseArea {
        anchors.fill: parent
        onClicked: clipboardWindow.hide()
    }

    Rectangle {
        anchors.centerIn: parent
        width: 600
        height: 420
        radius: Services.Theme.radiusLg
        color: Services.Theme.surface
        border.color: Services.Theme.border
        border.width: 1

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // search bar
            Rectangle {
                Layout.fillWidth: true
                height: 44
                radius: 10
                color: "#262626"
                border.color: searchField.activeFocus ? Services.Theme.borderHighlight : Services.Theme.border
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 8

                    Text {
                        text: "⌕"
                        font.pixelSize: 16
                    color: Services.Theme.textDisabled
                    }

                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        background: null
                        color: Services.Theme.textPrimary
                        placeholderText: "Search clipboard..."
                        placeholderTextColor: Services.Theme.textDisabled
                        onTextChanged: Services.Clipboard.query = text

                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Down) {
                                resultList.currentIndex = Math.min(resultList.currentIndex + 1, resultList.count - 1)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Up) {
                                resultList.currentIndex = Math.max(resultList.currentIndex - 1, 0)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                const selected = Services.Clipboard.filtered()[resultList.currentIndex]
                                if (selected) {
                                    Services.Clipboard.select(selected)
                                    clipboardWindow.hide()
                                }
                            } else if (event.key === Qt.Key_Delete) {
                                const toDelete = Services.Clipboard.filtered()[resultList.currentIndex]
                                if (toDelete) Services.Clipboard.deleteEntry(toDelete)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Escape) {
                                clipboardWindow.hide()
                            }
                        }
                    }
                }
            }

            ListView {
                id: resultList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: Services.Clipboard.filtered()
                highlightMoveDuration: 80
                visible: count > 0

                delegate: Rectangle {
                    id: card
                    required property var modelData
                    required property int index
                    width: resultList.width
                    height: 48
                    radius: 8
                    color: {
                        if (index === resultList.currentIndex) return Services.Theme.surfaceVariant
                        if (hoverArea.containsMouse) return Services.Theme.bgHover
                        return "transparent"
                    }

                    property bool isImage: Services.Clipboard.isImageEntry(modelData)
                    property string thumbPath: ""

                    Process {
                        id: thumbProc
                        property string pendingPath: ""
                        onExited: card.thumbPath = pendingPath
                    }

                    Component.onCompleted: {
                        if (isImage) {
                            const m = modelData.preview.match(/\b(png|jpe?g|gif|bmp|webp)\b/i)
                            const ext = m ? m[1].toLowerCase() : "png"
                            const path = "/tmp/qs-clip-" + modelData.id + "." + ext
                            thumbProc.pendingPath = path
                            thumbProc.command = ["sh", "-c",
                                "test -f '" + path + "' || cliphist decode " + modelData.id + " > '" + path + "'"]
                            thumbProc.running = true
                        }
                    }

                    MouseArea {
                        id: hoverArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            Services.Clipboard.select(card.modelData)
                            clipboardWindow.hide()
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 10

                        Image {
                            visible: card.isImage
                            source: card.isImage && card.thumbPath.length > 0
                                ? "file://" + card.thumbPath : ""
                            fillMode: Image.PreserveAspectCrop
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                        }

                        Text {
                            visible: !card.isImage
                            text: card.modelData.preview
                            color: Services.Theme.textPrimary
                            font.pixelSize: 14
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        Text {
                            visible: card.isImage
                            text: "Image"
                            color: Services.Theme.textSecondary
                            font.pixelSize: 14
                            Layout.fillWidth: true
                        }

                        Text {
                            text: "✕"
                            color: deleteArea.containsMouse ? Services.Theme.textPrimary : Services.Theme.textDisabled
                            Layout.preferredWidth: 20
                            horizontalAlignment: Text.AlignHCenter

                            MouseArea {
                                id: deleteArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: Services.Clipboard.deleteEntry(card.modelData)
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: resultList.count === 0
                spacing: 8

                Item { Layout.fillHeight: true }
                Text {
                    text: "⧉"
                    font.pixelSize: 32
                    color: Services.Theme.textDisabled
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: Services.Clipboard.query.length > 0 ? "No matches found" : "Clipboard history is empty"
                    color: Services.Theme.textSecondary
                    Layout.alignment: Qt.AlignHCenter
                }
                Item { Layout.fillHeight: true }
            }
        }
    }
}
