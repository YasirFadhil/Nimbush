#!/usr/bin/env bash
# ==============================================================================
# Nimbush Wayland Desktop Environment Installer
# Interactive setup, real-time dependency resolver & compositor injector
# First-class support for Arch, Debian/Ubuntu, Fedora, NixOS, openSUSE & more.
# ==============================================================================

set -o pipefail

# ── Color & Styling Definitions ───────────────────────────────────────────────
BOLD='\033[1m'
DIM='\033[2m'
ITALIC='\033[3m'
UNDERLINE='\033[4m'

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'

NC='\033[0m' # No Color

# ── Logging & UI Helpers ──────────────────────────────────────────────────────
info() {
    echo -e " ${BLUE}${BOLD}::${NC} $1"
}

success() {
    echo -e " ${GREEN}${BOLD}✔${NC} $1"
}

warn() {
    echo -e " ${YELLOW}${BOLD}!${NC} $1"
}

error() {
    echo -e " ${RED}${BOLD}✖${NC} $1"
}

step_header() {
    echo -e "\n${MAGENTA}${BOLD}┌── [ $1 ]${NC}"
}

step_footer() {
    echo -e "${MAGENTA}${BOLD}└──${NC}\n"
}

# ── CLI Arguments & Mode Flags ────────────────────────────────────────────────
AUTO_YES=false
CHECK_ONLY=false
INJECT_ONLY=false
SKIP_DEPS=false
SHOW_NIX_GUIDE=false
CLI_COMPOSITOR=""

print_help() {
    echo -e "${BOLD}Nimbush Wayland Desktop Environment Installer${NC}"
    echo ""
    echo -e "${BOLD}Usage:${NC} ./install.sh [OPTIONS]"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo "  -y, --yes          Non-interactive mode (automatically answer yes to prompts)"
    echo "  --check-only       Only perform real-time dependency and health diagnostics"
    echo "  --inject-only      Only run compositor configuration injection (Hyprland / Niri)"
    echo "  --hyprland         Target Hyprland compositor (auto-detects Lua or Classic format)"
    echo "  --niri             Target Niri scrollable compositor"
    echo "  --skip-deps        Skip dependency package checking & installation"
    echo "  --nix-guide        Display NixOS & Home Manager declarative setup instructions"
    echo "  -h, --help         Show this help message and exit"
    echo ""
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes)
            AUTO_YES=true
            shift
            ;;
        --check-only)
            CHECK_ONLY=true
            shift
            ;;
        --inject-only)
            INJECT_ONLY=true
            shift
            ;;
        --hyprland)
            CLI_COMPOSITOR="hyprland"
            shift
            ;;
        --niri)
            CLI_COMPOSITOR="niri"
            shift
            ;;
        --skip-deps)
            SKIP_DEPS=true
            shift
            ;;
        --nix-guide)
            SHOW_NIX_GUIDE=true
            shift
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            print_help
            exit 1
            ;;
    esac
done

# ── Banner ────────────────────────────────────────────────────────────────────
print_banner() {
    clear 2>/dev/null || true
    echo -e "${CYAN}${BOLD}"
    cat << 'EOF'
 ╔══════════════════════════════════════════════════════════════════════════════╗
 ║                                                                              ║
 ║    ███╗   ██╗  ██╗  ███╗   ███╗  ██████╗   ██╗   ██╗  ███████╗  ██╗  ██╗     ║
 ║    ████╗  ██║  ██║  ████╗ ████║  ██╔══██╗  ██║   ██║  ██╔════╝  ██║  ██║     ║
 ║    ██╔██╗ ██║  ██║  ██╔████╔██║  ██████╔╝  ██║   ██║  ███████╗  ███████║     ║
 ║    ██║╚██╗██║  ██║  ██║╚██╔╝██║  ██╔══██╗  ██║   ██║  ╚════██║  ██╔══██║     ║
 ║    ██║ ╚████║  ██║  ██║ ╚═╝ ██║  ██████╔╝  ╚██████╔╝  ███████║  ██║  ██║     ║
 ║    ╚═╝  ╚═══╝  ╚═╝  ╚═╝     ╚═╝  ╚═════╝    ╚═════╝   ╚══════╝  ╚═╝  ╚═╝     ║
 ║                                                                              ║
 ║                  Nimbush Wayland Desktop Shell Installer                     ║
 ║             Interactive Setup, Dependency Resolver & Compositor Injector     ║
 ╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# ── Package Manager Detection ─────────────────────────────────────────────────
detect_pkg_mgr() {
    if [ -e /etc/NIXOS ]; then
        echo "nixos"
    elif command -v yay &>/dev/null; then
        echo "yay"
    elif command -v paru &>/dev/null; then
        echo "paru"
    elif command -v pacman &>/dev/null; then
        echo "pacman"
    elif command -v apt &>/dev/null; then
        echo "apt"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v nix &>/dev/null || command -v nix-env &>/dev/null; then
        echo "nix"
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

# ── NixOS & Home Manager Declarative Setup Guide ──────────────────────────────
show_nix_declarative_guide() {
    step_header "NixOS & Home Manager Declarative Integration"

    echo -e "${CYAN}${BOLD}This repository includes a native Flake and Home Manager module!${NC}"
    echo -e "You can configure everything declaratively without manual script installation.\n"

    echo -e "${BOLD}1. Add to your flake.nix inputs:${NC}"
    echo -e "  ${DIM}────────────────────────────────────────────────────────────────────────${NC}"
    cat << 'EOF'
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    quickshell-shell = {
      url = "github:YasirFadhil/Nimbush";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
EOF
    echo -e "  ${DIM}────────────────────────────────────────────────────────────────────────${NC}\n"

    echo -e "${BOLD}2. Enable in your home.nix (Home Manager):${NC}"
    echo -e "  ${DIM}────────────────────────────────────────────────────────────────────────${NC}"
    cat << 'EOF'
  imports = [
    inputs.quickshell-shell.homeManagerModules.default
  ];

  programs.quickshell-shell = {
    enable = true;
    enableSystemdService = true;      # Launches Quickshell automatically upon login
    enableDefaultDependencies = true; # Automatically installs runtime CLI dependencies

    # ── Declarative Compositor Integration (Binds & Blur Layer Rules) ──
    hyprland.enableIntegration = true; # For Hyprland
    niri.enableIntegration     = true; # For Niri
  };
EOF
    echo -e "  ${DIM}────────────────────────────────────────────────────────────────────────${NC}\n"

    echo -e "${BOLD}3. Test Quickshell instantly with Nix Flakes (No install needed):${NC}"
    echo -e "   ${GREEN}nix run github:YasirFadhil/Nimbush${NC}  or  ${GREEN}nix run .${NC}\n"

    echo -e "${BOLD}4. Enter a temporary Nix development shell:${NC}"
    echo -e "   ${GREEN}nix develop${NC}\n"

    step_footer
}

# ── Target Configuration Directory Setup ─────────────────────────────────────
setup_target_directory() {
    if [ "$CHECK_ONLY" = true ] || [ "$INJECT_ONLY" = true ] || [ "$SHOW_NIX_GUIDE" = true ]; then
        return 0
    fi

    step_header "1/5 Directory & File Configuration"

    TARGET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    info "Current Source Directory: ${WHITE}${BOLD}$SCRIPT_DIR${NC}"
    info "Target Install Directory: ${WHITE}${BOLD}$TARGET_DIR${NC}"

    if [ "$SCRIPT_DIR" = "$TARGET_DIR" ]; then
        success "Running directly inside target configuration directory ($TARGET_DIR)."
    else
        if [ -d "$TARGET_DIR" ] || [ -L "$TARGET_DIR" ]; then
            warn "Target configuration directory already exists at $TARGET_DIR."
            ACTION="backup_copy"
            if [ "$AUTO_YES" = false ]; then
                echo -e "\n  ${BOLD}Choose an action:${NC}"
                echo -e "    ${CYAN}1)${NC} Backup existing and copy new files ${GREEN}(Recommended)${NC}"
                echo -e "    ${CYAN}2)${NC} Overwrite without backup"
                echo -e "    ${CYAN}3)${NC} Create symbolic link ($SCRIPT_DIR -> $TARGET_DIR)"
                echo -e "    ${CYAN}4)${NC} Skip directory copy / Keep existing"
                read -rp "  Select option [1-4] (default: 1): " dir_choice
                case "$dir_choice" in
                    2) ACTION="overwrite" ;;
                    3) ACTION="symlink" ;;
                    4) ACTION="skip" ;;
                    *) ACTION="backup_copy" ;;
                esac
            fi

            case "$ACTION" in
                backup_copy)
                    BACKUP_DIR="${TARGET_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
                    mv "$TARGET_DIR" "$BACKUP_DIR"
                    info "Backed up existing config to $BACKUP_DIR"
                    mkdir -p "$TARGET_DIR"
                    cp -r "$SCRIPT_DIR/." "$TARGET_DIR/"
                    success "Installed fresh configuration to $TARGET_DIR"
                    ;;
                overwrite)
                    rm -rf "$TARGET_DIR"
                    mkdir -p "$TARGET_DIR"
                    cp -r "$SCRIPT_DIR/." "$TARGET_DIR/"
                    success "Overwrote configuration in $TARGET_DIR"
                    ;;
                symlink)
                    BACKUP_DIR="${TARGET_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
                    mv "$TARGET_DIR" "$BACKUP_DIR"
                    ln -s "$SCRIPT_DIR" "$TARGET_DIR"
                    success "Created symbolic link $TARGET_DIR -> $SCRIPT_DIR"
                    ;;
                skip)
                    info "Skipping directory copy. Continuing setup..."
                    ;;
            esac
        else
            mkdir -p "$TARGET_DIR"
            cp -r "$SCRIPT_DIR/." "$TARGET_DIR/"
            success "Copied configuration to $TARGET_DIR"
        fi
    fi

    # Ensure all scripts are executable
    info "Setting executable permissions for helper scripts in $TARGET_DIR/scripts/..."
    if [ -d "$TARGET_DIR/scripts" ]; then
        chmod +x "$TARGET_DIR"/scripts/*.sh "$TARGET_DIR"/scripts/*.py 2>/dev/null || true
        success "Helper scripts permissions verified (chmod +x)."
    fi

    step_footer
}

# ── Dependency Database ───────────────────────────────────────────────────────
# Format: "command_to_check|category|arch_pkg|debian_pkg|fedora_pkg|nix_pkg|description|required_type"
DEPENDENCIES_DB=(
    # Core Framework & Compositors
    "qs|Core|quickshell|quickshell|quickshell|quickshell|Quickshell UI framework (qs)|req"
    "hyprland|Compositor|hyprland|hyprland|hyprland|hyprland|Hyprland Wayland compositor|comp"
    "niri|Compositor|niri|niri|niri|niri|Niri Scrollable Wayland compositor|comp"

    # Wayland & Clipboard
    "wl-copy|Wayland|wl-clipboard|wl-clipboard|wl-clipboard|wl-clipboard|Wayland clipboard CLI (wl-copy/wl-paste)|req"
    "cliphist|Wayland|cliphist|cliphist|cliphist|cliphist|Clipboard history daemon & manager|req"
    "wtype|Wayland|wtype|wtype|wtype|wtype|Wayland virtual keyboard typing tool for instant emoji insertion|opt"

    # Hardware, Audio & Power
    "brightnessctl|Hardware|brightnessctl|brightnessctl|brightnessctl|brightnessctl|Display backlight brightness control|req"
    "pactl|Audio|libpulse|pulseaudio-utils|pulseaudio-utils|pulseaudio|PulseAudio / PipeWire audio control utility|req"
    "paplay|Audio|libpulse|pulseaudio-utils|pulseaudio-utils|pulseaudio|Event sound feedback playback (paplay/pw-play)|req"
    "wpctl|Audio|wireplumber|wireplumber|wireplumber|wireplumber|WirePlumber PipeWire session controller (wpctl)|opt"
    "powerprofilesctl|Power|power-profiles-daemon|power-profiles-daemon|power-profiles-daemon|power-profiles-daemon|System power profiles daemon|req"
    "upower|Power|upower|upower|upower|upower|UPower battery & power management daemon|req"
    "nmcli|Network|networkmanager|network-manager|NetworkManager|networkmanager|NetworkManager command line tool|req"
    "bluetoothctl|Bluetooth|bluez-utils|bluez|bluez-tools|bluez|BlueZ Bluetooth management CLI|req"

    # Theming, Thematic Colors & Wallpaper
    "swww|Theming|swww|swww|swww|awww|Wayland animated wallpaper daemon (awww / swww)|opt"
    "matugen|Theming|matugen|matugen|matugen|matugen|Material You dynamic color palette generator from wallpaper|opt"
    "swaybg|Theming|swaybg|swaybg|swaybg|swaybg|Wayland wallpaper daemon (fallback)|opt"

    # System Utilities & IPC
    "socat|System|socat|socat|socat|socat|Unix socket utility for Hyprland workspace IPC|req"
    "fuser|System|psmisc|psmisc|psmisc|psmisc|Camera & hardware usage detector (psmisc)|req"
    "pkill|System|procps-ng|procps|procps-ng|procps|Process signal & process management (procps)|req"
    "notify-send|System|libnotify|libnotify-bin|libnotify|libnotify|Desktop notifications utility (notify-send)|req"
    "dbus-monitor|System|dbus|dbus|dbus-tools|dbus|D-Bus event monitoring (sleep/lock watcher)|req"
    "gdbus|System|glib2|libglib2.0-bin|glib2|glib|GDBus utility for XDG portal communications|req"
    "git|System|git|git|git|git|Git version control (for update notifications)|req"

    # Screenshots & Media
    "grim|Media|grim|grim|grim|grim|Wayland screenshot capture utility|req"
    "slurp|Media|slurp|slurp|slurp|slurp|Wayland interactive region selection utility|req"
    "swappy|Media|swappy|swappy|swappy|swappy|Interactive screenshot editor & annotator|opt"

    # Python & Dialog Tools
    "python3|Python|python|python3|python3|python3|Python 3 runtime for helper scripts|req"
    "zenity|GUI|zenity|zenity|zenity|zenity|XDG File Picker Dialog (fallback for wallpaper)|opt"
    "fastfetch|System|fastfetch|fastfetch|fastfetch|fastfetch|Fast system hardware & OS information tool|opt"
)

# ── Dependency Diagnostics & Scan ─────────────────────────────────────────────
run_dependency_diagnostics() {
    if [ "$SKIP_DEPS" = true ] && [ "$CHECK_ONLY" = false ]; then
        return 0
    fi

    step_header "2/5 Real-Time Dependency Diagnostics"

    PKG_MGR=$(detect_pkg_mgr)
    info "Detected System Package Manager: ${GREEN}${BOLD}${PKG_MGR}${NC}"

    if [ "$PKG_MGR" = "nixos" ] || [ "$PKG_MGR" = "nix" ]; then
        info "Nix environment detected. For declarative NixOS / Home Manager setup, select Option 5 in the menu."
    fi

    # Check for alternate binary names
    find_cmd() {
        local c="$1"
        if command -v "$c" &>/dev/null; then
            command -v "$c"
            return 0
        fi
        case "$c" in
            qs)
                command -v quickshell 2>/dev/null || true
                ;;
            swww)
                command -v awww 2>/dev/null || true
                ;;
            paplay)
                command -v pw-play 2>/dev/null || true
                ;;
            dbus-monitor)
                command -v busctl 2>/dev/null || true
                ;;
            *)
                echo ""
                ;;
        esac
    }

    # Detect compositors present
    HAS_HYPRLAND=false
    HAS_NIRI=false
    if command -v hyprland &>/dev/null; then HAS_HYPRLAND=true; fi
    if command -v niri &>/dev/null; then HAS_NIRI=true; fi

    MISSING_REQUIRED_CMDS=()
    MISSING_OPTIONAL_CMDS=()
    MISSING_PKGS=()
    MISSING_REQUIRED_PKGS=()

    INSTALLED_COUNT=0
    MISSING_COUNT=0

    echo -e "\n  ${BOLD}$(printf "%-22s %-12s %-14s %s" "COMPONENT" "CATEGORY" "STATUS" "DETAILS / PATH")${NC}"
    echo -e "  ${DIM}────────────────────────────────────────────────────────────────────────────────${NC}"

    for entry in "${DEPENDENCIES_DB[@]}"; do
        IFS='|' read -r cmd cat arch_pkg debian_pkg fedora_pkg nix_pkg desc req_type <<< "$entry"

        BIN_PATH=$(find_cmd "$cmd")

        # Map package name for current package manager
        PKG_NAME="$arch_pkg"
        case "$PKG_MGR" in
            yay|paru|pacman)   PKG_NAME="$arch_pkg" ;;
            apt)               PKG_NAME="$debian_pkg" ;;
            dnf)               PKG_NAME="$fedora_pkg" ;;
            nixos|nix|nix-env) PKG_NAME="$nix_pkg" ;;
            zypper)            PKG_NAME="$debian_pkg" ;;
            *)                 PKG_NAME="$arch_pkg" ;;
        esac

        if [ -n "$BIN_PATH" ]; then
            INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
            printf "  %-22s %-12s ${GREEN}%-14s${NC} ${DIM}%s${NC}\n" "$cmd" "[$cat]" "[✔ INSTALLED]" "$BIN_PATH"
        else
            # Compositor mutual exemption
            if [ "$cmd" = "hyprland" ] && [ "$HAS_NIRI" = true ]; then
                printf "  %-22s %-12s ${YELLOW}%-14s${NC} ${DIM}%s${NC}\n" "$cmd" "[$cat]" "[OPTIONAL]" "(Niri is installed)"
                continue
            elif [ "$cmd" = "niri" ] && [ "$HAS_HYPRLAND" = true ]; then
                printf "  %-22s %-12s ${YELLOW}%-14s${NC} ${DIM}%s${NC}\n" "$cmd" "[$cat]" "[OPTIONAL]" "(Hyprland is installed)"
                continue
            fi

            MISSING_COUNT=$((MISSING_COUNT + 1))
            MISSING_PKGS+=("$PKG_NAME")

            if [ "$req_type" = "req" ]; then
                MISSING_REQUIRED_CMDS+=("$cmd")
                MISSING_REQUIRED_PKGS+=("$PKG_NAME")
                printf "  %-22s %-12s ${RED}${BOLD}%-14s${NC} ${RED}%s (Package: %s)${NC}\n" "$cmd" "[$cat]" "[✖ MISSING]" "Required" "$PKG_NAME"
            elif [ "$req_type" = "comp" ]; then
                MISSING_REQUIRED_CMDS+=("$cmd")
                MISSING_REQUIRED_PKGS+=("$PKG_NAME")
                printf "  %-22s %-12s ${YELLOW}${BOLD}%-14s${NC} ${YELLOW}%s (Package: %s)${NC}\n" "$cmd" "[$cat]" "[! COMPOSITOR]" "At least one needed" "$PKG_NAME"
            else
                MISSING_OPTIONAL_CMDS+=("$cmd")
                printf "  %-22s %-12s ${YELLOW}%-14s${NC} ${DIM}%s (Package: %s)${NC}\n" "$cmd" "[$cat]" "[○ OPTIONAL]" "Recommended" "$PKG_NAME"
            fi
        fi
    done

    # Check Sound Theme Assets
    SOUND_FOUND=false
    for sdir in "/usr/share/sounds/freedesktop/stereo" "/run/current-system/sw/share/sounds/freedesktop/stereo" "$HOME/.local/share/sounds/freedesktop/stereo" "$HOME/.nix-profile/share/sounds/freedesktop/stereo" "/etc/profiles/per-user/$USER/share/sounds/freedesktop/stereo"; do
        if [ -d "$sdir" ]; then SOUND_FOUND=true; break; fi
    done
    if [ "$SOUND_FOUND" = true ]; then
        INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
        printf "  %-22s %-12s ${GREEN}%-14s${NC} ${DIM}%s${NC}\n" "freedesktop-sounds" "[Sound]" "[✔ INSTALLED]" "Sound theme found"
    else
        MISSING_COUNT=$((MISSING_COUNT + 1))
        MISSING_PKGS+=("sound-theme-freedesktop")
        printf "  %-22s %-12s ${YELLOW}%-14s${NC} ${DIM}%s${NC}\n" "freedesktop-sounds" "[Sound]" "[○ OPTIONAL]" "sound-theme-freedesktop"
    fi

    # Check Nerd Fonts
    FONT_FOUND=false
    if command -v fc-list &>/dev/null; then
        if fc-list : family | grep -i -E "Nerd Font|SymbolsNerdFont|JetBrainsMono" &>/dev/null; then
            FONT_FOUND=true
            INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
            printf "  %-22s %-12s ${GREEN}%-14s${NC} ${DIM}%s${NC}\n" "nerd-fonts" "[Typography]" "[✔ INSTALLED]" "Nerd Font / Symbols detected"
        fi
    fi
    if [ "$FONT_FOUND" = false ]; then
        MISSING_COUNT=$((MISSING_COUNT + 1))
        case "$PKG_MGR" in
            yay|paru|pacman)   MISSING_PKGS+=("ttf-nerd-fonts-symbols-mono") ;;
            nixos|nix|nix-env) MISSING_PKGS+=("nerd-fonts.symbols-only") ;;
            *)                 MISSING_PKGS+=("fonts-font-awesome") ;;
        esac
        printf "  %-22s %-12s ${YELLOW}%-14s${NC} ${YELLOW}%s${NC}\n" "nerd-fonts" "[Typography]" "[! WARNING]" "No Nerd Font detected (icons may render as boxes)"
    fi

    echo -e "  ${DIM}────────────────────────────────────────────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}Diagnostic Result:${NC} Installed: ${GREEN}${BOLD}${INSTALLED_COUNT}${NC} | Missing: ${RED}${BOLD}${MISSING_COUNT}${NC}\n"

    # Offer installation if missing dependencies found
    if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
        UNIQUE_ALL_PKGS=($(printf "%s\n" "${MISSING_PKGS[@]}" | sort -u))
        UNIQUE_REQ_PKGS=($(printf "%s\n" "${MISSING_REQUIRED_PKGS[@]}" | sort -u))

        # Adjust compositor selection if neither is installed
        if [ "$HAS_HYPRLAND" = false ] && [ "$HAS_NIRI" = false ]; then
            if [ "$AUTO_YES" = false ] && [ "$CHECK_ONLY" = false ]; then
                echo -e "  ${YELLOW}${BOLD}No Wayland compositor is installed.${NC}"
                echo -e "  Choose which compositor you want to install:"
                echo -e "    ${CYAN}1)${NC} Hyprland ${GREEN}(Recommended)${NC}"
                echo -e "    ${CYAN}2)${NC} Niri"
                echo -e "    ${CYAN}3)${NC} Both"
                echo -e "    ${CYAN}4)${NC} None (I will install manually)"
                read -rp "  Select [1-4] (default: 1): " comp_choice
                case "$comp_choice" in
                    2) UNIQUE_ALL_PKGS=($(printf '%s\n' "${UNIQUE_ALL_PKGS[@]}" | grep -v -E '^hyprland$')) ;;
                    3) ;; # keep both
                    4) UNIQUE_ALL_PKGS=($(printf '%s\n' "${UNIQUE_ALL_PKGS[@]}" | grep -v -E '^(hyprland|niri)$')) ;;
                    *) UNIQUE_ALL_PKGS=($(printf '%s\n' "${UNIQUE_ALL_PKGS[@]}" | grep -v -E '^niri$')) ;;
                esac
            else
                # Non-interactive default: Hyprland
                UNIQUE_ALL_PKGS=($(printf '%s\n' "${UNIQUE_ALL_PKGS[@]}" | grep -v -E '^niri$'))
            fi
        fi

        build_install_cmd() {
            local pkgs=("$@")
            local cmd=""
            case "$PKG_MGR" in
                yay)
                    cmd="yay -S --needed $([ "$AUTO_YES" = true ] && echo "--noconfirm") ${pkgs[*]}"
                    ;;
                paru)
                    cmd="paru -S --needed $([ "$AUTO_YES" = true ] && echo "--noconfirm") ${pkgs[*]}"
                    ;;
                pacman)
                    cmd="sudo pacman -S --needed $([ "$AUTO_YES" = true ] && echo "--noconfirm") ${pkgs[*]}"
                    ;;
                apt)
                    cmd="sudo apt update && sudo apt install $([ "$AUTO_YES" = true ] && echo "-y") ${pkgs[*]}"
                    ;;
                dnf)
                    cmd="sudo dnf install $([ "$AUTO_YES" = true ] && echo "-y") ${pkgs[*]}"
                    ;;
                zypper)
                    cmd="sudo zypper install $([ "$AUTO_YES" = true ] && echo "-y") ${pkgs[*]}"
                    ;;
                nixos|nix)
                    if command -v nix &>/dev/null; then
                        local nflakes=()
                        for p in "${pkgs[@]}"; do nflakes+=("nixpkgs#$p"); done
                        cmd="nix profile install ${nflakes[*]}"
                    else
                        local nattrs=()
                        for p in "${pkgs[@]}"; do nattrs+=("nixpkgs.$p"); done
                        cmd="nix-env -iA ${nattrs[*]}"
                    fi
                    ;;
                nix-env)
                    local nattrs=()
                    for p in "${pkgs[@]}"; do nattrs+=("nixpkgs.$p"); done
                    cmd="nix-env -iA ${nattrs[*]}"
                    ;;
                xbps)
                    cmd="sudo xbps-install -S $([ "$AUTO_YES" = true ] && echo "-y") ${pkgs[*]}"
                    ;;
                apk)
                    cmd="sudo apk add ${pkgs[*]}"
                    ;;
                emerge)
                    cmd="sudo emerge -av ${pkgs[*]}"
                    ;;
                eopkg)
                    cmd="sudo eopkg it $([ "$AUTO_YES" = true ] && echo "-y") ${pkgs[*]}"
                    ;;
                *)
                    cmd="# Install manually: ${pkgs[*]}"
                    ;;
            esac
            echo "$cmd"
        }

        if [ "$CHECK_ONLY" = false ]; then
            INSTALL_ACTION="all"
            if [ "$AUTO_YES" = false ]; then
                echo -e "  ${BOLD}Missing Dependencies Action Menu:${NC}"
                echo -e "    ${CYAN}1)${NC} Install ALL missing packages (${#UNIQUE_ALL_PKGS[@]} pkgs) ${GREEN}(Recommended)${NC}"
                echo -e "    ${CYAN}2)${NC} Install only REQUIRED missing packages (${#UNIQUE_REQ_PKGS[@]} pkgs)"
                echo -e "    ${CYAN}3)${NC} View command only (Do not run)"
                echo -e "    ${CYAN}4)${NC} Skip dependency installation"
                read -rp "  Select option [1-4] (default: 1): " install_choice
                case "$install_choice" in
                    2) INSTALL_ACTION="req_only" ;;
                    3) INSTALL_ACTION="view_only" ;;
                    4) INSTALL_ACTION="skip" ;;
                    *) INSTALL_ACTION="all" ;;
                esac
            fi

            TARGET_PKGS=()
            if [ "$INSTALL_ACTION" = "all" ]; then
                TARGET_PKGS=("${UNIQUE_ALL_PKGS[@]}")
            elif [ "$INSTALL_ACTION" = "req_only" ]; then
                TARGET_PKGS=("${UNIQUE_REQ_PKGS[@]}")
            fi

            if [ ${#TARGET_PKGS[@]} -gt 0 ]; then
                INSTALL_COMMAND=$(build_install_cmd "${TARGET_PKGS[@]}")
                info "Suggested package installation via $PKG_MGR:"
                echo -e "  ${CYAN}${BOLD}$INSTALL_COMMAND${NC}\n"

                if [ "$INSTALL_ACTION" != "view_only" ]; then
                    if eval "$INSTALL_COMMAND"; then
                        success "Package installation completed successfully!"
                    else
                        error "Package manager exited with errors. You may need to run manual installation or use Home Manager."
                    fi
                fi
            fi
        fi
    else
        success "All required and optional dependencies are satisfied!"
    fi

    step_footer
}

# ── Compositor Injection & Configuration Engine ───────────────────────────────
inject_compositor_configs() {
    if [ "$CHECK_ONLY" = true ] || [ "$SHOW_NIX_GUIDE" = true ]; then
        return 0
    fi

    step_header "3/5 Compositor Integration & Keybinding Setup"

    HYPR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
    HYPR_CONF_DIR="$HYPR_DIR/conf"
    HYPR_CONF="$HYPR_DIR/hyprland.conf"
    HYPR_QS_CONF="$HYPR_CONF_DIR/quickshell.conf"
    HYPR_LUA="$HYPR_DIR/hyprland.lua"
    HYPR_QS_LUA="$HYPR_CONF_DIR/quickshell.lua"

    NIRI_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/niri"
    NIRI_CONF_DIR="$NIRI_DIR/conf"
    NIRI_CONF="$NIRI_DIR/config.kdl"
    NIRI_QS_KDL="$NIRI_CONF_DIR/quickshell.kdl"

    # Scan current environment
    HAS_HYPR_LUA=false
    HAS_HYPR_CONF=false
    HAS_NIRI_CONF=false

    if [ -f "$HYPR_LUA" ]; then HAS_HYPR_LUA=true; fi
    if [ -f "$HYPR_CONF" ]; then HAS_HYPR_CONF=true; fi
    if [ -f "$NIRI_CONF" ]; then HAS_NIRI_CONF=true; fi

    echo -e "  ${BOLD}Detected Compositor Configuration Status:${NC}"
    if [ "$HAS_HYPR_LUA" = true ]; then
        echo -e "    ${GREEN}●${NC} Hyprland (Lua format):   ${BOLD}$HYPR_LUA${NC} ${GREEN}(Found)${NC}"
    elif [ "$HAS_HYPR_CONF" = true ]; then
        echo -e "    ${GREEN}●${NC} Hyprland (Classic conf): ${BOLD}$HYPR_CONF${NC} ${GREEN}(Found)${NC}"
    else
        echo -e "    ${DIM}○ Hyprland Configuration: Not found (will create clean modular tree if selected)${NC}"
    fi

    if [ "$HAS_NIRI_CONF" = true ]; then
        echo -e "    ${GREEN}●${NC} Niri (KDL format):       ${BOLD}$NIRI_CONF${NC} ${GREEN}(Found)${NC}"
    else
        echo -e "    ${DIM}○ Niri Configuration:     Not found (will create clean modular tree if selected)${NC}"
    fi

    # ── Injection Helper Functions ────────────────────────────────────────────

    write_hypr_classic_modular() {
        mkdir -p "$HYPR_CONF_DIR"
        info "Modularizing Hyprland Classic configuration: $HYPR_CONF -> $HYPR_CONF_DIR/..."

        local helper=""
        if [ -f "$TARGET_DIR/scripts/compositor-helper.py" ]; then
            helper="$TARGET_DIR/scripts/compositor-helper.py"
        elif [ -f "$SCRIPT_DIR/scripts/compositor-helper.py" ]; then
            helper="$SCRIPT_DIR/scripts/compositor-helper.py"
        fi

        if command -v python3 &>/dev/null && [ -n "$helper" ]; then
            python3 "$helper" modularize hypr_conf >/dev/null 2>&1 || true
            success "Generated clean modular Hyprland tree in $HYPR_CONF_DIR without duplicates."
        else
            # ── Fallback bash deduplicating modularization ──
            # 1. Quickshell Integration
            cat << 'EOF' > "$HYPR_QS_CONF"
# ══════════════════════════════════════════════════════════════════════════════
#  Quickshell Desktop Environment Integration (~/.config/hypr/conf/quickshell.conf)
# ══════════════════════════════════════════════════════════════════════════════

# ── 1. Autostart Quickshell Desktop Environment ──────────────────────────────
exec-once = qs

# ── 2. Quickshell IPC Keybindings ─────────────────────────────────────────────
bind = SUPER, SPACE,         exec, qs ipc call launcher toggle
bind = SUPER SHIFT, W,       exec, qs ipc call wallpaper toggle
bind = SUPER SHIFT, E,       exec, qs ipc call emoji toggle
bind = SUPER, V,             exec, qs ipc call clipboard toggle
bind = SUPER, P,             exec, qs ipc call powermenu toggle
bind = SUPER ALT, L,         exec, qs ipc call lockscreen toggle
bind = SUPER, D,             exec, qs ipc call dashboard toggle
bind = SUPER, N,             exec, qs ipc call notifCenter toggle
bind = SUPER, C,             exec, qs ipc call controlCenter toggle
bind = SUPER, B,             exec, qs ipc call battery toggle

# ── 3. Quickshell Layer Rules (Blur & Transparency) ───────────────────────────
layerrule = blur, quickshell:bar
layerrule = blur, quickshell:launcher
layerrule = ignorezero, quickshell:launcher
layerrule = blur, quickshell:wallpaperselector
layerrule = ignorezero, quickshell:wallpaperselector
layerrule = blur, quickshell:emojipicker
layerrule = ignorezero, quickshell:emojipicker
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
layerrule = blur, quickshell:settings
layerrule = ignorezero, quickshell:settings
layerrule = blur, quickshell:battery
layerrule = ignorezero, quickshell:battery
layerrule = blur, quickshell:volume
layerrule = ignorezero, quickshell:volume
layerrule = blur, quickshell:welcome
layerrule = ignorezero, quickshell:welcome
layerrule = blur, quickshell:powermenu
layerrule = ignorezero, quickshell:powermenu
layerrule = blur, quickshell:lockscreen
layerrule = blur, quickshell:osd
layerrule = ignorezero, quickshell:osd
layerrule = blur, quickshell:volumeosd
layerrule = ignorezero, quickshell:volumeosd
layerrule = blur, quickshell:brightnessosd
layerrule = ignorezero, quickshell:brightnessosd
layerrule = blur, ^quickshell:.*$
layerrule = ignorezero, ^quickshell:.*$
EOF
            success "Wrote $HYPR_QS_CONF"

            # 2. Autostart Daemons
            if [ ! -f "$HYPR_CONF_DIR/autostart.conf" ]; then
                cat << 'EOF' > "$HYPR_CONF_DIR/autostart.conf"
# ══════════════════════════════════════════════════════════════════════════════
#  Autostart Daemons & Background Services (~/.config/hypr/conf/autostart.conf)
# ══════════════════════════════════════════════════════════════════════════════

# Polkit Authentication Agent
exec-once = systemctl enable --now --user hyprpolkitagent

# Clipboard History Daemons
exec-once = wl-paste --type text --watch cliphist store
exec-once = wl-paste --type image --watch cliphist store
EOF
                success "Wrote $HYPR_CONF_DIR/autostart.conf"
            fi

            # 3. Keybindings
            if [ ! -f "$HYPR_CONF_DIR/keybinds.conf" ]; then
                cat << 'EOF' > "$HYPR_CONF_DIR/keybinds.conf"
# ══════════════════════════════════════════════════════════════════════════════
#  Keybindings & Shortcuts (~/.config/hypr/conf/keybinds.conf)
# ══════════════════════════════════════════════════════════════════════════════

$mainMod = SUPER
$terminal = kitty
$fileManager = nautilus

bind = $mainMod, T, exec, $terminal
bind = $mainMod, E, exec, $fileManager
bind = $mainMod, Q, killactive,
bind = $mainMod ALT, F, togglefloating,
bind = $mainMod SHIFT, F, fullscreen, 0
bind = $mainMod, J, togglesplit,

bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4
bind = $mainMod, 5, workspace, 5
bind = $mainMod, 6, workspace, 6
bind = $mainMod, 7, workspace, 7
bind = $mainMod, 8, workspace, 8
bind = $mainMod, 9, workspace, 9
bind = $mainMod, 0, workspace, 10

bind = , PRINT, exec, ~/.config/quickshell/scripts/screenshot.sh full
bind = SHIFT, PRINT, exec, ~/.config/quickshell/scripts/screenshot.sh region
bind = $mainMod, PRINT, exec, ~/.config/quickshell/scripts/screenshot.sh window
EOF
                success "Wrote $HYPR_CONF_DIR/keybinds.conf"
            fi

            # 4. Rules
            if [ ! -f "$HYPR_CONF_DIR/rules.conf" ]; then
                cat << 'EOF' > "$HYPR_CONF_DIR/rules.conf"
# ══════════════════════════════════════════════════════════════════════════════
#  Window Rules (~/.config/hypr/conf/rules.conf)
# ══════════════════════════════════════════════════════════════════════════════

windowrulev2 = suppressevent maximize, class:.*
windowrulev2 = float, title:^(Picture-in-Picture|Picture in picture)$
windowrulev2 = pin, title:^(Picture-in-Picture|Picture in picture)$
windowrulev2 = float, class:^(pavucontrol|nm-connection-editor|blueman-manager|swappy)$
EOF
                success "Wrote $HYPR_CONF_DIR/rules.conf"
            fi

            # 5. Clean & Connect Main hyprland.conf
            if [ -f "$HYPR_CONF" ]; then
                local backup_conf="${HYPR_CONF}.bak.$(date +%Y%m%d_%H%M%S)"
                cp "$HYPR_CONF" "$backup_conf"
                info "Created backup: $backup_conf"
                sed -i '/quickshell\.conf/d' "$HYPR_CONF"
                sed -i '/qs ipc call/d' "$HYPR_CONF"
                sed -i '/quickshell:/d' "$HYPR_CONF"
                sed -i '/exec-once = qs\b/d' "$HYPR_CONF"
                sed -i '/source = ~\/\.config\/hypr\/conf\//d' "$HYPR_CONF"
                echo -e "\n# ── Modular Configuration Sources ──\nsource = ~/.config/hypr/conf/autostart.conf\nsource = ~/.config/hypr/conf/keybinds.conf\nsource = ~/.config/hypr/conf/rules.conf\nsource = ~/.config/hypr/conf/quickshell.conf" >> "$HYPR_CONF"
                success "Connected modular sources to $HYPR_CONF without duplicates."
            else
                info "Creating starter $HYPR_CONF with modular sources..."
                cat << 'EOF' > "$HYPR_CONF"
# ══════════════════════════════════════════════════════════════════════════════
#  Hyprland Classic Modular Configuration (~/.config/hypr/hyprland.conf)
# ══════════════════════════════════════════════════════════════════════════════

monitor=,preferred,auto,1

general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(89b4faee) rgba(cba6f7ee) 45deg
    col.inactive_border = rgba(313244aa)
    layout = dwindle
}

decoration {
    rounding = 10
    blur {
        enabled = true
        size = 6
        passes = 3
    }
}

# ── Modular Configuration Sources ──
source = ~/.config/hypr/conf/autostart.conf
source = ~/.config/hypr/conf/keybinds.conf
source = ~/.config/hypr/conf/rules.conf
source = ~/.config/hypr/conf/quickshell.conf
EOF
                success "Created starter $HYPR_CONF"
            fi
        fi
    }

    write_hypr_lua_modular() {
        mkdir -p "$HYPR_CONF_DIR"
        info "Modularizing Hyprland Lua configuration: $HYPR_LUA -> $HYPR_CONF_DIR/..."

        local helper=""
        if [ -f "$TARGET_DIR/scripts/compositor-helper.py" ]; then
            helper="$TARGET_DIR/scripts/compositor-helper.py"
        elif [ -f "$SCRIPT_DIR/scripts/compositor-helper.py" ]; then
            helper="$SCRIPT_DIR/scripts/compositor-helper.py"
        fi

        if command -v python3 &>/dev/null && [ -n "$helper" ]; then
            python3 "$helper" modularize hypr_lua >/dev/null 2>&1 || true
            success "Generated clean modular Hyprland Lua tree in $HYPR_CONF_DIR without duplicates."
        else
            # ── Fallback bash deduplicating modularization ──
            cat << 'EOF' > "$HYPR_QS_LUA"
-- ══════════════════════════════════════════════════════════════════════════════
--  Quickshell Desktop Environment Integration (Hyprland Lua)
--  Loaded from ~/.config/hypr/hyprland.lua
-- ══════════════════════════════════════════════════════════════════════════════

local mainMod = "SUPER"

-- ── 1. Autostart Quickshell Desktop Environment ──────────────────────────────
hl.on("hyprland.start", function ()
    hl.exec_cmd("qs")
end)

-- ── 2. Quickshell IPC Keybindings ─────────────────────────────────────────────
hl.bind(mainMod .. " + SPACE",         hl.dsp.exec_cmd("qs ipc call launcher toggle"))
hl.bind(mainMod .. " + SHIFT + W",     hl.dsp.exec_cmd("qs ipc call wallpaper toggle"))
hl.bind(mainMod .. " + SHIFT + E",     hl.dsp.exec_cmd("qs ipc call emoji toggle"))
hl.bind(mainMod .. " + V",             hl.dsp.exec_cmd("qs ipc call clipboard toggle"))
hl.bind(mainMod .. " + P",             hl.dsp.exec_cmd("qs ipc call powermenu toggle"))
hl.bind(mainMod .. " + ALT + L",       hl.dsp.exec_cmd("qs ipc call lockscreen toggle"))
hl.bind(mainMod .. " + D",             hl.dsp.exec_cmd("qs ipc call dashboard toggle"))
hl.bind(mainMod .. " + N",             hl.dsp.exec_cmd("qs ipc call notifCenter toggle"))
hl.bind(mainMod .. " + C",             hl.dsp.exec_cmd("qs ipc call controlCenter toggle"))
hl.bind(mainMod .. " + B",             hl.dsp.exec_cmd("qs ipc call battery toggle"))

-- ── 3. Quickshell Layer Rules (Blur & Transparency) ───────────────────────────
hl.layer_rule({ match = { namespace = "quickshell:bar" },               blur = true })
hl.layer_rule({ match = { namespace = "quickshell:launcher" },          blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:wallpaperselector" }, blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:emojipicker" },       blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:clipboard" },         blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:controlcenter" },     blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:notifcenter" },       blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:dashboard" },         blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:calendar" },          blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:hud" },               blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:traymenu" },          blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:trayoverflow" },      blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:settings" },          blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:battery" },           blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:volume" },            blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:welcome" },           blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:powermenu" },         blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "^quickshell:.*$" },              blur = true, ignore_alpha = 0 })
EOF
            success "Wrote $HYPR_QS_LUA"

            if [ ! -f "$HYPR_CONF_DIR/autostart.lua" ]; then
                cat << 'EOF' > "$HYPR_CONF_DIR/autostart.lua"
-- ══════════════════════════════════════════════════════════════════════════════
--  Autostart Daemons & Background Services (~/.config/hypr/conf/autostart.lua)
-- ══════════════════════════════════════════════════════════════════════════════

hl.on("hyprland.start", function ()
    hl.exec_cmd("systemctl enable --now --user hyprpolkitagent")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)
EOF
                success "Wrote $HYPR_CONF_DIR/autostart.lua"
            fi

            if [ -f "$HYPR_LUA" ]; then
                local backup_lua="${HYPR_LUA}.bak.$(date +%Y%m%d_%H%M%S)"
                cp "$HYPR_LUA" "$backup_lua"
                info "Created backup: $backup_lua"
                sed -i '/quickshell\.lua/d' "$HYPR_LUA"
                sed -i '/qs ipc call/d' "$HYPR_LUA"
                sed -i '/quickshell:/d' "$HYPR_LUA"
                sed -i '/load_conf(/d' "$HYPR_LUA"
                echo -e "\n-- ── Load Modular Configuration Files ──\nlocal home = os.getenv(\"HOME\") or \"\"\nlocal confDir = home .. \"/.config/hypr/conf\"\n\nlocal function load_conf(module_name)\n    local module_path = confDir .. \"/\" .. module_name .. \".lua\"\n    if io.open(module_path, \"r\") then\n        dofile(module_path)\n    end\nend\n\nload_conf(\"autostart\")\nload_conf(\"keybinds\")\nload_conf(\"rules\")\nload_conf(\"quickshell\")" >> "$HYPR_LUA"
                success "Connected modular loader to $HYPR_LUA"
            else
                info "Writing starter $HYPR_LUA with modular loader..."
                cat << 'EOF' > "$HYPR_LUA"
-- Hyprland Lua Configuration
local home = os.getenv("HOME") or ""
local confDir = home .. "/.config/hypr/conf"

local function load_conf(module_name)
    local module_path = confDir .. "/" .. module_name .. ".lua"
    if io.open(module_path, "r") then
        dofile(module_path)
    end
end

load_conf("autostart")
load_conf("keybinds")
load_conf("rules")
load_conf("quickshell")
EOF
                success "Created starter $HYPR_LUA"
            fi
        fi
    }

    write_hypr_modular() {
        if [ "$HAS_HYPR_LUA" = true ]; then
            write_hypr_lua_modular
        else
            write_hypr_classic_modular
        fi
    }

    write_niri_modular() {
        mkdir -p "$NIRI_CONF_DIR"
        info "Modularizing Niri configuration: $NIRI_CONF -> $NIRI_CONF_DIR/..."

        local helper=""
        if [ -f "$TARGET_DIR/scripts/compositor-helper.py" ]; then
            helper="$TARGET_DIR/scripts/compositor-helper.py"
        elif [ -f "$SCRIPT_DIR/scripts/compositor-helper.py" ]; then
            helper="$SCRIPT_DIR/scripts/compositor-helper.py"
        fi

        if command -v python3 &>/dev/null && [ -n "$helper" ]; then
            python3 "$helper" modularize niri >/dev/null 2>&1 || true
            success "Generated clean modular Niri tree in $NIRI_CONF_DIR without duplicates."
        else
            # ── Fallback bash deduplicating modularization ──
            cat << 'EOF' > "$NIRI_QS_KDL"
// ══════════════════════════════════════════════════════════════════════════════
//  Quickshell Desktop Environment Integration (Niri)
//  Included from ~/.config/niri/config.kdl
// ══════════════════════════════════════════════════════════════════════════════

// ── 1. Autostart Quickshell Desktop Environment ──────────────────────────────
spawn-at-startup "qs"

// ── 2. Quickshell IPC Keybindings ─────────────────────────────────────────────
binds {
    Mod+Space       { spawn "qs" "ipc" "call" "launcher" "toggle"; }
    Mod+Shift+W     { spawn "qs" "ipc" "call" "wallpaper" "toggle"; }
    Mod+Shift+E     { spawn "qs" "ipc" "call" "emoji" "toggle"; }
    Mod+V           { spawn "qs" "ipc" "call" "clipboard" "toggle"; }
    Mod+P           { spawn "qs" "ipc" "call" "powermenu" "toggle"; }
    Mod+Alt+L       { spawn "qs" "ipc" "call" "lockscreen" "toggle"; }
    Mod+D           { spawn "qs" "ipc" "call" "dashboard" "toggle"; }
    Mod+N           { spawn "qs" "ipc" "call" "notifCenter" "toggle"; }
    Mod+C           { spawn "qs" "ipc" "call" "controlCenter" "toggle"; }
    Mod+B           { spawn "qs" "ipc" "call" "battery" "toggle"; }
}
EOF
            success "Wrote $NIRI_QS_KDL"

            if [ ! -f "$NIRI_CONF_DIR/autostart.kdl" ]; then
                cat << 'EOF' > "$NIRI_CONF_DIR/autostart.kdl"
// ══════════════════════════════════════════════════════════════════════════════
//  Autostart Daemons & Services (~/.config/niri/conf/autostart.kdl)
// ══════════════════════════════════════════════════════════════════════════════

spawn-at-startup "wl-paste" "--type" "text" "--watch" "cliphist" "store"
spawn-at-startup "wl-paste" "--type" "image" "--watch" "cliphist" "store"
EOF
                success "Wrote $NIRI_CONF_DIR/autostart.kdl"
            fi

            if [ -f "$NIRI_CONF" ]; then
                local backup_niri="${NIRI_CONF}.bak.$(date +%Y%m%d_%H%M%S)"
                cp "$NIRI_CONF" "$backup_niri"
                info "Created backup: $backup_niri"
                sed -i '/quickshell\.kdl/d' "$NIRI_CONF"
                sed -i '/qs ipc call/d' "$NIRI_CONF"
                sed -i '/include "conf\//d' "$NIRI_CONF"
                echo -e "\n// ── Modular Configurations ──\ninclude \"conf/autostart.kdl\"\ninclude \"conf/keybinds.kdl\"\ninclude \"conf/rules.kdl\"\ninclude \"conf/quickshell.kdl\"" >> "$NIRI_CONF"
                success "Connected modular includes to $NIRI_CONF"
            else
                info "Writing starter $NIRI_CONF with include directive..."
                cat << 'EOF' > "$NIRI_CONF"
// Niri Configuration
// ── Modular Configurations ──
include "conf/autostart.kdl"
include "conf/keybinds.kdl"
include "conf/rules.kdl"
include "conf/quickshell.kdl"
EOF
                success "Created starter $NIRI_CONF"
            fi
        fi
    }

    # ── Interactive Menu for Injection ────────────────────────────────────────
    INJECT_TARGET="auto"
    if [ -n "$CLI_COMPOSITOR" ]; then
        INJECT_TARGET="$CLI_COMPOSITOR"
    elif [ "$AUTO_YES" = false ]; then
        echo -e "\n  ${BOLD}Compositor Integration Menu:${NC}"
        echo -e "    ${CYAN}1)${NC} ${BOLD}Smart Auto-Detect & Inject${NC} (Hyprland / Niri) ${GREEN}(Recommended)${NC}"
        echo -e "    ${CYAN}2)${NC} ${BOLD}Hyprland${NC} (Auto-detects whether your setup uses Lua or Classic format)"
        echo -e "    ${CYAN}3)${NC} ${BOLD}Niri${NC} (${DIM}~/.config/niri/conf/quickshell.kdl + config.kdl${NC})"
        echo -e "    ${CYAN}4)${NC} ${BOLD}Both${NC} (Hyprland & Niri)"
        echo -e "    ${CYAN}5)${NC} Skip Compositor Configuration"
        read -rp "  Select option [1-5] (default: 1): " comp_menu_choice
        case "$comp_menu_choice" in
            2) INJECT_TARGET="hyprland" ;;
            3) INJECT_TARGET="niri" ;;
            4) INJECT_TARGET="all" ;;
            5) INJECT_TARGET="skip" ;;
            *) INJECT_TARGET="auto" ;;
        esac
    fi

    case "$INJECT_TARGET" in
        auto)
            applied=false
            if [ "$HAS_HYPR_LUA" = true ] || [ "$HAS_HYPR_CONF" = true ] || [ "$HAS_HYPRLAND" = true ]; then
                write_hypr_modular
                applied=true
            fi
            if [ "$HAS_NIRI_CONF" = true ] || [ "$HAS_NIRI" = true ]; then
                write_niri_modular
                applied=true
            fi
            if [ "$applied" = false ]; then
                write_hypr_modular
            fi
            ;;
        hyprland)
            write_hypr_modular
            ;;
        niri)
            write_niri_modular
            ;;
        all)
            write_hypr_modular
            write_niri_modular
            ;;
        skip)
            info "Skipped compositor injection."
            ;;
    esac

    step_footer
}

# ── Systemd Services Setup ───────────────────────────────────────────────────
setup_system_services() {
    if [ "$CHECK_ONLY" = true ] || [ "$INJECT_ONLY" = true ] || [ "$SHOW_NIX_GUIDE" = true ]; then
        return 0
    fi

    step_header "4/5 System Daemons & Services"

    SERVICES=("NetworkManager" "bluetooth" "power-profiles-daemon" "upower")
    INACTIVE_SERVICES=()

    for s in "${SERVICES[@]}"; do
        if command -v systemctl &>/dev/null; then
            if systemctl is-active --quiet "$s" 2>/dev/null; then
                success "Service '$s' is active and running."
            else
                warn "Service '$s' is currently inactive or not started."
                INACTIVE_SERVICES+=("$s")
            fi
        fi
    done

    if [ ${#INACTIVE_SERVICES[@]} -gt 0 ]; then
        ENABLE_SERVICES=false
        if [ "$AUTO_YES" = true ]; then
            ENABLE_SERVICES=true
        else
            echo -e "\n  ${BOLD}Inactive system services detected:${NC} ${YELLOW}${INACTIVE_SERVICES[*]}${NC}"
            read -rp "  Would you like to enable & start these services now? [y/N] (default: y): " srv_resp
            if [[ "$srv_resp" =~ ^[Yy]$ ]] || [ -z "$srv_resp" ]; then
                ENABLE_SERVICES=true
            fi
        fi

        if [ "$ENABLE_SERVICES" = true ]; then
            for s in "${INACTIVE_SERVICES[@]}"; do
                info "Enabling & starting $s..."
                sudo systemctl enable --now "$s" 2>/dev/null || warn "Could not enable $s automatically (requires sudo)."
            done
        fi
    fi

    step_footer
}

# ── Post-Installation Actions & Reference ─────────────────────────────────────
post_installation_summary() {
    step_header "5/5 Post-Installation & Verification"

    echo -e "${GREEN}${BOLD}==============================================================================${NC}"
    echo -e "${GREEN}${BOLD}  Quickshell Desktop Environment Setup Completed Successfully!                ${NC}"
    echo -e "${GREEN}${BOLD}==============================================================================${NC}\n"

    echo -e "${BOLD}1. Keybinding Cheat Sheet:${NC}"
    echo -e "   ${CYAN}${BOLD}SUPER + SPACE${NC}        →  App Launcher (Fuzzy search, Calculator, App grid)"
    echo -e "   ${CYAN}${BOLD}SUPER + SHIFT + W${NC}    →  Wallpaper Selector (Select, preview, manage wallpapers)"
    echo -e "   ${CYAN}${BOLD}SUPER + SHIFT + E${NC}    →  Emoji Picker (Search & copy 1,800+ emojis)"
    echo -e "   ${CYAN}${BOLD}SUPER + V${NC}            →  Clipboard History (Search, Pin items, Delete)"
    echo -e "   ${CYAN}${BOLD}SUPER + P${NC}            →  Power Menu (Lock, Suspend, Reboot, Shutdown)"
    echo -e "   ${CYAN}${BOLD}SUPER + ALT + L${NC}      →  Lockscreen (PAM auth, Live Media, Custom wallpaper)"
    echo -e "   ${CYAN}${BOLD}SUPER + D${NC}            →  Dashboard (System stats, Hardware monitor, Notes)"
    echo -e "   ${CYAN}${BOLD}SUPER + N${NC}            →  Notification Center (History, DND mode, Actions)"
    echo -e "   ${CYAN}${BOLD}SUPER + C${NC}            →  Control Center (WiFi, Bluetooth, Audio, Power profiles)"
    echo -e "   ${CYAN}${BOLD}SUPER + B${NC}            →  Battery & Power Panel"
    echo -e "   ${CYAN}${BOLD}PRINT${NC}                →  Fullscreen Screenshot (Grim + Slurp + Swappy)"
    echo -e "   ${CYAN}${BOLD}SHIFT + PRINT${NC}        →  Area Selection Screenshot"
    echo -e "   ${CYAN}${BOLD}SUPER + PRINT${NC}        →  Active Window Screenshot"
    echo ""

    echo -e "${BOLD}2. IPC Command Reference (for terminal or custom binds):${NC}"
    echo -e "   Launch Quickshell:    ${GREEN}qs${NC}  or  ${GREEN}quickshell${NC}"
    echo -e "   Live Logs Stream:     ${GREEN}qs log${NC}"
    echo -e "   Toggle Launcher:      ${GREEN}qs ipc call launcher toggle${NC}"
    echo -e "   Toggle Wallpaper:     ${GREEN}qs ipc call wallpaper toggle${NC}"
    echo -e "   Toggle Emoji Picker:  ${GREEN}qs ipc call emoji toggle${NC}"
    echo -e "   Toggle Clipboard:     ${GREEN}qs ipc call clipboard toggle${NC}"
    echo -e "   Toggle Control Ctr:   ${GREEN}qs ipc call controlCenter toggle${NC}"
    echo -e "   Toggle Notifications: ${GREEN}qs ipc call notifCenter toggle${NC}"
    echo -e "   Toggle Dashboard:     ${GREEN}qs ipc call dashboard toggle${NC}"
    echo -e "   Toggle Settings:      ${GREEN}qs ipc call settings toggle${NC}"
    echo -e "   Lock Screen:          ${GREEN}qs ipc call lockscreen lock${NC}"
    echo -e "   Reload Shell:         ${GREEN}qs ipc call shell reload${NC}"
    echo ""

    # Check active Wayland session & offer live reload / launch
    if [ -n "$WAYLAND_DISPLAY" ]; then
        if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] || pgrep -x Hyprland &>/dev/null; then
            info "Active Hyprland session detected."
            if [ "$AUTO_YES" = false ]; then
                read -rp "  Would you like to reload Hyprland configuration now? [Y/n] (default: y): " hl_reload
                if [[ "$hl_reload" =~ ^[Yy]$ ]] || [ -z "$hl_reload" ]; then
                    if command -v hyprctl &>/dev/null; then
                        hyprctl reload
                        success "Hyprland reloaded!"
                    fi
                fi
            fi
        elif [ -n "$NIRI_SOCKET" ] || pgrep -x niri &>/dev/null; then
            info "Active Niri session detected."
            if [ "$AUTO_YES" = false ]; then
                read -rp "  Would you like to reload Niri configuration now? [Y/n] (default: y): " nr_reload
                if [[ "$nr_reload" =~ ^[Yy]$ ]] || [ -z "$nr_reload" ]; then
                    if command -v niri &>/dev/null; then
                        niri msg action reload-config
                        success "Niri reloaded!"
                    fi
                fi
            fi
        fi

        # Check if Quickshell is already running
        if pgrep -x quickshell &>/dev/null || pgrep -x qs &>/dev/null; then
            success "Quickshell is currently running."
            if [ "$AUTO_YES" = false ]; then
                read -rp "  Would you like to reload Quickshell UI now? [Y/n] (default: y): " qs_reload
                if [[ "$qs_reload" =~ ^[Yy]$ ]] || [ -z "$qs_reload" ]; then
                    if command -v qs &>/dev/null; then
                        qs ipc call shell reload 2>/dev/null || pkill -USR1 qs 2>/dev/null || true
                        success "Quickshell reloaded!"
                    fi
                fi
            fi
        else
            if [ "$AUTO_YES" = false ]; then
                read -rp "  Would you like to start Quickshell now? [Y/n] (default: y): " qs_start
                if [[ "$qs_start" =~ ^[Yy]$ ]] || [ -z "$qs_start" ]; then
                    if command -v qs &>/dev/null; then
                        nohup qs >/dev/null 2>&1 &
                        success "Quickshell launched in background (qs)!"
                    elif command -v quickshell &>/dev/null; then
                        nohup quickshell >/dev/null 2>&1 &
                        success "Quickshell launched in background (quickshell)!"
                    fi
                fi
            fi
        fi
    fi

    echo -e "\n${GREEN}${BOLD}Enjoy your new Quickshell desktop environment!${NC}\n"
    step_footer
}

# ── Interactive Main Menu ─────────────────────────────────────────────────────
interactive_menu_launcher() {
    print_banner

    # Direct execution if flags were provided
    if [ "$SHOW_NIX_GUIDE" = true ]; then
        show_nix_declarative_guide
        exit 0
    fi

    if [ "$AUTO_YES" = true ] || [ "$CHECK_ONLY" = true ] || [ "$INJECT_ONLY" = true ] || [ "$SKIP_DEPS" = true ]; then
        if [ "$INJECT_ONLY" = true ]; then
            inject_compositor_configs
            exit 0
        fi
        setup_target_directory
        run_dependency_diagnostics
        if [ "$CHECK_ONLY" = true ]; then
            exit 0
        fi
        inject_compositor_configs
        setup_system_services
        post_installation_summary
        exit 0
    fi

    # Interactive top-level menu
    echo -e "  ${BOLD}Please choose an installation option:${NC}\n"
    echo -e "    ${CYAN}${BOLD}1)${NC} ${BOLD}Full Interactive Installation${NC} ${GREEN}(Recommended - All Steps)${NC}"
    echo -e "    ${CYAN}${BOLD}2)${NC} ${BOLD}Compositor Configuration & Keybinding Injection Only${NC} (Hyprland / Niri)"
    echo -e "    ${CYAN}${BOLD}3)${NC} ${BOLD}Real-Time Dependency Diagnostic Check Only${NC}"
    echo -e "    ${CYAN}${BOLD}4)${NC} ${BOLD}System Services Manager${NC} (NetworkManager, Bluetooth, Power profiles)"
    echo -e "    ${CYAN}${BOLD}5)${NC} ${BOLD}NixOS / Home Manager Declarative Setup Guide${NC} (Flakes & Module)"
    echo -e "    ${CYAN}${BOLD}6)${NC} ${BOLD}Quick Express Install${NC} (Auto-accept standard defaults)"
    echo -e "    ${CYAN}${BOLD}7)${NC} Exit\n"

    read -rp "  Select option [1-7] (default: 1): " main_choice

    case "$main_choice" in
        2)
            setup_target_directory
            inject_compositor_configs
            echo -e "${GREEN}${BOLD}Compositor injection completed!${NC}\n"
            ;;
        3)
            CHECK_ONLY=true
            run_dependency_diagnostics
            ;;
        4)
            setup_system_services
            ;;
        5)
            show_nix_declarative_guide
            ;;
        6)
            AUTO_YES=true
            setup_target_directory
            run_dependency_diagnostics
            inject_compositor_configs
            setup_system_services
            post_installation_summary
            ;;
        7)
            echo -e "\n${DIM}Installation cancelled.${NC}\n"
            exit 0
            ;;
        *)
            setup_target_directory
            run_dependency_diagnostics
            inject_compositor_configs
            setup_system_services
            post_installation_summary
            ;;
    esac
}

# ── Entry Point ───────────────────────────────────────────────────────────────
interactive_menu_launcher
