import QtQuick
import ".."
import "../Ui"
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

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

  // sysfs reads go through FileView, whose text() throws until the first read
  // lands, so every access is funnelled through here. Only the battery's cycle
  // count is still read this way; the rest comes from UPower.
  function readNum(view, fallback) {
    try {
      const value = parseInt(String(view.text()).trim(), 10)
      return isNaN(value) ? fallback : value
    } catch (e) {
      return fallback
    }
  }

  // ---- performance profile ----

  readonly property var profiles: ["power-saver", "balanced", "performance"]
  property string profile: ""

  // power-profiles-daemon may simply not be running, in which case no profile
  // is selected and nothing on screen would explain why.
  property bool profileFailed: false

  // What powerprofilesctl said when it failed, for the message below.
  property string profileError: ""

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
      // Kept for the message only. The exit code is what decides whether this
      // failed — setting the flag here marked the daemon unavailable on every
      // *successful* run, because a collector finishes when its stream closes
      // whether or not anything came through it, and an empty stderr closes too.
      // Whichever collector finished last decided the outcome, so the panel
      // reported a daemon that was running perfectly well as missing.
      onStreamFinished: root.profileError = this.text.trim()
    }
    onExited: function (exitCode) {
      root.profileFailed = exitCode !== 0
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

  // UPower carries the whole readout: percentage, state, both time estimates,
  // rate, capacity and health. It beats the sysfs files this used to watch,
  // which reported kernel micro-units needing scaling, could not tell "on mains
  // but holding" from "on battery", and whose watchers could deliver a value in
  // the wrong order and leave a binding stuck on it.
  readonly property var battery: UPower.displayDevice
  readonly property bool present: root.battery !== null && root.battery.ready && root.battery.isPresent

  // `percentage` and `healthPercentage` both arrive as fractions, so both are
  // scaled: Math.round(0.4) is 0, which is how a healthy battery came to read
  // 0% in the panel and on the bar.
  readonly property int capacity: root.present ? Math.round(root.battery.percentage * 100) : -1
  readonly property bool charging: root.present && root.battery.state === UPowerDeviceState.Charging
  readonly property bool full: root.present && root.battery.state === UPowerDeviceState.FullyCharged

  // Derived from the charge state rather than read from UPower's `onBattery`:
  // that one stays false on this machine even with a battery fitted, so
  // inverting it would report "On mains" whatever was actually happening.
  readonly property bool onMains: root.present && (
    root.battery.state === UPowerDeviceState.Charging
    || root.battery.state === UPowerDeviceState.FullyCharged
    || root.battery.state === UPowerDeviceState.PendingCharge)

  readonly property string stateLabel: {
    if (!root.present) return "No battery"
    if (root.charging) return "Charging"
    if (root.full) return "Full"
    if (root.onMains) return "On mains"
    return "On battery"
  }

  // Both estimates arrive in seconds and UPower decides which is meaningful:
  // timeToEmpty is -1 while charging, timeToFull is -1 while discharging.
  readonly property double secondsRemaining: {
    if (!root.present) return -1
    return root.charging ? root.battery.timeToFull : root.battery.timeToEmpty
  }

  readonly property string timeLabel: {
    if (root.charging) return "Time to full"
    if (root.full) return "Fully charged"
    return "Time remaining"
  }

  readonly property string timeValue: {
    if (root.secondsRemaining <= 0) return "—"

    const total = Math.round(root.secondsRemaining / 60)
    const h = Math.floor(total / 60)
    const m = total % 60
    return (h > 0 ? h + "h " : "") + m + "m"
  }

  function watts(value) {
    const magnitude = Math.abs(value)
    return magnitude > 0 ? magnitude.toFixed(1).replace(/\.0$/, "") + "W" : "—"
  }

  readonly property string draw: root.present ? root.watts(root.battery.changeRate) : "—"

  readonly property string size: root.present && root.battery.energyCapacity > 0
    ? root.battery.energyCapacity.toFixed(1).replace(/\.0$/, "") + "Wh"
    : "—"

  readonly property int health: root.present && root.battery.healthSupported
    ? Math.round(root.battery.healthPercentage * 100)
    : -1

  // Cycle count is the one reading UPower does not carry, so it comes from the
  // battery's own directory — named by UPower rather than assumed to be BAT0.
  readonly property string cyclePath: root.battery !== null && root.battery.nativePath !== ""
    ? "/sys/class/power_supply/" + root.battery.nativePath + "/cycle_count"
    : ""

  property int cycles: -1

  // The one battery reading UPower does not carry. Static, so it is read once
  // when the file loads rather than watched, and assigned from the load signal
  // rather than bound — a binding read before the file lands would stick.
  FileView {
    id: cycleView
    path: root.cyclePath
    printErrors: false
    blockLoading: true

    onLoaded: root.cycles = root.readNum(cycleView, -1)
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
    // The profile query starts itself: `profileGet` is declared with
    // `running: true`, and PanelHost rebuilds this panel every time it opens, so
    // each opening asks again. There used to be a `profileGet.running = false`
    // here, which stopped the query the moment the card was built — the kill
    // came back as a non-zero exit, and the panel announced a daemon that was
    // running fine as unavailable.

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
      // powerprofilesctl's own explanation when it gave one, so a failure that
      // says why is not replaced by a line that says only that it failed.
      text: root.profileError !== "" ? root.profileError : "power-profiles-daemon unavailable"
      color: Theme.danger
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
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
      hasControl: true
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
      label: root.stateLabel
      value: root.present ? root.capacity + "%" : "—"
    }

    PanelRow {
      id: timeRow
      width: card.contentWidth
      visible: root.present
      label: root.timeLabel
      value: root.timeValue
    }

    PanelRow {
      id: drawRow
      width: card.contentWidth
      visible: root.present
      label: root.charging ? "Charging at" : "Drawing"
      value: root.draw
    }

    PanelRow {
      id: sizeRow
      width: card.contentWidth
      visible: root.present && root.size !== "—"
      label: "Capacity"
      value: root.size
    }

    PanelRow {
      id: healthRow
      width: card.contentWidth
      visible: root.present && root.health > 0
      label: "Full charge health"
      value: root.health + "%"
    }

    PanelRow {
      id: cycleRow
      width: card.contentWidth
      visible: root.present && root.cycles >= 0
      label: "Charge cycles"
      value: root.cycles >= 0 ? String(root.cycles) : "—"
    }
  }
}