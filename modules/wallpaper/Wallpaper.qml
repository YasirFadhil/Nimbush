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

        onActivePathChanged: {
            if (activePath.length > 0) {
                var newUrl = "file://" + activePath
                if (backImg.source.toString() !== newUrl) {
                    prevImg.source = backImg.source
                    prevImg.opacity = 1.0
                    backImg.source = newUrl
                    fadeAnim.restart()
                }
            }
        }

        // Previous wallpaper layer (fades out for smooth crossfade)
        Image {
            id: prevImg
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            smooth: true
            mipmap: true
            opacity: 0.0
        }

        // Current active wallpaper layer
        Image {
            id: backImg
            anchors.fill: parent
            source: Services.Wallpaper.currentWallpaper.length > 0 ? ("file://" + Services.Wallpaper.currentWallpaper) : ""
            fillMode: Image.PreserveAspectCrop
            smooth: true
            mipmap: true
            opacity: 1.0
        }

        NumberAnimation {
            id: fadeAnim
            target: prevImg
            property: "opacity"
            to: 0.0
            duration: 150
            easing.type: Easing.OutCubic
        }
    }
}
