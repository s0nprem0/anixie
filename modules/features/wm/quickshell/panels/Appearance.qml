import QtQuick
import ".."
import "../Ui"
import Quickshell

Item {
  id: root

  function imageSource(path) {
    if (!path) return ""
    return path.indexOf("/") === 0 ? "file://" + path : path
  }

  function wallpaperModeIndex() {
    return ["auto", "light", "dark"].indexOf(AppearanceHost.wallpaperMode)
  }

  function barBackgroundIndex() {
    const mode = String(BarConfig.config.background || "clear")
    return ["clear", "glassy", "opaque"].indexOf(mode)
  }

  implicitWidth: Style.space(360)
  implicitHeight: card.implicitHeight

  Panel {
    id: card
    anchors.fill: parent
    maxWidth: Style.space(360)

    PanelHero {
      width: card.contentWidth
      art: root.imageSource(AppearanceHost.currentThumb)
      glyph: AppearanceHost.currentThumb === "" ? Util.palette : ""
      title: "Appearance"
      subtitle: (Theme.name === "wallpaper" ? AppearanceHost.currentWallpaperName : AppearanceHost.currentName)
        + " · " + Theme.mode
        + (AppearanceHost.pinned ? " · pinned" : "")
    }

    Text {
      width: card.contentWidth
      height: implicitHeight
      visible: AppearanceHost.busy
      text: "Applying…"
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }

    PanelSeparator {}

    PanelSectionHeader {
      width: card.contentWidth
      label: "Wallpaper"
      action: "Next"
      onActionTriggered: AppearanceHost.nextWallpaper()
    }

    Item {
      width: card.contentWidth
      height: Style.space(58)

      ListView {
        id: wallpapers
        anchors.fill: parent
        orientation: ListView.Horizontal
        spacing: Style.space(6)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: AppearanceHost.library

        delegate: Item {
          required property var modelData
          width: Style.space(92)
          height: Style.space(54)

          readonly property bool panelFocusable: true

          function activate() {
            AppearanceHost.useWallpaper(String(modelData.path || "generated"))
          }

          function keyStep(direction) {
            return false
          }

          Rectangle {
            anchors.fill: parent
            radius: Theme.cornerRadius
            color: Theme.surface
            border.color: modelData.path === AppearanceHost.currentPath
              || (modelData.generated && AppearanceHost.currentName === "Wallpaper")
              ? Theme.primary
              : Theme.border
            border.width: Style.strokeWidth
            clip: true

            Image {
              anchors.fill: parent
              source: root.imageSource(String(modelData.thumb || ""))
              fillMode: Image.PreserveAspectCrop
              sourceSize.width: width * 2
              sourceSize.height: height * 2
              asynchronous: true
            }

            Text {
              visible: String(modelData.thumb || "") === ""
              anchors.centerIn: parent
              text: modelData.generated ? "Generated" : String(modelData.name || "")
              color: Theme.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width - Style.space(8)
              horizontalAlignment: Text.AlignHCenter
              renderType: Text.NativeRendering
            }

            Rectangle {
              visible: modelData.video === true
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(3)
              width: Style.space(16)
              height: width
              radius: Theme.cornerRadius
              color: Theme.bg

              Text {
                anchors.centerIn: parent
                text: Util.record
                color: Theme.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                renderType: Text.NativeRendering
              }
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.activate()
          }
        }
      }

      Text {
        visible: AppearanceHost.library.length === 0
        anchors.centerIn: parent
        text: AppearanceHost.libraryProc.running ? "Loading wallpapers…" : "No wallpapers found"
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }
    }

    Row {
      width: card.contentWidth
      spacing: Style.space(6)

      TextButton {
        label: "Generated"
        onClicked: AppearanceHost.useWallpaper("generated")
      }

      TextButton {
        label: "Previous"
        onClicked: AppearanceHost.previousWallpaper()
      }

      TextButton {
        label: "Random"
        onClicked: Commands.run("wallpaper rotate")
      }

      TextButton {
        label: "Picker"
        onClicked: Commands.run("wallpaper")
      }
    }

    PanelSeparator {}

    PanelSectionHeader {
      width: card.contentWidth
      label: "Presets"
      action: AppearanceHost.pinned ? "Unpin" : "Pin"
      onActionTriggered: AppearanceHost.setPinned(!AppearanceHost.pinned)
    }

    Column {
      width: card.contentWidth
      spacing: Style.space(1)

      Repeater {
        model: AppearanceHost.rows

        delegate: ThemeRow {
          required property var modelData
          width: parent.width
          label: modelData.name
          colors: modelData.colors
          mode: modelData.mode
          selected: modelData.selected
          favorite: modelData.favorite
          onClicked: AppearanceHost.setTheme(modelData.name)
          onFavoriteToggled: AppearanceHost.toggleFavorite(modelData.name)
        }
      }
    }

    PanelSeparator {}

    Toggle {
      width: card.contentWidth
      label: "Glass blur"
      description: "Blur and refract the shell surfaces"
      checked: AppearanceHost.glass
      onToggled: AppearanceHost.toggleGlass()
    }

    PanelSectionHeader {
      width: card.contentWidth
      label: "Wallpaper palette"
    }

    SegmentedControl {
      width: card.contentWidth
      model: ["auto", "light", "dark"]
      currentIndex: root.wallpaperModeIndex()
      onActivated: function (index) {
        AppearanceHost.setWallpaperMode(["auto", "light", "dark"][index])
      }
    }

    PanelSectionHeader {
      width: card.contentWidth
      label: "Bar background"
    }

    SegmentedControl {
      width: card.contentWidth
      model: ["clear", "glassy", "opaque"]
      currentIndex: root.barBackgroundIndex()
      onActivated: function (index) {
        AppearanceHost.setBarBackground(["clear", "glassy", "opaque"][index])
      }
    }

    Toggle {
      width: card.contentWidth
      visible: AppearanceHost.currentIsVideo
      label: "Pause live wallpaper"
      checked: AppearanceHost.videoPaused
      onToggled: AppearanceHost.toggleVideo()
    }

    Text {
      width: card.contentWidth
      height: implicitHeight
      visible: AppearanceHost.lastError !== ""
      text: AppearanceHost.lastError
      color: Theme.danger
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
      renderType: Text.NativeRendering
    }

    PanelActionButton {
      width: card.contentWidth
      label: "Theme doctor"
      value: "Check"
      glyph: Util.palette
      navigational: false
      onClicked: Commands.runQuoted("kitty", ["-e", "theme", "doctor"])
    }
  }
}
