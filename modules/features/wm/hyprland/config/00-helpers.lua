local mod = "SUPER"
local terminal = "kitty"

-- Applications go through UWSM's transient-scope helper (installed by
-- hyprland/default.nix), so systemd tracks each one as its own app unit
-- instead of accumulating them in the compositor's cgroup. Short-lived
-- helpers — hyprctl, quickshell ipc, the pickers — deliberately do not:
-- a scope for a process that exits in milliseconds is noise.
local function app(command)
  return "app-launch " .. command
end

-- ------------------------------------------------------------------
-- Bind helpers
--
-- Every bind is described. Hyprland shows the description in its bind
-- listing and some shells read it, so `hyprctl binds` says what a key does
-- instead of only which keys are taken.
--
-- `hl.unbind` first, so re-running this file replaces bindings instead of
-- stacking a second one on top of the first.
--
-- `options` are merged into the bind's table alongside the description, so
-- a hardware key can still ask for `locked` and `repeating`.
-- ------------------------------------------------------------------
local function bind(key, description, command, options)
  hl.unbind(key)

  local opts = { description = description }
  for name, value in pairs(options or {}) do
    opts[name] = value
  end

  hl.bind(key, hl.dsp.exec_cmd(command), opts)
end

-- Same, for a key the shell catches itself as a global shortcut. No process
-- runs between the key and the shell, which is what makes the menu open on
-- the keypress rather than after a `quickshell ipc` call has started up.
local function bind_global(key, description, name)
  hl.unbind(key)
  hl.bind(key, hl.dsp.global("quickshell:" .. name), { description = description })
end

-- Same, for a handler function rather than a shell command.
--
-- The picker binds need the "picker" submap entered and left again around a
-- command, which is two dispatches around one exec — more than `bind`'s
-- single exec_cmd can express. They go through here so they still unbind
-- first and stay idempotent across a reload like every other bind.
local function bind_handler(key, description, handler)
  hl.unbind(key)
  hl.bind(key, handler, { description = description })
end

-- Same, for a dispatcher rather than a shell command.
--
-- The dispatcher is named with dots — "window.move", "focus" — because that
-- is how they read. hl.dsp does not accept that directly: hl.dsp["window.move"]
-- is nil, so the path has to be walked. Getting this wrong fails loudly at
-- config load with "attempt to call a nil value", which is better than the
-- alternative — a bind that registers and silently does nothing.
local function dispatch(key, description, name, args)
  hl.unbind(key)

  local dsp = hl.dsp
  for part in name:gmatch("[^%.]+") do
    dsp = dsp[part]
    if dsp == nil then
      error("no such dispatcher: " .. name .. " (for " .. key .. ")")
    end
  end

  hl.bind(key, args ~= nil and dsp(args) or dsp(), { description = description })
end
