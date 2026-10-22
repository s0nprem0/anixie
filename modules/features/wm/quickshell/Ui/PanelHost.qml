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
//
// With more than one display there is more than one bar. A panel is placed on
// the screen its anchor came from, and the curtain that dismisses it exists once
// per screen with a panel on it. The bars register here by screen name; nothing
// assumes a single "the bar" any more.
QtObject {
  id: root

  // The bars, by screen name. Each one is the invisible full-size item inside a
  // bar window, which is the coordinate space panels and curtains are placed in.
  property var bars: ({})

  function registerBar(item) {
    if (!item) return

    const name = Screens.nameOf(item)
    if (!name) return

    const next = {}
    for (const key in root.bars) next[key] = root.bars[key]
    next[name] = item
    root.bars = next
  }

  function unregisterBar(item) {
    if (!item) return

    // The screen may already be detached by the time a bar is destroyed, so the
    // lookup prefers the recorded screen name and falls back to identity.
    const name = Screens.nameOf(item)
    let found = root.bars[name] === item ? name : ""
    if (!found) {
      for (const key in root.bars) {
        if (root.bars[key] === item) {
          found = key
          break
        }
      }
    }
    if (!found) return

    const next = {}
    for (const key in root.bars) if (key !== found) next[key] = root.bars[key]
    root.bars = next
  }

  function barFor(screenName) {
    if (screenName && root.bars[screenName]) return root.bars[screenName]
    return root.bars[Screens.focusedName] || null
  }

  readonly property Item focusedBar: root.barFor(Screens.focusedName)

  // The open panels, in the order they were opened. The delegate for each is a
  // window, so this is a ListModel rather than an array: appending one must not
  // rebuild the others, which would reset the scroll and the focus of a panel
  // that was already open. `screenName` is stored alongside so the window can
  // stay on the output its button belongs to.
  property ListModel openPanels: ListModel {}

  // What each open panel was opened with, keyed by panel key. A panel can be
  // open once per screen, so the name alone is not unique: the key is name and
  // screen, and it is also what the keyboard focus follows.
  property var entries: ({})

  // The panel the keyboard is on, as a key. Empty when nothing is open.
  property string focused: ""

  readonly property bool shown: root.openPanels.count > 0

  // Which screens have at least one panel open. A curtain is only needed on
  // those — a full-screen dismiss surface on a display with nothing to dismiss
  // would swallow clicks meant for a window there.
  readonly property var openScreens: {
    const out = {}
    const count = root.openPanels.count
    for (let i = 0; i < count; i++) {
      out[String(root.openPanels.get(i).screenName)] = true
    }
    return out
  }

  readonly property var curtainScreens: {
    const out = []
    const opened = root.openScreens
    for (let i = 0; i < Screens.all.length; i++) {
      if (opened[String(Screens.all[i].name)]) out.push(Screens.all[i])
    }
    return out
  }

  // The bar's own edge, not always the top one. Panels hang off whichever side
  // it occupies, so a bottom or side bar opens them where the pointer is rather
  // than at a fixed corner.
  readonly property bool vertical: BarContext.vertical
  readonly property string position: Theme.position
  readonly property real barExtent: root.vertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal

  // The most room a panel may take beside the bar, less a margin so its far
  // edge is never flush against the screen's. Panel cards cap themselves at the
  // same figure; this is the backstop for one that measures its own height some
  // other way, because a window taller than the screen does not scroll — it
  // simply has its bottom off the display, out of reach of the pointer and of
  // the eye. Kept per screen, since the outputs need not be the same height.
  function maxHeightFor(screenHeight) {
    return Math.max(Style.space(120),
      Math.round((screenHeight || 1080) - (root.vertical ? 0 : root.barExtent) - Style.space(16)))
  }

  readonly property int panelMaxHeight: root.maxHeightFor(Screens.heightOf(Screens.focusedName))

  // ---- what is open ----

  function panelKey(name, screenName) {
    return name + "@" + screenName
  }

  // With a screen name this is that exact panel; without one it is the panel
  // the keys are on, and failing that any instance (what the tray's "is the
  // drawer open" check wants).
  function indexOf(name, screenName) {
    const wanted = screenName === undefined ? "" : root.panelKey(name, screenName)
    let fallback = -1
    for (let i = 0; i < root.openPanels.count; i++) {
      const panel = root.openPanels.get(i)
      if (panel.name !== name) continue
      if (wanted !== "") {
        if (panel.key === wanted) return i
      } else {
        if (root.focused === panel.key) return i
        if (fallback < 0) fallback = i
      }
    }
    return fallback
  }

  function indexOfKey(key) {
    for (let i = 0; i < root.openPanels.count; i++) {
      if (root.openPanels.get(i).key === key) return i
    }
    return -1
  }

  function isOpen(name, screenName) {
    return root.indexOf(name, screenName) >= 0
  }

  function countFor(screenName) {
    let count = 0
    for (let i = 0; i < root.openPanels.count; i++) {
      if (root.openPanels.get(i).screenName === screenName) count += 1
    }
    return count
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

    const screenName = Screens.nameOf(anchor)
    if (root.isOpen(name, screenName)) {
      root.close(name, screenName)
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

  // Open without taking the keyboard. The tray drawer is revealed by hovering,
  // and a panel that stole the keys from the window being typed in because the
  // pointer crossed the tray would be worse than no hover target at all.
  function showPassive(name, anchor, builder) {
    if (builder === undefined) {
      root.showNamed(root.nameFor(anchor), name, anchor, false)
      return
    }

    root.showNamed(name, anchor, builder, false)
  }

  function showNamed(name, anchor, builder, grabKeyboard) {
    if (!name || !anchor || !builder) return

    const screenName = Screens.nameOf(anchor)
    if (root.isOpen(name, screenName)) {
      if (grabKeyboard !== false) root.focus(name, screenName)
      return
    }

    const key = root.panelKey(name, screenName)

    const next = {}
    for (const other in root.entries) next[other] = root.entries[other]
    next[key] = { anchor: anchor, builder: builder, screenName: screenName }
    root.entries = next

    root.openPanels.append({ name: name, screenName: screenName, key: key })
    if (grabKeyboard !== false) root.focused = key
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

  function close(name, screenName) {
    if (name === undefined) {
      root.closeAll()
      return
    }

    const index = root.indexOf(name, screenName)
    if (index < 0) return
    root.closeIndex(index)
  }

  function closeIndex(index) {
    const key = root.openPanels.get(index).key
    root.openPanels.remove(index)

    const next = {}
    for (const other in root.entries) if (other !== key) next[other] = root.entries[other]
    root.entries = next

    // The keys go to the panel that is still up, so closing one does not leave
    // the rest unable to answer a key.
    if (root.focused === key) {
      root.focused = root.openPanels.count > 0
        ? root.openPanels.get(root.openPanels.count - 1).key
        : ""
    }
  }

  function closeFocused() {
    const index = root.indexOfKey(root.focused)
    if (index >= 0) root.closeIndex(index)
  }

  function closeAll() {
    root.openPanels.clear()
    root.entries = ({})
    root.focused = ""
  }

  // Dismissing by clicking a curtain only covers that output: the panels on
  // another display were not what the pointer clicked past.
  function closeForScreen(screenName) {
    for (let i = root.openPanels.count - 1; i >= 0; i--) {
      if (root.openPanels.get(i).screenName === screenName) root.closeIndex(i)
    }
  }

  function focus(name, screenName) {
    const index = root.indexOf(name, screenName)
    if (index >= 0) root.focused = root.openPanels.get(index).key
  }

  // Tab and Shift+Tab between open panels, wrapping. The arrows stay inside the
  // panel, which is where they are useful.
  function focusNext(delta) {
    if (root.openPanels.count < 2) return

    let index = root.indexOfKey(root.focused)
    if (index < 0) index = 0

    index = (index + delta + root.openPanels.count) % root.openPanels.count
    root.focused = root.openPanels.get(index).key
  }

  // ---- where they go ----

  // Centred on the owning button, then pulled back inside its screen so a
  // button near either edge still opens a fully visible panel. With several
  // panels up this is also what keeps them from overlapping the screen's edges
  // while still sitting under their own icons.
  //
  // Two axes because the bar has two: a top or bottom bar spreads its modules
  // across x, a left or right bar spreads them down y. The anchor's own screen
  // supplies both the coordinate space and the size to clamp against.
  function panelX(anchor, width, screenName) {
    const host = root.barFor(screenName)
    if (!anchor || !host) return 0

    const left = anchor.mapToItem(host, 0, 0).x
    const centre = left + anchor.width / 2

    const margin = Style.space(8)
    return Math.max(margin, Math.min(Math.round(centre - width / 2),
      Screens.widthOf(screenName) - width - margin))
  }

  function panelY(anchor, height, screenName) {
    const host = root.barFor(screenName)
    if (!anchor || !host) return 0

    const top = anchor.mapToItem(host, 0, 0).y
    const centre = top + anchor.height / 2

    const margin = Style.space(8)
    return Math.max(margin, Math.min(Math.round(centre - height / 2),
      Screens.heightOf(screenName) - height - margin))
  }

  // The invisible surfaces that dismiss everything.
  //
  // A panel surface only receives input that lands on it, so without this a
  // click anywhere else would pass straight through to whatever is underneath
  // and leave the panels stranded on screen. Each curtain covers everything the
  // bar on its screen does not and swallows that click. It deliberately stops
  // short of the bar itself, so the bar stays live and clicking a module still
  // works — which is how a second panel is opened without closing the first.
  //
  // One per screen with an open panel rather than one for the whole session: a
  // single window cannot cover two outputs at once.
  property Item windowHost: Item {
    visible: false

    Variants {
      model: root.curtainScreens

      delegate: PopupWindow {
        required property var modelData

        readonly property string screenName: String(modelData.name)
        readonly property var barItem: root.bars[screenName] || null

        // No `screen` here: a PopupWindow follows the window its anchor item is
        // in, and Quickshell refuses to set one directly. `modelData` is only
        // used for the dimensions below.
        visible: root.shown && barItem !== null
        color: "transparent"
        anchor.item: barItem

        // The popup's top-left lands on the rect's top-left and it grows down and
        // right, so the rect's origin is the one corner of the screen the bar
        // leaves free: below a top bar, above a bottom one, and beside a side bar.
        //
        // The rect's own size is empty on the axis the popup grows along; the size
        // below is what actually covers the screen.
        anchor.rect: root.position === "bottom"
          ? Qt.rect(0, 0, modelData.width, 0)
          : root.position === "left"
            ? Qt.rect(root.barExtent, 0, 0, modelData.height)
            : root.position === "right"
              ? Qt.rect(0, 0, 0, modelData.height)
              : Qt.rect(0, root.barExtent, modelData.width, 0)
        implicitWidth: root.vertical ? modelData.width - root.barExtent : modelData.width
        implicitHeight: root.vertical ? modelData.height : modelData.height - root.barExtent

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onPressed: root.closeForScreen(screenName)
        }
      }
    }

    // One window per open panel. A layer surface each, because the keyboard has to
    // live somewhere, and only the focused one asks for it.
    Instantiator {
      model: root.openPanels

      delegate: PanelWindow {
        id: panelWindow
        required property string name
        required property string screenName
        required property string key

        readonly property var entry: root.entries[panelWindow.key] || ({})

        // Loaded from the entry rather than from the model role: the screen can
        // disappear while the panel is up, in which case Quickshell's default
        // (the primary output) is the only place left to draw it.
        readonly property var screenInfo: Screens.byName(panelWindow.screenName)

        screen: panelWindow.screenInfo

        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        visible: true

        // The bar's edge decides both anchors. A panel always keeps the edge
        // that faces the bar (clear of it by the bar's thickness) and the
        // position along the other axis that its own button put it at.
        readonly property bool onRight: root.vertical && root.position === "right"
        readonly property bool onBottom: !root.vertical && root.position === "bottom"

        anchors.top: !panelWindow.onBottom
        anchors.bottom: panelWindow.onBottom
        anchors.left: !panelWindow.onRight
        anchors.right: panelWindow.onRight

        margins.top: panelWindow.onBottom
          ? 0
          : (root.vertical
            ? root.panelY(panelWindow.entry.anchor, panelWindow.implicitHeight, panelWindow.screenName)
            : root.barExtent)
        margins.bottom: panelWindow.onBottom ? root.barExtent : 0
        margins.left: panelWindow.onRight
          ? 0
          : (root.vertical
            ? root.barExtent
            : root.panelX(panelWindow.entry.anchor, panelWindow.implicitWidth, panelWindow.screenName))
        margins.right: panelWindow.onRight ? root.barExtent : 0

        // The focused panel is raised above the others: with panels anchored under
        // neighbouring icons they overlap, and Tab has to visibly bring one to the
        // front rather than only change where the keys go.
        WlrLayershell.layer: root.focused === panelWindow.key
          ? WlrLayer.Overlay
          : WlrLayer.Top
        WlrLayershell.namespace: "quickshell-panel"
        // Exclusive only for the panel the keys are on. None for the rest, which
        // is what hands the keyboard to the next one when Tab moves.
        WlrLayershell.keyboardFocus: root.focused === panelWindow.key
          ? WlrKeyboardFocus.Exclusive
          : WlrKeyboardFocus.None

        implicitWidth: loader.item ? loader.item.implicitWidth : 320
        implicitHeight: Math.min(
          root.maxHeightFor(panelWindow.screenInfo ? panelWindow.screenInfo.height : 1080),
          loader.item ? loader.item.implicitHeight : 0)

        Loader {
          id: loader
          anchors.fill: parent
          sourceComponent: panelWindow.entry.builder || null

          // The surface appears the moment the panel opens, but a card that
          // fades in over a tenth of a second reads as a panel opening rather
          // than a window being mapped underneath the pointer.
          opacity: 0
          Component.onCompleted: loader.opacity = 1
          Behavior on opacity {
            NumberAnimation { duration: Style.duration(110); easing.type: Easing.OutCubic }
          }
        }
      }
    }
  }
}
