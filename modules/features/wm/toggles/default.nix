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

  # Whether sudo asks for a password, which it does not on this machine: the
  # wheel group carries NOPASSWD, and `son` is in wheel. Asked of sudo itself
  # rather than read out of /etc/sudoers, which is root-only and unreadable by the
  # user the indicator is trying to tell.
  passwordlessSudo = pkgs.writeShellScriptBin "passwordless-sudo" (
    builtins.replaceStrings
      [ "@SUDO@" "@TERMINAL@" ]
      [
        "/run/wrappers/bin/sudo"
        "${pkgs.kitty}/bin/kitty"
      ]
      (builtins.readFile ./passwordless-sudo.sh)
  );

  # Who is logged in, and from somewhere else or not. logind rather than any one
  # remote tool's own idea of who is connected — no remote desktop is installed
  # here, and the bar should still say something if SSH ever is.
  remoteSession = pkgs.writeShellScriptBin "remote-session" (
    builtins.replaceStrings [ "@LOGINCTL@" ] [ "${pkgs.systemd}/bin/loginctl" ] (
      builtins.readFile ./remote-session.sh
    )
  );
in
{
  home.packages = [
    toggle
    passwordlessSudo
    remoteSession
  ];

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
