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
