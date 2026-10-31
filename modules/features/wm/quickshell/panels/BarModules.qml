import QtQuick
import ".."
import "../Ui"
import Quickshell

Item {
  id: root

  readonly property var sections: ["left", "centerBegin", "center", "centerEnd", "tray", "right"]

  readonly property var config: BarConfig.config
  readonly property var layout: (root.config && root.config.layout) ? root.config.layout : ({})

  function entriesOf(name) {
    const list = root.layout[name]
    return Array.isArray(list) ? list : []
  }

  implicitWidth: Style.space(400)
  implicitHeight: card.implicitHeight

  Panel {
    id: card
    anchors.fill: parent
    maxWidth: Style.space(400)

    PanelHero {
      width: card.contentWidth
      glyph: ""
      title: "Bar"
      subtitle: "Modules, position and background"
    }

    PanelSeparator {}

    PanelSectionHeader {
      width: card.contentWidth
      label: "Position"
    }

    SegmentedControl {
      width: card.contentWidth
      model: ["top", "bottom", "left", "right"]
      currentIndex: ["top", "bottom", "left", "right"].indexOf(BarContext.position)
      onActivated: function (index) {
        BarConfig.setPosition(["top", "bottom", "left", "right"][index])
      }
    }

    PanelSectionHeader {
      width: card.contentWidth
      label: "Background"
    }

    SegmentedControl {
      width: card.contentWidth
      model: ["clear", "glassy", "opaque"]
      currentIndex: ["clear", "glassy", "opaque"].indexOf(String(BarConfig.config.background || "clear"))
      onActivated: function (index) {
        BarConfig.setBackground(["clear", "glassy", "opaque"][index])
      }
    }

    PanelSeparator {}

    PanelSectionHeader {
      width: card.contentWidth
      label: "Modules"
      action: "Reset"
      onActionTriggered: BarConfig.reset()
    }

    Repeater {
      model: root.sections

      delegate: Item {
        id: sectionItem
        required property string modelData
        width: card.contentWidth
        height: sectionColumn.implicitHeight

        readonly property string sectionName: sectionItem.modelData

        Column {
          id: sectionColumn
          width: parent.width
          spacing: Style.space(2)

          PanelSectionHeader {
            width: parent.width
            label: sectionItem.sectionName
          }

          Repeater {
            model: root.entriesOf(sectionItem.sectionName)

            delegate: Row {
              id: moduleRow
              required property var modelData
              required property int index
              width: parent.width
              spacing: Style.space(4)

              readonly property string moduleId: String(moduleRow.modelData.id || "")

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(150)
                text: moduleRow.moduleId
                color: Theme.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
                renderType: Text.NativeRendering
              }

              Dropdown {
                width: Style.space(110)
                model: root.sections
                currentIndex: root.sections.indexOf(sectionItem.sectionName)
                onActivated: function (i) {
                  const target = root.sections[i]
                  if (target !== sectionItem.sectionName)
                    BarConfig.move(moduleRow.moduleId, target, 0)
                }
              }

              TextButton {
                label: "↑"
                onClicked: {
                  if (moduleRow.index > 0)
                    BarConfig.move(moduleRow.moduleId, sectionItem.sectionName, moduleRow.index - 1)
                }
              }

              TextButton {
                label: "↓"
                onClicked: {
                  const list = root.entriesOf(sectionItem.sectionName)
                  if (moduleRow.index < list.length - 1)
                    BarConfig.move(moduleRow.moduleId, sectionItem.sectionName, moduleRow.index + 2)
                }
              }

              TextButton {
                label: "×"
                onClicked: BarConfig.disable(moduleRow.moduleId)
              }
            }
          }
        }
      }
    }

    PanelSeparator {}

    PanelSectionHeader {
      width: card.contentWidth
      label: "Available"
    }

    Repeater {
      model: BarConfig.availableModules()

      delegate: Row {
        required property string modelData
        width: card.contentWidth
        spacing: Style.space(4)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(260)
          text: modelData
          color: Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          renderType: Text.NativeRendering
        }

        TextButton {
          label: "Enable"
          onClicked: BarConfig.enable(modelData)
        }
      }
    }
  }
}
