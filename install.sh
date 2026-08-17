#!/usr/bin/env bash
# Quickshell Configuration Install Script
# Automatically detects dependencies in real-time, verifies configuration directory,
# and offers live interactive installation.

# Color & Format definitions
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

status_check() {
    echo -ne "${CYAN}[CHECKING]${NC} $1...\r"
}

AUTO_YES=false
CHECK_ONLY=false

for arg in "$@"; do
    case "$arg" in
        -y|--yes)
            AUTO_YES=true
            ;;
        --check-only)
            CHECK_ONLY=true
            ;;
        -h|--help)
            echo "Usage: ./install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -y, --yes       Automatically answer yes to all prompts & installation"
            echo "  --check-only    Only perform real-time dependency detection check"
            echo "  -h, --help      Display this help message"
            exit 0
            ;;
    esac
done

echo -e "${BOLD}==========================================${NC}"
echo -e "${BOLD}  Quickshell Desktop Environment Installer ${NC}"
echo -e "${BOLD}==========================================${NC}\n"

# 0. Package Manager Real-Time Detection
detect_pkg_mgr() {
    if command -v yay &>/dev/null; then
        echo "yay"
    elif command -v paru &>/dev/null; then
        echo "paru"
    elif command -v pacman &>/dev/null; then
        echo "pacman"
    elif command -v apt &>/dev/null; then
        echo "apt"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v nix-env &>/dev/null; then
        echo "nix-env"
    elif command -v zypper &>/dev/null; then
        echo "zypper"
    elif command -v xbps-install &>/dev/null; then
        echo "xbps"
    else
        echo "unknown"
    fi
}

PKG_MGR=$(detect_pkg_mgr)
info "Detected Package Manager: ${BOLD}${PKG_MGR}${NC}"

# 1. Target config directory setup (skip if --check-only)
if [ "$CHECK_ONLY" = false ]; then
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
fi

# 2. Real-Time Dependency Verification
# Format: "cmd|arch_pkg|debian_pkg|fedora_pkg|nix_pkg|description|required"
DEPENDENCIES=(
    "qs|quickshell-git|quickshell|quickshell|quickshell|Quickshell UI framework|req"
    "hyprland|hyprland|hyprland|hyprland|hyprland|Hyprland compositor|opt"
    "niri|niri|niri|niri|niri|Niri Wayland compositor|opt"
    "nmcli|networkmanager|network-manager|NetworkManager|networkmanager|NetworkManager CLI|req"
    "bluetoothctl|bluez-utils|bluez|bluez-tools|bluez|BlueZ Bluetooth CLI|req"
    "brightnessctl|brightnessctl|brightnessctl|brightnessctl|brightnessctl|Brightness control utility|req"
    "cliphist|cliphist|cliphist|cliphist|cliphist|Cliphist clipboard history|req"
    "wl-copy|wl-clipboard|wl-clipboard|wl-clipboard|wl-clipboard|wl-clipboard tool|req"
    "pactl|libpulse|pulseaudio-utils|pulseaudio-utils|pulseaudio|PulseAudio / PipeWire utility|req"
    "powerprofilesctl|power-profiles-daemon|power-profiles-daemon|power-profiles-daemon|power-profiles-daemon|Power profiles daemon|req"
    "upower|upower|upower|upower|upower|UPower battery daemon|req"
    "socat|socat|socat|socat|socat|socat socket tool|req"
    "fuser|psmisc|psmisc|psmisc|psmisc|psmisc utility (camera detection)|req"
    "wlogout|wlogout|wlogout|wlogout|wlogout|wlogout power menu|opt"
)

run_dependency_check() {
    echo ""
    info "Performing real-time dependency detection..."
    echo -e "${DIM}--------------------------------------------------${NC}"

    MISSING_CMDS=()
    MISSING_PKGS=()
    INSTALLED_COUNT=0
    MISSING_COUNT=0

    for item in "${DEPENDENCIES[@]}"; do
        IFS='|' read -r cmd arch_pkg debian_pkg fedora_pkg nix_pkg desc req_type <<< "$item"
        
        status_check "$cmd ($desc)"
        sleep 0.05 # visual feedback for realtime scanning
        
        BIN_PATH=$(command -v "$cmd" 2>/dev/null || true)
        if [ -n "$BIN_PATH" ]; then
            INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
            success "$cmd ($desc) ${DIM}-> $BIN_PATH${NC}"
        else
            MISSING_COUNT=$((MISSING_COUNT + 1))
            MISSING_CMDS+=("$cmd")
            
            # Map package name based on detected package manager
            case "$PKG_MGR" in
                yay|paru|pacman)
                    MISSING_PKGS+=("$arch_pkg")
                    ;;
                apt)
                    MISSING_PKGS+=("$debian_pkg")
                    ;;
                dnf)
                    MISSING_PKGS+=("$fedora_pkg")
                    ;;
                nix-env)
                    MISSING_PKGS+=("$nix_pkg")
                    ;;
                *)
                    MISSING_PKGS+=("$arch_pkg")
                    ;;
            esac

            if [ "$req_type" = "req" ]; then
                error "Missing required command: '$cmd' ($desc)"
            else
                warn "Missing optional command: '$cmd' ($desc)"
            fi
        fi
    done

    # 3. Real-Time Font Verification
    status_check "Nerd Fonts / Icon Symbols"
    if command -v fc-list &>/dev/null; then
        if fc-list : family | grep -i -E "Nerd Font|SymbolsNerdFont|JetBrainsMono" &>/dev/null; then
            success "Found Nerd Fonts / Symbol icon font in fontconfig"
        else
            warn "No Nerd Fonts detected via fc-list (UI icons might render missing glyphs)"
            if [[ "$PKG_MGR" =~ ^(yay|paru|pacman)$ ]]; then
                MISSING_PKGS+=("ttf-nerd-fonts-symbols-mono")
            elif [ "$PKG_MGR" = "nix-env" ]; then
                MISSING_PKGS+=("nerd-fonts.symbols-only")
            fi
        fi
    else
        warn "fontconfig (fc-list) not installed, cannot verify font availability"
    fi

    # 4. Real-Time System Service Verification
    echo -e "${DIM}--------------------------------------------------${NC}"
    info "Verifying system services state..."

    check_service() {
        local service_name="$1"
        if command -v systemctl &>/dev/null; then
            if systemctl is-active --quiet "$service_name" 2>/dev/null; then
                success "Service '$service_name' is active and running"
            else
                warn "Service '$service_name' is not active (Enable with: sudo systemctl enable --now $service_name)"
            fi
        fi
    }

    check_service "NetworkManager"
    check_service "bluetooth"
    check_service "power-profiles-daemon"

    echo -e "${DIM}--------------------------------------------------${NC}"
    echo -e "${BOLD}Detection Summary:${NC} Installed: ${GREEN}${INSTALLED_COUNT}${NC} | Missing: ${RED}${MISSING_COUNT}${NC}"
}

run_dependency_check

# 5. Interactive Real-time Installation Offer
if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    # Remove duplicate package entries
    UNIQUE_PKGS=($(echo "${MISSING_PKGS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    
    echo ""
    warn "Missing package(s) detected: ${BOLD}${UNIQUE_PKGS[*]}${NC}"
    
    if [ "$PKG_MGR" != "unknown" ]; then
        INSTALL_CMD=""
        case "$PKG_MGR" in
            yay)
                INSTALL_CMD="yay -S --needed ${UNIQUE_PKGS[*]}"
                ;;
            paru)
                INSTALL_CMD="paru -S --needed ${UNIQUE_PKGS[*]}"
                ;;
            pacman)
                INSTALL_CMD="sudo pacman -S --needed ${UNIQUE_PKGS[*]}"
                ;;
            apt)
                INSTALL_CMD="sudo apt update && sudo apt install -y ${UNIQUE_PKGS[*]}"
                ;;
            dnf)
                INSTALL_CMD="sudo dnf install -y ${UNIQUE_PKGS[*]}"
                ;;
            nix-env)
                INSTALL_CMD="nix-env -iA ${UNIQUE_PKGS[*]/#/nixos.}"
                ;;
            zypper)
                INSTALL_CMD="sudo zypper install -y ${UNIQUE_PKGS[*]}"
                ;;
            xbps)
                INSTALL_CMD="sudo xbps-install -S ${UNIQUE_PKGS[*]}"
                ;;
        esac

        info "Suggested install command for $PKG_MGR:"
        echo -e "  ${CYAN}${INSTALL_CMD}${NC}\n"

        DO_INSTALL=false
        if [ "$AUTO_YES" = true ]; then
            DO_INSTALL=true
        elif [ "$CHECK_ONLY" = false ]; then
            read -rp "Would you like to install missing dependencies now using $PKG_MGR? [y/N] " install_resp
            if [[ "$install_resp" =~ ^[Yy]$ ]]; then
                DO_INSTALL=true
            fi
        fi

        if [ "$DO_INSTALL" = true ]; then
            info "Running installation command..."
            eval "$INSTALL_CMD"
            
            info "Re-running real-time dependency detection after installation..."
            run_dependency_check
        fi
    else
        warn "Could not auto-detect package manager. Please install missing packages manually."
    fi
fi

if [ "$CHECK_ONLY" = true ]; then
    echo ""
    info "Check complete (--check-only mode)."
    exit 0
fi

echo ""
success "Quickshell configuration setup complete!"
echo -e "${BOLD}Next Steps:${NC}"
echo -e "  1. Launch Quickshell:"
echo -e "     ${GREEN}qs -c ~/.config/quickshell${NC}"
echo -e "  2. Ensure clipboard history daemons are running in your Hyprland config:"
echo -e "     ${GREEN}exec-once = wl-paste --type text --watch cliphist store${NC}"
echo -e "     ${GREEN}exec-once = wl-paste --type image --watch cliphist store${NC}"

