import QtQuick
import ".."
import "../Ui"
import Quickshell
import Quickshell.Services.Mpris

// MPRIS now-playing readout. Shows the track title and artist — scrolling when
// they do not fit — with play/pause, next and previous on the usual gestures. A
// popup carries the cover art, the full metadata, and a list of the other
// players to switch between.
//
// The label scrolls rather than eliding because a track name is the one label on
// this bar whose *end* matters as much as its start: "Symphony No. 9 in D minor,
// Op. 125 — IV. Presto" and "Symphony No. 9 in D minor, Op. 125 — II. Molto
// vivace" are the same string for the first forty characters.
BarWidget {
  id: root

  // Reachable by hotkey as well as by right-click, like the other panels.
  Component.onCompleted: PanelRegistry.register("media", readout, popup)

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
  readonly property string album: root.player ? (root.player.trackAlbum || "") : ""
  readonly property string artUrl: root.player ? (root.player.trackArtUrl || "") : ""

  readonly property int maxLabelWidth: Number(root.setting("maxWidth", 240))

  // A player is named by whatever it has to say for itself: a track, then the
  // player's own identity, then the desktop entry it came from. A browser tab
  // with no metadata at all still gets a row.
  function playerName(p) {
    if (!p) return "Media player"
    return p.trackTitle || p.identity || p.desktopEntry || "Media player"
  }

  function playerDetail(p) {
    if (!p) return ""
    return p.trackArtist || p.identity || ""
  }

  // Whether this widget's popup is the one on screen, so the label can hold
  // still while it is being read.
  readonly property bool popupOpen: PanelHost.isOpen("media")

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
      else if (button === Qt.RightButton) PanelRegistry.toggle("media")
    }

    onWheelMoved: function (delta) {
      if (delta > 0) root.next()
      else root.previous()
    }
  }

  Component {
    id: popup

    Panel {
      id: card

      PanelHero {
        width: card.contentWidth
        art: root.artUrl
        // The play state is the icon when there is no sleeve to show, so a
        // player that has no artwork still says whether it is making noise.
        glyph: root.artUrl === "" ? (root.playing ? Util.glyph("f04c") : Util.glyph("f04b")) : ""
        title: root.title !== "" ? root.title : "Now playing"
        subtitle: root.artist !== "" ? root.artist : (root.hasPlayer ? "Unknown artist" : "")
      }

      // Only when there is one: an "Unknown album" line under "Unknown
      // artist" is three lines of saying nothing, and an album line repeating the
      // title above it says the same thing twice.
      Text {
        width: card.contentWidth
        visible: root.album !== "" && root.album !== root.title
        height: implicitHeight
        text: root.album
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        renderType: Text.NativeRendering
      }

      Row {
        width: card.contentWidth
        spacing: Style.space(8)
        topPadding: Style.space(4)

        WidgetButton {
          text: Util.glyph("f048")
          fontSize: Style.bar.iconFont
          tooltipText: "Previous"
          onPressed: function () { root.previous() }
        }

        WidgetButton {
          text: root.playing ? Util.glyph("f04c") : Util.glyph("f04b")
          fontSize: Style.bar.iconFont
          tooltipText: root.playing ? "Pause" : "Play"
          onPressed: function () { root.toggle() }
        }

        WidgetButton {
          text: Util.glyph("f051")
          fontSize: Style.bar.iconFont
          tooltipText: "Next"
          onPressed: function () { root.next() }
        }
      }

      // ---- the other players ----
      //
      // Only when there is more than one. With a single player this is a list
      // naming the thing the panel is already titled after, and picking from a
      // list of one is not a choice.
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
            ? Util.glyph("f04c")
            : ""
          selected: root.player === playerRow.modelData
          onClicked: MediaHost.choose(playerRow.modelData)
        }
      }
    }
  }
}
