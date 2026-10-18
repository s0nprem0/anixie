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
        "@FUZZEL@"
        "@JQ@"
        "@SH@"
        "@SETSID@"
      ]
      [
        "${./tree.json}"
        "${pkgs.fuzzel}/bin/fuzzel"
        "${pkgs.jq}/bin/jq"
        "${pkgs.bash}/bin/bash"
        "${pkgs.util-linux}/bin/setsid"
      ]
      (builtins.readFile ./tree.sh)
  );
in

{
  # The launcher, and the menu it now leads to.
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
  #
  # Bare `menu` is the menu; `menu apps` is the icon-carrying launcher, and
  # `menu <name>` still launches one application by name.
  home.packages = [
    menuTree

    (pkgs.writeShellScriptBin "menu" (
      builtins.replaceStrings
        [
          "@FUZZEL@"
          "@TERMINAL@"
          "@MENU_TREE@"
        ]
        [
          "${pkgs.fuzzel}/bin/fuzzel"
          "kitty"
          "${menuTree}/bin/menu-tree"
        ]
        (builtins.readFile ./menu.sh)
    ))
  ];
}
