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
  power/                  power profiles per source, battery thresholds
  shell/                  zsh, git, helix, neovim, kitty, yazi, tools
  theming/                palettes, templates, and the commands that apply them
  wm/                     Hyprland, Quickshell, capture, clipboard, picker, toggles
    hyprland/config/      the compositor's Lua, one section per file (concatenated)
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
Entries under the `tray` section are parked in the tray drawer instead of taking
a permanent slot on the bar.
The shell writes its own copy when the layout, background, position, or a widget setting changes:

```
~/.local/state/anixie/bar/bar.json
```

which **takes precedence** over `bar.json` until you reset it:

```sh
anixie bar reset                  # back to the shipped layout
anixie bar move bar.bell center 0 # move by id, section, index
anixie bar position bottom        # top | bottom | left | right
anixie bar set bar.clock format "HH:mm"  # one widget's setting
anixie bar get bar.clock format   # read it back (JSON)
anixie bar modules                # the catalog: id, section, on/off
anixie bar reload                 # re-read the saved layout from disk
anixie bar enable bar.media       # put a widget back (manifest decides where)
anixie bar disable bar.bell       # take it off; the place it came from is kept
anixie bar background glassy      # clear | glassy | opaque (also double-click)
anixie bar tray                   # open the tray drawer (parked widgets)
anixie bar toggle|on|off          # hide the bar, keeping panels and hotkeys
```

Position is saved with the layout too, so a switch does not need a rebuild. The
Nix option `anixie.wm.quickshell.position` is the default a fresh state starts
from. After editing the saved layout by hand, run `anixie bar reload`; the
shipped `bar.json` still changes only with a rebuild. The same controls are in
**Menu → Setup → Bar**.

Widgets are looked up in `ModuleRegistry`, then in `modules.json` — a widget is a
section, a source file and optional settings, so one the default layout does not
show is one line in the manifest rather than a code change. **Menu → Setup →
Plugins** lists what can be enabled or disabled without editing JSON.

The weather follows the machine's IP unless its entry names a place. A city,
postcode or `"lat,lon"` in `location` pins it instead, which is what a VPN needs:

```json
{ "id": "bar.weather", "interval": 1800, "location": "Malibu, CA" }
```

## Menu

`Super+Space` opens the shell's menu; `Super+Ctrl+C` opens it filtered to
capture. The shipped tree is `modules/features/wm/quickshell/menu.json` and
changes with a rebuild. `~/.config/anixie/menu.json` is a JSONC extension read on
every open: entries merge by group name, and by label within a group. A matching
entry replaces the shipped one, a new one is appended, and `"hidden": true`
removes it.

```json
{
  "entries": [
    { "label": "Open dots", "run": "app-launch kitty -e hx ~/nix-dots" },
    {
      "group": "Style",
      "entries": [
        { "label": "Previous theme", "hidden": true }
      ]
    }
  ]
}
```

The same tree is scriptable:

```sh
menu --list                 # every row
menu --list Setup           # one group
menu --only Capture         # open only that group
menu firefox                # launch an application by name
```

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

Right-click a bar widget for a small action menu; right-click the desktop for
terminal, files, theme, screen-time and lock. Tray icons keep their own
application menu (the app supplies it over DBusMenu).

## Themes

`themes.json` holds ten colours and a mode per palette; everything else is
derived. Light and dark palettes switch the same surfaces; GTK follows the mode
through gsettings (Adwaita/Adwaita-dark and Papirus/Papirus-Light icons).

```sh
anixie theme list | set NAME | next | prev | current
anixie theme wallpaper [FILE] [auto|light|dark]  # palette from a picture
anixie theme wallpaper-mode [auto|light|dark]    # remember the next mode
anixie textsize up|down|set N   # the whole shell, not just the bar
anixie wallpaper set FILE       # or `wallpaper theme` for the palette's gradient
```

A theme switched at runtime reaches the **shell, Hyprland's borders, kitty, btop
and tmux immediately**. GTK follows through its state settings.ini and gsettings,
Qt through a qt6ct palette, and Helix, yazi and the lock screen through their
state-directory configs; those applications take the change at their next start.
No rebuild is needed for a theme switch. `theme wallpaper` uses matugen's smart mode unless `light` or
`dark` is named, and falls back to the previous palette if the picture cannot be
read. Results are cached per picture and mode, and a video contributes its first
frame. `theme wallpaper` remembers an explicit `auto`/`light`/`dark` choice for
the next picture; `theme set wallpaper` reuses the last generated palette. While
`wallpaper` is the current theme, choosing a background through `anixie
wallpaper` also regenerates the palette from it.

The terminal gets the full 16-colour ANSI palette, so kitty, the zsh prompt,
fzf, bat and eza follow the theme rather than only the terminal background. GTK
also gets palette-derived `gtk.css` files, not just the Adwaita light/dark
switch. The picker previews a palette's colours as a small swatch.

Applications without a supported config format can be reached through
`~/.config/anixie/theme-hooks/*.sh`. Each executable hook runs after a switch
with `ANIXIE_THEME`, `ANIXIE_MODE`, and the palette colours in the environment.

## Everything else

```
anixie shot [smart|region|windows|fullscreen|scroll] [copy|save|annotate|redact|text]
anixie record                       # screen recording, webcam overlay, transcode
anixie clipboard | emoji | menu | pick | reminder
anixie toggle [dnd|idle|nightlight|stayawake]
anixie focus start 25 | stop | extend 15 | status
anixie screentime [show|json|reset|path|panel]
notify -G f017 SUMMARY [BODY] --exec COMMAND [ARG...]   # a toast with a glyph and a click action
anixie display …                    # monitors: scale, mirror, status
anixie power …                      # profile for AC or battery
anixie snapshot create|list|restore|prune
anixie webapp add NAME URL          # a site as an application
```

OCR is `capture-text` (`Super+Ctrl+Print`): drag a region, the text is on the
clipboard.

`shot scroll` selects a region, pages down with Page Down, and stitches the
frames, stopping when the view stops moving. `shot smart redact` opens satty
with the blur tool, and `shot smart text` with the text tool.

## Screen time, focus and battery

Screen time is tracked in the shell from the focused toplevel and the idle
monitor, and written one JSON file per day under
`~/.local/state/anixie/screentime`. The bar's screen-time clock opens the
breakdown; `anixie screentime` prints it, and `screentime panel` opens the panel
(adding the widget to a saved bar layout that predates it).

`anixie focus start 25` closes the app classes listed in
`anixie.wm.focus.blockedClasses`, silences notifications, and shows a
countdown indicator. The state survives a shell restart; `focus stop` puts the
previous notification setting back. `Super+Ctrl+F` starts a 25-minute block and
`Super+Ctrl+Shift+F` stops one.

While on battery, the power watcher dims the screen and steps down the profile
at 20% and again at 8%, restoring the brightness you had when mains returns.
The thresholds, profiles and brightness levels are
`anixie.power.batteryAutomation` options.

## Gaming

`anixie.gaming` installs Steam and enables GameMode; `anixie.applications.gaming` adds
gamescope, mangohud, protonup-qt, and (by default) Lutris, Heroic and RetroArch.
Steam is a system package because Proton and older titles need 32-bit graphics,
which `hardware.graphics.enable32Bit` turns on.

Steam launch options: `mangohud %command%` for the overlay, `gamescope --
%command%` for compositing. Remote Play and a gamescope session are off by
default (`anixie.gaming.steam.remotePlay`, `anixie.gaming.steam.gamescopeSession`).

## Secrets and disk encryption

sops-nix is wired but off by default. To use it:

```sh
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt   # public key is printed
cp .sops.yaml.example .sops.yaml            # put the public key in it
sops secrets/secrets.yaml                   # add the keys named in the module
```

Then set `anixie.secrets.enable = true` and declare the files under
`anixie.secrets.secrets`. The age key stays outside the store; only the encrypted
`secrets/secrets.yaml` is committed.

The machine is **not encrypted**. LUKS cannot be added to a running root
filesystem declaratively: back up, reinstall with LUKS, and then pin the device
with `anixie.security.luks` (see `modules/system/encryption.nix`) or let
`nixos-generate-config` write the `boot.initrd.luks.devices` entry. Enabling that
module on an unencrypted root makes the machine unbootable.

## Things worth knowing

- **No disk encryption yet.** Adding it needs a reinstall; see the secrets and
  encryption section above.
- **sudo asks for a password**; `wheelNeedsPassword = false` is one line away if
  a rebuild prompt is worse than the risk.
- **The Craft Apps run under XWayland** — Wayland has no native file
  drag-and-drop, so their desktop entries clear `WAYLAND_DISPLAY`.
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
