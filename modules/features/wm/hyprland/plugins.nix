{ inputs, pkgs, ... }:

let
  # Every plugin here is built from source against the Hyprland package this
  # flake installs. They reach into compositor internals, so they are pinned in
  # flake.nix to the same 0.56 series rather than tracking each project's main
  # branch.
  #
  # The install names are the ones Hyprland's `plugin =` loader looks for. Some
  # projects produce only their bare name, so each derivation installs the
  # aliases it has been seen to be loaded under instead of making the config
  # depend on which one upstream chose.
  scrolloverview = pkgs.stdenv.mkDerivation {
    pname = "hyprland-scroll-overview";
    version = "0.1";
    src = inputs.hyprland-scroll-overview;

    dontUseCmakeConfigure = true;

    inherit (pkgs.hyprland) buildInputs;
    nativeBuildInputs = pkgs.hyprland.nativeBuildInputs ++ [
      pkgs.hyprland
      pkgs.gcc14
      pkgs.pkg-config
      pkgs.pixman
      pkgs.libdrm
      pkgs.lua5_4
    ];

    enableParallelBuilding = true;

    buildPhase = ''
      runHook preBuild
      make all
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib"
      cp scrolloverview.so "$out/lib/libscrolloverview.so"
      cp scrolloverview.so "$out/lib/scrolloverview.so"
      cp scrolloverview.so "$out/lib/libhyprland-scroll-overview.so"
      runHook postInstall
    '';
  };

  hyprglass = pkgs.stdenv.mkDerivation {
    pname = "hyprglass";
    version = "0.1";
    src = inputs.hyprglass;

    # Modern toolchains refuse to dlopen a shared object without an explicit
    # non-executable stack note. The Makefile does not carry one, and the
    # assembly blob has no section of its own, so both are supplied here.
    postPatch = ''
      sed -i 's/LDFLAGS = -shared/LDFLAGS = -shared -Wl,-z,noexecstack/' Makefile
      sed -i 's/\$(CC) -shared -fPIC/\$(CC) -shared -fPIC -Wl,-z,noexecstack/' Makefile
      echo '.section .note.GNU-stack,"",@progbits' >> src/ItemHelperBlob.S
    '';

    dontUseCmakeConfigure = true;

    inherit (pkgs.hyprland) buildInputs;
    nativeBuildInputs = pkgs.hyprland.nativeBuildInputs ++ [
      pkgs.hyprland
      pkgs.gcc14
      pkgs.pkg-config
      pkgs.pixman
      pkgs.libdrm
    ];

    enableParallelBuilding = true;

    buildPhase = ''
      runHook preBuild
      make all
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib"
      cp hyprglass.so "$out/lib/libhyprglass.so"
      cp hyprglass.so "$out/lib/hyprglass.so"
      runHook postInstall
    '';
  };

  dynamicCursors = pkgs.stdenv.mkDerivation {
    pname = "hypr-dynamic-cursors";
    version = "0.1";
    src = inputs.hypr-dynamic-cursors;

    dontUseCmakeConfigure = true;

    inherit (pkgs.hyprland) buildInputs;
    nativeBuildInputs = pkgs.hyprland.nativeBuildInputs ++ [
      pkgs.hyprland
      pkgs.gcc14
      pkgs.pkg-config
      pkgs.pixman
      pkgs.libdrm
      pkgs.hyprcursor
      pkgs.hyprgraphics
    ];

    enableParallelBuilding = true;

    buildPhase = ''
      runHook preBuild
      make all
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib"
      cp out/dynamic-cursors.so "$out/lib/libdynamic-cursors.so"
      cp out/dynamic-cursors.so "$out/lib/dynamic-cursors.so"
      cp out/dynamic-cursors.so "$out/lib/libhypr-dynamic-cursors.so"
      runHook postInstall
    '';
  };

  edgehover = pkgs.stdenv.mkDerivation {
    pname = "hypr-edgehover";
    version = "0.1";
    src = inputs.hypr-edgehover;

    nativeBuildInputs = [
      pkgs.cmake
      pkgs.pkg-config
      pkgs.hyprland
      pkgs.gcc14
    ];
    buildInputs = pkgs.hyprland.buildInputs;

    enableParallelBuilding = true;
  };

  hymission = pkgs.stdenv.mkDerivation {
    pname = "hymission";
    version = "0.7.1";
    src = inputs.hymission;

    patches = [ ./patches/hymission-effective-alpha.patch ];

    nativeBuildInputs = [
      pkgs.cmake
      pkgs.pkg-config
      pkgs.hyprland
      pkgs.gcc14
    ];
    buildInputs = pkgs.hyprland.buildInputs ++ [
      pkgs.lua5_4
      pkgs.glib
      pkgs.gtk4
      pkgs.libadwaita
      pkgs.gtk4-layer-shell
    ];

    postInstall = ''
      ln -s "$out/libexec/hymission-search-input" "$out/lib/hymission-search-input"
      mkdir -p "$out/bin"
      ln -s "$out/libexec/hymission-search-input" "$out/bin/hymission-search-input"
    '';

    enableParallelBuilding = true;
  };

  layoutmode = pkgs.stdenv.mkDerivation {
    pname = "hyprland-layoutmode";
    version = "0.2.1";
    src = ./layoutmode;

    nativeBuildInputs = [
      pkgs.cmake
      pkgs.pkg-config
      pkgs.hyprland
    ];
    buildInputs = pkgs.hyprland.buildInputs;

    postInstall = ''
      ln -s "$out/lib/libhyprland-layoutmode.so" "$out/lib/liblayoutmode.so"
    '';

    enableParallelBuilding = true;
  };

  hyprbars = pkgs.stdenv.mkDerivation {
    pname = "hyprbars";
    version = "0.56.2-pin";
    src = "${inputs.hyprland-plugins}/hyprbars";

    patches = [ ./patches/hyprbars-only-floating.patch ];

    dontUseCmakeConfigure = true;

    inherit (pkgs.hyprland) buildInputs;
    nativeBuildInputs = pkgs.hyprland.nativeBuildInputs ++ [
      pkgs.hyprland
      pkgs.gcc14
      pkgs.pkg-config
      pkgs.pixman
      pkgs.libdrm
      pkgs.cairo
      pkgs.pango
      pkgs.lua5_4
    ];

    enableParallelBuilding = true;

    buildPhase = ''
      runHook preBuild
      make all
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib"
      cp hyprbars.so "$out/lib/libhyprbars.so"
      cp hyprbars.so "$out/lib/hyprbars.so"
      runHook postInstall
    '';
  };

  # The glass config is read at config load, so the toggle writes the state
  # file and asks for a reload. It is a separate command rather than an inline
  # shell expression in a bind so the quoting lives in one place.
  glassToggle = pkgs.writeShellScriptBin "glass-toggle" ''
    set -eu
    state="''${XDG_STATE_HOME:-$HOME/.local/state}/anixie"
    mkdir -p "$state"

    current=true
    if [ -r "$state/glass" ]; then
      current=$(cat "$state/glass")
    fi

    if [ "$current" = true ]; then
      printf 'false\n' > "$state/glass"
    else
      printf 'true\n' > "$state/glass"
    fi

    ${pkgs.hyprland}/bin/hyprctl reload >/dev/null
  '';
in
{
  home.packages = [ glassToggle ];

  # Load order matters: hyprglass hooks compositor rendering, and the overview
  # plugins are started after it so their surfaces are composited by the glass
  # path rather than drawn over it.
  wayland.windowManager.hyprland.plugins = [
    scrolloverview
    hyprglass
    dynamicCursors
    edgehover
    hymission
    hyprbars
    layoutmode
  ];
}
