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
    readonly property string logoGlyph: glyphMap[distroId] || "\u{f17c}" // generic Tux fallback

    Process {
        command: ["sh", "-c", "grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '\"'"]
        running: true
        stdout: SplitParser {
            onRead: data => root.distroId = data.trim().toLowerCase()
        }
    }
}
