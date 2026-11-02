-- ------------------------------------------------------------------
-- Startup
-- ------------------------------------------------------------------
local function sync_displays()
  -- Give every connected output a block of ten workspaces and write the mapping
  -- the bar reads. Re-running it after a hotplug keeps a returning dock on the
  -- same numbers instead of renumbering the screens already attached.
  hl.exec_cmd("monitors workspaces sync >/dev/null")
  hl.exec_cmd("monitors lid reconcile >/dev/null")
end

-- Held so the one-shot timer survives until it fires.
local display_timer = nil
local function schedule_sync()
  display_timer = hl.timer(function()
    sync_displays()
    -- The shell watches its screen list and re-applies the wallpaper for a new
    -- or resized output. Only fill in when it is not reachable (restart,
    -- crash): a second apply would restart a video wallpaper for no reason.
    -- `quickshell ipc` answers only while the shell is actually running, which
    -- a process-name check cannot promise.
    hl.exec_cmd("sh -c 'quickshell ipc call background current >/dev/null 2>&1 || wallpaper apply >/dev/null'")
  end, { timeout = 500, type = "oneshot" })
end

hl.on("hyprland.start", function()
  sync_displays()

  -- cliphist is fed both kinds of clipboard, so a screenshot copied with
  -- Super+Shift+C is in the history alongside any copied text. The wrapper
  -- drops selections that password managers mark as secrets.
  hl.exec_cmd("app-launch @CLIPBOARD_WATCH@")

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

  -- The plain Hyprland session entry (upstream's start-hyprland) has no
  -- session manager behind it, so nothing starts graphical-session.target.
  -- That target is not a cosmetic grouping: xdg-desktop-portal carries
  -- Requisite=graphical-session.target, so the portal refuses to activate
  -- ("Dependency failed for Portal service"), and every unit installed with
  -- WantedBy=graphical-session.target -- the bar, the lock bridge, the theme
  -- and power helpers -- stays down. Starting it directly is refused
  -- (RefuseManualStart=yes), so this starts anixie-session.target instead,
  -- which binds to it; a dependency start is what systemd allows.
  --
  -- Under UWSM the target is already active and this is a no-op.
  hl.exec_cmd("systemctl --user start --no-block anixie-session.target")
end)

-- A dock appearing or disappearing changes the set of active outputs. Sync the
-- block mapping and re-assert the workspace rules; the bar picks up the written
-- mapping on its own.
-- Wait a moment before asking: the event can arrive before the new output is
-- visible to hyprctl. The bar re-reads the mapping on its own shortly after.
hl.on("monitor.added", schedule_sync)
hl.on("monitor.removed", schedule_sync)
