import QtQuick
import Quickshell
import ".."

// One row of the picker.
//
// The label is drawn as a run of spans rather than one string, because the
// characters the query actually matched are worth marking: it is the only thing
// that tells you *why* a row is in the list, which is the whole bargain of a
// fuzzy search. "cap" matching "C**a**pture" explains itself; a list that simply
// contains the entry does not.
//
// The group is a dimmed prefix in front of the label rather than a header above
// it, which keeps the paths the menu shows as one readable line — "Capture ›
// Screenshot — region" — and saves a line of height per group. The caller
// passes it on the first row of a run and leaves it empty for the rest (see
// PickHost.groupOf), so the path marks where a group begins rather than
// repeating down it.

Item {
  id: root

  property string label: ""
  property string group: ""
  property string state: ""
  property string description: ""
  property string icon: ""
  property string preview: ""
  property var positions: []
  property bool selected: false
  property bool showIcon: true

  implicitHeight: Style.space(32)

  // The label cut into runs of matched and unmatched characters.
  //
  // Rebuilt only when the label or the matched positions change: this runs on
  // every keystroke for every visible row, and rebuilding it for a row that has
  // not changed is most of what a picker does while you type.
  readonly property var spans: root.buildSpans()

  readonly property bool hasPreview: root.preview !== ""

  function buildSpans() {
    const text = String(root.label)
    const hits = {}
    for (let i = 0; i < root.positions.length; i++) hits[root.positions[i]] = true

    const out = []
    let run = ""
    let runHit = false

    for (let i = 0; i < text.length; i++) {
      const hit = !!hits[i]
      if (run.length > 0 && hit !== runHit) {
        out.push({ text: run, hit: runHit })
        run = ""
      }
      runHit = hit
      run += text.charAt(i)
    }

    if (run.length > 0) out.push({ text: run, hit: runHit })
    return out
  }

  // The pointer, without taking it: a HoverHandler leaves clicks to whatever
  // already handles them, and every other list in the shell lights up under the
  // cursor — this one, the menu, was the exception.
  HoverHandler {
    id: pointer
  }

  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: Style.space(4)
    anchors.rightMargin: Style.space(4)
    radius: Theme.cornerRadius
    color: root.selected
      ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b,
          pointer.hovered
            ? Style.control.rowSelectedHoverAlpha
            : Style.control.selectedFillAlpha)
      : (pointer.hovered
        ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.rowHoverAlpha)
        : "transparent")

    Behavior on color {
      ColorAnimation { duration: Style.duration(Style.motion.base); easing.type: Easing.OutCubic }
    }
  }

  // The icon slot, held whether or not this row has an icon. Only the
  // applications in the menu carry one, and a row that gave the slot up would
  // pull its label twelve pixels to the left of its neighbours' — the list would
  // step in and out down its length. The slot is drawn empty instead, so a mixed
  // list still lines up.
  Image {
    id: iconImage

    visible: root.showIcon
    anchors.left: parent.left
    anchors.leftMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter

    width: root.hasPreview ? Style.space(24) : Style.space(18)
    height: width
    sourceSize.width: width * 2
    sourceSize.height: width * 2
    fillMode: root.hasPreview ? Image.PreserveAspectCrop : Image.PreserveAspectFit
    smooth: true
    // A clipboard thumbnail takes the icon slot when there is one. A desktop
    // entry can name an icon that is not installed, and a missing one is normal
    // rather than an error: the row is still worth showing. The existence check
    // is what keeps it blank — without it `iconPath` still returns an image URL,
    // and the provider fills it with its black and purple missing-icon square.
    readonly property string iconSource: {
      if (root.hasPreview) return "file://" + root.preview
      if (root.icon === "") return ""
      if (root.icon.charAt(0) === "/") return "file://" + root.icon
      return Quickshell.iconPath(root.icon, true)
    }

    opacity: iconSource !== "" ? 1 : 0
    source: iconSource
  }

  Row {
    id: textRow

    // Against the slot's right edge when there is a slot at all, and the row's
    // own edge when the caller turned icons off.
    anchors.left: root.showIcon ? iconImage.right : parent.left
    anchors.leftMargin: Style.space(12)
    anchors.right: stateLabel.left
    anchors.rightMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(8)

    Text {
      visible: root.group !== ""
      text: root.group + " ›"
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle
      renderType: Text.NativeRendering
      anchors.verticalCenter: textRow.verticalCenter
    }

    // The label's spans live in a Row of their own with no spacing. A Row spaces
    // every child, and the spans are one word cut into pieces — matched and
    // unmatched runs — so the outer spacing put a gap at each highlight
    // boundary: searching `sy` drew "Sy stem" instead of "System". The spacing
    // stays on the outer row so the group keeps its gap from the label.
    Row {
      spacing: 0
      anchors.verticalCenter: textRow.verticalCenter

      Repeater {
        model: root.spans

        Text {
          required property var modelData

          text: modelData.text
          color: modelData.hit ? Theme.accent : Theme.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          font.weight: modelData.hit ? Font.DemiBold : Font.Normal
          renderType: Text.NativeRendering
        }
      }
    }
  }

  Text {
    id: stateLabel

    anchors.right: parent.right
    anchors.rightMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter

    visible: root.state !== ""
    text: root.state
    color: Theme.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    renderType: Text.NativeRendering
  }
}