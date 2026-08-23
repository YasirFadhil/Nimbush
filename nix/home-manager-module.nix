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
          swww
          swaybg
          (python3.withPackages (ps: with ps; [
            pygobject3
            dbus-python
          ]))
          gobject-introspection
          gtk3
        ]));

      # Automatically place files into ~/.config/quickshell if not using wrapped package
      xdg.configFile."quickshell" = mkIf (cfg.package == null) {
        source = ../.;
        recursive = true;
      };

      # Declarative Wallpaper Configuration
      xdg.configFile."quickshell/wallpaper_config.json" = mkIf (cfg.wallpaper.current != null || cfg.wallpaper.customWallpapers != [ ]) {
        text = builtins.toJSON wallpaperConfig;
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
    (mkIf (cfg.hyprland.enableIntegration && (cfg.hyprland.enablePackage || (config.wayland.windowManager ? hyprland && config.wayland.windowManager.hyprland ? enable && config.wayland.windowManager.hyprland.enable))) {
      wayland.windowManager.hyprland.settings = {
        exec-once = [
          "wl-paste --type text --watch cliphist store"
          "wl-paste --type image --watch cliphist store"
        ];
        bind = [
          "SUPER, SPACE, exec, qs ipc call launcher toggle"
          "SUPER, V, exec, qs ipc call clipboard toggle"
          "SUPER, P, exec, qs ipc call powermenu toggle"
          "SUPER ALT, L, exec, qs ipc call lockscreen toggle"
          "SUPER, D, exec, qs ipc call dashboard toggle"
          "SUPER, N, exec, qs ipc call notifCenter toggle"
          "SUPER, C, exec, qs ipc call controlCenter toggle"
          "SUPER, B, exec, qs ipc call battery toggle"
          "SUPER, COMMA, exec, qs ipc call settings toggle"
          ", PRINT, exec, ~/.config/quickshell/scripts/screenshot.sh full"
          "SHIFT, PRINT, exec, ~/.config/quickshell/scripts/screenshot.sh region"
          "SUPER, PRINT, exec, ~/.config/quickshell/scripts/screenshot.sh window"
        ];
        layerrule = [
          "blur, quickshell:bar"
          "blur, quickshell:launcher"
          "ignorezero, quickshell:launcher"
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
        ];
      };
    })

    # Declarative Niri Integration
    (mkIf (cfg.niri.enableIntegration && (cfg.niri.enablePackage || (config.programs ? niri && config.programs.niri ? enable && config.programs.niri.enable))) {
      programs.niri.settings = {
        spawn-at-startup = [
          { command = [ "wl-paste" "--type" "text" "--watch" "cliphist" "store" ]; }
          { command = [ "wl-paste" "--type" "image" "--watch" "cliphist" "store" ]; }
        ];
        binds = {
          "Mod+Space".action.spawn = [ "qs" "ipc" "call" "launcher" "toggle" ];
          "Mod+V".action.spawn = [ "qs" "ipc" "call" "clipboard" "toggle" ];
          "Mod+P".action.spawn = [ "qs" "ipc" "call" "powermenu" "toggle" ];
          "Mod+Alt+L".action.spawn = [ "qs" "ipc" "call" "lockscreen" "toggle" ];
          "Mod+D".action.spawn = [ "qs" "ipc" "call" "dashboard" "toggle" ];
          "Mod+N".action.spawn = [ "qs" "ipc" "call" "notifCenter" "toggle" ];
          "Mod+C".action.spawn = [ "qs" "ipc" "call" "controlCenter" "toggle" ];
          "Mod+B".action.spawn = [ "qs" "ipc" "call" "battery" "toggle" ];
          "Mod+Comma".action.spawn = [ "qs" "ipc" "call" "settings" "toggle" ];
          "Print".action.spawn = [ "sh" "-c" "~/.config/quickshell/scripts/screenshot.sh full" ];
          "Shift+Print".action.spawn = [ "sh" "-c" "~/.config/quickshell/scripts/screenshot.sh region" ];
          "Mod+Print".action.spawn = [ "sh" "-c" "~/.config/quickshell/scripts/screenshot.sh window" ];
        };
      };
    })
  ]);
}
