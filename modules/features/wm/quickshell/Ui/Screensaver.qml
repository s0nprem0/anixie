import QtQuick
import ".."
import "."

// The screensaver: an opaque, input-catching cover shown before the session
// locks. It is not a security boundary — the lock is — so it shows the time and
// dismisses on the first key or click rather than asking for anything.
Item {
  id: root

  signal wake()

  focus: true

  property var now: new Date()
  readonly property string timeText: Qt.formatTime(root.now, "HH:mm")
  readonly property string dateText: Qt.formatDate(root.now, "dddd, d MMMM")

  onVisibleChanged: {
    if (root.visible) Qt.callLater(function () { root.forceActiveFocus() })
  }

  Keys.onPressed: function (event) {
    root.wake()
    event.accepted = true
  }

  Keys.onReleased: function (event) {
    event.accepted = true
  }

  Rectangle {
    anchors.fill: parent

    gradient: Gradient {
      GradientStop { position: 0; color: Theme.bg }
      GradientStop { position: 1; color: Theme.surface }
    }
  }

  Column {
    anchors.centerIn: parent
    spacing: Style.space(8)

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      height: implicitHeight
      text: root.timeText
      color: Theme.fg
      font.family: Style.font.family
      font.pixelSize: Style.space(56)
      font.weight: Font.Light
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      height: implicitHeight
      text: root.dateText
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle
    }
  }

  Column {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(64)
    spacing: Style.space(8)

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      height: implicitHeight
      text: Util.lock
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.space(18)
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      height: implicitHeight
      text: "Press any key to wake"
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
  }

  // Last, so it covers the clock too: any click or wheel wakes, and nothing
  // reaches the desktop underneath while the cover is up.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    onPressed: root.wake()
    onWheel: root.wake()
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.visible
    onTriggered: root.now = new Date()
  }
}
