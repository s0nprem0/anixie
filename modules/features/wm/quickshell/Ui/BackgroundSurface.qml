import QtQuick
import ".."

// One output's wallpaper.
//
// Two layers, so a change fades rather than blinking: the old frame stays opaque
// under the new one while the new one comes up over it. AnimatedImage is used for
// every file, which gives GIF and animated WebP the same path as a still JPEG.
Item {
  id: root

  property string source: ""

  // The host's counter, not the path: a theme can rewrite the generated file
  // under the same name, and the surface then has to reload it.
  property int revision: 0

  property string shownPath: ""
  property int shownRevision: -1
  property string outgoingPath: ""
  property real reveal: 1
  property bool syncQueued: false

  function url(path) {
    if (path === "") return ""
    return path.indexOf("/") === 0 ? "file://" + path : path
  }

  // Both properties change together on a switch, so settle them for one
  // event-loop turn before deciding whether this is a new path or the same file
  // rewritten. Acting on each assignment separately animated twice.
  onSourceChanged: root.scheduleSync()
  onRevisionChanged: root.scheduleSync()

  function scheduleSync() {
    if (root.syncQueued) return
    root.syncQueued = true
    Qt.callLater(root.sync)
  }

  function sync() {
    root.syncQueued = false

    const pathChanged = root.source !== root.shownPath
    const revisionChanged = root.revision !== root.shownRevision
    if (!pathChanged && !revisionChanged) return

    // The first frame is not a transition; there is nothing to crossfade from.
    if (root.shownPath === "") {
      root.shownPath = root.source
      root.shownRevision = root.revision
      root.outgoingPath = ""
      root.reveal = 1
      return
    }

    // Same file, rewritten in place: keep it as the outgoing frame and reload
    // the incoming layer by emptying its source for a turn.
    if (!pathChanged) {
      root.outgoingPath = root.shownPath
      root.shownPath = ""
      root.shownRevision = root.revision
      root.reveal = 0
      Qt.callLater(function () {
        root.shownPath = root.source
        fade.restart()
      })
      return
    }

    root.outgoingPath = root.shownPath
    root.shownPath = root.source
    root.shownRevision = root.revision
    root.reveal = 0
    fade.restart()
  }

  // Shown when there is no wallpaper yet, at login before the theme service has
  // written one. The palette rather than black, so the desktop never flashes.
  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: 0; color: Theme.bg }
      GradientStop { position: 1; color: Theme.surface }
    }
  }

  AnimatedImage {
    anchors.fill: parent
    source: root.url(root.outgoingPath)
    visible: root.outgoingPath !== ""
    fillMode: AnimatedImage.PreserveAspectCrop
    sourceSize.width: width
    sourceSize.height: height
    smooth: true
    cache: false
    asynchronous: true
  }

  AnimatedImage {
    anchors.fill: parent
    source: root.url(root.shownPath)
    visible: root.shownPath !== ""
    fillMode: AnimatedImage.PreserveAspectCrop
    sourceSize.width: width
    sourceSize.height: height
    smooth: true
    cache: false
    asynchronous: true
    opacity: root.reveal
  }

  SequentialAnimation {
    id: fade

    NumberAnimation {
      target: root
      property: "reveal"
      from: 0
      to: 1
      duration: Style.duration(420)
      easing.type: Easing.OutCubic
    }

    ScriptAction { script: root.outgoingPath = "" }
  }
}
