-- ------------------------------------------------------------------
-- Environment
--
-- Set in the compositor rather than through Home Manager's session
-- variables: these have to reach everything a bind starts, and a session
-- variable is exported by the login shell, which a compositor-launched app
-- never runs.
--
-- The `;` and `,` in the Qt and GTK values are fallback lists, not typos.
-- ------------------------------------------------------------------
hl.env("NIXOS_OZONE_WL", "1")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("GDK_BACKEND", "wayland,x11")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("MOZ_ENABLE_WAYLAND", "1")
