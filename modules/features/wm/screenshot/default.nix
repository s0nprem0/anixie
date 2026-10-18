{
  pkgs,
  ...
}:

{
  # swappy is what the `-- CMD` route is used for when a capture needs marking
  # up or blurring before it goes anywhere.
  programs.swappy = {
    enable = true;

    settings.Default = {
      # Matches $SHOT_DIR below, so a capture sent through swappy lands beside
      # one saved directly. save_dir and save_filename_format are the key names
      # present in the swappy 1.8 binary.
      save_dir = "$HOME/Pictures/Screenshots";
      save_filename_format = "shot-%Y%m%d-%H%M%S.png";
    };
  };

  home.packages = [
    # Screenshots go through one command with the mode vocabulary the reference
    # shell uses, so the binds and any habit carry over, while nothing depends on
    # its own vendored tooling. hyprshot covers the modes natively, including the
    # interactive window picker and clipboard-only capture that grim cannot do.
    #
    # The path is substituted in rather than left to $PATH: these run from a
    # Hyprland bind, which does not necessarily carry the user's profile path.
    (pkgs.writeShellScriptBin "shot" (
      builtins.replaceStrings
        [ "@HYPRSHOT@" ]
        [ "${pkgs.hyprshot}/bin/hyprshot" ]
        (builtins.readFile ./shot.sh)
    ))

    pkgs.hyprshot
  ];
}