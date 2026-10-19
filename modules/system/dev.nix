{
  pkgs,
  ...
}:

{
  # Loads .envrc so the flake devshell (nixfmt, statix, deadnix, nil)
  # is available while editing this repository.
  programs.direnv.enable = true;

  # htop on the system rather than in a user profile: it is the tool you reach
  # for when something is wrong, at a console, as root, or from a session whose
  # profile is not the one you are logged in as. btop is the everyday one and
  # lives in the user profile; this is the one that has to be there anyway.
  environment.systemPackages = [ pkgs.htop ];
}
