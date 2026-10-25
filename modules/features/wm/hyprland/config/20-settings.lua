-- ------------------------------------------------------------------
-- Settings
--
-- The border colours come from the resolved palette the `theme` command writes,
-- so `theme set` recolours the borders on the `hyprctl reload` it triggers. Read
-- at config load because Hyprland has no runtime call for either and a
-- build-time value cannot change without a rebuild.
--
-- The built-in colours below are the fallback, used when the file is not there
-- or does not name something usable. `alpha` is the two-digit alpha to append,
-- so a caller that wants a faint variant of a token does not have to parse the
-- live colour itself.
-- ------------------------------------------------------------------
local function theme_colour(token, fallback, alpha)
  local state_home = os.getenv("XDG_STATE_HOME")
    or ((os.getenv("HOME") or "") .. "/.local/state")
  local file = io.open(state_home .. "/anixie/theme/live/palette.json", "r")
  if not file then return fallback end

  local raw = file:read("a")
  file:close()

  -- The palette is JSON, which is not Lua: quoted keys and no trailing commas,
  -- so it cannot simply be loaded. Pull the one field out instead.
  local hex = raw:match('"' .. token .. '"%s*:%s*"(#%x%x%x%x%x%x)"')
  if not hex then return fallback end

  local r, g, b = hex:match("#(%x%x)(%x%x)(%x%x)")
  return "rgba(" .. r .. g .. b .. (alpha or "ff") .. ")"
end

-- Whether the live theme is light or dark. Written next to the palette by
-- `theme`, and read at config load for the glass theme.
local function theme_mode()
  local state_home = os.getenv("XDG_STATE_HOME")
    or ((os.getenv("HOME") or "") .. "/.local/state")
  local file = io.open(state_home .. "/anixie/theme/live/mode", "r")
  if not file then return "dark" end

  local value = file:read("l")
  file:close()
  if value and value:gsub("%s+", "") == "light" then return "light" end
  return "dark"
end

-- Glass is decided by a state file rather than a build-time flag, because
-- the plugin's config is read at load time and the toggle has to survive a
-- reload. No file means on, so a fresh install starts with the look the
-- plugin is there for.
local function glass_state()
  local state_home = os.getenv("XDG_STATE_HOME")
    or ((os.getenv("HOME") or "") .. "/.local/state")
  local file = io.open(state_home .. "/anixie/glass", "r")
  if not file then return true end

  local value = file:read("l")
  file:close()
  return value == nil or value:gsub("%s+", "") ~= "false"
end
local glass_enabled = glass_state()

hl.config({
  general = {
    -- The scrolling layout is what the keybinds and the overview plugins
    -- are built around: a row of columns you move along, rather than a
    -- tree that reflows every time a window opens.
    layout = "scrolling",

    gaps_in = 2,
    gaps_out = 2,
    border_size = 1,
    resize_on_border = true,

    ["col.active_border"] = theme_colour("primary", "@PRIMARY_RGBA_FF@"),
    ["col.inactive_border"] = theme_colour("muted", "@MUTED_RGBA_AA@"),
  },

  scrolling = {
    column_width = 0.6,
    follow_focus = true,
    direction = "right",
    fullscreen_on_one_column = true,
    wrap_focus = false,
    wrap_swapcol = false,
  },

  decoration = {
    rounding = 0,
    rounding_power = 0,

    -- Glass is a compositor effect, so ordinary opacity would double it.
    -- When it is off the plugin is not drawing, and the windows get the
    -- slight translucency the shell has everywhere else.
    active_opacity = glass_enabled and 1.0 or 0.97,
    inactive_opacity = glass_enabled and 1.0 or 0.94,

    dim_inactive = true,
    dim_strength = 0.08,
    dim_special = 0.4,

    shadow = {
      enabled = false,
      range = 6,
      render_power = 2,
    };

    blur = {
      enabled = true,
      new_optimizations = true,
      size = 4,
      passes = 2,
      contrast = 1.5,
      brightness = 0.8,
      vibrancy = 0,
      vibrancy_darkness = 0,
      popups = true,
    };
  },

  animations = {
    enabled = true;
  };

  -- Keep the split direction when a window opens or closes, so the layout
  -- does not reshuffle itself around every change.
  dwindle = {
    preserve_split = true;
  };

  input = {
    kb_layout = "us",
    follow_mouse = 1;
    touchpad = {
      natural_scroll = true;
    };
  },

  -- 300ms between wheel notches is long enough to feel ignored; 150 still
  -- debounces a free-spinning wheel. The scratchpad belongs to the
  -- workspace it was opened on, so switching away should hide it.
  binds = {
    scroll_event_delay = 150;
    hide_special_on_workspace_change = true;
  };

  -- The shell draws the wallpaper on its background layer; Hyprland's own
  -- default would flash over it. The logo and splash are off for the same
  -- reason: the shell is already up by the time the first frame is drawn.
  misc = {
    force_default_wallpaper = 0;
    disable_hyprland_logo = true;
    disable_splash_rendering = true;

    -- A blanked output should come back on the first key or mouse movement
    -- rather than waiting for a click. The logind listener's resume path
    -- normally does this itself; these cover a DPMS state set by anything else.
    key_press_enables_dpms = true;
    mouse_move_enables_dpms = true;
  };
})

-- The catch-all rule: native mode, automatic placement, and the scale set by
-- `anixie.wm.display.defaultScale`. On this 1080p laptop that is 1, which gives
-- a full 1920x1080 workspace rather than 1280x720; `auto` is there for a
-- machine whose first panel is HiDPI.
--
-- This is a fallback for every output, and it is what a monitor that has never
-- been configured gets. The `monitors` command changes one output and writes
-- the choice to a state file; the rules below read that file back and re-assert
-- the settings, which is the only way a choice made at runtime can outlive a
-- config reload. There is no runtime monitor dispatcher to ask, and
-- `hyprctl keyword` is refused outright by the Lua config manager.
--
-- The catch-all stays static. Runtime changes never rewrite it, so changing one
-- screen's scale cannot leak into another, and a saved per-output rule always
-- wins because it is loaded after this one.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = @MONITOR_DEFAULT_SCALE@ })

-- The saved settings, one rule per output that has any. Read with io rather
-- than through a helper because Hyprland exposes no config reader, and io is
-- available to the config: it is the same Lua state `hyprctl eval` runs in.
--
-- A line is `output scale transform disabled mirror position mode`. Fields
-- were added over time: a two-field line predates rotation and on/off, a
-- four-field line predates mirroring, and a five-field line predates position
-- and mode. Missing fields fall back to no rotation, the output on, not
-- mirroring, auto placement, and preferred mode, so an older file keeps its
-- scales without being rewritten.
--
-- Every field has to look right before it is used. A hand-edited or truncated
-- file should not be able to ask Hyprland for an output name, a scale, a
-- transform, a position or a mode that nothing here knows about, so a malformed
-- line is skipped rather than passed on.
do
  local state_home = os.getenv("XDG_STATE_HOME")
    or ((os.getenv("HOME") or "") .. "/.local/state")
  local file = io.open(state_home .. "/anixie/display.conf", "r")

  local function output_name(value)
    return value ~= nil and value:match("^[%w%-%._]+$") ~= nil
  end

  local function position_ok(value)
    return value == "auto"
      or value:match("^auto%-[%a]+$") ~= nil
      or value:match("^%-?%d+x%-?%d+$") ~= nil
  end

  local function mode_ok(value)
    return value == "preferred"
      or value == "highres"
      or value == "highrr"
      or value == "maxwidth"
      or value:match("^%d+x%d+$") ~= nil
      or value:match("^%d+x%d+@[%d%.]+$") ~= nil
  end

  if file then
    for line in file:lines() do
      local output, scale, transform, disabled, mirror, position, mode =
        line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)$")
      if not output then
        output, scale, transform, disabled, mirror, position =
          line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)$")
      end
      if not output then
        output, scale, transform, disabled, mirror =
          line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)$")
      end
      if not output then
        output, scale, transform, disabled =
          line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)$")
      end
      if not output then
        output, scale = line:match("^(%S+)%s+(%S+)$")
      end

      local scale_value = tonumber(scale)
      local transform_value = tonumber(transform or "0")
      local disabled_value = disabled or "0"
      local mirror_value = mirror or "none"
      local position_value = position or "auto"
      local mode_value = mode or "preferred"

      if
        output_name(output)
        and scale_value
        and scale_value > 0
        and scale:match("^%d+%.?%d*$")
        and transform_value
        and transform_value % 1 == 0
        and transform_value >= 0
        and transform_value <= 7
        and (disabled_value == "0" or disabled_value == "1")
        and (mirror_value == "none" or output_name(mirror_value))
        and position_ok(position_value)
        and mode_ok(mode_value)
      then
        hl.monitor({
          output = output,
          mode = mode_value,
          position = position_value,
          scale = scale_value,
          transform = transform_value,
          disabled = disabled_value == "1",
          mirror = mirror_value == "none" and "" or mirror_value,
        })
      end
    end
    file:close()
  end
end
