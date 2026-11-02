# The builder follows github:olafkfreund/nix-craftapps (MIT), which packaged
# the same release tarballs before this repository did it itself.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  alsa-lib,
  dbus,
  libGL,
  vulkan-loader,
  wayland,
  libxkbcommon,
  libx11,
  libxcb,
  libxcursor,
  libxi,
  libxrandr,
  name,
  version,
  hash,
  title,
  description,
}:

stdenv.mkDerivation {
  pname = name;
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/${name}/releases/download/v${version}/${name}-${version}-linux-x86_64.tar.gz";
    inherit hash;
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    stdenv.cc.cc.lib
    alsa-lib
  ];

  # dlopen()ed at runtime, so autoPatchelf cannot see them in NEEDED.
  runtimeDependencies = [
    dbus.lib
    libGL
    vulkan-loader
    wayland
    libxkbcommon
    libx11
    libxcb
    libxcursor
    libxi
    libxrandr
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r bin share $out/
    runHook postInstall
  '';

  # Some apps pre-check their graphics libraries with `ldconfig -p`, which
  # cannot see the RUNPATH, and refuse to start; the libraries load fine.
  postFixup = ''
    wrapProgram $out/bin/${name} --set-default ${lib.toUpper name}_SKIP_LIB_CHECK 1
  '';

  meta = {
    description = "${title}: ${description}";
    homepage = "https://github.com/storytold/${name}";
    changelog = "https://github.com/storytold/${name}/releases/tag/v${version}";
    license = with lib.licenses; [
      mit
      asl20
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = name;
  };
}
