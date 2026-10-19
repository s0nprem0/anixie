import QtQuick
import ".."

// A labelled slider: a name and its value on one line, a slider the full width of
// the panel beneath them.
//
// Full width rather than a control crammed into the right of a labelled row. A
// slider three-quarters of the width is easier to hit and easier to read, and it
// leaves the number somewhere it can actually be seen — in the header, with room
// around it — instead of fighting the handle for the same few pixels. The value
// is repeated beside every slider in the shell now; the header is where it goes.
//
// The value is *given* to the control (`value`) and *reported* back (`moved`).
// It is never written into `value`, which is deliberate: a slider that writes
// its own `value` destroys whatever binding was on it, and a binding that
// silently stops applying is worse than none — the control goes on showing the
// level it was left at, while the panel's caption beside it (which reads the
// real one) moves on, and the two disagree.
Item {
  id: root

  // Header line. Left empty where there is nothing to name — a per-application
  // mixer row is named by the name itself.
  property string label: ""

  // What the header says on the right: "45%", "muted", "—".
  property string value: ""

  property real from: 0
  property real to: 100
  property real stepSize: 1

  // The real level, bound from outside. The slider follows it.
  property real level: 0

  // Whether the control makes sense for what is being asked. A slider with no
  // device behind it is drawn, dimmed, rather than removed: its absence would
  // read as the panel having forgotten something.
  property bool available: true

  signal moved(real value)

  readonly property bool hasLabel: root.label !== ""

  implicitWidth: headerRow.implicitWidth
  // `height`, not `implicitHeight`: the header row states its own height from
  // the texts in it, and an Item's implicit size is 0 unless it says otherwise.
  implicitHeight: headerRow.height + (root.hasLabel ? Style.space(2) : 0) + slider.implicitHeight
  // A Panel is a Column, which positions children by their height rather than
  // their implicit height.
  height: implicitHeight

  Item {
    id: headerRow
    width: parent.width
    height: Math.max(labelText.implicitHeight, valueText.implicitHeight)

    visible: root.hasLabel || root.value !== ""

    Text {
      id: labelText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - valueText.width - Style.space(8)
      text: root.label
      color: root.available ? Theme.fg : Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
      renderType: Text.NativeRendering
    }

    Text {
      id: valueText
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: root.value
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.weight: Font.DemiBold
      renderType: Text.NativeRendering
    }
  }

  Slider {
    id: slider
    anchors.top: headerRow.visible ? headerRow.bottom : parent.top
    anchors.topMargin: root.hasLabel ? Style.space(2) : 0
    anchors.left: parent.left
    anchors.right: parent.right
    width: parent.width
    from: root.from
    to: root.to
    stepSize: root.stepSize
    enabled: root.available

    // The binding is put back the moment the drag ends rather than written once
    // and left broken: while the pointer is down the slider is the truth, and
    // afterwards the panel's own value is again. Anything that changes the
    // level from outside — a keybind, the OSD, another panel — moves the handle
    // straight away instead of leaving it stranded.
    Binding {
      target: slider
      property: "value"
      value: root.level
      when: !slider.pressed
    }

    onMoved: root.moved(slider.value)
  }
}