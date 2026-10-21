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

  function choose(player) {
    root.chosen = player
  }

  // Move through the players in the order the widget lists them. Wraps, and
  // does nothing with fewer than two: switching to the only player is not a
  // switch. A remembered player that has since gone is treated as no choice.
  function switchBy(delta) {
    if (root.players.length < 2) return

    const remembered = root.chosen && root.players.indexOf(root.chosen) !== -1 ? root.chosen : root.players[0]
    const index = root.players.indexOf(remembered)
    const from = index < 0 ? (delta > 0 ? -1 : 0) : index
    root.chosen = root.players[(from + delta + root.players.length) % root.players.length]
  }

  function next() {
    root.switchBy(1)
  }

  function previous() {
    root.switchBy(-1)
  }
}
