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
bind(mod .. " + CTRL + A", "Media & audio panel", "quickshell ipc call panel toggle audio")
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
-- Omarchy also puts the theme picker on CTRL+T, which is quicker once the
-- gesture is learned; both stay bound rather than moving a key that is already
-- in muscle memory.
bind(mod .. " + CTRL + SHIFT + SPACE", "Theme picker", "theme")
bind(mod .. " + CTRL + T", "Theme picker", "theme")

-- The background picker, next to the theme picker. `wallpaper` with no argument
-- lists the generated background and the pictures for the current theme; it is
-- the same command the shell's desktop context menu calls.
bind(mod .. " + CTRL + SPACE", "Wallpaper picker", "wallpaper")
