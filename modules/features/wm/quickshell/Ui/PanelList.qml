import QtQuick
import ".."

// A column that lists things, or says so when there are none.
//
// Use instead of hand-rolling Column + Repeater + an empty-state Text in every
// panel. The caller supplies the model and a delegate Component; grouping and
// section headers stay in the caller, since they are panel-specific.
Column {
  id: root

  property var model: []
  property string emptyText: ""
  property int rowSpacing: Style.space(2)
  property Component delegate: null

  spacing: root.rowSpacing

  Repeater {
    model: root.model
    delegate: root.delegate
  }

  Text {
    width: parent.width
    visible: {
      const count = Array.isArray(root.model) ? root.model.length : 0
      return count === 0 && root.emptyText !== ""
    }
    text: root.emptyText
    color: Theme.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
    renderType: Text.NativeRendering
  }
}
