{
  # hyprlock stays installed as the fallback for a session lock the shell cannot
  # acquire; it is no longer the lock on the lock key.
  programs.hyprlock.enable = true;

  # hypridle is kept only as the pre-suspend guard now. Its idle, screensaver and
  # lock listeners are gone: those live in the shell (see
  # features/wm/quickshell/Ui/IdleHost.qml and LockHost.qml).
  services.hypridle.enable = true;

  # The daemon behind pam_fprintd. Enabling it also makes the fingerprint module
  # available to PAM services; the shell's password service opts out below, so
  # the two lock flows stay separate.
  services.fprintd.enable = true;

  # Password authentication for the shell's lock surface. unixAuth is the
  # default; fprintAuth is turned off because the lock has a separate fingerprint
  # flow and should not hold the password prompt behind a reader.
  security.pam.services.quickshell-lock = {
    fprintAuth = false;
  };

  # Fingerprint only. The lock starts this after the compositor reports every
  # screen covered, and falls back to the password service when it fails.
  security.pam.services.quickshell-lock-fingerprint = {
    unixAuth = false;
    fprintAuth = true;
  };
}
