pragma ComponentBehavior: Bound
import QtQuick
import ".."

// A search/filter field with a clear button. Replaces hand-rolled TextFields
// used for filtering lists (Settings, BarModules, etc.).
Rectangle {
  id: root

  property string text: ""
  property string placeholderText: "Search"
  signal edited(string text)

  implicitHeight: Style.space(28)
  height: implicitHeight
  radius: Theme.cornerRadius
  color: Theme.surface
  border.width: Style.strokeWidth
  border.color: field.activeFocus ? Theme.primary : Theme.border

  TextField {
    id: field
    anchors.fill: parent
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: clearBtn.visible ? clearBtn.width + Style.space(8) : Style.space(8)
    text: root.text
    placeholderText: root.placeholderText
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    color: Theme.fg
    renderType: Text.NativeRendering
    verticalAlignment: Text.AlignVCenter
    onTextChanged: root.edited(text)
  }

  Text {
    id: clearBtn
    anchors.right: parent.right
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    visible: field.text !== ""
    text: "×"
    color: clearMouse.containsMouse ? Theme.fg : Theme.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.subtitle
    renderType: Text.NativeRendering

    MouseArea {
      id: clearMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        field.text = ""
        root.edited("")
      }
    }
  }
}
