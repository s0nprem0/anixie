pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// Which player the media widget is showing, and the keys that move between
// players.
//
// The choice lives here rather than in the widget because the hotkey reaches it
// from shell.qml, where no widget instance is in scope. It is null until one is
// picked, which is what lets the widget follow whichever player is actually
// making noise until the listener says otherwise.
QtObject {
  id: root

  property var chosen: null

  // Show an OSD when the active player changes track on its own. Off by
  // default: an automatic readout on every song change is not what everyone
  // wants on screen.
  property bool trackChangeOsd: false

  readonly property var players: Mpris.players ? Mpris.players.values : []

  // The player the widget is showing, and therefore the one the keys act on:
  // an explicit choice if it is still around, otherwise whichever is actually
  // playing, otherwise the first one.
  readonly property var active: {
    const chosen = root.chosen
    if (chosen && root.players.indexOf(chosen) !== -1) return chosen

    for (let i = 0; i < root.players.length; i++) {
      if (root.players[i].playbackState === MprisPlaybackState.Playing) return root.players[i]
    }

    return root.players.length > 0 ? root.players[0] : null
  }

  function choose(player) {
    root.chosen = player
  }

  function osdName(player) {
    if (!player) return ""
    const title = String(player.trackTitle || "")
    const artist = String(player.trackArtist || "")
    if (title !== "" && artist !== "") return artist + " — " + title
    if (title !== "") return title
    return String(player.identity || player.desktopEntry || "Media player")
  }

  function showOsd(icon, player, prefix) {
    if (!player) return
    const name = root.osdName(player)
    const message = prefix ? prefix + " · " + name : name
    // No explicit duration: a title is read, not glanced at, so the OSD sizes
    // its own time from the message.
    OsdHost.show(icon, message, "", "100", "")
  }

  // The keys go through the shell instead of playerctl so the same action can
  // put its own readout on screen. Play/pause is immediate; next/previous wait
  // one short beat for the player to publish the new track.
  function playPause() {
    const player = root.active
    if (!player || !player.canTogglePlaying) return

    const wasPlaying = player.isPlaying
    player.togglePlaying()
    // The glyph matches the new state, and the prefix says it in words: a
    // pause icon alone could be read as either "paused" or "press to pause".
    root.showOsd(wasPlaying ? "media-pause" : "media-play", player,
      wasPlaying ? "Paused" : "Playing")
  }

  property string pendingIcon: ""
  property var pendingPlayer: null

  function trackNext() {
    const player = root.active
    if (!player || !player.canGoNext) return

    player.next()
    root.pendingIcon = "media-next"
    root.pendingPlayer = player
    trackOsdTimer.restart()
  }

  function trackPrevious() {
    const player = root.active
    if (!player || !player.canGoPrevious) return

    player.previous()
    root.pendingIcon = "media-previous"
    root.pendingPlayer = player
    trackOsdTimer.restart()
  }

  function switchBy(delta) {
    if (root.players.length < 2) return

    const remembered = root.chosen && root.players.indexOf(root.chosen) !== -1 ? root.chosen : root.players[0]
    const index = root.players.indexOf(remembered)
    const from = index < 0 ? (delta > 0 ? -1 : 0) : index
    root.chosen = root.players[(from + delta + root.players.length) % root.players.length]
    root.showOsd("media", root.chosen)
  }

  // Move through the players in the order the widget lists them. Wraps, and
  // does nothing with fewer than two: switching to the only player is not a
  // switch. A remembered player that has since gone is treated as no choice.
  function next() {
    root.switchBy(1)
  }

  function previous() {
    root.switchBy(-1)
  }

  property Timer trackOsdTimer: Timer {
    interval: 350
    repeat: false
    onTriggered: root.showOsd(root.pendingIcon, root.pendingPlayer)
  }

  // Automatic now-playing readout. Only fires when opted in, and only when the
  // title actually changes, so a paused/playing toggle does not duplicate it.
  property string lastTrackTitle: ""

  property Connections trackChangeConnections: Connections {
    target: root.active

    function onTrackTitleChanged() {
      if (!root.trackChangeOsd) return
      const player = root.active
      if (!player) return
      const title = String(player.trackTitle || "")
      if (title === "" || title === root.lastTrackTitle) return
      root.lastTrackTitle = title
      root.showOsd("media", player)
    }
  }
}
