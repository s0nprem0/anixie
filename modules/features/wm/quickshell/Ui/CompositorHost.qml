pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Which compositor the shell is running under, and what it can do.
//
// The shell grew up on Hyprland, so every feature that talks to the
// compositor assumes its IPC. This host is the seam: it detects the running
// compositor once at startup and exposes capability flags, so a feature can
// ask "can I do this here?" instead of guessing from a socket that may not
// exist. Nothing here changes behaviour yet; it is the awareness layer the
// later adapters build on.
QtObject {
  id: root

  readonly property string name: {
    if (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") !== "") return "hyprland"
    if (Quickshell.env("NIRI_SOCKET") !== "") return "niri"
    if (Quickshell.env("MANGO_SOCKET") !== "" || Quickshell.env("MANGOWC_SOCKET") !== "") return "mango"
    return "unknown"
  }

  readonly property bool isHyprland: root.name === "hyprland"
  readonly property bool isNiri: root.name === "niri"
  readonly property bool isMango: root.name === "mango"

  // Capability flags. Only Hyprland is wired today; the others stay false
  // until their adapters land, so features degrade gracefully rather than
  // calling into an IPC that does not exist.
  readonly property bool supportsWorkspaceOverview: root.isHyprland
  readonly property bool supportsNightLightBackend: root.isHyprland || root.isNiri || root.isMango
  readonly property bool supportsMonitorColorMgmt: root.isHyprland
  readonly property bool supportsDock: true
  readonly property bool supportsBar: true
}
