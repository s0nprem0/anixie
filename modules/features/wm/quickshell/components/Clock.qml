import QtQuick
import ".."

Text {
  id: root
  color: Theme.fg
  font.family: "JetBrains Mono"
  font.pixelSize: 14
  font.weight: Font.DemiBold

  property var entry: ({})

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

    const format = entry.format ? String(entry.format) : "ddd dd MMM  HH:mm"

    // ddd has to precede dd in the alternation, or "ddd" matches as "dd" + "d".
    root.stamp = format.replace(/ddd|dd|HH|mm|MMM/g, function (token) {
      if (token === "ddd") return days[d.getDay()]
      if (token === "dd") return String(d.getDate()).padStart(2, "0")
      if (token === "HH") return String(d.getHours()).padStart(2, "0")
      if (token === "mm") return String(d.getMinutes()).padStart(2, "0")
      if (token === "MMM") return mons[d.getMonth()]
      return token
    })
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