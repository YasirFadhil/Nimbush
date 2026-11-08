pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Central state
    property bool connected: false
    property string interfaceName: ""
    property string ipv4Address: ""
    readonly property string glyph: "\udb80\ude00" // U+F0200 nf-md-ethernet

    // Compatibility aliases
    readonly property bool ethConnected: connected
    readonly property string ethIface: interfaceName
    readonly property string ethIp: ipv4Address
    readonly property string ethGlyph: glyph

    Process {
        id: ethProc
        command: ["sh", "-c",
            "for d in /sys/class/net/en* /sys/class/net/eth*; do "
            + "[ -e \"$d\" ] || continue; n=${d##*/}; "
            + "if [ \"$(cat $d/operstate 2>/dev/null)\" = up ]; then "
            + "echo \"$n|$(ip -4 -o addr show dev $n 2>/dev/null | head -1)\"; exit 0; fi; "
            + "done; echo none"]
        stdout: StdioCollector {
            onStreamFinished: {
                const line = text.trim()
                if (line === "" || line === "none") {
                    root.connected = false
                    root.interfaceName = ""
                    root.ipv4Address = ""
                    return
                }
                const parts = line.split("|")
                const f = (parts[1] || "").trim().split(/\s+/)
                root.connected = true
                root.interfaceName = parts[0]
                root.ipv4Address = f.length > 3 ? f[3].split("/")[0] : ""
            }
        }
    }

    // Event-driven: single system-wide monitor process for link and address events
    Process {
        id: ethMonitor
        command: ["ip", "monitor", "link", "address"]
        running: true
        stdout: SplitParser { onRead: ethDebounce.restart() }
    }

    Timer {
        id: ethDebounce
        interval: 300
        repeat: false
        onTriggered: if (!ethProc.running) ethProc.running = true
    }

    // Fallback polling (infrequent at 15s)
    Timer {
        interval: 15000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: if (!ethProc.running) ethProc.running = true
    }

    function refresh() {
        if (!ethProc.running) ethProc.running = true
    }
}
