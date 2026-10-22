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
  # Through the renderer, so a placeholder written into the Lua itself — the
  # palette file's path, which the border colours read at runtime — is substituted
  # along with the ones passed to `render` by hand. `@DEFAULT_AUDIO_SINK@` in the
  # volume binds is not a theme token and is left alone.
  wayland.windowManager.hyprland.extraConfig = render ''
    local mod = "SUPER"
    local terminal = "kitty"

    -- ------------------------------------------------------------------
    -- Bind helpers
    --
    -- Every bind is described. Hyprland shows the description in its bind
    -- listing and some shells read it, so `hyprctl binds` says what a key does
    -- instead of only which keys are taken.
    --
    -- `hl.unbind` first, so re-running this file replaces bindings instead of
    -- stacking a second one on top of the first.
    --
    -- `options` are merged into the bind's table alongside the description, so
    -- a hardware key can still ask for `locked` and `repeating`.
    -- ------------------------------------------------------------------
    local function bind(key, description, command, options)
      hl.unbind(key)

      local opts = { description = description }
      for name, value in pairs(options or {}) do
        opts[name] = value
      end

      hl.bind(key, hl.dsp.exec_cmd(command), opts)
    end

    -- Same, for a key the shell catches itself as a global shortcut. No process
    -- runs between the key and the shell, which is what makes the menu open on
    -- the keypress rather than after a `quickshell ipc` call has started up.
    local function bind_global(key, description, name)
      hl.unbind(key)
      hl.bind(key, hl.dsp.global("quickshell:" .. name), { description = description })
    end

    -- Same, for a handler function rather than a shell command.
    --
    -- The picker binds need the "picker" submap entered and left again around a
    -- command, which is two dispatches around one exec — more than `bind`'s
    -- single exec_cmd can express. They go through here so they still unbind
    -- first and stay idempotent across a reload like every other bind.
    local function bind_handler(key, description, handler)
      hl.unbind(key)
      hl.bind(key, handler, { description = description })
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

    -- ------------------------------------------------------------------
    -- Environment
    --
    -- Set in the compositor rather than through Home Manager's session
    -- variables: these have to reach everything a bind starts, and a session
    -- variable is exported by the login shell, which a compositor-launched app
    -- never runs.
    --
    -- The `;` and `,` in the Qt and GTK values are fallback lists, not typos.
    -- ------------------------------------------------------------------
    hl.env("NIXOS_OZONE_WL", "1")
    hl.env("QT_QPA_PLATFORM", "wayland;xcb")
    hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
    hl.env("GDK_BACKEND", "wayland,x11")
    hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
    hl.env("MOZ_ENABLE_WAYLAND", "1")

    -- ------------------------------------------------------------------
    -- Settings
    --
    -- The border colours come from the live theme rather than from the palette
    -- this file was built with, so `theme set` recolours the borders on the
    -- `hyprctl reload` it already triggers. Read the same way the saved monitor
    -- scale is: a small state file the config reads at load, because Hyprland has
    -- no runtime call for either and a build-time value cannot change without a
    -- rebuild.
    --
    -- The built-in colours below are the fallback, used when the file is not
    -- there or does not name something usable.
    -- ------------------------------------------------------------------
    local function theme_colour(token, fallback)
      local state_home = os.getenv("XDG_STATE_HOME")
        or ((os.getenv("HOME") or "") .. "/.local/state")
      local file = io.open(state_home .. "/anixie/theme/current", "r")
      if not file then return fallback end

      local name = file:read("l")
      file:close()
      if not name then return fallback end
      name = name:gsub("%s+", "")
      -- Escaped before it goes into a pattern: a palette name is a plain word, but
      -- one of them will eventually contain a '-' or a '.', and in a Lua pattern
      -- those are quantifiers rather than characters.
      name = name:gsub("(%W)", "%%%1")

      local palettes_file = io.open("@PALETTES@", "r")
      if not palettes_file then return fallback end
      local raw = palettes_file:read("a")
      palettes_file:close()

      -- The palette table is JSON, which is not Lua: quoted keys and no trailing
      -- commas, so it cannot simply be loaded. Pull the one field out instead.
      local hex = raw:match('"' .. name .. '"%s*:%s*{[^}]-"' .. token .. '"%s*:%s*"(#%x%x%x%x%x%x)"')
      if not hex then return fallback end

      local r, g, b = hex:match("#(%x%x)(%x%x)(%x%x)")
      return "rgba(" .. r .. g .. b .. "ff)"
    end

    hl.config({
      general = {
        gaps_in = 5,
        gaps_out = 10,
        border_size = 2,
        resize_on_border = true,

        -- Edge snapping for floating windows; tiled windows ignore it.
        snap = {
          enabled = true,
          window_gap = 8,
          monitor_gap = 8,
          respect_gaps = true;
        };

        ["col.active_border"] = theme_colour("primary", "${render "@PRIMARY_RGBA_FF@"}"),
        ["col.inactive_border"] = theme_colour("muted", "${render "@MUTED_RGBA_AA@"}"),
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

      -- Keep the split direction when a window opens or closes, so the layout
      -- does not reshuffle itself around every change.
      dwindle = {
        preserve_split = true;
      };

      input = {
        kb_layout = "us",
        follow_mouse = 1;
        touchpad = {
          natural_scroll = true;
        };
      },

      -- 300ms between wheel notches is long enough to feel ignored; 150 still
      -- debounces a free-spinning wheel. The scratchpad belongs to the
      -- workspace it was opened on, so switching away should hide it.
      binds = {
        scroll_event_delay = 150;
        hide_special_on_workspace_change = true;
      };

      -- awww draws the wallpaper; Hyprland's own default would flash over it.
      -- The logo and splash are off for the same reason: awww is already up by
      -- the time the first frame is drawn.
      misc = {
        force_default_wallpaper = 0;
        disable_hyprland_logo = true;
        disable_splash_rendering = true;

        -- A blanked output should come back on the first key or mouse movement
        -- rather than waiting for a click. hypridle's on-resume normally does
        -- this itself; these cover a DPMS state set by anything else.
        key_press_enables_dpms = true;
        mouse_move_enables_dpms = true;
      };
    })

    -- Native resolution, no HiDPI scaling: the panel is already 1920x1080, so
    -- 1.0 gives a full 1920x1080 workspace rather than 1280x720. hl.monitor
    -- wants the output named, and an empty string means the default one.
    --
    -- This is the fallback for every output, and it is what a monitor that has
    -- never been scaled gets. The `monitors` command steps the scale of the one
    -- you are on and writes the choice to a state file; the rules below read that
    -- file back and re-assert the scale, which is the only way a choice made at
    -- runtime can outlive a config reload. There is no runtime monitor dispatcher
    -- to ask, and `hyprctl keyword` is refused outright by the Lua config manager.
    hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

    -- The saved settings, one rule per output that has any. Read with io rather
    -- than through a helper because Hyprland exposes no config reader, and io is
    -- available to the config: it is the same Lua state `hyprctl eval` runs in.
    --
    -- A line is `output scale transform disabled`. The last two were added after
    -- the first, so a line written by the older format is still two fields: the
    -- pattern's optional groups leave them nil, and the rule falls back to no
    -- rotation and the output on. That way a machine updating from the earlier
    -- version keeps its scales without the file having to be rewritten.
    --
    -- Every field has to look right before it is used. A hand-edited or truncated
    -- file should not be able to ask Hyprland for an output name or a scale that
    -- nothing here knows about, so a malformed line is skipped rather than passed
    -- on.
    do
      local state_home = os.getenv("XDG_STATE_HOME")
        or ((os.getenv("HOME") or "") .. "/.local/state")
      local file = io.open(state_home .. "/anixie/display.conf", "r")

      if file then
        for line in file:lines() do
          local output, scale, transform, disabled =
            line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)$")
            or line:match("^(%S+)%s+(%S+)$")

          if output and scale and scale:match("^%d+%.?%d*$") then
            hl.monitor({
              output = output,
              mode = "preferred",
              position = "auto",
              scale = tonumber(scale),
              transform = tonumber(transform or "0"),
              disabled = disabled == "1",
            })
          end
        end
        file:close()
      end
    end

    -- ------------------------------------------------------------------
    -- Gestures
    --
    -- One gesture, so it cannot fight another for the same fingers: a
    -- horizontal three-finger swipe moves between workspaces, the touchpad
    -- equivalent of the keyboard's workspace binds.
    --
    -- The swipe distance and inversion are Hyprland's defaults; only the
    -- binding itself is new. Vertical three-finger swipes are left free.
    -- ------------------------------------------------------------------
    hl.gesture({
      fingers = 3,
      direction = "horizontal",
      action = "workspace",
    })

    -- ------------------------------------------------------------------
    -- Startup
    -- ------------------------------------------------------------------
    hl.on("hyprland.start", function()
      -- cliphist is fed both kinds of clipboard, so a screenshot copied with
      -- Super+Shift+C is in the history alongside any copied text. The wrapper
      -- drops selections that password managers mark as secrets.
      hl.exec_cmd("clipboard-watch")

      -- Push this Hyprland's socket and instance signature into both the
      -- D-Bus activation environment and the systemd user manager. Home
      -- Manager only does that once, at session start, so a compositor restart
      -- otherwise leaves them holding the previous signature and a socket that
      -- no longer exists — fatal to anything started from it. The bar in
      -- particular crash-loops on "Failed to create a wl_display" until the
      -- session is logged into again. The portal is D-Bus-activated, so it
      -- needs the same variables in the bus's environment, not only systemd's.
      --
      -- Named explicitly rather than importing the whole environment, which
      -- would drag every variable Hyprland happens to be carrying along.
      hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP XDG_SESSION_TYPE")

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

    bind_global(mod .. " + SPACE", "Menu", "menu")

    -- Asks how long, then for a message, and the timer it sets keeps running
    -- after this shell is gone.
    bind(mod .. " + R", "Reminder", "reminder -i")

    -- This used to be SHIFT+V. Unbind the old key explicitly so a reload in a
    -- running session does not leave both shortcuts behind.
    hl.unbind(mod .. " + SHIFT + V")
    bind(mod .. " + CTRL + V", "Clipboard history", "clipboard")

    -- The emoji picker types the choice into the focused window rather than only
    -- copying it, so it lands in the sentence being written instead of having to
    -- be pasted.
    bind(mod .. " + PERIOD", "Emoji picker", "emoji")

    -- The dock. Hyprland drives it, so the bind asks the shell over its IPC
    -- rather than writing a flag the shell would notice on a poll — the dock
    -- should appear on the keypress, not up to a second later.
    bind(mod .. " + SHIFT + D", "Dock", "quickshell ipc call dock toggle")

    -- The default browser, whichever it is, opened on its own home page. Not
    -- `xdg-open` on its own: with no file or URL it prints its usage and exits,
    -- so the key did nothing. xdg-settings names the browser's desktop entry and
    -- the menu launches it by id. basename strips the suffix rather than a
    -- parameter expansion, whose dollar-brace Nix would take for its own.
    bind(mod .. " + SHIFT + RETURN", "Browser",
      "menu \"$(basename \"$(xdg-settings get default-web-browser)\" .desktop)\"")

    -- The editor command is escaped so Nix leaves it alone. Inside this string an
    -- unescaped dollar-brace is Nix interpolation, and Nix reads what sits between
    -- the braces — `EDITOR:-nvim` — as a URI literal, the same shape as a web
    -- address. It interpolates to the plain text `EDITOR:-nvim`, the dollar sign is
    -- gone, and the bind runs `EDITOR:-nvim` as a command, which is nothing. The
    -- two single quotes before the dollar-brace are what keep it a shell expansion.
    bind(mod .. " + SHIFT + N", "Editor", "''${EDITOR:-nvim}")

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

    -- ------------------------------------------------------------------
    -- The webcam overlay
    --
    -- A pinned portrait window in the corner of whatever is being recorded, drawn
    -- by mpv. Three sizes, each a share of the *recording's* height rather than
    -- the monitor's, so the camera takes the same part of a 1080p capture as of a
    -- 6K one.
    --
    -- These rules only apply when the window first appears, which is why the
    -- resize binds move and resize the client directly instead of switching it
    -- between rules. The app-id carries the size, and mpv is started with it, so
    -- the rule that matches is the one for the size it was started at.
    --
    --   small   h*9/50 tall, 8:9 wide
    --   medium  h/4    tall, 8:9 wide
    --   large   h*27/80 tall, 8:9 wide
    --
    -- The 40 is the margin from the corner, matching MARGIN in
    -- features/wm/capture/webcam-overlay.sh, which has to agree with it or the
    -- first size and every later resize would land in different places.
    -- ------------------------------------------------------------------
    hl.window_rule({
      name = "webcam-overlay-small",
      match = { class = "^WebcamOverlay-small$" },
      size = { "(monitor_h*4/25)", "(monitor_h*9/50)" },
      move = { "(monitor_w-monitor_h*4/25-40)", "(monitor_h-monitor_h*9/50-40)" },
    })
    hl.window_rule({
      name = "webcam-overlay-medium",
      match = { class = "^WebcamOverlay-medium$" },
      size = { "(monitor_h*2/9)", "(monitor_h/4)" },
      move = { "(monitor_w-monitor_h*2/9-40)", "(monitor_h-monitor_h/4-40)" },
    })
    hl.window_rule({
      name = "webcam-overlay-large",
      match = { class = "^WebcamOverlay-large$" },
      size = { "(monitor_h*3/10)", "(monitor_h*27/80)" },
      move = { "(monitor_w-monitor_h*3/10-40)", "(monitor_h-monitor_h*27/80-40)" },
    })

    -- Float, pin and leave alone. `no_initial_focus` keeps the camera from taking
    -- focus when it appears — otherwise starting a recording would interrupt
    -- whatever is being recorded — and `no_dim` keeps it from dimming with the
    -- rest when something else is focused.
    --
    -- Matched on class and title together: the class alone would also catch an
    -- mpv window whose app-id happened to be set the same way, and the title is
    -- the fixed string the overlay is always started with.
    hl.window_rule({
      name = "webcam-overlay-behaviour",
      match = {
        class = "^WebcamOverlay-(small|medium|large)$",
        title = "^WebcamOverlay$",
      },
      float = true,
      pin = true,
      no_initial_focus = true,
      no_dim = true,
    })

    -- File choosers are dialogs for the app that opened them, not documents
    -- to tile beside it. Match the portal classes as well as the titles GTK
    -- and Qt put on their choosers: an app can draw the dialog in its own
    -- process, in which case the class is the parent's and only the title
    -- identifies it.
    hl.window_rule({
      name = "file-chooser-float",
      match = {
        class = "^(xdg-desktop-portal-gtk|xdg-desktop-portal-kde)$",
      },
      float = true,
    })
    hl.window_rule({
      name = "file-chooser-title-float",
      match = {
        title = "^(Open|Save) Files?$|^Save As$|^(Open|Select) Folder$|^Choose Files?$|^Select File$",
      },
      float = true,
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
    --
    -- Every bind that opens the picker goes through `capture`, which is what
    -- enters the "picker" submap for the duration. A bind that calls `shot`
    -- directly still takes the shot, but Return, Tab and the arrows — the whole
    -- keyboard side of the picker — are only bound inside the submap, so they do
    -- nothing. That is why every one of them is wrapped, not just PRINT.
    --
    -- PRINT is spelled as a keysym. No keycode, no leading comma, and none of
    -- the positional-field trouble that made it a workaround in hyprlang.
    -- ------------------------------------------------------------------
    bind_handler("PRINT", "Screenshot", capture("shot smart"))

    -- The same capture as PRINT, for a keyboard without a Print key. This key
    -- used to splice a shell conditional together around the command, which
    -- rendered as `if command -v shot; then shot; else shot; fi smart` — `fi`
    -- followed by an argument, a shell syntax error, so the key did nothing.
    bind_handler(mod .. " + SHIFT + S", "Screenshot", capture("shot smart"))

    bind_handler(mod .. " + SHIFT + W", "Screenshot window", capture("shot windows"))

    -- Fullscreen capture is SUPER+SHIFT+G, not SUPER+SHIFT+F: in the reference
    -- shell F is the file manager, and two binds on one key means one of them
    -- is never going to work.
    --
    -- No picker, so no submap: the monitor is already known and there is nothing
    -- to aim at.
    bind(mod .. " + SHIFT + G", "Screenshot fullscreen", "shot fullscreen")

    -- Straight to the clipboard, for pasting a screenshot into whatever is
    -- focused. Still a picker — "smart copy" means pick, then copy.
    bind_handler(mod .. " + SHIFT + C", "Screenshot to clipboard", capture("shot smart copy"))

    -- Marked up before it is saved: handed to satty, which opens already in crop
    -- mode, so this crops and annotates rather than capturing everything and
    -- then waiting to be told what to do.
    --
    -- ALT, not CTRL: the reference shell puts the audio panel on SUPER+CTRL+A, and
    -- the panel keys are a set worth keeping together — A, W, B, D, P below. This
    -- key had CTRL only because SUPER+SHIFT+A was taken by the lock at the time,
    -- which is no longer true; ALT keeps it clear of the whole panel group. It is
    -- also in the capture menu, so nothing depends on this key existing.
    bind_handler(mod .. " + ALT + A", "Screenshot annotation", capture("shot smart annotate"))

    -- The colour under the pointer, as a hex code. hyprpicker does this on its
    -- own; pkill first, because one left running would eat the next press.
    bind(mod .. " + PRINT", "Color picker", "pkill hyprpicker 2>/dev/null || hyprpicker -a")

    -- The text inside a region, OCR'd to the clipboard.
    bind_handler(mod .. " + CTRL + PRINT", "Extract text", capture("capture-text"))

    -- The whole menu, filtered to the capture entries. The family has grown past
    -- what is worth a key each, and this is how the rest stay reachable.
    --
    -- A plain bind, not one of the `capture` wrappers above. Those enter the
    -- picker submap around the command, which is right when the command *is* the
    -- picker — but the menu opens the picker for a region and then hands off to
    -- a detached process, and the wrapper would take the submap back down in the
    -- gap between the two. The picker enters it itself now, so the wrapper is
    -- only a backstop, and this path does not want one.
    bind_global(mod .. " + CTRL + C", "Capture menu", "menu-capture")

    -- Shrink a picture or a video before sending it. No picker of its own — it
    -- asks the shell for the file, the format and the size — so it is a plain
    -- bind.
    bind(mod .. " + CTRL + PERIOD", "Transcode", "transcode")

    -- ------------------------------------------------------------------
    -- Recording
    --
    -- ALT+PRINT starts one, or stops the one that is running — the same key both
    -- ways, like PRINT for screenshots. It asks about audio first, then opens the
    -- same picker as a screenshot, so the region keys are already known.
    --
    -- Wrapped in `capture` because it *is* the picker: it needs the submap up for
    -- Return and the arrows. When the key is stopping a recording instead, the
    -- submap goes up and straight back down, which is harmless.
    -- ------------------------------------------------------------------
    bind_handler(mod .. " + ALT + PRINT", "Screen record", capture("record"))

    -- The overlay is resized while a recording runs, not chosen up front, so these
    -- are plain binds rather than anything the picker owns.
    --
    -- `[` and `]` by keysym name: bracketleft and bracketright are what the X11
    -- keysym table calls them, and Hyprland takes the name, not the character.
    bind(mod .. " + ALT + bracketleft", "Webcam overlay smaller", "webcam-overlay resize smaller")
    bind(mod .. " + ALT + bracketright", "Webcam overlay larger", "webcam-overlay resize larger")

    -- ------------------------------------------------------------------
    -- Monitors
    --
    -- Scaling steps the monitor you are on through 1x, 1.25x, 1.6x, 2x, 3x and 4x,
    -- and the choice is remembered by the `monitors` command rather than by this
    -- file — see the note on the monitor rules above.
    --
    -- `/` is `slash` by keysym name, the same reason `[` is bracketleft below.
    -- ------------------------------------------------------------------
    bind(mod .. " + slash", "Scale up", "monitors scale up")
    bind(mod .. " + ALT + slash", "Scale down", "monitors scale down")

    -- The laptop panel on its own, and mirroring it onto whatever is plugged in.
    -- Both are no-ops without the hardware: `monitors internal` falls back to the
    -- first monitor, and `monitors mirror` says so and stops when there is no
    -- external one to mirror onto.
    bind(mod .. " + CTRL + DELETE", "Internal display", "monitors internal toggle")
    bind(mod .. " + CTRL + ALT + DELETE", "Mirror displays", "monitors mirror toggle")

    -- Moving between monitors, for layouts the arrow keys cannot reach: screens
    -- that only touch at a corner, or that have a gap between them, are not
    -- neighbours, so direction cannot find them. `+1` and `-1` walk the list
    -- instead, and wrap.
    dispatch(mod .. " + CTRL + ALT + TAB", "Next monitor", "focus", { monitor = "+1" })
    dispatch(mod .. " + CTRL + ALT + SHIFT + TAB", "Previous monitor", "focus", { monitor = "-1" })

    -- The focused window, and the whole workspace, to the monitor on that side.
    -- A direction with no monitor in it resolves to nothing and the bind quietly
    -- does nothing, which is the right failure for a key that has no meaning on a
    -- single screen.
    dispatch(mod .. " + SHIFT + CTRL + LEFT", "Window to monitor left", "window.move", { monitor = "left" })
    dispatch(mod .. " + SHIFT + CTRL + RIGHT", "Window to monitor right", "window.move", { monitor = "right" })
    dispatch(mod .. " + SHIFT + CTRL + UP", "Window to monitor up", "window.move", { monitor = "up" })
    dispatch(mod .. " + SHIFT + CTRL + DOWN", "Window to monitor down", "window.move", { monitor = "down" })

    dispatch(mod .. " + SHIFT + ALT + LEFT", "Workspace to monitor left", "workspace.move", { monitor = "left" })
    dispatch(mod .. " + SHIFT + ALT + RIGHT", "Workspace to monitor right", "workspace.move", { monitor = "right" })
    dispatch(mod .. " + SHIFT + ALT + UP", "Workspace to monitor up", "workspace.move", { monitor = "up" })
    dispatch(mod .. " + SHIFT + ALT + DOWN", "Workspace to monitor down", "workspace.move", { monitor = "down" })

    -- ------------------------------------------------------------------
    -- Panels and the bar
    --
    -- Every panel already opens by clicking its glyph; these are the same panels
    -- by key, so nobody has to aim at a 16-pixel target. They go through the
    -- shell's IPC rather than a flag file, for the same reason the dock toggle
    -- does: the panel should appear on the keypress, not on the next poll.
    --
    -- The name is what the widget registers itself under when it loads, so a panel
    -- that is not on the bar logs a warning and does nothing rather than opening
    -- something else.
    --
    -- A, W, B, D and P are the reference shell's letters for audio, network,
    -- bluetooth, brightness and power. Calendar is the clock's panel.
    -- ------------------------------------------------------------------
    bind(mod .. " + CTRL + A", "Audio panel", "quickshell ipc call panel toggle audio")
    bind(mod .. " + CTRL + W", "Network panel", "quickshell ipc call panel toggle network")
    bind(mod .. " + CTRL + B", "Bluetooth panel", "quickshell ipc call panel toggle bluetooth")
    bind(mod .. " + CTRL + D", "Brightness panel", "quickshell ipc call panel toggle display")
    bind(mod .. " + CTRL + P", "Power panel", "quickshell ipc call panel toggle power")
    bind(mod .. " + CTRL + ALT + D", "Calendar panel", "quickshell ipc call panel toggle calendar")

    -- The per-screen panel, separate from the brightness one on CTRL+D: a
    -- brightness slider has no business carrying a row for every attached output,
    -- and a second screen appearing is not a brightness problem.
    bind(mod .. " + CTRL + SHIFT + D", "Monitors panel", "quickshell ipc call panel toggle displays")

    -- The same panels by number, the way Omarchy numbers them: CTRL+1 is the
    -- first panel icon from the left, CTRL+2 the next, counting only the widgets
    -- that have a panel at all. The letters above are quicker once they are
    -- learned; these are what you can find without knowing which letter a panel
    -- was given.
    for i = 1, 9 do
      bind(mod .. " + CTRL + " .. i, "Panel " .. i .. " from the left",
        "quickshell ipc call panel position " .. i)
    end

    -- The bar on and off. The window stays mapped and only its contents hide, so
    -- the panels above still open against it while it is out of the way.
    bind(mod .. " + SHIFT + SPACE", "Toggle bar", "quickshell ipc call bar toggle")

    -- ------------------------------------------------------------------
    -- Style
    --
    -- The theme picker. The shell, the window borders, the terminal and the
    -- picker all follow it; the shell and the borders follow the state file it
    -- writes, and kitty is signalled.
    --
    -- The reference's key, and the reason it is this one: it is the only theme
    -- gesture that needs a picker, so it wants the space bar with everything held.
    -- ------------------------------------------------------------------
    bind(mod .. " + CTRL + SHIFT + SPACE", "Theme picker", "theme")

    -- ------------------------------------------------------------------
    -- Toggles
    --
    -- The modes the bar's indicators show, on the keys the reference gives them.
    -- Each is the same switch the indicator flips — `toggle` is what both call —
    -- so the key and the glyph cannot end up disagreeing.
    --
    -- Night light warms to 4000K and back to 6500K; idle is the idle *lock*, so
    -- turning it off is what leaves the machine awake.
    -- ------------------------------------------------------------------
    bind(mod .. " + CTRL + N", "Night light", "toggle nightlight")
    bind(mod .. " + CTRL + I", "Stay awake", "toggle idle")
    bind(mod .. " + CTRL + comma", "Silence notifications", "toggle dnd")
    bind(mod .. " + ALT + comma", "Replay notifications", "quickshell ipc call notify replay")
    bind(mod .. " + CTRL + O", "Toggle menu", "toggle")

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

    -- Comma and shift+comma walk the existing workspaces, the same as the wheel
    -- below: a gap of empty ones is crossed in one step. Numbered stepping would
    -- stop on every empty workspace instead, which is a different gesture.
    --
    -- Not period. Hyprland key names are case-insensitive, so PERIOD and period
    -- are the same keysym: binding workspace stepping to period unbinds and
    -- replaces the emoji picker above, and it did so silently — the bind was
    -- gone from hyprctl binds with no error anywhere. Which of the two you want
    -- on that key is a choice, and the reference shell's choice is the emoji
    -- picker, so step with comma instead.
    dispatch(mod .. " + comma", "Previous workspace", "focus", { workspace = "e-1" })
    dispatch(mod .. " + SHIFT + comma", "Next workspace", "focus", { workspace = "e+1" })

    -- Note what is *not* here: SUPER+SHIFT+arrow does not also move the window to
    -- the next workspace. It used to, alongside the swap above, and because a
    -- key bound twice keeps whichever was registered last and says nothing
    -- about the other, one of the two silently did not exist. Sending a window
    -- to another workspace is SHIFT with a number, above; the arrows are for
    -- swapping with the neighbour, which is the action you reach for more.

    -- The wheel moves between existing workspaces, so a gap of several empty
    -- ones is crossed in one notch. mouse_up and mouse_down, not a bare "wheel":
    -- the key has to say which way the wheel turned, or the two binds are
    -- identical apart from their argument and one shadows the other.
    dispatch(mod .. " + mouse_up", "Previous workspace", "focus", { workspace = "e-1" })
    dispatch(mod .. " + mouse_down", "Next workspace", "focus", { workspace = "e+1" })

    -- The focused workspace can also cycle its layout from the keyboard; the
    -- bar's focused workspace button does the same thing on click.
    bind(mod .. " + ALT + L", "Cycle workspace layout", "quickshell ipc call workspaces cycle")

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
    -- The session menu rather than a bare exit: locking, sleeping and leaving
    -- belong on one key, and the two that lose something ask first.
    bind(mod .. " + M", "Session menu", "quickshell ipc call panel toggle session")

    -- The power button means the same thing now: logind is told to ignore it
    -- (modules/system/power.nix), and this is what it opens instead. A long press
    -- still powers off, which is the fallback a stuck session needs.
    bind("XF86PowerOff", "Session menu", "quickshell ipc call panel toggle session")

    -- Super+Shift+M was a second way out through hyprshutdown, which is not
    -- installed: it silently fell back to killing the compositor. One path, and
    -- it is the menu.

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
    --
    -- These arrive as hardware keys, so `locked` lets them through a fullscreen
    -- window. Volume and brightness also repeat: holding the key should slide
    -- rather than move one step. The mute keys and playback controls do not
    -- repeat — they are toggles, and a repeating toggle ends wherever the
    -- key-release happens to leave it.
    --
    -- The volume ceiling is 100%, the same one the panel's slider has. Above
    -- that the slider cannot show the level or bring it back down, and the OSD
    -- — which clamps to 100 — would sit pinned at "100%" while the output kept
    -- getting louder.
    -- ------------------------------------------------------------------
    bind("XF86AudioRaiseVolume", "Volume up",
      "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+", { locked = true, repeating = true })
    bind("XF86AudioLowerVolume", "Volume down",
      "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-", { locked = true, repeating = true })
    -- ALT steps by one point. Tapping ALT and a volume key is how a level is
    -- set exactly, without dragging the slider and without overshooting.
    bind("ALT + XF86AudioRaiseVolume", "Volume up precisely",
      "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 1%+", { locked = true, repeating = true })
    bind("ALT + XF86AudioLowerVolume", "Volume down precisely",
      "wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%-", { locked = true, repeating = true })
    bind("XF86AudioMute", "Mute",
      "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle", { locked = true })
    -- SHIFT on the mute key cycles outputs, the reference's gesture, so moving
    -- between speakers, headphones and HDMI needs no panel and no pointer.
    bind("SHIFT + XF86AudioMute", "Switch audio output", "audio-output-switch", { locked = true })
    bind("XF86AudioMicMute", "Mute microphone",
      "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle", { locked = true })

    bind("XF86AudioPlay", "Play/pause", "playerctl play-pause", { locked = true })
    bind("XF86AudioPause", "Play/pause", "playerctl play-pause", { locked = true })
    bind("XF86AudioNext", "Next track", "playerctl next", { locked = true })
    bind("XF86AudioPrev", "Previous track", "playerctl previous", { locked = true })
    -- SHIFT on the playback keys moves between players — Spotify, a browser
    -- tab, a local player — the way the reference's keys do. It changes what
    -- the shell treats as the active player; it does not change which
    -- application is making noise.
    bind("SHIFT + XF86AudioPlay", "Switch media source",
      "quickshell ipc call media sourceSwitch", { locked = true })
    bind("SHIFT + XF86AudioPause", "Switch media source",
      "quickshell ipc call media sourceSwitch", { locked = true })

    bind("XF86MonBrightnessUp", "Brighter", "brightnessctl set +5%", { locked = true, repeating = true })
    bind("XF86MonBrightnessDown", "Dimmer", "brightnessctl set 5%-", { locked = true, repeating = true })
  '';
}
