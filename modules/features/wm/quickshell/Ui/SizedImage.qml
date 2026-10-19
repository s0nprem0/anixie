import QtQuick
import ".."

// An image that fits a box without distorting itself.
//
// The obvious Image scales its `sourceSize` to fill the box and will stretch a
// picture to whatever shape the box happens to be; set `fillMode` and the
// painting gets its own maths but the item still claims the full box, so a
// parent laying out a row reserves the wrong height for it. This keeps the box
// honest: it takes the size you give it and fits the picture inside, centred,
// cropping rather than distorting when the aspect does not match.
Item {
  id: root

  property url source: ""
  property int fillMode: Image.PreserveAspectFit
  property color placeholderColor: Theme.muted
  // Named `smoothing`, not `smooth`, because Item already has a `smooth` of its
  // own and shadowing it is the sort of thing that behaves differently than it
  // reads. This is the image's own setting.
  property bool smoothing: true

  // The aspect ratio the source really has, so a caller that wants a predictable
  // box can ask for it before the image has loaded. Zero until it has.
  readonly property real sourceAspect: image.sourceSize.width > 0 && image.sourceSize.height > 0
    ? image.sourceSize.width / image.sourceSize.height
    : 0

  implicitWidth: Style.space(200)
  implicitHeight: Style.space(120)

  Image {
    id: image
    anchors.fill: parent
    source: root.source
    fillMode: root.fillMode
    asynchronous: true
    smooth: root.smoothing
    // Greyed out rather than tinted: the picture's own colours are the point, and
    // a palette tint over it would misreport what the user chose.
    opacity: image.status === Image.Ready ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Style.duration(140) } }
  }
}