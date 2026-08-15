pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string currentBranch: "main"
    property int mainBehindCount: 0
    property bool hasUpdate: mainBehindCount > 0
    property string commitLogs: ""
    property bool isChecking: false
    property bool isPulling: false
    property string lastError: ""
    property string lastCheckTime: ""
    property string pullMessage: ""

    property bool _previousHasUpdate: false

    Process {
        id: checkProc
        command: ["sh", "-c", "cd $HOME/.config/quickshell && b=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'main'); git fetch origin >/dev/null 2>&1; c=$(git rev-list --count main..origin/main 2>/dev/null || echo 0); echo \"$b|$c\"; echo \"---LOGS---\"; git log main..origin/main --oneline -n 5 2>/dev/null"]
        
        property string rawOutput: ""

        stdout: SplitParser {
            onRead: data => {
                checkProc.rawOutput += data + "\n"
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.isChecking = false
            if (exitCode === 0 && checkProc.rawOutput.length > 0) {
                const parts = checkProc.rawOutput.split("---LOGS---")
                if (parts.length >= 1) {
                    const meta = parts[0].trim().split("|")
                    if (meta.length >= 2) {
                        root.currentBranch = meta[0].trim()
                        root.mainBehindCount = parseInt(meta[1].trim()) || 0
                    }
                }
                
                if (parts.length >= 2) {
                    root.commitLogs = parts[1].trim()
                }

                const now = new Date()
                root.lastCheckTime = Qt.formatTime(now, "hh:mm")
                root.lastError = ""

                // Send notification if update newly detected on main
                if (root.hasUpdate && !root._previousHasUpdate) {
                    notifyProc.command = ["notify-send", "-a", "Quickshell Update", "Update Available", root.mainBehindCount + " new commit(s) available on main branch"]
                    notifyProc.running = true
                }
                root._previousHasUpdate = root.hasUpdate
            } else {
                root.lastError = "Failed to fetch source updates from remote"
            }
        }
    }

    Process {
        id: pullProc
        command: ["sh", "-c", "cd $HOME/.config/quickshell && if [ \"$(git rev-parse --abbrev-ref HEAD)\" != \"main\" ]; then git checkout main; fi && git pull origin main"]
        
        property string pullOutput: ""

        stdout: SplitParser {
            onRead: data => {
                pullProc.pullOutput += data + "\n"
            }
        }
        stderr: SplitParser {
            onRead: data => {
                pullProc.pullOutput += data + "\n"
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.isPulling = false
            if (exitCode === 0) {
                root.lastError = ""
                root.pullMessage = "Main branch updated successfully!"
                root.checkUpdates()
                notifyProc.command = ["notify-send", "-a", "Quickshell Update", "Quickshell Updated", "Successfully pulled latest source updates for main branch."]
                notifyProc.running = true
            } else {
                root.lastError = "Update pull failed: " + pullProc.pullOutput.trim()
                notifyProc.command = ["notify-send", "-u", "critical", "-a", "Quickshell Update", "Update Failed", "Git pull failed for main branch."]
                notifyProc.running = true
            }
        }
    }

    Process {
        id: notifyProc
    }

    function checkUpdates() {
        if (isChecking || isPulling) return
        isChecking = true
        checkProc.rawOutput = ""
        checkProc.running = true
    }

    function pullUpdates() {
        if (isPulling || isChecking) return
        isPulling = true
        pullProc.pullOutput = ""
        pullProc.running = true
    }

    // Periodically check every 15 minutes
    Timer {
        interval: 15 * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.checkUpdates()
    }

    // Initial check 2 seconds after startup
    Timer {
        interval: 2000
        running: true
        repeat: false
        onTriggered: root.checkUpdates()
    }
}
