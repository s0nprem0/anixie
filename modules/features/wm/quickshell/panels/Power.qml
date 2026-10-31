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

  // One set of numbers for the bar's colour, the warning and the automation.
  readonly property int lowThreshold: @LOW_THRESHOLD@
  readonly property int criticalThreshold: @CRITICAL_THRESHOLD@

  // Friendly names for the daemon's profile identifiers.
  readonly property var profiles: ["power-saver", "balanced", "performance"]
  readonly property var profileChoices: [
    { label: "Quiet", value: "power-saver" },
    { label: "Balanced", value: "balanced" },
    { label: "Performance", value: "performance" }
  ]

  function profileLabel(value) {
    for (let i = 0; i < root.profileChoices.length; i++) {
      if (root.profileChoices[i].value === value) return root.profileChoices[i].label
    }
    return value
  }

  // The build option is the default; toggling writes the state file the watcher
  // reads, so the choice survives a rebuild.
  property bool automation: @AUTOMATION_DEFAULT@
  property bool automationBusy: false

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

  property string profile: ""

  // power-profiles-daemon may simply not be running, in which case no profile
  // is selected and nothing on screen would explain why.
  property bool profileFailed: false
  property string pendingProfile: ""

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
    onExited: function (exitCode) {
      if (exitCode === 0 && root.pendingProfile !== "") {
        OsdHost.show("power-profile", "Power profile: " + root.pendingProfile, "", "", "", 1500)
      }
      root.pendingProfile = ""
    }
  }

  function setProfile(name) {
    root.pendingProfile = String(name || "")
    profileSet.command = ["powerprofilesctl", "set", name]
    profileSet.running = true
  }

  Process {
    id: automationGet
    running: true
    command: ["@POWERPROFILE@", "automation"]
    stdout: StdioCollector {
      onStreamFinished: {
        const value = String(this.text).trim()
        if (value === "on" || value === "off") root.automation = value === "on"
      }
    }
  }

  Process {
    id: automationSet
    running: false
    onExited: function (exitCode) {
      root.automationBusy = false
      // The write also re-applies the profile for the current source, so ask
      // both readers again instead of guessing what the daemon ended up with.
      automationGet.running = false
      automationGet.running = true
      profileGet.running = false
      profileGet.running = true
    }
  }

  function setAutomation(enabled) {
    root.automationBusy = true
    automationSet.command = ["@POWERPROFILE@", "set-automation", enabled ? "on" : "off"]
    automationSet.running = true
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

  // The watcher applies the low/critical profile while discharging. The note
  // under the chips says which one it is holding the machine on.
  readonly property string automatedProfile: root.capacity <= root.criticalThreshold
    ? "@CRITICAL_PROFILE@"
    : "@LOW_PROFILE@"

  readonly property bool automated: root.automation && root.present && !root.onMains
    && root.capacity >= 0 && root.capacity <= root.lowThreshold

  readonly property string levelGlyph: {
    if (!root.present) return Util.bolt
    if (root.capacity <= 10) return Util.batteryEmpty
    if (root.capacity <= 30) return Util.batteryQuarter
    if (root.capacity <= 55) return Util.batteryHalf
    if (root.capacity <= 80) return Util.batteryThreeQuarters
    return Util.batteryFull
  }

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

  readonly property bool hasTime: root.present && root.secondsRemaining > 0

  readonly property string timeLabel: root.charging ? "Time to full" : "Time remaining"

  readonly property string timeValue: {
    if (root.secondsRemaining <= 0) return "—"

    const total = Math.round(root.secondsRemaining / 60)
    const h = Math.floor(total / 60)
    const m = total % 60
    return (h > 0 ? h + "h " : "") + m + "m"
  }

  function watts(value) {
    const magnitude = Math.abs(value)
    // "—" is for a missing battery, not for a full one: 0 W on mains is the
    // answer, and hiding it made the row look broken.
    return magnitude >= 0.05 ? magnitude.toFixed(1).replace(/\.0$/, "") + "W" : "0W"
  }

  readonly property string draw: root.present ? root.watts(root.battery.changeRate) : "—"

  readonly property string size: root.present && root.battery.energyCapacity > 0
    ? root.battery.energyCapacity.toFixed(1).replace(/\.0$/, "") + "Wh"
    : "—"

  // UPower reports health as a fraction and not every battery supports it, so
  // fall back to the two sysfs capacities. One decimal, because health moves by
  // tenths and the rounded integer hid that.
  readonly property real healthPercent: {
    if (!root.present) return -1
    if (root.battery.healthSupported) return root.battery.healthPercentage * 100
    if (root.energyFull > 0 && root.energyFullDesign > 0)
      return root.energyFull * 100 / root.energyFullDesign
    return -1
  }

  readonly property string health: root.healthPercent > 0
    ? root.healthPercent.toFixed(1).replace(/\.0$/, "")
    : "—"

  // Cycle count is the one reading UPower does not carry, so it comes from the
  // battery's own directory — named by UPower rather than assumed to be BAT0.
  readonly property string batteryDir: root.battery !== null && root.battery.nativePath !== ""
    ? "/sys/class/power_supply/" + root.battery.nativePath
    : ""

  readonly property string cyclePath: root.batteryDir + "/cycle_count"

  property int cycles: -1
  property int energyFull: -1
  property int energyFullDesign: -1

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
    id: energyFullView
    path: root.batteryDir + "/energy_full"
    printErrors: false
    blockLoading: true

    onLoaded: root.energyFull = root.readNum(energyFullView, -1)
  }

  FileView {
    id: energyFullDesignView
    path: root.batteryDir + "/energy_full_design"
    printErrors: false
    blockLoading: true

    onLoaded: root.energyFullDesign = root.readNum(energyFullDesignView, -1)
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

  // ---- the system ----
  //
  // What the panel is running on. Omarchy prints this too, and it earns its place
  // here: the panel is already where you look when the machine feels slow, and
  // "which kernel is this, how much memory is there" is the first question.
  property string kernel: ""
  property string cpu: ""
  property string memory: ""

  Process {
    id: sysinfo
    command: ["sh", "-c",
      "uname -r; awk -F': ' '/model name/{print $2; exit}' /proc/cpuinfo; "
      + "awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf \"%.1f / %.1f GB\", (t-a)/1048576, t/1048576}' /proc/meminfo"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = String(this.text).trim().split("\n")
        root.kernel = lines[0] || ""
        root.cpu = lines[1] || ""
        root.memory = lines[2] || ""
      }
    }
  }

  implicitWidth: Style.space(320)
  implicitHeight: card.implicitHeight

  Panel {
    id: card
    anchors.fill: parent

    // ---- the hero ----
    //
    // What this laptop is doing, stated before anything is set: charging, on
    // mains, running down. A panel about power that opens with a list of things
    // you can change, and no sentence saying where you currently are, makes you
    // read the whole thing to find the number you came for.
    PanelHero {
      width: card.contentWidth
      glyph: root.charging ? Util.charging : root.levelGlyph
      title: "Power"
      subtitle: root.present ? root.stateLabel : ""
    }

    PanelSeparator {}

    Toggle {
      width: card.contentWidth
      visible: root.present
      label: "Battery automation"
      description: "Dim and step the profile down at "
        + root.lowThreshold + "% and " + root.criticalThreshold + "%"
      checked: root.automation
      busy: root.automationBusy
      onToggled: root.setAutomation(!root.automation)
    }

    PanelSeparator {
      visible: root.present
    }

    // ---- profile ----
    // The profile query starts itself: `profileGet` is declared with
    // `running: true`, and PanelHost rebuilds this panel every time it opens, so
    // each opening asks again. There used to be a `profileGet.running = false`
    // here, which stopped the query the moment the card was built — the kill
    // came back as a non-zero exit, and the panel announced a daemon that was
    // running fine as unavailable.

    PanelSectionHeader {
      width: card.contentWidth
      label: "Performance profile"
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
      renderType: Text.NativeRendering
    }

    SegmentedControl {
      width: card.contentWidth
      model: root.profileChoices
      currentIndex: root.profiles.indexOf(root.profile)
      available: !root.profileFailed
      onActivated: function (index) { root.setProfile(root.profiles[index]) }
    }

    Text {
      width: card.contentWidth
      height: implicitHeight
      visible: root.automated
      text: "Battery automation is active: "
        + root.profileLabel(root.automatedProfile) + " at " + root.capacity + "%"
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
      renderType: Text.NativeRendering
    }

    // ---- brightness ----
    SliderField {
      width: card.contentWidth
      label: "Brightness"
      value: root.brightness + "%"
      from: 0
      to: 100
      stepSize: 1
      level: root.brightness
      available: root.brightnessMax > 0
      onMoved: function (value) { root.setBrightness(value) }
    }

    // ---- battery ----
    PanelSeparator {
      visible: root.present
    }

    PanelSectionHeader {
      width: card.contentWidth
      visible: root.present
      label: "Battery"
    }

    PanelRow {
      id: chargeRow
      width: card.contentWidth
      visible: root.present
      // The state itself is the hero's line — charging, on mains, on battery —
      // so this row is only the number that goes with it.
      label: "Charge"
      value: root.capacity + "%"
    }

    PanelRow {
      id: timeRow
      width: card.contentWidth
      visible: root.hasTime
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
      visible: root.present && root.health !== "—"
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

    PanelSeparator {}

    PanelSectionHeader {
      width: card.contentWidth
      label: "System"
    }

    PanelRow {
      width: card.contentWidth
      label: "Kernel"
      value: root.kernel
    }

    PanelRow {
      width: card.contentWidth
      label: "Processor"
      value: root.cpu
    }

    PanelRow {
      width: card.contentWidth
      label: "Memory"
      value: root.memory
    }
  }
}