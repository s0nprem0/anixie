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
-- A focus block, and a way out of it. The shell owns the timer and the
-- blocked-window list (see Ui/FocusHost.qml); these keys only ask it to
-- start or stop, which is why they are plain execs rather than the panel
-- wrappers above.
bind(mod .. " + CTRL + F", "Focus for 25 minutes", "focus start 25")
bind(mod .. " + CTRL + SHIFT + F", "Stop focus", "focus stop")

bind(mod .. " + CTRL + N", "Night light", "toggle nightlight")
bind(mod .. " + CTRL + I", "Stay awake", "toggle idle")
bind(mod .. " + CTRL + comma", "Silence notifications", "toggle dnd")
bind(mod .. " + ALT + comma", "Replay notifications", "quickshell ipc call notify replay")
bind(mod .. " + CTRL + O", "Toggle menu", "toggle")
