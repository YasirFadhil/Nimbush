{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  packages = [
    (pkgs.python3.withPackages (ps: with ps; [
      pygobject3
    ]))
    pkgs.at-spi2-core
    pkgs.gobject-introspection
  ];

  shellHook = ''
    export GI_TYPELIB_PATH="${pkgs.at-spi2-core}/lib/girepository-1.0:$GI_TYPELIB_PATH"
  '';
}
