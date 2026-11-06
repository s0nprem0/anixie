pragma ComponentBehavior: Bound
import QtQuick
import ".."
import "../Ui"
import Quickshell.Wayland

// Title of the focused window, read from the compositor rather than from
// Hyprland, so it also covers windows from other toolkits. Left click
// activates, middle click closes, right click opens a small action menu.
BarWidget {
  id: root

  readonly property var toplevel: ToplevelManager.activeToplevel
  readonly property string title: toplevel ? (toplevel.title || "") : ""

  // Validate the configured cap: a missing, non-numeric, non-finite, zero or
  // negative value falls back to the default rather than producing NaN or a
  // zero-width (or infinitely wide) widget.
  readonly property real configuredMaxWidth: Number(setting("maxWidth", 200))
  readonly property real maxLabelWidth: {
    const value = configuredMaxWidth
    return Number.isFinite(value) && value > 0 ? value : 200
  }

  // One effective label width, used for both the widget and the text, so the
  // two cannot disagree about how much of the title is visible.
  readonly property real labelWidth: Math.min(maxLabelWidth, label.implicitWidth)

  wantsSlot: title !== "" && !root.vertical
  implicitWidth: labelWidth + 16
  implicitHeight: barSize

  // A title that changes width every few seconds would otherwise make the rest
  // of the bar twitch; ease into the new width instead.
  Behavior on implicitWidth {
    NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic }
  }

  Rectangle {
    anchors.fill: parent
    radius: Theme.cornerRadius
    color: mouseArea.containsMouse
      ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.hoverFillAlpha)
      : "transparent"

    Behavior on color {
      ColorAnimation { duration: Style.duration(Style.motion.fast) }
    }
  }

  Text {
    id: label
    anchors.verticalCenter: parent.verticalCenter
    x: 8
    width: root.labelWidth
    text: root.title
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: Theme.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    renderType: Text.NativeRendering

    onTruncatedChanged: {
      if (mouseArea.containsMouse) {
        if (label.truncated && root.title !== "")
          TooltipHost.show(root.title, root)
        else
          TooltipHost.hide(root)
      }
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    onEntered: {
      if (label.truncated && root.title !== "")
        TooltipHost.show(root.title, root)
    }

    onExited: TooltipHost.hide(root)

    onClicked: function (mouse) {
      const toplevel = root.toplevel
      if (!toplevel) return

      if (mouse.button === Qt.MiddleButton) {
        try { toplevel.close() } catch (e) { }
      } else if (mouse.button === Qt.RightButton) {
        TooltipHost.hide(root)
        ContextMenuHost.open([
          {
            label: "Activate",
            action: function () {
              const current = root.toplevel
              if (current) try { current.activate() } catch (e) { }
            }
          },
          {
            label: "Close",
            danger: true,
            action: function () {
              const current = root.toplevel
              if (current) try { current.close() } catch (e) { }
            }
          }
        ], root)
      } else {
        try { toplevel.activate() } catch (e) { }
      }
    }
  }
}