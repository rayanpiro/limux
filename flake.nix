{
  description = "Limux dev environment";

  inputs = {
    # nixos-25.11 ships rustc 1.91 but the gtk4-rs versions limux uses
    # require 1.92+, so we track unstable (which is still glibc-compatible
    # with libghostty built from the same channel).
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # Limux uses am-will's fork of ghostty (matches the submodule pin in
    # .gitmodules + the commit recorded in this repo's tree). Upstream
    # ghostty no longer ships a unified libghostty.so — it split into
    # libghostty-vt.so + ghostty-internal.so, which limux-ghostty-sys
    # can't link against.
    ghostty-fork = {
      url = "github:am-will/ghostty/81ab8ffa90185221782baf785e85387321e16f8d";
      flake = false;
    };
  };

  outputs =
    { self
    , nixpkgs
    , flake-utils
    , ghostty-fork
    ,
    }:
    flake-utils.lib.eachSystem
      [
        "x86_64-linux"
        "aarch64-linux"
      ]
      (system:
        let
          pkgs = import nixpkgs { inherit system; };

          libghostty = import ./libghostty.nix { inherit pkgs ghostty-fork; };
          limux = import ./limux.nix { inherit pkgs libghostty; };
        in
        {
          packages = {
            inherit libghostty limux;
            default = limux;
          };

          devShells.default = pkgs.mkShell {
            nativeBuildInputs = [
              pkgs.gtk4
              pkgs.libadwaita
              pkgs.libsoup_3
              pkgs.webkitgtk_6_0
              pkgs.libepoxy
              pkgs.pkg-config
              pkgs.glib
              pkgs.gsettings-desktop-schemas
              libghostty
            ];

            LIBGHOSTTY_DIR = "${libghostty}/lib";
            LIBGHOSTTY_GLAD_DIR = "${libghostty}/share/libghostty/vendor/glad";

            # GTK4's FileDialog (and other widgets) read GSettings at runtime —
            # without these on XDG_DATA_DIRS, opening Browse crashes with
            # "No GSettings schemas are installed on the system".
            shellHook = ''
              export XDG_DATA_DIRS="${pkgs.glib}/share/gsettings-schemas/${pkgs.glib.name}:${pkgs.gtk4}/share/gsettings-schemas/${pkgs.gtk4.name}:${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}:''${XDG_DATA_DIRS:-}"
            '';
          };
        });
}
