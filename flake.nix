{
  description = "Nimbush - Quickshell Wayland Desktop Environment by YasirFadhil";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        runtimeDependencies = with pkgs; [
          networkmanager
          bluez
          bluez-tools
          pipewire
          pulseaudio
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
        ];

        # Derivation builder for Quickshell configuration with optional extra packages (Hyprland / Niri)
        mkQuickshellShell = { extraPkgs ? [ ] }: pkgs.stdenv.mkDerivation {
          pname = "quickshell-shell";
          version = "1.0.0";

          src = ./.;

          nativeBuildInputs = [ pkgs.makeWrapper ];
          buildInputs = [ ];

          installPhase = ''
            mkdir -p $out/share/quickshell $out/bin

            # Copy all shell code and assets
            cp -r * $out/share/quickshell/

            # Create runner executable script
            makeWrapper ${pkgs.quickshell}/bin/qs $out/bin/quickshell-shell \
              --add-flags "-c $out/share/quickshell" \
              --prefix PATH : ${pkgs.lib.makeBinPath (runtimeDependencies ++ extraPkgs)}
          '';

          meta = with pkgs.lib; {
            description = "Nimbush - Quickshell Wayland desktop environment configuration by YasirFadhil";
            license = licenses.mit;
            platforms = platforms.linux;
          };
        };

        quickshell-shell = mkQuickshellShell { };
        quickshell-shell-hyprland = mkQuickshellShell { extraPkgs = [ pkgs.hyprland ]; };
        quickshell-shell-niri = mkQuickshellShell { extraPkgs = [ pkgs.niri ]; };
      in
      {
        packages = {
          default = quickshell-shell;
          quickshell-shell = quickshell-shell;
          quickshell-shell-hyprland = quickshell-shell-hyprland;
          quickshell-shell-niri = quickshell-shell-niri;
        };

        apps = {
          default = {
            type = "app";
            program = "${quickshell-shell}/bin/quickshell-shell";
          };
          hyprland = {
            type = "app";
            program = "${quickshell-shell-hyprland}/bin/quickshell-shell";
          };
          niri = {
            type = "app";
            program = "${quickshell-shell-niri}/bin/quickshell-shell";
          };
        };

        devShells = {
          default = pkgs.mkShell {
            name = "quickshell-dev-shell";
            packages = [
              pkgs.quickshell
            ] ++ runtimeDependencies;

            shellHook = ''
              echo "Quickshell development shell ready."
              echo "Run 'qs -c .' to test your quickshell configuration locally."
            '';
          };

          hyprland = pkgs.mkShell {
            name = "quickshell-hyprland-dev-shell";
            packages = [
              pkgs.quickshell
              pkgs.hyprland
            ] ++ runtimeDependencies;

            shellHook = ''
              echo "Quickshell development shell (with Hyprland) ready."
              echo "Run 'qs -c .' to test your quickshell configuration locally."
            '';
          };

          niri = pkgs.mkShell {
            name = "quickshell-niri-dev-shell";
            packages = [
              pkgs.quickshell
              pkgs.niri
            ] ++ runtimeDependencies;

            shellHook = ''
              echo "Quickshell development shell (with Niri) ready."
              echo "Run 'qs -c .' to test your quickshell configuration locally."
            '';
          };
        };
      }
    ) // {
      # Home Manager Module output
      homeManagerModules = {
        default = import ./nix/home-manager-module.nix { inherit self; };
        quickshell-shell = import ./nix/home-manager-module.nix { inherit self; };
      };

      # Overlay output for NixOS / nixpkgs users
      overlays.default = final: prev: {
        quickshell-shell = self.packages.${prev.system}.default;
        quickshell-shell-hyprland = self.packages.${prev.system}.quickshell-shell-hyprland;
        quickshell-shell-niri = self.packages.${prev.system}.quickshell-shell-niri;
      };
    };
}
