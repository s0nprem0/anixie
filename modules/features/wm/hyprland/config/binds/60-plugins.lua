-- ------------------------------------------------------------------
-- Layout and overview plugins
--
-- These are handlers rather than execs: the plugin call runs inside the
-- compositor, so there is no process to start and no IPC round-trip before
-- the animation begins. Every one is guarded, because a plugin that did not
-- load should leave the key doing nothing rather than aborting the config.
-- ------------------------------------------------------------------
bind_handler(mod .. " + D", "Toggle tiling and floating", function()
  if hl.plugin.layoutmode then hl.plugin.layoutmode.toggle() end
end)

bind_handler(mod .. " + TAB", "Mission control", function()
  if hl.plugin.hymission then hl.plugin.hymission.toggle() end
end)

bind_handler("ALT + TAB", "Window overview", function()
  if hl.plugin.scrolloverview then hl.plugin.scrolloverview.overview("toggle") end
end)

bind(mod .. " + CTRL + ALT + G", "Toggle glass", "glass-toggle")

-- ------------------------------------------------------------------
-- Scratchpad
-- Keeps its window alive and hidden while every other workspace stays
-- empty. Good for a long-running terminal.
--
-- SUPER+grave rather than SUPER+TAB: TAB is mission control now, and a key
-- with two meanings is one that silently loses one of them.
--
-- toggle_special takes the bare name: it applies the "special:" prefix
-- itself, and passing one is rejected.
-- ------------------------------------------------------------------
dispatch(mod .. " + grave", "Scratchpad", "workspace.toggle_special", "special")
