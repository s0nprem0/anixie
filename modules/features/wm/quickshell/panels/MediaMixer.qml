pragma ComponentBehavior: Bound
import QtQuick
import ".."
import "../Ui"
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire

// Now playing and the mixer in one panel.
//
// The reference puts the track, its transport, the output and input levels, the
// per-application mixer, the devices and the PipeWire version in one column. The
// shell used to split that ground between two panels; this is the merge, so the
// volume key and the media widget open the same surface and a track and the
// level it is playing at are never a panel apart.
//
// It reads the player from MediaHost and the mixer straight from PipeWire, which
// is what lets the volume widget open it with no media player in sight. The
// audio half is the old Audio panel; the tracker at the bottom is still why a
// slider can write back to a node at all.
Item {
  id: root

  // ---- the player ----
  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var player: MediaHost.active
  readonly property bool hasPlayer: root.player !== null && root.player !== undefined
  readonly property bool playing: root.hasPlayer
    ? root.player.playbackState === MprisPlaybackState.Playing
    : false

  readonly property string title: root.hasPlayer ? String(root.player.trackTitle || "") : ""
  readonly property string artist: root.hasPlayer ? String(root.player.trackArtist || "") : ""
  readonly property string album: root.hasPlayer ? String(root.player.trackAlbum || "") : ""
  readonly property string artUrl: root.hasPlayer ? String(root.player.trackArtUrl || "") : ""
  readonly property string identity: root.hasPlayer
    ? String(root.player.identity || root.player.desktopEntry || root.player.busName || "")
    : ""
  readonly property string appId: root.hasPlayer
    ? String(root.player.desktopEntry || root.player.identity || "")
    : ""

  readonly property bool positionSupported: root.hasPlayer && root.player.positionSupported
  readonly property bool lengthSupported: root.hasPlayer && root.player.lengthSupported
  readonly property bool canSeekPlayer: root.hasPlayer && !!root.player.canSeek
  readonly property real length: (root.lengthSupported)
    ? Math.max(0, Number(root.player.length || 0))
    : 0
  readonly property bool hasSeek: root.hasPlayer && root.lengthSupported && root.positionSupported && root.canSeekPlayer && root.length > 0

  property real shownPosition: 0
  property real lastSyncTime: 0
  readonly property real progress: root.length > 0
    ? Math.max(0, Math.min(1, root.shownPosition / root.length))
    : 0

  function syncPosition() {
    if (!root.hasPlayer) {
      root.shownPosition = 0
      return
    }
    if (root.positionSupported) {
      const p = Number(root.player.position || 0)
      if (isFinite(p)) {
        root.shownPosition = Math.max(0, Math.min(root.length > 0 ? root.length : p, p))
      }
    }
    root.lastSyncTime = Date.now()
  }

  Timer {
    interval: 500
    repeat: true
    running: root.hasSeek && root.playing && (PanelHost.isOpen("media", Screens.nameOf(root)) || PanelHost.isOpen("audio", Screens.nameOf(root)))
    onTriggered: {
      if (!root.hasSeek || !root.playing) return
      const now = Date.now()
      const elapsed = Math.max(0, (now - root.lastSyncTime) / 1000.0)
      if (elapsed > 2.0) {
        root.syncPosition()
        return
      }
      root.shownPosition = Math.min(root.length, root.shownPosition + elapsed)
      root.lastSyncTime = now
    }
  }

  Connections {
    target: root.player
    ignoreUnknownSignals: true
    function onPositionChanged() { root.syncPosition() }
    function onLengthChanged() { root.syncPosition() }
    function onPlaybackStateChanged() { root.syncPosition() }
  }

  onPlayerChanged: {
    root.shownPosition = 0
    root.lastSyncTime = Date.now()
    root.syncPosition()
  }
  onTitleChanged: { root.syncPosition() }
  onArtistChanged: { root.syncPosition() }
  onAlbumChanged: { root.syncPosition() }
  onLengthChanged: { if (root.shownPosition > root.length && root.length >= 0) root.shownPosition = Math.max(0, root.length) }

  function formatTime(value) {
    const total = Math.max(0, Math.floor(Number(value) || 0))
    const hours = Math.floor(total / 3600)
    const minutes = Math.floor((total % 3600) / 60)
    const seconds = total % 60
    const pad = function (n) { return n < 10 ? "0" + n : String(n) }
    return hours > 0
      ? hours + ":" + pad(minutes) + ":" + pad(seconds)
      : minutes + ":" + pad(seconds)
  }

  function seekAt(x) {
    if (!root.hasSeek) return
    const w = Math.max(1, seekArea.width)
    const ratio = Math.max(0, Math.min(1, Number(x) / w))
    root.seekTo(ratio * root.length)
  }

  function seekTo(target) {
    if (!root.hasSeek || !root.player) return
    const t = Number(target)
    if (!isFinite(t)) return
    const position = Math.max(0, Math.min(root.length, t))
    try {
      root.player.position = position
    } catch (e) {}
    root.shownPosition = position
    root.lastSyncTime = Date.now()
  }

  function playerName(p) {
    if (!p) return "Media player"
    const identity = String(p.identity || p.desktopEntry || p.busName || "")
    if (identity !== "") return identity
    const title = String(p.trackTitle || "")
    if (title !== "") return title
    return "Media player"
  }

  function playerDetail(p) {
    if (!p) return ""
    const title = String(p.trackTitle || "")
    const artist = String(p.trackArtist || "")
    const identity = String(p.identity || p.desktopEntry || "")
    if (title !== "" && artist !== "") {
      if (root.player === p && title === root.title && artist === root.artist) return artist + " — " + title
      return artist + " — " + title
    }
    if (artist !== "") return artist
    if (title !== "" && root.player !== p) return title
    if (identity !== "") return identity
    return ""
  }

  // ---- the mixer ----
  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var defaultSink: Pipewire.defaultAudioSink
  readonly property var defaultSource: Pipewire.defaultAudioSource

  readonly property var sinkAudio: root.defaultSink && root.defaultSink.audio ? root.defaultSink.audio : null
  readonly property var sourceAudio: root.defaultSource && root.defaultSource.audio ? root.defaultSource.audio : null

  readonly property bool outputReady: root.sinkAudio !== null
  readonly property real outputLevel: root.outputReady && isFinite(Number(root.sinkAudio.volume)) ? Math.max(0, Math.min(1.0, Number(root.sinkAudio.volume))) : 0
  readonly property int outputPercent: root.outputReady ? Math.round(root.outputLevel * 100) : 0
  readonly property bool outputMuted: root.outputReady ? !!root.sinkAudio.muted : true
  readonly property bool inputReady: root.sourceAudio !== null
  readonly property real inputLevel: root.inputReady && isFinite(Number(root.sourceAudio.volume)) ? Math.max(0, Math.min(1.0, Number(root.sourceAudio.volume))) : 0
  readonly property int inputPercent: root.inputReady ? Math.round(root.inputLevel * 100) : 0
  readonly property bool inputMuted: root.inputReady ? !!root.sourceAudio.muted : true

  readonly property var sinks: {
    const out = []
    const list = root.nodes || []
    for (let i = 0; i < list.length; i++) {
      const node = list[i]
      if (!node) continue
      if (node.isSink && !node.isStream && node.audio) out.push(node)
    }
    return out
  }

  readonly property var streams: {
    const out = []
    const list = root.nodes || []
    for (let i = 0; i < list.length; i++) {
      const node = list[i]
      if (!node) continue
      if (node.isStream && node.audio) out.push(node)
    }
    return out
  }

  function displayName(node) {
    if (!node) return ""
    const desc = node.description !== undefined && node.description !== null ? String(node.description) : ""
    const name = node.name !== undefined && node.name !== null ? String(node.name) : ""
    return desc !== "" ? desc : name
  }

  function level(node) {
    if (!node || !node.audio) return 0
    const v = Number(node.audio.volume)
    if (!isFinite(v)) return 0
    return Math.max(0, Math.min(1.0, v))
  }

  function percent(node) {
    return Math.round(root.level(node) * 100)
  }

  function setLevel(node, value) {
    if (!node || !node.audio) return
    const v = Number(value)
    if (!isFinite(v)) return
    node.audio.volume = Math.max(0, Math.min(1.0, v))
  }

  function setMuted(node, muted) {
    if (!node || !node.audio) return
    node.audio.muted = !!muted
  }

  function setDefaultSink(node) {
    if (!node) return
    try {
      Pipewire.preferredDefaultAudioSink = node
    } catch (e) {}
    try {
      if (node.id !== undefined && node.name !== undefined && node.name !== null) {
        // Route through alexie when available (daemon), falling back to the
        // audio-output script. Commands.runAlexie handles the fallback.
        Commands.runAlexie("audio set " + JSON.stringify(String(node.id)) + " " + JSON.stringify(String(node.name)))
      }
    } catch (e) {}
  }

  // ---- devices and metadata ----
  property bool devicesExpanded: false
  property string serverName: ""
  property string rateText: ""

  readonly property string pipewireInfo: root.serverName !== ""
    ? "PipeWire: " + root.serverName + (root.rateText !== "" ? " | Rate: " + root.rateText : "")
    : "PipeWire"

  property Process info: Process {
    command: ["sh", "-c", "if command -v pactl >/dev/null 2>&1; then pactl info 2>/dev/null || true; fi"]
    running: false

    stdout: StdioCollector {
      onStreamFinished: {
        const text = String(this.text || "")
        if (text === "") return
        const lines = text.split("\n")
        let server = ""
        let spec = ""

        for (let i = 0; i < lines.length; i++) {
          const line = lines[i]
          const colon = line.indexOf(":")
          if (colon < 0) continue
          const key = line.slice(0, colon)
          const value = line.slice(colon + 1).trim()
          if (key === "Server Name") server = value
          else if (key === "Default Sample Specification") spec = value
        }

        if (server !== "") {
          const version = server.match(/\(on (.+)\)/)
          root.serverName = version ? "on " + version[1] : server
        }

        if (spec !== "") {
          const rate = spec.match(/(\d+)\s*Hz/)
          if (rate) {
            const r = Number(rate[1])
            if (isFinite(r)) root.rateText = Math.round(r / 1000) + " kHz"
          }
        }
      }
    }
  }

  Component.onCompleted: {
    root.info.running = true
    root.syncPosition()
  }

  implicitWidth: Style.space(340)
  implicitHeight: card.implicitHeight

  Panel {
    id: card
    anchors.fill: parent

    // ---- now playing ----
    PanelHero {
      width: card.contentWidth
      art: root.artUrl
      glyph: root.artUrl === "" ? (root.hasPlayer
        ? (root.playing ? Util.mediaPause : Util.mediaPlay)
        : Util.volumeHigh) : ""
      title: root.title !== "" ? root.title : (root.hasPlayer ? "Now playing" : "Audio")
      subtitle: root.hasPlayer
        ? (root.artist !== "" && root.album !== ""
            ? root.artist + " · " + root.album
            : (root.artist !== ""
                ? root.artist
                : (root.identity !== "" ? root.identity : "Unknown artist")))
        : (root.outputReady ? root.displayName(root.defaultSink) : "no output device")
    }

    Text {
      width: card.contentWidth
      height: implicitHeight
      visible: root.album !== "" && root.album !== root.title && root.artist === ""
      text: root.album
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      renderType: Text.NativeRendering
    }

    // ---- progress ----
    //
    // The times sit at the ends of the track, the way the reference draws them,
    // and the bar between them is the target: a player is scrubbed far more
    // often than it is pressed one second at a time.
    Item {
      id: progressRow

      width: card.contentWidth
      height: Style.space(18)
      visible: root.hasPlayer && root.lengthSupported && root.positionSupported && root.length > 0

      readonly property bool panelFocusable: root.hasSeek

      function activate() {
      }

      function keyStep(direction) {
        if (!root.hasSeek) return false
        root.seekTo(root.shownPosition + direction * 5)
        return true
      }

      Text {
        id: elapsed

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.formatTime(root.shownPosition)
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }

      Text {
        id: total

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.formatTime(root.length)
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }

      Item {
        id: seekArea

        anchors.left: elapsed.right
        anchors.right: total.left
        anchors.leftMargin: Style.space(8)
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        height: Style.space(16)

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          height: Style.space(3)
          radius: Theme.cornerRadius
          color: Theme.border
        }

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width * root.progress
          height: Style.space(3)
          radius: Theme.cornerRadius
          color: Theme.accent
        }

        MouseArea {
          anchors.fill: parent
          enabled: root.hasSeek
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onPressed: function (mouse) { if (root.hasSeek) root.seekAt(mouse.x) }
          onPositionChanged: function (mouse) {
            if (pressed && root.hasSeek) root.seekAt(mouse.x)
          }
        }
      }
    }

    // ---- transport ----
    Row {
      width: card.contentWidth
      spacing: Style.space(8)
      topPadding: Style.space(4)
      visible: root.hasPlayer

      WidgetButton {
        text: Util.mediaPrevious
        fontSize: Style.bar.iconFont
        tooltipText: "Previous"
        dimmed: !(root.player && root.player.canGoPrevious)
        enabled: !!(root.player && root.player.canGoPrevious)
        onPressed: function () {
          if (root.player && root.player.canGoPrevious) {
            try { root.player.previous() } catch (e) {}
          }
        }
      }

      WidgetButton {
        text: root.playing ? Util.mediaPause : Util.mediaPlay
        fontSize: Style.bar.iconFont
        tooltipText: root.playing ? "Pause" : "Play"
        dimmed: !(root.player && root.player.canTogglePlaying)
        enabled: !!(root.player && root.player.canTogglePlaying)
        onPressed: function () {
          if (root.player && root.player.canTogglePlaying) {
            try { root.player.togglePlaying() } catch (e) {}
          }
        }
      }

      WidgetButton {
        text: Util.mediaNext
        fontSize: Style.bar.iconFont
        tooltipText: "Next"
        dimmed: !(root.player && root.player.canGoNext)
        enabled: !!(root.player && root.player.canGoNext)
        onPressed: function () {
          if (root.player && root.player.canGoNext) {
            try { root.player.next() } catch (e) {}
          }
        }
      }
    }

    // ---- the other players ----
    //
    // Only when there is more than one, and only after the track: the list is
    // about the thing above it, not a second section of its own.
    PanelSeparator {
      visible: root.players.length > 1
    }

    PanelSectionHeader {
      width: card.contentWidth
      visible: root.players.length > 1
      label: "Players"
    }

    Repeater {
      model: root.players.length > 1 ? root.players : []

      delegate: ChoiceRow {
        id: playerRow
        required property var modelData

        width: card.contentWidth
        label: root.playerName(playerRow.modelData)
        detail: root.playerDetail(playerRow.modelData)
        glyph: playerRow.modelData.playbackState === MprisPlaybackState.Playing
          ? Util.mediaPause
          : ""
        selected: root.player === playerRow.modelData
        onClicked: MediaHost.choose(playerRow.modelData)
      }
    }

    PanelSeparator {}

    // ---- output ----
    //
    // The level is one line and one bar: the reference's "Output: 40%   Mute".
    // The mute action is a real button rather than a word in the row so the
    // keyboard can reach it the same way it reaches the slider.
    Column {
      width: card.contentWidth
      spacing: Style.space(2)

      PanelRow {
        width: parent.width
        label: "Output"
        value: !root.outputReady ? "—" : (root.outputMuted ? "muted" : root.outputPercent + "%")
        hasControl: true
        controlWidth: outputMute.implicitWidth

        TextButton {
          id: outputMute

          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          visible: root.outputReady
          label: root.outputMuted ? "Unmute" : "Mute"
          active: root.outputMuted
          onClicked: root.setMuted(root.defaultSink, !root.outputMuted)
        }
      }

      PanelSlider {
        width: parent.width
        from: 0
        to: 1
        stepSize: 0.02
        level: root.outputReady ? root.outputLevel : 0
        available: root.outputReady
        onMoved: function (value) { root.setLevel(root.defaultSink, value) }
      }
    }

    // ---- input ----
    Column {
      width: card.contentWidth
      spacing: Style.space(2)

      PanelRow {
        width: parent.width
        label: "Input"
        value: root.defaultSource === null
          ? "none"
          : (root.inputMuted ? "muted" : root.inputPercent + "%")
        hasControl: true
        controlWidth: inputMute.implicitWidth

        TextButton {
          id: inputMute

          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          visible: root.defaultSource !== null
          label: root.inputMuted ? "Unmute" : "Mute"
          active: root.inputMuted
          onClicked: root.setMuted(root.defaultSource, !root.inputMuted)
        }
      }

      PanelSlider {
        width: parent.width
        from: 0
        to: 1
        stepSize: 0.02
        level: root.inputReady ? root.inputLevel : 0
        available: root.inputReady
        onMoved: function (value) { root.setLevel(root.defaultSource, value) }
      }
    }

    // ---- per-application ----
    //
    // A mixer row is the one place a second line earns its keep: the name is
    // what tells you which of six identical sliders you are looking at.
    PanelSeparator {
      visible: root.streams.length > 0
    }

    PanelSectionHeader {
      width: card.contentWidth
      visible: root.streams.length > 0
      label: "Applications"
    }

    Repeater {
      model: root.streams

      delegate: PanelSlider {
        id: streamField
        required property var modelData

        width: card.contentWidth
        label: root.displayName(streamField.modelData)
        value: root.percent(streamField.modelData) + "%"
        from: 0
        to: 1
        stepSize: 0.02
        level: root.level(streamField.modelData)
        onMoved: function (value) { root.setLevel(streamField.modelData, value) }
      }
    }

    // ---- devices ----
    PanelSeparator {}

    Button {
      width: card.contentWidth
      label: "Devices"
      value: root.devicesExpanded ? "hide" : "show"
      navigational: false
      onClicked: root.devicesExpanded = !root.devicesExpanded
    }

    Column {
      width: card.contentWidth
      spacing: Style.space(2)
      visible: root.devicesExpanded

      PanelSectionHeader {
        width: parent.width
        visible: root.sinks.length > 0
        label: "Outputs"
      }

      Repeater {
        model: root.sinks

        delegate: ChoiceRow {
          id: sinkRow
          required property var modelData

          width: card.contentWidth
          label: root.displayName(sinkRow.modelData)
          selected: root.defaultSink === sinkRow.modelData
          onClicked: root.setDefaultSink(sinkRow.modelData)
        }
      }

      PanelRow {
        width: parent.width
        visible: root.defaultSource !== null
        label: "Input"
        value: root.displayName(root.defaultSource)
      }
    }

    // The version and the devices stay visible without opening Devices: they are
    // what you look at when something is wrong, and making that a second click
    // would hide the answer behind the question.
    Column {
      width: card.contentWidth
      spacing: Style.space(2)

      Text {
        width: parent.width
        text: root.pipewireInfo
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        renderType: Text.NativeRendering
      }

      Text {
        width: parent.width
        visible: root.outputReady
        text: "Output: " + root.displayName(root.defaultSink)
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        renderType: Text.NativeRendering
      }

      Text {
        width: parent.width
        visible: root.defaultSource !== null
        text: "Input: " + root.displayName(root.defaultSource)
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        renderType: Text.NativeRendering
      }
    }
  }

  // Keep the nodes alive: without tracking, their volumes cannot be written.
  PwObjectTracker {
    objects: {
      const keep = []
      const seen = {}
      function add(n) {
        if (!n) return
        const id = n.id !== undefined ? String(n.id) : (n.name !== undefined ? String(n.name) : "")
        if (id === "") return
        if (seen[id]) return
        seen[id] = true
        keep.push(n)
      }
      if (root.defaultSink) add(root.defaultSink)
      const sinks = root.sinks || []
      for (let i = 0; i < sinks.length; i++) add(sinks[i])
      const streams = root.streams || []
      for (let i = 0; i < streams.length; i++) add(streams[i])
      if (root.defaultSource) add(root.defaultSource)
      return keep
    }
  }
}
