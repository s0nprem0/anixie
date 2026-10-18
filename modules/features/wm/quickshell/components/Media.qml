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
  // popup's list; until then, whichever is actually making noise, so a paused
  // tab does not shadow the track that is sounding.
  property var chosen: null

  readonly property var player: {
    if (root.chosen && root.players.indexOf(root.chosen) !== -1) return root.chosen

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
  readonly property bool popupOpen: PanelHost.shown && PanelHost.owner === readout

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
            renderType: Text.NativeRendering
          }

          Text {
            text: root.artist !== "" ? root.artist : "Unknown artist"
            color: Theme.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            width: Style.space(260)
            elide: Text.ElideRight
            renderType: Text.NativeRendering
          }

          // Only when there is one: an "Unknown album" line under "Unknown
          // artist" is three lines of saying nothing.
          Text {
            text: root.album
            visible: root.album !== ""
            color: Theme.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            width: Style.space(260)
            elide: Text.ElideRight
            renderType: Text.NativeRendering
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

      // ---- the other players ----
      //
      // Only when there is more than one. With a single player this is a list
      // naming the thing the panel is already titled after, and picking from a
      // list of one is not a choice.
      PanelSeparator {
        visible: root.players.length > 1
      }

      PanelSectionHeader {
        width: parent ? parent.width : 0
        visible: root.players.length > 1
        label: "Players"
      }

      Repeater {
        model: root.players.length > 1 ? root.players : []

        delegate: Rectangle {
          id: playerRow
          required property var modelData

          readonly property bool selected: root.player === playerRow.modelData

          width: Style.space(320)
          height: Style.space(30)
          radius: Theme.cornerRadius
          color: selected
            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Style.control.selectedFillAlpha)
            : (rowMouse.containsMouse
              ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.hoverFillAlpha)
              : "transparent")
          border.color: selected ? Theme.accent : "transparent"
          border.width: 1

          Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(8)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: playerRow.modelData.playbackState === MprisPlaybackState.Playing
                ? Util.glyph("f04c")
                : Util.glyph("f04b")
              color: playerRow.selected ? Theme.accent : Theme.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              renderType: Text.NativeRendering
            }

            Column {
              width: parent.width - Style.space(26)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              Text {
                width: parent.width
                text: root.playerName(playerRow.modelData)
                color: Theme.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.weight: playerRow.selected ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
                renderType: Text.NativeRendering
              }

              Text {
                width: parent.width
                text: root.playerDetail(playerRow.modelData)
                visible: text !== ""
                color: Theme.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                renderType: Text.NativeRendering
              }
            }
          }

          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.chosen = playerRow.modelData
          }
        }
      }
    }
  }
}
