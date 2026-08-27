pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// High-precision unified system resource & task manager monitor
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

    // Real-time Sparkline History (16 samples)
    property var cpuHistory: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property var ramHistory: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

    // Hardware metadata
    property string cpuModel: "Processor"
    property int cpuCores: 1

    // Task / process list state
    property var processes: []
    property string sortBy: "cpu" // "cpu", "mem", "name"
    property string filterType: "all" // "all", "apps"
    property string searchQuery: ""
    property bool isLoadingTasks: false
    property bool isPaused: false
    property int lastKilledPid: -1
    property string lastActionMessage: ""

    // Fast polling loop for basic stats: updates every 2.5 seconds
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

    // Dynamic tasks polling loop: updates every 4 seconds when sysmon panel is active and not paused
    Timer {
        id: tasksTimer
        interval: 4000
        running: (typeof OverlayManager !== "undefined" ? OverlayManager.sysmonPanelVisible : false) && !root.isPaused && root.searchQuery === ""
        repeat: true
        onTriggered: {
            refreshTasks()
        }
    }

    // Basic system metrics process
    Process {
        id: sysmonProc
        command: ["bash", Quickshell.env("HOME") + "/.config/quickshell/scripts/sysmon-helper.sh"]

        stdout: SplitParser {
            onRead: data => {
                const parts = data.trim().split("|")
                if (parts.length >= 9) {
                    // CPU
                    const cpu = parseFloat(parts[0])
                    if (!isNaN(cpu)) {
                        root.cpuUsage = Math.max(0, Math.min(100, cpu))
                        let ch = root.cpuHistory.slice(1)
                        ch.push(root.cpuUsage)
                        root.cpuHistory = ch
                    }

                    // RAM
                    const ram = parseFloat(parts[1])
                    if (!isNaN(ram)) {
                        root.ramUsage = Math.max(0, Math.min(100, ram))
                        let rh = root.ramHistory.slice(1)
                        rh.push(root.ramUsage)
                        root.ramHistory = rh
                    }
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

    // Hardware info process
    Process {
        id: cpuInfoProc
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/tasks-helper.py", "info"]
        running: true

        stdout: SplitParser {
            onRead: data => {
                try {
                    const info = JSON.parse(data.trim())
                    if (info.model) root.cpuModel = info.model
                    if (info.cores) root.cpuCores = info.cores
                } catch (e) {}
            }
        }
    }

    // Task list fetch process
    Process {
        id: tasksProc
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/tasks-helper.py", "list", root.sortBy, root.searchQuery]

        stdout: SplitParser {
            splitMarker: ""
            onRead: data => {
                root.isLoadingTasks = false
                try {
                    const procs = JSON.parse(data.trim())
                    if (Array.isArray(procs)) {
                        root.processes = procs
                    }
                } catch (e) {}
            }
        }

        onExited: (exitCode) => {
            root.isLoadingTasks = false
        }
    }

    // Task kill process
    Process {
        id: killProc
        property int targetPid: -1
        property int sigNum: 15
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/tasks-helper.py", "kill", String(targetPid), String(sigNum)]

        stdout: SplitParser {
            onRead: data => {
                try {
                    const res = JSON.parse(data.trim())
                    if (res.success) {
                        root.lastKilledPid = res.pid
                        root.lastActionMessage = "Process " + res.pid + " killed"
                        // Instantly remove from local array
                        const updated = []
                        for (let i = 0; i < root.processes.length; i++) {
                            if (root.processes[i].pid !== res.pid) {
                                updated.push(root.processes[i])
                            }
                        }
                        root.processes = updated
                    } else {
                        root.lastActionMessage = res.error || "Failed to kill process"
                    }
                } catch (e) {}
            }
        }

        onExited: (exitCode) => {
            refreshTasks()
        }
    }

    // Public functions
    function refreshTasks() {
        if (tasksProc.running) return
        root.isLoadingTasks = true
        tasksProc.command = ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/tasks-helper.py", "list", root.sortBy, root.searchQuery]
        tasksProc.running = true
    }

    function setSort(s) {
        if (root.sortBy === s) return
        root.sortBy = s
        refreshTasks()
    }

    function setSearch(q) {
        root.searchQuery = q
        refreshTasks()
    }

    function killTask(pid, force) {
        killProc.targetPid = pid
        killProc.sigNum = force ? 9 : 15
        killProc.running = true
    }

    function togglePause() {
        root.isPaused = !root.isPaused
    }

    function launchTaskManager() {
        const termCmd = ["sh", "-c", "kitty -e btop || kitty -e htop || foot -e btop || foot -e htop || alacritty -e btop || alacritty -e htop || xdg-terminal-exec htop || mission-center &"]
        Quickshell.process(termCmd)
    }
}
