import QtQuick
import ".."
import "../Ui"
import "../panels"

// A small clock on the bar that opens today's screen-time and focus panel.
//
// Always present rather than conditionally shown: it is the way into the panel
// that starts a focus block, so hiding it when the count is zero would make the
// control disappear exactly when it is wanted.
BarWidget {
  id: root

  Component.onCompleted: root.registerPanel("screentime", readout, panel)

  readonly property int active: ScreentimeStore.activeSeconds
  readonly property string label: ScreentimeStore.formatDuration(root.active)

  wantsSlot: true
  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  Component {
    id: panel
    Screentime {}
  }

  BarIconButton {
    id: readout
    anchors.centerIn: parent
    text: Util.clock
    labelText: !root.vertical && root.active >= 60 ? root.label : ""
    active: FocusHost.active
    foreground: FocusHost.active ? Theme.accent : Theme.fg
    tooltipText: "Screen time " + root.label + (FocusHost.active ? " · focus " + FocusHost.remainingLabel + " left" : "")
      + " · click for details"

    onPressed: function () {
      PanelRegistry.toggle("screentime", readout)
    }
  }
}
