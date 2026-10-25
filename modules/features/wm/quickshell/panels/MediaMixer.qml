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
  readonly property bool hasPlayer: root.player !== null
  readonly property bool playing: root.player
    ? root.player.playbackState === MprisPlaybackState.Playing
    : false

  readonly property string title: root.player ? String(root.player.trackTitle || "") : ""
  readonly property string artist: root.player ? String(root.player.trackArtist || "") : ""
  readonly property string album: root.player ? String(root.player.trackAlbum || "") : ""
  readonly property string artUrl: root.player ? String(root.player.trackArtUrl || "") : ""
  readonly property string identity: root.player
    ? String(root.player.identity || root.player.desktopEntry || "")
    : ""

  readonly property bool hasSeek: root.hasPlayer
    && root.player.lengthSupported && root.player.positionSupported
    && root.length > 0
  readonly property real length: root.player && root.player.lengthSupported
    ? Number(root.player.length || 0)
    : 0

  // The player's position is corrected by MPRIS whenever it says something, and
  // advanced by a second while it is playing. A player that only publishes its
  // position on a seek otherwise leaves the bar sitting at the start of the
  // track for the whole song.
  property real shownPosition: 0
  readonly property real progress: root.length > 0
    ? Math.max(0, Math.min(1, root.shownPosition / root.length))
    : 0

  function syncPosition() {
    if (root.player && root.player.positionSupported) {
      root.shownPosition = Number(root.player.position || 0)
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.hasSeek && root.playing
    onTriggered: {
      if (!root.hasSeek) return
      root.shownPosition = Math.min(root.length, root.shownPosition + 1)
    }
  }

  Connections {
    target: root.player
    function onPositionChanged() { root.syncPosition() }
    function onLengthChanged() { root.syncPosition() }
    function onPlaybackStateChanged() { root.syncPosition() }
  }

  onPlayerChanged: root.syncPosition()
  onTitleChanged: root.shownPosition = 0

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
    if (!root.player || !root.hasSeek || !root.player.canSeek) return
    const ratio = Math.max(0, Math.min(1, x / Math.max(1, seekArea.width)))
    root.seekTo(ratio * root.length)
  }

  function seekTo(target) {
    if (!root.player || !root.hasSeek || !root.player.canSeek) return
    const position = Math.max(0, Math.min(root.length, Number(target) || 0))
    root.player.position = position
    root.shownPosition = position
  }

  function playerName(p) {
    if (!p) return "Media player"
    return p.trackTitle || p.identity || p.desktopEntry || "Media player"
  }

  function playerDetail(p) {
    if (!p) return ""
    return p.trackArtist || p.identity || ""
  }

  // ---- the mixer ----
  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var defaultSink: Pipewire.defaultAudioSink
  readonly property var defaultSource: Pipewire.defaultAudioSource

  readonly property var sinkAudio: root.defaultSink ? root.defaultSink.audio : null
  readonly property var sourceAudio: root.defaultSource ? root.defaultSource.audio : null

  readonly property int outputPercent: root.sinkAudio ? Math.round(root.sinkAudio.volume * 100) : 0
  readonly property bool outputMuted: root.sinkAudio ? root.sinkAudio.muted : true
  readonly property bool outputReady: root.sinkAudio !== null

  readonly property int inputPercent: root.sourceAudio ? Math.round(root.sourceAudio.volume * 100) : 0
  readonly property bool inputMuted: root.sourceAudio ? root.sourceAudio.muted : true

  // Sinks are what you can play *to*; streams are what is playing *now*.
  // `!isStream` matters: a playback stream reports `isSink` as well, so without
  // it every playing application would appear in the list of output devices.
  readonly property var sinks: {
    const out = []
    for (let i = 0; i < root.nodes.length; i++) {
      const node = root.nodes[i]
      if (node && node.isSink && !node.isStream && node.audio) out.push(node)
    }
    return out
  }

  readonly property var streams: {
    const out = []
    for (let i = 0; i < root.nodes.length; i++) {
      const node = root.nodes[i]
      if (node && node.isStream && node.audio) out.push(node)
    }
    return out
  }

  function displayName(node) {
    if (!node) return ""
    return String(node.description || node.name || "")
  }

  function level(node) {
    return node && node.audio ? node.audio.volume : 0
  }

  function percent(node) {
    return node && node.audio ? Math.round(node.audio.volume * 100) : 0
  }

  function setLevel(node, value) {
    if (node && node.audio) node.audio.volume = value
  }

  function setMuted(node, muted) {
    if (node && node.audio) node.audio.muted = muted
  }

  // Selecting an output is two things: tell WirePlumber what the default is, and
  // move what is already playing, which a new default does not do on its own.
  // The command carries both identifiers because the two layers name a sink
  // differently — node id for PipeWire, sink name for the PulseAudio
  // compatibility layer that does the moving.
  function setDefaultSink(node) {
    if (!node) return
    Pipewire.preferredDefaultAudioSink = node
    if (node.id !== undefined && node.name) {
      Quickshell.execDetached(["audio-output", "set", String(node.id), String(node.name)])
    }
  }

  // ---- devices and metadata ----
  property bool devicesExpanded: false
  property string serverName: ""
  property string rateText: ""

  readonly property string pipewireInfo: root.serverName !== ""
    ? "PipeWire: " + root.serverName + (root.rateText !== "" ? " | Rate: " + root.rateText : "")
    : "PipeWire"

  property Process info: Process {
    command: ["sh", "-c", "pactl info 2>/dev/null || true"]
    running: false

    stdout: StdioCollector {
      onStreamFinished: {
        const lines = String(this.text || "").split("\n")
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

        const version = server.match(/\(on (.+)\)/)
        root.serverName = version ? "on " + version[1] : server

        const rate = spec.match(/(\d+)\s*Hz/)
        root.rateText = rate ? Math.round(Number(rate[1]) / 1000) + " kHz" : ""
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
        ? (root.artist !== "" ? root.artist : "Unknown artist")
          + (root.identity !== "" ? " · " + root.identity : "")
        : (root.outputReady ? root.displayName(root.defaultSink) : "no output device")
    }

    Text {
      width: card.contentWidth
      height: implicitHeight
      visible: root.album !== "" && root.album !== root.title
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
      visible: root.hasSeek

      // The sideways keys scrub, the same gesture the sliders use. Return has
      // nothing of its own to do here.
      readonly property bool panelFocusable: root.hasSeek
        && root.player !== null && root.player.canSeek

      function activate() {
      }

      function keyStep(direction) {
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
        height: Style.space(12)

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
          enabled: root.player !== null && root.player.canSeek
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onPressed: function (mouse) { root.seekAt(mouse.x) }
          onPositionChanged: function (mouse) {
            if (pressed) root.seekAt(mouse.x)
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
        dimmed: !root.player || !root.player.canGoPrevious
        onPressed: function () {
          if (root.player && root.player.canGoPrevious) root.player.previous()
        }
      }

      WidgetButton {
        text: root.playing ? Util.mediaPause : Util.mediaPlay
        fontSize: Style.bar.iconFont
        tooltipText: root.playing ? "Pause" : "Play"
        dimmed: !root.player || !root.player.canTogglePlaying
        onPressed: function () {
          if (root.player && root.player.canTogglePlaying) root.player.togglePlaying()
        }
      }

      WidgetButton {
        text: Util.mediaNext
        fontSize: Style.bar.iconFont
        tooltipText: "Next"
        dimmed: !root.player || !root.player.canGoNext
        onPressed: function () {
          if (root.player && root.player.canGoNext) root.player.next()
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

      SliderField {
        width: parent.width
        from: 0
        to: 1
        stepSize: 0.02
        level: root.level(root.defaultSink)
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

      SliderField {
        width: parent.width
        from: 0
        to: 1
        stepSize: 0.02
        level: root.level(root.defaultSource)
        available: root.defaultSource !== null
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

      delegate: SliderField {
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

    PanelActionButton {
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
      for (let i = 0; i < root.sinks.length; i++) keep.push(root.sinks[i])
      for (let i = 0; i < root.streams.length; i++) keep.push(root.streams[i])
      if (root.defaultSource) keep.push(root.defaultSource)
      return keep
    }
  }
}
