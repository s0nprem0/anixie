{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.applications.ente-auth;
in
{
  options.anixie.applications.ente-auth.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install Ente Auth as the TOTP authenticator.";
  };

  config = lib.mkIf cfg.enable {
    # Ente Auth holds TOTP codes separately from the KeePassXC vault, so a
    # compromised password store does not also hand over the second factor. It
    # imports Aegis exports directly, which is how the existing phone vault
    # moves over. Sync is optional and end-to-end encrypted; it can also run
    # entirely offline.
    home.packages = [ pkgs.ente-auth ];
  };
}
