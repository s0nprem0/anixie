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

dispatch(mod .. " + CTRL + H", "Resize left", "window.resize", { x = -10, y = 0, relative = true })
dispatch(mod .. " + CTRL + L", "Resize right", "window.resize", { x = 10, y = 0, relative = true })
dispatch(mod .. " + CTRL + K", "Resize up", "window.resize", { x = 0, y = -10, relative = true })
dispatch(mod .. " + CTRL + J", "Resize down", "window.resize", { x = 0, y = 10, relative = true })

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
dispatch(mod .. " + Q", "Close window", "window.close")

dispatch(mod .. " + F", "Fullscreen", "window.fullscreen", { action = "toggle" })

-- Float lives on T, not V. V is the universal paste key now (see
-- binds/55-clipboard.lua); T is free and is where the reference puts tile/float.
dispatch(mod .. " + T", "Float", "window.float", { action = "toggle" })

-- pseudo-tile turns the window into a column the group resizes as a unit;
-- pin floats a window above everything regardless of focus order.
dispatch(mod .. " + P", "Pseudo-tile", "window.pseudo")
dispatch(mod .. " + SHIFT + P", "Pin window", "window.pin", { action = "toggle" })

-- ------------------------------------------------------------------
-- Workspaces
-- 1-5 jump, and SHIFT with the same sends the window along too. The number is
-- per monitor: `monitors workspace 2` resolves the focused screen's block, so
-- Super+2 is the second workspace on whichever display has focus.
-- ------------------------------------------------------------------
for i = 1, 5 do
  bind(mod .. " + " .. i, "Workspace " .. i, "monitors workspace " .. i)
  bind(mod .. " + SHIFT + " .. i, "Send to workspace " .. i, "monitors move-window " .. i)
end

-- Comma and shift+comma step within the focused monitor's block. `e-1` / `e+1`
-- would walk the global workspace list and cross to another screen; the block
-- is what makes each monitor's 1-10 independent.
--
-- Not period. Hyprland key names are case-insensitive, so PERIOD and period
-- are the same keysym: binding workspace stepping to period unbinds and
-- replaces the emoji picker above, and it did so silently — the bind was
-- gone from hyprctl binds with no error anywhere. Which of the two you want
-- on that key is a choice, and the reference shell's choice is the emoji
-- picker, so step with comma instead.
bind(mod .. " + comma", "Previous workspace", "monitors workspace-step prev")
bind(mod .. " + SHIFT + comma", "Next workspace", "monitors workspace-step next")

-- Note what is *not* here: SUPER+SHIFT+arrow does not also move the window to
-- the next workspace. It used to, alongside the swap above, and because a
-- key bound twice keeps whichever was registered last and says nothing
-- about the other, one of the two silently did not exist. Sending a window
-- to another workspace is SHIFT with a number, above; the arrows are for
-- swapping with the neighbour, which is the action you reach for more.

-- The wheel steps within the focused monitor's block. mouse_up and mouse_down,
-- not a bare "wheel": the key has to say which way the wheel turned, or the two
-- binds are identical apart from their argument and one shadows the other.
bind(mod .. " + mouse_up", "Previous workspace", "monitors workspace-step prev")
bind(mod .. " + mouse_down", "Next workspace", "monitors workspace-step next")

-- The focused workspace can also cycle its layout from the keyboard; the
-- bar's focused workspace button does the same thing on click.
bind(mod .. " + ALT + L", "Cycle workspace layout", "quickshell ipc call workspaces cycle")
