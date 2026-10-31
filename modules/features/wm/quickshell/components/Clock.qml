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
    text: root.vertical
      ? root.stamp.replace(/\s+/g, "\n")
      : (root.zone === "" ? root.stamp : root.stamp + "  " + root.zoneLabel)
    fontSize: root.vertical ? Style.font.bodySmall : Style.font.body
    labelRotation: 0
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
      maxWidth: Style.space(300)

      PanelHero {
        width: zoneCard.contentWidth
        glyph: Util.clock
        title: "Clock timezone"
        subtitle: "the time zone shown in the bar"
      }

      PanelSeparator {}

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

    CalendarPanel {
      eventsBinary: "@CALENDAR_EVENTS@"
      monthNames: root.monthNames
      weekNumber: function (date) { return root.isoWeek(date) }
    }
  }
}
