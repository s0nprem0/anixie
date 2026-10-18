{ config, ... }:

let
  render = config.my.theme.template.render;
in
{
  # ----------------------------------------------------------------------
  # Hyprland's own configuration is Lua, and this is all of it.
  #
  # It lives in one file, and in `extraConfig`, rather than in the module's
  # `settings` attrset, because that renderer is not trustworthy yet. It emits
  # each key as its own Lua call, and three of the shapes it emits do not parse:
  #
  #   settings.exec-once  ->  hl.exec-once("...")   hyphen in an identifier
  #   settings."$mod"     ->  hl.$mod("SUPER")      `$` cannot start a name
  #   settings.bind       ->  hl.bind("SUPER, Q, exec, kitty")
  #
  # The first is a syntax error that stops the whole file loading. The second is
  # the same. The third parses, because it is just a string, but it is the wrong
  # shape for hl.bind, which takes the key combination and the dispatcher as two
  # separate arguments — so it would have produced a config that loads and binds
  # nothing.
  #
  # Writing it out by hand instead means depending on the documented `hl.*` API
  # rather than on that translation, and it is also what makes the screenshot
  # picker's keys possible at all: layer rules live only in this API.
  #
  # Every line below is verified with `Hyprland --verify-config` before it is
  # considered done.
  # ----------------------------------------------------------------------
  wayland.windowManager.hyprland.extraConfig = ''
    -- ------------------------------------------------------------------
    -- Variables
    -- Plain Lua locals, not Hyprland config variables. The config-variable
    -- form ($mod = SUPER) has no Lua spelling that the module can emit, and
    -- string concatenation is both simpler and checked by the parser.
    -- ------------------------------------------------------------------
    local mod = "SUPER"
    local terminal = "kitty"
    local menu = "menu"

    -- ------------------------------------------------------------------
    -- Settings
    -- hl.config takes the same group/key shape the old hyprlang settings
    -- attrset described, so these read the same as they always did.
    -- ------------------------------------------------------------------
    hl.config({
      general = {
        gaps_in = 5,
        gaps_out = 10,
        border_size = 2,
        resize_on_border = true,

        ["col.active_border"] = "${render "@PRIMARY_RGBA_FF@"}",
        ["col.inactive_border"] = "${render "@MUTED_RGBA_AA@"}",
      },

      decoration = {
        rounding = 8,
        active_opacity = 0.97,
        inactive_opacity = 0.94,

        shadow = {
          enabled = true,
        },

        blur = {
          enabled = true,
          size = 5,
          passes = 2,
        };
      },

      input = {
        kb_layout = "us",
        follow_mouse = 1;
        touchpad = {
          natural_scroll = true;
        };
      },

      -- The wallpaper is awww's to draw. Hyprland's own default is a flat
      -- colour, which would otherwise flash over it at every start.
      misc = {
        force_default_wallpaper = 0;
      };
    })

    -- Native resolution with no HiDPI scaling: the panel is already 1920x1080,
    -- so 1.0 gives a full 1920x1080 workspace instead of 1280x720.
    --
    -- An empty output means "the default one", which is how the old
    -- `monitor = ,preferred,auto,1` line asked for it: the leading comma was
    -- an empty field. hl.monitor wants that spelled out rather than inferred,
    -- and says so if `output` is missing.
    hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

    -- ------------------------------------------------------------------
    -- Startup
    -- ------------------------------------------------------------------
    hl.on("hyprland.start", function()
      -- cliphist is fed both kinds of clipboard, so a screenshot copied with
      -- Super+Shift+C is in the history the same as any copied text.
      hl.exec_cmd("wl-paste --type text --watch cliphist store")
      hl.exec_cmd("wl-paste --type image --watch cliphist store")

      -- Push this Hyprland's socket and instance signature into the systemd
      -- user manager. Home Manager only does that once, at session start, so a
      -- compositor restart otherwise leaves the user manager holding the
      -- previous signature and a socket that no longer exists — which is fatal
      -- to anything started from it. The bar in particular crash-loops on
      -- "Failed to create a wl_display" until the session is logged into again.
      --
      -- Named explicitly rather than importing the whole environment, which
      -- would drag every variable Hyprland happens to be carrying into the user
      -- manager.
      hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP")

      -- awww-daemon aborts with SIGABRT if a second instance finds the socket
      -- already taken, and it re-runs whenever Hyprland reloads its config, so
      -- only start it when it is not already up. Matched on the process name
      -- rather than the full command line: pgrep -f would match the shell
      -- running this very line and the guard would never start anything.
      hl.exec_cmd("pgrep awww-daemon > /dev/null || awww-daemon")
    end)

    -- ------------------------------------------------------------------
    -- Launching
    -- ------------------------------------------------------------------
    hl.bind(mod .. " + RETURN", hl.dsp.exec_cmd(terminal))

    hl.bind(mod .. " + SPACE", hl.dsp.exec_cmd(menu))

    -- A reminder: asks how long, then for a message, and the timer it sets
    -- keeps running after this shell is gone.
    hl.bind(mod .. " + R", hl.dsp.exec_cmd("reminder -i"))

    hl.bind(mod .. " + SHIFT + V", hl.dsp.exec_cmd("sh -c 'cliphist list | fuzzel --dmenu | cliphist decode | wl-copy'"))

    -- Super+period, the emoji picker every other desktop uses. bemoji draws its
    -- list through fuzzel and types the choice with wtype rather than only
    -- putting it on the clipboard, so it lands in the focused window.
    hl.bind(mod .. " + PERIOD", hl.dsp.exec_cmd("bemoji -t"))

    -- The dock. Hyprland drives it, so the bind asks the shell over its IPC
    -- rather than writing a flag the shell would have to notice on a poll — the
    -- dock should appear on the keypress, not up to a second later.
    hl.bind(mod .. " + D", hl.dsp.exec_cmd("quickshell ipc call dock toggle"))

    -- ------------------------------------------------------------------
    -- The screenshot picker
    --
    -- Keys scoped to the picker's layer surface. In hyprlang there is no way
    -- to express this at all: layer rules with binds exist only in the Lua API,
    -- which is the whole reason this file is Lua.
    --
    -- The picks are a submap rather than permanent binds, so they cannot
    -- shadow a real application's keys when the picker is not open. Entering
    -- the submap is what capture binds do; leaving it is driven by the picker
    -- actually closing, which catches the mouse, the keyboard and a cancel
    -- alike without any of them having to remember to tidy up.
    -- ------------------------------------------------------------------
    hl.layer_rule({
      name = "picker-noanim",
      match = { namespace = "hyprpicker" },
      no_anim = true,
    })

    hl.on("layer.closed", function(layer)
      if layer.namespace:match("hyprpicker") then
        hl.dispatch(hl.dsp.submap("default"))
      end
    end)

    -- Opens the picker and arms its keys. Returns a function so each capture
    -- bind below can name its own mode.
    local function capture(cmd)
      return function()
        hl.dispatch(hl.dsp.submap("picker"))
        hl.exec_cmd(cmd)
      end
    end

    hl.define_submap("picker", "reset", function()
      -- Key handling cannot live in shot-pick: a key press arrives as a bind,
      -- never as input to that process. Each one re-runs it with a flag, and
      -- the marker file it touches is what tells the waiting slurp what was
      -- really asked for.

      -- Return takes whatever is under the pointer, so a click-free capture of
      -- a single window is two keys rather than a drag.
      hl.bind("RETURN", hl.dsp.exec_cmd("shot-pick --take-window"))
      hl.bind("CTRL + RETURN", hl.dsp.exec_cmd("shot-pick --take-fullscreen"))

      -- Tab walks to the neighbouring window and snaps the selection to it,
      -- which is the quickest way to capture something specific on a cluttered
      -- screen. CTRL+Tab goes the other way.
      hl.bind("TAB", hl.dsp.exec_cmd("shot-pick --select-window next"))
      hl.bind("CTRL + TAB", hl.dsp.exec_cmd("shot-pick --select-window prev"))

      -- Arrows extend the selection to whichever neighbour is in that
      -- direction, so a capture that needs two windows is one keypress per edge.
      hl.bind("LEFT", hl.dsp.exec_cmd("shot-pick --select-window left"))
      hl.bind("RIGHT", hl.dsp.exec_cmd("shot-pick --select-window right"))
      hl.bind("UP", hl.dsp.exec_cmd("shot-pick --select-window up"))
      hl.bind("DOWN", hl.dsp.exec_cmd("shot-pick --select-window down"))
    end)

    -- ------------------------------------------------------------------
    -- Screen capture
    -- One command, several modes, all through `shot` (features/wm/screenshot).
    -- The mode names and the keys are the reference shell's, so the habits
    -- carry across: the Print key captures, exactly as it does there.
    -- ------------------------------------------------------------------

    -- The primary binding. `smart` is the picker that can be both a drag and a
    -- click on a window, which is the one worth having on a single key.
    --
    -- Spelled as a keycode rather than as PRINT, because this Hyprland reads
    -- PRINT as a modifier: the line then parsed as dispatcher "shot smart", and
    -- the whole bind failed with "Invalid dispatcher".
    hl.bind("code:133", capture("shot smart"))

    -- The same capture, for people who reach for the keyboard rather than the
    -- keypad — also the reference shell's alias for it.
    hl.bind(mod .. " + SHIFT + S", capture("shot smart"))

    -- Snap to a whole window or monitor with no dragging at all.
    hl.bind(mod .. " + SHIFT + W", capture("shot windows"))

    -- The colour under the pointer, as a hex code. hyprpicker does this on its
    -- own; `pkill` first because one left running would eat the next press.
    -- Not a capture, so it never enters the picker submap.
    hl.bind(mod .. " + code:133", hl.dsp.exec_cmd("pkill hyprpicker || hyprpicker -a"))

    -- Straight to the clipboard rather than a file, for pasting a screenshot
    -- into whatever is focused.
    hl.bind(mod .. " + SHIFT + C", capture("shot smart copy"))

    -- Marked up before it is saved: the capture is handed to satty, which opens
    -- already in crop mode, so this crops and annotates the focused window
    -- rather than the whole screen and then waits to be told what to do.
    hl.bind(mod .. " + SHIFT + A", capture("shot smart annotate"))

    -- The whole screen with no picker at all, for when there is nothing to aim
    -- at. Nothing to choose, so no submap to arm either.
    hl.bind(mod .. " + SHIFT + F", hl.dsp.exec_cmd("shot fullscreen"))

    -- ------------------------------------------------------------------
    -- Moving focus between windows
    -- mod + HJKL walks the layout; the arrow keys duplicate it for people who
    -- reach for those first.
    -- ------------------------------------------------------------------
    hl.bind(mod .. " + H", hl.dsp.focus({ direction = "left" }))
    hl.bind(mod .. " + L", hl.dsp.focus({ direction = "right" }))
    hl.bind(mod .. " + K", hl.dsp.focus({ direction = "up" }))
    hl.bind(mod .. " + J", hl.dsp.focus({ direction = "down" }))

    hl.bind(mod .. " + LEFT", hl.dsp.focus({ direction = "left" }))
    hl.bind(mod .. " + RIGHT", hl.dsp.focus({ direction = "right" }))
    hl.bind(mod .. " + UP", hl.dsp.focus({ direction = "up" }))
    hl.bind(mod .. " + DOWN", hl.dsp.focus({ direction = "down" }))

    -- ------------------------------------------------------------------
    -- Moving and resizing the focused window
    -- Same HJKL shape as focus movement, with a modifier added:
    --   mod SHIFT + HJKL   nudge the window
    --   mod CTRL  + HJKL   resize the window
    -- The x/y step is relative; the sign decides the direction.
    -- ------------------------------------------------------------------
    hl.bind(mod .. " + SHIFT + H", hl.dsp.window.move({ x = -10, y = 0, relative = true }))
    hl.bind(mod .. " + SHIFT + L", hl.dsp.window.move({ x = 10, y = 0, relative = true }))
    hl.bind(mod .. " + SHIFT + K", hl.dsp.window.move({ x = 0, y = -10, relative = true }))
    hl.bind(mod .. " + SHIFT + J", hl.dsp.window.move({ x = 0, y = 10, relative = true }))

    hl.bind(mod .. " + CTRL + H", hl.dsp.window.resize({ x = -10, y = 0 }))
    hl.bind(mod .. " + CTRL + L", hl.dsp.window.resize({ x = 10, y = 0 }))
    hl.bind(mod .. " + CTRL + K", hl.dsp.window.resize({ x = 0, y = -10 }))
    hl.bind(mod .. " + CTRL + J", hl.dsp.window.resize({ x = 0, y = 10 }))

    -- ------------------------------------------------------------------
    -- Swapping the focused window with its neighbour
    -- ------------------------------------------------------------------
    hl.bind(mod .. " + SHIFT + LEFT", hl.dsp.window.swap({ direction = "left" }))
    hl.bind(mod .. " + SHIFT + RIGHT", hl.dsp.window.swap({ direction = "right" }))
    hl.bind(mod .. " + SHIFT + UP", hl.dsp.window.swap({ direction = "up" }))
    hl.bind(mod .. " + SHIFT + DOWN", hl.dsp.window.swap({ direction = "down" }))

    -- ------------------------------------------------------------------
    -- Window state
    -- ------------------------------------------------------------------
    hl.bind(mod .. " + Q", hl.dsp.window.kill())
    hl.bind(mod .. " + F", hl.dsp.window.fullscreen({ action = "toggle" }))
    hl.bind(mod .. " + V", hl.dsp.window.float({ action = "toggle" }))

    -- pseudo-tile turns the window into a column the group resizes as a unit;
    -- pin floats a window above everything regardless of focus order.
    hl.bind(mod .. " + P", hl.dsp.window.pseudo())
    hl.bind(mod .. " + SHIFT + P", hl.dsp.window.pin({ action = "toggle" }))

    -- ------------------------------------------------------------------
    -- Workspaces
    -- 1-5 jump and SHIFT + the same sends the window with you.
    -- ------------------------------------------------------------------
    for i = 1, 5 do
      hl.bind(mod .. " + " .. i, hl.dsp.focus({ workspace = tostring(i) }))
      hl.bind(mod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = tostring(i) }))
    end

    -- Comma and period step through all of them, so you are not boxed into the
    -- first five. Relative movement has no Lua form, so these still go through
    -- hyprctl — the same escape hatch the wheel already uses.
    hl.bind(mod .. " + comma", hl.dsp.exec_cmd("hyprctl dispatch workspace -1"))
    hl.bind(mod .. " + period", hl.dsp.exec_cmd("hyprctl dispatch workspace 1"))

    hl.bind(mod .. " + SHIFT + LEFT", hl.dsp.exec_cmd("hyprctl dispatch movetoworkspace -1"))
    hl.bind(mod .. " + SHIFT + RIGHT", hl.dsp.exec_cmd("hyprctl dispatch movetoworkspace 1"))

    -- Scrolling the wheel moves between existing workspaces.
    hl.bind(mod .. " + mouse_down", hl.dsp.exec_cmd("hyprctl dispatch workspace e-1"))
    hl.bind(mod .. " + mouse_up", hl.dsp.exec_cmd("hyprctl dispatch workspace e+1"))

    -- ------------------------------------------------------------------
    -- Scratchpad
    -- A special workspace that keeps its window alive and hidden while every
    -- other workspace stays empty. Good for a long-running terminal.
    -- ------------------------------------------------------------------
    hl.bind(mod .. " + TAB", hl.dsp.workspace.toggle_special("name:special"))

    -- ------------------------------------------------------------------
    -- Session
    -- SHIFT + M is the graceful logout Hyprland's own config recommends: it
    -- prefers a shutdown helper when one exists and falls back to a plain
    -- compositor exit. Plain mod + M still exits immediately.
    -- ------------------------------------------------------------------
    hl.bind(mod .. " + M", hl.dsp.exit())
    hl.bind(mod .. " + SHIFT + M", hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch exit"))
    hl.bind(mod .. " + SHIFT + A", hl.dsp.exec_cmd("hyprlock"))
    hl.bind(mod .. " + SHIFT + R", hl.dsp.exec_cmd("hyprctl reload"))

    -- ------------------------------------------------------------------
    -- Media and brightness
    -- These arrive as hardware keys, so `locked` lets them through a
    -- fullscreen window and `repeating` holds down smoothly.
    -- ------------------------------------------------------------------
    hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
    hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
    hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })

    hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
    hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
    hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

    hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl set +5%"), { locked = true, repeating = true })
    hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"), { locked = true, repeating = true })

    -- ------------------------------------------------------------------
    -- Mouse and trackpad
    -- mod + left/right drags a window around or resizes it, which is much
    -- quicker than holding a modifier and pressing an arrow repeatedly.
    --
    -- The bind's third argument marks it as a mouse bind; without it Hyprland
    -- waits for a key combination instead of a button.
    -- ------------------------------------------------------------------
    hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
    hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
    hl.bind(mod .. " + mouse:274", hl.dsp.window.drag(), { mouse = true })
  '';
}