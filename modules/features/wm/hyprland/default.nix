{ pkgs, ... }:

{
  imports = [
    ./lua.nix
  ];

  # Tools invoked from binds in lua.nix. The bar and the launcher ship their own
  # packages, so only the standalone helpers belong here.
  home.packages = with pkgs; [
    # The shell draws still wallpapers on its background layer. awww is only
    # started by the `wallpaper` command for videos, which the shell cannot
    # render yet. It remains the manual fallback too.
    awww
    brightnessctl
    cliphist
    grim
    slurp
    wl-clipboard
  ];

  wayland.windowManager.hyprland = {
    enable = true;

    # Hyprland reads its configuration as Lua, so this Home Manager module
    # renders ~/.config/hypr/hyprland.lua.
    #
    # Not a matter of taste. A hyprlang bind is `mods, key, dispatcher, arg` with
    # positional fields, and PRINT is read as the *modifier* in
    # `bind=PRINT, exec, shot smart` — which fails with `Invalid dispatcher:
    # requested "shot smart" does not exist`, and can only be worked around by
    # spelling the key as a raw code. `hl.bind("PRINT", ...)` has no such
    # problem: it names the keysym.
    #
    # Layer rules with binds also exist only in this API, which is what the
    # screenshot picker's keys need, so that they cannot shadow a real
    # application's keys while the picker is closed.
    #
    # The module's settings attrset is deliberately unused: it emits
    # `hl.exec-once(...)` and `hl.$mod(...)`, neither of which is a legal Lua
    # identifier, and renders settings.bind as a single string where hl.bind
    # wants two arguments. Settings and binds are written out in lua.nix
    # instead, against the documented hl.* API.
    configType = "lua";
  };
}
