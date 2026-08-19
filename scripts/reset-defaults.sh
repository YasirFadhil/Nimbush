#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell"
DEFAULTS_FILE="$CONFIG_DIR/defaults/settings_default.json"
SETTINGS_FILE="$CONFIG_DIR/user_settings.json"
CACHE_SETTINGS_FILE="$CACHE_DIR/user_settings.json"
BACKUP_FILE="$CONFIG_DIR/backup_settings.json"

MODE="${1:-settings}"

if [ "$MODE" = "full" ]; then
    echo "[Quickshell] Full reset requested. Restoring files from .backup_original..."
    if [ -d "$CONFIG_DIR/.backup_original" ]; then
        cp -rf "$CONFIG_DIR/.backup_original/"* "$CONFIG_DIR/"
        echo "[Quickshell] System files restored to original snapshot."
    else
        echo "[Quickshell] Warning: .backup_original directory not found!"
    fi
fi

echo "[Quickshell] Resetting user settings to factory defaults..."
mkdir -p "$CACHE_DIR"
if [ -f "$DEFAULTS_FILE" ]; then
    cp -f "$DEFAULTS_FILE" "$SETTINGS_FILE"
    cp -f "$DEFAULTS_FILE" "$CACHE_SETTINGS_FILE"
    echo "[Quickshell] Settings successfully reset to factory defaults."
else
    echo '{"themeMode":"light","accentColor":"#2c2c2e","accentName":"Graphite","cornerRadius":16,"uiScale":1.0,"barPosition":"top","barStyle":"islands","clock24h":true,"clockShowSeconds":false,"islandStyle":"expanded","workspaceStyle":"pills","soundFeedback":true,"notificationTimeout":5,"dndEnabled":false,"lockscreenClockStyle":"hero","showSysmonTray":true,"showBatteryTray":true,"firstRunCompleted":false,"customSettingsVersion":1}' > "$SETTINGS_FILE"
    cp -f "$SETTINGS_FILE" "$CACHE_SETTINGS_FILE"
    echo "[Quickshell] Fallback default settings written."
fi

# Send IPC notification if quickshell is running
if pgrep -x quickshell >/dev/null 2>&1; then
    quickshell ipc call config reload 2>/dev/null || true
fi

echo "[Quickshell] Reset complete."
