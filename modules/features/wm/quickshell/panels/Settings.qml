import QtQuick
import ".."
import "../Ui"
import Quickshell

Item {
  id: root

  readonly property var allTabs: [
    { label: "Appearance", icon: Util.palette, source: "Appearance.qml" },
    { label: "Bar", icon: Util.chart, source: "BarModules.qml" },
    { label: "Displays", icon: Util.laptop, source: "Displays.qml" },
    { label: "Media & audio", icon: Util.media, source: "MediaMixer.qml" },
    { label: "Network", icon: Util.globe, source: "Network.qml" },
    { label: "Night light", icon: Util.moon, source: "NightLight.qml" },
    { label: "Notifications", icon: Util.bell, source: "Notifications.qml" },
    { label: "Power", icon: Util.bolt, source: "Power.qml" },
    { label: "Screentime", icon: Util.clock, source: "Screentime.qml" },
    { label: "Session", icon: Util.lock, source: "Session.qml" }
  ]

  property string searchText: ""
  property int currentTab: 0

  readonly property string _searchQuery: root.searchText.replace(/^\s+|\s+$/g, "").toLowerCase()

  readonly property var filteredTabs: {
    if (root._searchQuery === "") return root.allTabs
    const out = []
    for (let i = 0; i < root.allTabs.length; i++) {
      if (root.allTabs[i].label.toLowerCase().indexOf(root._searchQuery) !== -1) out.push({ tab: root.allTabs[i], index: i })
    }
    return out
  }

  function selectTabByLabel(name) {
    const q = String(name || "").replace(/^\s+|\s+$/g, "").toLowerCase()
    if (q === "") return false
    for (let i = 0; i < root.allTabs.length; i++) {
      if (root.allTabs[i].label.toLowerCase() === q) {
        root.currentTab = i
        return true
      }
    }
    for (let i = 0; i < root.allTabs.length; i++) {
      if (root.allTabs[i].label.toLowerCase().indexOf(q) !== -1) {
        root.currentTab = i
        return true
      }
    }
    return false
  }

  function selectFilteredIndex(idx) {
    if (root._searchQuery === "") {
      if (idx >= 0 && idx < root.allTabs.length) root.currentTab = idx
      return
    }
    const list = root.filteredTabs
    if (idx < 0 || idx >= list.length) return
    root.currentTab = list[idx].index
  }

  function moveFiltered(delta) {
    const list = root.filteredTabs
    if (list.length === 0) return
    let cur = -1
    if (root._searchQuery === "") {
      cur = root.currentTab
      const next = Math.max(0, Math.min(list.length - 1, cur + delta))
      root.currentTab = next
      return
    }
    for (let i = 0; i < list.length; i++) {
      if (list[i].index === root.currentTab) { cur = i; break }
    }
    if (cur < 0) {
      root.currentTab = list[0].index
      return
    }
    const next = (cur + delta) % list.length
    const n = next < 0 ? next + list.length : next
    root.currentTab = list[n].index
  }

  onSearchTextChanged: {
    if (root._searchQuery === "") return
    const list = root.filteredTabs
    if (list.length === 0) return
    // Ensure currentTab points to a visible tab
    for (let i = 0; i < list.length; i++) {
      if (list[i].index === root.currentTab) return
    }
    root.currentTab = list[0].index
  }

  Connections {
    target: SettingsHost
    function onRequestedTabChanged() {
      const name = String(SettingsHost.requestedTab || "")
      if (name === "") return
      root.selectTabByLabel(name)
      SettingsHost.requestedTab = ""
    }
  }

  implicitWidth: Style.space(760)
  implicitHeight: card.implicitHeight

  Panel {
    id: card
    anchors.fill: parent
    maxWidth: Style.space(760)

    PanelHero {
      width: card.contentWidth
      glyph: ""
      title: "Settings"
      subtitle: "System and shell preferences"
    }

    Row {
      width: card.contentWidth
      spacing: Style.space(12)

      Column {
        id: sidebar
        width: Style.space(180)
        spacing: Style.space(4)
        focus: false

        FilterInput {
          id: searchField
          width: parent.width
          placeholderText: "Search settings"
          text: root.searchText
          onEdited: function (t) { root.searchText = t }

          Keys.onPressed: function (event) {
            if (event.key === Qt.Key_Down) {
              root.moveFiltered(1)
              sidebar.focus = true
              event.accepted = true
            } else if (event.key === Qt.Key_Up) {
              root.moveFiltered(-1)
              sidebar.focus = true
              event.accepted = true
            } else if (event.key === Qt.Key_Tab) {
              // Allow tab to move focus
            }
          }
        }

        Item {
          width: parent.width
          focus: true
          Keys.onPressed: function (event) {
            if (searchField.activeFocus) return
            if (event.key === Qt.Key_Down) {
              root.moveFiltered(1)
              event.accepted = true
            } else if (event.key === Qt.Key_Up) {
              root.moveFiltered(-1)
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              event.accepted = true
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: root._searchQuery === "" ? root.allTabs.length : root.filteredTabs.length

              delegate: Rectangle {
                id: tabButton
                required property int index
                width: sidebar.width
                height: Style.space(36)
                radius: Theme.cornerRadius
                focus: true
                activeFocusOnTab: true

                readonly property var tabData: root._searchQuery === ""
                  ? root.allTabs[tabButton.index]
                  : root.filteredTabs[tabButton.index].tab
                readonly property bool active: root.allTabs[root.currentTab].label === tabButton.tabData.label

                color: tabButton.active
                  ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25)
                  : (tabButton.activeFocus
                      ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                      : (tabMouse.containsMouse ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.08) : "transparent"))
                border.width: tabButton.active ? Style.strokeWidth * 2 : Style.strokeWidth
                border.color: tabButton.active
                  ? Theme.primary
                  : (tabButton.activeFocus ? Theme.primary : Theme.border)

                // Left accent bar for the active tab.
                Rectangle {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(4)
                  height: parent.height - Style.space(8)
                  radius: Theme.cornerRadius
                  visible: tabButton.active
                  color: Theme.primary
                }

                Accessible.role: Accessible.Button
                Accessible.name: tabButton.tabData.label

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(6)

                  Text {
                    text: tabButton.tabData.icon || ""
                    color: tabButton.active ? Theme.primary : Theme.fg
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Style.font.body
                    renderType: Text.NativeRendering
                    verticalAlignment: Text.AlignVCenter
                  }

                  Text {
                    text: tabButton.tabData.label || ""
                    color: tabButton.active ? Theme.primary : Theme.fg
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.weight: tabButton.active ? Font.DemiBold : Font.Normal
                    renderType: Text.NativeRendering
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                  }
                }

                MouseArea {
                  id: tabMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.selectFilteredIndex(tabButton.index)
                  }
                }

                Keys.onPressed: function (event) {
                  if (searchField.activeFocus) return
                  if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                    root.selectFilteredIndex(tabButton.index)
                    event.accepted = true
                  }
                }
              }
            }

            // Empty state when search yields nothing.
            PanelList {
              width: sidebar.width
              visible: root._searchQuery !== "" && root.filteredTabs.length === 0
              model: []
              emptyText: "No results"
              rowSpacing: Style.space(2)
            }
          }
        }
      }

      Column {
        width: Math.max(0, card.contentWidth - sidebar.width - Style.space(12))
        spacing: Style.space(8)

        Loader {
          id: tabLoader
          width: parent.width
          source: root.allTabs.length > 0 ? Qt.resolvedUrl(root.allTabs[Math.max(0, Math.min(root.currentTab, root.allTabs.length - 1))].source) : ""
          onStatusChanged: {
            if (status === Loader.Error) {
              console.warn("settings: failed to load " + source)
            }
          }
        }

        PanelList {
          width: parent.width
          visible: tabLoader.status === Loader.Error && tabLoader.source !== ""
          model: []
          emptyText: "No settings here"
          rowSpacing: Style.space(2)
        }
      }
    }
  }
}
