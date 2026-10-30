-- ------------------------------------------------------------------
-- Universal clipboard
--
-- macOS puts copy, cut, paste and select-all on one modifier, and the same
-- chords work in every application. Linux splits them: GUI apps take
-- CTRL+C/V/X/A, terminals take CTRL+SHIFT+C/V (CTRL+C is an interrupt and
-- CTRL+V is literal-next). These binds make SUPER the one modifier and send
-- whichever chord the focused surface expects.
--
-- The key events are synthesized with send_key_state rather than wtype: the
-- physically held SUPER merges into an injected chord, and send_key_state
-- targets the focused surface, so the menu's search field works too. The
-- down/up split works around Hyprland sometimes leaving synthetic key state
-- stuck or repeating after a single send.
--
-- SUPER+CTRL+V remains the shell's clipboard history (binds/00-launch.lua).
-- ------------------------------------------------------------------

-- Terminals are identified by class, not by title. Add a class here when
-- another terminal is installed; kitty is the only one this machine ships.
local terminal_classes = {
  kitty = true,
}

local function active_window_is_terminal()
  local window = hl.get_active_window()
  return window ~= nil and terminal_classes[window.class] == true
end

local function send_shortcut_once(mods, key)
  return function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))
    hl.timer(function()
      hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
    end, { timeout = 50, type = "oneshot" })
  end
end

-- Copy and paste differ in a terminal: CTRL+SHIFT+C/V is kitty's text
-- clipboard, while CTRL+C would interrupt the process and CTRL+V is meant
-- to reach the application so agent harnesses can read an image.
local function copy_or_paste(key)
  return function()
    if active_window_is_terminal() then
      send_shortcut_once("CTRL SHIFT", key)()
    else
      send_shortcut_once("CTRL", key)()
    end
  end
end

bind_handler(mod .. " + A", "Select all", send_shortcut_once("CTRL", "A"))
bind_handler(mod .. " + C", "Copy", copy_or_paste("C"))
bind_handler(mod .. " + X", "Cut", send_shortcut_once("CTRL", "X"))
bind_handler(mod .. " + V", "Paste", copy_or_paste("V"))
