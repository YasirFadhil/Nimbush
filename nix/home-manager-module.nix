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
    enable = mkEnableOption "YasirFadhil's Quickshell Wayland Desktop Shell";

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
      enableIntegration = mkOption {
        type = types.bool;
        default = true;
        description = "Automatically inject Quickshell keybindings, autostart, and layer rules into Hyprland if enabled in Home Manager.";
      };
    };

    niri = {
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
        ++ (optionals cfg.enableDefaultDependencies (with pkgs; [
          quickshell
          networkmanager
          bluez
          bluez-tools
          brightnessctl
          cliphist
          wl-clipboard
          power-profiles-daemon
          upower
          socat
          psmisc
          python3
          wlogout
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
          Documentation = [ "https://github.com/YasirFadhil/Shell" ];
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
    (mkIf (cfg.hyprland.enableIntegration && (config.wayland.windowManager.hyprland ? enable && config.wayland.windowManager.hyprland.enable)) {
      wayland.windowManager.hyprland.settings = {
        exec-once = [
          "wl-paste --type text --watch cliphist store"
          "wl-paste --type image --watch cliphist store"
        ];
        bind = [
          "SUPER, SPACE, exec, qs ipc call launcher toggle"
          "SUPER, V, exec, qs ipc call clipboard toggle"
          "SUPER, P, exec, qs ipc call powermenu toggle"
          "SUPER, L, exec, qs ipc call lockscreen toggle"
          "SUPER, D, exec, qs ipc call dashboard toggle"
          "SUPER, N, exec, qs ipc call notifCenter toggle"
          "SUPER, C, exec, qs ipc call controlCenter toggle"
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
        ];
      };
    })

    # Declarative Niri Integration
    (mkIf (cfg.niri.enableIntegration && (config.programs ? niri && config.programs.niri ? enable && config.programs.niri.enable)) {
      programs.niri.settings = {
        spawn-at-startup = [
          { command = [ "wl-paste" "--type" "text" "--watch" "cliphist" "store" ]; }
          { command = [ "wl-paste" "--type" "image" "--watch" "cliphist" "store" ]; }
        ];
        binds = {
          "Mod+Space".action.spawn = [ "qs" "ipc" "call" "launcher" "toggle" ];
          "Mod+V".action.spawn = [ "qs" "ipc" "call" "clipboard" "toggle" ];
          "Mod+P".action.spawn = [ "qs" "ipc" "call" "powermenu" "toggle" ];
          "Mod+L".action.spawn = [ "qs" "ipc" "call" "lockscreen" "toggle" ];
          "Mod+D".action.spawn = [ "qs" "ipc" "call" "dashboard" "toggle" ];
          "Mod+N".action.spawn = [ "qs" "ipc" "call" "notifCenter" "toggle" ];
          "Mod+C".action.spawn = [ "qs" "ipc" "call" "controlCenter" "toggle" ];
        };
      };
    })
  ]);
}
