import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../Ui"

// The clock's month view, plus the events from the configured read-only
// subscriptions. Split out of Clock.qml so the fetch, the parse, and the two
// small lists do not sit inside the bar widget's own file.
//
// The panel never talks to the network itself: `calendar-events` owns the
// config, the cache and the iCalendar parsing, and this only asks it for the
// month on screen. A missing binary (the module is disabled) or a missing
// config is a state this draws, not a crash.
Panel {
  id: cal

  // Substituted at build time from `anixie.wm.calendar.bin`. Empty when the
  // module is disabled, which is what turns the subscription half off.
  property string eventsBinary: ""

  // The clock owns both: the month names and the ISO week rule are the bar
  // widget's, and duplicating them here would let the two drift.
  property var monthNames: []
  property var weekNumber: function (date) { return 0 }

  readonly property date today: new Date()
  readonly property int todayDate: today.getDate()
  readonly property int todayMonth: today.getMonth()
  readonly property int todayYear: today.getFullYear()

  property int viewYear: todayYear
  property int viewMonth: todayMonth

  // The day whose events are listed below the grid. Starts on today, and moves
  // to the first of the month when the month is stepped away from today.
  property string selectedKey: dayKey(today)

  readonly property int monthLength: new Date(viewYear, viewMonth + 1, 0).getDate()
  readonly property int lead: (new Date(viewYear, viewMonth, 1).getDay() + 6) % 7
  readonly property int weekRows: Math.ceil((lead + monthLength) / 7)
  readonly property string monthTitle: monthNames[viewMonth] + " " + viewYear

  // The range the backend is asked for, as plain YYYY-MM-DD. Passing the month
  // rather than "today" is what makes stepping the month fetch that month.
  readonly property string rangeFrom: dayKey(new Date(viewYear, viewMonth, 1))
  readonly property string rangeTo: dayKey(new Date(viewYear, viewMonth + 1, 0))

  property var events: []
  property var warnings: []
  property bool configured: true
  property bool loading: false
  property string failure: ""

  maxWidth: Style.space(320)

  function pad(value) {
    return value < 10 ? "0" + value : String(value)
  }

  function dayKey(date) {
    return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate())
  }

  function keyOf(iso) {
    return String(iso || "").slice(0, 10)
  }

  // Whether one event covers a day. All-day events end exclusively; a timed
  // event at exactly midnight on the following day does not spill onto it.
  function covers(event, key) {
    const start = keyOf(event.start)
    if (start === "" || key < start) return false

    const end = keyOf(event.end)
    if (end === "") return key === start

    if (event.allDay) return key < end
    if (key > end) return false
    return !(key === end && String(event.end).slice(11, 16) === "00:00")
  }

  function dayEvents(key) {
    const out = []
    for (let i = 0; i < events.length; i++) {
      if (covers(events[i], key)) out.push(events[i])
    }
    return out
  }

  function hasEvents(key) {
    for (let i = 0; i < events.length; i++) {
      if (covers(events[i], key)) return true
    }
    return false
  }

  function timeLabel(event) {
    if (event.allDay) return "All day"
    const start = String(event.start || "")
    return start.length >= 16 ? start.slice(11, 16) : ""
  }

  function select(key) {
    cal.selectedKey = key
  }

  function step(delta) {
    const moved = new Date(viewYear, viewMonth + delta, 1)
    cal.viewYear = moved.getFullYear()
    cal.viewMonth = moved.getMonth()

    // Today when it is in the new month, otherwise the 1st. Keeping a selected
    // day from the old month would leave the list below the grid describing a
    // date that is not drawn.
    const todayInView = cal.todayYear === cal.viewYear && cal.todayMonth === cal.viewMonth
    cal.selectedKey = todayInView ? dayKey(cal.today) : dayKey(moved)
  }

  function weekMonday(row) {
    return new Date(viewYear, viewMonth, 1 - lead + row * 7)
  }

  function refresh() {
    if (eventsBinary === "") return

    cal.loading = true
    cal.failure = ""
    fetcher.command = [
      cal.eventsBinary,
      "list",
      "--from", cal.rangeFrom,
      "--to", cal.rangeTo
    ]
    fetcher.running = false
    fetcher.running = true
  }

  function apply(raw) {
    cal.loading = false

    try {
      const data = JSON.parse(String(raw || ""))
      cal.configured = data.configured !== false
      cal.events = Array.isArray(data.events) ? data.events : []
      cal.warnings = Array.isArray(data.warnings) ? data.warnings : []
    } catch (error) {
      cal.events = []
      cal.warnings = []
      cal.failure = "could not read the calendar response"
      console.warn("calendar: " + error)
    }
  }

  Component.onCompleted: refresh()
  onViewMonthChanged: refreshTimer.restart()
  onViewYearChanged: refreshTimer.restart()

  // A step or a year change can fire both bindings; one fetch follows the last
  // state rather than two racing ones.
  property Timer refreshTimer: Timer {
    interval: 40
    repeat: false
    onTriggered: cal.refresh()
  }

  property Process fetcher: Process {
    command: ["true"]
    running: false

    stdout: StdioCollector {
      onStreamFinished: cal.apply(this.text)
    }

    stderr: StdioCollector {
      onStreamFinished: cal.failure = String(this.text || "").trim()
    }

    onExited: function (exitCode) {
      if (exitCode !== 0 && cal.failure === "") cal.failure = "calendar backend failed"
    }
  }

  Column {
    width: cal.contentWidth
    spacing: Style.space(4)

    // ---- month header ----
    Row {
      spacing: 0

      WidgetButton {
        text: Util.chevronLeft
        fontSize: Style.bar.iconFont
        tooltipText: "Previous month"
        onPressed: function () { cal.step(-1) }
      }

      Text {
        width: Style.space(212)
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

    // ---- weekday header ----
    Row {
      spacing: 0

      // Over the week-number column of every row below.
      Item {
        width: Style.space(26)
        height: Style.space(16)
      }

      Repeater {
        model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

        delegate: Text {
          required property string modelData
          width: Style.space(38)
          height: Style.space(16)
          horizontalAlignment: Text.AlignHCenter
          text: modelData
          color: Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }

    // ---- the grid ----
    Repeater {
      model: cal.weekRows

      delegate: Row {
        id: weekRow
        required property int index
        spacing: 0

        Text {
          width: Style.space(26)
          height: Style.space(36)
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: cal.weekNumber(cal.weekMonday(weekRow.index))
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
            readonly property string key: inMonth
              ? cal.viewYear + "-" + cal.pad(cal.viewMonth + 1) + "-" + cal.pad(dayNumber)
              : ""
            readonly property bool isToday: inMonth
              && dayNumber === cal.todayDate
              && cal.viewMonth === cal.todayMonth
              && cal.viewYear === cal.todayYear
            readonly property bool isSelected: inMonth && key === cal.selectedKey

            width: Style.space(38)
            height: Style.space(36)

            Rectangle {
              anchors.centerIn: parent
              width: Style.space(28)
              height: Style.space(28)
              radius: Theme.cornerRadius
              color: parent.isToday ? Theme.accent : "transparent"
              border.width: parent.isSelected && !parent.isToday ? Style.strokeWidth : 0
              border.color: Theme.primary
            }

            Text {
              anchors.centerIn: parent
              anchors.verticalCenterOffset: parent.inMonth && cal.hasEvents(parent.key) ? -2 : 0
              text: parent.inMonth ? String(parent.dayNumber) : ""
              color: parent.isToday ? Theme.bg : Theme.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            // A dot, not a count: the list below is where the count is read.
            Rectangle {
              visible: parent.inMonth && cal.hasEvents(parent.key)
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(3)
              width: Style.space(3)
              height: Style.space(3)
              radius: width / 2
              color: parent.isToday ? Theme.bg : Theme.accent
            }

            MouseArea {
              anchors.fill: parent
              enabled: parent.inMonth
              cursorShape: Qt.PointingHandCursor
              onClicked: cal.select(parent.key)
            }
          }
        }
      }
    }

    PanelSeparator {}

    // ---- selected day ----
    Text {
      width: cal.contentWidth
      text: cal.selectedKey
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Repeater {
      model: cal.dayEvents(cal.selectedKey)

      delegate: Row {
        required property var modelData
        width: cal.contentWidth
        spacing: Style.space(8)

        Text {
          width: Style.space(58)
          text: cal.timeLabel(modelData)
          color: modelData.allDay ? Theme.accent : Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.NoWrap
        }

        Column {
          width: parent.width - Style.space(66)

          Text {
            width: parent.width
            text: String(modelData.summary || "(no title)")
            color: Theme.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            visible: String(modelData.location || "") !== ""
            text: String(modelData.location || "")
            color: Theme.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }
    }

    Text {
      width: cal.contentWidth
      visible: cal.eventsBinary !== ""
        && cal.configured
        && cal.failure === ""
        && cal.dayEvents(cal.selectedKey).length === 0
      text: cal.loading ? "Loading events…" : "No events"
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Text {
      width: cal.contentWidth
      visible: cal.eventsBinary === ""
      text: "Calendar subscriptions are disabled."
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Text {
      width: cal.contentWidth
      visible: cal.eventsBinary !== "" && !cal.configured
      text: "No subscription yet. Add an .ics URL to ~/.config/anixie/calendar.json."
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Text {
      width: cal.contentWidth
      visible: cal.failure !== ""
      text: cal.failure
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Text {
      width: cal.contentWidth
      visible: cal.warnings.length > 0
      text: String(cal.warnings.join(" · "))
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }
}
