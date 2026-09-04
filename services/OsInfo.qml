pragma Singleton
import QtQuick
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import "." as Services

// Reads /etc/os-release once at startup to auto-detect which distro
// this host is running, and manages user profile / avatar paths.
Singleton {
    id: root

    readonly property string homeDir: (Quickshell.env("HOME") || "/home/" + (Quickshell.env("USER") || "user"))
    readonly property string pickerScript: {
        var u = Qt.resolvedUrl("../scripts/xdg-file-picker.py").toString()
        var p = u.startsWith("file://") ? u.substring(7) : u
        return p.length > 0 ? p : (homeDir + "/.config/quickshell/scripts/xdg-file-picker.py")
    }

    readonly property var glyphMap: ({
        nixos:                "\u{f313}",
        gentoo:               "\u{f30d}",
        arch:                 "\u{f303}",
        archarm:              "\u{f303}",
        manjaro:              "\u{f312}",
        garuda:               "\u{f303}",
        endeavouros:          "\u{f322}",
        artix:                "\u{f31f}",
        debian:               "\u{f306}",
        ubuntu:               "\u{f31b}",
        linuxmint:            "\u{f30e}",
        mint:                 "\u{f30e}",
        pop:                  "\u{f32a}",
        elementary:           "\u{f309}",
        zorin:                "\u{f301}",
        raspbian:             "\u{f315}",
        steamos:              "\u{f31a}",
        kali:                 "\u{f327}",
        fedora:               "\u{f30a}",
        rhel:                 "\u{f316}",
        redhat:               "\u{f316}",
        centos:               "\u{f304}",
        rocky:                "\u{f304}",
        alma:                 "\u{f316}",
        opensuse:             "\u{f314}",
        "opensuse-tumbleweed":  "\u{f314}",
        "opensuse-leap":        "\u{f314}",
        suse:                 "\u{f314}",
        void:                 "\u{f32e}",
        alpine:               "\u{f300}",
        slackware:            "\u{f318}"
    })

    property string distroId: ""
    property string distroIdLike: ""
    property string distroName: ""
    property string username: ""
    property string hostname: ""
    property string kernel: ""
    property string shellName: ""
    property string systemAvatarPath: ""
    property bool isPickingAvatar: false

    readonly property bool isCustomAvatar: Boolean(Services.Config && Services.Config.customAvatar && Services.Config.customAvatar.trim().length > 0)

    property string avatarPath: {
        if (Services.Config && Services.Config.customAvatar && Services.Config.customAvatar.trim().length > 0) {
            var c = Services.Config.customAvatar.trim()
            return c.startsWith("file://") ? c : ("file://" + c)
        }
        if (systemAvatarPath && systemAvatarPath.length > 0) {
            return systemAvatarPath
        }
        return homeDir ? ("file://" + homeDir + "/.face") : ""
    }
    
    readonly property string logoGlyph: {
        if (glyphMap[distroId]) return glyphMap[distroId]
        if (distroIdLike.length > 0) {
            const likes = distroIdLike.toLowerCase().split(/\s+/)
            for (let i = 0; i < likes.length; i++) {
                if (glyphMap[likes[i]]) return glyphMap[likes[i]]
            }
        }
        return "\u{f17c}" // generic Tux fallback
    }

    readonly property string avatarHelperScript: {
        var u = Qt.resolvedUrl("../scripts/avatar-helper.py").toString()
        var p = u.startsWith("file://") ? u.substring(7) : u
        return p.length > 0 ? p : (homeDir + "/.config/quickshell/scripts/avatar-helper.py")
    }

    FileDialog {
        id: nativeAvatarDialog
        title: "Select Profile Picture"
        currentFolder: "file://" + root.homeDir + "/Pictures"
        nameFilters: ["Image files (*.jpg *.jpeg *.png *.webp *.gif *.bmp *.svg *.avif)", "All files (*)"]
        onAccepted: {
            var urlStr = nativeAvatarDialog.selectedFile.toString()
            var pathStr = urlStr.startsWith("file://") ? urlStr.substring(7) : urlStr
            if (pathStr.length > 0) {
                root.setCustomAvatar(pathStr)
            }
            root.isPickingAvatar = false
        }
        onRejected: {
            root.isPickingAvatar = false
        }
    }

    Process {
        id: avatarPickerProc
        command: ["python3", root.pickerScript, "Select Profile Picture"]
        stdout: SplitParser {
            onRead: data => {
                var selected = data.trim()
                if (selected.length > 0) {
                    root.setCustomAvatar(selected)
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.isPickingAvatar = false
        }
    }

    Process {
        id: avatarSyncProc
        command: ["python3", root.avatarHelperScript, "sync", (Services.Config && Services.Config.customAvatar) ? Services.Config.customAvatar : ""]
        stdout: SplitParser {
            onRead: data => {
                try {
                    var obj = JSON.parse(data.trim())
                    if (obj.fileUrl) {
                        root.systemAvatarPath = obj.fileUrl
                    } else if (obj.cleared) {
                        root.systemAvatarPath = ""
                    }
                } catch (e) {}
            }
        }
    }

    function setCustomAvatar(pathStr) {
        var clean = pathStr.startsWith("file://") ? pathStr.substring(7) : pathStr
        if (clean.length === 0) return
        if (Services.Config) Services.Config.setCustomAvatar(clean)
        avatarSyncProc.command = ["python3", root.avatarHelperScript, "set", clean]
        avatarSyncProc.running = false
        avatarSyncProc.running = true
    }

    function pickCustomAvatar() {
        root.isPickingAvatar = true
        try {
            nativeAvatarDialog.open()
        } catch (e) {
            avatarPickerProc.running = false
            avatarPickerProc.running = true
        }
    }

    function clearCustomAvatar() {
        if (Services.Config) Services.Config.clearCustomAvatar()
        avatarSyncProc.command = ["python3", root.avatarHelperScript, "clear"]
        avatarSyncProc.running = false
        avatarSyncProc.running = true
    }

    function refreshAvatar() {
        avatarProc.running = false
        avatarProc.running = true
    }

    Process {
        command: ["sh", "-c", "id=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '\"'); like=$(grep '^ID_LIKE=' /etc/os-release | cut -d= -f2 | tr -d '\"'); echo \"$id|$like\""]
        running: true
        stdout: SplitParser {
            onRead: data => {
                const parts = data.trim().toLowerCase().split("|")
                root.distroId = parts[0] || ""
                root.distroIdLike = parts[1] || ""
            }
        }
    }

    Process {
        command: ["sh", "-c", "p=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '\"'); u=$(id -un); h=$(uname -n); k=$(uname -r); s=$(basename \"$SHELL\"); echo \"$p|$u|$h|$k|$s\""]
        running: true
        stdout: SplitParser {
            onRead: data => {
                const parts = data.trim().split("|")
                if (parts.length >= 5) {
                    root.distroName = parts[0]
                    root.username = parts[1]
                    root.hostname = parts[2]
                    root.kernel = parts[3]
                    root.shellName = parts[4]
                    avatarProc.running = true
                }
            }
        }
    }

    Process {
        id: avatarProc
        command: ["python3", root.avatarHelperScript, "sync", (Services.Config && Services.Config.customAvatar) ? Services.Config.customAvatar : ""]
        running: true
        stdout: SplitParser {
            onRead: data => {
                try {
                    var obj = JSON.parse(data.trim())
                    if (obj.fileUrl && obj.fileUrl.length > 0) {
                        root.systemAvatarPath = obj.fileUrl
                    }
                } catch (e) {
                    const p = data.trim()
                    if (p.length > 0) root.systemAvatarPath = p
                }
            }
        }
    }
}
