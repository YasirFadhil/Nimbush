pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property string device: "intel_backlight"
    property int maxBrightness: 1
    property int current: 0
    readonly property real percent: current / maxBrightness

    FileView {
        path: "/sys/class/backlight/" + root.device + "/max_brightness"
        onLoaded: root.maxBrightness = parseInt(text())
    }

    FileView {
      path: "/sys/class/backlight/" + root.device + "/brightness"
      watchChanges: true
      onFileChanged: reload()
      onLoaded: root.current = parseInt(text())
    }

    Process { id: setProc }

    function setPercent(p) {
        const val = Math.round(Math.max(0, Math.min(1, p)) * maxBrightness)
        setProc.command = ["brightnessctl", "-d", root.device, "set", val.toString()]
        setProc.running = true
    }
}
