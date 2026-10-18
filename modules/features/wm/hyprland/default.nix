{ pkgs, ... }:

{
  imports = [
    ./lua.nix
  ];

  # Tools invoked from binds in lua.nix. The bar and the launcher ship their own
  # packages, so only the standalone helpers belong here.
  home.packages = with pkgs; [
    awww
    brightnessctl
    cliphist
    grim
    playerctl
    slurp
    wl-clipboard
  ];

  wayland.windowManager.hyprland = {
    enable = true;

    # Hyprland reads its configuration as Lua rather than as hyprlang, so this
    # Home Manager module renders ~/.config/hypr/hyprland.lua.
    #
    # Chosen over "hyprlang" for one concrete reason: the screenshot picker's
    # keys. Binding keys to a layer surface needs a layer rule, and layer rules
    # with binds exist only in the Lua API — `hl.layer_rule`, reachable from
    # Lua and from nowhere else. Written as hyprlang there is no syntax for it
    # at all, which is why the picker keys had to be abandoned for a while.
    #
    # It also means the module's settings attrset is not the whole story: it
    # renders the declarative parts faithfully, but it emits config variables
    # as `hl.$mod("SUPER")`, and `$` cannot begin a Lua identifier, so any
    # `$name = value` entry produces a syntax error. Settings and binds both
    # live in lua.nix instead, written against the documented `hl.*` API.
    configType = "lua";
  };
}
