pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "." as Services

Singleton {
    id: root

    readonly property string homeDir: (Quickshell.env("HOME") || "/home/" + (Quickshell.env("USER") || "user"))
    readonly property string assetsDir: {
        var u = Qt.resolvedUrl("../assets/wallpapers").toString()
        var p = u.startsWith("file://") ? u.substring(7) : u
        return p.length > 0 ? p : (homeDir + "/.config/quickshell/assets/wallpapers")
    }

    readonly property string darkWallbler: assetsDir + "/wallbler.jpg"
    readonly property string lightWallbler: assetsDir + "/wallbler-light.jpg"

    readonly property bool isWallblerActive: currentWallpaper === darkWallbler || currentWallpaper === lightWallbler

    property string currentWallpaper: (Services.Config && Services.Config.themeMode === "light") ? lightWallbler : darkWallbler

    property var defaultWallpapers: [
        { 
            name: "Wallbler (Dynamic)", 
            path: (Services.Config && Services.Config.themeMode === "light") ? lightWallbler : darkWallbler,
            darkPath: darkWallbler,
            lightPath: lightWallbler,
            isDynamic: true,
            isCustom: false 
        }
    ]
    property var customWallpapers: []
    property var allWallpapers: []
    property bool isPicking: false

    readonly property string configPath: homeDir + "/.cache/quickshell/wallpaper_config.json"
    readonly property string declConfigPath: homeDir + "/.config/quickshell/wallpaper_config.json"
    readonly property string pickerScript: {
        var u = Qt.resolvedUrl("../scripts/xdg-file-picker.py").toString()
        var p = u.startsWith("file://") ? u.substring(7) : u
        return p.length > 0 ? p : (homeDir + "/.config/quickshell/scripts/xdg-file-picker.py")
    }

    onCurrentWallpaperChanged: {
        applyToSwww(currentWallpaper)
    }

    Component.onCompleted: {
        swwwDaemonProc.running = true
        updateAllList()
        loadConfigProc.running = true
        applyToSwww(currentWallpaper)
    }

    Connections {
        target: Services.Config
        function onConfigChanged() { root.handleThemeChange() }
        function onThemeModeChanged() { root.handleThemeChange() }
    }

    function handleThemeChange() {
        if (isWallblerActive) {
            var isLight = Services.Config && Services.Config.themeMode === "light"
            var target = isLight ? lightWallbler : darkWallbler
            if (currentWallpaper !== target) {
                currentWallpaper = target
                saveConfig()
                if (Services.Config && Services.Config.useMatugen) {
                    Services.Config.generateMatugen(target)
                }
            }
        }
        updateAllList()
    }

    function applyToSwww(filePath) {
        if (!filePath) return
        swwwProc.targetFile = filePath
        swwwProc.running = false
        swwwProc.running = true
    }

    function updateAllList() {
        var isLight = Services.Config && Services.Config.themeMode === "light"
        var list = [
            { 
                name: "Wallbler (Dynamic)", 
                path: isLight ? lightWallbler : darkWallbler,
                darkPath: darkWallbler,
                lightPath: lightWallbler,
                isDynamic: true,
                isCustom: false 
            }
        ]
        for (var j = 0; j < customWallpapers.length; j++) {
            list.push(customWallpapers[j])
        }
        allWallpapers = list
    }

    function setWallpaper(filePath) {
        if (!filePath) return
        
        // If Wallbler is selected (either dark or light variant or dynamic preset)
        if (filePath === darkWallbler || filePath === lightWallbler || filePath.indexOf("wallbler") !== -1) {
            var isLight = Services.Config && Services.Config.themeMode === "light"
            currentWallpaper = isLight ? lightWallbler : darkWallbler
        } else {
            currentWallpaper = filePath
        }

        saveConfig()
        if (Services.Config) {
            Services.Config.generateMatugen(currentWallpaper)
        }
    }

    property bool isPickingLockscreen: false

    Process {
        id: swwwDaemonProc
        command: ["sh", "-c", "pgrep -x swww-daemon >/dev/null || (nohup swww-daemon >/dev/null 2>&1 &)"]
    }

    Process {
        id: swwwProc
        property string targetFile: ""
        command: [
            "swww", "img", targetFile,
            "--transition-type", "grow",
            "--transition-pos", "center",
            "--transition-duration", "0.5",
            "--transition-fps", "60",
            "--transition-bezier", ".25,1,.5,1"
        ]
    }

    function pickCustomWallpaper() {
        if (isPicking) return
        isPicking = true
        pickerProc.running = false
        pickerProc.running = true
    }

    function pickLockscreenWallpaper() {
        if (isPickingLockscreen) return
        isPickingLockscreen = true
        lockscreenPickerProc.running = false
        lockscreenPickerProc.running = true
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
            var isLight = Services.Config && Services.Config.themeMode === "light"
            setWallpaper(isLight ? lightWallbler : darkWallbler)
        } else {
            saveConfig()
        }
    }

    function deleteCustomWallpaper(filePath) {
        removeCustomWallpaper(filePath)
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

    Timer {
        id: saveDebounceTimer
        interval: 350
        repeat: false
        onTriggered: {
            var data = {
                currentWallpaper: root.currentWallpaper,
                customWallpapers: root.customWallpapers
            }
            var jsonStr = JSON.stringify(data, null, 2)
            saveConfigProc.running = false
            saveConfigProc.command = [
                "sh", "-c",
                "mkdir -p ~/.cache/quickshell && " +
                "cat << 'EOF' > \"" + root.configPath + "\"\n" + jsonStr + "\nEOF\n" +
                "(cat << 'EOF' > \"" + root.declConfigPath + "\"\n" + jsonStr + "\nEOF) 2>/dev/null || true"
            ]
            saveConfigProc.running = true
        }
    }

    function saveConfig() {
        saveDebounceTimer.restart()
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

    // Process to pick dedicated custom wallpaper for lockscreen
    Process {
        id: lockscreenPickerProc
        command: ["python3", root.pickerScript]
        stdout: SplitParser {
            onRead: data => {
                var selected = data.trim()
                if (selected.length > 0 && Services.Config) {
                    Services.Config.setLockscreenCustomWallpaper(selected)
                    Services.Config.setLockscreenWallpaperMode("custom")
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.isPickingLockscreen = false
        }
    }

    // Process to load saved wallpaper config
    Process {
        id: loadConfigProc
        property string rawData: ""
        command: [
            "sh", "-c",
            "if [ -f \"" + configPath + "\" ]; then tr -d '\\r\\n' < \"" + configPath + "\"; " +
            "elif [ -f \"" + declConfigPath + "\" ]; then tr -d '\\r\\n' < \"" + declConfigPath + "\"; " +
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
                    }
                    if (parsed && parsed.currentWallpaper && parsed.currentWallpaper.length > 0) {
                        root.setWallpaper(parsed.currentWallpaper)
                    } else {
                        var isLight = Services.Config && Services.Config.themeMode === "light"
                        root.setWallpaper(isLight ? root.lightWallbler : root.darkWallbler)
                    }
                } catch (e) {
                    var isLight2 = Services.Config && Services.Config.themeMode === "light"
                    root.setWallpaper(isLight2 ? root.lightWallbler : root.darkWallbler)
                }
            } else {
                var isLight3 = Services.Config && Services.Config.themeMode === "light"
                root.setWallpaper(isLight3 ? root.lightWallbler : root.darkWallbler)
            }
            root.updateAllList()
        }
    }

    Process {
        id: saveConfigProc
    }
}
