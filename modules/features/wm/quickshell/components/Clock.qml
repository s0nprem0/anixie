import QtQuick
import ".."
import "../Ui"

// Clock. Formatted inside a timer tick rather than inside a text binding: a
// binding that calls new Date() reads no property, so QML cannot know when to
// re-evaluate it — it runs once and the clock freezes on that value. Assigning
// a string from the handler is what makes the text update.
BarWidget {
  id: root

  property string stamp: ""

  function refresh() {
    const d = new Date()
    const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    const mons = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    const format = String(root.setting("format", "ddd dd MMM  HH:mm"))

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

  visible: stamp !== ""
  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  Timer {
    running: true
    interval: 1000
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: readout
    anchors.centerIn: parent
    text: root.stamp
    fontSize: Style.font.body
    centerFigures: false
    active: true
    useActiveColor: false
  }
}