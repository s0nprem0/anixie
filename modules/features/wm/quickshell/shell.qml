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
  PanelWindow {
    id: bar

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
    // bottom is not given a height on its own. The screen size is taken from
    // the application rather than from an item, since the bar cannot measure
    // itself before it exists.
    readonly property var screen: Qt.application.screens && Qt.application.screens.length > 0
      ? Qt.application.screens[0]
      : null

    implicitWidth: BarContext.vertical
      ? Style.bar.sizeVertical
      : (screen ? screen.width : 1920)
    implicitHeight: BarContext.vertical
      ? (screen ? screen.height : 1080)
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

    Component.onCompleted: {
      PanelHost.host = barRoot
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

  // The on-screen display for volume and brightness. Anchored to the bottom
  // edge alone, which is what centres a layer surface on the axis it does not
  // anchor, so the window is only as wide as the card and cannot swallow clicks
  // across the whole width of the screen.
  PanelWindow {
    id: osdWindow

    anchors.bottom: true
    margins.bottom: Style.space(90)
    implicitWidth: osdCard.implicitWidth
    implicitHeight: osdCard.implicitHeight

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    visible: OsdHost.shown

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Osd {
      id: osdCard
      anchors.fill: parent
      icon: OsdHost.icon
      percent: OsdHost.percent
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
    function reset(): void { BarConfig.reset() }

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

  // What the shell is actually drawing with. The theme follows a state file on
  // its own, so this is how you check that it did rather than taking a screenshot
  // and squinting at it.
  IpcHandler {
    target: "theme"

    function set(name: string): void { Theme.set(name) }
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

    anchors.right: true
    anchors.bottom: true
    margins.right: Style.space(24)
    margins.bottom: Style.space(24)
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
      pinned: CapturePreview.pinned
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
  // an empty one leaves no window behind to swallow clicks.
  PanelWindow {
    id: notificationWindow

    anchors.top: true
    anchors.right: true

    // Clear of the bar, which occupies the top edge.
    margins.top: Style.bar.sizeHorizontal + Style.space(10)
    margins.right: Style.space(10)

    implicitWidth: notificationColumn.implicitWidth
    implicitHeight: notificationColumn.implicitHeight

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    visible: NotificationHost.tracked.length > 0

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notifications"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Column {
      id: notificationColumn

      anchors.fill: parent
      spacing: Style.space(8)

      Repeater {
        model: NotificationHost.stacked

        delegate: NotificationCard {
          required property var modelData

          // Width comes from the card's own implicit width, which is what sizes
          // the column and so the window. Binding it back to the column would be
          // circular and collapse both.
          notification: modelData
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

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    visible: PickHost.shown

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-picker"
    WlrLayershell.keyboardFocus: PickHost.shown
      ? WlrKeyboardFocus.Exclusive
      : WlrKeyboardFocus.None

    Picker {
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