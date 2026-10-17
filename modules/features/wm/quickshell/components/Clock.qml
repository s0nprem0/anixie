import QtQuick
import ".."

Text {
  id: root
  color: Theme.fg
  font.family: "JetBrains Mono"
  font.pixelSize: 14
  font.weight: Font.DemiBold

  // Formatted inside a timer tick instead of inside the text binding. A binding
  // that calls new Date() reads no property, so QML cannot know when to
  // re-evaluate it: it runs once and the clock freezes on that value. Assigning
  // a string from the handler is what makes the text update.
  property string stamp: ""

  function refresh() {
    const d = new Date()
    const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    const mons = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    const hh = String(d.getHours()).padStart(2, "0")
    const mm = String(d.getMinutes()).padStart(2, "0")
    root.stamp = days[d.getDay()] + " " + String(d.getDate()).padStart(2, "0")
               + " " + mons[d.getMonth()] + "  " + hh + ":" + mm
  }

  Timer {
    running: true
    interval: 1000
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  text: root.stamp
}