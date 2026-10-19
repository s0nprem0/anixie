import QtQuick
import ".."

// A labelled on/off row: a name on the left, the switch on the right, with an
// optional line of explanation underneath.
//
// Several panels need "a thing, and a switch to turn it" — the Wi-Fi radio, the
// recording indicator, stay-awake. Hand-rolling that row each time is how the
// labels end up at different sizes and the switches at different offsets, so it
// lives here once.
//
// The caller owns the value: bind `checked` to real state and act on `toggled()`.
Item {
  id: root

  property string label: ""
  property string description: ""
  property bool checked: false
  property bool busy: false
  property color accent: Theme.accent

  // Whether the row takes input at all. Separate from `busy`, which keeps the row
  // looking live while one operation is in flight; this greys it out because the
  // control makes no sense for what is being asked here.
  property bool available: true

  signal toggled()

  readonly property bool hasDescription: root.description !== ""
  readonly property bool interactive: root.available && !root.busy

  implicitWidth: labelText.implicitWidth + Style.space(12) + switchItem.implicitWidth
  // `textColumn.height`, not its implicit height: the column states its own
  // height from the texts inside it, and an Item's implicit size is 0 unless it
  // says otherwise. Measuring the wrong one left a row with a description under
  // it exactly as tall as the switch, so the description was drawn outside the
  // row and ran into whatever came next in the panel.
  implicitHeight: Math.max(switchItem.implicitHeight, textColumn.height)
  height: implicitHeight

  ToggleSwitch {
    id: switchItem
    anchors.right: parent.right
    // On the row's top edge, level with the label's line: the row is as tall as
    // the switch for a label alone, and one line taller for a label with a
    // description under it.
    anchors.top: parent.top
    opacity: root.available ? 1 : 0.45
    checked: root.checked
    busy: root.busy
    accent: root.accent
    onToggled: if (root.interactive) root.toggled()
  }

  Item {
    id: textColumn
    anchors.left: parent.left
    anchors.right: switchItem.left
    anchors.rightMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    height: childrenRect.height

    Text {
      id: labelText
      text: root.label
      color: root.available ? Theme.fg : Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      renderType: Text.NativeRendering
      width: parent.width
      elide: Text.ElideRight
    }

    Text {
      text: root.description
      visible: root.hasDescription
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
      width: parent.width
      elide: Text.ElideRight
      topPadding: root.hasDescription ? Style.space(2) : 0
      anchors.top: labelText.bottom
    }
  }
}