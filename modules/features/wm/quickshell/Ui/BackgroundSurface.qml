pragma ComponentBehavior: Bound
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

  // Generation/request tokens to prevent stale callbacks
  property int requestGeneration: 0
  property int activeGeneration: -1
  property int pendingGeneration: -1
  property bool transitionActive: false
  property bool pendingTransition: false
  property string pendingSource: ""
  property int pendingRevision: -1
  property bool destroyed: false

  function url(path) {
    if (path === "") return ""
    const p = String(path)
    if (p === "") return ""
    // If it's already a URL with scheme, preserve it
    if (p.indexOf(":/") !== -1 && p.indexOf("file://") === -1) {
      // Could be other schemes; try to resolve as-is if it looks like a URL
      // But better to be safe - only pass through if it has known schemes? Just return
      return p
    }
    if (p.indexOf("file://") === 0) {
      try {
        return Qt.resolvedUrl(p)
      } catch (e) {
        return p
      }
    }
    if (p.indexOf("/") === 0) {
      try {
        // Use Qt.resolvedUrl for proper encoding of special chars
        return Qt.resolvedUrl("file://" + p)
      } catch (e) {
        // Fallback
        return encodeURI("file://" + p).replace(/%5B/g, '[').replace(/%5D/g, ']')
      }
    }
    try {
      return Qt.resolvedUrl(p)
    } catch (e) {
      return p
    }
  }

  Component.onDestruction: {
    root.destroyed = true
    try { fade.stop() } catch (e) {}
  }

  // Both properties change together on a switch, so settle them for one
  // event-loop turn before deciding whether this is a new path or the same file
  // rewritten. Acting on each assignment separately animated twice.
  onSourceChanged: root.scheduleSync()
  onRevisionChanged: root.scheduleSync()

  function scheduleSync() {
    if (root.destroyed) return
    root.requestGeneration += 1
    if (root.syncQueued) {
      // A newer request is queued; let it process with latest values
      return
    }
    root.syncQueued = true
    Qt.callLater(root.sync)
  }

  function sync() {
    if (root.destroyed) {
      root.syncQueued = false
      return
    }
    root.syncQueued = false
    const gen = root.requestGeneration
    root.pendingGeneration = gen

    const pathChanged = root.source !== root.shownPath
    const revisionChanged = root.revision !== root.shownRevision
    if (!pathChanged && !revisionChanged) {
      root.pendingGeneration = -1
      return
    }

    // The first frame is not a transition; there is nothing to crossfade from.
    if (root.shownPath === "") {
      root.activeGeneration = gen
      root.pendingGeneration = -1
      root.transitionActive = false
      root.pendingTransition = false
      root.shownPath = root.source
      root.shownRevision = root.revision
      root.outgoingPath = ""
      root.reveal = 1
      // Ensure incoming layer is set up
      incomingImage.source = root.url(root.shownPath)
      return
    }

    // Same file, rewritten in place: keep it as the outgoing frame and reload
    // the incoming layer by emptying its source for a turn.
    if (!pathChanged) {
      // Cancel any previous pending transition state if superseded
      if (root.transitionActive || root.pendingTransition) {
        try { fade.stop() } catch (e) {}
      }
      root.activeGeneration = gen
      root.pendingGeneration = -1
      root.pendingSource = root.source
      root.pendingRevision = root.revision
      root.outgoingPath = root.shownPath
      root.shownPath = ""
      root.reveal = 0
      // Force reload by clearing and restoring
      incomingImage.source = ""
      Qt.callLater(function () {
        if (root.destroyed) return
        if (root.activeGeneration !== gen) return // stale
        root.shownPath = root.pendingSource
        root.shownRevision = root.pendingRevision
        incomingImage.source = root.url(root.shownPath)
        // Don't start fade until loaded; status handler will trigger
        root.pendingTransition = true
        root.transitionActive = false
      })
      return
    }

    // Different path
    if (root.transitionActive || root.pendingTransition) {
      try { fade.stop() } catch (e) {}
    }
    root.activeGeneration = gen
    root.pendingGeneration = -1
    root.pendingSource = root.source
    root.pendingRevision = root.revision
    root.outgoingPath = root.shownPath
    root.shownPath = ""
    root.reveal = 0
    incomingImage.source = ""
    Qt.callLater(function () {
      if (root.destroyed) return
      if (root.activeGeneration !== gen) return // stale request
      root.shownPath = root.pendingSource
      root.shownRevision = root.pendingRevision
      incomingImage.source = root.url(root.shownPath)
      root.pendingTransition = true
      root.transitionActive = false
    })
  }

  function startFadeIfReady(gen) {
    if (root.destroyed) return
    if (gen !== undefined && root.activeGeneration !== gen) return
    if (!root.pendingTransition) return
    // Check if incoming is ready
    if (incomingImage.status === Image.Ready) {
      root.pendingTransition = false
      root.transitionActive = true
      root.reveal = 0
      fade.restart()
    }
    // If error, keep outgoing, don't clear it - handle in error handler
  }

  // Shown when there is no wallpaper yet, at login before the theme service has
  // written one. The palette rather than black, so the desktop never flashes.
  Rectangle {
    id: gradientFallback
    anchors.fill: parent
    visible: (root.outgoingPath === "" && root.shownPath === "") || incomingImage.status === Image.Loading
    gradient: Gradient {
      GradientStop { position: 0; color: Theme.bg }
      GradientStop { position: 1; color: Theme.surface }
    }
    z: -1
  }

  AnimatedImage {
    id: outgoingImage
    anchors.fill: parent
    source: root.url(root.outgoingPath)
    visible: root.outgoingPath !== "" && incomingImage.status !== Image.Ready && root.transitionActive ? false : (root.outgoingPath !== "" && root.reveal < 1)
    fillMode: AnimatedImage.PreserveAspectCrop
    sourceSize.width: width
    sourceSize.height: height
    smooth: true
    cache: false
    asynchronous: true
  }

  AnimatedImage {
    id: incomingImage
    anchors.fill: parent
    source: ""
    visible: root.shownPath !== ""
    fillMode: AnimatedImage.PreserveAspectCrop
    sourceSize.width: width
    sourceSize.height: height
    smooth: true
    cache: false
    asynchronous: true
    opacity: root.reveal

    onStatusChanged: {
      if (root.destroyed) return
      if (root.pendingTransition && incomingImage.status === Image.Ready) {
        root.startFadeIfReady(root.activeGeneration)
      } else if (incomingImage.status === Image.Error) {
        // Keep last successfully displayed wallpaper - don't switch to broken image
        if (root.pendingTransition) {
          // Revert: keep outgoing as current shown, clear pending
          const gen = root.activeGeneration
          if (root.activeGeneration === gen) {
            root.shownPath = root.outgoingPath
            root.shownRevision = root.shownRevision // keep old revision? or don't change
            root.outgoingPath = ""
            root.reveal = 1
            root.pendingTransition = false
            root.transitionActive = false
            try { fade.stop() } catch (e) {}
            incomingImage.source = root.url(root.shownPath)
          }
        }
      }
    }
  }

  SequentialAnimation {
    id: fade

    NumberAnimation {
      target: root
      property: "reveal"
      from: 0
      to: 1
      duration: Style.duration ? Style.duration(420) : 420
      easing.type: Easing.OutCubic
    }

    ScriptAction { script: {
      if (root.destroyed) return
      if (!root.transitionActive) return
      root.outgoingPath = ""
      root.transitionActive = false
      root.pendingTransition = false
    } }
  }
}
