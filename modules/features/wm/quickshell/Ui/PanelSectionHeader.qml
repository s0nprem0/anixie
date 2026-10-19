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

  // The action's own name, drawn at the end of the heading row. Empty for the
  // headings that only name something.
  property string action: ""

  // Whether the action can be used right now. Dimmed rather than gone, so a
  // heading does not change shape as the reason it cannot be used comes and goes.
  property bool actionEnabled: true

  signal actionTriggered()

  // ---- the keyboard ----
  //
  // Only a heading that carries an action is a stop: a heading that only names
  // something is a label, and the keys should walk past it.
  readonly property bool panelFocusable: root.hasAction && root.actionEnabled

  function activate() {
    if (root.hasAction && root.actionEnabled) root.actionTriggered()
  }

  function keyStep(direction) {
    return false
  }

  readonly property bool hasAction: root.action !== ""

  implicitWidth: Math.max(labelText.implicitWidth, actionHit.implicitWidth)
  implicitHeight: Math.max(labelText.implicitHeight, actionLabel.implicitHeight)
  // An Item's implicit size is 0 unless it says otherwise, and this one has to
  // say it: a Panel is a Column, which positions children by height.
  height: implicitHeight

  Text {
    id: labelText
    anchors.left: parent.left
    anchors.right: root.hasAction ? actionHit.left : parent.right
    anchors.rightMargin: root.hasAction ? Style.space(8) : 0
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    textFormat: Text.PlainText
    color: Theme.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.weight: Font.DemiBold
    renderType: Text.NativeRendering
    elide: Text.ElideRight
    width: Math.max(0, parent.width - x - (root.hasAction ? actionHit.width + Style.space(8) : 0))

    // Glyphs paint above the box Text reserves for them: the Nerd Font's outlines
    // run past its own ascent, and a header at the top of a clipping list loses
    // that sliver to the clip and renders beheaded. Reserved here so every panel
    // is covered at once rather than each one guessing.
    topPadding: Math.ceil(font.pixelSize * 0.15)
  }

  Item {
    id: actionHit
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    visible: root.hasAction
    width: actionLabel.implicitWidth + Style.space(8)
    height: labelText.implicitHeight
    opacity: root.actionEnabled ? 1 : 0.45

    implicitWidth: width
    implicitHeight: height

    Text {
      id: actionLabel
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: root.action
      color: actionMouse.containsMouse && root.actionEnabled ? Theme.fg : Theme.primary
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.weight: Font.DemiBold
      renderType: Text.NativeRendering
      Behavior on color { ColorAnimation { duration: Style.duration(120) } }
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