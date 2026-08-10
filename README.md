# Shell by YasirFadhil

This repository contains my personal Wayland desktop environment configuration.

## What is this?
This is not a traditional command-line shell. It is a Wayland UI shell built with **Quickshell**, which handles panels, widgets, notifications, and menus for my desktop.

## Components
* **Quickshell**: The core UI framework.
* **Hyprland**: Supported Wayland compositors.
* **wlogout**: Custom power menu styling.

## Installation & Setup

First, clone the repository and move it to your Quickshell configuration directory:

```bash
git clone https://github.com/YasirFadhil/Shell.git
mv Shell ~/.config/quickshell
```

### Hyprland Configuration (Standard .conf)

To make the shell start automatically when you launch Hyprland, add this line to your `hyprland.conf`:

```ini
exec-once = qs -c ~/.config/quickshell
```

To set up keybindings for the application launcher and the clipboard manager:

```ini
bind = $mainMod, SPACE, exec, qs ipc call launcher toggle
bind = $mainMod, V, exec, qs ipc call clipboard toggle
bind = $mainMod, P, exec, qs ipc call power toggle
```

### Hyprland Configuration (Latest Lua Config)

If you are using the newer Lua-based configuration for Hyprland, you can integrate it like this:

```lua
-- Autostart Quickshell
hl.on("hyprland.start", function ()
    hl.exec_cmd("qs -c ~/.config/quickshell")
end)

-- Keybindings
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd("qs ipc call launcher toggle"))
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("qs ipc call clipboard toggle"))
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("qs ipc call powermenu toggle"))
```

## DISCLAIMER: FULL VIBE CODED
Please be warned: this entire repository is **full vibe coded**. 
* There are no strict architectural patterns.
* Zero best practices are guaranteed.
* The code was written purely based on what worked and looked good at the time.

Use or copy this code at your own risk.
