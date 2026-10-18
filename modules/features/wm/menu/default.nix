{
  pkgs,
  ...
}:

let
  # The menu: every command this shell has, flattened and searchable, with the
  # applications alongside them. Built as its own command so it can be invoked
  # directly — `menu-tree --only Capture` is what the capture key runs — and so
  # `menu` is only the thing that decides which of them you meant.
  menuTree = pkgs.writeShellScriptBin "menu-tree" (
    builtins.replaceStrings
      [
        "@TREE@"
        "@QUICKSHELL@"
        "@JQ@"
        "@SH@"
      ]
      [
        "${./tree.json}"
        "${pkgs.quickshell}/bin/quickshell"
        "${pkgs.jq}/bin/jq"
        "${pkgs.bash}/bin/bash"
      ]
      (builtins.readFile ./tree.sh)
  );
in

{
  # The menu, and the launcher it now contains.
  #
  # `$menu` used to be bare `fuzzel`, which reads its candidates from stdin. A
  # Hyprland bind has no stdin to give it, so it opened an empty list — the bind
  # looked bound and did nothing.
  #
  # The applications come from desktop entries, which on NixOS cannot be found by
  # walking XDG_DATA_DIRS: an entry lives inside the store path of the package
  # that ships it, and nothing puts those on the search path. They are found by
  # asking Nix what the profile closes over, which is a few hundred paths and
  # takes about a second — cached under the profile it was built from, so a
  # rebuild invalidates it and a keypress does not pay for it.
  #
  # Bare `menu` is the menu, `menu apps` is the menu filtered to applications,
  # and `menu <name>` still launches one by name.
  home.packages = [
    menuTree

    (pkgs.writeShellScriptBin "menu" (
      builtins.replaceStrings
        [
          "@TERMINAL@"
          "@MENU_TREE@"
        ]
        [
          "kitty"
          "${menuTree}/bin/menu-tree"
        ]
        (builtins.readFile ./menu.sh)
    ))
  ];
}
