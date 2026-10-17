import QtQuick
import ".."
import "../Ui"

// Clock. Formatted inside a timer tick rather than inside a text binding: a
// binding that calls new Date() reads no property, so QML cannot know when to
// re-evaluate it — it runs once and the clock freezes on that value. Assigning
// a string from the handler is what makes the text update.
//
// Left opens a month calendar, right cycles the label between the two formats.
BarWidget {
  id: root

  property string stamp: ""

  // Which of the two formats the label is drawn with.
  property bool altFormat: false

  readonly property string format: String(root.setting("format", "ddd dd MMM  HH:mm"))
  readonly property string formatAlt: String(root.setting("formatAlt", "dddd dd MMMM yyyy"))
  readonly property string activeFormat: root.altFormat ? root.formatAlt : root.format

  readonly property var dayNames: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
  readonly property var monthNames: ["January", "February", "March", "April", "May", "June",
                                     "July", "August", "September", "October", "November", "December"]

  function refresh() {
    root.stamp = root.formatDate(new Date(), root.activeFormat)
  }

  // Tokens are replaced longest-first, so dddd cannot match as ddd plus a stray
  // d, and MMMM cannot match as MMM plus one. Anything unrecognised is left as
  // typed, so a literal in the format string survives.
  function formatDate(date, format) {
    return format.replace(/dddd|ddd|dd|MMMM|MMM|yyyy|HH|mm|W/g, function (token) {
      if (token === "dddd") return root.dayNames[date.getDay()]
      if (token === "ddd") return root.dayNames[date.getDay()].slice(0, 3)
      if (token === "dd") return String(date.getDate()).padStart(2, "0")
      if (token === "MMMM") return root.monthNames[date.getMonth()]
      if (token === "MMM") return root.monthNames[date.getMonth()].slice(0, 3)
      if (token === "yyyy") return String(date.getFullYear())
      if (token === "HH") return String(date.getHours()).padStart(2, "0")
      if (token === "mm") return String(date.getMinutes()).padStart(2, "0")
      if (token === "W") return String(root.isoWeek(date))
      return token
    })
  }

  // ISO 8601: the week belongs to the year holding its Thursday, weeks start on
  // Monday, and the first week is the one with that Thursday in it.
  function isoWeek(date) {
    const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()))
    const weekday = d.getUTCDay() || 7
    d.setUTCDate(d.getUTCDate() + 4 - weekday)

    const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1))
    return Math.ceil(((d - yearStart) / 86400000 + 1) / 7)
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
    tooltipText: "Calendar · right-click to change the format"

    onPressed: function (button) {
      if (button === Qt.LeftButton) PanelHost.toggle(readout, calendar)
      else if (button === Qt.RightButton) {
        root.altFormat = !root.altFormat
        root.refresh()
      }
    }
  }

  Component {
    id: calendar

    Panel {
      id: cal

      // No header of the Panel's own: the month and its steppers are the header.
      title: ""
      maxWidth: Style.space(284)

      readonly property date today: new Date()
      readonly property int todayDate: today.getDate()
      readonly property int todayMonth: today.getMonth()
      readonly property int todayYear: today.getFullYear()

      // The month on screen, which starts at the current one and steps from
      // here. Reset every time the popup is opened, since PanelHost rebuilds
      // its contents rather than keeping them.
      property int viewYear: todayYear
      property int viewMonth: todayMonth

      readonly property int monthLength: new Date(viewYear, viewMonth + 1, 0).getDate()
      // Blank cells before the 1st, with the week starting on Monday.
      readonly property int lead: (new Date(viewYear, viewMonth, 1).getDay() + 6) % 7
      readonly property int weekRows: Math.ceil((lead + monthLength) / 7)
      readonly property string monthTitle: root.monthNames[viewMonth] + " " + viewYear

      function step(delta) {
        const moved = new Date(viewYear, viewMonth + delta, 1)
        cal.viewYear = moved.getFullYear()
        cal.viewMonth = moved.getMonth()
      }

      // Monday of the first row, from which both the date and the week number of
      // any cell follow.
      function weekMonday(row) {
        return new Date(viewYear, viewMonth, 1 - lead + row * 7)
      }

      Column {
        spacing: Style.space(4)

        Row {
          spacing: 0

          WidgetButton {
            text: Util.chevronLeft
            fontSize: Style.bar.iconFont
            tooltipText: "Previous month"
            onPressed: function () { cal.step(-1) }
          }

          Text {
            width: Style.space(190)
            height: Style.space(Style.bar.iconSlot)
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            text: cal.monthTitle
            color: Theme.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.weight: Font.DemiBold
          }

          WidgetButton {
            text: Util.chevronRight
            fontSize: Style.bar.iconFont
            tooltipText: "Next month"
            onPressed: function () { cal.step(1) }
          }
        }

        Row {
          spacing: 0

          // Sits over the week-number column of every row below.
          Item {
            width: Style.space(26)
            height: Style.space(16)
          }

          Repeater {
            model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

            delegate: Text {
              required property string modelData
              width: Style.space(34)
              height: Style.space(16)
              horizontalAlignment: Text.AlignHCenter
              text: modelData
              color: Theme.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }

        Repeater {
          model: cal.weekRows

          delegate: Row {
            id: weekRow
            required property int index

            spacing: 0

            Text {
              width: Style.space(26)
              height: Style.space(34)
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              text: root.isoWeek(cal.weekMonday(weekRow.index))
              color: Theme.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: 7

              delegate: Item {
                required property int index

                readonly property int dayNumber: weekRow.index * 7 + index - cal.lead + 1
                readonly property bool inMonth: dayNumber >= 1 && dayNumber <= cal.monthLength
                readonly property bool isToday: inMonth
                  && dayNumber === cal.todayDate
                  && cal.viewMonth === cal.todayMonth
                  && cal.viewYear === cal.todayYear

                width: Style.space(34)
                height: Style.space(34)

                Rectangle {
                  anchors.centerIn: parent
                  width: Style.space(26)
                  height: Style.space(26)
                  radius: Theme.cornerRadius
                  color: Theme.accent
                  visible: parent.isToday
                }

                Text {
                  anchors.centerIn: parent
                  text: parent.inMonth ? String(parent.dayNumber) : ""
                  color: parent.isToday ? Theme.bg : Theme.fg
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
              }
            }
          }
        }
      }
    }
  }
}
