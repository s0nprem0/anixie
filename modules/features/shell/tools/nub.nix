# Nub: an all-in-one Node.js toolkit (https://nubjs.com). Ships as a prebuilt
# Rust binary; there is no nixpkgs package yet, so fetch the release tarball.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

stdenv.mkDerivation {
  pname = "nub";
  version = "0.9.7";

  src = fetchurl {
    url = "https://github.com/nubjs/nub/releases/download/v0.9.7/nub-linux-x64.tar.gz";
    sha256 = "ee07bc58ad904cee969916e1f1cdd849129e699c87757a3173dbabb6b3f512ee";
  };

  nativeBuildInputs = [ autoPatchelfHook ];

  buildInputs = [ stdenv.cc.cc.lib ];

  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    install -m 0755 bin/nub bin/nub-launcher-linux-x64 $out/bin/
    ln -s nub $out/bin/nubr
    ln -s nub $out/bin/nubx
    runHook postInstall
  '';

  meta = {
    description = "All-in-one Node.js toolkit: TypeScript runner, script/package runner, package manager, Node version manager";
    homepage = "https://nubjs.com";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "nub";
  };
}
