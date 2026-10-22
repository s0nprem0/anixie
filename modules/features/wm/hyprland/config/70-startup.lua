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
  hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_ID")
end)
