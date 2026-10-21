import QtQuick
import ".."
import "../Ui"
import Quickshell
import Quickshell.Io

// Somewhere else's clock, beside yours.
//
// A second time zone on the bar is the one piece of Omarchy's centre group this
// bar did not have, and it is the small one: the time where someone else is, so
// a call does not need arithmetic. `date` does the zone, because QML's JavaScript
// has no time zone database — `Intl` is not in this engine — and a Process once a
// minute is cheaper and more correct than a table of offsets that goes wrong
// twice a year.
//
// The zones are a list in bar.json so the widget is worth having on a machine
// whose people are somewhere specific. Left and right click step through it,
// which is how one widget covers "what time is it in Sydney" and "and in Lisbon".
BarWidget {
  id: root

  readonly property var zones: {
    const configured = root.setting("zones", null)
    if (configured && configured.length > 0) return configured

    return [
      { label: "UTC", zone: "UTC" },
      { label: "LDN", zone: "Europe/London" },
      { label: "NYC", zone: "America/New_York" },
      { label: "TYO", zone: "Asia/Tokyo" }
    ]
  }

  property int index: 0
  readonly property var zone: root.zones[Math.max(0, Math.min(root.zones.length - 1, root.index))]

  property string stamp: ""

  function step(delta) {
    if (root.zones.length === 0) return
    root.index = (root.index + delta + root.zones.length) % root.zones.length
  }

  function refresh() {
    clock.running = false
    clock.running = true
    root.schedule()
  }

  // Re-read on the minute rather than on a timer of its own length: a clock that
  // refreshes every sixty seconds from whenever it started is wrong by up to a
  // minute, and this is the one reading where that is visible.
  //
  // One shot to the boundary, not a one-second timer checking the second: the
  // date process still runs once a minute, but the shell stops waking up sixty
  // times to decide it has nothing to do.
  function schedule() {
    const now = new Date()
    tick.interval = Math.max(50, (60 - now.getSeconds()) * 1000 - now.getMilliseconds())
    tick.restart()
  }

  Process {
    id: clock
    command: ["date", "+%H:%M"]
    environment: ({ TZ: root.zone.zone, LC_TIME: "C" })
    stdout: StdioCollector {
      onStreamFinished: root.stamp = String(this.text).trim()
    }
  }

  Timer {
    id: tick
    interval: 60000
    running: true
    repeat: false
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  onIndexChanged: root.refresh()

  wantsSlot: root.stamp !== ""
  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  // Text, not a glyph: see Weather.qml. A BarIconButton would scale "20:04" to
  // the size of an icon, and the time is the whole point of this widget.
  WidgetButton {
    id: readout
    anchors.centerIn: parent
    text: root.vertical
      ? root.stamp
      : root.stamp + "  " + root.zone.label
    fontSize: Style.font.body
    centerFigures: false
    tooltipText: root.zone.label + " · " + root.zone.zone
      + " · click for the next zone"

    onPressed: function (button) {
      if (button === Qt.LeftButton) root.step(1)
      else if (button === Qt.RightButton) root.step(-1)
    }
  }
}