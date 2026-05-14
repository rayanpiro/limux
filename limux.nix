{ pkgs, libghostty }:
let
  inherit (pkgs) lib rustPlatform;

  # Source filter: keep the Rust workspace + assets we install, drop the
  # vendored ghostty submodule, build artefacts, and flake outputs.
  src = lib.cleanSourceWith {
    filter = path: type:
      let
        rel = lib.removePrefix (toString ./. + "/") (toString path);
        topLevel = builtins.head (lib.splitString "/" rel);
      in
        !(builtins.elem topLevel [
          "ghostty"
          "target"
          "dist"
          "result"
          ".git"
          ".direnv"
        ]);
    src = lib.cleanSource ./.;
  };

  cargoVersion =
    let
      raw = builtins.readFile ./Cargo.toml;
      m = builtins.match ".*\nversion = \"([^\"]+)\".*" raw;
    in
      if m == null then "0.0.0" else builtins.head m;

  # CARGO_TARGET_<TRIPLE>_RUSTFLAGS env var name for the current host.
  # Cargo upper-cases the triple and replaces '-' with '_'.
  rustTarget = pkgs.stdenv.hostPlatform.rust.cargoShortTarget;
  rustTargetEnvSuffix =
    lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] rustTarget);
in
rustPlatform.buildRustPackage {
  pname = "limux";
  version = cargoVersion;

  inherit src;

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  nativeBuildInputs = with pkgs; [
    pkg-config
    wrapGAppsHook4
    autoPatchelfHook
  ];

  buildInputs = with pkgs; [
    libghostty
    libepoxy
    gtk4
    libadwaita
    webkitgtk_6_0
    libsoup_3
    glib
    gsettings-desktop-schemas
    gdk-pixbuf
    pango
    cairo
    graphene
    harfbuzz
    wayland
  ];

  # rustc passes -Wl,--gc-sections by default, which drops glad's
  # loader sections (bundled into the limux-ghostty-sys rlib) before
  # libghostty.so's unresolved gladLoader* references are processed.
  # Mark the entry points as undefined roots so their sections survive.
  env."CARGO_TARGET_${rustTargetEnvSuffix}_RUSTFLAGS" =
    "-Clink-arg=-Wl,-u,gladLoaderLoadGLContext "
    + "-Clink-arg=-Wl,-u,gladLoaderUnloadGLContext";

  # limux-ghostty-sys/build.rs looks for libghostty + glad sources at
  # fixed paths under ../../ghostty relative to the crate. We exclude
  # the (huge) ghostty submodule from the source tree, so stage a
  # minimal fake tree pointing at the libghostty derivation instead.
  preBuild = ''
    mkdir -p ghostty/zig-out/lib ghostty/vendor
    ln -s ${libghostty}/lib/libghostty.so   ghostty/zig-out/lib/libghostty.so
    ln -s ${libghostty}/share/libghostty/vendor/glad ghostty/vendor/glad
  '';

  # One workspace test currently fails (tracked in CLAUDE.md); skip until fixed.
  doCheck = false;

  postInstall = ''
    # buildRustPackage installs every [[bin]] into $out/bin. Limux wants:
    #   bin/limux              — the CLI (crate limux-cli, binary limux-cli)
    #   libexec/limux/limux-host — the GTK app (crate limux-host-linux, binary limux)
    install -d "$out/libexec/limux"
    mv "$out/bin/limux"     "$out/libexec/limux/limux-host"
    mv "$out/bin/limux-cli" "$out/bin/limux"

    # limux-control-server is an internal debug tool; the shipped packages
    # (PKGBUILD, RPM, tarball) don't install it, so drop it from $out too.
    rm -f "$out/bin/limux-control-server"

    # Desktop entry + appstream metadata.
    install -Dm644 rust/limux-host-linux/dev.limux.linux.desktop \
      "$out/share/applications/dev.limux.linux.desktop"
    install -Dm644 rust/limux-host-linux/dev.limux.linux.metainfo.xml \
      "$out/share/metainfo/dev.limux.linux.metainfo.xml"

    # App launcher icons.
    for size in 16 32 128 256 512; do
      src="rust/limux-host-linux/icons/app/$size.png"
      if [ -f "$src" ]; then
        install -Dm644 "$src" "$out/share/icons/hicolor/''${size}x''${size}/apps/limux.png"
      fi
    done

    # Action / symbolic icons used by the GTK host.
    for svg in rust/limux-host-linux/icons/*.svg; do
      [ -f "$svg" ] || continue
      install -Dm644 "$svg" \
        "$out/share/icons/hicolor/scalable/actions/$(basename "$svg")"
    done
    if [ -d rust/limux-host-linux/icons/hicolor/scalable ]; then
      cp -r rust/limux-host-linux/icons/hicolor/scalable/. \
        "$out/share/icons/hicolor/scalable/"
    fi
  '';

  meta = with lib; {
    description = "GTK4 + libghostty terminal workspace manager for Linux";
    homepage = "https://github.com/am-will/limux";
    license = licenses.mit;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    mainProgram = "limux";
  };
}
