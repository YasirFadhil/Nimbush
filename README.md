# Shell by YasirFadhil

This repository contains a modern Wayland desktop environment configuration built with **Quickshell**.

## What is this?

This is a Wayland UI shell built with **Quickshell**, providing status bars, dashboard, app launcher, system controls, notifications, wallpaper manager, clipboard history, and power/lock menus.

## Features & Highlights

- **Universal Linux OS Support**: Distro detection for Arch Linux, Debian, Ubuntu, Fedora, NixOS, openSUSE, Gentoo, Void Linux, Alpine Linux, Solus, Manjaro, Pop!_OS, Linux Mint, EndeavourOS, Artix, Kali, SteamOS, and more.
- **Default Wallpaper System**: Ships with **1 clean default wallpaper** (`Wallbler`), plus interactive **Custom Wallpaper** selection via XDG file picker with persistent JSON configuration.
- **Dual Compositor Compatibility**: First-class support for **Hyprland** (Lua & Classic `.conf` format) and **Niri** compositors.

## Supported Linux Distributions

The installer (`install.sh`) and system status modules automatically support detection and package management across:
- **Arch Linux & Derivatives** (`yay`, `paru`, `pacman`)
- **Debian / Ubuntu & Derivatives** (`apt`)
- **Fedora / RHEL / CentOS / Alma / Rocky** (`dnf`)
- **NixOS** (`nix-env` / Home Manager)
- **openSUSE / SUSE** (`zypper`)
- **Void Linux** (`xbps`)
- **Alpine Linux** (`apk`)
- **Gentoo Linux** (`emerge`)
- **Solus** (`eopkg`)

---

## Dependencies

Before running Quickshell, ensure the required dependencies are installed:

### Core Framework & Compositors
- **Quickshell** (`quickshell-git` / `quickshell`)
- **Hyprland** (`hyprland`) or **Niri** (`niri`)

### System Utilities & Services
- **NetworkManager** (`networkmanager` / `nmcli`) – Network & Wi-Fi management
- **BlueZ** (`bluez`, `bluez-utils` / `bluetoothctl`) – Bluetooth management
- **PipeWire / PulseAudio** (`libpulse` / `pactl`, `paplay`) – Volume control & sound feedback
- **Brightnessctl** (`brightnessctl`) – Screen brightness control
- **Cliphist** & **wl-clipboard** (`cliphist`, `wl-clipboard`) – Clipboard history
- **Power Profiles Daemon** (`power-profiles-daemon`) – Power mode switcher
- **UPower** (`upower`) – Battery monitoring
- **socat** (`socat`) – Hyprland socket IPC event listener (Hyprland mode)
- **psmisc** (`psmisc` / `fuser`) – Camera detection for Dynamic Island
- **procps** (`procps` / `pkill`) – Process cleanup & management
- **libnotify** (`libnotify` / `notify-send`) – Desktop notifications
- **git** (`git`) – Automatic shell update service
- **D-Bus & GLib** (`dbus`, `glib` / `dbus-monitor`, `gdbus`) – Bluetooth live signal monitoring & XDG Portal file chooser
- **Grim & Slurp** (`grim`, `slurp`, `swappy`) – Wayland screenshot capture & editing
- **Python 3** (`python3`) – XDG wallpaper file picker script

### Fonts
- **Nerd Fonts** (`ttf-nerd-fonts-symbols-mono` / `ttf-jetbrains-mono-nerd`) – Icons (`Symbols Nerd Font Mono`)

---

## Installation & Setup

### Automated Install

```bash
git clone https://github.com/YasirFadhil/Shell.git ~/.config/quickshell
cd ~/.config/quickshell
./install.sh
```

The `install.sh` script automatically detects your package manager and distro, verifies dependencies, checks system services, and offers live installation.

---

### NixOS Flake & Home Manager Integration

This repository includes a `flake.nix` and a built-in **Home Manager module** ([nix/home-manager-module.nix](file:///home/yasirfadhil/.config/quickshell/nix/home-manager-module.nix)).

#### 1. Instant Run (`nix run`)

Run Quickshell directly via Flake without manual installation:

```bash
nix run github:YasirFadhil/Shell
```

Or from inside the cloned repository directory:

```bash
nix run .
```

#### 2. Declarative Setup via Home Manager Module (`flake.nix` / `home.nix`)

Add this repository to your system `flake.nix` inputs:

```nix
# Your system flake.nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";

    quickshell-shell = {
      url = "github:YasirFadhil/Shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, quickshell-shell, ... }: {
    # ...
  };
}
```

Then enable and configure the module declaratively inside your `home.nix`:

```nix
# home.nix
{ pkgs, inputs, ... }:

{
  imports = [
    inputs.quickshell-shell.homeManagerModules.default
  ];

  programs.quickshell-shell = {
    enable = true;
    enableSystemdService = true;      # Automatically runs Quickshell as a user background service
    enableDefaultDependencies = true; # Installs runtime CLI tools (brightnessctl, cliphist, wl-clipboard, etc.)

    # ── Declarative Wallpaper Configuration ──────────────────────────────
    wallpaper = {
      current = "/home/username/Pictures/wallpapers/catppuccin.jpg";
      customWallpapers = [
        "/home/username/Pictures/wallpapers/wallpaper1.jpg"
        "/home/username/Pictures/wallpapers/wallpaper2.png"
      ];
    };

    # ── Declarative Compositor Integration ────────────────────────────────
    # Automatically injects IPC keybindings, autostart, & blur layer rules
    hyprland.enableIntegration = true; # If wayland.windowManager.hyprland.enable = true
    niri.enableIntegration     = true; # If programs.niri.enable = true
  };
}
```

---

## Compositor Setup & Configuration

Example configuration files are provided in the [`examples/`](file:///home/yasirfadhil/.config/quickshell/examples) directory.

### 1. Hyprland Configuration

#### Option A: Hyprland Lua Configuration (`~/.config/hypr/hyprland.lua` - Hyprland 0.55+)

```lua
local mainMod = "SUPER"

-- Autostart Quickshell & Clipboard daemons
hl.on("hyprland.start", function ()
    hl.exec_cmd("qs -c ~/.config/quickshell")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)

-- Keybindings
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd("qs ipc call launcher toggle"))
hl.bind(mainMod .. " + V",     hl.dsp.exec_cmd("qs ipc call clipboard toggle"))
hl.bind(mainMod .. " + P",     hl.dsp.exec_cmd("qs ipc call powermenu toggle"))
hl.bind(mainMod .. " + L",     hl.dsp.exec_cmd("qs ipc call lockscreen toggle"))
hl.bind(mainMod .. " + D",     hl.dsp.exec_cmd("qs ipc call dashboard toggle"))
hl.bind(mainMod .. " + N",     hl.dsp.exec_cmd("qs ipc call notifCenter toggle"))
hl.bind(mainMod .. " + C",     hl.dsp.exec_cmd("qs ipc call controlCenter toggle"))

-- Layer Rules (Blur & Transparency)
hl.layer_rule({ match = { namespace = "quickshell:bar" },           blur = true })
hl.layer_rule({ match = { namespace = "quickshell:launcher" },      blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:clipboard" },     blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:controlcenter" }, blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:notifcenter" },   blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:dashboard" },     blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:calendar" },      blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:hud" },           blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "^quickshell:.*$" },          blur = true, ignore_alpha = 0 })
```

#### Option B: Hyprland Classic Configuration (`~/.config/hypr/hyprland.conf`)

```ini
$mainMod = SUPER

# Autostart
exec-once = qs -c ~/.config/quickshell
exec-once = wl-paste --type text --watch cliphist store
exec-once = wl-paste --type image --watch cliphist store

# Keybindings
bind = $mainMod, SPACE, exec, qs ipc call launcher toggle
bind = $mainMod, V,     exec, qs ipc call clipboard toggle
bind = $mainMod, P,     exec, qs ipc call powermenu toggle
bind = $mainMod, L,     exec, qs ipc call lockscreen toggle
bind = $mainMod, D,     exec, qs ipc call dashboard toggle
bind = $mainMod, N,     exec, qs ipc call notifCenter toggle
bind = $mainMod, C,     exec, qs ipc call controlCenter toggle

# Layer Rules
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
```

---

### 2. Niri Configuration (`~/.config/niri/config.kdl`)

```kdl
// Autostart Quickshell & Services
spawn-at-startup "qs" "-c" "~/.config/quickshell"
spawn-at-startup "wl-paste" "--type" "text" "--watch" "cliphist" "store"
spawn-at-startup "wl-paste" "--type" "image" "--watch" "cliphist" "store"

// Keybindings
binds {
    Mod+Space { spawn "qs" "ipc" "call" "launcher" "toggle"; }
    Mod+V     { spawn "qs" "ipc" "call" "clipboard" "toggle"; }
    Mod+P     { spawn "qs" "ipc" "call" "powermenu" "toggle"; }
    Mod+L     { spawn "qs" "ipc" "call" "lockscreen" "toggle"; }
    Mod+D     { spawn "qs" "ipc" "call" "dashboard" "toggle"; }
    Mod+N     { spawn "qs" "ipc" "call" "notifCenter" "toggle"; }
    Mod+C     { spawn "qs" "ipc" "call" "controlCenter" "toggle"; }
}
```

---

## Quickshell IPC Commands

You can trigger shell actions from the terminal or compositor keybindings using `qs ipc call`:

| Component | Command |
|---|---|
| **App Launcher** | `qs ipc call launcher toggle` |
| **Clipboard History** | `qs ipc call clipboard toggle` |
| **Power Menu** | `qs ipc call powermenu toggle` |
| **Lock Screen** | `qs ipc call lockscreen lock` |
| **Dashboard** | `qs ipc call dashboard toggle` |
| **Notification Center** | `qs ipc call notifCenter toggle` |
| **Control Center** | `qs ipc call controlCenter toggle` |

---

## DISCLAIMER: FULL VIBE CODED

Please be warned: this entire repository is **full vibe coded**.

- There are no strict architectural patterns.
- Zero best practices are guaranteed.
- The code was written purely based on what worked and looked good at the time.

Use or copy this code at your own risk.
