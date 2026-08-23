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

        property bool showingA: true

        Component.onCompleted: {
            if (Services.Wallpaper && Services.Wallpaper.currentWallpaper) {
                var cur = Services.Wallpaper.currentWallpaper
                imgA.source = "file://" + cur
                imgA.opacity = 1.0
                imgA.scale = 1.0
                wallWin.showingA = true

                // Pre-cache alternate Wallbler wallpaper in GPU memory for zero-lag instant transitions
                if (cur === Services.Wallpaper.darkWallbler) {
                    imgB.source = "file://" + Services.Wallpaper.lightWallbler
                    imgB.opacity = 0.0
                } else if (cur === Services.Wallpaper.lightWallbler) {
                    imgB.source = "file://" + Services.Wallpaper.darkWallbler
                    imgB.opacity = 0.0
                }
            }
        }

        Connections {
            target: Services.Wallpaper
            function onCurrentWallpaperChanged() {
                var p = Services.Wallpaper.currentWallpaper
                if (p && p.length > 0) {
                    wallWin.switchWallpaper("file://" + p)
                }
            }
        }

        function switchWallpaper(newUrl) {
            if (!newUrl) return

            if (showingA) {
                if (imgA.source.toString() === newUrl && imgA.opacity > 0.9) return

                imgB.source = newUrl
                imgB.z = 2
                imgA.z = 1
                showingA = false

                if (imgB.status === Image.Ready) {
                    transitionToB.restart()
                }
            } else {
                if (imgB.source.toString() === newUrl && imgB.opacity > 0.9) return

                imgA.source = newUrl
                imgA.z = 2
                imgB.z = 1
                showingA = true

                if (imgA.status === Image.Ready) {
                    transitionToA.restart()
                }
            }
        }

        // ── GPU Texture Layer A ───────────────────────────────────────────────
        Image {
            id: imgA
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            smooth: true
            sourceSize: Qt.size(wallWin.width > 0 ? wallWin.width : 1920, wallWin.height > 0 ? wallWin.height : 1080)
            opacity: 1.0
            scale: 1.0
            z: 1

            onStatusChanged: {
                if (status === Image.Ready && wallWin.showingA && opacity < 1.0) {
                    transitionToA.restart()
                }
            }
        }

        // ── GPU Texture Layer B ───────────────────────────────────────────────
        Image {
            id: imgB
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            smooth: true
            sourceSize: Qt.size(wallWin.width > 0 ? wallWin.width : 1920, wallWin.height > 0 ? wallWin.height : 1080)
            opacity: 0.0
            scale: 1.0
            z: 0

            onStatusChanged: {
                if (status === Image.Ready && !wallWin.showingA && opacity < 1.0) {
                    transitionToB.restart()
                }
            }
        }

        // ── Ultra-Fast GPU Native Transitions (Zero-Lag, 144fps Lock) ────────
        ParallelAnimation {
            id: transitionToA

            // Incoming Layer A (Depth Bloom & Settle)
            NumberAnimation {
                target: imgA
                property: "opacity"
                from: imgA.opacity
                to: 1.0
                duration: 420
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: imgA
                property: "scale"
                from: 1.03
                to: 1.0
                duration: 420
                easing.type: Easing.OutCubic
            }

            // Outgoing Layer B
            NumberAnimation {
                target: imgB
                property: "opacity"
                from: imgB.opacity
                to: 0.0
                duration: 380
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: imgB
                property: "scale"
                from: 1.0
                to: 0.985
                duration: 380
                easing.type: Easing.OutCubic
            }

            onFinished: {
                imgB.opacity = 0.0
                imgB.scale = 1.0
                imgB.z = 0
                imgA.z = 1
            }
        }

        ParallelAnimation {
            id: transitionToB

            // Incoming Layer B (Depth Bloom & Settle)
            NumberAnimation {
                target: imgB
                property: "opacity"
                from: imgB.opacity
                to: 1.0
                duration: 420
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: imgB
                property: "scale"
                from: 1.03
                to: 1.0
                duration: 420
                easing.type: Easing.OutCubic
            }

            // Outgoing Layer A
            NumberAnimation {
                target: imgA
                property: "opacity"
                from: imgA.opacity
                to: 0.0
                duration: 380
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: imgA
                property: "scale"
                from: 1.0
                to: 0.985
                duration: 380
                easing.type: Easing.OutCubic
            }

            onFinished: {
                imgA.opacity = 0.0
                imgA.scale = 1.0
                imgA.z = 0
                imgB.z = 1
            }
        }
    }
}
