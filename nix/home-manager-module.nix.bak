{ self }:

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.quickshell-shell;
  defaultPackage = if (self.packages ? ${pkgs.system}) then self.packages.${pkgs.system}.default else null;
  opencvContrib = pkgs.opencv4.override {
    enableContrib = true;
    enablePython = true;
  };
  faceIdPython = pkgs.python3.withPackages (ps: with ps; [
    opencvContrib
    numpy
  ]);

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
        description = "Write Quickshell keybindings, autostart, and layer rules into ~/.config/hypr/conf/*.lua (Hyprland >= 0.55, Lua config only).";
      };

      writeModularConfig = mkOption {
        type = types.bool;
        default = true;
        description = "Write standalone modular Quickshell configuration files into ~/.config/hypr/.";
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
      home.sessionVariables.FACEID_PYTHON = "${faceIdPython}/bin/python";

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
          tlp
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
          ffmpeg
          v4l-utils
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

      # Standalone Modular Hyprland Configurations
      # Hyprland Lua config (>= 0.55)
      xdg.configFile."hypr/conf/quickshell.lua" = mkIf (cfg.hyprland.enableIntegration && cfg.hyprland.writeModularConfig) {
        text = ''
-- ── Quickshell Desktop Environment Integration (Hyprland Lua) ──
local mainMod = "SUPER"

hl.on("hyprland.start", function ()
    hl.exec_cmd("qs")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
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

hl.layer_rule({ match = { namespace = "^quickshell:.*$" }, blur = true, ignore_alpha = 0.2 })

-- Override per-namespace (taruh di bawah catch-all), contoh:
-- hl.layer_rule({ match = { namespace = "quickshell:launcher" }, ignore_alpha = 0.4 })
'';
      };

      xdg.configFile."hypr/conf/autostart.lua" = mkIf (cfg.hyprland.enableIntegration && cfg.hyprland.writeModularConfig && cfg.hyprland.writeModularTree) {
        text = ''
-- ── Autostart Daemons & Background Services (Hyprland Lua) ──
hl.on("hyprland.start", function ()
    hl.exec_cmd("systemctl enable --now --user hyprpolkitagent")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)
'';
      };

      xdg.configFile."hypr/conf/keybinds.lua" = mkIf (cfg.hyprland.enableIntegration && cfg.hyprland.writeModularConfig && cfg.hyprland.writeModularTree) {
        text = ''
-- ── Keybindings & Shortcuts (Hyprland Lua) ──
local mainMod = "SUPER"
local terminal = "kitty"
local fileManager = "nautilus"
local menu = "wofi --show drun"

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

      xdg.configFile."hypr/conf/rules.lua" = mkIf (cfg.hyprland.enableIntegration && cfg.hyprland.writeModularConfig && cfg.hyprland.writeModularTree) {
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
          EnvironmentFile = "-%h/.config/quickshell/state/icon-theme.env";
          Environment = [ "FACEID_PYTHON=${faceIdPython}/bin/python" ];
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
