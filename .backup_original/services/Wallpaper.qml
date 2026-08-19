pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string assetsDir: (Quickshell.env("HOME") || "/home/" + (Quickshell.env("USER") || "user")) + "/.config/quickshell/assets/wallpapers"

    property string currentWallpaper: assetsDir + "/wallbler.jpg"

    property var defaultWallpapers: [
        { name: "Wallbler", path: assetsDir + "/wallbler.jpg", isCustom: false }
    ]
    property var customWallpapers: []
    property var allWallpapers: []
    property bool isPicking: false

    readonly property string configPath: (Quickshell.env("HOME") || "/home/" + (Quickshell.env("USER") || "user")) + "/.cache/quickshell/wallpaper_config.json"
    readonly property string pickerScript: (Quickshell.env("HOME") || "/home/" + (Quickshell.env("USER") || "user")) + "/.config/quickshell/scripts/xdg-file-picker.py"

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
        if (currentWallpaper === filePath && allWallpapers.length > 0) {
            setWallpaper(allWallpapers[0].path)
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

    function toBase64(str) {
        if (!str) return ""
        const bytes = []
        for (let i = 0; i < str.length; i++) {
            const code = str.charCodeAt(i)
            if (code < 128) {
                bytes.push(code)
            } else if (code < 2048) {
                bytes.push((code >> 6) | 192, (code & 63) | 128)
            } else if ((code & 0xFC00) === 0xD800 && i + 1 < str.length && (str.charCodeAt(i + 1) & 0xFC00) === 0xDC00) {
                const surrogate = ((code & 0x03FF) << 10) + (str.charCodeAt(++i) & 0x03FF) + 0x10000
                bytes.push((surrogate >> 18) | 240, ((surrogate >> 12) & 63) | 128, ((surrogate >> 6) & 63) | 128, (surrogate & 63) | 128)
            } else {
                bytes.push((code >> 12) | 224, ((code >> 6) & 63) | 128, (code & 63) | 128)
            }
        }
        return Qt.btoa(bytes)
    }

    function saveConfig() {
        var data = {
            currentWallpaper: currentWallpaper,
            customWallpapers: customWallpapers
        }
        var jsonStr = JSON.stringify(data)
        var b64 = toBase64(jsonStr)
        saveConfigProc.running = false
        saveConfigProc.command = ["sh", "-c", "mkdir -p ~/.cache/quickshell && echo '" + b64 + "' | base64 -d > \"" + configPath + "\""]
        saveConfigProc.running = true
    }

    Process {
        id: killSwaybgProc
        command: ["sh", "-c", "pkill swaybg || true"]
    }

    // Process to run XDG File Chooser via python script
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

    readonly property string declConfigPath: (Quickshell.env("HOME") || "/home/" + (Quickshell.env("USER") || "user")) + "/.config/quickshell/wallpaper_config.json"

    // Process to load saved wallpaper config
    Process {
        id: loadConfigProc
        command: ["sh", "-c", "if [ -f \"" + declConfigPath + "\" ]; then cat \"" + declConfigPath + "\"; elif [ -f \"" + configPath + "\" ]; then cat \"" + configPath + "\"; else echo '{}'; fi"]
        stdout: SplitParser {
            onRead: data => {
                try {
                    var parsed = JSON.parse(data.trim())
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
            }
        }
    }

    // Process to save wallpaper config
    Process {
        id: saveConfigProc
    }
}
