import QtQuick
import ".."

// The small label that introduces a panel section — "PERFORMANCE PROFILE",
// "BATTERY", "WI-FI NETWORKS". Sits under a PanelSeparator, above the rows it
// names, with an optional action at the end of it.
//
// Muted rather than a tint of the foreground: the panels already use muted for
// their section labels, and a heading is the one place a panel does *not* want
// the accent — accent is for what is live or chosen, and a heading is neither.
//
// An action belongs to the section it acts on. "Rescan" sat in a full-width row
// of its own at the bottom of the Wi-Fi panel, which read as a label rather than
// as a button and put the one control for the list a screenful away from the
// list.
Item {
  id: root

  property string label: ""

  property string action: ""
  property bool actionEnabled: true

  signal actionTriggered()

  readonly property bool panelFocusable: root.hasAction && root.actionEnabled

  function activate() {
    if (root.hasAction && root.actionEnabled) root.actionTriggered()
  }

  function keyStep(direction) {
    return false
  }

  readonly property bool hasAction: root.action !== ""
  readonly property real horizontalPadding: Style.space(2)

  implicitWidth: parent ? parent.width : Math.max(labelText.implicitWidth, actionHit.implicitWidth)
  implicitHeight: Math.max(labelText.implicitHeight, actionLabel.implicitHeight) + Style.space(2)
  height: implicitHeight
  clip: true

  Text {
    id: labelText
    anchors.left: parent.left
    anchors.leftMargin: root.horizontalPadding
    anchors.right: root.hasAction ? actionHit.left : parent.right
    anchors.rightMargin: root.hasAction ? Style.space(6) : root.horizontalPadding
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    textFormat: Text.PlainText
    color: Theme.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.weight: Font.DemiBold
    renderType: Text.NativeRendering
    elide: Text.ElideRight
    maximumLineCount: 1
    topPadding: Math.ceil(font.pixelSize * 0.12)
  }

  Item {
    id: actionHit
    anchors.right: parent.right
    anchors.rightMargin: root.horizontalPadding
    anchors.verticalCenter: parent.verticalCenter
    visible: root.hasAction
    width: Math.min(actionLabel.implicitWidth + Style.space(4), root.width * 0.5)
    height: labelText.implicitHeight
    opacity: root.actionEnabled ? 1 : Style.disabledOpacity

    implicitWidth: width
    implicitHeight: height

    Text {
      id: actionLabel
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width
      horizontalAlignment: Text.AlignRight
      text: root.action
      color: actionMouse.containsMouse && root.actionEnabled ? Theme.fg : Theme.primary
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.weight: Font.DemiBold
      renderType: Text.NativeRendering
      elide: Text.ElideRight
      maximumLineCount: 1
      Behavior on color { ColorAnimation { duration: Style.duration(Style.motion.fast) } }
    }

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      enabled: root.hasAction && root.actionEnabled
      hoverEnabled: true
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.actionTriggered()
    }
  }
}