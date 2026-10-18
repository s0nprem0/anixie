import QtQuick
import ".."

// The small label that introduces a panel section — "PERFORMANCE PROFILE",
// "BATTERY", "WI-FI NETWORKS". Sits under a PanelSeparator, above the rows it
// names.
//
// Muted rather than a tint of the foreground: the panels already use muted for
// their section labels, and a heading is the one place a panel does *not* want
// the accent — accent is for what is live or chosen, and a heading is neither.
Text {
  id: root

  property string label: ""

  text: root.label
  textFormat: Text.PlainText
  color: Theme.muted
  font.family: Style.font.family
  font.pixelSize: Style.font.caption
  font.weight: Font.DemiBold
  renderType: Text.NativeRendering

  // Glyphs paint above the box Text reserves for them: the Nerd Font's outlines
  // run past its own ascent, and a header at the top of a clipping list loses
  // that sliver to the clip and renders beheaded. Reserved here so every panel
  // is covered at once rather than each one guessing.
  topPadding: Math.ceil(font.pixelSize * 0.15)
}
