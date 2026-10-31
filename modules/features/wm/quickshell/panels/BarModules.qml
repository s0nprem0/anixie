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

  function sectionLabel(name) {
    switch (String(name)) {
    case "left": return "Left"
    case "centerBegin": return "Center begin"
    case "center": return "Center"
    case "centerEnd": return "Center end"
    case "tray": return "Tray (parked)"
    case "right": return "Right"
    default: return String(name)
    }
  }

  function prettyId(id) {
    let s = String(id || "")
    // Strip the "bar." prefix and turn separators into spaces, then title-case.
    s = s.replace(/^bar\./, "")
    s = s.replace(/[-_.]/g, " ")
    s = s.replace(/\s+/g, " ").trim()
    if (s === "") return String(id)
    return s.replace(/\b\w/g, function (c) { return c.toUpperCase() })
  }

  property string filterText: ""

  function matchesFilter(id) {
    if (root.filterText.trim() === "") return true
    const q = root.filterText.toLowerCase()
    return String(id).toLowerCase().indexOf(q) !== -1
      || root.prettyId(id).toLowerCase().indexOf(q) !== -1
  }

  function filteredEntries(name) {
    return root.entriesOf(name).filter(function (entry) {
      return entry && entry.id && root.matchesFilter(entry.id)
    })
  }

  function filteredAvailable() {
    return BarConfig.availableModules.filter(function (id) {
      return root.matchesFilter(id)
    })
  }

  property bool confirmReset: false

  Timer {
    id: resetTimer
    interval: 3000
    repeat: false
    onTriggered: root.confirmReset = false
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
        const next = ["top", "bottom", "left", "right"][index]
        const changed = BarContext.position !== next
        if (BarConfig.setPosition(next) && changed) PanelHost.closeAll()
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
      action: root.confirmReset ? "Confirm reset" : "Reset"
      onActionTriggered: {
        if (root.confirmReset) {
          BarConfig.reset()
          root.confirmReset = false
          resetTimer.stop()
        } else {
          root.confirmReset = true
          resetTimer.restart()
        }
      }
    }

    TextField {
      width: card.contentWidth
      placeholderText: "Filter modules"
      text: root.filterText
      onTextChanged: root.filterText = text
    }

    Repeater {
      model: root.sections

      delegate: Item {
        id: sectionItem
        required property string modelData
        width: card.contentWidth
        height: sectionColumn.implicitHeight
        visible: root.filteredEntries(sectionItem.modelData).length > 0 || root.filterText.trim() === ""

        readonly property string sectionName: sectionItem.modelData

        Column {
          id: sectionColumn
          width: parent.width
          spacing: Style.space(2)

          PanelSectionHeader {
            width: parent.width
            label: root.sectionLabel(sectionItem.sectionName)
          }

          Repeater {
            model: root.filteredEntries(sectionItem.sectionName)

            delegate: Row {
              id: moduleRow
              required property var modelData
              required property int index
              width: parent.width
              spacing: Style.space(4)

              readonly property string moduleId: String(moduleRow.modelData.id || "")

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(120)
                text: root.prettyId(moduleRow.moduleId)
                color: Theme.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
                renderType: Text.NativeRendering
              }

              Dropdown {
                width: Style.space(90)
                model: root.sections.map(root.sectionLabel)
                currentIndex: root.sections.indexOf(sectionItem.sectionName)
                onActivated: function (i) {
                  const target = root.sections[i]
                  if (target !== sectionItem.sectionName)
                    BarConfig.move(moduleRow.moduleId, target, 0)
                }
              }

              Dropdown {
                width: Style.space(100)
                model: (["All screens"]).concat(Quickshell.screens.map(function (s) { return String(s.name) }))
                currentIndex: {
                  const screens = moduleRow.modelData.screens
                  if (!Array.isArray(screens) || screens.length === 0 || screens.indexOf("all") !== -1)
                    return 0
                  const idx = Quickshell.screens.map(function (s) { return String(s.name) }).indexOf(String(screens[0]))
                  return idx >= 0 ? idx + 1 : 0
                }
                onActivated: function (i) {
                  if (i === 0) BarConfig.setScreens(moduleRow.moduleId, null)
                  else BarConfig.setScreens(moduleRow.moduleId, Quickshell.screens[i - 1].name)
                }
              }

              TextButton {
                label: "↑"
                available: root.filterText.trim() === ""
                onClicked: {
                  if (root.filterText.trim() === "" && moduleRow.index > 0)
                    BarConfig.move(moduleRow.moduleId, sectionItem.sectionName, moduleRow.index - 1)
                }
              }

              TextButton {
                label: "↓"
                available: root.filterText.trim() === ""
                onClicked: {
                  const full = root.entriesOf(sectionItem.sectionName)
                  if (root.filterText.trim() === "" && moduleRow.index < full.length - 1)
                    BarConfig.move(moduleRow.moduleId, sectionItem.sectionName, moduleRow.index + 2)
                }
              }

              TextButton {
                label: "Park"
                onClicked: BarConfig.disable(moduleRow.moduleId)
              }
            }
          }
        }
      }
    }

    Text {
      width: card.contentWidth
      visible: String(BarConfig.lastError || "") !== ""
      text: String(BarConfig.lastError || "")
      color: Theme.error
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      wrapMode: Text.WordWrap
      renderType: Text.NativeRendering
    }

    PanelSeparator {}

    PanelSectionHeader {
      width: card.contentWidth
      label: "Available"
    }

    Repeater {
      model: root.filteredAvailable()

      delegate: Row {
        required property string modelData
        width: card.contentWidth
        spacing: Style.space(4)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(260)
          text: root.prettyId(modelData)
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
