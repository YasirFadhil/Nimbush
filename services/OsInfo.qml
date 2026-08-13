pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Reads /etc/os-release once at startup to auto-detect which distro
// this host is running, so the bar's corner logo doesn't need to be
// hardcoded per-host (nixosss = NixOS vs Gentho = Gentoo).
Singleton {
    id: root

    readonly property var glyphMap: ({
        nixos:  "\u{f313}",
        gentoo: "\u{f30d}",
        arch:   "\u{f303}",
        debian: "\u{f306}",
        ubuntu: "\u{f31b}",
        fedora: "\u{f30a}"
    })

    property string distroId: ""
    property string distroName: ""
    property string username: ""
    property string hostname: ""
    property string kernel: ""
    property string shellName: ""
    property string avatarPath: Quickshell.env("HOME") ? ("file://" + Quickshell.env("HOME") + "/.face") : ""
    readonly property string logoGlyph: glyphMap[distroId] || "\u{f17c}" // generic Tux fallback

    Process {
        command: ["sh", "-c", "grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '\"'"]
        running: true
        stdout: SplitParser {
            onRead: data => root.distroId = data.trim().toLowerCase()
        }
    }

    Process {
        command: ["sh", "-c", "p=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '\"'); u=$(id -un); h=$(hostname); k=$(uname -r); s=$(basename \"$SHELL\"); echo \"$p|$u|$h|$k|$s\""]
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
        command: ["sh", "-c", "u=$(id -un); home=$(eval echo ~$u); f=\"/tmp/quickshell_avatar_${u}.jpg\"; for p in \"$home/.face\" \"$home/.face.icon\" \"$home/.face.jpg\" \"$home/.face.png\" \"/var/lib/AccountsService/icons/$u\"; do if [ -f \"$p\" ]; then ln -sf \"$p\" \"$f\"; echo \"file://$f\"; break; fi; done"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                const p = data.trim()
                if (p.length > 0) root.avatarPath = p
            }
        }
    }
}
