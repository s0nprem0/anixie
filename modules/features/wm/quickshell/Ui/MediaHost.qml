pragma Singleton

pragma ComponentBehavior: Bound
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

  readonly property var players: Mpris.players ? (Mpris.players.values || []) : []

  // Per-player track identity for automatic OSD
  property var trackIdByPlayer: ({})
  property var trackKeyByPlayer: ({})

  function playerKey(player) {
    if (!player) return ""
    try {
      if (player.dbusName) return String(player.dbusName)
      if (player.identity) return String(player.identity)
      if (player.desktopEntry) return String(player.desktopEntry)
    } catch (e) {}
    // Fallback to object identity not directly possible in JS; use string coercion
    try {
      return String(player)
    } catch (e) {
      return ""
    }
  }

  function normalizeText(v) {
    if (v === undefined || v === null) return ""
    const s = String(v)
    const trimmed = s.trim()
    if (trimmed === "") return ""
    return trimmed
  }

  function trackKeyForPlayer(player) {
    if (!player) return ""
    const title = root.normalizeText(player.trackTitle)
    const artist = root.normalizeText(player.trackArtist)
    if (title === "" && artist === "") return ""
    return artist + "||" + title
  }

  // Clean up records for removed players
  function pruneTrackRecords() {
    const players = root.players
    const nextByPlayer = {}
    const nextKeyByPlayer = {}
    for (let i = 0; i < players.length; i++) {
      const p = players[i]
      const k = root.playerKey(p)
      if (k === "") continue
      if (root.trackIdByPlayer.hasOwnProperty(k)) {
        nextByPlayer[k] = root.trackIdByPlayer[k]
      }
      if (root.trackKeyByPlayer.hasOwnProperty(k)) {
        nextKeyByPlayer[k] = root.trackKeyByPlayer[k]
      }
    }
    root.trackIdByPlayer = nextByPlayer
    root.trackKeyByPlayer = nextKeyByPlayer
    // Clear chosen if it disappeared
    if (root.chosen && root.players.indexOf(root.chosen) === -1) {
      root.chosen = null
    }
  }

  onPlayersChanged: root.pruneTrackRecords()

  // The player the widget is showing, and therefore the one the keys act on:
  // an explicit choice if it is still around, otherwise whichever is actually
  // playing, otherwise the first one.
  readonly property var active: {
    const chosen = root.chosen
    if (chosen && root.players.indexOf(chosen) !== -1) return chosen

    for (let i = 0; i < root.players.length; i++) {
      try {
        if (root.players[i].playbackState === MprisPlaybackState.Playing || root.players[i].isPlaying) return root.players[i]
      } catch (e) {}
    }

    return root.players.length > 0 ? root.players[0] : null
  }

  onActiveChanged: {
    root.pruneTrackRecords()
    // Initialize track key for new active player to avoid immediate duplicate OSD
    const p = root.active
    if (p && root.trackChangeOsd) {
      const k = root.playerKey(p)
      const key = root.trackKeyForPlayer(p)
      if (k !== "") {
        root.trackKeyByPlayer[k] = key
      }
    }
  }

  function choose(player) {
    root.chosen = player
  }

  function osdName(player) {
    if (!player) return ""
    const title = root.normalizeText(player.trackTitle)
    const artist = root.normalizeText(player.trackArtist)
    const album = root.normalizeText(player.trackAlbum)
    if (title !== "" && artist !== "" && album !== "") return artist + " — " + title + " (" + album + ")"
    if (title !== "" && artist !== "") return artist + " — " + title
    if (title !== "" && album !== "") return title + " (" + album + ")"
    if (title !== "") return title
    const identity = root.normalizeText(player.identity)
    if (identity !== "") return identity
    const desktop = root.normalizeText(player.desktopEntry)
    if (desktop !== "") return desktop
    return "Media player"
  }

  function showOsd(icon, player, prefix) {
    if (!player) return
    const name = root.osdName(player)
    if (name === "") return
    const message = prefix ? prefix + " · " + name : name
    // No explicit duration: a title is read, not glanced at, so the OSD sizes
    // its own time from the message.
    try {
      OsdHost.show(icon, message, "", "100", "")
    } catch (e) {}
  }

  // The keys go through the shell instead of playerctl so the same action can
  // put its own readout on screen. Play/pause is immediate; next/previous wait
  // one short beat for the player to publish the new track.
  function playPause() {
    const player = root.active
    if (!player) return
    try {
      if (player.canTogglePlaying === false) return
    } catch (e) {}
    try {
      const wasPlaying = !!player.isPlaying
      player.togglePlaying()
      // The glyph matches the new state, and the prefix says it in words
      root.showOsd(wasPlaying ? "media-pause" : "media-play", player,
        wasPlaying ? "Paused" : "Playing")
    } catch (e) {}
  }

  property string pendingIcon: ""
  property var pendingPlayer: null
  property int pendingToken: 0

  function trackNext() {
    const player = root.active
    if (!player) return
    try {
      if (player.canGoNext === false) return
    } catch (e) {}
    try {
      player.next()
      root.pendingIcon = "media-next"
      root.pendingPlayer = player
      root.pendingToken += 1
      trackOsdTimer.restart()
    } catch (e) {}
  }

  function trackPrevious() {
    const player = root.active
    if (!player) return
    try {
      if (player.canGoPrevious === false) return
    } catch (e) {}
    try {
      player.previous()
      root.pendingIcon = "media-previous"
      root.pendingPlayer = player
      root.pendingToken += 1
      trackOsdTimer.restart()
    } catch (e) {}
  }

  function switchBy(delta) {
    if (root.players.length < 2) return

    // Start from root.active, not blindly from players[0]
    let current = root.chosen && root.players.indexOf(root.chosen) !== -1 ? root.chosen : root.active
    if (!current || root.players.indexOf(current) === -1) {
      current = root.players[0]
    }
    const index = root.players.indexOf(current)
    const from = index < 0 ? (delta > 0 ? -1 : 0) : index
    const nextPlayer = root.players[(from + delta + root.players.length) % root.players.length]
    root.chosen = nextPlayer
    root.showOsd("media", root.chosen)
  }

  // Move through the players in the order the widget lists them. Wraps, and
  // does nothing with fewer than two.
  function next() {
    root.switchBy(1)
  }

  function previous() {
    root.switchBy(-1)
  }

  property Timer trackOsdTimer: Timer {
    interval: 350
    repeat: false
    onTriggered: {
      // Make callback safe if player disappeared
      const p = root.pendingPlayer
      if (!p) return
      if (root.players.indexOf(p) === -1) {
        root.pendingPlayer = null
        return
      }
      root.showOsd(root.pendingIcon, p)
    }
  }

  // Automatic now-playing readout. Only fires when opted in, and only when the
  // title/artist actually changes, so a paused/playing toggle does not duplicate it.
  property string lastTrackTitle: "" // kept for compatibility if referenced

  property Timer trackDebounce: Timer {
    interval: 150
    repeat: false
    onTriggered: root._applyTrackChange()
  }

  property Connections trackChangeConnections: Connections {
    target: root.trackChangeOsd ? root.active : null
    enabled: root.trackChangeOsd

    function onTrackTitleChanged() {
      root.handleTrackChange()
    }

    function onTrackArtistChanged() {
      root.handleTrackChange()
    }

    function onTrackAlbumChanged() {
      root.handleTrackChange()
    }

    function onPlaybackStateChanged() {
      // Don't trigger automatic OSD on state changes alone
    }
  }

  onTrackChangeOsdChanged: {
    if (root.trackChangeOsd && root.active) {
      const k = root.playerKey(root.active)
      const key = root.trackKeyForPlayer(root.active)
      if (k !== "") root.trackKeyByPlayer[k] = key
    }
  }

  function handleTrackChange() {
    if (!root.trackChangeOsd) return
    root.trackDebounce.restart()
  }

  function _applyTrackChange() {
    if (!root.trackChangeOsd) return
    const player = root.active
    if (!player) return
    const k = root.playerKey(player)
    const key = root.trackKeyForPlayer(player)
    if (key === "") return
    if (k !== "" && root.trackKeyByPlayer.hasOwnProperty(k) && root.trackKeyByPlayer[k] === key) {
      return
    }
    if (k !== "") {
      root.trackKeyByPlayer[k] = key
    }
    root.showOsd("media", player)
  }
}
