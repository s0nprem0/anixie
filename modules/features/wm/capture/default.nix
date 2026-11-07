{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.wm.capture;
  daemonEnabled = config.anixie.daemon.enable or false;

  mkScript = import ../../cli/scripts.nix { inherit pkgs; };

  # Every external binary the capture scripts call, in one table. They are
  # substituted in rather than left to $PATH because these run from a Hyprland
  # bind, which does not necessarily carry the user's profile path.
  #
  # ffmpeg and ffprobe are named separately even though they come from the same
  # package, because the scripts use the two names separately and a reader looking
  # for where ffprobe is wired up should find it.
  bins = {
    "@HYPERPICKER@" = "${pkgs.hyprpicker}/bin/hyprpicker";
    "@HYPRCTL@" = "${pkgs.hyprland}/bin/hyprctl";
    "@JQ@" = "${pkgs.jq}/bin/jq";
    "@GRIM@" = "${pkgs.grim}/bin/grim";
    "@WL_COPY@" = "${pkgs.wl-clipboard}/bin/wl-copy";
    "@SATTY@" = "${pkgs.satty}/bin/satty";
    "@GSR@" = "${pkgs.gpu-screen-recorder}/bin/gpu-screen-recorder";
    "@FFMPEG@" = "${pkgs.ffmpeg}/bin/ffmpeg";
    "@FFPROBE@" = "${pkgs.ffmpeg}/bin/ffprobe";
    "@NOTIFY_SEND@" = config.anixie.wm.notify.bin;
    "@NOTIFY_SEND_RAW@" = "${pkgs.libnotify}/bin/notify-send";
    "@MPV@" = "${pkgs.mpv}/bin/mpv";
    "@SETSID@" = "${pkgs.util-linux}/bin/setsid";
    "@TESSERACT@" = "${pkgs.tesseract}/bin/tesseract";
    "@ZBAR@" = "${pkgs.zbar}/bin/zbarimg";
    "@MAGICK@" = "${pkgs.imagemagick}/bin/magick";
    "@QUICKSHELL@" = "${pkgs.quickshell}/bin/quickshell";
    "@WTYPE@" = "${pkgs.wtype}/bin/wtype";

    # The shared help and error helpers, sourced by the scripts that print a
    # header manual. Not a binary — the path is the file itself.
    "@ANIXIE_LIB@" = "${../../cli/lib.sh}";
  };

  shotPick = mkScript {
    name = if daemonEnabled then "shot-pick-legacy" else "shot-pick";
    file = ./pick.sh;
    inherit bins;
  };

  webcamOverlay = mkScript {
    name = if daemonEnabled then "webcam-overlay-legacy" else "webcam-overlay";
    file = ./webcam-overlay.sh;
    inherit bins;
  };

  # Read something off the screen that is not a picture: the text in a region, or
  # the value behind a QR code.
  captureText = mkScript {
    name = if daemonEnabled then "capture-text-legacy" else "capture-text";
    file = ./text.sh;
    bins = bins // {
      "@SHOT_PICK@" = shotPick.command;
    };
  };

  captureQr = mkScript {
    name = if daemonEnabled then "capture-qr-legacy" else "capture-qr";
    file = ./qr.sh;
    bins = bins // {
      "@SHOT_PICK@" = shotPick.command;
    };
  };

  captureShare = mkScript {
    name = if daemonEnabled then "capture-share-legacy" else "capture-share";
    file = ./share.sh;
    inherit bins;
  };
in

{
  options.anixie.wm.capture.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install the screenshot, recording, OCR and QR capture commands.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      # The picker the capture commands share.
      shotPick.package

      # The webcam overlay a recording can carry.
      webcamOverlay.package

      # Reading what is on the screen rather than picturing it, and shrinking what
      # comes off it before sending it somewhere. capture-text and capture-qr are
      # ported to alexie, so their bash versions are skipped when the daemon is on.
    ]
    ++ lib.optionals (!daemonEnabled) [
      captureText.package
      captureQr.package
    ]
    ++ [
      captureShare.package

      # Annotation is satty's job. It is written for Wayland and opens in crop mode,
      # so the annotate bind goes straight to cropping rather than making you pick the
      # crop tool first.
      pkgs.hyprpicker
      pkgs.slurp
      pkgs.grim
      pkgs.satty

      # gpu-screen-recorder encodes on the GPU and falls back to the CPU. ffmpeg
      # does the tidy-up pass when a recording stops: trimming the first frame and
      # normalizing the audio.
      pkgs.gpu-screen-recorder
      pkgs.ffmpeg

      # The readers and converters the capture menu reaches: tesseract for the text
      # in a region, zbar for a QR code, imagemagick for pictures on the way to jpg
      # or png. Installed as well as substituted, so they can be run by hand while
      # working out why one of them read something wrong.
      pkgs.tesseract
      pkgs.zbar
      pkgs.imagemagick
      # Page Down between scrolling-capture frames. wtype is also the emoji
      # picker's typer, but naming it here keeps this module's dependency set
      # complete on its own.
      pkgs.wtype
    ];
  };
}
