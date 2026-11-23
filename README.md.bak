# Nimbush

A sleek, modern, and highly modular Wayland desktop environment shell built with **Quickshell** by **YasirFadhil**.

---

## Highlights

- **Dual Compositor Compatibility**: Seamless support for **Hyprland** (Lua & Classic `.conf` format) and **Niri** scrollable tiling compositor.
- **Strict Modular Tree Structure**: Clean separation of configs (`conf/autostart`, `conf/keybinds`, `conf/rules`, `conf/quickshell`).
- **Interactive App Launcher**: Fast, focused application runner with instant fuzzy search (`Super + Space`).
- **Wallpaper Manager**: Dynamic visual wallpaper selector powered by `awww` / `swww` and Material You palette generator (`Super + Shift + W`).
- **Emoji Picker**: Quick Unicode emoji search & clipboard inserter (`Super + Shift + E`).
- **Clipboard History**: Integrated clipboard manager with pinning support (`Super + V`).
- **Control Center & Dashboard**: Unified toggles for Wi-Fi, Bluetooth, Audio, Power Profiles, System Hardware Monitor, and Notifications.

---

## Supported Linux Distributions

The installer and shell components are optimized specifically for:

- **Arch Linux & Derivatives** (`pacman`, `yay`, `paru`)
- **NixOS** (Flake & Home Manager Module)
- **Gentoo Linux** (`emerge`)

---

## Quick Installation

### 1. Automated Installer (Arch / Gentoo / Generic)

```bash
git clone https://github.com/YasirFadhil/Nimbush.git ~/.config/quickshell
cd ~/.config/quickshell
./install.sh
```

The interactive installer automatically verifies required dependencies, sets up system services, and configures your compositor without duplicating lines.

#### Installer Options
- `./install.sh` : Interactive installer with automated compositor injection.
- `./install.sh --hyprland` : Auto-detect and configure Hyprland (Lua or Classic `.conf`).
- `./install.sh --niri` : Configure Niri compositor.
- `./install.sh --check-only` : Run real-time health and dependency diagnostics.

---

### 2. NixOS & Home Manager Setup

#### Instant Test Run (`nix run`)

```bash
nix run github:YasirFadhil/Nimbush
```

#### Declarative Setup via Home Manager Module

Add Nimbush to your `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";

    quickshell-shell = {
      url = "github:YasirFadhil/Nimbush";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, quickshell-shell, ... }: {
    # ...
  };
}
```

Enable and configure in your `home.nix`:

```nix
{ pkgs, inputs, ... }:

{
  imports = [
    inputs.quickshell-shell.homeManagerModules.default
  ];

  programs.quickshell-shell = {
    enable = true;
    enableSystemdService = true;      # Runs Quickshell as a user background service
    enableDefaultDependencies = true; # Automatically installs required runtime tools

    # Declarative Wallpaper Configuration
    wallpaper = {
      current = "/home/username/Pictures/wallpapers/catppuccin.jpg";
      customWallpapers = [
        "/home/username/Pictures/wallpapers/wallpaper1.jpg"
      ];
    };

    # Declarative Compositor Integration
    hyprland.enableIntegration = true; # If using Hyprland in Home Manager
    niri.enableIntegration     = true; # If using Niri in Home Manager
  };
}
```

---

## Modular Configuration Tree

Nimbush follows a clean, isolated directory structure for both Hyprland and Niri:

### Hyprland (`~/.config/hypr/`)
```text
~/.config/hypr/
├── hyprland.lua (or hyprland.conf)  # Main entry point (monitors, look & feel, layouts)
└── conf/
    ├── autostart.lua (.conf)       # System daemons (hyprpolkitagent, wl-paste, cliphist)
    ├── keybinds.lua (.conf)        # General navigation & application shortcuts
    ├── rules.lua (.conf)           # Window & workspace rules
    └── quickshell.lua (.conf)      # Quickshell autostart, IPC binds & layer blur rules
```

### Niri (`~/.config/niri/`)
```text
~/.config/niri/
├── config.kdl                      # Main entry point (output, layout, input)
└── conf/
    ├── autostart.kdl               # Clipboard & system daemons
    ├── keybinds.kdl                # Window & workspace keybindings
    ├── rules.kdl                   # Window & layer rules
    └── quickshell.kdl              # Quickshell autostart & IPC binds
```

---

## Default Shortcuts & IPC Commands

| Action | Default Keybind | IPC Command |
|---|---|---|
| **App Launcher** | `Super + Space` | `qs ipc call launcher toggle` |
| **Wallpaper Selector** | `Super + Shift + W` | `qs ipc call wallpaper toggle` |
| **Emoji Picker** | `Super + Shift + E` | `qs ipc call emoji toggle` |
| **Clipboard History** | `Super + V` | `qs ipc call clipboard toggle` |
| **Power Menu** | `Super + P` | `qs ipc call powermenu toggle` |
| **Lock Screen** | `Super + Alt + L` | `qs ipc call lockscreen toggle` |
| **Dashboard** | `Super + D` | `qs ipc call dashboard toggle` |
| **Notification Center** | `Super + N` | `qs ipc call notifCenter toggle` |
| **Control Center** | `Super + C` | `qs ipc call controlCenter toggle` |
| **Battery & Power** | `Super + B` | `qs ipc call battery toggle` |

---

## Disclaimer: Full Vibe Coded

Please be warned: this entire repository is **full vibe coded**.

- Written purely based on what worked, felt smooth, and looked good.
- Use or adapt at your own risk.
