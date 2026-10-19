{ pkgs, ... }:

let
  # The modes the bar's indicators show, as one command. The keys call it, the
  # indicator polls it, and the picker lists it — one answer to "is it on".
  toggle = pkgs.writeShellScriptBin "toggle" (
    builtins.replaceStrings
      [
        "@HYPRCTL@"
        "@QUICKSHELL@"
      ]
      [
        "${pkgs.hyprland}/bin/hyprctl"
        "${pkgs.quickshell}/bin/quickshell"
      ]
      (builtins.readFile ./toggle.sh)
  );
in
{
  home.packages = [ toggle ];

  # The inhibitor behind `toggle stayawake`. A unit rather than a backgrounded
  # process so it survives the shell that started it and stops exactly when it
  # is told to: a logind inhibitor only exists while the process holding it lives.
  #
  # `idle` covers the screen blanking and locking that hypridle does; this covers
  # the sleep class on top of that — the lid, and the desktop's own suspend
  # policy — which nothing else here turns off.
  systemd.user.services.anixie-stayawake = {
    Unit.Description = "Hold off blanking, sleeping and suspending";
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.systemd}/bin/systemd-inhibit --what=idle:sleep --mode=block sleep infinity";
      # Nothing to restore on the way out; the inhibitor is the whole job.
      RemainAfterExit = false;
    };
  };
}
