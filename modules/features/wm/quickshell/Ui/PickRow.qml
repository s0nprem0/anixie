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
// Screenshot — region" — and saves a line of height per group.

Item {
  id: root

  property string label: ""
  property string group: ""
  property string state: ""
  property string description: ""
  property string icon: ""
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

  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: Style.space(4)
    anchors.rightMargin: Style.space(4)
    radius: Theme.cornerRadius
    color: root.selected
      ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.selectedFillAlpha)
      : "transparent"
  }

  Image {
    id: iconImage

    anchors.left: parent.left
    anchors.leftMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter

    visible: root.showIcon && root.icon !== ""
    width: visible ? Style.space(18) : 0
    height: width
    sourceSize.width: width * 2
    sourceSize.height: width * 2
    fillMode: Image.PreserveAspectFit
    smooth: true
    // A desktop entry can name an icon that is not installed, and a missing one
    // is normal rather than an error: the row is still worth showing.
    source: root.icon !== "" ? Quickshell.iconPath(root.icon, "") : ""
  }

  Row {
    id: textRow

    // The row starts at the same inset whether or not there is an icon, so a
    // list mixing entries that have icons with entries that do not — the menu,
    // where only the applications have one — does not step in and out.
    anchors.left: iconImage.visible ? iconImage.right : parent.left
    anchors.leftMargin: Style.space(12)
    anchors.right: stateLabel.left
    anchors.rightMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(8)

    Text {
      visible: root.group !== ""
      text: root.group + "›"
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle
      anchors.verticalCenter: textRow.verticalCenter
    }

    Repeater {
      model: root.spans

      Text {
        required property var modelData

        text: modelData.text
        color: modelData.hit ? Theme.accent : Theme.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.weight: modelData.hit ? Font.DemiBold : Font.Normal
        anchors.verticalCenter: textRow.verticalCenter
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
  }
}