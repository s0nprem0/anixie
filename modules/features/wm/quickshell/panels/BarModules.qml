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

  function clockPreview(format) {
    const now = new Date()
    const pad = function (value) { return (value < 10 ? "0" : "") + value }
    const dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    const monthNames = ["January", "February", "March", "April", "May", "June",
                       "July", "August", "September", "October", "November", "December"]
    const day = dayNames[now.getDay()]
    const month = monthNames[now.getMonth()]

    return String(format || "").replace(/dddd|ddd|dd|MMMM|MMM|yyyy|HH|mm|ss|W/g, function (token) {
      if (token === "dddd") return day
      if (token === "ddd") return day.slice(0, 3)
      if (token === "dd") return pad(now.getDate())
      if (token === "MMMM") return month
      if (token === "MMM") return month.slice(0, 3)
      if (token === "yyyy") return String(now.getFullYear())
      if (token === "HH") return pad(now.getHours())
      if (token === "mm") return pad(now.getMinutes())
      if (token === "ss") return pad(now.getSeconds())
      if (token === "W") return pad(1)
      return token
    })
  }

  function prettyId(id) {
    let s = String(id || "")
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

  implicitWidth: Style.space(460)
  implicitHeight: card.implicitHeight

  Panel {
    id: card
    anchors.fill: parent
    maxWidth: Style.space(460)

    PanelHero {
      width: card.contentWidth
      glyph: Util.chart
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

    Row {
      width: card.contentWidth
      spacing: Style.space(6)

      TextButton {
        label: "Undo"
        available: BarConfig.hasPrevious
        onClicked: BarConfig.undo()
      }

      TextButton {
        label: "Clear filter"
        available: root.filterText.trim() !== ""
        onClicked: root.filterText = ""
      }
    }

    Text {
      width: card.contentWidth
      visible: root.sections.every(function (name) { return root.filteredEntries(name).length === 0 })
        && root.filterText.trim() !== ""
      text: "No modules match the filter"
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      wrapMode: Text.WordWrap
      renderType: Text.NativeRendering
    }

    Repeater {
      model: root.sections

      delegate: Item {
        id: sectionItem
        required property string modelData
        width: card.contentWidth
        height: sectionColumn.implicitHeight
        visible: root.filteredEntries(sectionItem.modelData).length > 0
          || root.filterText.trim() !== ""

        readonly property string sectionName: sectionItem.modelData

        Column {
          id: sectionColumn
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            width: parent.width
            label: root.sectionLabel(sectionItem.sectionName)
          }

          Repeater {
            model: root.filteredEntries(sectionItem.sectionName)

            delegate: Item {
              id: moduleRow
              required property var modelData
              required property int index
              width: card.contentWidth
              height: moduleColumn.implicitHeight

              readonly property string moduleId: String(modelData.id || "")
              property string dragId: String(modelData.id || "")

              Drag.active: dragHandle.active
              Drag.source: moduleRow
              Drag.hotSpot.x: width / 2
              Drag.hotSpot.y: height / 2
              Drag.keys: ["bar-module"]

              Column {
                id: moduleColumn
                width: parent.width
                spacing: Style.space(2)

                Row {
                  id: identityRow
                  width: parent.width
                  spacing: Style.space(4)
                  z: 1

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
                    }
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(Style.space(80), parent.width - Style.space(212))
                    text: root.prettyId(moduleRow.moduleId)
                    color: Theme.fg
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                    renderType: Text.NativeRendering
                  }

                  Dropdown {
                    width: Style.space(88)
                    model: root.sections.map(root.sectionLabel)
                    currentIndex: root.sections.indexOf(sectionItem.sectionName)
                    onActivated: function (i) {
                      const target = root.sections[i]
                      if (target !== sectionItem.sectionName)
                        BarConfig.move(moduleRow.moduleId, target, 0)
                    }
                  }

                  Dropdown {
                    width: Style.space(96)
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
                }

                Row {
                  id: actionRow
                  width: parent.width
                  spacing: Style.space(4)
                  z: 1

                  Item {
                    width: Math.max(0, parent.width - Style.space(180))
                    height: 1
                  }

                  TextButton {
                    label: "↑"
                    tooltipText: "Move up"
                    available: root.filterText.trim() === ""
                    onClicked: {
                      if (root.filterText.trim() === "" && moduleRow.index > 0)
                        BarConfig.move(moduleRow.moduleId, sectionItem.sectionName, moduleRow.index - 1)
                    }
                  }

                  TextButton {
                    label: "↓"
                    tooltipText: "Move down"
                    available: root.filterText.trim() === ""
                    onClicked: {
                      const full = root.entriesOf(sectionItem.sectionName)
                      if (root.filterText.trim() === "" && moduleRow.index < full.length - 1)
                        BarConfig.move(moduleRow.moduleId, sectionItem.sectionName, moduleRow.index + 2)
                    }
                  }

                  TextButton {
                    label: "Park"
                    tooltipText: "Park in the tray (remembers original place)"
                    onClicked: BarConfig.disable(moduleRow.moduleId)
                  }

                  TextButton {
                    label: "Remove"
                    tooltipText: "Fully remove (no tray, re-enable goes to default section)"
                    onClicked: BarConfig.remove(moduleRow.moduleId)
                  }
                }
              }

              DropArea {
                anchors.fill: parent
                z: 0
                keys: ["bar-module"]
                enabled: root.filterText.trim() === ""

                onEntered: function (drag) {
                  dropTarget.highlight = true
                  dropTarget.dropY = drag ? drag.y : 0
                }
                onPositionChanged: function (drag) {
                  if (drag) dropTarget.dropY = drag.y
                }
                onExited: dropTarget.highlight = false
                onDropped: function (drop) {
                  dropTarget.highlight = false
                  const source = drop.source
                  if (!source || source === moduleRow) return
                  const id = String(source.dragId || "")
                  if (id === "") return
                  const lowerHalf = dropTarget.dropY >= (moduleRow.height / 2)
                  const insertAt = moduleRow.index + (lowerHalf ? 1 : 0)
                  BarConfig.move(id, sectionItem.sectionName, insertAt)
                }

                property bool highlight: false
                property real dropY: 0
              }

              Rectangle {
                x: 0
                y: dropTarget.dropY < (parent.height / 2) ? 0 : (parent.height - height)
                width: parent.width
                height: dropTarget.highlight ? Style.space(2) : 0
                color: Theme.primary
                radius: 0
                z: 2
                visible: dropTarget.highlight
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

    Text {
      width: card.contentWidth
      visible: !(root.config && Array.isArray(root.config.disabled)) || root.config.disabled.length === 0
      text: "No parked modules"
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      renderType: Text.NativeRendering
    }

    Repeater {
      model: (root.config && Array.isArray(root.config.disabled)) ? root.config.disabled : []

      delegate: Row {
        required property var modelData
        width: card.contentWidth
        spacing: Style.space(4)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(Style.space(120), parent.width - Style.space(140))
          text: root.prettyId(String(modelData.entry ? modelData.entry.id : ""))
          color: Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          renderType: Text.NativeRendering
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(60)
          visible: String(modelData.section || "") !== ""
          text: root.sectionLabel(String(modelData.section || ""))
          color: Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          renderType: Text.NativeRendering
        }

        TextButton {
          label: "Restore"
          onClicked: BarConfig.enable(String(modelData.entry ? modelData.entry.id : ""))
        }
      }
    }

    Row {
      width: card.contentWidth
      spacing: Style.space(6)
      visible: (root.config && Array.isArray(root.config.disabled)) && root.config.disabled.length > 0

      TextButton {
        label: "Restore all"
        onClicked: {
          const disabled = (root.config && Array.isArray(root.config.disabled)) ? root.config.disabled : []
          for (let i = 0; i < disabled.length; i++) {
            const entry = disabled[i] && disabled[i].entry ? disabled[i].entry : null
            if (entry && entry.id) BarConfig.enable(String(entry.id))
          }
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

      onEnabledIdsChanged: {
        if (enabledIds.indexOf(selected) === -1)
          selected = enabledIds.length > 0 ? enabledIds[0] : ""
      }

      Dropdown {
        id: widgetSelect
        width: parent.width
        model: parent.enabledIds.map(root.prettyId)
        currentIndex: {
          const ids = parent.enabledIds
          const i = ids.indexOf(parent.selected)
          return i >= 0 ? i : 0
        }
        onActivated: function (i) {
          const ids = parent.enabledIds
          if (i >= 0 && i < ids.length) parent.selected = ids[i]
        }
      }

      readonly property string selectedId: selected

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
        id: clockFormatInput
        width: parent.width
        visible: parent.selectedId === "bar.clock"
        placeholderText: "Clock format (e.g. dddd HH:mm)"
        text: BarConfig.settingOf(parent.selectedId, "format") || ""
        onEditingFinished: BarConfig.setSetting(parent.selectedId, "format", text)
      }

      Text {
        width: parent.width
        visible: parent.selectedId === "bar.clock"
        text: "Preview: " + root.clockPreview(clockFormatInput.text || BarConfig.settingOf(parent.selectedId, "format") || "")
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
        renderType: Text.NativeRendering
      }

      TextField {
        width: parent.width
        visible: parent.selectedId === "bar.clock"
        placeholderText: "Clock alternate format"
        text: BarConfig.settingOf(parent.selectedId, "formatAlt") || ""
        onEditingFinished: BarConfig.setSetting(parent.selectedId, "formatAlt", text)
      }

      TextField {
        width: parent.width
        visible: parent.selectedId === "bar.weather"
        placeholderText: "Weather location"
        text: BarConfig.settingOf(parent.selectedId, "location") || ""
        onEditingFinished: BarConfig.setSetting(parent.selectedId, "location", text)
      }

      TextField {
        width: parent.width
        visible: parent.selectedId === "bar.weather"
        placeholderText: "Weather interval (seconds)"
        text: String(BarConfig.settingOf(parent.selectedId, "interval") || "")
        onEditingFinished: {
          const n = parseInt(text, 10)
          if (isFinite(n)) BarConfig.setSetting(parent.selectedId, "interval", n)
        }
      }

      TextField {
        width: parent.width
        visible: parent.selectedId === "bar.world-clock"
        placeholderText: "World clock zones (comma-separated)"
        text: BarConfig.settingOf(parent.selectedId, "zones") || ""
        onEditingFinished: BarConfig.setSetting(parent.selectedId, "zones", text)
      }

      TextField {
        width: parent.width
        visible: parent.selectedId === "bar.model-usage"
        placeholderText: "Model usage interval (seconds)"
        text: String(BarConfig.settingOf(parent.selectedId, "interval") || "")
        onEditingFinished: {
          const n = parseInt(text, 10)
          if (isFinite(n)) BarConfig.setSetting(parent.selectedId, "interval", n)
        }
      }

      TextField {
        width: parent.width
        visible: parent.selectedId === "bar.model-usage"
        placeholderText: "Model usage days"
        text: String(BarConfig.settingOf(parent.selectedId, "days") || "")
        onEditingFinished: {
          const n = parseInt(text, 10)
          if (isFinite(n)) BarConfig.setSetting(parent.selectedId, "days", n)
        }
      }
    }

    PanelSeparator {}

    PanelSectionHeader {
      width: card.contentWidth
      label: "Available"
    }

    Text {
      width: card.contentWidth
      visible: root.filteredAvailable().length === 0
      text: root.filterText.trim() === "" ? "All modules are enabled" : "No modules match the filter"
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      renderType: Text.NativeRendering
    }

    Repeater {
      model: root.filteredAvailable()

      delegate: Row {
        required property string modelData
        width: card.contentWidth
        spacing: Style.space(4)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(Style.space(120), parent.width - Style.space(164))
          text: root.prettyId(modelData)
          color: Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          renderType: Text.NativeRendering
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(90)
          text: root.sectionLabel(BarConfig.sectionFor(modelData)) + " · off"
          color: Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
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