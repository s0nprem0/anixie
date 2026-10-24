import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../Ui"

// Model usage: what the local coding agents have spent recently.
//
// The numbers come from `scripts/model-usage.sh`, which reads opencode's own
// stats command and Claude's local session logs. There is no account API here:
// the bar can only report what the tools wrote down on this machine, so it hides
// when both of them have nothing to say.
BarWidget {
  id: root

  Component.onCompleted: root.registerPanel("model-usage", readout, panel)

  readonly property int days: Math.max(1, Number(root.setting("days", 1)))
  readonly property int intervalMs: Math.max(30000, Number(root.setting("interval", 300)) * 1000)

  property var data: null
  property string lastError: ""

  readonly property var opencode: root.data ? root.data.opencode : null
  readonly property var claude: root.data ? root.data.claude : null

  readonly property bool hasData: {
    const oc = root.opencode
    const cl = root.claude
    const ocUsed = oc && (Number(oc.cost) > 0
      || String(oc.input) !== "0"
      || String(oc.output) !== "0"
      || String(oc.cache) !== "0")
    const clUsed = cl && (Number(cl.input) > 0 || Number(cl.output) > 0 || Number(cl.cache) > 0)
    return !!(ocUsed || clUsed)
  }

  readonly property string barLabel: {
    if (!root.data) return ""
    if (root.opencode && Number(root.opencode.cost) > 0) return "$" + root.opencode.cost
    if (root.opencode && String(root.opencode.input) !== "0") return String(root.opencode.input)
    if (root.claude) {
      const total = Number(root.claude.input) + Number(root.claude.output)
      return root.formatCount(total > 0 ? total : Number(root.claude.cache))
    }
    return ""
  }

  function formatCount(value) {
    const number = Number(value)
    if (!isFinite(number)) return String(value)
    if (number >= 1000000) return (number / 1000000).toFixed(1).replace(/\.0$/, "") + "M"
    if (number >= 1000) return (number / 1000).toFixed(1).replace(/\.0$/, "") + "K"
    return String(number)
  }

  function refresh() {
    if (stats.running) return
    stats.running = true
  }

  function apply(raw) {
    try {
      const parsed = JSON.parse(String(raw || "{}"))
      root.data = parsed && parsed.opencode && parsed.claude ? parsed : null
      root.lastError = ""
    } catch (e) {
      root.data = null
      root.lastError = String(e)
    }
  }

  wantsSlot: root.hasData
  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  Process {
    id: stats
    running: true
    command: ["sh", Quickshell.env("HOME") + "/.config/quickshell/scripts/model-usage.sh", String(root.days)]

    stdout: StdioCollector {
      onStreamFinished: root.apply(this.text)
    }
    onExited: {
      if (root.data === null && root.lastError === "") root.lastError = "No usage data"
    }
  }

  Timer {
    interval: root.intervalMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: readout
    anchors.centerIn: parent
    text: root.barLabel
    fontSize: Style.font.body
    centerFigures: false
    tooltipText: "Model usage · click for details"

    onPressed: function (button) {
      if (button === Qt.LeftButton || button === Qt.MiddleButton) PanelRegistry.toggle("model-usage", readout)
      else if (button === Qt.RightButton) root.refresh()
    }
  }

  Component {
    id: panel

    Panel {
      id: card
      title: ""

      PanelHero {
        width: card.contentWidth
        glyph: Util.chart
        title: "Model usage"
        subtitle: "Last " + root.days + (root.days === 1 ? " day" : " days") + " · local logs"
      }

      PanelSeparator {}

      PanelSectionHeader {
        width: card.contentWidth
        label: "opencode"
      }

      PanelRow {
        width: card.contentWidth
        label: "Cost"
        value: root.opencode && Number(root.opencode.cost) > 0
          ? "$" + root.opencode.cost
          : "—"
      }

      PanelRow {
        width: card.contentWidth
        label: "Sessions"
        value: root.opencode ? String(root.opencode.sessions) : "0"
      }

      PanelRow {
        width: card.contentWidth
        label: "Input · output"
        value: root.opencode
          ? root.opencode.input + " · " + root.opencode.output
          : "—"
      }

      PanelRow {
        width: card.contentWidth
        label: "Cache read"
        value: root.opencode && String(root.opencode.cache) !== ""
          ? String(root.opencode.cache)
          : "—"
      }

      PanelRow {
        width: card.contentWidth
        label: "Top model"
        value: root.opencode && String(root.opencode.model) !== ""
          ? String(root.opencode.model)
          : "—"
      }

      PanelSeparator {}

      PanelSectionHeader {
        width: card.contentWidth
        label: "Claude"
      }

      PanelRow {
        width: card.contentWidth
        label: "Sessions"
        value: root.claude ? String(root.claude.sessions) : "0"
      }

      PanelRow {
        width: card.contentWidth
        label: "Input · output"
        value: root.claude
          ? root.formatCount(root.claude.input) + " · " + root.formatCount(root.claude.output)
          : "—"
      }

      PanelRow {
        width: card.contentWidth
        label: "Cache"
        value: root.claude ? root.formatCount(root.claude.cache) : "—"
      }

      Text {
        width: card.contentWidth
        height: implicitHeight
        visible: !root.hasData
        text: root.lastError !== ""
          ? root.lastError
          : "No usage recorded for the selected window."
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
        renderType: Text.NativeRendering
      }

      PanelActionButton {
        width: card.contentWidth
        label: "Refresh now"
        navigational: false
        onClicked: root.refresh()
      }
    }
  }
}
