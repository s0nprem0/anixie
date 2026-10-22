-- ------------------------------------------------------------------
-- Glass
--
-- The layer names are this shell's, not the reference's: every surface
-- Quickshell makes declares its own namespace, and glass has to be told
-- which ones are allowed to refract.
-- ------------------------------------------------------------------
if hl.plugin.hyprglass then
  local accent = tonumber("0x" .. "@ACCENT_HEX@") or 0xf6bc70

  hl.plugin.hyprglass.config({
    enabled = glass_enabled,
    default_theme = "dark",
    default_preset = "clear",
    tint_color = accent * 0x100 + 0x22,
    brightness = 0.7,
    layers = {
      enabled = glass_enabled and 1 or 0,
    },
  })

  for _, namespace in ipairs({
    "quickshell",
    "quickshell-panel",
    "quickshell-context",
    "quickshell-context-curtain",
    "quickshell-dock",
    "quickshell-osd",
    "quickshell-notifications",
    "quickshell-picker",
    "quickshell-capture-preview",
  }) do
    hl.plugin.hyprglass.layer(namespace, { preset = "clear" })
  end

  hl.plugin.hyprglass.preset("clear", {
    blur_strength = 0.65,
    blur_iterations = 3,
    refraction_strength = 0.85,
    chromatic_aberration = 1.6,
    fresnel_strength = 0.85,
    specular_strength = 2,
    glass_opacity = 0.65,
    edge_thickness = 2,
    lens_distortion = 1.2,
    dark = {
      brightness = 0.85,
      contrast = 0.8,
      saturation = 0.85,
      vibrancy = 0.6,
      vibrancy_darkness = 0.12,
      adaptive_dim = 0.2,
      adaptive_boost = 0.1,
    },
  })

  -- Glass already blurs what is behind a window; letting Hyprland blur it
  -- as well doubles the effect and washes the edges out.
  if glass_enabled then
    hl.window_rule({
      name = "prevent-double-blur",
      match = { class = ".*" },
      no_blur = true,
    })
  end
end
