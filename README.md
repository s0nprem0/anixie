# nix-dots

A NixOS desktop: Hyprland as the compositor, Quickshell as the shell (bar,
panels, launcher, notifications, OSD, dock), and one palette through all of it.
Built for `2200h`; the shape is reusable, the hardware bits are not.

## Using it

```sh
anixie update          # rebuild and switch (nh elevates itself; asks for a password)
anixie update boot     # build for the next boot (also: test)
anixie <group> --help  # every group documents itself
```

**Commit before rebuilding.** The flake source is the git tree, so untracked
files are invisible to the build — silently, until the shell crash-loops on a
missing import. `anixie update` refuses and names them; `--allow-dirty`
overrides. `git add` is enough to build, but commit before `nh os switch` so the
generation matches the history.

**Going back** is a generation away: pick the previous one in the systemd-boot
menu, or `nixos-rebuild switch --rollback`.

The shell is a systemd user service:

```sh
systemctl --user restart quickshell
journalctl --user -u quickshell -n 50
```

QML errors go to the journal *and* to
`$XDG_RUNTIME_DIR/quickshell/by-id/*/log.qslog`; `console.log` lands only in the
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
shell.qml                 assembly point for the shell's component groups
components/               one widget per file (clock, weather, media, tray, …)
panels/                   panel bodies (media mixer, network, power, displays, …)
Ui/                       shared pieces, hosts and the surface/IPC components:
                          Panel, PanelHero, ShellLayers, ShellOverlays, ShellIpc,
                          Style, Theme, PanelHost
bar.json                  the shipped bar layout
modules.json              where a widget goes when enabled from the menu/CLI
```

## The bar

`bar.json` ships the layout: one bar per screen, same layout everywhere; panels
and hotkeys stay on their display. `tray` entries go to the tray drawer instead
of a permanent slot. The shell writes its own copy on any layout, background,
position or widget change; it **takes precedence** over `bar.json` until reset:

```
~/.local/state/anixie/bar/bar.json
```

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

Position is saved with the layout, so changing it needs no rebuild;
`anixie.wm.quickshell.position` is only the default for fresh state. After a
hand edit, run `anixie bar reload`; the shipped `bar.json` changes only with a
rebuild. The same controls live in **Menu → Setup → Bar**.

Widgets resolve through `ModuleRegistry` and `modules.json`: a section, a source
file and optional settings, so showing one the default layout omits is a
manifest line, not code. **Menu → Setup → Plugins** toggles them without editing
JSON.

The weather follows the machine's IP unless its entry names a place. A city,
postcode or `"lat,lon"` in `location` pins it, which is what a VPN needs:

```json
{ "id": "bar.weather", "interval": 1800, "location": "Malibu, CA" }
```

## Menu

`Super+Space` opens the menu; `Super+Ctrl+C` opens it filtered to capture. The
shipped tree is `modules/features/wm/quickshell/menu.json` and changes with a
rebuild. `~/.config/anixie/menu.json` is a JSONC extension read on every open:
entries merge by group and then label; a match replaces, a new entry appends,
and `"hidden": true` removes.

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

When a typed query is not an app or command, the full menu falls through in
order: arithmetic (`2+3*4` → a copyable `= 14`), a URL (`example.com`), installed
entries, `fd` hits under your home, then a web search. These rows are only in
the full menu; a theme or audio picker stays a fixed list.

`Tab` cycles `all`, `apps`, `web` and `files`. `apps` adds a `most used` section
from launches this shell has counted (`$XDG_STATE_HOME/anixie/app-usage.json`)
and, while the query is empty, live window thumbnails — `Shift+↑`/`Shift+↓`
walks them and Return focuses one. `web` and `files` narrow the same suggestions
to that tab.

## Panels

One per widget, opening under it. A screen shows one panel at a time: opening
another replaces it, while panels on other outputs stay. Arrows walk controls,
Return activates, ←/→ move a slider or pick a chip, Tab moves to the next
screen's panel, Escape closes the focused one, and `Super+Ctrl+1-9` toggles by
position from the left.

| Hotkey | Panel |
| --- | --- |
| `Super+Ctrl+A` | Media & audio (now playing, transport, output/input, app volumes, devices) |
| `Super+Ctrl+W` | Network (scan, DNS, share by QR) |
| `Super+Ctrl+B` | Bluetooth |
| `Super+Ctrl+D` | Display (brightness, text size) |
| `Super+Ctrl+Shift+D` | Displays (arrangement, layout/mirror, scale, rotation, mode, placement, on/off) |
| `Super+Ctrl+P` | Power (profile, brightness, battery, system) |
| `Super+Ctrl+Alt+D` | Calendar |

The media widget opens the same media & audio panel. Notifications and the
forecast panel open from their widgets and have no key of their own.

Right-click a bar widget for a small action menu; right-click the desktop for
terminal, files, theme, screen-time and lock. Tray icons keep their own
application menu (the app supplies it over DBusMenu).

## Calendar

The clock's month view (`Super+Ctrl+Alt+D`) can show a read-only calendar
subscription. Put the `.ics` URL in `~/.config/anixie/calendar.json` — the one
calendar file you edit, deliberately outside the store:

```json
{
  "urls": [
    "https://calendar.example.test/private/basic.ics",
    { "name": "Work", "url": "https://example.test/work.ics" }
  ],
  "refreshMinutes": 30
}
```

The panel fetches into `~/.cache/anixie/calendar`, expands recurring events,
and marks days with a dot plus the selected day's list. A failed refresh keeps
the cached copy and warns instead of blanking the view. Nothing is written back
to the calendar, and the secret URL leaves the config only for the subscription
server. Disable the feature with `anixie.wm.calendar.enable = false`.

## Multiple displays

Every output has its own bar, workspace row and panels. Scale, rotation, mode,
position, on/off and mirroring are per output in
`~/.local/state/anixie/display.conf`; `hyprland/config/20-settings.lua` supplies
defaults for a screen with no saved line (`anixie.wm.display.defaultScale`, 1).

The Displays panel (`Super+Ctrl+Shift+D`) draws the live arrangement and offers
Identify, which flashes each output's name. Mirroring is a per-screen Layout
choice; a mirrored screen has no geometry, so those rows stay disabled until it
is extended.

A geometry change goes through `monitors try`: immediate, but reverted after
fifteen seconds unless kept. The panel shows the countdown, and a systemd timer
owns the revert, so an unreadable mode returns even if the panel is gone.

Workspaces are per monitor: each output gets a block of ten global workspace
ids, so `Super+1` is the first workspace of whichever screen has focus, and
`Super+Comma` / the wheel stay inside that block. The mapping lives in
`~/.local/state/anixie/workspaces.json` and is re-synced on hotplug.

```sh
monitors try HDMI-A-1 mode 1920x1080@60.00  # auto-reverts after 15s
monitors keep                               # keep the try, write it to state
monitors revert                             # undo a try now
monitors set HDMI-A-1 position auto-right   # or XxY
monitors set HDMI-A-1 mirror eDP-1          # none to extend again
monitors identify                           # flash each output's name on it
monitors brightness up 5                    # DDC/CI when focus is external
monitors lid close | open                   # clamshell path
monitors workspaces sync | show | reset
monitors recover                            # clear a stale internal-off state
monitors wake                               # DPMS off/on after a dark resume
```

Closing the lid with an external screen removes the internal panel from the
layout; opening it restores the saved scale. Booting undocked clears a stale
internal-off state before Hyprland reads it, so the laptop screen cannot come up
disabled as the only display.

## Themes

`themes.json` holds the palette tokens — background, surface containers,
outline, semantic accents, ANSI derivation — plus metadata such as the mode,
family and paired light/dark variant; everything else is derived. Light and dark
palettes switch the same surfaces; GTK follows the mode through gsettings
(adw-gtk3/adw-gtk3-dark and Papirus/Papirus-Light icons, with Papirus folder
colours following the palette).

### Appearance panel

The palette glyph on the bar, `Super+Ctrl+T`, `Super+Ctrl+Space`, the menu, the
desktop context menu, or `anixie appearance` all open the same panel. It carries
the current wallpaper and thumbnail strip, the preset list with colour swatches,
favorites and pinning, wallpaper generation/navigation, glass and bar-background
controls, wallpaper palette mode, live-video pause, and a theme doctor shortcut.
Right-click a preset to toggle its favorite; favorites sort first.

### Commands

```sh
anixie appearance               # open the appearance panel
anixie theme list | set NAME | next | prev | current
anixie theme state              # the saved appearance state as JSON
anixie theme migrate            # import the old separate state files
anixie theme favorite add|remove|toggle NAME
anixie theme pin|unpin          # keep automatic switching from changing the theme
anixie theme export             # print a Nix snippet for the current choice
anixie theme doctor             # check the live state and generated files
anixie theme cursor-size N      # set the cursor size at runtime
anixie theme wallpaper [FILE] [auto|light|dark]  # palette from a picture
anixie theme wallpaper-mode [auto|light|dark]    # remember the next mode
anixie theme auto               # apply the scheduled light/dark variant
anixie textsize up|down|set N   # the whole shell, not just the bar
anixie wallpaper library [--json]  # pictures found in the configured folders
anixie wallpaper set FILE       # add a picture and use it
anixie wallpaper use FILE [--output NAME]  # choose for one output or all
anixie wallpaper next|prev [--random] | rotate
anixie wallpaper pause|resume|status  # live video wallpapers
```

### What updates when

- **Live:** the shell, Hyprland borders, kitty, tmux, the wallpaper, the XDG
  settings portal (light/dark and accent), and the cursor size.
- **Next start:** Qt applications, Helix, yazi, btop, hyprlock, and the share
  picker. GTK settings and colour scheme update live; GTK CSS overrides are read
  when the application starts.
- **Hooks:** anything executable under `~/.config/anixie/theme-hooks/` runs after
  every switch with `ANIXIE_THEME`, `ANIXIE_MODE`, `ANIXIE_BG`, `ANIXIE_FG`,
  `ANIXIE_SURFACE`, `ANIXIE_MUTED`, `ANIXIE_PRIMARY`, `ANIXIE_ACCENT`,
  `ANIXIE_ACCENT_ALT`, `ANIXIE_SECONDARY`, `ANIXIE_TERTIARY`, `ANIXIE_YELLOW`,
  `ANIXIE_DANGER`, `ANIXIE_ERROR`, `ANIXIE_SUCCESS`, `ANIXIE_OUTLINE`,
  `ANIXIE_SURFACE_CONTAINER`, `ANIXIE_SURFACE_VARIANT`, `ANIXIE_BG_DARK`,
  `ANIXIE_BG_LIGHT`, and `ANIXIE_FG_LIGHT`.

`theme doctor` reports missing generation files, an invalid palette, unresolved
placeholders and malformed wallpaper state. `theme export` prints the current
preset so a runtime choice can be made the build default.

`theme wallpaper` uses matugen's smart mode unless `light` or `dark` is given,
and falls back to the previous palette on an unreadable picture. Results are
cached per picture and mode (a video contributes its first frame). An explicit
`auto`/`light`/`dark` is remembered for the next picture, and
`theme set wallpaper` reuses the last generated palette. Naming a picture also
records it as the current background, so the palette and the wallpaper stay in
step. While `wallpaper` is the theme, `anixie wallpaper` also regenerates the
palette.

The terminal gets the full 16-colour ANSI palette, so kitty, the zsh prompt, fzf,
bat and eza follow the theme, not just the background. GTK also gets
palette-derived `gtk.css`, beyond the light/dark switch.

Wallpapers are resolved per output and stored in `wallpapers.json`; the shell
reads the resulting `background.json`. Stills are drawn by the shell, videos by
`mpvpaper`, and generated gradients match each output's resolution. The lock
screen shows a still frame for a video wallpaper, and a display that is plugged
in or changes resolution is re-applied automatically. The library scans
`~/Pictures/Wallpapers`, `~/Pictures` and the per-theme folder by default.
Set `anixie.theme.wallpaper.default` to a picture to use it wherever neither the
theme nor an output has a choice; a runtime `anixie wallpaper use` still wins.

### Options

- `anixie.theme.theme` — the build-time default preset.
- `anixie.theme.wallpaper.dirs`, `.extraDirs` and `.recursive` — where the
  library scans.
- `anixie.theme.wallpaper.default` — picture used when nothing else is chosen;
  `null` keeps the generated palette gradient.
- `anixie.theme.auto.schedule.enable`, `.light`, `.dark` — automatic day/night
  switching; the timer is installed by Home Manager.
- `anixie.theme.auto.rotation.enable`, `.interval`, `.shuffle` — wallpaper
  rotation.
- `anixie.theme.kvantum.enable` — opt-in Kvantum style using the built-in
  KvAdapta light/dark theme; Qt6ct remains the default platform theme.

Scheduled switching and rotation are off by default. Pinning a theme makes
`theme auto` leave it alone.

### Checking a change

```sh
nix flake check
anixie theme doctor
anixie theme set gruvbox-dark
anixie theme set catppuccin-latte
anixie wallpaper use ~/Pictures/example.jpg --output eDP-1
anixie wallpaper pause && anixie wallpaper status && anixie wallpaper resume
```

Multi-monitor, video backends and portal consumers still need a live session;
the generated files can be inspected with `anixie theme state` and
`anixie wallpaper current --json`.

## Everything else

```
anixie shot [smart|region|windows|fullscreen|scroll] [copy|save|annotate|redact|text]
anixie record                       # screen recording, webcam overlay, transcode
anixie clipboard | emoji | menu | pick | reminder
anixie toggle [dnd|idle|nightlight|stayawake]
anixie focus start 25 | stop | extend 15 | status
anixie screentime [show|json|reset|path|panel]
notify -G f017 SUMMARY [BODY] --exec COMMAND [ARG...]   # a toast with a glyph and a click action
notify SUMMARY [BODY] --action LABEL CMD [ARG...]... --with DATA...  # up to three persistent buttons
anixie power …                      # profile for AC or battery
anixie snapshot create|list|restore|prune
anixie webapp add NAME URL          # a site as an application
```

OCR is `capture-text` (`Super+Ctrl+Print`): drag a region, the text is on the
clipboard.

`Super+Ctrl+V` opens clipboard history with a preview: image thumbnails, text
with character/line/word counts, and paths with `go to location`. `Delete`
removes an entry, `clear all` wipes the history, and Return or a click copies.
The history is cliphist's.

`shot scroll` selects a region, pages down with Page Down, and stitches the
frames, stopping when the view stops moving. `shot smart redact` opens satty
with the blur tool, and `shot smart text` with the text tool.

## Screen time, focus and battery

Screen time is tracked from the focused toplevel and idle monitor into one JSON
file per day under `~/.local/state/anixie/screentime`. The bar's screen-time clock
opens the breakdown; `anixie screentime` prints it and `screentime panel` shows
it (adding the widget to a saved layout that lacks it).

`anixie focus start 25` closes the app classes in
`anixie.wm.focus.blockedClasses`, silences notifications, and shows a countdown.
State survives a shell restart; `focus stop` restores the previous notification
setting. `Super+Ctrl+F` starts a 25-minute block, `Super+Ctrl+Shift+F` stops one.

The default profile is `performance` on mains and `power-saver` on battery
(`anixie.power.acProfile` and `anixie.power.batteryProfile`; use
`anixie power set battery balanced` for more responsiveness). Power-saver also
lowers the platform profile and EPP, which is the largest idle-power saving
available without leaving the machine sluggish at a desk.

While on battery the power watcher dims the screen and steps down the profile at
20%, then 8%, restoring your brightness on mains. Thresholds, profiles and
brightness are `anixie.power.batteryAutomation` options; they also drive the
bar's warning colour and the low-battery notification. The power panel toggles
automation; that choice is stored in
`~/.local/state/anixie/powerprofile/automation` and overrides the build default.

The watcher coalesces the battery's udev event stream and acts only when the
source, charge state or percentage actually changes. UPower still polls the
battery every 30 seconds, which is enough for the thresholds.

Charging is left to the firmware: there is no charge ceiling or threshold
service to keep in sync, so the battery charges normally to 100%.

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

- **No disk encryption.** It needs a reinstall; see above.
- **sudo asks for a password**; `wheelNeedsPassword = false` is one line away if
  a rebuild prompt is worse than the risk.
- **The Craft Apps run under XWayland** — Wayland has no native file
  drag-and-drop, so their desktop entries clear `WAYLAND_DISPLAY`.
- **Performance is more than the daemon's profile.** While `performance` is
  selected, a system service also forces the GPU's DPM level high, turns off
  PCIe ASPM, caps dirty page cache at 512M and disables the NMI watchdog, then
  restores every value on any other profile. Outside that profile the kernel
  starts with `pcie_aspm.policy=powersave` and `nmi_watchdog=0`, and the battery
  default is `power-saver`. `anixie power show` reports the active profile.
- **`nix flake check` is the gate.** shellcheck over every module script,
  qmllint over the assembled QML tree, and nixfmt/statix/deadnix over the Nix.
  A headless start is not part of it.
- **Saved matches are machine-specific** — the hostname, backlight and keyboard
  backlight are named in `hosts/vivobook` and the Quickshell bar settings.
