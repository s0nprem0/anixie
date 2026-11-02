pragma Singleton

import QtQuick

// Flashes every output's name on that output.
//
// The Displays panel can say "HDMI-A-1" all it likes, but with two black
// rectangles on the desk the row and the screen still have to be matched. This
// is the state behind a short overlay per output; `monitors identify` reaches it
// through the shell's IPC, and the panel's Identify action calls that command.
QtObject {
  id: root

  property bool opened: false
  property int duration: 1600

  function flash() {
    root.opened = true
    // Restart even when it is already up: a second press should extend the
    // time, not leave the first countdown to hide it.
    timer.restart()
  }

  property Timer timer: Timer {
    interval: root.duration
    onTriggered: root.opened = false
  }
}
