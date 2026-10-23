{
  # hyprlock stays installed as the fallback for a session lock the shell cannot
  # acquire; it is no longer the lock on the lock key.
  programs.hyprlock.enable = true;

  # fprintd itself is enabled by auth.nix, which owns the fingerprint PAM
  # services. The shell's password service opts out below, so the two lock flows
  # stay separate.

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
