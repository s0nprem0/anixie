-- ------------------------------------------------------------------
-- Session
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
bind(mod .. " + CTRL + L", "Lock", "quickshell ipc call lock lock")

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
