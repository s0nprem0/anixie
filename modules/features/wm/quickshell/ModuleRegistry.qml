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

  readonly property var registry: ({
    "bar.workspaces": workspaces,
    "bar.clock": clock,
    "bar.audio": audio,
    "bar.power": power,
    "bar.wifi": wifi,
    "bar.microphone": microphone,
    "bar.active-window": activeWindow,
    "bar.media": media
  })

  function has(id) {
    return registry[id] !== undefined
  }
}