import QtQuick
import ".."

// A number you nudge: a value with a minus and a plus beside it, and nothing to
// type into.
//
// Typing a number is the wrong interaction for a value that only moves in steps
// and has a hard range — brightness, scale, text size. It is slower than two
// clicks, it admits values the value cannot take, and it puts a caret in a
// setting nobody is editing as prose. This is the same control as the reference
// shell's stepper, and the shell keeps one of them wherever a panel wants to
// move a number by a known amount.
Item {
  id: root

  property real value: 0
  property real from: 0
  property real to: 100
  property real step: 1
  property int decimals: 0

  // Formatting is shared with the label so the two never disagree about how the
  // number reads — 1.5 and 1.50 are the same value and should not look like
  // different settings.
  property string prefix: ""
  property string suffix: ""

  signal changed(real value)

  // ---- the keyboard ----
  //
  // A stepper is a slider in clicks, so the same keys do the same thing: left and
  // right nudge the value a step, and Return nudges it up, which is the more
  // common direction.
  readonly property bool panelFocusable: true

  function activate() {
    root.move(1)
  }

  function keyStep(direction) {
    root.move(direction)
    return true
  }

  readonly property bool canDecrease: root.value > root.from
  readonly property bool canIncrease: root.value < root.to

  readonly property int button: Style.space(22)

  function display() {
    return root.prefix + Number(root.value).toFixed(root.decimals) + root.suffix
  }

  // Clamped to the range and rounded to the step's own precision, so pressing
  // plus repeatedly past the top stops on the top rather than overshooting into
  // a value nothing accepts.
  function move(delta) {
    const span = root.to - root.from
    const scale = Math.pow(10, root.decimals)
    const stepped = Math.round((root.value + delta * root.step - root.from) * scale) / scale
    const next = Math.min(root.to, Math.max(root.from, root.from + stepped))
    if (next === root.value) return
    root.value = next
    root.changed(next)
  }

  implicitWidth: minusButton.width + Style.space(6) + valueText.implicitWidth + Style.space(6) + plusButton.width
  implicitHeight: button
  height: implicitHeight

  PanelActionStep {
    id: minusButton
    width: root.button
    height: root.button
    glyph: "−"
    enabled: root.canDecrease
    onClicked: root.move(-1)
  }

  Text {
    id: valueText
    anchors.centerIn: parent
    width: Math.min(implicitWidth, root.width - root.button * 2 - Style.space(12))
    text: root.display()
    color: Theme.fg
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideRight
    renderType: Text.NativeRendering
  }

  PanelActionStep {
    id: plusButton
    width: root.button
    height: root.button
    glyph: "+"
    enabled: root.canIncrease
    onClicked: root.move(1)
  }

  // The square a stepper step is drawn in, kept local to this component so the
  // two buttons cannot drift apart. `enabled` is Item's own, not a new one — the
  // plus and minus set it directly when the value is at a bound.
  component PanelActionStep: Item {
    id: step

    property string glyph: ""

    signal clicked()

    readonly property bool live: step.enabled && mouse.containsMouse

    Rectangle {
      anchors.fill: parent
      radius: Theme.cornerRadius
      color: step.enabled
        ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, step.live ? Style.control.selectedFillAlpha : Style.control.hoverFillAlpha)
        : "transparent"
      Behavior on color { NumberAnimation { duration: Style.duration(120) } }
    }

    Text {
      anchors.centerIn: parent
      text: step.glyph
      color: step.enabled ? (step.live ? Theme.primary : Theme.fg) : Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      renderType: Text.NativeRendering
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      enabled: step.enabled
      hoverEnabled: true
      cursorShape: step.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: step.clicked()
    }
  }
}