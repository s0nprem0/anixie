{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.applications.keepassxc;
in
{
  options.anixie.applications.keepassxc.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install KeePassXC as the password manager and TOTP generator.";
  };

  config = lib.mkIf cfg.enable {
    # KeePassXC reads a local KDBX vault and generates TOTP codes from the same
    # entry, so the second factor lives beside the password it protects. It has
    # no Aegis importer; moving an existing Aegis vault over needs a one-off
    # conversion (`atk`, or export the individual otpauth:// URIs).
    home.packages = [ pkgs.keepassxc ];
  };
}
