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

-- The shell's own surfaces. Layer blur is opt-in per namespace; without
-- these the bar and the popups render sharp over a blurred desktop.
for _, namespace in ipairs({
  "quickshell",
  "quickshell-panel",
  "quickshell-context",
  "quickshell-context-curtain",
  "quickshell-dock",
  "quickshell-osd",
  "quickshell-notifications",
  "quickshell-picker",
  "quickshell-capture-preview",
}) do
  hl.layer_rule({
    name = "blur-" .. namespace,
    match = { namespace = namespace },
    blur = true,
    ignore_alpha = 0.01,
  })
end

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
