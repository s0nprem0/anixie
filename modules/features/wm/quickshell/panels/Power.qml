import QtQuick
import ".."
import "../Ui"
import Quickshell
import Quickshell.Io

// Power panel: performance profile, screen brightness, and battery detail.
//
// Reads come from sysfs through FileView, which watches the files, so nothing
// polls them. The two writes cannot go through sysfs — the backlight and the
// profile daemon are root-owned — so those go out as short-lived calls, and the
// value is re-read from the file afterwards rather than assumed.
//
// A panel only exists while it is open, so the handful of calls it makes on
// appearing cost nothing during normal use.
Item {
  id: root

  readonly property string backlight: "/sys/class/backlight/amdgpu_bl1"
  readonly property string battery: "/sys/class/power_supply/BAT0"

  // sysfs reads go through FileView, whose text() throws until the first read
  // lands, so every access is funnelled through these.
  function readNum(view, fallback) {
    try {
      const value = parseInt(String(view.text()).trim(), 10)
      return isNaN(value) ? fallback : value
    } catch (e) {
      return fallback
    }
  }

  function readText(view) {
    try {
      return String(view.text()).trim()
    } catch (e) {
      return ""
    }
  }

  // ---- performance profile ----

  readonly property var profiles: ["power-saver", "balanced", "performance"]
  property string profile: ""

  // power-profiles-daemon may simply not be running, in which case no profile
  // is selected and nothing on screen would explain why.
  property bool profileFailed: false

  Process {
    id: profileGet
    running: true
    command: ["powerprofilesctl", "get"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.profile = this.text.trim()
        root.profileFailed = false
      }
    }
    stderr: StdioCollector {
      onStreamFinished: root.profileFailed = true
    }
    onExited: function (exitCode) {
      if (exitCode !== 0) root.profileFailed = true
    }
  }

  Process {
    id: profileSet
    running: false
    stdout: StdioCollector {
      // powerprofilesctl is silent on success; on failure it prints why. Either
      // way, re-read rather than assume the write landed.
      onStreamFinished: {
        profileGet.running = false
        profileGet.running = true
      }
    }
  }

  function setProfile(name) {
    profileSet.command = ["powerprofilesctl", "set", name]
    profileSet.running = true
  }

  // ---- brightness ----

  readonly property int brightnessValue: root.readNum(brightnessView, 0)
  readonly property int brightnessMax: root.readNum(brightnessMaxView, 0)
  readonly property int brightness: root.brightnessMax > 0
    ? Math.round(root.brightnessValue * 100 / root.brightnessMax)
    : 0

  Process {
    id: brightnessSet
    running: false
  }

  function setBrightness(percent) {
    const target = Math.round(percent * root.brightnessMax / 100)
    brightnessSet.command = ["brightnessctl", "set", String(target)]
    brightnessSet.running = true
  }

  // ---- battery ----

  readonly property int capacity: root.readNum(capacityView, -1)
  readonly property string batteryStatus: root.readText(statusView)
  readonly property double energyNow: root.readNum(energyNowView, 0)
  readonly property double powerNow: root.readNum(powerNowView, 0)
  readonly property double energyFull: root.readNum(energyFullView, 0)
  readonly property double energyDesign: root.readNum(energyDesignView, 0)

  readonly property bool charging: batteryStatus === "Charging"
  readonly property bool present: capacity >= 0

  // energy_now and power_now share a unit, so the quotient is hours directly.
  readonly property double hoursLeft: powerNow > 0 ? energyNow / powerNow : -1

  readonly property string timeLeft: {
    if (hoursLeft < 0) return "—"
    const total = Math.round(hoursLeft * 60)
    const h = Math.floor(total / 60)
    const m = total % 60
    return (h > 0 ? h + "h " : "") + m + "m"
  }

  readonly property int health: energyDesign > 0
    ? Math.round(energyFull * 100 / energyDesign)
    : -1

  FileView {
    id: capacityView
    path: root.battery + "/capacity"
    printErrors: false
    watchChanges: true
    blockLoading: true
  }

  FileView {
    id: statusView
    path: root.battery + "/status"
    printErrors: false
    watchChanges: true
    blockLoading: true
  }

  FileView {
    id: energyNowView
    path: root.battery + "/energy_now"
    printErrors: false
    watchChanges: true
    blockLoading: true
  }

  FileView {
    id: powerNowView
    path: root.battery + "/power_now"
    printErrors: false
    watchChanges: true
    blockLoading: true
  }

  FileView {
    id: energyFullView
    path: root.battery + "/energy_full"
    printErrors: false
    watchChanges: true
    blockLoading: true
  }

  FileView {
    id: energyDesignView
    path: root.battery + "/energy_full_design"
    printErrors: false
    watchChanges: true
    blockLoading: true
  }

  FileView {
    id: brightnessView
    path: root.backlight + "/actual_brightness"
    printErrors: false
    watchChanges: true
    blockLoading: true
  }

  FileView {
    id: brightnessMaxView
    path: root.backlight + "/max_brightness"
    printErrors: false
    blockLoading: true
  }

  implicitWidth: Style.space(320)
  implicitHeight: card.implicitHeight

  Panel {
    id: card
    anchors.fill: parent
    title: "Power"

    // ---- profile ----
    Component.onCompleted: profileGet.running = false

    Text {
      width: card.contentWidth
      height: implicitHeight
      text: "PERFORMANCE PROFILE"
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.weight: Font.DemiBold
    }

    Text {
      width: card.contentWidth
      height: implicitHeight
      visible: root.profileFailed
      text: "power-profiles-daemon unavailable"
      color: Theme.danger
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Row {
      width: card.contentWidth
      spacing: Style.space(6)

      Repeater {
        model: root.profiles

        delegate: Rectangle {
          id: chip
          required property var modelData

          readonly property bool selected: root.profile === modelData

          width: profileLabel.implicitWidth + Style.space(16)
          height: Style.space(24)
          radius: height / 2
          color: selected ? Theme.primary : Theme.bg
          border.color: selected ? Theme.primary : Theme.muted
          border.width: 1

          Text {
            id: profileLabel
            anchors.centerIn: parent
            text: chip.modelData
            color: chip.selected ? Theme.bg : Theme.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            renderType: Text.NativeRendering
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.setProfile(chip.modelData)
          }
        }
      }
    }

    // ---- brightness ----
    PanelRow {
      id: brightnessRow
      width: card.contentWidth
      label: "Brightness"
      value: root.brightness + "%"

      Slider {
        id: brightnessSlider
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: brightnessRow.controlWidth
        from: 0
        to: 100
        stepSize: 1
        enabled: root.brightnessMax > 0
        value: root.brightness
        onMoved: root.setBrightness(value)
      }
    }

    // ---- battery ----
    Text {
      width: card.contentWidth
      height: implicitHeight
      visible: root.present
      text: "BATTERY"
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.weight: Font.DemiBold
      topPadding: Style.space(4)
    }

    PanelRow {
      id: chargeRow
      width: card.contentWidth
      visible: root.present
      label: root.charging ? "Charging" : "On battery"
      value: root.present ? root.capacity + "%" : "—"
    }

    PanelRow {
      id: timeRow
      width: card.contentWidth
      visible: root.present
      label: "Time remaining"
      value: root.timeLeft
    }

    PanelRow {
      id: healthRow
      width: card.contentWidth
      visible: root.present && root.health > 0
      label: "Full charge health"
      value: root.health + "%"
    }
  }
}