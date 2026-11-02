import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../Ui"

// Google Meet picture-in-picture.
//
// A browser cannot give a QML surface its video stream, so this uses the window
// Hyprland already has: the script floats, pins and shrinks the Meet window into
// the bottom-right corner, and restores its saved geometry on the next press.
// The widget only exists while a Meet window is open; it is not a permanent
// invitation to go looking for one.
BarWidget {
  id: root

  readonly property string script: Quickshell.env("HOME") + "/.config/quickshell/scripts/meet-pip.sh"

  property bool found: false
  property string title: ""

  function refresh() {
    if (probe.running) return
    probe.running = true
  }

  function toggle() {
    Commands.runQuoted("sh", [root.script, "toggle"])
    afterToggle.restart()
  }

  wantsSlot: root.found
  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  Process {
    id: probe
    running: true
    command: ["sh", root.script, "status"]

    stdout: StdioCollector {
      onStreamFinished: {
        const text = String(this.text || "").trim()
        const tab = text.indexOf("\t")
        root.found = text.charAt(0) === "1"
        root.title = tab >= 0 ? text.slice(tab + 1) : ""
      }
    }
  }

  Timer {
    interval: 4000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: afterToggle
    interval: 450
    repeat: false
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: readout
    anchors.centerIn: parent
    text: Util.video
    active: true
    tooltipText: "Google Meet"
      + (root.title !== "" ? " · " + root.title : "")
      + " · click for picture-in-picture"

    onPressed: function (button) {
      if (button === Qt.LeftButton || button === Qt.MiddleButton) root.toggle()
    }
  }
}
