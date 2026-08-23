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
    property string avatarPath: Quickshell.env("HOME") ? ("file://" + Quickshell.env("HOME") + "/.face") : ""
    
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
