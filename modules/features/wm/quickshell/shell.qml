//@ pragma UseQApplication
// Blocky status bar in five sections. `center` is pinned to the exact middle of
// the bar, and centerBegin/centerEnd hang off its edges so they grow outward
// instead of shifting the clock off centre.
//
// The bar runs on whichever edge bar.json names. On a side edge it becomes a
// column, the modules drop their labels, and the five sections run top-to-bottom
// instead of left-to-right — so "left" means the start of the bar, which is the
// top when it is vertical.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland

import "."
import "Ui"
import "components"

ShellRoot {
  id: shell

  // Rebuilt when the bar switches edges. Layer surfaces cannot be re-anchored
  // reliably after they are mapped, so the window is recreated instead: the
  // position in the model makes Variants destroy and rebuild each per-screen bar.
  readonly property var barSurfaces: {
    const out = []
    const screens = Quickshell.screens
    for (let i = 0; i < screens.length; i++) {
      out.push({ screen: screens[i], position: BarContext.position })
    }
    return out
  }

  // The desktop background. One layer-shell surface per output, on the
  // Background layer so windows sit over it. It takes input only for the
  // desktop context menu: the surface claims the pointer, but windows are above
  // the background layer and keep theirs, and a left click still goes nowhere
  // because the MouseArea accepts only the right button. The path comes from
  // the `wallpaper` command and changes crossfade in place; video wallpapers
  // still go to awww, so this surface steps aside for them.
  Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
      required property var modelData
      screen: modelData

      implicitWidth: modelData.width
      implicitHeight: modelData.height

      anchors.top: true
      anchors.bottom: true
      anchors.left: true
      anchors.right: true

      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      mask: Region {
        item: backgroundInput
      }
      visible: !BackgroundHost.video

      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.namespace: "quickshell-background"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      BackgroundSurface {
        anchors.fill: parent
        source: BackgroundHost.video ? "" : BackgroundHost.path
        revision: BackgroundHost.revision
      }

      MouseArea {
        id: backgroundInput
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: function (mouse) {
          ContextMenuHost.openAt([
            { label: "Terminal", glyph: Util.keyboard, action: function () { Commands.app("kitty") } },
            { label: "Files", glyph: Util.menu, action: function () { Commands.app("thunar") } },
            { separator: true },
            { label: "Theme picker", glyph: Util.sun, action: function () { Commands.run("theme") } },
            { label: "Next theme", action: function () { Commands.run("theme next") } },
            { separator: true },
            { label: "Screen time & focus…", glyph: Util.clock, action: function () { Commands.run("screentime panel") } },
            { label: "Lock", glyph: Util.lock, action: function () { LockHost.lock() } }
          ], backgroundInput, mouse.x, mouse.y)
        }
      }
    }
  }

  // The idle screensaver. It covers every output and takes the keyboard while it
  // is up, so a key wakes it rather than reaching an application behind it. The
  // compositor's session lock, not this, is the security boundary; this hides the
  // desktop while the user is away and disappears on the first input.
  Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
      required property var modelData
      screen: modelData

      implicitWidth: modelData.width
      implicitHeight: modelData.height

      anchors.top: true
      anchors.bottom: true
      anchors.left: true
      anchors.right: true

      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      visible: IdleHost.screensaverShown && !LockHost.locked

      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "quickshell-screensaver"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

      Screensaver {
        anchors.fill: parent
        onWake: IdleHost.wake()
      }
    }
  }

  // One bar per connected screen. `Variants` builds and destroys them as
  // displays or the bar's edge change, and `screen: targetScreen` is what puts
  // each copy on its own output. Everything that hangs off a bar — panels, the
  // curtain, drag and drop — looks the bar up by screen name (see Ui/Screens.qml).
  Variants {
    model: shell.barSurfaces

    delegate: PanelWindow {
      id: bar
      required property var modelData
      // A screen can disappear between a hotplug event and Variants rebuilding
      // this delegate. Keep the window harmless for that frame rather than
      // reading a width off a screen object that is already gone.
      readonly property var targetScreen: modelData && modelData.screen ? modelData.screen : null
      screen: targetScreen

      // Edges are set from the position rather than by switching between four
      // blocks of anchors: a single anchors block can express any edge, and
      // clearing the ones that do not apply keeps Hyprland from seeing both.
      // A side bar spans top to bottom and is sized by width instead, a top or
      // bottom bar spans left to right and is sized by height.
      anchors {
        top: BarContext.vertical || BarContext.position === "top" ? true : false
        bottom: BarContext.vertical || BarContext.position === "bottom" ? true : false
        left: !BarContext.vertical || BarContext.position === "left" ? true : false
        right: !BarContext.vertical || BarContext.position === "right" ? true : false
      }

      // A side bar is as long as the screen and as wide as an icon; a top or bottom
      // bar is as wide as the screen and as tall as one row. Both dimensions are
      // stated rather than left to the anchors, because a window anchored top to
      // bottom is not given a height on its own. Each copy takes its size from its
      // own screen, so a laptop panel and an external display are not laid out to
      // the same width.
      implicitWidth: BarContext.vertical
        ? Style.bar.sizeVertical
        : (targetScreen ? targetScreen.width : 0)
      implicitHeight: BarContext.vertical
        ? (targetScreen ? targetScreen.height : 0)
        : Style.bar.sizeHorizontal

      color: "transparent"

      // The bar's thickness is reserved from the workspace, so Hyprland lays every
      // window out below it instead of underneath it.
      //
      // This has to be asked for as a size rather than through exclusionMode: the
      // bar used to set ExclusionMode.Ignore, which declares no zone at all, and
      // maximized windows took the full output height and ran under the bar. Since
      // the default background is a transparent "clear", the window showed straight
      // through it, which read as the bar and the window overlapping. Switching to
      // ExclusionMode.Normal did not fix it either — on this Quickshell it still
      // left hyprctl reporting "reserved: 0 0 0 0". Stating the zone directly does
      // register, and reports "reserved: 0 26 0 0".
      //
      // Stated as a size rather than left at exclusionMode's default of -1 (the
      // compositor guesses from the anchored edges), so the reserved strip always
      // matches the bar's own geometry rather than whatever Hyprland infers.
      //
      // Popups (PanelHost's panel and curtain, TooltipHost's window) keep the
      // default of no exclusive zone on purpose: they float over the desktop and
      // must not push windows around when they open.
      //
      // Zero while the bar is hidden, which is what gives the pixels back. The
      // window itself stays mapped: unmapping it would take the anchor every panel
      // hangs off with it, and a hotkey-opened panel would have nothing to attach
      // to. Hiding the contents is what makes it invisible.
      exclusiveZone: BarContext.shown
        ? (BarContext.vertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal)
        : 0

      // The panel popup anchors to this item rather than to whichever button was
      // used, because a popup resolves its anchor once, at creation. It cannot
      // anchor to the PanelWindow itself either: that is a QObject here, not an
      // item, so it has no coordinate space to place against. The tooltip has no
      // such need — it anchors to the button it describes directly.
      Item {
        id: barRoot
        anchors.fill: parent
      }

      // Registered by screen name rather than assigned to one shared host: every
      // output has a bar, and a panel belongs to the bar it was clicked on while
      // the hotkeys belong to the one under the pointer.
      Component.onCompleted: {
        PanelHost.registerBar(barRoot)
        BarDrag.registerBar(barRoot)
      }

      Component.onDestruction: {
        PanelHost.unregisterBar(barRoot)
        BarDrag.unregisterBar(barRoot)
      }

      Background {
        anchors.fill: parent
      }

      readonly property real gap: Style.space(2)

      // ---- start (left, or top when vertical) ----
      Section {
        anchors.top: BarContext.vertical ? parent.top : undefined
        anchors.left: BarContext.vertical ? undefined : parent.left
        anchors.horizontalCenter: BarContext.vertical ? undefined : undefined
        anchors.verticalCenter: BarContext.vertical ? undefined : parent.verticalCenter
        anchors.topMargin: BarContext.vertical ? bar.gap : undefined
        anchors.leftMargin: BarContext.vertical ? undefined : bar.gap
        name: "left"
        entries: BarConfig.section("left")
      }

      // ---- centre ----
      Section {
        id: centerSection
        anchors.horizontalCenter: BarContext.vertical ? undefined : parent.horizontalCenter
        anchors.verticalCenter: BarContext.vertical ? parent.verticalCenter : undefined
        name: "center"
        entries: BarConfig.section("center")
      }

      // ---- centerBegin: grows away from the centre group ----
      Section {
        anchors.right: BarContext.vertical ? undefined : centerSection.left
        anchors.bottom: BarContext.vertical ? centerSection.top : undefined
        anchors.verticalCenter: BarContext.vertical ? undefined : parent.verticalCenter
        anchors.rightMargin: BarContext.vertical ? undefined : bar.gap
        anchors.bottomMargin: BarContext.vertical ? bar.gap : undefined
        name: "centerBegin"
        entries: BarConfig.section("centerBegin")
      }

      // ---- centerEnd ----
      Section {
        anchors.left: BarContext.vertical ? undefined : centerSection.right
        anchors.top: BarContext.vertical ? centerSection.bottom : undefined
        anchors.verticalCenter: BarContext.vertical ? undefined : parent.verticalCenter
        anchors.leftMargin: BarContext.vertical ? undefined : bar.gap
        anchors.topMargin: BarContext.vertical ? bar.gap : undefined
        name: "centerEnd"
        entries: BarConfig.section("centerEnd")
      }

      // ---- end (right, or bottom when vertical) ----
      Section {
        anchors.bottom: BarContext.vertical ? parent.bottom : undefined
        anchors.right: BarContext.vertical ? undefined : parent.right
        anchors.verticalCenter: BarContext.vertical ? undefined : parent.verticalCenter
        anchors.bottomMargin: BarContext.vertical ? bar.gap : undefined
        anchors.rightMargin: BarContext.vertical ? undefined : bar.gap
        name: "right"
        entries: BarConfig.section("right")
      }

      // The gap a release would fill. Full thickness of the bar so it reads as a
      // slot opening rather than a cursor drawn over the modules.
      Rectangle {
        id: dragIndicator

        visible: BarDrag.active && BarDrag.targetValid
        x: BarDrag.indicatorRect.x
        y: BarDrag.indicatorRect.y
        width: BarDrag.indicatorRect.width
        height: BarDrag.indicatorRect.height
        color: Theme.accent
        radius: 1
        z: 100
      }
    }
  }

  // The low-battery warning. Lives on the shell rather than on the bar's readout
  // so it keeps working regardless of which modules the bar is showing.
  PowerAlert {}

  // The polkit prompt. A surface of its own rather than anything to do with the
  // bar: a privilege request is not a bar event, and this has to cover the whole
  // output and hold the keyboard for as long as it is up.
  //
  // It only takes keyboard focus while it is showing. Holding it permanently
  // would keep the compositor from ever delivering keys to windows underneath.
  PanelWindow {
    id: polkitWindow
    screen: Screens.focused

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    visible: PolkitHost.awaiting

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-polkit"
    WlrLayershell.keyboardFocus: PolkitHost.awaiting
      ? WlrKeyboardFocus.Exclusive
      : WlrKeyboardFocus.None

    PolkitPrompt {
      anchors.fill: parent
      message: PolkitHost.message
      prompt: PolkitHost.prompt
      detail: PolkitHost.detail
      detailIsError: PolkitHost.detailIsError

      onSubmitted: function (value) { PolkitHost.submit(value) }
      onCancelled: PolkitHost.cancel()
    }
  }

  // The on-screen display for volume, microphone and brightness. Anchored to
  // the bottom edge alone, which centres a layer surface on the axis it does
  // not anchor, so the window is only as wide as the card and cannot swallow
  // clicks across the whole width of the screen.
  PanelWindow {
    id: osdWindow
    screen: Screens.focused

    anchors.bottom: true
    margins.bottom: Style.space(90)
    implicitWidth: osdCard.implicitWidth
    implicitHeight: osdCard.implicitHeight

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    // Keep the surface mapped while it fades out, then let it go. Binding
    // `visible` to `shown` alone would unmap it on the first frame of the fade.
    visible: OsdHost.opened || osdCard.opacity > 0

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Osd {
      id: osdCard
      anchors.fill: parent
      icon: OsdHost.icon
      message: OsdHost.message
      hasProgress: OsdHost.hasProgress
      value: OsdHost.value
      maxValue: OsdHost.maxValue
      mediaOsd: OsdHost.mediaOsd

      opacity: OsdHost.opened ? 1 : 0
      Behavior on opacity {
        NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
      }
    }
  }

  // The dock. Left edge, reserving a strip like the bar does, so windows are laid
  // out beside it rather than running underneath — a dock that windows slide
  // under would be worse than no dock at all.
  //
  // `Ignore` is not used here, unlike the popups. The bar had to state its zone
  // as a size because exclusionMode left hyprctl reporting no reservation at
  // all, and the same is true of this window; an invisible-but-present dock must
  // not cost screen space when it is closed, so the zone follows `shown`.
  PanelWindow {
    id: dockWindow

    anchors.top: true
    anchors.bottom: true
    anchors.left: true

    exclusiveZone: DockHost.shown ? dockWindow.dockWidth : 0
    visible: DockHost.shown

    color: Theme.surface

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-dock"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Stated here rather than measured from the content. Measuring it meant
    // asking the content column for a width that the column then took from the
    // window, and the two agreed on nothing at all: the dock came up one pixel
    // wide and Hyprland reserved one pixel.
    readonly property real dockWidth: Style.space(360)
    implicitWidth: dockWindow.dockWidth

    Dock {
      anchors.fill: parent
    }
  }

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
      if (!BarContext.trayItem) return
      PanelHost.toggle("tray", BarContext.trayItem, BarContext.trayItem.drawer)
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

  // The screenshot preview. Bottom right, over the desktop, gone on its own after
  // ten seconds unless it is pinned.
  //
  // `Ignore` for the exclusive zone and `None` for the keyboard, like the popups:
  // it floats over whatever is there and must not push windows around or take the
  // keyboard from the window being worked in. Only the two buttons want clicks,
  // and they take them as buttons rather than by the window claiming input.
  PanelWindow {
    id: capturePreviewWindow
    screen: Screens.focused

    anchors.right: true
    anchors.bottom: true
    // The same clearance the notifications get, from the other corner.
    margins.right: BarContext.position === "right"
      ? Style.bar.sizeVertical + Style.space(24)
      : Style.space(24)
    margins.bottom: BarContext.position === "bottom"
      ? Style.bar.sizeHorizontal + Style.space(24)
      : Style.space(24)
    implicitWidth: previewCard.implicitWidth
    implicitHeight: previewCard.implicitHeight

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    visible: CapturePreview.shown

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-capture-preview"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    CapturePreviewCard {
      id: previewCard
      anchors.fill: parent
      source: CapturePreview.path
      revision: CapturePreview.revision
      pinned: CapturePreview.pinned
      onOpened: Commands.app("xdg-open", [CapturePreview.path])
      onAnnotated: {
        Commands.run("wl-copy --type image/png < " + Util.shellQuote(CapturePreview.path))
        CapturePreview.reveal(CapturePreview.path)
      }
      onPinToggled: CapturePreview.togglePin()
      onDismissed: CapturePreview.hide()
    }
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

  // Notification popups. Top right, over everything, and taking no keyboard:
  // a notification is there to be read, not typed into. Sized to its stack, so
  // an empty one leaves no window behind to swallow clicks. The output choice is
  // read from NotificationHost, which the panel can change at runtime.
  Variants {
    model: NotificationHost.displayMode === "all"
      ? Quickshell.screens
      : (NotificationHost.displayMode === "specific" && Screens.byName(NotificationHost.displayName)
        ? [Screens.byName(NotificationHost.displayName)]
        : (Screens.focused ? [Screens.focused] : []))

    delegate: PanelWindow {
      id: notificationWindow
      required property var modelData
      screen: modelData

      anchors.top: true
      anchors.right: true

      // Clear of the bar on whichever edge it is: the cards sit under a top bar
      // and beside a right one, rather than over it.
      margins.top: BarContext.position === "top"
        ? Style.bar.sizeHorizontal + Style.space(10)
        : Style.space(10)
      margins.right: BarContext.position === "right"
        ? Style.bar.sizeVertical + Style.space(10)
        : Style.space(10)

      implicitWidth: notificationColumn.implicitWidth
      implicitHeight: notificationColumn.implicitHeight

      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      // Step aside over a fullscreen window when there is nothing to show, so
      // the fullscreen surface can be scanned out directly. A notification brings
      // the popup back over it, the way a toast should.
      readonly property bool fullscreenOnOutput: {
        if (!NotificationHost.fullscreenStepAside) return false
        const name = String(modelData.name)
        const list = Hyprland.workspaces ? Hyprland.workspaces.values : []
        for (const workspace of list) {
          if (workspace.monitor && String(workspace.monitor.name) === name && workspace.hasFullscreen) return true
        }
        return false
      }
      visible: NotificationHost.tracked.length > 0 || NotificationHost.replaying
        || NotificationHost.restoring || !notificationWindow.fullscreenOnOutput

      // A burst — a mailing list, a chat backlog — should not draw a column taller
      // than the screen with the last cards unreachable. The newest few are shown,
      // the rest are counted, and the history panel has them all.
      readonly property int maxCards: NotificationHost.replaying || NotificationHost.restoring ? 10 : 4
      readonly property var decks: {
        if (NotificationHost.replaying) {
          return NotificationHost.replayEntries.map(function (entry) {
            return { items: [entry], restored: false }
          })
        }

        const out = []
        if (NotificationHost.restoring) {
          for (const entry of NotificationHost.restoredEntries) out.push({ items: [entry], restored: true })
        }
        for (const group of NotificationHost.groups) out.push({ items: group.items, restored: false })
        return out
      }
      readonly property var shownDecks: notificationWindow.decks.slice(0, notificationWindow.maxCards)
      readonly property int hiddenCount: Math.max(0, notificationWindow.decks.length - notificationWindow.shownDecks.length)

      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "quickshell-notifications"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      Column {
        id: notificationColumn

        anchors.fill: parent
        spacing: Style.space(8)

        Repeater {
          model: notificationWindow.shownDecks

          delegate: NotificationDeck {
            required property var modelData

            items: modelData.items
            replay: NotificationHost.replaying || modelData.restored === true
            forceExpanded: NotificationHost.replaying || modelData.restored === true
          }
        }

        Text {
          visible: notificationWindow.hiddenCount > 0
          height: implicitHeight
          text: "+" + notificationWindow.hiddenCount + " more"
          color: Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          renderType: Text.NativeRendering
        }
      }
      }
  }

  // The picker. Covers the whole output and takes the keyboard for as long as it
  // is up, for the same reason the polkit prompt does: it is a surface you type
  // into, and everything on it has to be reachable without the mouse.
  //
  // On the Overlay layer, above the notifications — a picker opened while
  // something is being notified should cover it, not be covered by it.
  PanelWindow {
    id: pickerWindow
    screen: Screens.focused

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    // Mapped while shown and for as long as the card is still fading, which is
    // the same arrangement the OSD uses: unmapping on `shown` alone would cut
    // the fade off on its first frame.
    visible: PickHost.shown || picker.reveal > 0

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-picker"
    WlrLayershell.keyboardFocus: PickHost.shown
      ? WlrKeyboardFocus.Exclusive
      : WlrKeyboardFocus.None

    Picker {
      id: picker
      anchors.fill: parent
    }
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

  // The menu's keys, as Hyprland global shortcuts rather than commands. A bind
  // that runs `menu` starts a process, which starts `quickshell ipc`, which is a
  // Qt application starting up to deliver one message — about 140ms before the
  // shell has even heard of the keypress. A global shortcut is a Wayland event
  // the shell is already listening for. The binds are in hyprland/lua.nix, as
  // `hl.dsp.global("quickshell:<name>")`.
  GlobalShortcut {
    name: "menu"
    description: "Open the menu"
    onPressed: MenuHost.open("")

    // Builds the menu's singleton and starts the desktop-entry scan now, rather
    // than on the first keypress (see MenuHost.warm).
    Component.onCompleted: MenuHost.warm()
  }

  GlobalShortcut {
    name: "menu-capture"
    description: "Open the capture menu"
    onPressed: MenuHost.open("Capture")
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
