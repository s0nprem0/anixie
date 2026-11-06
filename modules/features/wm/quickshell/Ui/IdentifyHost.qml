pragma Singleton

pragma ComponentBehavior: Bound
import QtQuick

// Flashes every output's name on that output.
//
// The Displays panel can say "HDMI-A-1" all it likes, but with two black
// rectangles on the desk the row and the screen still have to be matched. This
// is the state behind a short overlay per output; `monitors identify` reaches it
// through the shell's IPC, and the panel's Identify action calls that command.
QtObject {
  id: root

  property bool opened: false
  property int duration: 3000

  // Friendly per-output label ("make model"), keyed by output name and
  // supplied by `monitors identify` alongside the duration. Empty when the
  // caller gave none, in which case only the output name is shown.
  property var descriptions: ({})

  function descriptionFor(name) {
    const key = String(name || "")
    return (root.descriptions && root.descriptions[key]) ? String(root.descriptions[key]) : ""
  }

  function parseDuration(raw) {
    if (raw === undefined || raw === null) return null
    const s = String(raw).trim()
    if (s === "") return null
    if (!/^[+-]?\d+$/.test(s)) return null
    const n = Number(s)
    return Number.isFinite(n) ? n : null
  }

  function flash(rawDuration, rawPayload) {
    const parsed = root.parseDuration(rawDuration)
    root.duration = parsed === null ? 3000 : Math.max(500, Math.min(10000, parsed))

    root.descriptions = ({})
    if (rawPayload !== undefined && rawPayload !== null && String(rawPayload).trim() !== "") {
      try {
        const data = JSON.parse(String(rawPayload))
        if (data && typeof data === "object" && !Array.isArray(data)) {
          root.descriptions = data
        }
      } catch (e) {
        console.warn("identify: could not parse descriptions: " + e)
      }
    }

    root.opened = true
    // Restart even when it is already up: a second press should extend the
    // time, not leave the first countdown to hide it.
    timer.restart()
  }

  property Timer timer: Timer {
    interval: root.duration
    onTriggered: root.opened = false
  }
}
