{
  pkgs,
  ...
}:

{
  # The launcher.
  #
  # `$menu` used to be bare `fuzzel`, which reads its candidates from stdin. A
  # Hyprland bind has no stdin to give it, so it opened an empty list — the bind
  # looked bound and did nothing.
  #
  # The candidates come from desktop entries, which on NixOS cannot be found by
  # walking XDG_DATA_DIRS: an entry lives inside the store path of the package
  # that ships it, and nothing puts those on the search path. They are found by
  # asking Nix what the profile closes over, which is a few hundred paths and
  # takes about a second — cached under the profile it was built from, so a
  # rebuild invalidates it and a keypress does not pay for it.
  home.packages = [
    (pkgs.writeShellScriptBin "menu" (
      builtins.replaceStrings
        [
          "@FUZZEL@"
          "@TERMINAL@"
        ]
        [
          "${pkgs.fuzzel}/bin/fuzzel"
          "kitty"
        ]
        (builtins.readFile ./menu.sh)
    ))
  ];
}
