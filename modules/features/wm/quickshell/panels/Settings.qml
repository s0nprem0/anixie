import QtQuick
import ".."
import "../Ui"
import Quickshell

Item {
  id: root

  readonly property var tabs: [
    { label: "Appearance", source: "Appearance.qml" },
    { label: "Bar", source: "BarModules.qml" },
    { label: "Displays", source: "Displays.qml" },
    { label: "Network", source: "Network.qml" },
    { label: "Notifications", source: "Notifications.qml" },
    { label: "Power", source: "Power.qml" },
    { label: "Screentime", source: "Screentime.qml" },
    { label: "Session", source: "Session.qml" }
  ]

  property int currentTab: 0

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

    Dropdown {
      width: card.contentWidth
      model: root.tabs.map(function (t) { return t.label })
      currentIndex: root.currentTab
      onActivated: function (i) { root.currentTab = i }
    }

    PanelSeparator {}

    Loader {
      id: tabLoader
      width: card.contentWidth
      source: Qt.resolvedUrl(root.tabs[root.currentTab].source)
    }
  }
}
