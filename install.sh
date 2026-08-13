#!/usr/bin/env bash
# Quickshell Configuration Install Script
# Automatically installs dependencies and sets up configuration directory

set -e

# Color definitions
BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

info() {
    echo -e "${BLUE}${BOLD}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}${BOLD}[OK]${NC} $1"
}

warn() {
    echo -e "${YELLOW}${BOLD}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}${BOLD}[ERROR]${NC} $1"
}

AUTO_YES=false
for arg in "$@"; do
    if [ "$arg" = "-y" ] || [ "$arg" = "--yes" ]; then
        AUTO_YES=true
    fi
done

echo -e "${BOLD}==========================================${NC}"
echo -e "${BOLD}  Quickshell Desktop Environment Installer ${NC}"
echo -e "${BOLD}==========================================${NC}\n"

# 1. Target config directory setup
TARGET_DIR="$HOME/.config/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$SCRIPT_DIR" != "$TARGET_DIR" ]; then
    info "Setting up configuration directory at $TARGET_DIR..."
    if [ -d "$TARGET_DIR" ] || [ -L "$TARGET_DIR" ]; then
        warn "$TARGET_DIR already exists."
        REPLACE=false
        if [ "$AUTO_YES" = true ]; then
            REPLACE=true
        else
            read -rp "Do you want to backup and replace $TARGET_DIR? [y/N] " response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                REPLACE=true
            fi
        fi

        if [ "$REPLACE" = true ]; then
            BACKUP_DIR="${TARGET_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
            mv "$TARGET_DIR" "$BACKUP_DIR"
            info "Backed up existing config to $BACKUP_DIR"
            cp -r "$SCRIPT_DIR" "$TARGET_DIR"
            success "Copied configuration to $TARGET_DIR"
        else
            info "Skipping directory copy. Continuing with dependency check..."
        fi
    else
        mkdir -p "$(dirname "$TARGET_DIR")"
        cp -r "$SCRIPT_DIR" "$TARGET_DIR"
        success "Copied configuration to $TARGET_DIR"
    fi
fi

# 2. Dependency Verification
info "Verifying required commands and utilities..."

REQUIRED_COMMANDS=(
    "qs:Quickshell UI framework"
    "hyprland:Hyprland compositor"
    "nmcli:NetworkManager"
    "bluetoothctl:BlueZ Bluetooth"
    "brightnessctl:Brightness control utility"
    "cliphist:Cliphist clipboard history"
    "wl-copy:wl-clipboard tool"
    "pactl:PulseAudio / PipeWire utility"
    "powerprofilesctl:Power profiles daemon"
    "upower:UPower battery daemon"
    "socat:socat socket tool"
    "fuser:psmisc utility"
    "wlogout:wlogout power menu (optional)"
)

MISSING_COUNT=0
for item in "${REQUIRED_COMMANDS[@]}"; do
    cmd="${item%%:*}"
    desc="${item#*:}"
    if command -v "$cmd" &>/dev/null; then
        success "Found $cmd ($desc)"
    else
        warn "Missing '$cmd' ($desc)"
        MISSING_COUNT=$((MISSING_COUNT + 1))
    fi
done

if [ $MISSING_COUNT -gt 0 ]; then
    warn "$MISSING_COUNT optional/required dependency command(s) missing. Refer to README.md for details."
fi

# 3. System Service Verification
if command -v systemctl &>/dev/null; then
    info "Verifying system services..."
    systemctl is-active --quiet NetworkManager || warn "NetworkManager service is not active. Enable with: sudo systemctl enable --now NetworkManager"
    systemctl is-active --quiet bluetooth || warn "Bluetooth service is not active. Enable with: sudo systemctl enable --now bluetooth"
    systemctl is-active --quiet power-profiles-daemon || warn "power-profiles-daemon service is not active. Enable with: sudo systemctl enable --now power-profiles-daemon"
fi

echo ""
success "Quickshell configuration setup complete!"
echo -e "${BOLD}Next Steps:${NC}"
echo -e "  1. Launch Quickshell:"
echo -e "     ${GREEN}qs -c ~/.config/quickshell${NC}"
echo -e "  2. Ensure clipboard history daemons are in your Hyprland config:"
echo -e "     ${GREEN}exec-once = wl-paste --type text --watch cliphist store${NC}"
echo -e "     ${GREEN}exec-once = wl-paste --type image --watch cliphist store${NC}"
