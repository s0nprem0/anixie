import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../Ui"

// Clock. Local time is formatted in JavaScript on the minute; another zone goes
// through `date`, because the QML engine has no time zone database and `Intl` is
// not in it. That keeps the common case fork-free — the label changes once a
// minute, so a subprocess for it was a subprocess for a string this can build
// itself.
//
// Left opens a month calendar, right cycles the label between the two formats,
// middle opens the timezone selector.
BarWidget {
  id: root

  // Reachable by hotkey as well as by click.
  Component.onCompleted: {
    root.registerPanel("calendar", readout, calendar)
    root.registerPanel("clock-zone", readout, zonePanel)
  }

  property string stamp: ""

  // Which of the two formats the label is drawn with.
  property bool altFormat: false
  property string zone: ""

  readonly property string format: String(root.setting("format", "ddd dd MMM  HH:mm"))
  readonly property string formatAlt: String(root.setting("formatAlt", "dddd dd MMMM yyyy"))
  readonly property string activeFormat: root.altFormat ? root.formatAlt : root.format

  // Local first, then a short list that covers most calls. A layout entry may
  // replace it with its own `zones` array, in the same shape WorldClock uses.
  readonly property var zones: {
    const configured = root.setting("zones", null)
    if (configured && configured.length > 0) return configured

    return [
      { label: "Local", zone: "" },
      { label: "UTC", zone: "UTC" },
      { label: "London", zone: "Europe/London" },
      { label: "Berlin", zone: "Europe/Berlin" },
      { label: "New York", zone: "America/New_York" },
      { label: "Los Angeles", zone: "America/Los_Angeles" },
      { label: "Tokyo", zone: "Asia/Tokyo" },
      { label: "Sydney", zone: "Australia/Sydney" }
    ]
  }

  readonly property string zoneLabel: {
    for (let i = 0; i < root.zones.length; i++) {
      const entry = root.zones[i]
      if (entry && entry.zone === root.zone) return String(entry.label || root.zone)
    }
    return root.zone
  }

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME")
    || Quickshell.env("HOME") + "/.local/state") + "/anixie/clock"
  readonly property string zonePath: root.stateDir + "/zone"

  readonly property var dayNames: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
  readonly property var monthNames: ["January", "February", "March", "April", "May", "June",
                                     "July", "August", "September", "October", "November", "December"]

  function refresh() {
    clock.running = false

    // An empty zone means "use the system's local zone", not UTC. `TZ=""` would
    // select UTC, so the local case has to leave the variable unset instead.
    if (root.zone === "") {
      root.stamp = root.localStamp(root.activeFormat)
    } else {
      const format = root.dateFormat(root.activeFormat)
      // `date` takes the zone in its environment, so running it directly saves
      // the shell this used to start for every one of those calls. The only
      // reason for the shell was setting TZ on the command line.
      clock.command = ["date", "+" + format]
      clock.environment = { TZ: root.zone, LC_TIME: "C" }
      clock.running = true
    }

    root.schedule()
  }

  // The label has no seconds, so nothing has to happen until the minute turns.
  // This used to be a one-second timer whose handler asked the clock what second
  // it was sixty times a minute; one shot to the next boundary is the same
  // promptness for a sixtieth of the wakeups.
  function schedule() {
    const now = new Date()
    tick.interval = Math.max(50, (60 - now.getSeconds()) * 1000 - now.getMilliseconds())
    tick.restart()
  }

  // The same tokens as dateFormat, filled from the local clock. LC_TIME=C is why
  // the names are the English arrays below rather than whatever the locale says.
  function localStamp(format) {
    const now = new Date()
    const pad = function (value) { return (value < 10 ? "0" : "") + value }
    const day = root.dayNames[now.getDay()]
    const month = root.monthNames[now.getMonth()]

    return String(format).replace(/dddd|ddd|dd|MMMM|MMM|yyyy|HH|mm|W/g, function (token) {
      if (token === "dddd") return day
      if (token === "ddd") return day.slice(0, 3)
      if (token === "dd") return pad(now.getDate())
      if (token === "MMMM") return month
      if (token === "MMM") return month.slice(0, 3)
      if (token === "yyyy") return String(now.getFullYear())
      if (token === "HH") return pad(now.getHours())
      if (token === "mm") return pad(now.getMinutes())
      if (token === "W") return pad(root.isoWeek(now))
      return token
    })
  }

  // The same tokens, for the zone case, where date(1) is what turns them into
  // words. `%` is escaped first so a literal in a format survives the pass
  // through date rather than becoming an unknown conversion.
  function dateFormat(format) {
    return String(format).replace(/%/g, "%%")
      .replace(/dddd|ddd|dd|MMMM|MMM|yyyy|HH|mm|W/g, function (token) {
        if (token === "dddd") return "%A"
        if (token === "ddd") return "%a"
        if (token === "dd") return "%d"
        if (token === "MMMM") return "%B"
        if (token === "MMM") return "%b"
        if (token === "yyyy") return "%Y"
        if (token === "HH") return "%H"
        if (token === "mm") return "%M"
        if (token === "W") return "%V"
        return token
      })
  }

  function setZone(next) {
    root.zone = String(next || "")
    zoneWriter.command = ["sh", "-c",
      'mkdir -p "$1"; printf "%s\n" "$2" > "$1/zone"',
      "_", root.stateDir, root.zone]
    zoneWriter.running = true
  }

  // ISO 8601: the week belongs to the year holding its Thursday, weeks start on
  // Monday, and the first week is the one with that Thursday in it. The calendar
  // grid still needs this in JavaScript; only the bar's label goes through date.
  function isoWeek(date) {
    const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()))
    const weekday = d.getUTCDay() || 7
    d.setUTCDate(d.getUTCDate() + 4 - weekday)

    const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1))
    return Math.ceil(((d - yearStart) / 86400000 + 1) / 7)
  }

  wantsSlot: stamp !== ""
  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  Timer {
    id: tick
    running: true
    repeat: false
    interval: 60000
    // Fires once immediately, then `refresh` re-arms it for the next minute.
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // A new zone is the one change that makes the label wrong now rather than at
  // the next minute tick.
  onZoneChanged: root.refresh()

  Process {
    id: clock
    running: false
    stdout: StdioCollector {
      onStreamFinished: root.stamp = String(this.text).trim()
    }
  }

  Process {
    id: zoneWriter
    running: false
  }

  // The saved choice is read once at startup. There is no watch: the live path
  // is the selector below, which assigns the property and writes the file.
  property FileView zoneFile: FileView {
    path: root.zonePath
    printErrors: false
    blockLoading: true

    onLoaded: {
      const saved = String(root.zoneFile.text()).trim()
      // The assignment refreshes through onZoneChanged; an unchanged zone is
      // already handled by the timer's first fire.
      if (saved !== root.zone) root.zone = saved
    }
  }

  WidgetButton {
    id: readout
    contextMenu: function () {
      return [
        { label: "Calendar", glyph: Util.clock, action: function () { PanelRegistry.toggle("calendar", readout) } },
        { label: "Clock timezone", action: function () { PanelRegistry.toggle("clock-zone", readout) } },
        { separator: true },
        {
          label: root.altFormat ? "24-hour clock" : "12-hour clock",
          action: function () {
            root.altFormat = !root.altFormat
            root.refresh()
          }
        }
      ]
    }
    anchors.centerIn: parent
    text: root.vertical || root.zone === ""
      ? root.stamp
      : root.stamp + "  " + root.zoneLabel
    fontSize: Style.font.body
    centerFigures: false
    active: true
    useActiveColor: false
    tooltipText: "Calendar · left-click for the month · right-click for menu"
      + " · middle-click for the timezone"
      + (root.zone === "" ? "" : " · " + root.zone)

    onPressed: function (button) {
      if (button === Qt.LeftButton) PanelRegistry.toggle("calendar", readout)
      else if (button === Qt.RightButton) {
        root.altFormat = !root.altFormat
        root.refresh()
      } else if (button === Qt.MiddleButton) {
        PanelRegistry.toggle("clock-zone", readout)
      }
    }
  }

  Component {
    id: zonePanel

    Panel {
      id: zoneCard
      title: "Clock timezone"
      maxWidth: Style.space(300)

      Repeater {
        model: root.zones

        delegate: ChoiceRow {
          id: zoneRow
          required property var modelData

          width: zoneCard.contentWidth
          label: String(zoneRow.modelData.label || zoneRow.modelData.zone)
          detail: zoneRow.modelData.zone === ""
            ? "System local time"
            : String(zoneRow.modelData.zone)
          selected: root.zone === zoneRow.modelData.zone
          onClicked: {
            root.setZone(String(zoneRow.modelData.zone))
            PanelHost.close("clock-zone", Screens.nameOf(root))
          }
        }
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
