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

              // Drag-and-drop reordering handle. Only active when no filter
              // is applied, so indices stay aligned with the saved layout.
              Drag.source: moduleRow
              property string dragId: String(moduleRow.modelData.id || "")

              readonly property string moduleId: String(moduleRow.modelData.id || "")

              Rectangle {
                id: grip
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(16)
                height: Style.space(20)
                radius: Theme.cornerRadius
                color: dragHandle.containsMouse ? Theme.bg : "transparent"
                visible: root.filterText.trim() === ""

                Text {
                  anchors.centerIn: parent
                  text: "≡"
                  color: Theme.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  renderType: Text.NativeRendering
                }

                DragHandler {
                  id: dragHandle
                  target: null
                  enabled: root.filterText.trim() === ""
                  onActiveChanged: {
                    if (active) moduleRow.Drag.active = true
                    else moduleRow.Drag.active = false
                  }
                }
              }

              DropArea {
                id: dropTarget
                anchors.fill: parent
                enabled: root.filterText.trim() === ""

                onEntered: function (drag) {
                  dropTarget.highlight = true
                }
                onExited: dropTarget.highlight = false
                onDropped: function (drop) {
                  dropTarget.highlight = false
                  const source = drop.source
                  if (!source || source === moduleRow) return
                  const id = String(source.dragId || "")
                  if (id === "") return
                  BarConfig.move(id, sectionItem.sectionName, moduleRow.index)
                }

                property bool highlight: false
              }

              Rectangle {
                anchors.fill: parent
                color: dropTarget.highlight ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) : "transparent"
                radius: Theme.cornerRadius
                z: -1
              }

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

              TextButton {
                label: "Remove"
                onClicked: BarConfig.remove(moduleRow.moduleId)
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
      label: "Parked (disabled)"
    }

    Repeater {
      model: (root.config && Array.isArray(root.config.disabled)) ? root.config.disabled : []

      delegate: Row {
        required property var modelData
        width: card.contentWidth
        spacing: Style.space(4)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(200)
          text: root.prettyId(String(modelData.entry ? modelData.entry.id : ""))
          color: Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          renderType: Text.NativeRendering
        }

        TextButton {
          label: "Restore"
          onClicked: BarConfig.enable(String(modelData.entry ? modelData.entry.id : ""))
        }
      }
    }

    PanelSeparator {}

    PanelSectionHeader {
      width: card.contentWidth
      label: "Widget settings"
    }

    Column {
      width: card.contentWidth
      spacing: Style.space(6)

      readonly property var enabledIds: BarConfig.enabledModules
      property string selected: enabledIds.length > 0 ? enabledIds[0] : ""

      Dropdown {
        id: widgetSelect
        width: parent.width
        model: parent.enabledIds
        currentIndex: 0
        onActivated: function (i) {
          const ids = parent.enabledIds
          if (i >= 0 && i < ids.length) parent.selected = ids[i]
        }
      }

      readonly property string selectedId: parent.selected

      Text {
        width: parent.width
        visible: parent.enabledIds.length === 0
        text: "No enabled widgets"
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering
      }

      TextField {
        width: parent.width
        visible: parent.selectedId.indexOf("clock") !== -1
        placeholderText: "Clock format (e.g. dddd HH:mm)"
        text: BarConfig.settingOf(parent.selectedId, "format") || ""
        onEditingFinished: BarConfig.setSetting(parent.selectedId, "format", text)
      }

      TextField {
        width: parent.width
        visible: parent.selectedId.indexOf("weather") !== -1
        placeholderText: "Weather location"
        text: BarConfig.settingOf(parent.selectedId, "location") || ""
        onEditingFinished: BarConfig.setSetting(parent.selectedId, "location", text)
      }

      TextField {
        width: parent.width
        visible: parent.selectedId.indexOf("weather") !== -1
        placeholderText: "Weather interval (seconds)"
        text: String(BarConfig.settingOf(parent.selectedId, "interval") || "")
        onEditingFinished: {
          const n = parseInt(text, 10)
          if (isFinite(n)) BarConfig.setSetting(parent.selectedId, "interval", n)
        }
      }
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
