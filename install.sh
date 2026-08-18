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
    elif command -v apk &>/dev/null; then
        echo "apk"
    elif command -v emerge &>/dev/null; then
        echo "emerge"
    elif command -v eopkg &>/dev/null; then
        echo "eopkg"
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
    "paplay|libpulse|pulseaudio-utils|pulseaudio-utils|pulseaudio|Sound feedback playback|req"
    "powerprofilesctl|power-profiles-daemon|power-profiles-daemon|power-profiles-daemon|power-profiles-daemon|Power profiles daemon|req"
    "upower|upower|upower|upower|upower|UPower battery daemon|req"
    "socat|socat|socat|socat|socat|socat socket tool|req"
    "fuser|psmisc|psmisc|psmisc|psmisc|psmisc camera detection|req"
    "pkill|procps-ng|procps|procps-ng|procps|Procps process management|req"
    "notify-send|libnotify|libnotify-bin|libnotify|libnotify|Desktop notification tool|req"
    "git|git|git|git|git|Git version control|req"
    "dbus-monitor|dbus|dbus|dbus-tools|dbus|D-Bus system monitor|req"
    "gdbus|glib2|libglib2.0-bin|glib2|glib|GDBus tool for XDG portal|req"
    "grim|grim|grim|grim|grim|Wayland screenshot capture|req"
    "slurp|slurp|slurp|slurp|slurp|Wayland region selector|req"
    "swappy|swappy|swappy|swappy|swappy|Screenshot editor|opt"
    "python3|python|python3|python3|python3|Python 3 interpreter|req"
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
        NIX_PREFIX="nixpkgs."
        if nix-env -q -a nixos.hello &>/dev/null 2>&1; then
            NIX_PREFIX="nixos."
        fi

        case "$PKG_MGR" in
            yay)
                if [ "$AUTO_YES" = true ]; then
                    INSTALL_CMD="yay -S --needed --noconfirm ${UNIQUE_PKGS[*]}"
                else
                    INSTALL_CMD="yay -S --needed ${UNIQUE_PKGS[*]}"
                fi
                ;;
            paru)
                if [ "$AUTO_YES" = true ]; then
                    INSTALL_CMD="paru -S --needed --noconfirm ${UNIQUE_PKGS[*]}"
                else
                    INSTALL_CMD="paru -S --needed ${UNIQUE_PKGS[*]}"
                fi
                ;;
            pacman)
                if [ "$AUTO_YES" = true ]; then
                    INSTALL_CMD="sudo pacman -S --needed --noconfirm ${UNIQUE_PKGS[*]}"
                else
                    INSTALL_CMD="sudo pacman -S --needed ${UNIQUE_PKGS[*]}"
                fi
                ;;
            apt)
                if [ "$AUTO_YES" = true ]; then
                    INSTALL_CMD="sudo apt update && sudo apt install -y ${UNIQUE_PKGS[*]}"
                else
                    INSTALL_CMD="sudo apt update && sudo apt install ${UNIQUE_PKGS[*]}"
                fi
                ;;
            dnf)
                if [ "$AUTO_YES" = true ]; then
                    INSTALL_CMD="sudo dnf install -y ${UNIQUE_PKGS[*]}"
                else
                    INSTALL_CMD="sudo dnf install ${UNIQUE_PKGS[*]}"
                fi
                ;;
            nix-env)
                NIX_ATTRS=()
                for pkg in "${UNIQUE_PKGS[@]}"; do
                    NIX_ATTRS+=("${NIX_PREFIX}${pkg}")
                done
                INSTALL_CMD="nix-env -iA ${NIX_ATTRS[*]}"
                ;;
            zypper)
                if [ "$AUTO_YES" = true ]; then
                    INSTALL_CMD="sudo zypper install -y ${UNIQUE_PKGS[*]}"
                else
                    INSTALL_CMD="sudo zypper install ${UNIQUE_PKGS[*]}"
                fi
                ;;
            xbps)
                if [ "$AUTO_YES" = true ]; then
                    INSTALL_CMD="sudo xbps-install -Sy ${UNIQUE_PKGS[*]}"
                else
                    INSTALL_CMD="sudo xbps-install -S ${UNIQUE_PKGS[*]}"
                fi
                ;;
            apk)
                INSTALL_CMD="sudo apk add ${UNIQUE_PKGS[*]}"
                ;;
            emerge)
                INSTALL_CMD="sudo emerge -av ${UNIQUE_PKGS[*]}"
                ;;
            eopkg)
                if [ "$AUTO_YES" = true ]; then
                    INSTALL_CMD="sudo eopkg it -y ${UNIQUE_PKGS[*]}"
                else
                    INSTALL_CMD="sudo eopkg it ${UNIQUE_PKGS[*]}"
                fi
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
            if bash -c "$INSTALL_CMD"; then
                success "Dependency installation executed successfully."
            else
                error "Installation command encountered errors. You may need to run it manually."
            fi
            
            info "Re-running real-time dependency detection after installation..."
            run_dependency_check
        fi
    else
        warn "Could not auto-detect package manager. Please install missing packages manually."
    fi
fi

# 6. Compositor Configuration Auto-Detection & Setup
setup_compositor_configs() {
    if [ "$CHECK_ONLY" = true ]; then
        return 0
    fi

    echo -e "${DIM}--------------------------------------------------${NC}"
    info "Scanning compositor configurations in ~/.config..."

    HYPR_CONFIG="$HOME/.config/hypr/hyprland.conf"
    HYPR_LUA_CONFIG="$HOME/.config/hypr/hyprland.lua"
    NIRI_CONFIG="$HOME/.config/niri/config.kdl"
    COMPOSITOR_FOUND=false

    # Hyprland (.conf) check & injection
    if [ -f "$HYPR_CONFIG" ]; then
        COMPOSITOR_FOUND=true
        if grep -q -E "quickshell|qs ipc" "$HYPR_CONFIG"; then
            success "Hyprland configuration at $HYPR_CONFIG already contains Quickshell integration."
        else
            warn "Hyprland config found at $HYPR_CONFIG (Quickshell integration not present)."
            INJECT_HYPR=false
            if [ "$AUTO_YES" = true ]; then
                INJECT_HYPR=true
            else
                read -rp "Would you like to auto-inject Quickshell autostart, binds & layer rules into $HYPR_CONFIG? [y/N] " response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    INJECT_HYPR=true
                fi
            fi

            if [ "$INJECT_HYPR" = true ]; then
                BACKUP_HYPR="${HYPR_CONFIG}_backup_$(date +%Y%m%d_%H%M%S)"
                cp "$HYPR_CONFIG" "$BACKUP_HYPR"
                info "Backed up $HYPR_CONFIG to $BACKUP_HYPR"

                cat << 'EOF' >> "$HYPR_CONFIG"

# ── Quickshell Shell Integration ──
exec-once = qs -c ~/.config/quickshell
exec-once = wl-paste --type text --watch cliphist store
exec-once = wl-paste --type image --watch cliphist store

# Quickshell Keybindings
bind = SUPER, SPACE, exec, qs ipc call launcher toggle
bind = SUPER, V,     exec, qs ipc call clipboard toggle
bind = SUPER, P,     exec, qs ipc call powermenu toggle
bind = SUPER, L,     exec, qs ipc call lockscreen toggle
bind = SUPER, D,     exec, qs ipc call dashboard toggle
bind = SUPER, N,     exec, qs ipc call notifCenter toggle
bind = SUPER, C,     exec, qs ipc call controlCenter toggle

# Quickshell Layer Rules (Blur & Transparency)
layerrule = blur, quickshell:bar
layerrule = blur, quickshell:launcher
layerrule = ignorezero, quickshell:launcher
layerrule = blur, quickshell:clipboard
layerrule = ignorezero, quickshell:clipboard
layerrule = blur, quickshell:controlcenter
layerrule = ignorezero, quickshell:controlcenter
layerrule = blur, quickshell:notifcenter
layerrule = ignorezero, quickshell:notifcenter
layerrule = blur, quickshell:dashboard
layerrule = ignorezero, quickshell:dashboard
layerrule = blur, quickshell:calendar
layerrule = ignorezero, quickshell:calendar
layerrule = blur, quickshell:hud
layerrule = ignorezero, quickshell:hud
EOF
                success "Successfully injected Quickshell configuration into $HYPR_CONFIG"
            fi
        fi
    fi

    # Hyprland (.lua) check & injection
    if [ -f "$HYPR_LUA_CONFIG" ]; then
        COMPOSITOR_FOUND=true
        if grep -q -E "quickshell|qs ipc" "$HYPR_LUA_CONFIG"; then
            success "Hyprland Lua configuration at $HYPR_LUA_CONFIG already contains Quickshell integration."
        else
            warn "Hyprland Lua config found at $HYPR_LUA_CONFIG (Quickshell integration not present)."
            INJECT_HYPR_LUA=false
            if [ "$AUTO_YES" = true ]; then
                INJECT_HYPR_LUA=true
            else
                read -rp "Would you like to auto-inject Quickshell autostart, binds & layer rules into $HYPR_LUA_CONFIG? [y/N] " response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    INJECT_HYPR_LUA=true
                fi
            fi

            if [ "$INJECT_HYPR_LUA" = true ]; then
                BACKUP_HYPR_LUA="${HYPR_LUA_CONFIG}_backup_$(date +%Y%m%d_%H%M%S)"
                cp "$HYPR_LUA_CONFIG" "$BACKUP_HYPR_LUA"
                info "Backed up $HYPR_LUA_CONFIG to $BACKUP_HYPR_LUA"

                cat << 'EOF' >> "$HYPR_LUA_CONFIG"

-- ── Quickshell Shell Integration ──
hl.on("hyprland.start", function ()
    hl.exec_cmd("qs -c ~/.config/quickshell")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)

local mainMod = "SUPER"
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd("qs ipc call launcher toggle"))
hl.bind(mainMod .. " + V",     hl.dsp.exec_cmd("qs ipc call clipboard toggle"))
hl.bind(mainMod .. " + P",     hl.dsp.exec_cmd("qs ipc call powermenu toggle"))
hl.bind(mainMod .. " + L",     hl.dsp.exec_cmd("qs ipc call lockscreen toggle"))
hl.bind(mainMod .. " + D",     hl.dsp.exec_cmd("qs ipc call dashboard toggle"))
hl.bind(mainMod .. " + N",     hl.dsp.exec_cmd("qs ipc call notifCenter toggle"))
hl.bind(mainMod .. " + C",     hl.dsp.exec_cmd("qs ipc call controlCenter toggle"))

hl.layer_rule({ match = { namespace = "quickshell:bar" },           blur = true })
hl.layer_rule({ match = { namespace = "quickshell:launcher" },      blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:clipboard" },     blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:controlcenter" }, blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:notifcenter" },   blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:dashboard" },     blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:calendar" },      blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:hud" },           blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "^quickshell:.*$" },          blur = true, ignore_alpha = 0 })
EOF
                success "Successfully injected Quickshell configuration into $HYPR_LUA_CONFIG"
            fi
        fi
    fi

    # Niri check & injection
    if [ -f "$NIRI_CONFIG" ]; then
        COMPOSITOR_FOUND=true
        if grep -q -E "quickshell|qs ipc" "$NIRI_CONFIG"; then
            success "Niri configuration at $NIRI_CONFIG already contains Quickshell integration."
        else
            warn "Niri config found at $NIRI_CONFIG (Quickshell integration not present)."
            INJECT_NIRI=false
            if [ "$AUTO_YES" = true ]; then
                INJECT_NIRI=true
            else
                read -rp "Would you like to auto-inject Quickshell autostart & binds into $NIRI_CONFIG? [y/N] " response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    INJECT_NIRI=true
                fi
            fi

            if [ "$INJECT_NIRI" = true ]; then
                BACKUP_NIRI="${NIRI_CONFIG}_backup_$(date +%Y%m%d_%H%M%S)"
                cp "$NIRI_CONFIG" "$BACKUP_NIRI"
                info "Backed up $NIRI_CONFIG to $BACKUP_NIRI"

                cat << 'EOF' >> "$NIRI_CONFIG"

// ── Quickshell Shell Integration ──
spawn-at-startup "qs" "-c" "~/.config/quickshell"
spawn-at-startup "wl-paste" "--type" "text" "--watch" "cliphist" "store"
spawn-at-startup "wl-paste" "--type" "image" "--watch" "cliphist" "store"

binds {
    Mod+Space { spawn "qs" "ipc" "call" "launcher" "toggle"; }
    Mod+V     { spawn "qs" "ipc" "call" "clipboard" "toggle"; }
    Mod+P     { spawn "qs" "ipc" "call" "powermenu" "toggle"; }
    Mod+L     { spawn "qs" "ipc" "call" "lockscreen" "toggle"; }
    Mod+D     { spawn "qs" "ipc" "call" "dashboard" "toggle"; }
    Mod+N     { spawn "qs" "ipc" "call" "notifCenter" "toggle"; }
    Mod+C     { spawn "qs" "ipc" "call" "controlCenter" "toggle"; }
}
EOF
                success "Successfully injected Quickshell configuration into $NIRI_CONFIG"
            fi
        fi
    fi

    if [ "$COMPOSITOR_FOUND" = false ]; then
        info "No existing Hyprland or Niri config detected in ~/.config."
        info "Example configs are available in $SCRIPT_DIR/examples/"
        info "  - Hyprland (conf): $SCRIPT_DIR/examples/hyprland.conf"
        info "  - Hyprland (lua):  $SCRIPT_DIR/examples/hyprland.lua"
        info "  - Niri:            $SCRIPT_DIR/examples/niri.kdl"
    fi
}

setup_compositor_configs

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
echo -e "  2. Restart your Hyprland / Niri compositor or reload keybindings."

