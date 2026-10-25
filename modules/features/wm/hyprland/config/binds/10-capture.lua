-- ------------------------------------------------------------------
-- Capture
--
-- Keys and modes are the reference shell's, so the habits carry across.
--
-- Every bind that opens the picker goes through `capture`, which is what
-- enters the "picker" submap for the duration. A bind that calls `shot`
-- directly still takes the shot, but Return, Tab and the arrows — the whole
-- keyboard side of the picker — are only bound inside the submap, so they do
-- nothing. That is why every one of them is wrapped, not just PRINT.
--
-- PRINT is spelled as a keysym. No keycode, no leading comma, and none of
-- the positional-field trouble that made it a workaround in hyprlang.
-- ------------------------------------------------------------------
bind_handler("PRINT", "Screenshot", capture("shot smart"))

-- The same capture as PRINT, for a keyboard without a Print key. This key
-- used to splice a shell conditional together around the command, which
-- rendered as `if command -v shot; then shot; else shot; fi smart` — `fi`
-- followed by an argument, a shell syntax error, so the key did nothing.
bind_handler(mod .. " + SHIFT + S", "Screenshot", capture("shot smart"))

bind_handler(mod .. " + SHIFT + W", "Screenshot pick window", capture("shot windows"))

-- Fullscreen capture is SUPER+SHIFT+G, not SUPER+SHIFT+F: in the reference
-- shell F is the file manager, and two binds on one key means one of them
-- is never going to work.
--
-- No picker, so no submap: the monitor is already known and there is nothing
-- to aim at.
bind(mod .. " + SHIFT + G", "Screenshot fullscreen", "shot fullscreen")

-- Straight to the clipboard, for pasting a screenshot into whatever is
-- focused. Still a picker — "smart copy" means pick, then copy.
bind_handler(mod .. " + SHIFT + C", "Screenshot to clipboard", capture("shot smart copy"))

-- Marked up before it is saved: handed to satty, which opens already in crop
-- mode, so this crops and annotates rather than capturing everything and
-- then waiting to be told what to do.
--
-- ALT, not CTRL: the reference shell puts the media & audio panel on SUPER+CTRL+A, and
-- the panel keys are a set worth keeping together — A, W, B, D, P below. This
-- key had CTRL only because SUPER+SHIFT+A was taken by the lock at the time,
-- which is no longer true; ALT keeps it clear of the whole panel group. It is
-- also in the capture menu, so nothing depends on this key existing.
bind_handler(mod .. " + ALT + A", "Screenshot annotation", capture("shot smart annotate"))

-- The colour under the pointer, as a hex code. hyprpicker does this on its
-- own; pkill first, because one left running would eat the next press.
bind(mod .. " + PRINT", "Color picker", "pkill -x hyprpicker 2>/dev/null; hyprpicker -a")

-- The text inside a region, OCR'd to the clipboard.
bind_handler(mod .. " + CTRL + PRINT", "Extract text", capture("capture-text"))

-- The whole menu, filtered to the capture entries. The family has grown past
-- what is worth a key each, and this is how the rest stay reachable.
--
-- A plain bind, not one of the `capture` wrappers above. Those enter the
-- picker submap around the command, which is right when the command *is* the
-- picker — but the menu opens the picker for a region and then hands off to
-- a detached process, and the wrapper would take the submap back down in the
-- gap between the two. The picker enters it itself now, so the wrapper is
-- only a backstop, and this path does not want one.
bind_global(mod .. " + CTRL + C", "Capture menu", "menu-capture")

-- Shrink a picture or a video before sending it. No picker of its own — it
-- asks the shell for the file, the format and the size — so it is a plain
-- bind.
bind(mod .. " + CTRL + PERIOD", "Transcode", "transcode")

-- ------------------------------------------------------------------
-- Recording
--
-- ALT+PRINT starts one, or stops the one that is running — the same key both
-- ways, like PRINT for screenshots. It asks about audio first, then opens the
-- same picker as a screenshot, so the region keys are already known.
--
-- Wrapped in `capture` because it *is* the picker: it needs the submap up for
-- Return and the arrows. When the key is stopping a recording instead, the
-- submap goes up and straight back down, which is harmless.
-- ------------------------------------------------------------------
bind_handler(mod .. " + ALT + PRINT", "Screen record", capture("record"))

-- The overlay is resized while a recording runs, not chosen up front, so these
-- are plain binds rather than anything the picker owns.
--
-- `[` and `]` by keysym name: bracketleft and bracketright are what the X11
-- keysym table calls them, and Hyprland takes the name, not the character.
bind(mod .. " + ALT + bracketleft", "Webcam overlay smaller", "webcam-overlay resize smaller")
bind(mod .. " + ALT + bracketright", "Webcam overlay larger", "webcam-overlay resize larger")
