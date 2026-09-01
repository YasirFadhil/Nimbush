{ self }:

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.quickshell-shell;
  defaultPackage = if (self.packages ? ${pkgs.system}) then self.packages.${pkgs.system}.default else null;

  # Build JSON wallpaper config declaratively
  wallpaperConfig = {
    currentWallpaper = if cfg.wallpaper.current != null
      then cfg.wallpaper.current
      else "";
    customWallpapers = map (wp:
      if isAttrs wp then wp
      else {
        name = builtins.baseNameOf wp;
        path = wp;
        isCustom = true;
      }
    ) cfg.wallpaper.customWallpapers;
  };
in
{
  options.programs.quickshell-shell = {
    enable = mkEnableOption "Nimbush - YasirFadhil's Quickshell Wayland Desktop Shell";

    package = mkOption {
      type = types.nullOr types.package;
      default = defaultPackage;
      defaultText = literalExpression "inputs.quickshell-shell.packages.\${pkgs.system}.default";
      description = "The quickshell-shell package to install.";
    };

    enableSystemdService = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to create a systemd user service to launch Quickshell automatically upon Wayland session start.";
    };

    enableDefaultDependencies = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to automatically install required CLI dependencies (brightnessctl, cliphist, wl-clipboard, etc.) into home.packages.";
    };

    wallpaper = {
      current = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "/home/user/Pictures/wallpapers/catppuccin.jpg";
        description = "Declarative active wallpaper path.";
      };

      customWallpapers = mkOption {
        type = types.listOf (types.either types.str (types.submodule {
          options = {
            name = mkOption { type = types.str; description = "Wallpaper display name"; };
            path = mkOption { type = types.str; description = "Wallpaper file path"; };
            isCustom = mkOption { type = types.bool; default = true; description = "Whether wallpaper is custom"; };
          };
        }));
        default = [ ];
        example = [ "/home/user/Pictures/wall1.jpg" "/home/user/Pictures/wall2.png" ];
        description = "List of custom wallpapers available in the Quickshell Dashboard picker.";
      };
    };

    hyprland = {
      enablePackage = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to include the Hyprland package in home.packages (optional if already installed at system level or using Niri).";
      };

      enableIntegration = mkOption {
        type = types.bool;
        default = true;
        description = "Automatically inject Quickshell keybindings, autostart, and layer rules into Hyprland if enabled in Home Manager.";
      };

      writeModularConfig = mkOption {
        type = types.bool;
        default = true;
        description = "Write standalone modular Quickshell configuration files (conf/quickshell.conf and conf/quickshell.lua) into ~/.config/hypr/.";
      };

      writeModularTree = mkOption {
        type = types.bool;
        default = true;
        description = "Write full modular tree files (conf/autostart, conf/keybinds, conf/rules) into ~/.config/hypr/.";
      };
    };

    niri = {
      enablePackage = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to include the Niri package in home.packages (optional if already installed at system level or using Hyprland).";
      };

      enableIntegration = mkOption {
        type = types.bool;
        default = true;
        description = "Automatically inject Quickshell autostart and keybindings into Niri if enabled in Home Manager.";
      };

      writeModularConfig = mkOption {
        type = types.bool;
        default = true;
        description = "Write standalone modular Quickshell configuration file (conf/quickshell.kdl) into ~/.config/niri/.";
      };

      writeModularTree = mkOption {
        type = types.bool;
        default = true;
        description = "Write full modular tree files (conf/autostart.kdl, conf/keybinds.kdl, conf/rules.kdl) into ~/.config/niri/.";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      home.packages = (optional (cfg.package != null) cfg.package)
        ++ (optional cfg.hyprland.enablePackage pkgs.hyprland)
        ++ (optional cfg.niri.enablePackage pkgs.niri)
        ++ (optionals cfg.enableDefaultDependencies (with pkgs; [
          quickshell
          networkmanager
          bluez
          bluez-tools
          brightnessctl
          cliphist
          wl-clipboard
          wtype
          power-profiles-daemon
          upower
          socat
          psmisc
          procps
          libnotify
          git
          dbus
          glib
          grim
          slurp
          swappy
          zenity
          fastfetch
          sound-theme-freedesktop
          matugen
          wireplumber
          awww
          swaybg
          (python3.withPackages (ps: with ps; [
            pygobject3
            dbus-python
          ]))
          gobject-introspection
          gtk3
          fontconfig
          dconf
          gsettings-desktop-schemas
        ]));

      # Automatically place files into ~/.config/quickshell if not using wrapped package
      xdg.configFile."quickshell" = mkIf (cfg.package == null) {
        source = self;
        recursive = true;
      };

      # Declarative Wallpaper Configuration
      xdg.configFile."quickshell/wallpaper_config.json" = mkIf (cfg.wallpaper.current != null || cfg.wallpaper.customWallpapers != [ ]) {
        text = builtins.toJSON wallpaperConfig;
      };

      # Standalone Modular Hyprland Configurations (Conf format)
      xdg.configFile."hypr/conf/quickshell.conf" = mkIf cfg.hyprland.writeModularConfig {
        text = ''
# ── Quickshell Desktop Environment Integration (Hyprland Classic) ──
exec-once = qs

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
'';
      };

      xdg.configFile."hypr/conf/autostart.conf" = mkIf (cfg.hyprland.writeModularConfig && cfg.hyprland.writeModularTree) {
        text = ''
# ── Autostart Daemons & Background Services (Hyprland Classic) ──
exec-once = systemctl enable --now --user hyprpolkitagent
exec-once = wl-paste --type text --watch cliphist store
exec-once = wl-paste --type image --watch cliphist store
'';
      };

      xdg.configFile."hypr/conf/keybinds.conf" = mkIf (cfg.hyprland.writeModularConfig && cfg.hyprland.writeModularTree) {
        text = ''
# ── Keybindings & Shortcuts (Hyprland Classic) ──
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
'';
      };

      xdg.configFile."hypr/conf/rules.conf" = mkIf (cfg.hyprland.writeModularConfig && cfg.hyprland.writeModularTree) {
        text = ''
# ── Window Rules (Hyprland Classic) ──
windowrulev2 = suppressevent maximize, class:.*
windowrulev2 = float, title:^(Picture-in-Picture|Picture in picture)$
windowrulev2 = pin, title:^(Picture-in-Picture|Picture in picture)$
windowrulev2 = float, class:^(pavucontrol|nm-connection-editor|blueman-manager|swappy)$
'';
      };

      # Standalone Modular Hyprland Configurations (Lua format)
      xdg.configFile."hypr/conf/quickshell.lua" = mkIf cfg.hyprland.writeModularConfig {
        text = ''
-- ── Quickshell Desktop Environment Integration (Hyprland Lua) ──
local mainMod = "SUPER"

hl.on("hyprland.start", function ()
    hl.exec_cmd("qs")
end)

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
'';
      };

      xdg.configFile."hypr/conf/autostart.lua" = mkIf (cfg.hyprland.writeModularConfig && cfg.hyprland.writeModularTree) {
        text = ''
-- ── Autostart Daemons & Background Services (Hyprland Lua) ──
hl.on("hyprland.start", function ()
    hl.exec_cmd("systemctl enable --now --user hyprpolkitagent")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)
'';
      };

      xdg.configFile."hypr/conf/keybinds.lua" = mkIf (cfg.hyprland.writeModularConfig && cfg.hyprland.writeModularTree) {
        text = ''
-- ── Keybindings & Shortcuts (Hyprland Lua) ──
local mainMod = "SUPER"
local terminal = "kitty"
local fileManager = "nautilus"

hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal), { repeating = true })
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + Q", hl.dsp.window.close(), { repeating = true })
hl.bind(mainMod .. " + ALT + F", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))

for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind("print", hl.dsp.exec_cmd("~/.config/quickshell/scripts/screenshot.sh full"), { locked = true })
hl.bind("SHIFT + print", hl.dsp.exec_cmd("~/.config/quickshell/scripts/screenshot.sh region"), { locked = true })
hl.bind(mainMod .. " + print", hl.dsp.exec_cmd("~/.config/quickshell/scripts/screenshot.sh window"), { locked = true })
'';
      };

      xdg.configFile."hypr/conf/rules.lua" = mkIf (cfg.hyprland.writeModularConfig && cfg.hyprland.writeModularTree) {
        text = ''
-- ── Window & Workspace Rules (Hyprland Lua) ──
hl.window_rule({
    name  = "suppress-maximize",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name  = "pip-float",
    match = { title = "^(Picture-in-Picture|Picture in picture)$" },
    float = true,
    pin   = true,
})

hl.window_rule({
    name  = "dialog-float",
    match = { class = "(pavucontrol|nm-connection-editor|blueman-manager|swappy)" },
    float = true,
})
'';
      };

      # Standalone Modular Niri Configuration
      xdg.configFile."niri/conf/quickshell.kdl" = mkIf cfg.niri.writeModularConfig {
        text = ''
// ── Quickshell Desktop Environment Integration (Niri) ──
spawn-at-startup "qs"

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
'';
      };

      xdg.configFile."niri/conf/autostart.kdl" = mkIf (cfg.niri.writeModularConfig && cfg.niri.writeModularTree) {
        text = ''
// ── Autostart Daemons & Services (Niri) ──
spawn-at-startup "wl-paste" "--type" "text" "--watch" "cliphist" "store"
spawn-at-startup "wl-paste" "--type" "image" "--watch" "cliphist" "store"
'';
      };

      xdg.configFile."niri/conf/keybinds.kdl" = mkIf (cfg.niri.writeModularConfig && cfg.niri.writeModularTree) {
        text = ''
// ── Keybindings & Shortcuts (Niri) ──
binds {
    Mod+Return { spawn "kitty"; }
    Mod+E      { spawn "nautilus"; }
    Mod+Q      { close-window; }
    Mod+F      { fullscreen-window; }

    Mod+Left   { focus-column-left; }
    Mod+Right  { focus-column-right; }
    Mod+Up     { focus-window-up; }
    Mod+Down   { focus-window-down; }

    Mod+1 { focus-workspace 1; }
    Mod+2 { focus-workspace 2; }
    Mod+3 { focus-workspace 3; }
    Mod+4 { focus-workspace 4; }
    Mod+5 { focus-workspace 5; }
    Mod+6 { focus-workspace 6; }
    Mod+7 { focus-workspace 7; }
    Mod+8 { focus-workspace 8; }
    Mod+9 { focus-workspace 9; }

    Print       { spawn "sh" "-c" "~/.config/quickshell/scripts/screenshot.sh full"; }
    Shift+Print { spawn "sh" "-c" "~/.config/quickshell/scripts/screenshot.sh region"; }
    Mod+Print   { spawn "sh" "-c" "~/.config/quickshell/scripts/screenshot.sh window"; }
}
'';
      };

      xdg.configFile."niri/conf/rules.kdl" = mkIf (cfg.niri.writeModularConfig && cfg.niri.writeModularTree) {
        text = ''
// ── Window & Layout Rules (Niri) ──
window-rule {
    match app-id=r#"^(pavucontrol|nm-connection-editor|blueman-manager|swappy)$"#
    open-floating true
}

window-rule {
    match title=r#"^(Picture-in-Picture|Picture in picture)$"#
    open-floating true
}
'';
      };

      # Systemd user service for auto-launching Quickshell on Graphical Sessions
      systemd.user.services.quickshell-shell = mkIf cfg.enableSystemdService {
        Unit = {
          Description = "Quickshell Wayland Desktop Shell";
          Documentation = [ "https://github.com/YasirFadhil/Nimbush" ];
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };

        Service = {
          ExecStart = if cfg.package != null
            then "${cfg.package}/bin/quickshell-shell"
            else "${pkgs.quickshell}/bin/qs -c %h/.config/quickshell";
          Restart = "on-failure";
          RestartSec = "2s";
        };

        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
      };
    }

    # Declarative Hyprland Integration
    (mkIf (cfg.hyprland.enableIntegration && (cfg.hyprland.enablePackage || (lib.attrByPath [ "wayland" "windowManager" "hyprland" "enable" ] false config))) {
      wayland.windowManager.hyprland.settings = {
        exec-once = (optional (!cfg.enableSystemdService) "qs") ++ [
          "wl-paste --type text --watch cliphist store"
          "wl-paste --type image --watch cliphist store"
        ];
        bind = [
          "SUPER, SPACE, exec, qs ipc call launcher toggle"
          "SUPER SHIFT, W, exec, qs ipc call wallpaper toggle"
          "SUPER SHIFT, E, exec, qs ipc call emoji toggle"
          "SUPER, V, exec, qs ipc call clipboard toggle"
          "SUPER, P, exec, qs ipc call powermenu toggle"
          "SUPER ALT, L, exec, qs ipc call lockscreen toggle"
          "SUPER, D, exec, qs ipc call dashboard toggle"
          "SUPER, N, exec, qs ipc call notifCenter toggle"
          "SUPER, C, exec, qs ipc call controlCenter toggle"
          "SUPER, B, exec, qs ipc call battery toggle"
          ", PRINT, exec, ~/.config/quickshell/scripts/screenshot.sh full"
          "SHIFT, PRINT, exec, ~/.config/quickshell/scripts/screenshot.sh region"
          "SUPER, PRINT, exec, ~/.config/quickshell/scripts/screenshot.sh window"
        ];
        layerrule = [
          "blur, quickshell:bar"
          "blur, quickshell:launcher"
          "ignorezero, quickshell:launcher"
          "blur, quickshell:wallpaperselector"
          "ignorezero, quickshell:wallpaperselector"
          "blur, quickshell:emojipicker"
          "ignorezero, quickshell:emojipicker"
          "blur, quickshell:clipboard"
          "ignorezero, quickshell:clipboard"
          "blur, quickshell:controlcenter"
          "ignorezero, quickshell:controlcenter"
          "blur, quickshell:notifcenter"
          "ignorezero, quickshell:notifcenter"
          "blur, quickshell:dashboard"
          "ignorezero, quickshell:dashboard"
          "blur, quickshell:calendar"
          "ignorezero, quickshell:calendar"
          "blur, quickshell:hud"
          "ignorezero, quickshell:hud"
          "blur, quickshell:traymenu"
          "ignorezero, quickshell:traymenu"
          "blur, quickshell:trayoverflow"
          "ignorezero, quickshell:trayoverflow"
          "blur, quickshell:battery"
          "ignorezero, quickshell:battery"
          "blur, quickshell:volume"
          "ignorezero, quickshell:volume"
          "blur, quickshell:settings"
          "ignorezero, quickshell:settings"
          "blur, quickshell:welcome"
          "ignorezero, quickshell:welcome"
          "blur, quickshell:powermenu"
          "ignorezero, quickshell:powermenu"
          "blur, quickshell:lockscreen"
          "blur, quickshell:osd"
          "ignorezero, quickshell:osd"
          "blur, quickshell:volumeosd"
          "ignorezero, quickshell:volumeosd"
          "blur, quickshell:brightnessosd"
          "ignorezero, quickshell:brightnessosd"
          "blur, ^quickshell:.*$"
          "ignorezero, ^quickshell:.*$"
        ];
      };
    })

    # Declarative Niri Integration
    (mkIf (cfg.niri.enableIntegration && (cfg.niri.enablePackage || (lib.attrByPath [ "programs" "niri" "enable" ] false config))) {
      programs.niri.settings = {
        spawn-at-startup = (optional (!cfg.enableSystemdService) { command = [ "qs" ]; }) ++ [
          { command = [ "wl-paste" "--type" "text" "--watch" "cliphist" "store" ]; }
          { command = [ "wl-paste" "--type" "image" "--watch" "cliphist" "store" ]; }
        ];
        binds = {
          "Mod+Space".action.spawn = [ "qs" "ipc" "call" "launcher" "toggle" ];
          "Mod+Shift+W".action.spawn = [ "qs" "ipc" "call" "wallpaper" "toggle" ];
          "Mod+Shift+E".action.spawn = [ "qs" "ipc" "call" "emoji" "toggle" ];
          "Mod+V".action.spawn = [ "qs" "ipc" "call" "clipboard" "toggle" ];
          "Mod+P".action.spawn = [ "qs" "ipc" "call" "powermenu" "toggle" ];
          "Mod+Alt+L".action.spawn = [ "qs" "ipc" "call" "lockscreen" "toggle" ];
          "Mod+D".action.spawn = [ "qs" "ipc" "call" "dashboard" "toggle" ];
          "Mod+N".action.spawn = [ "qs" "ipc" "call" "notifCenter" "toggle" ];
          "Mod+C".action.spawn = [ "qs" "ipc" "call" "controlCenter" "toggle" ];
          "Mod+B".action.spawn = [ "qs" "ipc" "call" "battery" "toggle" ];
          "Print".action.spawn = [ "sh" "-c" "~/.config/quickshell/scripts/screenshot.sh full" ];
          "Shift+Print".action.spawn = [ "sh" "-c" "~/.config/quickshell/scripts/screenshot.sh region" ];
          "Mod+Print".action.spawn = [ "sh" "-c" "~/.config/quickshell/scripts/screenshot.sh window" ];
        };
      };
    })
  ]);
}
