# Shell by YasirFadhil

This repository contains my personal Wayland desktop environment configuration.

## What is this?

This is not a traditional command-line shell. It is a Wayland UI shell built with **Quickshell**, which handles panels, widgets, notifications, and menus for my desktop.

## Components

- **Quickshell**: The core UI framework.
- **Hyprland / Niri**: Supported Wayland compositors.

## Dependencies

Before running Quickshell, ensure the following dependencies are installed on your system:

### Core Framework & Compositors

- **Quickshell** (`quickshell-git` / `quickshell`)
- **Hyprland** (`hyprland`) or **Niri** (`niri`)

### System Utilities & Services

- **NetworkManager** (`networkmanager` / `nmcli`) – Wi-Fi and network management
- **BlueZ** (`bluez`, `bluez-utils` / `bluetoothctl`) – Bluetooth management
- **PipeWire / PulseAudio** (`libpulse` / `pactl`) – Audio volume & sink control
- **Brightnessctl** (`brightnessctl`) – Screen brightness control
- **Cliphist** & **wl-clipboard** (`cliphist`, `wl-clipboard`) – Clipboard history & selection handling
- **Power Profiles Daemon** (`power-profiles-daemon`) – Power profile mode switcher
- **UPower** (`upower`) – Battery & power monitoring
- **socat** (`socat`) – Hyprland IPC socket listener for workspaces (for Hyprland mode)
- **psmisc** (`psmisc` / `fuser`) – Camera active status detection for Dynamic Island

### Fonts

- **Nerd Fonts Symbols** (`ttf-nerd-fonts-symbols-mono` / `ttf-jetbrains-mono-nerd`) – UI icons (`Symbols Nerd Font Mono`)

## Installation & Setup

### Quick Install (Automated)

Clone the repository and run the installation script:

```bash
git clone https://github.com/YasirFadhil/Shell.git ~/.config/quickshell
cd ~/.config/quickshell
./install.sh
```

The script will handle directory setup, verify required CLI commands, and check system services.

### Manual Setup

If you prefer to set up manually:

```bash
git clone https://github.com/YasirFadhil/Shell.git ~/.config/quickshell
qs -c ~/.config/quickshell
```

### Hyprland Configuration (Hyprland 0.55+)

To make the shell start automatically when you launch Hyprland, add this line to your `hyprland.lua`:

```lua
-- Autostart Quickshell
hl.on("hyprland.start", function ()
    hl.exec_cmd("qs -c ~/.config/quickshell")
end)

-- Keybindings
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd("qs ipc call launcher toggle"))
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("qs ipc call clipboard toggle"))
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("qs ipc call powermenu toggle"))
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("qs ipc call lockscreen toggle"))

-- Layer Rules
hl.layer_rule({ match = { namespace = "quickshell:bar" }, blur = true })
hl.layer_rule({ match = { namespace = "quickshell:launcher" },      blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:clipboard" },     blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:controlcenter" }, blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:notifcenter" },   blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:calendar" },      blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:hud" },      blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "^quickshell:.*$" }, blur = true, ignore_alpha = 0 })
```

### Niri Configuration (`config.kdl`)

To use this configuration on **Niri**, add the autostart and keybindings to your `~/.config/niri/config.kdl`:

```kdl
// Autostart Quickshell
spawn-at-startup "qs" "-c" "~/.config/quickshell"

// Keybindings
binds {
    Mod+Space { spawn "qs" "ipc" "call" "launcher" "toggle"; }
    Mod+V     { spawn "qs" "ipc" "call" "clipboard" "toggle"; }
    Mod+P     { spawn "qs" "ipc" "call" "powermenu" "toggle"; }
    Mod+L     { spawn "qs" "ipc" "call" "lockscreen" "toggle"; }
}
```

## DISCLAIMER: FULL VIBE CODED

Please be warned: this entire repository is **full vibe coded**.

- There are no strict architectural patterns.
- Zero best practices are guaranteed.
- The code was written purely based on what worked and looked good at the time.

Use or copy this code at your own risk.
