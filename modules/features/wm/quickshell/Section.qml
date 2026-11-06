pragma ComponentBehavior: Bound
import QtQuick
import "."
import "Ui"

// One run of bar modules, as named by a bar.json section.
//
// Horizontal bars stack modules in a row; vertical ones need a column, so this
// picks its positioner from the orientation rather than forcing every module to
// know which way up the bar is.
Item {
  id: root

  // A section is part of the bar, so it goes when the bar goes. The window stays
  // mapped behind it — that is what keeps a hotkey-opened panel's anchor alive —
  // so hiding the contents is what actually makes the bar disappear.
  visible: BarContext.shown

  property var entries: []

  // Which bar.json section this is, so a module can be told which edge of itself
  // stays put when it grows. Set by shell.qml.
  property string name: ""
  property string screenName: ""

  readonly property bool vertical: BarContext.vertical

  implicitWidth: vertical ? Style.bar.sizeVertical : row.implicitWidth
  implicitHeight: vertical ? column.implicitHeight : Style.bar.sizeHorizontal

  // The Loaders this section is drawing, in layout order. Discovered through the
  // Repeater's own itemAt() rather than by walking Item.children: the children
  // list also holds the Repeater object and is not a public contract for
  // delegate ownership, while itemAt() is the Repeater's documented accessor
  // and returns the delegate at a model index (or null while it is loading).
  function widgets() {
    const repeater = root.vertical ? columnRepeater : rowRepeater
    const out = []

    if (!repeater) return out

    for (let i = 0; i < repeater.count; i++) {
      const loader = repeater.itemAt(i)
      if (loader) out.push(loader)
    }

    return out
  }

  // Registration follows the name. Re-registering on a change keeps the drag
  // registry from holding a section under a stale name; BarDrag.registerSection
  // replaces the entry for the same item, so this cannot duplicate.
  Component.onCompleted: BarDrag.registerSection(root.name, root)
  Component.onDestruction: BarDrag.unregisterSection(root.name, root)
  onNameChanged: BarDrag.registerSection(root.name, root)

  // Hiding the bar must not leave a drag or tooltip dangling over nothing.
  onVisibleChanged: {
    if (root.visible) return

    try { TooltipHost.clear() } catch (e) { }
    try { if (BarDrag.active) BarDrag.cancel() } catch (e) { }
  }

  Row {
    id: row
    visible: !root.vertical
    anchors.centerIn: parent

    // Modules are laid out as separate blocks rather than one continuous run.
    spacing: Theme.gap

    ModuleRepeater {
      id: rowRepeater
      modules: !root.vertical ? root.entries : []
      sectionName: root.name
      screenName: root.screenName
    }
  }

  Column {
    id: column
    visible: root.vertical
    anchors.centerIn: parent
    spacing: Theme.gap

    ModuleRepeater {
      id: columnRepeater
      modules: root.vertical ? root.entries : []
      sectionName: root.name
      screenName: root.screenName
    }
  }
}