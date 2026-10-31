import QtQuick
import ".."
import "../Ui"
import Quickshell

Item {
  id: root

  readonly property var allTabs: [
    { label: "Appearance", source: "Appearance.qml" },
    { label: "Bar", source: "BarModules.qml" },
    { label: "Displays", source: "Displays.qml" },
    { label: "Network", source: "Network.qml" },
    { label: "Notifications", source: "Notifications.qml" },
    { label: "Power", source: "Power.qml" },
    { label: "Screentime", source: "Screentime.qml" },
    { label: "Session", source: "Session.qml" }
  ]

  property string searchText: ""
  property int currentTab: 0

  readonly property var filteredTabs: {
    const q = root.searchText.trim().toLowerCase()
    if (q === "") return root.allTabs
    return root.allTabs.filter(function (t) {
      return t.label.toLowerCase().indexOf(q) !== -1
    })
  }

  // Honor deep-link requests from the host.
  Connections {
    target: SettingsHost
    function onRequestedTabChanged() {
      const name = String(SettingsHost.requestedTab || "")
      if (name === "") return
      for (let i = 0; i < root.allTabs.length; i++) {
        if (root.allTabs[i].label.toLowerCase() === name.toLowerCase()) {
          root.currentTab = i
          break
        }
      }
      SettingsHost.requestedTab = ""
    }
  }

  implicitWidth: Style.space(520)
  implicitHeight: card.implicitHeight

  Panel {
    id: card
    anchors.fill: parent
    maxWidth: Style.space(520)

    PanelHero {
      width: card.contentWidth
      glyph: ""
      title: "Settings"
      subtitle: "System and shell preferences"
    }

    PanelSeparator {}

    TextField {
      width: card.contentWidth
      placeholderText: "Search settings"
      text: root.searchText
      onTextChanged: root.searchText = text
    }

    PanelSeparator {}

    Dropdown {
      width: card.contentWidth
      model: root.filteredTabs.map(function (t) { return t.label })
      currentIndex: {
        const tabs = root.filteredTabs
        for (let i = 0; i < tabs.length; i++) {
          if (tabs[i].label === root.allTabs[root.currentTab].label) return i
        }
        return 0
      }
      onActivated: function (i) {
        const tabs = root.filteredTabs
        if (i < 0 || i >= tabs.length) return
        for (let j = 0; j < root.allTabs.length; j++) {
          if (root.allTabs[j].label === tabs[i].label) { root.currentTab = j; break }
        }
      }
    }

    PanelSeparator {}

    Loader {
      id: tabLoader
      width: card.contentWidth
      source: Qt.resolvedUrl(root.allTabs[root.currentTab].source)
    }
  }
}
