-- ------------------------------------------------------------------
-- Launching
-- ------------------------------------------------------------------
bind(mod .. " + RETURN", "Terminal", app(terminal))

-- The file manager and the system monitor, on Omarchy's keys. Thunar is the
-- default directory handler, so this is the same application a "show in folder"
-- opens; btop runs inside the terminal rather than as a toplevel of its own.
bind(mod .. " + SHIFT + F", "File manager", app("thunar"))
bind(mod .. " + SHIFT + T", "System monitor", app(terminal .. " btop"))

bind_global(mod .. " + SPACE", "Menu", "menu")

-- The same descriptions the menu is built from, as a searchable sheet. Hyprland
-- already carries them (see 00-helpers.lua), so this is a reader over
-- `hyprctl binds` rather than a second list.
bind(mod .. " + SLASH", "Keyboard shortcuts", "shortcuts")

-- Asks how long, then for a message, and the timer it sets keeps running
-- after this shell is gone.
bind(mod .. " + R", "Reminder", "reminder -i")

-- This used to be SHIFT+V. Unbind the old key explicitly so a reload in a
-- running session does not leave both shortcuts behind.
hl.unbind(mod .. " + SHIFT + V")
bind(mod .. " + CTRL + V", "Clipboard history", "clipboard")

-- The emoji picker types the choice into the focused window rather than only
-- copying it, so it lands in the sentence being written instead of having to
-- be pasted.
bind(mod .. " + PERIOD", "Emoji picker", "emoji")

-- The dock. Hyprland drives it, so the bind asks the shell over its IPC
-- rather than writing a flag the shell would notice on a poll — the dock
-- should appear on the keypress, not up to a second later.
bind(mod .. " + SHIFT + D", "Dock", "quickshell ipc call dock toggle")

-- The default browser, whichever it is, opened on its own home page. Not
-- `xdg-open` on its own: with no file or URL it prints its usage and exits,
-- so the key did nothing. xdg-settings names the browser's desktop entry and
-- the menu launches it by id. basename strips the suffix rather than a
-- parameter expansion, whose dollar-brace Nix would take for its own.
bind(mod .. " + SHIFT + RETURN", "Browser",
  "menu \"$(basename \"$(xdg-settings get default-web-browser)\" .desktop)\"")

-- The editor command reads the user's EDITOR, falling back to hx. It has to
-- run in a terminal: EDITOR is hx here, and a TUI started through `uwsm app`
-- alone has no TTY and exits immediately. This is a raw Lua file, not a Nix
-- string, so the dollar-brace needs no escaping to reach the shell.
bind(mod .. " + SHIFT + N", "Editor", app(terminal .. " -e ${EDITOR:-hx}"))
