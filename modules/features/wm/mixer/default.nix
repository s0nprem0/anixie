{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.wm.mixer;

  # Every external binary a script here calls, in one table, so a reader can see
  # the whole dependency set at a glance. They are substituted rather than left
  # to $PATH because these run from a Hyprland bind and from the shell, neither
  # of which necessarily carries the user's profile path.
  bins = {
    "@PACTL@" = "${pkgs.pulseaudio}/bin/pactl";
    "@JQ@" = "${pkgs.jq}/bin/jq";
    "@WPCTL@" = "${pkgs.wireplumber}/bin/wpctl";
    "@NOTIFY_SEND@" = config.anixie.wm.notify.bin;
  };

  render =
    name: path: extra:
    let
      all = bins // extra;
    in
    pkgs.writeShellScriptBin name (
      builtins.replaceStrings (builtins.attrNames all) (builtins.attrValues all) (builtins.readFile path)
    );

  outputSet = render "audio-output-set" ./output-set.sh { };

  outputSwitch = render "audio-output-switch" ./output-switch.sh {
    "@OUTPUT_SET@" = "${outputSet}/bin/audio-output-set";
  };
in

{
  options.anixie.wm.mixer.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install pavucontrol and the audio switching commands.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      pkgs.pavucontrol

      # The scripts need pactl to move a stream that is already playing, and
      # installing the client as well means `pactl` is there to reach for by hand
      # when a device is misbehaving.
      pkgs.pulseaudio
      pkgs.jq

      outputSet
      outputSwitch
    ];
  };
}
