{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.wm.mixer;
in
{
  options.my.wm.mixer.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install pavucontrol, the PulseAudio volume control GUI.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.pavucontrol ];
  };
}
