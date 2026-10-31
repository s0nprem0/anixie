import QtQuick
import Quickshell
import ".."
import "../Ui"

// One application in the dock: its icon, its newest window's title, and a count
// when it has more than one window open.
//
// Clicking brings the app's best window forward rather than always the newest
// one — see DockHost.pickWindow — so an app with a background window and a
// focused one comes forward in the order you would expect.
Item {
  id: root

  required property var app

  readonly property var windows: root.app && root.app.windows ? root.app.windows : []
  readonly property int count: root.windows.length
  readonly property var newest: root.windows.length > 0 ? root.windows[0] : null

  // A minimized window is not "closed and forgotten": it is still there, and the
  // dock is the only way back to it, so it is marked rather than hidden.
  readonly property bool anyMinimized: root.windows.some(function (w) { return w.minimized })
  readonly property bool anyFocused: root.windows.some(function (w) { return DockHost.isFocused(w.address) })

  height: Style.space(34)

  scale: hover.containsMouse ? 1.06 : 1.0
  transformOrigin: Item.Center
  Behavior on scale { NumberAnimation { duration: Style.duration(120) } }

  Rectangle {
    anchors.fill: parent
    radius: Theme.cornerRadius
    // Accented only for the window that actually has input. A softer tint for a
    // tile that merely has a window, so the two states are distinguishable at a
    // glance without the accent meaning "click me".
    color: root.anyFocused ? Theme.primary
      : hover.containsMouse ? Theme.bg
      : "transparent"
    opacity: root.anyFocused ? 0.28 : 1

    Behavior on color { ColorAnimation { duration: Style.duration(120) } }
  }

  MouseArea {
    id: hover

    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onClicked: {
      if (!root.app || root.windows.length === 0) {
        Commands.app(root.app ? root.app.klass : "")
        return
      }
      DockHost.activate(root.app)
    }
  }

  Row {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    anchors.right: closeButton.left
    anchors.rightMargin: Style.space(6)
    spacing: Style.space(8)

    // The app's icon where one resolves, and its initial where none does.
    //
    // Most of a NixOS session's applications have no installed icon: their
    // desktop entries live inside their own store paths and their icons are not
    // in a theme, so iconPath comes back empty for nearly everything. Rather
    // than a row of blanks, an unresolvable app gets its initial in a rounded
    // tile, which stays readable and looks deliberate.
    Rectangle {
      width: Style.space(20)
      height: Style.space(20)
      radius: width / 3
      color: Theme.bg
      border.color: Theme.border
      border.width: Style.strokeWidth
      anchors.verticalCenter: parent.verticalCenter

      readonly property string iconSource: root.app ? Quickshell.iconPath(root.app.klass, "") : ""

      Image {
        anchors.fill: parent
        anchors.margins: Style.space(2)
        visible: parent.iconSource !== ""
        source: parent.iconSource
        sourceSize.width: Style.bar.iconSize * 2
        sourceSize.height: Style.bar.iconSize * 2
        fillMode: Image.PreserveAspectFit
        smooth: true
      }

      Text {
        anchors.centerIn: parent
        visible: parent.parent.iconSource === ""
        text: root.app && root.app.klass !== ""
          ? root.app.klass.charAt(0).toUpperCase()
          : "?"
        color: Theme.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.weight: Font.DemiBold
      }
    }

    Text {
      width: Math.max(0, parent.width - Style.space(20) - Style.space(8) - countBadge.width - Style.space(8))
      anchors.verticalCenter: parent.verticalCenter
      text: root.newest ? root.newest.title : ""
      color: Theme.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }

    Rectangle {
      id: countBadge

      anchors.verticalCenter: parent.verticalCenter
      visible: root.count > 1
      width: visible ? Style.space(16) : 0
      height: visible ? Style.space(14) : 0
      radius: height / 2
      color: Theme.bg

      Text {
        anchors.centerIn: parent
        visible: root.count > 1
        text: String(root.count)
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }

  // A minimized window sits on Hyprland's special workspace, so without this the
  // tile looks like an ordinary running app when in fact nothing is on screen.
  Rectangle {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(2)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(3)
    height: parent.height - Style.space(10)
    radius: width / 2
    visible: root.anyMinimized
    color: Theme.accent
  }

  // Pin toggle, shown on hover. Pinned apps stay in the dock with no window.
  Rectangle {
    id: pinButton

    anchors.right: closeButton.left
    anchors.rightMargin: Style.space(4)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(20)
    height: Style.space(20)
    radius: width / 2
    visible: hover.containsMouse
    color: pinMouse.containsMouse ? Theme.bg : "transparent"

    Text {
      anchors.centerIn: parent
      text: DockHost.isPinned(root.app ? root.app.klass : "") ? "📌" : "📍"
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      id: pinMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton
      onClicked: {
        if (!root.app) return
        if (DockHost.isPinned(root.app.klass)) DockHost.unpin(root.app.klass)
        else DockHost.pin(root.app.klass)
      }
    }
  }

  // Running indicator: a dot or a line, depending on the dock's style.
  Rectangle {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(2)
    anchors.verticalCenter: parent.verticalCenter
    visible: root.windows.length > 0
    width: DockHost.indicatorStyle === "line" ? Style.space(3) : Style.space(6)
    height: DockHost.indicatorStyle === "line" ? parent.height - Style.space(10) : Style.space(6)
    radius: DockHost.indicatorStyle === "dot" ? width / 2 : Style.strokeWidth
    color: root.anyFocused ? Theme.primary : Theme.muted
  }

  // Only on hover, and only for the tile under the pointer, so a dock full of
  // close buttons is not a wall of targets.
  Rectangle {
    id: closeButton

    anchors.right: parent.right
    anchors.rightMargin: Style.space(4)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(20)
    height: Style.space(20)
    radius: width / 2
    visible: hover.containsMouse
    color: closeMouse.containsMouse ? Theme.danger : "transparent"

    Text {
      anchors.centerIn: parent
      visible: root.anyFocused || hover.containsMouse
      text: "✕"
      color: Theme.bg
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      id: closeMouse

      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton
      onClicked: DockHost.close(root.newest ? root.newest.address : "")
    }
  }
}