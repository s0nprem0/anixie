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
    { label: "Network", icon: Util.globe, source: "Network.qml" },
    { label: "Notifications", icon: Util.bell, source: "Notifications.qml" },
    { label: "Power", icon: Util.bolt, source: "Power.qml" },
    { label: "Screentime", icon: Util.clock, source: "Screentime.qml" },
    { label: "Session", icon: Util.lock, source: "Session.qml" }
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
        focus: true

        Keys.onDownPressed: root.currentTab = Math.min(root.currentTab + 1, root.allTabs.length - 1)
        Keys.onUpPressed: root.currentTab = Math.max(root.currentTab - 1, 0)

        TextField {
          width: parent.width
          placeholderText: "Search"
          text: root.searchText
          onTextChanged: root.searchText = text
        }

        Repeater {
          model: root.filteredTabs

          delegate: Rectangle {
            id: tabButton
            required property var modelData
            required property int index
            width: sidebar.width
            height: Style.space(36)
            radius: Theme.cornerRadius
            color: tabButton.active ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18) : (tabMouse.containsMouse ? Theme.bg : "transparent")
            border.width: Style.strokeWidth
            border.color: tabButton.active ? Theme.primary : Theme.border

            readonly property bool active: root.allTabs[root.currentTab].label === tabButton.modelData.label

            Row {
              anchors.centerIn: parent
              spacing: Style.space(6)

              Text {
                text: tabButton.modelData.icon
                color: tabButton.active ? Theme.primary : Theme.fg
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Style.font.body
                renderType: Text.NativeRendering
              }

              Text {
                text: tabButton.modelData.label
                color: tabButton.active ? Theme.bg : Theme.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                renderType: Text.NativeRendering
              }
            }

            MouseArea {
              id: tabMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                for (let i = 0; i < root.allTabs.length; i++) {
                  if (root.allTabs[i].label === tabButton.modelData.label) { root.currentTab = i; break }
                }
              }
            }
          }
        }
      }

      Column {
        width: card.contentWidth - sidebar.width - Style.space(12)
        spacing: Style.space(8)

        Loader {
          id: tabLoader
          width: parent.width
          source: Qt.resolvedUrl(root.allTabs[root.currentTab].source)
        }

        Text {
          width: parent.width
          visible: tabLoader.status === Loader.Error
          text: "No settings here"
          color: Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
          renderType: Text.NativeRendering
        }
      }
    }
  }
}
