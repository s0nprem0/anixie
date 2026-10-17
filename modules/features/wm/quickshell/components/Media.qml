import QtQuick
import ".."
import "../Ui"
import Quickshell
import Quickshell.Services.Mpris

// MPRIS now-playing readout. Shows the track title (and artist when there is
// room), with play/pause, next and previous on the usual gestures. A popup
// carries the cover art and the full metadata.
BarWidget {
  id: root

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var player: {
    // Prefer a playing player over a paused one, so a paused tab does not
    // shadow the track that is actually sounding.
    for (let i = 0; i < root.players.length; i++) {
      if (root.players[i].playbackState === MprisPlaybackState.Playing) return root.players[i]
    }
    return root.players.length > 0 ? root.players[0] : null
  }

  readonly property bool hasPlayer: root.player !== null
  readonly property bool playing: root.player ? root.player.playbackState === MprisPlaybackState.Playing : false
  readonly property string title: root.player ? (root.player.trackTitle || "") : ""
  readonly property string artist: root.player ? (root.player.trackArtist || "") : ""
  readonly property string artUrl: root.player ? (root.player.trackArtUrl || "") : ""

  visible: root.hasPlayer && !root.vertical
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
    labelText: root.vertical ? "" : root.title
    tooltipText: root.title !== ""
      ? root.title + (root.artist !== "" ? " · " + root.artist : "")
      : "No track"

    onPressed: function (button) {
      if (button === Qt.LeftButton) root.toggle()
      else if (button === Qt.MiddleButton) root.next()
      else if (button === Qt.RightButton) PanelHost.toggle(readout, popup)
    }

    onWheelMoved: function (delta) {
      if (delta > 0) root.next()
      else root.previous()
    }
  }

  Component {
    id: popup

    Panel {
      title: "Now playing"
      maxWidth: Style.space(360)

      Row {
        spacing: Style.space(12)

        Image {
          width: Style.space(64)
          height: Style.space(64)
          source: root.artUrl
          fillMode: Image.PreserveAspectCrop
          visible: root.artUrl !== ""
        }

        Column {
          spacing: Style.space(4)

          Text {
            text: root.title !== "" ? root.title : "Unknown track"
            color: Theme.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.weight: Font.DemiBold
            width: Style.space(260)
            elide: Text.ElideRight
          }

          Text {
            text: root.artist !== "" ? root.artist : "Unknown artist"
            color: Theme.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            width: Style.space(260)
            elide: Text.ElideRight
          }

          Row {
            spacing: Style.space(8)

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
        }
      }
    }
  }
}
