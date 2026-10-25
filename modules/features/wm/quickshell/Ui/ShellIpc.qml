import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// Every IPC target the shell exposes. Keeping them in one object makes the
// command surface readable in one place; the windows and bar state they call
// into live in their own components.
Item {
  // The dock is the one thing Hyprland drives rather than the shell, so it needs
  // a way in from the compositor. IPC rather than a polled flag file: the toggle
  // should take effect on the keypress, not on the next tick.
  IpcHandler {
    target: "dock"

    function toggle(): void { DockHost.toggle() }
    function show(): void { DockHost.show() }
    function hide(): void { DockHost.hide() }
  }

  // The bar itself: hide and show it without touching the shell, so panels and
  // hotkeys keep working and only the pixels change hands.
  //
  // `on` and `off` rather than `show` and `hide`, because `show` is a subcommand
  // of `quickshell ipc` itself — `ipc call bar show` prints the target listing
  // instead of calling anything. The dock target has the same trap in its own
  // `show`; its bind uses `toggle`, so nothing has hit it yet.
  IpcHandler {
    target: "bar"

    function toggle(): void { BarContext.toggle() }
    function on(): void { BarContext.shown = true }
    function off(): void { BarContext.shown = false }

    // Rearranging from a script, which is what a drag persists and what makes
    // the saved layout testable without a pointer.
    function move(id: string, section: string, index: string): void {
      BarConfig.move(id, section, Number(index))
    }
    function reset(): void {
      PanelHost.closeAll()
      BarConfig.reset()
    }
    function background(mode: string): void { BarConfig.setBackground(mode) }
    function position(value: string): string {
      const changed = BarContext.position !== value
      if (!BarConfig.setPosition(value)) {
        return "position must be top, bottom, left or right"
      }
      // Moving the edge replaces the bar surface the panels are anchored to;
      // closing them is better than leaving them attached to a destroyed item.
      if (changed) PanelHost.closeAll()
      return "ok"
    }

    // Per-widget settings. A value that parses as JSON becomes a number or
    // boolean; everything else stays text, so `format "dddd HH:mm"` and
    // `interval 600` both land in the shape the widget reads.
    function set(id: string, key: string, value: string): string {
      let parsed = value
      try {
        const candidate = JSON.parse(value)
        if (candidate !== null && typeof candidate !== "object") parsed = candidate
      } catch (e) {
      }
      const existed = BarConfig.settingOf(id, key) !== undefined
      if (!BarConfig.setSetting(id, key, parsed)) {
        return "no widget called \"" + id + "\" on the bar"
      }
      return existed ? "ok" : "ok (new setting)"
    }

    // The current value of one widget setting, as JSON. Useful from a shell and
    // the source for the menu's checked rows.
    function get(id: string, key: string): string {
      const value = BarConfig.settingOf(id, key)
      return value === undefined ? "" : JSON.stringify(value)
    }

    function reload(): void {
      PanelHost.closeAll()
      BarConfig.reload()
    }

    // The widget catalog, for `anixie bar modules`: known widgets with their
    // current section and state, one tab-separated row each.
    function modules(): string {
      const ids = BarConfig.knownModules()
      return ids.map(function (id) {
        return id + "\t" + BarConfig.sectionFor(id) + "\t"
          + (BarConfig.isEnabled(id) ? "on" : "off")
      }).join("\n")
    }

    // Taking a widget off the bar and putting it back. The place it came from is
    // remembered, so `enable` restores rather than appends; a widget that was
    // never on the bar goes where modules.json says.
    function enable(id: string): void { BarConfig.enable(id) }
    function disable(id: string): void { BarConfig.disable(id) }

    // The tray drawer, for a script or a key: what a click on the parked count
    // opens.
    function tray(): void {
      if (BarContext.trayItem) BarContext.trayItem.toggleDrawer()
    }
  }

  // The panels, by name, for their hotkeys.
  //
  // One function taking a name rather than six named ones: the name is what the
  // widget registers itself under, and `panel toggle audio` reads the same as the
  // bind that calls it. A name nothing registered logs a warning and does nothing,
  // which is what a panel that is not on the bar should do.
  IpcHandler {
    target: "panel"

    function toggle(name: string): void { PanelRegistry.toggle(name) }
    function names(): string { return PanelRegistry.names().join(" ") }

    // The nth panel from the left, for Super+Ctrl+1-9: the number is the order the
    // icons sit on the bar, not the order the widgets registered in.
    function position(number: string): void { PanelRegistry.togglePosition(number) }

    // Everything, which is what `close` has always meant here.
    function close(): void { PanelHost.closeAll() }
  }

  // Workspace layout, on the focused monitor.
  //
  // The state lives in the Workspaces widget, one per bar. Registering this
  // handler there registered one per output and only one could win, so
  // `Super+Alt+L` could cycle a workspace on the display that was not focused.
  // There is one handler here; it asks that widget (see Ui/WorkspacesHost.qml).
  IpcHandler {
    target: "workspaces"

    function cycle(): void { WorkspacesHost.cycle() }
    function refresh(): void { WorkspacesHost.refresh() }
  }

  // What the shell is actually drawing with. The theme follows a state file on
  // its own, so this is how you check that it did rather than taking a screenshot
  // and squinting at it.
  IpcHandler {
    target: "theme"

    function set(name: string): void { Theme.set(name) }

    // A palette that was made after the shell was built, handed over whole.
    function palette(json: string): void { Theme.setCustom(json) }
    function current(): string { return Theme.name }
    function list(): string { return Theme.names().join(" ") }
  }

  // The global text size, by multiplier. The `textsize` command writes the state
  // file and calls this, so a running shell resizes at once and a restarted one
  // comes back on the saved value.
  IpcHandler {
    target: "text"

    function set(scale: string): void { Style.setTextScale(scale) }
    function current(): string { return String(Style.textScale) }
  }

  // Silencing notifications, for the `toggle` command's key.
  //
  // The daemon lives in this shell, so there is nothing to write to disk and
  // nothing to watch — the switch is a call in, and `status` is the call back
  // out, which is what stops the bar and the key from disagreeing.
  // The bar's indicators for state that lives outside the shell. `toggle` and
  // `reminder` call these after they change something, so the bar is told rather
  // than asking (see Ui/IndicatorHost.qml for why the night light is still read).
  IpcHandler {
    target: "indicator"

    function nightlight(temperature: string): void { IndicatorHost.setNightlight(temperature) }
    function idle(state: string): void { IndicatorHost.setIdle(state) }
    function stayawake(state: string): void { IndicatorHost.setStayAwake(state) }
    function reminders(count: string): void { IndicatorHost.setReminders(count) }
  }

  IpcHandler {
    target: "notify"

    function toggle(): void { NotificationHost.toggle() }
    function status(): string { return NotificationHost.doNotDisturb ? "on" : "off" }
    function dismissAll(): void { NotificationHost.dismissAll() }
    function dismissOne(): string { return NotificationHost.dismissOne() }
    function invokeLast(): string { return NotificationHost.invokeLast() }
    function count(): string { return NotificationHost.count() }
    function replay(): void { NotificationHost.replay() }
    function showHistory(): void { NotificationHost.replay() }
    function closeReplay(): void { NotificationHost.closeReplay() }
  }

  // Moving the media widget between players, for the source-switch keys. The
  // choice is MediaHost's, so this is the same switch the popup's player list
  // makes — a key and a click cannot disagree about which player is current.
  IpcHandler {
    target: "media"

    function playPause(): void { MediaHost.playPause() }
    function trackNext(): void { MediaHost.trackNext() }
    function trackPrevious(): void { MediaHost.trackPrevious() }

    function sourceSwitch(): void { MediaHost.next() }
    function sourceSwitchPrevious(): void { MediaHost.previous() }
  }

  // The OSD as a service: anything that can run `quickshell ipc` can ask for a
  // readout without owning a window. The payload matches Omarchy's OSD — icon
  // name, message, optional value/max, progress text and duration — so a script
  // written for one desktop works on the other.
  IpcHandler {
    target: "osd"

    function show(payload: string): string { OsdHost.showPayload(payload); return "ok" }
    // `show` collides with the ipc CLI's own `show` subcommand, which turns
    // `ipc call osd show <payload>` into a target listing. Scripts use this
    // alias; the direct function stays for anything that speaks the socket.
    function payload(payload: string): string { OsdHost.showPayload(payload); return "ok" }
    function close(): string { OsdHost.hide(); return "ok" }
    function state(): string { return OsdHost.opened ? "open" : "closed" }
  }

  // The display-name overlay, for the Displays panel and `monitors identify`.
  // Not `show`: that is an `ipc` subcommand, and the OSD target already has a
  // scar from it.
  IpcHandler {
    target: "identify"

    function flash(): string { IdentifyHost.flash(); return "ok" }
  }

  // The wallpaper path, for the `wallpaper` command and for scripts. Setting it
  // writes the state file too, so a change made here survives a shell restart.
  IpcHandler {
    target: "background"

    function set(path: string): string { BackgroundHost.set(path); return "ok" }
    function video(path: string): string { BackgroundHost.setVideo(path); return "ok" }
    function reload(): string { BackgroundHost.reload(); return "ok" }
    function current(): string { return BackgroundHost.path }
  }

  // The session lock and the idle cycle. `unlock` is deliberately available to
  // the user's own processes: it is the recovery path from a TTY if the lock UI
  // itself is misbehaving, and anyone who can run it already has the session.
  IpcHandler {
    target: "lock"

    function lock(): string { LockHost.lock(); return "ok" }
    function unlock(): string { LockHost.unlock(); return "ok" }
    function suspend(): string { LockHost.lockAndSuspend(); return "ok" }
    function fallback(): string { LockHost.fallbackLock(); return "ok" }
    function status(): string { return LockHost.locked ? "locked" : "unlocked" }
    function isLocked(): string { return LockHost.locked ? "true" : "false" }
  }

  IpcHandler {
    target: "idle"

    function status(): string { return IdleHost.enabled ? "on" : "off" }
    function toggle(): string { return IdleHost.toggle() }
    function on(): string { return IdleHost.setEnabled(true) }
    function off(): string { return IdleHost.setEnabled(false) }
  }

  // Focus mode and screen time. Both are shell-owned because both depend on
  // things only the shell already watches: the toplevel list and the idle
  // monitor.
  IpcHandler {
    target: "focus"

    function start(minutes: string): string { return FocusHost.start(minutes) }
    function extend(minutes: string): string { return FocusHost.extend(minutes) }
    function stop(): string { return FocusHost.stop() }
    function status(): string { return FocusHost.status() }
  }

  IpcHandler {
    target: "screentime"

    function status(): string { return ScreentimeStore.json() }
    function reset(): string { ScreentimeStore.reset(); return "ok" }
  }

  // What `shot` calls in through, after it has saved a capture. Driven by the
  // capture rather than by a key of its own, so a screenshot taken from a shell or
  // from the capture menu previews the same way one taken from Print does.
  //
  // `recording` is the same idea for the record dot: `record` says when a
  // recording starts and stops instead of the bar asking it every 1.5 seconds.
  IpcHandler {
    target: "capture"

    function preview(path: string): void { CapturePreview.reveal(path) }
    function togglePin(): void { CapturePreview.togglePin() }
    function hide(): void { CapturePreview.hide() }
    function recording(state: string): void { RecorderHost.set(state === "start") }
  }

  // What `pick` calls in through, and what the menu calls for itself.
  //
  // One entry point taking the path to a file holding the whole request: the
  // entries, the prompt and what to run afterwards all arrive together, and a
  // caller that had to make three separate calls could be half-served by a shell
  // that restarted between them. A file rather than the JSON itself because a
  // single argument is capped at 128KB and the emoji list is past it.
  IpcHandler {
    target: "pick"

    function open(path: string): string { return PickHost.open(path) }
  }

  // The menu, for scripts and for checking it without a picker on screen.
  // `open` and `only` rather than one function with an optional group, because
  // `ipc call` passes every argument a function declares.
  IpcHandler {
    target: "menu"

    function open(): void { MenuHost.open("") }
    function only(group: string): void { MenuHost.open(group) }
    function list(group: string): string { return MenuHost.list(group) }
    function launch(name: string): string { return MenuHost.launchByName(name) }
  }
}
