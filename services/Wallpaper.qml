pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "." as Services

Singleton {
    id: root

    readonly property string homeDir: (Quickshell.env("HOME") || "/home/" + (Quickshell.env("USER") || "user"))
    readonly property string assetsDir: homeDir + "/.config/quickshell/assets/wallpapers"

    property string currentWallpaper: assetsDir + "/wallbler.jpg"

    property var defaultWallpapers: [
        { name: "Wallbler", path: assetsDir + "/wallbler.jpg", isCustom: false }
    ]
    property var customWallpapers: []
    property var allWallpapers: []
    property bool isPicking: false

    readonly property string configPath: homeDir + "/.cache/quickshell/wallpaper_config.json"
    readonly property string declConfigPath: homeDir + "/.config/quickshell/wallpaper_config.json"
    readonly property string pickerScript: homeDir + "/.config/quickshell/scripts/xdg-file-picker.py"

    Component.onCompleted: {
        updateAllList()
        loadConfigProc.running = true
        killSwaybgProc.running = true
    }

    function updateAllList() {
        var list = []
        for (var i = 0; i < defaultWallpapers.length; i++) {
            list.push(defaultWallpapers[i])
        }
        for (var j = 0; j < customWallpapers.length; j++) {
            list.push(customWallpapers[j])
        }
        allWallpapers = list
    }

    function setWallpaper(filePath) {
        if (!filePath) return
        currentWallpaper = filePath
        saveConfig()
        if (Services.Config) {
            Services.Config.generateMatugen(filePath)
        }
    }

    function pickCustomWallpaper() {
        if (isPicking) return
        isPicking = true
        pickerProc.running = false
        pickerProc.running = true
    }

    function removeCustomWallpaper(filePath) {
        var newCustoms = []
        for (var i = 0; i < customWallpapers.length; i++) {
            if (customWallpapers[i].path !== filePath) {
                newCustoms.push(customWallpapers[i])
            }
        }
        customWallpapers = newCustoms
        updateAllList()
        if (currentWallpaper === filePath) {
            setWallpaper(defaultWallpapers.length > 0 ? defaultWallpapers[0].path : assetsDir + "/wallbler.jpg")
        } else {
            saveConfig()
        }
    }

    function addCustomWallpaper(filePath) {
        if (!filePath) return
        var filename = filePath.substring(filePath.lastIndexOf("/") + 1)
        
        for (var i = 0; i < customWallpapers.length; i++) {
            if (customWallpapers[i].path === filePath) {
                setWallpaper(filePath)
                return
            }
        }

        var newCustoms = customWallpapers.slice()
        newCustoms.unshift({
            name: filename,
            path: filePath,
            isCustom: true
        })
        customWallpapers = newCustoms
        updateAllList()
        setWallpaper(filePath)
    }

    function saveConfig() {
        var data = {
            currentWallpaper: currentWallpaper,
            customWallpapers: customWallpapers
        }
        var jsonStr = JSON.stringify(data, null, 2)
        saveConfigProc.running = false
        saveConfigProc.command = [
            "sh", "-c",
            "mkdir -p ~/.cache/quickshell && " +
            "cat << 'EOF' > \"" + configPath + "\"\n" + jsonStr + "\nEOF\n" +
            "cat << 'EOF' > \"" + declConfigPath + "\"\n" + jsonStr + "\nEOF"
        ]
        saveConfigProc.running = true
    }

    Process {
        id: killSwaybgProc
        command: ["sh", "-c", "pkill swaybg || true"]
    }

    // Process to run GTK/XDG File Chooser via python script
    Process {
        id: pickerProc
        command: ["python3", root.pickerScript]
        stdout: SplitParser {
            onRead: data => {
                var selected = data.trim()
                if (selected.length > 0) {
                    root.addCustomWallpaper(selected)
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.isPicking = false
        }
    }

    // Process to load saved wallpaper config
    Process {
        id: loadConfigProc
        property string rawData: ""
        command: [
            "sh", "-c",
            "if [ -f \"" + declConfigPath + "\" ]; then tr -d '\\r\\n' < \"" + declConfigPath + "\"; " +
            "elif [ -f \"" + configPath + "\" ]; then tr -d '\\r\\n' < \"" + configPath + "\"; " +
            "else echo '{}'; fi"
        ]
        stdout: SplitParser {
            onRead: chunk => {
                loadConfigProc.rawData += chunk
            }
        }
        onExited: (exitCode, exitStatus) => {
            var trimmed = loadConfigProc.rawData.trim()
            if (trimmed.length > 0 && trimmed.startsWith("{")) {
                try {
                    var parsed = JSON.parse(trimmed)
                    if (parsed && parsed.customWallpapers && Array.isArray(parsed.customWallpapers)) {
                        root.customWallpapers = parsed.customWallpapers
                        root.updateAllList()
                    }
                    if (parsed && parsed.currentWallpaper && parsed.currentWallpaper.length > 0) {
                        root.setWallpaper(parsed.currentWallpaper)
                    } else {
                        root.setWallpaper(root.assetsDir + "/wallbler.jpg")
                    }
                } catch (e) {
                    root.setWallpaper(root.assetsDir + "/wallbler.jpg")
                }
            } else {
                root.setWallpaper(root.assetsDir + "/wallbler.jpg")
            }
        }
    }

    Process {
        id: saveConfigProc
    }
}
