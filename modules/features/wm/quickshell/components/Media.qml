import QtQuick
import "../Ui"
import "../panels"
import Quickshell.Services.Mpris

// MPRIS now-playing readout. Shows the track title and artist — scrolling when
// they do not fit — with play/pause, next and previous on the usual gestures. A
// popup carries the cover art, the transport, the seek bar, the mixer and the
// other players; see panels/MediaMixer.qml.
//
// The label scrolls rather than eliding because a track name is the one label on
// this bar whose *end* matters as much as its start: "Symphony No. 9 in D minor,
// Op. 125 — IV. Presto" and "Symphony No. 9 in D minor, Op. 125 — II. Molto
// vivace" are the same string for the first forty characters.
BarWidget {
  id: root

  // Reachable by hotkey as well as by right-click, like the other panels.
  Component.onCompleted: root.registerPanel("media", readout, popup)

  readonly property var players: Mpris.players ? Mpris.players.values : []

  // Which player the widget is showing. Explicit once one is picked from the
  // popup's list — or moved to by the source-switch keys — and until then
  // whichever is actually making noise, so a paused tab does not shadow the
  // track that is sounding. The choice itself lives in MediaHost, because the
  // hotkey has to reach it without a widget instance.
  readonly property var player: {
    const chosen = MediaHost.chosen
    if (chosen && root.players.indexOf(chosen) !== -1) return chosen

    for (let i = 0; i < root.players.length; i++) {
      if (root.players[i].playbackState === MprisPlaybackState.Playing) return root.players[i]
    }
    return root.players.length > 0 ? root.players[0] : null
  }

  readonly property bool hasPlayer: root.player !== null
  readonly property bool playing: root.player ? root.player.playbackState === MprisPlaybackState.Playing : false

  readonly property string title: root.player ? (root.player.trackTitle || "") : ""
  readonly property string artist: root.player ? (root.player.trackArtist || "") : ""
  readonly property int maxLabelWidth: Number(root.setting("maxWidth", 240))

  // Whether this widget's popup is the one on screen, so the label can hold
  // still while it is being read.
  readonly property bool popupOpen: PanelHost.isOpen("media", Screens.nameOf(root))
    || PanelHost.isOpen("audio", Screens.nameOf(root))

  wantsSlot: root.hasPlayer && !root.vertical
  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  function toggle() {
    if (root.player && root.player.canTogglePlaying) root.player.togglePlaying()
  }

  function next() {
    if (root.player && root.player.canGoNext) root.player.next()
  }

  function previous() {
    if (root.player && root.player.canGoPrevious) root.player.previous()
  }

  BarIconButton {
    id: readout
    contextMenu: [
      { label: "Play or pause", glyph: Util.mediaPlay, action: function () { root.toggle() } },
      { label: "Next track", glyph: Util.mediaNext, action: function () { root.next() } },
      { label: "Previous track", glyph: Util.mediaPrevious, action: function () { root.previous() } },
      { separator: true },
      { label: "Media & audio panel", glyph: Util.media, action: function () { PanelRegistry.toggle("media", readout) } }
    ]
    anchors.centerIn: parent
    text: root.playing ? Util.glyph("f04c") : Util.glyph("f04b")

    // The artist rides along with the title. There is room for it while the
    // label is moving anyway, and a bar showing only the track name cannot tell
    // two versions of the same song apart.
    labelText: root.title !== "" && root.artist !== ""
      ? root.title + "  ·  " + root.artist
      : root.title
    labelMaxWidth: root.maxLabelWidth
    marquee: true
    marqueePaused: root.popupOpen

    tooltipText: root.title !== ""
      ? root.title + (root.artist !== "" ? " · " + root.artist : "")
      : "No track"

    onPressed: function (button) {
      if (button === Qt.LeftButton) root.toggle()
      else if (button === Qt.MiddleButton) root.next()
      else if (button === Qt.RightButton) PanelRegistry.toggle("media", readout)
    }

    onWheelMoved: function (delta) {
      if (delta > 0) root.next()
      else root.previous()
    }
  }

  Component {
    id: popup

    MediaMixer {}
  }
}
