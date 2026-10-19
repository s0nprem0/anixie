{ lib, ... }:

{
  # Fingerprint sign-in, where the machine has a reader. No sensor showed up on
  # this Vivobook — the only i2c device is the ELAN touchpad, and nothing on the
  # USB bus claims to be one — but the wiring costs nothing without one: fprintd
  # sits idle, there is no print to enrol, and each service below simply falls
  # through to the password prompt.
  services.fprintd.enable = true;

  # The doors a fingerprint should open. Enrol with `fprintd-enroll`, and the
  # lock screen, sudo, the login greeter and the polkit prompt all offer the
  # reader first. Only services that already exist are named here — defining a
  # PAM service that nothing uses would write a config with nothing in it.
  #
  # mkForce because the GDM module sets fprintAuth to false on the services it
  # touches, and its plain definition would otherwise win over this one.
  security.pam.services = {
    hyprlock.fprintAuth = lib.mkForce true; # the session lock
    sudo.fprintAuth = lib.mkForce true; # a terminal's privilege escalation
    gdm.fprintAuth = lib.mkForce true; # the display manager's login
    login.fprintAuth = lib.mkForce true; # the console login
    polkit-1.fprintAuth = lib.mkForce true; # the shell's polkit prompt
  };
}
