-- ------------------------------------------------------------------
-- Plugin settings
--
-- The values are the reference shell's. The plugins are out-of-tree, so
-- every use is guarded: a plugin that failed to build or load should leave
-- the rest of the desktop working, not abort this config.
-- ------------------------------------------------------------------
hl.config({
  plugin = {
    scrolloverview = {
      gesture_distance = 300,
      scale = 0.65,
      workspace_gap = 2,
      layout = "vertical",
      wallpaper = 0,
      blur = true,
    },

    dynamic_cursors = {
      enabled = true,
      mode = "tilt",
      threshold = 1,
      rotate = {
        length = 20,
        offset = 0.0,
      },
      tilt = {
        limit = 5000,
        activation = "negative_quadratic",
        window = 100,
        full = 60,
      },
      shake = {
        enabled = false,
        threshold = 6.0,
        base = 4.0,
        speed = 4.0,
        influence = 0.0,
        limit = 0.0,
        timeout = 2000,
        effects = false,
        ipc = false,
      },
      hyprcursor = {
        nearest = 1,
        enabled = true,
        resolution = -1,
        fallback = "clientside",
      },
    },

    hypr_edgehover = {
      enabled = 1,
      edges = "lrtb",
      inset = 1,
      max_distance = 0,
      keyboard_focus = -1,
      gap_pass = "hover,click,scroll,keyboard",
      layer_pass = "hover,keyboard",
      layer_namespaces = "",
      overhang_pass = "hover,keyboard",
      overhang_threshold = 8,
      overhang_edge_width = 0,
      steal_edge_width = 2,
      zones_top = "0-100",
      zones_bottom = "0-100",
      zones_left = "0-100",
      zones_right = "0-100",
    },

    -- Title bars belong to floating windows only. The patch this build
    -- carries enforces that in the compositor; the setting here is what
    -- the plugin reads when it makes the decision.
    --
    -- The colours are read from the live palette, like the borders are, so a
    -- `theme set` recolours the bars on the reload it triggers instead of
    -- leaving them on the palette the flake was built with. The placeholders
    -- remain the fallback for a session that has no palette file yet.
    hyprbars = {
      enabled = true,
      only_floating = true,
      hide_fullscreen = true,
      bar_height = 25,
      bar_color = theme_colour("surface", "@SURFACE_RGBA_FF@"),
      col = {
        text = theme_colour("foreground", "@FG_RGBA_FF@"),
      },
      -- A fresh window is too bright a chip on an unfocused bar; a faint
      -- muted tint keeps the button findable without competing with the text.
      inactive_button_color = theme_colour("muted", "@MUTED_RGBA_AA@", "22"),
      bar_text_font = "FiraCode Nerd Font",
      bar_text_size = 10,
      bar_text_weight = 600,
      bar_text_align = "left",
      bar_padding = 10,
      bar_button_padding = 8,
      bar_title_enabled = true,
      bar_part_of_window = false,
      bar_blur = false,
    },
  },
})

if hl.plugin.hyprbars then
  hl.plugin.hyprbars.add_button({
    bg_color = "rgba(00000000)",
    fg_color = theme_colour("danger", "@DANGER_RGBA_FF@"),
    size = 14,
    icon = "X",
    action = "hyprctl dispatch 'hl.dsp.window.close()'",
  })
end
