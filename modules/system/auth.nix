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
  # greetd's PAM service authenticates through the `login` substack, so the
  # greeter picks the reader up from `login` below without a service of its own.
  security.pam.services = {
    hyprlock.fprintAuth = true; # the session lock
    sudo.fprintAuth = true; # a terminal's privilege escalation
    login.fprintAuth = true; # the console and greetd's greeter
    polkit-1.fprintAuth = true; # the shell's polkit prompt
  };
}
