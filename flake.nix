{
  description = "YasirFadhil's Quickshell Wayland Desktop Environment Shell";

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
          power-profiles-daemon
          upower
          socat
          psmisc
          python3
          wlogout
        ];

        # Derivation packaging the Quickshell configuration & runner wrapper script
        quickshell-shell = pkgs.stdenv.mkDerivation {
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
              --prefix PATH : ${pkgs.lib.makeBinPath runtimeDependencies}
          '';

          meta = with pkgs.lib; {
            description = "Quickshell Wayland desktop environment configuration by YasirFadhil";
            license = licenses.mit;
            platforms = platforms.linux;
          };
        };
      in
      {
        packages = {
          default = quickshell-shell;
          quickshell-shell = quickshell-shell;
        };

        apps.default = {
          type = "app";
          program = "${quickshell-shell}/bin/quickshell-shell";
        };

        devShells.default = pkgs.mkShell {
          name = "quickshell-dev-shell";
          packages = [
            pkgs.quickshell
          ] ++ runtimeDependencies;

          shellHook = ''
            echo "Quickshell development shell ready."
            echo "Run 'qs -c .' to test your quickshell configuration locally."
          '';
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
      };
    };
}
