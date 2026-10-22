# nix-dots

A NixOS desktop: Hyprland as the compositor, Quickshell as the shell (bar,
panels, launcher, notifications, OSD, dock), and one palette through all of it.
Built for `vivobook`; the shape is reusable, the hardware bits are not.

## Using it

```sh
anixie update          # rebuild and switch (nh elevates itself; asks for a password)
anixie update boot     # build for the next boot (also: test)
anixie <group> --help  # every group documents itself
```

**Commit before rebuilding.** The flake source is the git tree, so an uncommitted
file is invisible to the build — which is silent: the panels that reference it
ship, the file they import does not, and the shell crash-loops. Staging is
enough for `nix build`, but commit before `nh os switch`.

**Going back** is a generation away: pick the previous one in the systemd-boot
menu, or `nixos-rebuild switch --rollback`.

**If the keyboard stops behaving**, the Lua config's binds cannot be removed by
`hyprctl reload`. `./revert-hyprland.sh` points `~/.config/hypr` back at the
hyprlang files from the running build (or from a path you pass it) and reloads;
it lives outside the flake on purpose, so it still works when a build is the
thing that is broken.

The shell is a systemd user service:

```sh
systemctl --user restart quickshell
journalctl --user -u quickshell -n 50
```

QML errors go to the journal *and* to
`/run/user/1000/quickshell/by-id/*/log.qslog`; QML `console.log` lands in the
latter, interleaved with service noise.

## What is where

```
hosts/vivobook/           the machine: hardware, boot, hostname
modules/system/           NixOS side: users, audio, network, boot, lock, snapshots
modules/features/         per-user side
  applications/           packaged apps, one directory each
  cli/                    the `anixie` front door
  power/                  power profiles per source
  shell/                  zsh, git, helix, kitty, yazi, tools
  theming/                palettes, templates, and the commands that apply them
  wm/                     Hyprland, Quickshell, capture, clipboard, picker, toggles
    quickshell/           the shell itself (see below)
```

Quickshell's tree:

```
shell.qml                 every surface: bar, OSD, dock, notifications, picker
components/               one widget per file (clock, weather, media, tray, …)
panels/                   panel bodies (audio, network, power, displays, …)
Ui/                       shared pieces: Panel, PanelHero, SliderField, ChoiceRow,
                          Toggle, Dropdown, ScrollBar, Style, Theme, PanelHost
bar.json                  the shipped bar layout
modules.json              where a widget goes when enabled from the menu/CLI
```

## The bar

`bar.json` ships the layout. One bar is drawn on every connected screen, with the
same layout on each; panels and their hotkeys use the display they belong to.
The shell writes its own copy when the layout or the background changes:

```
~/.local/state/anixie/bar/bar.json
```

which **takes precedence** over `bar.json` until you reset it:

```sh
anixie bar reset                  # back to the shipped layout
anixie bar move bar.bell center 0 # move by id, section, index
anixie bar enable bar.media       # put a widget back (manifest decides where)
anixie bar disable bar.bell       # take it off; the place it came from is kept
anixie bar background glassy      # clear | glassy | opaque (also double-click)
anixie bar tray                   # open the tray drawer (parked widgets)
anixie bar toggle|on|off          # hide the bar, keeping panels and hotkeys
```

Widgets are looked up in `ModuleRegistry`, then in `modules.json` — a widget is a
section, a source file and optional settings, so one the default layout does not
show is one line in the manifest rather than a code change.

## Panels

One per widget, opening under it, several at once. Arrows walk the controls,
Return activates, ←/→ move a slider or a pick a chip, Tab moves to the next open
panel, Escape closes the one the keys are on, and `Super+Ctrl+1-9` toggles a panel
by its position from the left.

| Hotkey | Panel |
| --- | --- |
| `Super+Ctrl+A` | Audio |
| `Super+Ctrl+W` | Network (scan, DNS, share by QR) |
| `Super+Ctrl+B` | Bluetooth |
| `Super+Ctrl+D` | Display (brightness, text size) |
| `Super+Ctrl+Shift+D` | Displays (per-output scale, rotation, on/off) |
| `Super+Ctrl+P` | Power (profile, brightness, battery, system) |
| `Super+Ctrl+Alt+D` | Calendar |

Media, notifications and the forecast panel open from their widgets and have no
key of their own.

## Themes

`themes.json` holds ten colours per palette; everything else is derived.

```sh
anixie theme list | set NAME | next | prev | current
anixie textsize up|down|set N   # the whole shell, not just the bar
anixie wallpaper set FILE       # or `wallpaper theme` for the palette's gradient
```

A theme switched at runtime reaches the **shell, Hyprland's borders and kitty
immediately**. Helix, yazi, btop, tmux, the lock screen, GTK and Qt are generated
at build time — their configs are store symlinks, which is what makes them
reproducible and what stops a runtime write — so they follow on the next rebuild.

## Everything else

```
anixie shot [smart|region|windows|fullscreen] [copy|save|annotate]
anixie record                       # screen recording, webcam overlay, transcode
anixie clipboard | emoji | menu | pick | reminder
anixie toggle [dnd|idle|nightlight|stayawake]
anixie display …                    # monitors: scale, mirror, status
anixie power …                      # profile for AC or battery
anixie snapshot create|list|restore|prune
anixie webapp add NAME URL          # a site as an application
```

OCR is `capture-text` (`Super+Ctrl+Print`): drag a region, the text is on the
clipboard.

## Things worth knowing

- **No disk encryption.** A fresh install decision that is still open.
- **sudo asks for a password**; `wheelNeedsPassword = false` is one line away if
  a rebuild prompt is worse than the risk.
- **PhotoCraft runs under XWayland** — Wayland has no native file drag-and-drop,
  so its desktop entry clears `WAYLAND_DISPLAY`.
- **Performance is more than the daemon's profile.** While `performance` is
  selected, a system service also forces the GPU's DPM level high, turns off
  PCIe ASPM, caps dirty page cache at 512M and disables the NMI watchdog, then
  puts every value back on any other profile. `anixie power show` reports it.
- **`nix flake check` is the gate.** It runs `shellcheck -S warning` over every
  module script, `qmllint` over the assembled QML tree (with the Qt and
  Quickshell import paths, so a syntax error fails before the shell
  crash-loops), and nixfmt, statix and deadnix over the Nix code. A headless
  start is still not part of it.
- **Saved matches are for this machine.** The hostname, backlight device and
  keyboard backlight are named in `hosts/vivobook` and
  `modules/features/wm/quickshell/bar.json`-adjacent settings.
