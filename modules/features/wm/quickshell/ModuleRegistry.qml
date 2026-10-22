pragma Singleton

import QtQuick
import "components"

// Maps the ids used in bar.json to the QML that draws them. A layout entry of
// `"type": "command"` skips this map and is drawn by CommandModule instead.
QtObject {
  readonly property Component workspaces: Component { Workspaces {} }
  readonly property Component clock: Component { Clock {} }
  readonly property Component audio: Component { Volume {} }
  readonly property Component power: Component { Battery {} }
  readonly property Component wifi: Component { Wifi {} }
  readonly property Component microphone: Component { Microphone {} }
  readonly property Component activeWindow: Component { ActiveWindow {} }
  readonly property Component media: Component { Media {} }
  readonly property Component spacer: Component { Spacer {} }
  readonly property Component menu: Component { Menu {} }
  readonly property Component bluetooth: Component { Bluetooth {} }
  readonly property Component indicators: Component { Indicators {} }
  readonly property Component tray: Component { Tray {} }
  readonly property Component monitor: Component { Monitor {} }
  readonly property Component bell: Component { Bell {} }
  readonly property Component passwordlessSudo: Component { PasswordlessSudo {} }
  readonly property Component remoteSession: Component { RemoteSession {} }
  readonly property Component weather: Component { Weather {} }
  readonly property Component worldClock: Component { WorldClock {} }
  readonly property Component updateBadge: Component { UpdateBadge {} }
  readonly property Component keyboardLayout: Component { KeyboardLayout {} }
  readonly property Component agents: Component { Agents {} }
  readonly property Component tailscale: Component { Tailscale {} }
  readonly property Component dropbox: Component { Dropbox {} }
  readonly property Component modelUsage: Component { ModelUsage {} }
  readonly property Component meet: Component { Meet {} }
  readonly property Component systemStats: Component { SystemStats {} }

  readonly property var registry: ({
    "bar.workspaces": workspaces,
    "bar.clock": clock,
    "bar.audio": audio,
    "bar.power": power,
    "bar.wifi": wifi,
    "bar.microphone": microphone,
    "bar.active-window": activeWindow,
    "bar.media": media,
    "bar.spacer": spacer,
    "bar.menu": menu,
    "bar.bluetooth": bluetooth,
    "bar.indicators": indicators,
    "bar.tray": tray,
    "bar.monitor": monitor,
    "bar.bell": bell,
    "bar.passwordless-sudo": passwordlessSudo,
    "bar.remote-session": remoteSession,
    "bar.weather": weather,
    "bar.world-clock": worldClock,
    "bar.update": updateBadge,
    "bar.keyboard-layout": keyboardLayout,
    "bar.agents": agents,
    "bar.tailscale": tailscale,
    "bar.dropbox": dropbox,
    "bar.model-usage": modelUsage,
    "bar.meet": meet,
    "bar.system-stats": systemStats
  })

  function has(id) {
    return registry[id] !== undefined
  }
}