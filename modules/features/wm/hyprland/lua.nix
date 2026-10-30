{ config, ... }:

let
  render = config.anixie.theme.template.render;

  # The config is one Lua chunk, so these are concatenated rather than loaded
  # with `require`: the sections share locals — `mod`, the bind helpers and
  # `capture` — and a file loaded with `require` would get its own scope.
  #
  # Order matters. `00-helpers.lua` defines the bind helpers, and `75-rules.lua`
  # defines `capture` before the capture binds in `binds/10-capture.lua` use it.
  sections = [
    "00-helpers.lua"
    "10-env.lua"
    "20-settings.lua"
    "30-plugins.lua"
    "40-animations.lua"
    "50-glass.lua"
    "60-gestures.lua"
    "70-startup.lua"
    "binds/00-launch.lua"
    "75-rules.lua"
    "binds/10-capture.lua"
    "binds/20-monitors.lua"
    "binds/30-panels.lua"
    "binds/40-toggles.lua"
    "binds/50-windows.lua"
    "binds/55-clipboard.lua"
    "binds/60-plugins.lua"
    "binds/70-session.lua"
    "binds/80-media.lua"
  ];
in
{
  # ----------------------------------------------------------------------
  # Hyprland's configuration, in Lua.
  #
  # Two things make Lua the right choice here, rather than a matter of taste.
  #
  # The first is PRINT. In hyprlang a bind is `mods, key, dispatcher, arg` with
  # positional fields, and `bind=PRINT, exec, shot smart` reads PRINT as the
  # modifier and `exec` as the key — so it fails with `Invalid dispatcher:
  # requested "shot smart" does not exist`. Escaping it as `code:133` and then
  # leaving the modifier field empty with a leading comma works, but both are
  # workarounds for a grammar that has no room for "a key with no modifier".
  # In Lua, `hl.bind("PRINT", ...)` just names the keysym. The workaround goes
  # away entirely.
  #
  # The second is that layer rules with binds exist only in this API. The
  # screenshot picker's keys need to be scoped to the picker's layer surface so
  # they cannot shadow a real application while the picker is closed.
  #
  # Settings, startup and binds all live here rather than in the module's
  # `settings` attrset, because that renderer emits `hl.exec-once(...)` and
  # `hl.$mod(...)` — a hyphen and a `$`, neither of which can appear in a Lua
  # identifier — and renders `settings.bind` as a single string where `hl.bind`
  # wants two arguments. Written out by hand, it depends only on the documented
  # `hl.*` API.
  #
  # Every bind is registered through `bind`/`dispatch` in 00-helpers.lua, which
  # unbind first. That makes the file idempotent: reloading cannot leave two
  # bindings fighting over one key, which is the usual reason a keybind
  # "sometimes" does the wrong thing after a reload.
  #
  # The sections under config/ are read through the renderer, so a placeholder
  # written into the Lua itself — the palette file's path and the border colours
  # — is substituted along with the ones passed to `render` by hand.
  # `@DEFAULT_AUDIO_SINK@` in the volume binds is not a theme token and is left
  # alone.
  # ----------------------------------------------------------------------
  wayland.windowManager.hyprland.extraConfig = builtins.concatStringsSep "\n" (
    map (file: render (./config + "/${file}")) sections
  );
}
