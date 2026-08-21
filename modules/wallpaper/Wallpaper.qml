import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../services" as Services

Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
        id: wallWin
        required property var modelData

        screen: modelData
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "quickshell:wallpaper"
        exclusiveZone: -1
        color: "#000000"

        property string activePath: Services.Wallpaper.currentWallpaper
        property bool showingA: true

        onActivePathChanged: {
            if (activePath.length > 0) {
                switchWallpaper("file://" + activePath)
            }
        }

        function switchWallpaper(newUrl) {
            if (!newUrl) return

            if (showingA) {
                if (imgA.source.toString() === newUrl && imgA.opacity > 0.95) return

                imgB.source = newUrl
                imgB.z = 2
                imgA.z = 1
                showingA = false

                if (imgB.status === Image.Ready) {
                    animB.restart()
                }
            } else {
                if (imgB.source.toString() === newUrl && imgB.opacity > 0.95) return

                imgA.source = newUrl
                imgA.z = 2
                imgB.z = 1
                showingA = true

                if (imgA.status === Image.Ready) {
                    animA.restart()
                }
            }
        }

        // Layer A
        Image {
            id: imgA
            anchors.fill: parent
            source: Services.Wallpaper.currentWallpaper.length > 0 ? ("file://" + Services.Wallpaper.currentWallpaper) : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            smooth: true
            sourceSize: Qt.size(wallWin.width > 0 ? wallWin.width : 1920, wallWin.height > 0 ? wallWin.height : 1080)
            opacity: 1.0
            z: 1

            onStatusChanged: {
                if (status === Image.Ready && wallWin.showingA && opacity < 1.0) {
                    animA.restart()
                }
            }
        }

        // Layer B (pre-cached)
        Image {
            id: imgB
            anchors.fill: parent
            source: (Services.Wallpaper.currentWallpaper === Services.Wallpaper.darkWallbler) 
                ? ("file://" + Services.Wallpaper.lightWallbler) 
                : ("file://" + Services.Wallpaper.darkWallbler)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            smooth: true
            sourceSize: Qt.size(wallWin.width > 0 ? wallWin.width : 1920, wallWin.height > 0 ? wallWin.height : 1080)
            opacity: 0.0
            z: 0

            onStatusChanged: {
                if (status === Image.Ready && !wallWin.showingA && opacity < 1.0) {
                    animB.restart()
                }
            }
        }

        // Hardware-accelerated smooth opacity crossfade
        NumberAnimation {
            id: animA
            target: imgA
            property: "opacity"
            from: 0.0
            to: 1.0
            duration: 200
            easing.type: Easing.OutCubic
            onFinished: {
                imgB.opacity = 0.0
            }
        }

        NumberAnimation {
            id: animB
            target: imgB
            property: "opacity"
            from: 0.0
            to: 1.0
            duration: 200
            easing.type: Easing.OutCubic
            onFinished: {
                imgA.opacity = 0.0
            }
        }
    }
}
