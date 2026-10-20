{
  pkgs,
  ...
}:

let
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
    "@NOTIFY_SEND@" = "${pkgs.libnotify}/bin/notify-send";
    "@MPV@" = "${pkgs.mpv}/bin/mpv";
    "@SETSID@" = "${pkgs.util-linux}/bin/setsid";
    "@TESSERACT@" = "${pkgs.tesseract}/bin/tesseract";
    "@ZBAR@" = "${pkgs.zbar}/bin/zbarimg";
    "@MAGICK@" = "${pkgs.imagemagick}/bin/magick";
    "@QUICKSHELL@" = "${pkgs.quickshell}/bin/quickshell";

    # The shared help and error helpers, sourced by the scripts that print a
    # header manual. Not a binary — the path is the file itself.
    "@ANIXIE_LIB@" = "${../../cli/lib.sh}";
  };

  # A script with its placeholders filled in. `extra` carries the placeholders
  # that point at another of these scripts, so a script's name is written once and
  # every reference to it resolves to the same store path.
  #
  # attrNames and attrValues are both ordered by name, so the patterns and their
  # replacements line up.
  render =
    name: path: extra:
    let
      all = bins // extra;
    in
    pkgs.writeShellScriptBin name (
      builtins.replaceStrings (builtins.attrNames all) (builtins.attrValues all) (builtins.readFile path)
    );

  shotPick = render "shot-pick" ./pick.sh { };

  shot = render "shot" ./shot.sh {
    "@SHOT_PICK@" = "${shotPick}/bin/shot-pick";
  };

  # Check or signal the recorder, by pid. Split out from `record` because the bar
  # indicator asks it whether a recording is running on a poll, and that question
  # should not have to load the whole recording script to be answered.
  recordProcess = render "record-process" ./record-process.sh { };

  webcamOverlay = render "webcam-overlay" ./webcam-overlay.sh { };

  record = render "record" ./record.sh {
    "@SHOT_PICK@" = "${shotPick}/bin/shot-pick";
    "@RECORD_PROCESS@" = "${recordProcess}/bin/record-process";
    "@WEBCAM_OVERLAY@" = "${webcamOverlay}/bin/webcam-overlay";
  };

  # Read something off the screen that is not a picture: the text in a region, or
  # the value behind a QR code.
  captureText = render "capture-text" ./text.sh {
    "@SHOT_PICK@" = "${shotPick}/bin/shot-pick";
  };

  captureQr = render "capture-qr" ./qr.sh {
    "@SHOT_PICK@" = "${shotPick}/bin/shot-pick";
  };

  transcode = render "transcode" ./transcode.sh { };
in

{
  home.packages = [
    # The picker, and the screenshot command that uses it.
    shotPick
    shot

    # Recording, and the webcam overlay a recording can carry.
    recordProcess
    webcamOverlay
    record

    # Reading what is on the screen rather than picturing it, and shrinking what
    # comes off it before sending it somewhere.
    captureText
    captureQr
    transcode
    # Annotation is satty's job. It is written for Wayland and opens in crop mode,
    # so the annotate bind goes straight to cropping rather than making you pick the
    # crop tool first.
    #
    # swappy was here before and drew nothing at all: it is an X11-era GTK
    # application, and under XWayland its window never appeared — the client was in
    # hyprctl's list with nothing on screen. Worth knowing if an annotation tool
    # ever looks like it launched and then vanished.
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
  ];
}
