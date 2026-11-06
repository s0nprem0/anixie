pragma ComponentBehavior: Bound
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
  component Badge: Rectangle {
    id: badge

    property string label: ""
    property color labelColor: Theme.fg
    property color badgeBorder: Theme.border

    implicitWidth: badgeText.implicitWidth + Style.space(12)
    implicitHeight: badgeText.implicitHeight + Style.space(6)
    radius: Theme.cornerRadius
    color: Theme.surface
    border.color: badge.badgeBorder
    border.width: Style.strokeWidth

    Text {
      id: badgeText
      anchors.centerIn: parent
      text: badge.label
      color: badge.labelColor
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      renderType: Text.NativeRendering
    }
  }
  id: root

  property string source: ""
  property bool pinned: false
  property int revision: 0

  // Set by the shell from CapturePreview.copyFailed: the copy `shot` makes
  // before the card is revealed did not reach the clipboard. Kept as a property
  // rather than read from the singleton so the card stays usable on its own.
  property bool copyFailed: false

  signal opened()
  signal annotated()
  signal pinToggled()
  signal dismissed()
  signal copySucceeded()
  signal copyFailure()
  signal hoverEntered()
  signal hoverExited()
  signal retried()

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

  // A new capture replaces the image in the same card, so the confirmations
  // belong to the file that earned them. Without this a fresh screenshot could
  // carry the previous one's "Copied" for a second and a half.
  onSourceChanged: {
    root.copied = false
    root.copyFailedHere = false
    root.openFailed = false
  }

  property bool copied: false

  // The copy that `shot` makes on the default path is the one most captures are
  // for, so a failure to reach the clipboard has to be visible rather than
  // logged. `copyFailed` arrives from the shell; `copyFailedHere` is the same
  // failure discovered here, when the Copy button is pressed.
  readonly property bool copyFailureShown: (root.copyFailed || root.copyFailedHere) && !root.copied
  property bool copyFailedHere: false

  property Process copyProc: Process {
    running: false
    onExited: function (exitCode, exitStatus) {
      if (exitCode === 0) {
        root.copied = true
        root.copyFailedHere = false
        copiedTimer.restart()
        root.copySucceeded()
      } else {
        root.copied = false
        root.copyFailedHere = true
        root.copyFailure()
      }
    }
  }

  function copyToClipboard() {
    if (root.source === "") return
    root.copied = false
    root.copyProc.command = ["sh", "-c", "wl-copy --type image/png < " + Util.shellQuote(root.source)]
    root.copyProc.running = false
    root.copyProc.running = true
  }

  // Opening the file in whatever viewer the desktop has. It runs here rather
  // than in the shell so the failure is a badge on the card the user is already
  // looking at, instead of a process that exits non-zero with nobody watching.
  property bool openFailed: false

  property Process openProc: Process {
    running: false
    onExited: function (exitCode, exitStatus) {
      if (exitCode !== 0) {
        root.openFailed = true
        openFailedTimer.restart()
      }
    }
  }

  function openCapture() {
    if (root.source === "") return
    root.openProc.command = ["sh", "-c", "test -f \"$1\" && exec xdg-open \"$1\"", "sh", root.source]
    root.openProc.running = false
    root.openProc.running = true
    root.opened()
  }

  Rectangle {
    anchors.fill: parent
    radius: Theme.cornerRadius
    color: Theme.surface
    border.color: Theme.border
    border.width: Style.strokeWidth
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onEntered: root.hoverEntered()
    onExited: root.hoverExited()
    onClicked: root.openCapture()
    cursorShape: Qt.PointingHandCursor
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

  // Deliberate loading and failure states so a rapid replacement never shows a
  // blank or stale image without explanation.
  Rectangle {
    visible: preview.status === Image.Loading || preview.status === Image.Error
    anchors.fill: preview
    radius: Theme.cornerRadius
    color: Theme.surface
    border.color: Theme.border
    border.width: Style.strokeWidth

    Text {
      anchors.centerIn: parent
      text: preview.status === Image.Error ? "Could not load capture — click to retry" : "Loading capture…"
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      renderType: Text.NativeRendering
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      enabled: preview.status === Image.Error
      onClicked: root.retried()
    }
  }

  // The whole capture is one click away.
  MouseArea {
    anchors.fill: preview
    cursorShape: Qt.PointingHandCursor
    hoverEnabled: true
    propagateComposedEvents: true
    onClicked: function (mouse) {
      root.openCapture()
      mouse.accepted = false
    }
  }

  // Hovering the card holds it open, so reading a capture is not a race against
  // the ten-second timer. On the card rather than on the image, because moving
  // from the image to a button must not count as leaving.
  HoverHandler {
    id: cardHover
    onHoveredChanged: cardHover.hovered ? root.hoverEntered() : root.hoverExited()
  }

  Item {
    id: actions
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.margins: Style.space(6)
    width: actionRow.implicitWidth
    height: actionRow.implicitHeight
    z: 30
    opacity: cardHover.hovered || root.pinned ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
      NumberAnimation { duration: Style.duration(Style.motion.fast); easing.type: Easing.OutCubic }
    }

    Rectangle {
      anchors.fill: actionRow
      anchors.margins: -Style.space(2)
      radius: Theme.cornerRadius
      color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.9)
      border.color: Theme.border
      border.width: Style.strokeWidth
    }

    Row {
      id: actionRow
      spacing: Style.space(2)
      padding: Style.space(2)

      WidgetButton {
        text: Util.copy
        fontSize: Style.bar.iconFont
        tooltipText: root.copyFailureShown ? "Copy failed — try again" : "Copy again"
        onPressed: function () { root.copyToClipboard() }
      }

      WidgetButton {
        text: Util.folder
        fontSize: Style.bar.iconFont
        tooltipText: "Show in folder"
        onPressed: function () {
          if (root.source !== "")
            showInFolder.running = true
        }
      }

      WidgetButton {
        text: Util.link
        fontSize: Style.bar.iconFont
        tooltipText: "Copy path"
        onPressed: function () {
          if (root.source !== "")
            copyPath.running = true
        }
      }

      WidgetButton {
        text: Util.copy
        fontSize: Style.bar.iconFont
        tooltipText: "Copy file URI"
        onPressed: function () {
          if (root.source !== "")
            copyUri.running = true
        }
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
        tooltipText: root.pinned ? "Let it close (Super+Alt+Esc)" : "Keep on screen (Super+Alt+Esc)"
        active: root.pinned
        selected: root.pinned
        onPressed: function () { root.pinToggled() }
      }

      WidgetButton {
        text: Util.close
        fontSize: Style.bar.iconFont
        tooltipText: "Dismiss (Super+Esc)"
        onPressed: function () { root.dismissed() }
      }
    }
  }

  // Status line - only show on hover or when there are issues
  Column {
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.margins: Style.space(6)
    spacing: Style.space(4)
    z: 30
    opacity: (cardHover.hovered || root.pinned || root.copyFailureShown || root.openFailed || root.copied || root.clipped) ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
      NumberAnimation { duration: Style.duration(Style.motion.fast); easing.type: Easing.OutCubic }
    }

    Badge {
      visible: root.copyFailureShown
      label: "Copy failed — retry"
      labelColor: Theme.danger
      badgeBorder: Theme.danger
    }

    Badge {
      visible: root.openFailed
      label: "Couldn't open the capture"
      labelColor: Theme.danger
      badgeBorder: Theme.danger
    }

    Badge {
      visible: root.clipped && cardHover.hovered
      label: "Click to open full capture"
      labelColor: Theme.muted
      badgeBorder: Theme.border
    }

    Badge {
      visible: root.pinned
      label: "Pinned"
      labelColor: Theme.primary
      badgeBorder: Theme.primary
    }

    Badge {
      visible: root.copied
      label: "Copied"
    }
  }

  Timer {
    id: copiedTimer
    interval: 1500
    repeat: false
    onTriggered: root.copied = false
  }

  Timer {
    id: openFailedTimer
    interval: 4000
    repeat: false
    onTriggered: root.openFailed = false
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

  Process {
    id: copyPath
    command: ["sh", "-c", "test -f \"$1\" && printf '%s' \"$1\" | wl-copy --type text/plain", "sh", root.source]
  }

  Process {
    id: copyUri
    command: ["sh", "-c", "test -f \"$1\" && uri=\"file://$(realpath -- \"$1\" 2>/dev/null || printf '%s' \"$1\")\" && printf '%s\n' \"$uri\" | wl-copy --type text/uri-list", "sh", root.source]
  }

  Process {
    id: showInFolder
    command: ["sh", "-c", "test -f \"$1\" && { if command -v dbus-send >/dev/null 2>&1; then dbus-send --session --print-reply --dest=org.freedesktop.FileManager1 --type=method_call /org/freedesktop/FileManager1 org.freedesktop.FileManager1.ShowItems array:string:\"file://$(realpath -- \"$1\" 2>/dev/null || printf '%s' \"$1\")\" string:\"\" >/dev/null 2>&1 && exit 0; fi; xdg-open \"$(dirname \"$1\")\" >/dev/null 2>&1; }", "sh", root.source]
  }
}
