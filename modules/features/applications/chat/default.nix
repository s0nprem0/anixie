{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.applications.chat;

  # nixpkgs is still on the 2026-09-03 date tag, while upstream has moved to
  # v1.15.x releases. Keep nixpkgs' build recipe and override just the release.
  equicord = pkgs.equicord.overrideAttrs (old: rec {
    version = "v1.15.12.0";

    src = pkgs.fetchFromGitHub {
      owner = "Equicord";
      repo = "Equicord";
      tag = version;
      hash = "sha256-i7VlyecgQvVHYqI0SuNdxLSLot5kcgBUsB/MKcKmxys=";
    };

    pnpmDeps = pkgs.fetchPnpmDeps {
      inherit (old) pname;
      inherit version src;
      pnpm = pkgs.pnpm_10;
      fetcherVersion = 3;
      hash = "sha256-Yh12UoWHzClDZoKPYlaNsr/+GQLS35iJ9enJa5tG+Nw=";
    };

    env = (old.env or { }) // {
      EQUICORD_HASH = version;
    };
  });
in
{
  options.anixie.applications.chat.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install Discord with the Equicord plugin set applied.";
  };

  config = lib.mkIf cfg.enable {
    # Equicord is a fork of Vencord distributed as a patcher payload, not as a
    # client. `pkgs.equicord` on its own installs only the payload — no binary,
    # no desktop entry — which is why it never showed up in the launcher. The
    # package that gives you a working app is Discord with that payload applied.
    home.packages = [
      (pkgs.discord.override {
        withEquicord = true;
        inherit equicord;
      })
    ];
  };
}
