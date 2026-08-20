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
    "zenity|zenity|zenity|zenity|zenity|XDG File Picker Dialog (fallback)|opt"
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

    # Detect which compositors are present
    HAS_HYPRLAND=false
    HAS_NIRI=false
    if command -v hyprland &>/dev/null; then
        HAS_HYPRLAND=true
    fi
    if command -v niri &>/dev/null; then
        HAS_NIRI=true
    fi

    for item in "${DEPENDENCIES[@]}"; do
        IFS='|' read -r cmd arch_pkg debian_pkg fedora_pkg nix_pkg desc req_type <<< "$item"
        
        status_check "$cmd ($desc)"
        sleep 0.05 # visual feedback for realtime scanning
        
        BIN_PATH=$(command -v "$cmd" 2>/dev/null || true)
        if [ -n "$BIN_PATH" ]; then
            INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
            success "$cmd ($desc) ${DIM}-> $BIN_PATH${NC}"
        else
            # Compositor mutual check:
            # If the user already has Hyprland or Niri installed, the other compositor is optional
            # and is skipped from missing required packages and install command.
            if [ "$cmd" = "hyprland" ] && [ "$HAS_NIRI" = true ]; then
                info "$cmd ($desc) ${DIM}-> (Optional - Niri is already installed)${NC}"
                continue
            elif [ "$cmd" = "niri" ] && [ "$HAS_HYPRLAND" = true ]; then
                info "$cmd ($desc) ${DIM}-> (Optional - Hyprland is already installed)${NC}"
                continue
            fi

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
            elif [ "$cmd" = "hyprland" ] || [ "$cmd" = "niri" ]; then
                warn "Missing compositor: '$cmd' ($desc - at least one compositor is needed)"
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
    
    # If neither compositor is installed, prompt user which one to install instead of forcing both
    if [ "$HAS_HYPRLAND" = false ] && [ "$HAS_NIRI" = false ]; then
        echo ""
        warn "No Wayland compositor detected. You need at least Hyprland or Niri to run Quickshell."
        if [ "$AUTO_YES" = true ]; then
            # In auto-yes mode, default to Hyprland
            UNIQUE_PKGS=($(printf '%s\n' "${UNIQUE_PKGS[@]}" | grep -v -E '^niri$'))
        elif [ "$CHECK_ONLY" = false ]; then
            echo -e "Which compositor would you like to install?"
            echo -e "  1) Hyprland ${DIM}(Recommended default)${NC}"
            echo -e "  2) Niri"
            echo -e "  3) Both"
            echo -e "  4) None ${DIM}(I will install/configure manually)${NC}"
            read -rp "Select compositor [1-4] (default: 1): " comp_sel
            case "$comp_sel" in
                2)
                    UNIQUE_PKGS=($(printf '%s\n' "${UNIQUE_PKGS[@]}" | grep -v -E '^hyprland$'))
                    ;;
                3)
                    # Keep both
                    ;;
                4)
                    UNIQUE_PKGS=($(printf '%s\n' "${UNIQUE_PKGS[@]}" | grep -v -E '^(hyprland|niri)$'))
                    ;;
                *)
                    UNIQUE_PKGS=($(printf '%s\n' "${UNIQUE_PKGS[@]}" | grep -v -E '^niri$'))
                    ;;
            esac
        fi
    fi
    
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

    HYPR_DIR="$HOME/.config/hypr"
    HYPR_CONFIG="$HYPR_DIR/hyprland.conf"
    HYPR_QS_CONF="$HYPR_DIR/quickshell.conf"
    HYPR_LUA_CONFIG="$HYPR_DIR/hyprland.lua"
    HYPR_QS_LUA="$HYPR_DIR/quickshell.lua"

    NIRI_DIR="$HOME/.config/niri"
    NIRI_CONFIG="$NIRI_DIR/config.kdl"
    NIRI_QS_KDL="$NIRI_DIR/quickshell.kdl"

    COMPOSITOR_FOUND=false

    # ── Hyprland Classic (.conf) ──────────────────────────────────────────────
    if [ -f "$HYPR_CONFIG" ] || [ -f "$HYPR_QS_CONF" ]; then
        COMPOSITOR_FOUND=true
        if grep -q -E "quickshell|qs ipc|quickshell\.conf" "$HYPR_CONFIG" 2>/dev/null || [ -f "$HYPR_QS_CONF" ]; then
            success "Hyprland configuration contains Quickshell integration."
            
            # Ensure ~/.config/hypr/quickshell.conf exists and is up to date if sourced
            if [ -f "$HYPR_QS_CONF" ] || grep -q "source = ~/.config/hypr/quickshell.conf" "$HYPR_CONFIG" 2>/dev/null; then
                UPDATE_QS_CONF=false
                if [ "$AUTO_YES" = true ]; then
                    UPDATE_QS_CONF=true
                else
                    read -rp "Would you like to refresh/update $HYPR_QS_CONF? [y/N] " update_resp
                    if [[ "$update_resp" =~ ^[Yy]$ ]]; then
                        UPDATE_QS_CONF=true
                    fi
                fi
                if [ "$UPDATE_QS_CONF" = true ]; then
                    cat << 'EOF' > "$HYPR_QS_CONF"
# ── Quickshell Desktop Environment Integration ──────────────────────────────
# Autostart Quickshell & clipboard daemon
exec-once = qs
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

# Screenshot Keybindings (Grim + Slurp + Swappy + Quickshell Notification)
bind = , PRINT,       exec, ~/.config/quickshell/scripts/screenshot.sh full
bind = SHIFT, PRINT,  exec, ~/.config/quickshell/scripts/screenshot.sh region
bind = SUPER, PRINT,  exec, ~/.config/quickshell/scripts/screenshot.sh window

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
layerrule = blur, quickshell:traymenu
layerrule = ignorezero, quickshell:traymenu
layerrule = blur, quickshell:trayoverflow
layerrule = ignorezero, quickshell:trayoverflow
EOF
                    success "Updated $HYPR_QS_CONF successfully."
                fi
            fi
        else
            warn "Hyprland config found at $HYPR_CONFIG (Quickshell integration not present)."
            INJECT_HYPR=false
            if [ "$AUTO_YES" = true ]; then
                INJECT_HYPR=true
            else
                read -rp "Would you like to integrate Quickshell into $HYPR_CONFIG? [y/N] " response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    INJECT_HYPR=true
                fi
            fi

            if [ "$INJECT_HYPR" = true ]; then
                BACKUP_HYPR="${HYPR_CONFIG}_backup_$(date +%Y%m%d_%H%M%S)"
                cp "$HYPR_CONFIG" "$BACKUP_HYPR"
                info "Backed up $HYPR_CONFIG to $BACKUP_HYPR"

                # Write modular quickshell.conf
                cat << 'EOF' > "$HYPR_QS_CONF"
# ── Quickshell Desktop Environment Integration ──────────────────────────────
# Autostart Quickshell & clipboard daemon
exec-once = qs
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

# Screenshot Keybindings (Grim + Slurp + Swappy + Quickshell Notification)
bind = , PRINT,       exec, ~/.config/quickshell/scripts/screenshot.sh full
bind = SHIFT, PRINT,  exec, ~/.config/quickshell/scripts/screenshot.sh region
bind = SUPER, PRINT,  exec, ~/.config/quickshell/scripts/screenshot.sh window

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
layerrule = blur, quickshell:traymenu
layerrule = ignorezero, quickshell:traymenu
layerrule = blur, quickshell:trayoverflow
layerrule = ignorezero, quickshell:trayoverflow
EOF
                # Add source line to hyprland.conf
                echo -e "\n# Quickshell Integration\nsource = ~/.config/hypr/quickshell.conf" >> "$HYPR_CONFIG"
                success "Created $HYPR_QS_CONF and added source directive to $HYPR_CONFIG"
            fi
        fi
    elif [ "$HAS_HYPRLAND" = true ] && [ ! -d "$HYPR_DIR" ]; then
        info "Hyprland is installed, but ~/.config/hypr does not exist."
        CREATE_HYPR=false
        if [ "$AUTO_YES" = true ]; then
            CREATE_HYPR=true
        else
            read -rp "Would you like to initialize ~/.config/hypr with Quickshell configuration? [y/N] " response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                CREATE_HYPR=true
            fi
        fi
        if [ "$CREATE_HYPR" = true ]; then
            mkdir -p "$HYPR_DIR"
            cp "$SCRIPT_DIR/examples/hyprland.conf" "$HYPR_CONFIG"
            success "Created starter Hyprland config at $HYPR_CONFIG"
            COMPOSITOR_FOUND=true
        fi
    fi

    # ── Hyprland Lua (.lua) ───────────────────────────────────────────────────
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
                read -rp "Would you like to auto-inject Quickshell integration into $HYPR_LUA_CONFIG? [y/N] " response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    INJECT_HYPR_LUA=true
                fi
            fi

            if [ "$INJECT_HYPR_LUA" = true ]; then
                BACKUP_HYPR_LUA="${HYPR_LUA_CONFIG}_backup_$(date +%Y%m%d_%H%M%S)"
                cp "$HYPR_LUA_CONFIG" "$BACKUP_HYPR_LUA"
                info "Backed up $HYPR_LUA_CONFIG to $BACKUP_HYPR_LUA"

                cat << 'EOF' >> "$HYPR_LUA_CONFIG"

-- ── Quickshell Desktop Environment Integration ──
hl.on("hyprland.start", function ()
    hl.exec_cmd("qs")
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

-- Screenshot Keybindings (Grim + Slurp + Swappy + Quickshell Notification)
hl.bind("print",               hl.dsp.exec_cmd("~/.config/quickshell/scripts/screenshot.sh full"),   { locked = true })
hl.bind("SHIFT + print",       hl.dsp.exec_cmd("~/.config/quickshell/scripts/screenshot.sh region"), { locked = true })
hl.bind(mainMod .. " + print", hl.dsp.exec_cmd("~/.config/quickshell/scripts/screenshot.sh window"), { locked = true })

hl.layer_rule({ match = { namespace = "quickshell:bar" },           blur = true })
hl.layer_rule({ match = { namespace = "quickshell:launcher" },      blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:clipboard" },     blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:controlcenter" }, blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:notifcenter" },   blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:dashboard" },     blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:calendar" },      blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:hud" },           blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:traymenu" },      blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:trayoverflow" },  blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "^quickshell:.*$" },          blur = true, ignore_alpha = 0 })
EOF
                success "Successfully injected Quickshell configuration into $HYPR_LUA_CONFIG"
            fi
        fi
    fi

    # ── Niri (.kdl) ───────────────────────────────────────────────────────────
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

// ── Quickshell Desktop Environment Integration ──
spawn-at-startup "qs"
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

    // Screenshot Keybindings (Grim + Slurp + Swappy + Quickshell Notification)
    Print       { spawn "sh" "-c" "~/.config/quickshell/scripts/screenshot.sh full"; }
    Shift+Print { spawn "sh" "-c" "~/.config/quickshell/scripts/screenshot.sh region"; }
    Mod+Print   { spawn "sh" "-c" "~/.config/quickshell/scripts/screenshot.sh window"; }
}
EOF
                success "Successfully injected Quickshell configuration into $NIRI_CONFIG"
            fi
        fi
    elif [ "$HAS_NIRI" = true ] && [ ! -d "$NIRI_DIR" ]; then
        info "Niri is installed, but ~/.config/niri does not exist."
        CREATE_NIRI=false
        if [ "$AUTO_YES" = true ]; then
            CREATE_NIRI=true
        else
            read -rp "Would you like to initialize ~/.config/niri with Quickshell configuration? [y/N] " response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                CREATE_NIRI=true
            fi
        fi
        if [ "$CREATE_NIRI" = true ]; then
            mkdir -p "$NIRI_DIR"
            cp "$SCRIPT_DIR/examples/niri.kdl" "$NIRI_CONFIG"
            success "Created starter Niri config at $NIRI_CONFIG"
            COMPOSITOR_FOUND=true
        fi
    fi

    if [ "$COMPOSITOR_FOUND" = false ]; then
        info "No existing Hyprland or Niri config detected in ~/.config."
        info "Example configs are ready to use in $SCRIPT_DIR/examples/:"
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
echo -e "${GREEN}${BOLD}====================================================${NC}"
echo -e "${GREEN}${BOLD}  Quickshell Setup & Installation Completed!       ${NC}"
echo -e "${GREEN}${BOLD}====================================================${NC}\n"

# 7. Post-Installation Quick Reference & Interactive Options
echo -e "${BOLD}1. Keybindings Cheat Sheet (Hyprland / Niri):${NC}"
echo -e "   ${CYAN}SUPER + SPACE${NC}  ->  App Launcher (Fuzzy search, Calculator, Categories)"
echo -e "   ${CYAN}SUPER + V${NC}      ->  Clipboard Manager (History, Pinning, Search, Clear)"
echo -e "   ${CYAN}SUPER + P${NC}      ->  Power Menu (Lock, Sleep, Reboot, Shutdown)"
echo -e "   ${CYAN}SUPER + L${NC}      ->  Lockscreen (PAM auth, Media Player, Wallpapers)"
echo -e "   ${CYAN}SUPER + D${NC}      ->  Dashboard (System Monitor, Sliders, Quick Notes)"
echo -e "   ${CYAN}SUPER + N${NC}      ->  Notification Center (History, DND Mode, Actions)"
echo -e "   ${CYAN}SUPER + C${NC}      ->  Control Center (Network, Bluetooth, Audio, Power)"
echo -e "   ${CYAN}PRINT${NC}          ->  Fullscreen Screenshot (Swappy editor & Quickshell notif)"
echo -e "   ${CYAN}SHIFT + PRINT${NC}  ->  Area Screenshot (Select region -> Swappy -> Quickshell notif)"
echo -e "   ${CYAN}SUPER + PRINT${NC}  ->  Window Screenshot (Select window -> Swappy -> Quickshell notif)"
echo ""

echo -e "${BOLD}2. Manual Launch & IPC Command Reference:${NC}"
echo -e "   Run Quickshell:     ${GREEN}qs${NC}  or  ${GREEN}quickshell${NC}"
echo -e "   View Live Logs:     ${GREEN}qs log${NC}"
echo -e "   Toggle Launcher:    ${GREEN}qs ipc call launcher toggle${NC}"
echo -e "   Toggle Dashboard:   ${GREEN}qs ipc call dashboard toggle${NC}"
echo -e "   Toggle Clipboard:   ${GREEN}qs ipc call clipboard toggle${NC}"
echo -e "   Toggle Control Ctr: ${GREEN}qs ipc call controlCenter toggle${NC}"
echo -e "   Toggle Notif Center:${GREEN}qs ipc call notifCenter toggle${NC}"
echo -e "   Toggle Power Menu:  ${GREEN}qs ipc call powermenu toggle${NC}"
echo -e "   Lock Screen:        ${GREEN}qs ipc call lockscreen lock${NC}"
echo ""

echo -e "${BOLD}3. Recommended System Daemons:${NC}"
echo -e "   Ensure these background services are enabled for full functionality:"
echo -e "   - Bluetooth:        ${DIM}sudo systemctl enable --now bluetooth${NC}"
echo -e "   - Power Profiles:   ${DIM}sudo systemctl enable --now power-profiles-daemon${NC}"
echo -e "   - NetworkManager:   ${DIM}sudo systemctl enable --now NetworkManager${NC}"
echo -e "   - UPower (Battery): ${DIM}sudo systemctl enable --now upower${NC}"
echo ""

# Interactive reload / launch offer if inside active session
if [ -n "$WAYLAND_DISPLAY" ]; then
    if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] || pgrep -x Hyprland &>/dev/null; then
        echo -e "${CYAN}Active Hyprland session detected.${NC}"
        if [ "$AUTO_YES" = false ]; then
            read -rp "Would you like to reload Hyprland config now? [y/N] " reload_resp
            if [[ "$reload_resp" =~ ^[Yy]$ ]]; then
                if command -v hyprctl &>/dev/null; then
                    hyprctl reload
                    success "Hyprland reloaded."
                fi
            fi
        fi
    elif [ -n "$NIRI_SOCKET" ] || pgrep -x niri &>/dev/null; then
        echo -e "${CYAN}Active Niri session detected.${NC}"
        if [ "$AUTO_YES" = false ]; then
            read -rp "Would you like to reload Niri config now? [y/N] " reload_resp
            if [[ "$reload_resp" =~ ^[Yy]$ ]]; then
                if command -v niri &>/dev/null; then
                    niri msg action reload-config
                    success "Niri reloaded."
                fi
            fi
        fi
    fi

    # Check if quickshell is currently running
    if pgrep -x quickshell &>/dev/null || pgrep -x qs &>/dev/null; then
        success "Quickshell is already running."
    else
        if [ "$AUTO_YES" = false ]; then
            read -rp "Would you like to start Quickshell now? [y/N] " start_resp
            if [[ "$start_resp" =~ ^[Yy]$ ]]; then
                if command -v qs &>/dev/null; then
                    nohup qs >/dev/null 2>&1 &
                    success "Quickshell launched in background (qs)."
                elif command -v quickshell &>/dev/null; then
                    nohup quickshell >/dev/null 2>&1 &
                    success "Quickshell launched in background (quickshell)."
                fi
            fi
        fi
    fi
fi

echo -e "\n${GREEN}${BOLD}Enjoy your new Quickshell desktop environment!${NC}\n"

