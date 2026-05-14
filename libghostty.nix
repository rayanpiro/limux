{ pkgs, ghostty-fork }:
let
  # Zig dep cache for the fork. Use a copy-farm instead of symlinks
  # to dodge https://codeberg.org/ziglang/zig/issues/32121 — the
  # same workaround upstream ghostty's libghostty-vt.nix applies.
  ghosttyDeps = pkgs.callPackage "${ghostty-fork}/build.zig.zon.nix" {
    name = "libghostty-cache";
    linkFarm = name: entries:
      pkgs.runCommand name { } ''
        mkdir -p $out
        ${pkgs.lib.concatMapStringsSep "\n" (e: ''
          cp -rL ${e.path} $out/${e.name}
        '') entries}
      '';
  };
in
pkgs.stdenv.mkDerivation {
  pname = "libghostty";
  version = "fork-81ab8ff";

  src = ghostty-fork;

  nativeBuildInputs = [
    pkgs.zig_0_15
    pkgs.pkg-config
    pkgs.git
    pkgs.pandoc
    pkgs.ncurses
    pkgs.gobject-introspection
    pkgs.blueprint-compiler
    pkgs.libxml2
    pkgs.gettext
    pkgs.wayland-scanner
    pkgs.wayland-protocols
    pkgs.wrapGAppsHook4
  ];

  buildInputs = [
    pkgs.libGL
    pkgs.bzip2
    pkgs.expat
    pkgs.fontconfig
    pkgs.freetype
    pkgs.harfbuzz
    pkgs.libpng
    pkgs.libxml2
    pkgs.oniguruma
    pkgs.simdutf
    pkgs.zlib
    pkgs.glslang
    pkgs.spirv-cross
    pkgs.libxkbcommon
    pkgs.glib
    pkgs.gobject-introspection
    pkgs.gsettings-desktop-schemas
    pkgs.gst_all_1.gst-plugins-base
    pkgs.gst_all_1.gst-plugins-good
    pkgs.gst_all_1.gstreamer
    pkgs.gtk4
    pkgs.libadwaita
    pkgs.libx11
    pkgs.libxcursor
    pkgs.libxi
    pkgs.libxrandr
    pkgs.gtk4-layer-shell
    pkgs.wayland
  ];

  GI_TYPELIB_PATH = pkgs.lib.makeSearchPath "lib/girepository-1.0"
    (map (pkgs.lib.getOutput "lib") [
      pkgs.cairo
      pkgs.gdk-pixbuf
      pkgs.glib
      pkgs.gobject-introspection
      pkgs.graphene
      pkgs.gtk4
      pkgs.gtk4-layer-shell
      pkgs.harfbuzz
      pkgs.libadwaita
      pkgs.pango
    ]);

  buildPhase = ''
    runHook preBuild
    export ZIG_GLOBAL_CACHE_DIR=$(mktemp -d)
    zig build \
      --system ${ghosttyDeps} \
      -Dapp-runtime=none \
      -Dcpu=baseline \
      -Doptimize=ReleaseFast \
      --prefix $out \
      --verbose
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    # Expose glad sources alongside the lib so limux-ghostty-sys's
    # build.rs (LIBGHOSTTY_GLAD_DIR) can find them.
    mkdir -p $out/share/libghostty
    cp -r vendor $out/share/libghostty/vendor
    runHook postInstall
  '';
}
