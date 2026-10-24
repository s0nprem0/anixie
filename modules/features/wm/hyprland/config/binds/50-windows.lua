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
