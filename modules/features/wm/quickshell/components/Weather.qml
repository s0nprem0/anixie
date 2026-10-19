import QtQuick
import ".."
import "../Ui"
import Quickshell
import Quickshell.Io

// Weather: the current temperature in the bar, and a three-day forecast behind a
// click.
//
// The reading comes from the same wttr.in geolocation the old bar module used, so
// there is still nothing to configure. What changes is where the data goes: the
// bar half asks wttr.in for the three values it draws, and the forecast half asks
// for the full document and trims it, rather than one script printing both.
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
  Component.onCompleted: PanelRegistry.register("weather", readout, forecastPanel)

  readonly property int interval: Number(root.setting("interval", 1800)) * 1000

  property string temperature: ""
  property string conditions: ""

  // The forecast, held as the parsed object once a request lands.
  property var forecast: null

  // Which of the two requests a running process is for, so a bar refresh and a
  // panel open do not overwrite each other's result with the wrong shape.
  property string pending: ""

  function refreshBar() {
    root.pending = "bar"
    barQuery.running = false
    barQuery.running = true
  }

  function refreshForecast() {
    root.pending = "forecast"
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
  visible: root.temperature !== ""

  BarIconButton {
    id: readout
    anchors.centerIn: parent
    text: root.temperature
    labelText: ""
    tooltipText: root.conditions !== ""
      ? root.conditions + " · click for the forecast"
      : "Weather · click for the forecast"

    onPressed: function (button) {
      if (button === Qt.LeftButton || button === Qt.MiddleButton) {
        // Asked for here rather than on a timer, so opening the panel shows
        // something and the half-hourly refresh stays the bar's only background
        // work.
        root.refreshForecast()
        PanelHost.toggle(readout, forecastPanel)
      }
    }
  }

  Process {
    id: barQuery
    command: ["sh", Quickshell.env("HOME") + "/.config/quickshell/scripts/weather-forecast.sh", "bar"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: {
        if (root.pending === "bar") root.applyBar(this.text)
      }
    }
  }

  Process {
    id: forecastQuery
    command: ["sh", Quickshell.env("HOME") + "/.config/quickshell/scripts/weather-forecast.sh", "forecast"]
    stdout: StdioCollector {
      onStreamFinished: {
        if (root.pending === "forecast") root.applyForecast(this.text)
      }
    }
  }

  readonly property Timer watch: Timer {
    interval: root.interval
    running: true
    repeat: true
    onTriggered: root.refreshBar()
  }

  Component {
    id: forecastPanel

    Item {
      id: card

      readonly property var days: root.forecast && root.forecast.days ? root.forecast.days : []

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

        PanelSeparator {}

        Text {
          width: panel.contentWidth
          visible: !root.forecast
          height: visible ? implicitHeight : 0
          text: "Forecast unavailable"
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