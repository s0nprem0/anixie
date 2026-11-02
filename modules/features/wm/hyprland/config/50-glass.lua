-- ------------------------------------------------------------------
-- Glass
--
-- Soft frosted glass with subtle refraction.
-- Prioritizes readability, clean surfaces, and restrained highlights.
-- ------------------------------------------------------------------

if hl.plugin.hyprglass then
  local mode = theme_mode()
  local light = mode == "light"
  local accent = tonumber("0x" .. "@ACCENT_HEX@") or 0xf6bc70

  -- Subtle accent tint in dark mode; neutral glass in light mode.
  local tint_color = light
    and 0xffffff08
    or (accent * 0x100 + 0x12)

  hl.plugin.hyprglass.config({
    enabled = glass_enabled,
    default_theme = mode,
    default_preset = "clear",

    tint_color = tint_color,
    brightness = 0.9,

    light = {
      brightness = 1.0,
      contrast = 0.96,
      saturation = 0.92,
      vibrancy = 0.08,
      vibrancy_darkness = 0.0,
      adaptive_dim = 0.0,
      adaptive_boost = 0.12,
    },

    layers = {
      enabled = glass_enabled and 1 or 0,
    },
  })

  -- Quickshell surfaces that should receive glass.
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
    hl.plugin.hyprglass.layer(namespace, {
      preset = "clear",
    })
  end

  -- Main glass preset.
  hl.plugin.hyprglass.preset("clear", {
    -- Frosted background
    blur_strength = 0.8,
    blur_iterations = 4,

    -- Restrained optical effects
    refraction_strength = 0.25,
    chromatic_aberration = 0.08,
    fresnel_strength = 0.3,
    specular_strength = 0.35,
    lens_distortion = 0.0,

    -- Surface appearance
    glass_opacity = 0.82,
    edge_thickness = 1,

    -- Dark theme
    dark = {
      brightness = 0.88,
      contrast = 0.92,
      saturation = 0.9,
      vibrancy = 0.25,
      vibrancy_darkness = 0.08,
      adaptive_dim = 0.12,
      adaptive_boost = 0.05,
    },

    -- Light theme
    light = {
      brightness = 1.0,
      contrast = 0.96,
      saturation = 0.92,
      vibrancy = 0.08,
      vibrancy_darkness = 0.0,
      adaptive_dim = 0.0,
      adaptive_boost = 0.12,
    },
  })

  -- Hyprglass handles blur for these shell surfaces.
  -- Avoid stacking Hyprland blur on top of glass.
  if glass_enabled then
    -- Only Quickshell's own windows need this: their blur is handled by
    -- Hyprglass, and Hyprland's own blur would otherwise run on top of it.
    -- Unrelated applications keep their normal blur.
    hl.window_rule({
      name = "prevent-double-blur",
      match = {
        class = "^quickshell",
      },
      no_blur = true,
    })
  end
end
