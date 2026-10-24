{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.wm.mixer;

  mkScript = import ../../cli/scripts.nix { inherit pkgs; };

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

  outputSet = mkScript {
    name = "audio-output-set";
    file = ./output-set.sh;
    inherit bins;
  };

  outputSwitch = mkScript {
    name = "audio-output-switch";
    file = ./output-switch.sh;
    bins = bins // {
      "@OUTPUT_SET@" = outputSet.command;
    };
  };

  # The only public command. The two operations stay separate scripts, but the
  # panel, the bind and the menu all name this one.
  audioOutput = mkScript {
    name = "audio-output";
    file = ./audio-output.sh;
    bins = {
      "@OUTPUT_SET@" = outputSet.command;
      "@OUTPUT_SWITCH@" = outputSwitch.command;
    };
  };
in

{
  options.anixie.wm.mixer.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install pavucontrol and the audio-output command.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      pkgs.pavucontrol

      # The scripts need pactl to move a stream that is already playing, and
      # installing the client as well means `pactl` is there to reach for by hand
      # when a device is misbehaving.
      pkgs.pulseaudio
      pkgs.jq

      audioOutput.package
    ];
  };
}
