import QtQuick
import ".."
import "../Ui"
import Quickshell
import Quickshell.Io

// Weather: the current temperature in the bar, and a three-day forecast behind a
// click.
//
// The reading comes from wttr.in, in the place named by `location` in this
// widget's bar.json entry. Left out or empty, wttr.in geolocates the requestor by
// IP, as it always did. What changes is where the data goes: the bar half asks
// wttr.in for the three values it draws, and the forecast half asks for the full
// document and trims it, rather than one script printing both.
//
// The temperature is written to a property from a Process result rather than
// through a text binding for the same reason the clock is: a binding reading no
// property never re-evaluates, so the label would freeze at whatever it first
// printed.
//
// A forecast does not change by the minute, so this is polled on a long timer —
// half an hour, as before — rather than on a tick.
BarWidget {
  id: root

  // Reachable by hotkey as well as by click.
  Component.onCompleted: {
    PanelRegistry.register("weather", readout, forecastPanel)
    root.ready = true
  }

  // The entry is handed over after the module is built, so a change handler on
  // `location` can fire before the Processes below exist.
  property bool ready: false

  readonly property int interval: Number(root.setting("interval", 1800)) * 1000

  // A city, postcode or "LAT,LON", as wttr.in accepts them. Empty means IP
  // geolocation, which is what a VPN makes wrong — hence the override.
  readonly property string location: String(root.setting("location", "")).trim()

  property string temperature: ""
  property string conditions: ""

  // The forecast, held as the parsed object once a request lands.
  property var forecast: null

  // The location arrives with the bar.json entry after the module is built, so
  // the first request may already be running on IP geolocation. Fetch again when
  // it changes rather than waiting out the half-hour timer.
  onLocationChanged: {
    if (!root.ready) return
    root.refreshBar()
    if (root.forecast !== null) root.refreshForecast()
  }

  // Whether a forecast request is in flight, so the panel can say it is looking
  // rather than that there is nothing — the two look identical otherwise, and a
  // panel that reports a failure it has not established is worse than a blank.
  property bool fetching: false

  // Each request carries its own result to its own collector, so there is nothing
  // to tell apart and nothing to guard: a shared "which request is this" flag was
  // one, and it threw results away. The two overlap at startup — the bar's own
  // fetch and the panel's, from a hotkey — and whichever finished second was
  // dropped on the grounds that its flag was no longer set, which is how the bar
  // sat empty with the weather working perfectly well.
  function refreshBar() {
    barQuery.running = false
    barQuery.running = true
  }

  function refreshForecast() {
    root.fetching = true
    forecastQuery.running = false
    forecastQuery.running = true
  }

  function applyBar(raw) {
    try {
      const data = JSON.parse(String(raw || ""))
      root.temperature = String(data.text || "")
      root.conditions = String(data.tooltip || "")
    } catch (e) {
      root.temperature = ""
      root.conditions = ""
    }
  }

  function applyForecast(raw) {
    try {
      const data = JSON.parse(String(raw || ""))
      root.forecast = data && data.ok ? data : null
    } catch (e) {
      root.forecast = null
    }
  }

  function dayName(date) {
    const parsed = new Date(date + "T00:00:00")
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][parsed.getDay()]
  }

  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight
  wantsSlot: root.temperature !== ""

  // A plain button rather than a BarIconButton: that one draws its `text`
  // through OpticalGlyph, which fits whatever it is given into the glyph canvas
  // — a single icon. "30°C" arriving there was scaled to the size of an icon,
  // which is why the temperature read as a speck beside the clock. This is text,
  // so it is drawn as text, at the same size as the clock.
  WidgetButton {
    id: readout
    contextMenu: [
      { label: "Weather panel", glyph: Util.sun, action: function () { PanelRegistry.toggle("weather", readout) } },
      { label: "Refresh", action: function () { root.refreshBar() } }
    ]
    anchors.centerIn: parent
    text: root.temperature
    fontSize: Style.font.body
    centerFigures: false
    tooltipText: root.conditions !== ""
      ? root.conditions + " · click for the forecast"
      : "Weather · click for the forecast"

    onPressed: function (button) {
      if (button === Qt.LeftButton || button === Qt.MiddleButton) PanelRegistry.toggle("weather", readout)
    }
  }

  Process {
    id: barQuery
    command: ["sh", Quickshell.env("HOME") + "/.config/quickshell/scripts/weather-forecast.sh", "bar", root.location]
    running: true
    stdout: StdioCollector {
      onStreamFinished: root.applyBar(this.text)
    }
  }

  Process {
    id: forecastQuery
    command: ["sh", Quickshell.env("HOME") + "/.config/quickshell/scripts/weather-forecast.sh", "forecast", root.location]
    stdout: StdioCollector {
      onStreamFinished: {
        root.applyForecast(this.text)
        root.fetching = false
      }
    }
    // Nothing came back at all — no collector, no collector's stream. The panel
    // stops saying it is looking either way, so it does not look stuck.
    onExited: root.fetching = false
  }

  readonly property Timer watch: Timer {
    interval: root.interval
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshBar()
  }

  Component {
    id: forecastPanel

    Item {
      id: card

      readonly property var days: root.forecast && root.forecast.days ? root.forecast.days : []

      // Asked for as the panel is built, rather than by the click that usually
      // opens it. Opening by hotkey goes straight to PanelHost and never touches
      // this handler, so a forecast fetched there was only ever fetched for the
      // one way in that people use less. It costs nothing: a panel only exists
      // while it is open, and the half-hourly timer stays the bar's only
      // background work.
      Component.onCompleted: root.refreshForecast()

      implicitWidth: Style.space(320)
      implicitHeight: panel.implicitHeight

      Panel {
        id: panel
        anchors.fill: parent
        maxWidth: Style.space(320)

        PanelHero {
          width: panel.contentWidth
          glyph: Util.sun
          title: root.forecast && root.forecast.area ? root.forecast.area : "Weather"
          subtitle: root.forecast && root.forecast.current
            ? root.forecast.current.temp + "°C · " + root.forecast.current.desc
            : ""
        }

        PanelSeparator {
          // Only between the hero and a forecast. A rule with nothing under it is
          // a divider for a section that is not there.
          visible: card.days.length > 0
        }

        Text {
          width: panel.contentWidth
          visible: !card.days.length
          height: implicitHeight
          // A request in flight and a request that failed are not the same, and
          // saying "unavailable" while one is still running is the panel telling
          // you something it does not yet know.
          text: root.fetching ? "Fetching…" : "Forecast unavailable"
          color: Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          renderType: Text.NativeRendering
        }

        Repeater {
          model: card.days

          delegate: PanelRow {
            id: day
            required property var modelData

            width: panel.contentWidth
            label: root.dayName(day.modelData.date)
            value: day.modelData.lo + "° / " + day.modelData.hi + "°  "
                   + (day.modelData.desc || "").trim()
          }
        }
      }
    }
  }
}