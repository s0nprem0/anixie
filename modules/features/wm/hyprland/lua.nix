{ config, ... }:

let
  render = config.my.theme.template.render;
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
  # Every bind is registered through `bind`/`dispatch` below, which unbind first.
  # That makes the file idempotent: reloading cannot leave two bindings fighting
  # over one key, which is the usual reason a keybind "sometimes" does the wrong
  # thing after a reload.
  # ----------------------------------------------------------------------
  wayland.windowManager.hyprland.extraConfig = ''
    local mod = "SUPER"
    local terminal = "kitty"
    local menu = "menu"

    -- ------------------------------------------------------------------
    -- Bind helpers
    --
    -- Every bind is described. Hyprland shows the description in its bind
    -- listing and some shells read it, so `hyprctl binds` says what a key does
    -- instead of only which keys are taken.
    --
    -- `hl.unbind` first, so re-running this file replaces bindings instead of
    -- stacking a second one on top of the first.
    -- ------------------------------------------------------------------
    local function bind(key, description, command)
      hl.unbind(key)
      hl.bind(key, hl.dsp.exec_cmd(command), { description = description })
    end

    -- Same, for a dispatcher rather than a shell command.
    --
    -- The dispatcher is named with dots — "window.move", "focus" — because that
    -- is how they read. hl.dsp does not accept that directly: hl.dsp["window.move"]
    -- is nil, so the path has to be walked. Getting this wrong fails loudly at
    -- config load with "attempt to call a nil value", which is better than the
    -- alternative — a bind that registers and silently does nothing.
    local function dispatch(key, description, name, args)
      hl.unbind(key)

      local dsp = hl.dsp
      for part in name:gmatch("[^%.]+") do
        dsp = dsp[part]
        if dsp == nil then
          error("no such dispatcher: " .. name .. " (for " .. key .. ")")
        end
      end

      hl.bind(key, args ~= nil and dsp(args) or dsp(), { description = description })
    end

    -- Runs a command, but only if it exists; otherwise the fallback. Used
    -- throughout the capture binds so this shell can grow into the reference
    -- shell's commands one at a time, without the keys going dead in the
    -- meantime.
    local function or_else(command, fallback)
      return "if command -v " .. command .. " >/dev/null 2>&1; then "
        .. command .. "; else " .. fallback .. "; fi"
    end

    -- ------------------------------------------------------------------
    -- Settings
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
        };

        blur = {
          enabled = true,
          size = 5,
          passes = 2;
        };
      },

      input = {
        kb_layout = "us",
        follow_mouse = 1;
        touchpad = {
          natural_scroll = true;
        };
      },

      -- awww draws the wallpaper; Hyprland's own default would flash over it.
      misc = {
        force_default_wallpaper = 0;
      };
    })

    -- Native resolution, no HiDPI scaling: the panel is already 1920x1080, so
    -- 1.0 gives a full 1920x1080 workspace rather than 1280x720. hl.monitor
    -- wants the output named, and an empty string means the default one.
    hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

    -- ------------------------------------------------------------------
    -- Startup
    -- ------------------------------------------------------------------
    hl.on("hyprland.start", function()
      -- cliphist is fed both kinds of clipboard, so a screenshot copied with
      -- Super+Shift+C is in the history alongside any copied text.
      hl.exec_cmd("wl-paste --type text --watch cliphist store")
      hl.exec_cmd("wl-paste --type image --watch cliphist store")

      -- Push this Hyprland's socket and instance signature into the systemd
      -- user manager. Home Manager only does that once, at session start, so a
      -- compositor restart otherwise leaves the user manager holding the
      -- previous signature and a socket that no longer exists — fatal to
      -- anything started from it. The bar in particular crash-loops on
      -- "Failed to create a wl_display" until the session is logged into again.
      --
      -- Named explicitly rather than importing the whole environment, which
      -- would drag every variable Hyprland happens to be carrying along.
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
    bind(mod .. " + RETURN", "Terminal", terminal)

    bind(mod .. " + SPACE", "Launcher", menu)

    -- Asks how long, then for a message, and the timer it sets keeps running
    -- after this shell is gone.
    bind(mod .. " + R", "Reminder", "reminder -i")

    bind(mod .. " + SHIFT + V", "Clipboard history",
      "cliphist list | fuzzel --dmenu | cliphist decode | wl-copy")

    -- bemoji draws its list through fuzzel and types the choice with wtype
    -- rather than only putting it on the clipboard, so it lands in the focused
    -- window instead of having to be pasted.
    bind(mod .. " + PERIOD", "Emoji picker", "bemoji -t")

    -- The dock. Hyprland drives it, so the bind asks the shell over its IPC
    -- rather than writing a flag the shell would notice on a poll — the dock
    -- should appear on the keypress, not up to a second later.
    bind(mod .. " + SHIFT + D", "Dock", "quickshell ipc call dock toggle")

    bind(mod .. " + SHIFT + RETURN", "Browser",
      or_else("xdg-open", "$EDITOR https://example.com"))

    bind(mod .. " + SHIFT + N", "Editor", "${EDITOR:-nvim}")

    -- ------------------------------------------------------------------
    -- The screenshot picker
    --
    -- Keys scoped to the picker's layer surface, so they cannot shadow a real
    -- application's keys while the picker is closed.
    --
    -- A submap, because that is what scoping a bind to a moment in time means
    -- here: the capture binds enter it, and it is left again when the picker
    -- closes. Leaving it matters more than it sounds. While a submap is
    -- active, every bind outside it is inactive — so a submap that never came
    -- down takes the whole desktop's keyboard with it, Super+Return included,
    -- with nothing on screen to say why.
    --
    -- Which is why three separate things close it: the capture wrapper resets
    -- it however the picker ends, the layer handler resets it when the picker
    -- closes, and escape and catchall reset it from the keyboard. The first
    -- one is the one that matters — it cannot miss, because it does not care
    -- why the command returned or whether a layer ever opened at all.
    -- ------------------------------------------------------------------
    hl.layer_rule({
      name = "picker-noanim",
      match = { namespace = "hyprpicker" },
      no_anim = true,
    })

    hl.on("layer.closed", function(layer)
      -- namespace is read off the layer rather than assumed: indexing nil raises
      -- inside the callback, and an event handler that dies silently is worse
      -- than one that never fires.
      local ns = layer and layer.namespace
      if ns and ns:find("hyprpicker", 1, true) then
        hl.dispatch(hl.dsp.submap("reset"))
      end
    end)

    local function capture(cmd)
      return function()
        hl.dispatch(hl.dsp.submap("picker"))
        -- "reset" rather than "default": Hyprland rejects the latter with
        -- "submap doesn't exist (wasn't registered!)", since only the name
        -- given to define_submap is registered.
        hl.exec_cmd(cmd .. " ; hyprctl dispatch 'hl.dsp.submap(\"reset\")'")
      end
    end

    -- Two arguments, name then body. A third argument is not "a reset mode":
    -- the three-argument form is define_submap(name, nextSubmap, body), which
    -- names a submap to switch to once this one dispatches.
    --
    -- Inside here binds go through hl.bind directly, never through the bind
    -- helper above. That helper unbinds first, which is what makes the global
    -- binds idempotent — but hl.unbind has no scope, so calling it from in here
    -- would take down the global binding for the same key. Binding SUPER+RETURN
    -- to "select fullscreen" while the picker is open would delete Terminal.
    hl.define_submap("picker", function()
      -- The way out, from either direction. Being stuck in here must never be
      -- a dead end.
      hl.bind("escape", hl.dsp.submap("reset"))
      hl.bind("catchall", hl.dsp.submap("reset"))

      -- Key handling cannot live in shot-pick: a key press arrives as a bind,
      -- never as input to that process. Each of these re-runs it with a flag,
      -- and the marker file it touches is what tells the waiting slurp what was
      -- really being asked for.

      -- Return takes whatever is under the pointer, so capturing one window is
      -- two keys rather than a drag.
      hl.bind("RETURN", hl.dsp.exec_cmd("shot-pick --take-window"), { description = "Select window under pointer" })
      hl.bind(mod .. " + RETURN", hl.dsp.exec_cmd("shot-pick --take-fullscreen"), { description = "Select fullscreen" })

      -- Tab walks to the neighbouring window and snaps the selection to it,
      -- which is the quickest way to capture something specific on a cluttered
      -- screen. Shift+Tab goes the other way.
      hl.bind("TAB", hl.dsp.exec_cmd("shot-pick --select-window next"), { description = "Select next window" })
      hl.bind("SHIFT + TAB", hl.dsp.exec_cmd("shot-pick --select-window prev"), { description = "Select previous window" })

      -- Arrows extend the selection to whichever neighbour is in that
      -- direction, so a capture spanning two windows is one keypress per edge.
      hl.bind("LEFT", hl.dsp.exec_cmd("shot-pick --select-window left"), { description = "Extend left" })
      hl.bind("RIGHT", hl.dsp.exec_cmd("shot-pick --select-window right"), { description = "Extend right" })
      hl.bind("UP", hl.dsp.exec_cmd("shot-pick --select-window up"), { description = "Extend up" })
      hl.bind("DOWN", hl.dsp.exec_cmd("shot-pick --select-window down"), { description = "Extend down" })
    end)

    -- ------------------------------------------------------------------
    -- Capture
    --
    -- Keys and modes are the reference shell's, so the habits carry across.
    -- Every one falls back to `shot`, so nothing here depends on commands this
    -- shell does not have.
    --
    -- PRINT is spelled as a keysym. No keycode, no leading comma, and none of
    -- the positional-field trouble that made it a workaround in hyprlang.
    -- ------------------------------------------------------------------
    hl.unbind("PRINT")
    hl.bind("PRINT", capture("shot smart"), { description = "Screenshot" })

    bind(mod .. " + SHIFT + S", "Screenshot", or_else("shot", "shot") .. " smart")

    bind(mod .. " + SHIFT + W", "Screenshot window", "shot windows")

    -- Fullscreen capture is SUPER+SHIFT+G, not SUPER+SHIFT+F: in the reference
    -- shell F is the file manager, and two binds on one key means one of them
    -- is never going to work.
    bind(mod .. " + SHIFT + G", "Screenshot fullscreen", "shot fullscreen")

    -- Straight to the clipboard, for pasting a screenshot into whatever is
    -- focused.
    bind(mod .. " + SHIFT + C", "Screenshot to clipboard", "shot smart copy")

    -- Marked up before it is saved: handed to satty, which opens already in crop
    -- mode, so this crops and annotates rather than capturing everything and
    -- then waiting to be told what to do.
    --
    -- CTRL, not SHIFT: SUPER+SHIFT+A used to be both this and the lock, which
    -- is one key doing two unrelated things.
    bind(mod .. " + CTRL + A", "Screenshot annotation", "shot smart annotate")

    -- The colour under the pointer, as a hex code. hyprpicker does this on its
    -- own; pkill first, because one left running would eat the next press.
    bind(mod .. " + PRINT", "Color picker", "pkill hyprpicker 2>/dev/null || hyprpicker -a")

    -- ------------------------------------------------------------------
    -- Focus
    -- mod + HJKL walks the layout; the arrows duplicate it for people who
    -- reach for those first.
    -- ------------------------------------------------------------------
    dispatch(mod .. " + H", "Focus left", "focus", { direction = "left" })
    dispatch(mod .. " + L", "Focus right", "focus", { direction = "right" })
    dispatch(mod .. " + K", "Focus up", "focus", { direction = "up" })
    dispatch(mod .. " + J", "Focus down", "focus", { direction = "down" })

    dispatch(mod .. " + LEFT", "Focus left", "focus", { direction = "left" })
    dispatch(mod .. " + RIGHT", "Focus right", "focus", { direction = "right" })
    dispatch(mod .. " + UP", "Focus up", "focus", { direction = "up" })
    dispatch(mod .. " + DOWN", "Focus down", "focus", { direction = "down" })

    -- ------------------------------------------------------------------
    -- Moving and resizing the focused window
    -- Same HJKL shape as focus, with a modifier added:
    --   mod SHIFT + HJKL   nudge the window
    --   mod CTRL  + HJKL   resize the window
    -- The x/y step is relative; the sign decides the direction.
    -- ------------------------------------------------------------------
    dispatch(mod .. " + SHIFT + H", "Nudge left", "window.move", { x = -10, y = 0, relative = true })
    dispatch(mod .. " + SHIFT + L", "Nudge right", "window.move", { x = 10, y = 0, relative = true })
    dispatch(mod .. " + SHIFT + K", "Nudge up", "window.move", { x = 0, y = -10, relative = true })
    dispatch(mod .. " + SHIFT + J", "Nudge down", "window.move", { x = 0, y = 10, relative = true })

    dispatch(mod .. " + CTRL + H", "Resize left", "window.resize", { x = -10, y = 0 })
    dispatch(mod .. " + CTRL + L", "Resize right", "window.resize", { x = 10, y = 0 })
    dispatch(mod .. " + CTRL + K", "Resize up", "window.resize", { x = 0, y = -10 })
    dispatch(mod .. " + CTRL + J", "Resize down", "window.resize", { x = 0, y = 10 })

    -- ------------------------------------------------------------------
    -- Swapping the focused window with its neighbour
    -- ------------------------------------------------------------------
    dispatch(mod .. " + SHIFT + LEFT", "Swap left", "window.swap", { direction = "left" })
    dispatch(mod .. " + SHIFT + RIGHT", "Swap right", "window.swap", { direction = "right" })
    dispatch(mod .. " + SHIFT + UP", "Swap up", "window.swap", { direction = "up" })
    dispatch(mod .. " + SHIFT + DOWN", "Swap down", "window.swap", { direction = "down" })

    -- ------------------------------------------------------------------
    -- Window state
    -- ------------------------------------------------------------------
    dispatch(mod .. " + Q", "Close window", "window.kill")

    dispatch(mod .. " + F", "Fullscreen", "window.fullscreen", { action = "toggle" })
    dispatch(mod .. " + V", "Float", "window.float", { action = "toggle" })

    -- pseudo-tile turns the window into a column the group resizes as a unit;
    -- pin floats a window above everything regardless of focus order.
    dispatch(mod .. " + P", "Pseudo-tile", "window.pseudo")
    dispatch(mod .. " + SHIFT + P", "Pin window", "window.pin", { action = "toggle" })

    -- ------------------------------------------------------------------
    -- Workspaces
    -- 1-5 jump, and SHIFT with the same sends the window along too.
    -- ------------------------------------------------------------------
    for i = 1, 5 do
      dispatch(mod .. " + " .. i, "Workspace " .. i, "focus", { workspace = tostring(i) })
      dispatch(mod .. " + SHIFT + " .. i, "Send to workspace " .. i, "window.move", { workspace = tostring(i) })
    end

    -- Comma and shift+comma step through all of them, so you are not boxed into
    -- the first five.
    --
    -- Not period. Hyprland key names are case-insensitive, so PERIOD and period
    -- are the same keysym: binding workspace stepping to period unbinds and
    -- replaces the emoji picker above, and it did so silently — the bind was
    -- gone from hyprctl binds with no error anywhere. Which of the two you want
    -- on that key is a choice, and the reference shell's choice is the emoji
    -- picker, so step with comma instead.
    bind(mod .. " + comma", "Previous workspace", "hyprctl dispatch 'hl.dsp.focus({workspace = -1})'")
    bind(mod .. " + SHIFT + comma", "Next workspace", "hyprctl dispatch 'hl.dsp.focus({workspace = 1})'")

    -- Note what is *not* here: SUPER+SHIFT+arrow does not also move the window to
    -- the next workspace. It used to, alongside the swap above, and because a
    -- key bound twice keeps whichever was registered last and says nothing
    -- about the other, one of the two silently did not exist. Sending a window
    -- to another workspace is SHIFT with a number, above; the arrows are for
    -- swapping with the neighbour, which is the action you reach for more.

    -- The wheel moves between existing workspaces. mouse_up and mouse_down, not
    -- a bare "wheel": the key has to say which way the wheel turned, or the two
    -- binds are identical apart from their argument and one shadows the other.
    bind(mod .. " + mouse_up", "Previous workspace", "hyprctl dispatch 'hl.dsp.focus({workspace = -1})'")
    bind(mod .. " + mouse_down", "Next workspace", "hyprctl dispatch 'hl.dsp.focus({workspace = 1})'")

    -- ------------------------------------------------------------------
    -- Scratchpad
    -- Keeps its window alive and hidden while every other workspace stays
    -- empty. Good for a long-running terminal.
    --
    -- toggle_special takes the bare name: it applies the "special:" prefix
    -- itself, and passing one is rejected.
    -- ------------------------------------------------------------------
    dispatch(mod .. " + TAB", "Scratchpad", "workspace.toggle_special", "special")

    -- ------------------------------------------------------------------
    -- Session
    -- SHIFT + M is the graceful logout: it prefers a shutdown helper when one
    -- exists and falls back to a plain compositor exit.
    -- ------------------------------------------------------------------
    dispatch(mod .. " + M", "Log out", "exit")

    bind(mod .. " + SHIFT + M", "Log out gracefully",
      "command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'")

    -- Lock is SUPER+CTRL+L. It used to share SUPER+SHIFT+A with the annotation
    -- bind, which is one key with two meanings and whichever fired last.
    bind(mod .. " + CTRL + L", "Lock", "hyprlock")

    bind(mod .. " + SHIFT + R", "Reload config", "hyprctl reload")

    -- ------------------------------------------------------------------
    -- Mouse and trackpad
    -- mod + left/right drags a window around or resizes it, which is much
    -- quicker than holding a modifier and pressing an arrow repeatedly.
    --
    -- The third argument marks these as mouse binds; without it Hyprland waits
    -- for a key combination rather than a button.
    -- ------------------------------------------------------------------
    hl.unbind(mod .. " + mouse:272")
    hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true, description = "Drag window" })

    hl.unbind(mod .. " + mouse:273")
    hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Resize window" })

    hl.unbind(mod .. " + mouse:274")
    hl.bind(mod .. " + mouse:274", hl.dsp.window.drag(), { mouse = true, description = "Drag window" })

    -- ------------------------------------------------------------------
    -- Media and brightness
    -- These arrive as hardware keys, so `locked` lets them through a fullscreen
    -- window and `repeating` holds down smoothly.
    -- ------------------------------------------------------------------
    bind("XF86AudioRaiseVolume", "Volume up",
      "wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+")
    bind("XF86AudioLowerVolume", "Volume down", "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-")
    bind("XF86AudioMute", "Mute", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")

    bind("XF86AudioPlay", "Play/pause", "playerctl play-pause")
    bind("XF86AudioNext", "Next track", "playerctl next")
    bind("XF86AudioPrev", "Previous track", "playerctl previous")

    bind("XF86MonBrightnessUp", "Brighter", "brightnessctl set +5%")
    bind("XF86MonBrightnessDown", "Dimmer", "brightnessctl set 5%-")
  '';
}