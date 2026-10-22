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
      })
    ];
  };
}
