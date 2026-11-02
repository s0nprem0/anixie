-- ------------------------------------------------------------------
-- Environment
--
-- Set in the compositor rather than through Home Manager's session
-- variables: these have to reach everything a bind starts, and a session
-- variable is exported by the login shell, which a compositor-launched app
-- never runs.
--
-- hl.env(name, value) sets one variable before the display server initialises.
-- Hyprland stores the value literally: there is no shell parsing, so `;` and
-- `,` stay part of the value (they are fallback lists for Qt/GTK, not
-- separators). The value is not shell-quoted and must not be quoted as if it
-- were a shell assignment. The variable is placed in Hyprland's own
-- environment and propagated to every process Hyprland launches; Hyprland also
-- pushes it into the systemd and D-Bus activation environments unless
-- HYPRLAND_NO_SD_VARS is set. Removing a name here therefore removes it from
-- child processes too.
--
-- Groups below are by toolkit/application family. Mandatory variables are
-- required for the Wayland-first session to work; optional compatibility
-- overrides are marked as such and can be dropped on a non-NixOS or
-- single-toolkit system.
-- ------------------------------------------------------------------

-- NixOS-specific compatibility (mandatory on NixOS, meaningless elsewhere).
-- NIXOS_OZONE_WL is consumed by the NixOS Chromium/Electron wrappers and
-- enables their Ozone/Wayland backend. It has no effect on other distros; keep
-- it only for NixOS configurations.
hl.env("NIXOS_OZONE_WL", "1")

-- Qt (mandatory fallback chain). Qt tries the platforms in order: Wayland
-- first, then XCB. Both plugins are provided by qtbase/qtwayland in this
-- configuration.
hl.env("QT_QPA_PLATFORM", "wayland;xcb")

-- GTK (mandatory fallback chain). GTK tries the backends in order: Wayland
-- first, then X11. Both are provided by the installed GTK 3/4 builds.
hl.env("GDK_BACKEND", "wayland,x11")

-- Electron/Chromium (optional compatibility override). ELECTRON_OZONE_PLATFORM_HINT
-- asks Electron to choose its Ozone backend automatically; NIXOS_OZONE_WL above
-- is what actually enables Wayland in the NixOS-wrapped Chromium/Electron. This
-- is redundant where the wrapper already passes --ozone-platform-hint, but harmless.
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- Intentionally not set globally:
--   QT_WAYLAND_DISABLE_WINDOWDECORATION: disabling Qt's client-side decorations
--   removes title bars/buttons from ordinary Qt applications. Hyprland here
--   draws no server-side title bars, so the global setting would leave Qt apps
--   without usable window controls. Scope it to the individual applications that
--   need it (e.g. via a window rule or a per-app launcher) instead.
--   MOZ_ENABLE_WAYLAND: the installed Firefox wrapper already sets this to 1 by
--   default, so setting it here is redundant.