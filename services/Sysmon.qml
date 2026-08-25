pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// High-precision unified system resource monitor (CPU, RAM, Temp, Disk, Uptime)
Singleton {
    id: root

    property real cpuUsage: 0    // 0-100
    property real ramUsage: 0    // 0-100
    property real cpuTemp: 0     // celsius
    property real diskUsage: 0   // 0-100
    property string ramUsedStr: ""
    property string ramTotalStr: ""
    property string ramDetailStr: (ramUsedStr && ramTotalStr) ? (ramUsedStr + " / " + ramTotalStr) : ramUsedStr
    property string diskUsedStr: ""
    property string diskTotalStr: ""
    property string diskDetailStr: (diskUsedStr && diskTotalStr) ? (diskUsedStr + " / " + diskTotalStr) : diskUsedStr
    property string uptimeStr: ""

    // Fast polling loop: updates every 2.5 seconds
    Timer {
        id: pollTimer
        interval: 2500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!sysmonProc.running) sysmonProc.running = true
        }
    }

    // Unified accurate read process
    Process {
        id: sysmonProc
        command: ["bash", Quickshell.env("HOME") + "/.config/quickshell/scripts/sysmon-helper.sh"]

        stdout: SplitParser {
            onRead: data => {
                const parts = data.trim().split("|")
                if (parts.length >= 9) {
                    // CPU
                    const cpu = parseFloat(parts[0])
                    if (!isNaN(cpu)) root.cpuUsage = Math.max(0, Math.min(100, cpu))

                    // RAM
                    const ram = parseFloat(parts[1])
                    if (!isNaN(ram)) root.ramUsage = Math.max(0, Math.min(100, ram))
                    root.ramUsedStr = parts[2] || ""
                    root.ramTotalStr = parts[3] || ""

                    // Temp
                    const tempRaw = parseFloat(parts[4])
                    if (!isNaN(tempRaw) && tempRaw > 0) {
                        root.cpuTemp = tempRaw > 1000 ? Math.round(tempRaw / 1000) : Math.round(tempRaw)
                    }

                    // Disk
                    const disk = parseFloat(parts[5])
                    if (!isNaN(disk)) root.diskUsage = Math.max(0, Math.min(100, disk))
                    root.diskUsedStr = parts[6] || ""
                    root.diskTotalStr = parts[7] || ""

                    // Uptime
                    if (parts[8] && parts[8].trim().length > 0) {
                        root.uptimeStr = parts[8].trim()
                    }
                }
            }
        }
    }
}
