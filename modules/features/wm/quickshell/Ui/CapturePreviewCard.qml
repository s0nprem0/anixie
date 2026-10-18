import QtQuick
import ".."

// The preview card: the capture, fitted inside a fixed box, with a pin button and
// a dismiss button over the top-right corner.
//
// The box is a fixed size rather than the image's own, so a 6K capture and a
// 200px one both come up as the same card and the buttons are always in the same
// place. The image is fitted inside it and decoded no larger than it needs to be.
Item {
  id: root

  property string source: ""
  property bool pinned: false

  signal pinToggled()
  signal dismissed()

  readonly property int boxWidth: Style.space(360)
  readonly property int boxHeight: Style.space(250)
  readonly property int padding: Style.space(8)

  implicitWidth: boxWidth + padding * 2
  implicitHeight: boxHeight + padding * 2

  Rectangle {
    anchors.fill: parent
    radius: Theme.cornerRadius
    color: Theme.surface
    border.color: Theme.muted
    border.width: 1
  }

  Image {
    id: preview

    anchors.fill: parent
    anchors.margins: root.padding

    // file:// because the path from `shot` is absolute; a bare path is treated as
    // a resource and silently loads nothing.
    source: root.source === "" ? "" : "file://" + root.source

    fillMode: Image.PreserveAspectFit
    asynchronous: true
    cache: false

    // Decoded down to the box, rather than at the capture's own size. A 4K
    // screenshot kept at full resolution for a thumbnail is memory spent on
    // pixels that are then scaled away.
    sourceSize.width: root.boxWidth
    sourceSize.height: root.boxHeight
  }

  Row {
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.margins: Style.space(10)
    spacing: Style.space(2)

    WidgetButton {
      text: Util.pin
      fontSize: Style.bar.iconFont
      tooltipText: root.pinned ? "Let it close" : "Keep on screen"
      active: root.pinned
      selected: root.pinned
      onPressed: function () { root.pinToggled() }
    }

    WidgetButton {
      text: Util.close
      fontSize: Style.bar.iconFont
      tooltipText: "Dismiss"
      onPressed: function () { root.dismissed() }
    }
  }
}
