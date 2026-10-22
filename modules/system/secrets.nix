{
  config,
  lib,
  user,
  ...
}:

let
  cfg = config.my.secrets;

  # The file is only a default when it exists. A repository without encrypted
  # secrets should evaluate without one, and `builtins.pathExists` is the
  # cheapest way to say "use it if it is there".
  defaultFile =
    if builtins.pathExists ../../secrets/secrets.yaml then ../../secrets/secrets.yaml else null;
in
{
  options.my.secrets = {
    enable = lib.mkEnableOption "sops-nix managed secrets";

    defaultSopsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = defaultFile;
      description = ''
        The encrypted secrets file shared by every secret below. Create it with
        `sops secrets/secrets.yaml`; see the README's secrets section for the
        age key setup.
      '';
    };

    ageKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.users.users.${user}.home}/.config/sops/age/keys.txt";
      description = "The age private key sops decrypts with, outside the store.";
    };

    secrets = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            path = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Where the decrypted secret is written; empty means sops-nix's default.";
            };
            owner = lib.mkOption {
              type = lib.types.str;
              default = user;
            };
            group = lib.mkOption {
              type = lib.types.str;
              default = "users";
            };
            mode = lib.mkOption {
              type = lib.types.str;
              default = "0400";
            };
          };
        }
      );
      default = { };
      description = "Secrets to materialise at activation, keyed by their name in the encrypted file.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.defaultSopsFile != null;
        message = "my.secrets.enable is set but secrets/secrets.yaml does not exist";
      }
    ];

    sops = {
      inherit (cfg) defaultSopsFile;
      age.keyFile = cfg.ageKeyFile;
      secrets = lib.mapAttrs (
        _: secret:
        {
          inherit (secret) owner group mode;
        }
        // lib.optionalAttrs (secret.path != "") { inherit (secret) path; }
      ) cfg.secrets;
    };
  };
}
