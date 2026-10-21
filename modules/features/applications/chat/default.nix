{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.applications.chat;
in
{
  options.my.applications.chat.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install Equicord, a Discord client with the Vencord plugin set built in.";
  };

  config = lib.mkIf cfg.enable {
    # Equicord: a Discord client with the Vencord plugin set built in, so the
    # plugins are part of the client rather than a patch applied to someone else's
    # binary.
    home.packages = [ pkgs.equicord ];
  };
}
