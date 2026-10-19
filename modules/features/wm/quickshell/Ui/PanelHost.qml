pragma Singleton

import QtQuick
import QtQml.Models
import ".."
import Quickshell
import Quickshell.Wayland

// The panels: several at once, each under the button it belongs to, with the
// keyboard on one of them at a time.
//
// This used to hold one panel, because one was all it could. Omarchy — which the
// bar is modelled on, and which now runs on Quickshell too — lets you open one
// per widget and puts them side by side: open the network panel, then the audio
// one, and both stay up; Tab steps between them; Escape closes the one the keys
// are on. That is a better answer to "what is this laptop doing" than a panel
// that replaces the last one, and it costs a list instead of a single owner.
//
// Each panel is a layer surface of its own rather than a popup. A popup has no
// reliable keyboard under Hyprland — `grabFocus` only asks to be dismissed by an
// outside click — so the keys are taken the way the picker takes them: an
// exclusive keyboard focus on a surface, held only by the panel that has the
// keys. That is also what makes several panels work: one surface each, and the
// keyboard handed between them.
QtObject {
  id: root

  // The bar's window, set once at startup. Panels are positioned against it.
  property Item host: null

  // The open panels, in the order they were opened. The delegate for each is a
  // window, so this is a ListModel rather than an array: appending one must not
  // rebuild the others, which would reset the scroll and the focus of a panel
  // that was already open.
  property ListModel openPanels: ListModel {}

  // What each open panel was opened with. Keyed by name, because a panel is
  // named once and its anchor and builder are what the widget registered.
  property var entries: ({})

  // The panel the keyboard is on. Empty when nothing is open.
  property string focused: ""

  readonly property bool shown: root.openPanels.count > 0

  // Taken from the bar's own window rather than from Quickshell.screens, whose
  // entries on this version expose only model and name.
  readonly property real screenWidth: root.host && root.host.Screen.width ? root.host.Screen.width : 1920
  readonly property real screenHeight: root.host && root.host.Screen.height ? root.host.Screen.height : 1080
  readonly property real barHeight: Style.bar.sizeHorizontal

  // The most room a panel may take below the bar, less a margin so its bottom
  // edge is never flush against the screen's. Panel cards cap themselves at the
  // same figure; this is the backstop for one that measures its own height some
  // other way, because a window taller than the screen does not scroll — it
  // simply has its bottom off the display, out of reach of the pointer and of
  // the eye.
  readonly property int panelMaxHeight: Math.max(Style.space(120), Math.round(screenHeight - barHeight - Style.space(16)))

  // ---- what is open ----

  function isOpen(name) {
    for (let i = 0; i < root.openPanels.count; i++) {
      if (root.openPanels.get(i).name === name) return true
    }
    return false
  }

  function indexOf(name) {
    for (let i = 0; i < root.openPanels.count; i++) {
      if (root.openPanels.get(i).name === name) return i
    }
    return -1
  }

  function toggle(name, anchor, builder) {
    // Three arguments from the registry, two from a drop-in module's
    // `bar.togglePanel(anchor, builder)`, which has no name to give. The anchor
    // is what a panel belongs to either way, so it supplies one.
    if (builder === undefined) {
      root.toggleNamed(root.nameFor(anchor), name, anchor)
      return
    }

    root.toggleNamed(name, anchor, builder)
  }

  function toggleNamed(name, anchor, builder) {
    if (!name || !anchor || !builder) return

    if (root.isOpen(name)) {
      root.close(name)
      return
    }

    root.show(name, anchor, builder)
  }

  function show(name, anchor, builder) {
    if (builder === undefined) {
      root.showNamed(root.nameFor(anchor), name, anchor)
      return
    }

    root.showNamed(name, anchor, builder)
  }

  function showNamed(name, anchor, builder) {
    if (!name || !anchor || !builder) return
    if (root.isOpen(name)) {
      root.focus(name)
      return
    }

    const next = {}
    for (const key in root.entries) next[key] = root.entries[key]
    next[name] = { anchor: anchor, builder: builder }
    root.entries = next

    root.openPanels.append({ name: name })
    root.focused = name
  }

  // A name for a panel that has none: a module that only knows its anchor still
  // needs one to be opened twice or closed by name. Kept on the anchor itself, so
  // the same widget always names the same panel.
  property int anonymousCount: 0

  function nameFor(anchor) {
    if (!anchor.__panelName) {
      root.anonymousCount += 1
      anchor.__panelName = "panel-" + root.anonymousCount
    }
    return anchor.__panelName
  }

  function close(name) {
    if (name === undefined) {
      root.closeAll()
      return
    }

    const index = root.indexOf(name)
    if (index < 0) return

    root.openPanels.remove(index)

    const next = {}
    for (const key in root.entries) if (key !== name) next[key] = root.entries[key]
    root.entries = next

    // The keys go to the panel that is still up, so closing one does not leave
    // the rest unable to answer a key.
    if (root.focused === name) {
      root.focused = root.openPanels.count > 0
        ? root.openPanels.get(root.openPanels.count - 1).name
        : ""
    }
  }

  function closeFocused() {
    if (root.focused !== "") root.close(root.focused)
  }

  function closeAll() {
    root.openPanels.clear()
    root.entries = ({})
    root.focused = ""
  }

  function focus(name) {
    if (root.isOpen(name)) root.focused = name
  }

  // Tab and Shift+Tab between open panels, wrapping. The arrows stay inside the
  // panel, which is where they are useful.
  function focusNext(delta) {
    if (root.openPanels.count < 2) return

    let index = root.indexOf(root.focused)
    if (index < 0) index = 0

    index = (index + delta + root.openPanels.count) % root.openPanels.count
    root.focused = root.openPanels.get(index).name
  }

  // ---- where they go ----

  // Centred under the owning button, then pulled back inside the screen so a
  // button near either edge still opens a fully visible panel. With several
  // panels up this is also what keeps them from overlapping the screen's edges
  // while still sitting under their own icons.
  function panelX(anchor, width) {
    if (!anchor || !root.host) return 0

    const left = anchor.mapToItem(root.host, 0, 0).x
    const centre = left + anchor.width / 2

    const margin = Style.space(8)
    return Math.max(margin, Math.min(Math.round(centre - width / 2), root.screenWidth - width - margin))
  }

  // The invisible surface that dismisses everything.
  //
  // A panel surface only receives input that lands on it, so without this a
  // click anywhere else would pass straight through to whatever is underneath
  // and leave the panels stranded on screen. The curtain covers everything below
  // the bar and swallows that click. It deliberately stops short of the bar
  // itself, so the bar stays live and clicking a module still works — which is
  // how a second panel is opened without closing the first.
  property PopupWindow curtain: PopupWindow {
    visible: root.shown
    color: "transparent"
    anchor.item: root.host
    // The popup's top edge lands on the rect's top edge and it grows downward, so
    // the rect has to start at the bar's full height for the bar to stay
    // uncovered.
    anchor.rect: Qt.rect(0, root.barHeight, root.screenWidth, 0)
    implicitWidth: root.screenWidth
    implicitHeight: root.screenHeight - root.barHeight

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onPressed: root.closeAll()
    }
  }

  // One window per open panel. A layer surface each, because the keyboard has to
  // live somewhere, and only the focused one asks for it.
  property Item windowHost: Item {
    visible: false

    // Instantiator rather than Repeater: a Repeater only builds Items, and these
    // delegates are windows.
    Instantiator {
      model: root.openPanels

      delegate: PanelWindow {
        id: panelWindow
        required property string name

        readonly property var entry: root.entries[panelWindow.name] || ({})

        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        visible: true

        anchors.top: true
        anchors.left: true
        margins.top: root.barHeight
        margins.left: root.panelX(panelWindow.entry.anchor, panelWindow.implicitWidth)

        // The focused panel is raised above the others: with panels anchored under
        // neighbouring icons they overlap, and Tab has to visibly bring one to the
        // front rather than only change where the keys go.
        WlrLayershell.layer: root.focused === panelWindow.name
          ? WlrLayer.Overlay
          : WlrLayer.Top
        WlrLayershell.namespace: "quickshell-panel"
        // Exclusive only for the panel the keys are on. None for the rest, which
        // is what hands the keyboard to the next one when Tab moves.
        WlrLayershell.keyboardFocus: root.focused === panelWindow.name
          ? WlrKeyboardFocus.Exclusive
          : WlrKeyboardFocus.None

        implicitWidth: loader.item ? loader.item.implicitWidth : 320
        implicitHeight: Math.min(root.panelMaxHeight,
          loader.item ? loader.item.implicitHeight : 0)

        Loader {
          id: loader
          anchors.fill: parent
          sourceComponent: panelWindow.entry.builder || null
        }
      }
    }
  }
}
