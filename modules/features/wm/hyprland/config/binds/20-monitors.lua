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
