import QtQuick
import QtQuick.Controls
import ".."
import "../Ui"
import Quickshell
import Quickshell.Io

// Wi-Fi panel: what is nearby, which one is in use, and a way to switch.
//
// nmcli is the only network manager here, so this is shell-driven rather than
// backed by a native module the way audio and power are.
Item {
  id: root

  property var wifiDevice: ""
  property var networks: []
  property string activeSsid: ""
  property bool scanning: false

  // nmcli exiting non-zero is not the same as there being no networks, and the
  // panel says which it is rather than showing an empty list either way.
  property bool failed: false
  property string failure: ""

  // A scan reports networks the device has not seen yet; connecting to a hidden
  // network is out of scope, so only listed ones are offered.
  function parse(raw) {
    const found = []

    for (let i = 0; i < raw.split("\n").length; i++) {
      const row = raw.split("\n")[i]
      if (row === "") continue

      const parts = row.split(":")

      // IN-USE,SSID,SIGNAL,SECURITY. The SSID is whatever sits between the
      // first and the last two fields, rejoined, because nmcli escapes a colon
      // inside an SSID as "\:" and a naive split would tear it in half.
      if (parts.length < 4) continue

      const inUse = parts[0] === "*"
      const ssid = decodeSsid(parts.slice(1, parts.length - 2).join(":"))
      if (ssid === "") continue

      found.push({
        ssid: ssid,
        signal: parseInt(parts[parts.length - 2], 10) || 0,
        security: decodeSsid(parts[parts.length - 1]),
        inUse: inUse
      })
    }

    // Strongest first, with the network in use pinned to the top.
    found.sort(function (a, b) {
      if (a.inUse !== b.inUse) return a.inUse ? -1 : 1
      return b.signal - a.signal
    })

    return found
  }

  function decodeSsid(value) {
    return String(value).replace(/\\(.)/g, "$1")
  }

  // ---- commands ----

Process {
    id: listProc
    running: true
    command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list"]
    stdout: StdioCollector {
      onStreamFinished: {
        const found = root.parse(this.text)
        root.networks = found
        root.activeSsid = found.length && found[0].inUse ? found[0].ssid : ""
        root.scanning = false

        if (found.length > 0) {
          root.failed = false
          root.failure = ""
        }

        // The process that starts as part of building the shell can come back
        // with its output already dropped, which reads as "no networks". Ask
        // again rather than showing an empty list.
        if (found.length === 0 && root.emptyRetries < 3) {
          root.emptyRetries += 1
          emptyRetry.restart()
        }
      }
    }

    stderr: StdioCollector {
      onStreamFinished: root.failure = this.text.trim()
    }

    onExited: function (exitCode) {
      if (exitCode !== 0) {
        root.failed = true
        if (root.failure === "") root.failure = "nmcli exited with " + exitCode
      }
    }
  }

  property int emptyRetries: 0

  Timer {
    id: emptyRetry
    interval: 700
    onTriggered: root.refresh()
  }

  Process {
    id: scanProc
    running: false
  }

  Process {
    id: actionProc
    running: false
    stdout: StdioCollector {
      // Whether it worked shows up in the list a moment later; re-read now so
      // the panel settles quickly either way.
      onStreamFinished: {
        listProc.running = false
        listProc.running = true
      }
    }
  }

  Process {
    id: deviceProc
    running: true
    command: ["nmcli", "-t", "-f", "DEVICE,TYPE", "device", "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        const rows = this.text.split("\n")
        for (let i = 0; i < rows.length; i++) {
          const parts = rows[i].split(":")
          if (parts[1] === "wifi") root.wifiDevice = parts[0]
        }
      }
    }
  }

  function refresh() {
    listProc.running = false
    listProc.running = true
  }

  function rescan() {
    root.scanning = true
    scanProc.command = ["nmcli", "device", "wifi", "rescan"]
    scanProc.running = true

    // A rescan takes a moment to report; poll a little harder while it runs.
    settle.restart()
  }

  function connect(ssid) {
    actionProc.command = ["nmcli", "device", "wifi", "connect", ssid]
    actionProc.running = true
    settle.restart()
  }

  function disconnect() {
    actionProc.command = ["nmcli", "device", "disconnect", root.wifiDevice]
    actionProc.running = true
    settle.restart()
  }

  Timer {
    id: settle
    interval: 900
    repeat: true
    running: root.scanning
    onTriggered: root.refresh()
  }

  Timer {
    interval: 10000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: {
    deviceProc.running = false
    deviceProc.running = true
    root.emptyRetries = 0
    root.failed = false
    root.refresh()
  }

  // Signal bars: four steps, filled by where the percentage lands.
  function signalLevel(percent) {
    if (percent >= 70) return 4
    if (percent >= 45) return 3
    if (percent >= 20) return 2
    return 1
  }

  readonly property int maxListHeight: Style.space(220)

  implicitWidth: Style.space(300)
  implicitHeight: card.implicitHeight

  Panel {
    id: card
    anchors.fill: parent
    title: "Wi-Fi"

    PanelRow {
      id: statusRow
      width: card.contentWidth
      // The status line doubles as the error surface: when nmcli is broken it
      // is the only place the reason can be read, since the list below is empty
      // for exactly the same reason either way.
      label: root.failed
        ? "Unavailable"
        : (root.activeSsid !== "" ? root.activeSsid : "Not connected")
      value: root.failed ? "" : root.networks.length + " found"
    }

    Text {
      width: card.contentWidth
      height: implicitHeight
      visible: root.failed && root.failure !== ""
      text: root.failure
      color: Theme.danger
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
      topPadding: Style.space(2)
    }

    Rectangle {
      id: disconnectButton
      width: card.contentWidth
      height: Style.space(24)
      radius: Theme.cornerRadius
      visible: root.activeSsid !== ""
      color: disconnectMouse.containsMouse ? Theme.danger : "transparent"
      border.color: Theme.danger
      border.width: 1

      Text {
        anchors.centerIn: parent
        text: "Disconnect"
        color: disconnectMouse.containsMouse ? Theme.bg : Theme.danger
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      MouseArea {
        id: disconnectMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.disconnect()
      }
    }

    ListView {
      id: list
      width: card.contentWidth
      height: Math.min(contentHeight, root.maxListHeight)
      clip: true
      model: root.networks
      spacing: Style.space(2)

      delegate: Rectangle {
        id: rowItem
        required property var modelData

        width: list.width
        height: Style.space(26)
        radius: Theme.cornerRadius
        color: rowMouse.containsMouse ? Theme.bg : "transparent"

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(6)
          anchors.right: signalBars.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          text: rowItem.modelData.ssid
          elide: Text.ElideMiddle
          color: rowItem.modelData.inUse ? Theme.primary : Theme.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          renderType: Text.NativeRendering
        }

        // Four ascending bars, the filled count set by the signal percentage.
        Row {
          id: signalBars
          anchors.right: parent.right
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          spacing: 2

          Repeater {
            model: 4
            delegate: Rectangle {
              required property int index
              width: 3
              height: 4 + index * 3
              radius: Theme.cornerRadius
              anchors.verticalCenter: parent.verticalCenter
              color: index < root.signalLevel(rowItem.modelData.signal)
                ? (rowItem.modelData.inUse ? Theme.primary : Theme.muted)
                : Theme.bg
            }
          }
        }

        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (rowItem.modelData.inUse) root.disconnect()
            else root.connect(rowItem.modelData.ssid)
          }
        }
      }

      ScrollBar.vertical: ScrollBar {}
    }

    Rectangle {
      width: card.contentWidth
      height: Style.space(24)
      radius: Theme.cornerRadius
      color: rescanMouse.containsMouse ? Theme.bg : "transparent"
      border.color: Theme.muted
      border.width: 1

      Text {
        anchors.centerIn: parent
        text: root.scanning ? "Scanning…" : "Scan for networks"
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      MouseArea {
        id: rescanMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.rescan()
      }
    }
  }
}