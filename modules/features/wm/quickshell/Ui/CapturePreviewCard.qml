import QtQuick
import Quickshell.Io
import ".."

// The preview card: the capture, fitted to its own aspect ratio inside a fixed
// maximum, with copy, annotate, pin and dismiss over the top-right corner.
//
// The image is fitted rather than forced into a fixed box. A landscape capture
// takes the full width and whatever height its ratio needs; a portrait one
// keeps the full height and narrows the card instead. Only an extreme ratio —
// a stitched scrolling capture — is cropped, because fitting a 1920x24000
// image into a 360px box would otherwise show a twenty-pixel-wide sliver.
// Cropping keeps the top of the capture, which is where a page starts, and the
// card can be opened with a click for the whole file.
Item {
  id: root

  property string source: ""
  property bool pinned: false
  property int revision: 0

  signal opened()
  signal annotated()
  signal pinToggled()
  signal dismissed()

  readonly property int maxWidth: Style.space(360)
  readonly property int maxHeight: Style.space(250)
  readonly property int minWidth: Style.space(72)
  readonly property int minHeight: Style.space(48)
  readonly property int padding: Style.space(8)

  readonly property bool loaded: preview.implicitWidth > 0 && preview.implicitHeight > 0

  readonly property real aspect: root.loaded
    ? preview.implicitWidth / preview.implicitHeight
    : 1

  // Fit inside maxWidth x maxHeight. Computed directly rather than with
  // Image.PreserveAspectFit alone, because the card has to know the result to
  // size its own window.
  readonly property real scaleToFit: root.loaded
    ? Math.min(root.maxWidth / preview.implicitWidth, root.maxHeight / preview.implicitHeight)
    : 1

  readonly property real fitWidth: preview.implicitWidth * root.scaleToFit
  readonly property real fitHeight: preview.implicitHeight * root.scaleToFit

  // Tall and narrower than the smallest readable width: show the top of it at
  // full width instead of shrinking to a sliver.
  readonly property bool clipped: root.loaded && root.aspect < 1 && root.fitWidth < root.minWidth

  // The maximum box while the image is still decoding, so the window does not
  // open at thumbnail size and then jump to its real shape.
  readonly property real imageWidth: !root.loaded
    ? root.maxWidth
    : (root.clipped ? root.maxWidth : Math.max(root.minWidth, root.fitWidth))
  readonly property real imageHeight: !root.loaded
    ? root.maxHeight
    : (root.clipped ? root.maxHeight : Math.max(root.minHeight, root.fitHeight))

  readonly property bool annotating: annotate.running

  implicitWidth: root.imageWidth + root.padding * 2
  implicitHeight: root.imageHeight + root.padding * 2

  property bool copied: false

  function copyToClipboard() {
    Commands.run("wl-copy --type image/png < " + Util.shellQuote(root.source))
    root.copied = true
    copiedTimer.restart()
  }

  Rectangle {
    anchors.fill: parent
    radius: Theme.cornerRadius
    color: Theme.surface
    border.color: Theme.border
    border.width: Style.strokeWidth
  }

  Image {
    id: preview

    anchors.fill: parent
    anchors.margins: root.padding

    // file:// because the path from `shot` is absolute; a bare path is treated as
    // a resource and silently loads nothing. The revision is part of the URL so
    // an in-place annotation of the same file is decoded again instead of
    // showing the pixels Qt already has.
    source: root.source === "" ? "" : "file://" + root.source + "?v=" + root.revision

    // Set from onStatusChanged rather than bound: a fillMode binding that is
    // re-evaluated while the image is decoding can restart the asynchronous
    // load, and a portrait capture then never reaches Ready.
    fillMode: Image.PreserveAspectFit
    verticalAlignment: Image.AlignTop
    onSourceChanged: fillMode = Image.PreserveAspectFit
    asynchronous: true
    cache: false

    // Decoded at twice the card width, rather than at the capture's own size. A
    // 4K screenshot kept at full resolution for a thumbnail is memory spent on
    // pixels that are then scaled away. Only one dimension is given, so the
    // aspect ratio is preserved and the card can trust implicitWidth/Height.
    sourceSize.width: root.maxWidth * 2

    onStatusChanged: {
      if (status === Image.Ready) {
        fillMode = root.clipped ? Image.PreserveAspectCrop : Image.PreserveAspectFit
      }
    }
  }

  // The whole capture is one click away. This sits below the buttons in the
  // stacking order, so a click on one of those never reaches it.
  MouseArea {
    anchors.fill: preview
    cursorShape: Qt.PointingHandCursor
    onClicked: root.opened()
  }

  Row {
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.margins: Style.space(10)
    spacing: Style.space(2)

    WidgetButton {
      text: Util.copy
      fontSize: Style.bar.iconFont
      tooltipText: "Copy again"
      onPressed: function () { root.copyToClipboard() }
    }

    WidgetButton {
      text: Util.annotate
      fontSize: Style.bar.iconFont
      tooltipText: root.annotating ? "Annotating…" : "Annotate"
      interactive: !root.annotating
      onPressed: function () { annotate.running = true }
    }

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

  // A tall capture is cropped at the top, so say that rather than letting the
  // cut-off image look like the whole thing.
  Rectangle {
    visible: root.clipped && !root.copied
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.margins: root.padding + Style.space(4)
    implicitWidth: tallLabel.implicitWidth + Style.space(12)
    implicitHeight: tallLabel.implicitHeight + Style.space(6)
    radius: Theme.cornerRadius
    color: Theme.surface
    border.color: Theme.border
    border.width: Style.strokeWidth

    Text {
      id: tallLabel
      anchors.centerIn: parent
      text: "Click to open the full capture"
      color: Theme.fg
      font.family: Style.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  // A quiet confirmation that the copy actually happened. It sits over the
  // bottom of the image and disappears on its own, so it never competes with
  // the capture for attention.
  Rectangle {
    visible: root.copied
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.margins: root.padding + Style.space(4)
    implicitWidth: copiedLabel.implicitWidth + Style.space(12)
    implicitHeight: copiedLabel.implicitHeight + Style.space(6)
    radius: Theme.cornerRadius
    color: Theme.surface
    border.color: Theme.border
    border.width: Style.strokeWidth

    Text {
      id: copiedLabel
      anchors.centerIn: parent
      text: "Copied"
      color: Theme.fg
      font.family: Style.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  Timer {
    id: copiedTimer
    interval: 1500
    repeat: false
    onTriggered: root.copied = false
  }

  // Annotating in place keeps the file's name, so the next capture's unique-name
  // search and the preview's path both stay valid. Saving over the same file is
  // also what makes the refresh in the shell a one-liner.
  Process {
    id: annotate
    command: ["sh", "-c", "test -f \"$1\" && exec satty --filename \"$1\" --output-filename \"$1\" --initial-tool crop", "sh", root.source]
    onExited: function (exitCode) {
      if (exitCode === 0) root.annotated()
    }
  }
}
