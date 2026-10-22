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

  function showOsd(icon, player) {
    if (!player) return
    OsdHost.show(icon, root.osdName(player), "", "100", "", 1600)
  }

  // The keys go through the shell instead of playerctl so the same action can
  // put its own readout on screen. Play/pause is immediate; next/previous wait
  // one short beat for the player to publish the new track.
  function playPause() {
    const player = root.active
    if (!player || !player.canTogglePlaying) return

    const icon = player.isPlaying ? "media-pause" : "media-play"
    player.togglePlaying()
    root.showOsd(icon, player)
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
}
