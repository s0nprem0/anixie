import QtQuick
import ".."
import "../Ui"
import Quickshell

Item {
  id: root

  function imageSource(path) {
    if (!path) return ""
    const p = String(path)
    if (p === "") return ""
    if (p.indexOf(":/") !== -1) return p
    if (p.indexOf("/") === 0) return "file://" + p
    return p
  }

  function wallpaperModeIndex() {
    const m = AppearanceHost && AppearanceHost.wallpaperMode ? String(AppearanceHost.wallpaperMode) : "auto"
    const idx = ["auto", "light", "dark"].indexOf(m)
    return idx === -1 ? 0 : idx
  }

  // Map nearest preset interval; if value doesn't match a preset cleanly, pick nearest
  function rotationIndex() {
    const minutes = BackgroundHost && BackgroundHost.rotationMinutes !== undefined ? Number(BackgroundHost.rotationMinutes) : 0
    if (!isFinite(minutes) || minutes <= 0) return 0
    if (minutes <= 45) return 1
    if (minutes <= 165) return 2
    return 3
  }

  function barBackgroundIndex() {
    const cfg = (BarConfig && BarConfig.config) ? BarConfig.config : ({})
    const mode = String(cfg.background || "clear")
    const idx = ["clear", "glassy", "opaque"].indexOf(mode)
    return idx === -1 ? 0 : idx
  }

  readonly property bool hasGenerated: {
    const lib = (AppearanceHost && AppearanceHost.library) ? AppearanceHost.library : []
    for (let i = 0; i < lib.length; i++) {
      if (lib[i] && lib[i].generated) return true
    }
    return false
  }

  implicitWidth: Style.space(340)
  implicitHeight: card.implicitHeight

  Panel {
    id: card
    anchors.fill: parent
    maxWidth: Style.space(340)

    PanelHero {
      width: card.contentWidth
      art: AppearanceHost ? root.imageSource(AppearanceHost.currentThumb) : ""
      glyph: (AppearanceHost && AppearanceHost.currentThumb === "") ? Util.palette : ""
      title: "Appearance"
      subtitle: AppearanceHost
        ? ((Theme.name === "wallpaper" ? AppearanceHost.currentWallpaperName : AppearanceHost.currentName)
          + " · " + Theme.mode
          + (AppearanceHost.pinned ? " · pinned" : ""))
        : Theme.name + " · " + Theme.mode
    }

    Text {
      width: card.contentWidth
      height: implicitHeight
      visible: AppearanceHost && AppearanceHost.busy
      text: "Applying…"
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }

    PanelSeparator {}

    PanelSectionHeader {
      width: card.contentWidth
      label: Theme.name === "wallpaper" ? "Wallpaper" : "Wallpaper · " + Theme.name
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

      WheelHandler {
        onWheel: function (event) {
          const delta = event.angleDelta.x !== 0 ? event.angleDelta.x : -event.angleDelta.y
          const max = Math.max(0, wallpapers.contentWidth - wallpapers.width)
          wallpapers.contentX = Math.max(0, Math.min(max, wallpapers.contentX - delta / 2))
          event.accepted = true
        }
      }

      PanelList {
        visible: AppearanceHost && AppearanceHost.library && AppearanceHost.library.length === 0
        anchors.centerIn: parent
        width: Style.space(200)
        model: []
        emptyText: (AppearanceHost && AppearanceHost.libraryProc && AppearanceHost.libraryProc.running) ? "Loading wallpapers…" : "No wallpapers found"
        rowSpacing: Style.space(2)
      }
    }

    Row {
      width: card.contentWidth
      spacing: Style.space(6)
      visible: !!AppearanceHost

      TextButton {
        visible: !root.hasGenerated
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
      visible: AppearanceHost && Array.isArray(AppearanceHost.rows) && AppearanceHost.rows.length > 0
      label: "Presets"
      action: AppearanceHost.pinned ? "Unpin" : "Pin"
      onActionTriggered: AppearanceHost.setPinned && AppearanceHost.setPinned(!AppearanceHost.pinned)
    }

    Column {
      width: card.contentWidth
      spacing: Style.space(1)
      visible: AppearanceHost && Array.isArray(AppearanceHost.rows) && AppearanceHost.rows.length > 0

      Repeater {
        model: AppearanceHost.rows

        delegate: ThemeRow {
          required property var modelData
          width: parent.width
          label: modelData && modelData.name ? String(modelData.name) : ""
          colors: modelData ? modelData.colors : []
          mode: modelData ? modelData.mode : ""
          selected: !!(modelData && modelData.selected)
          favorite: !!(modelData && modelData.favorite)
          onClicked: AppearanceHost && AppearanceHost.setTheme && AppearanceHost.setTheme(modelData && modelData.name ? modelData.name : "")
          onFavoriteToggled: AppearanceHost && AppearanceHost.toggleFavorite && AppearanceHost.toggleFavorite(modelData && modelData.name ? modelData.name : "")
        }
      }
    }

    PanelSeparator {}

    Toggle {
      width: card.contentWidth
      visible: !!AppearanceHost
      label: "Glass blur"
      description: "Blur and refract the shell surfaces"
      checked: AppearanceHost ? !!AppearanceHost.glass : false
      onToggled: AppearanceHost && AppearanceHost.toggleGlass && AppearanceHost.toggleGlass()
    }

    PanelSectionHeader {
      width: card.contentWidth
      label: "Wallpaper palette"
    }

    ButtonGroup {
      width: card.contentWidth
      model: ["auto", "light", "dark"]
      currentIndex: root.wallpaperModeIndex()
      onActivated: function (index) {
        AppearanceHost.setWallpaperMode(["auto", "light", "dark"][index])
      }
    }

    PanelSectionHeader {
      width: card.contentWidth
      label: "Rotate wallpapers"
    }

    ButtonGroup {
      width: card.contentWidth
      model: ["Off", "30m", "2h", "6h"]
      currentIndex: root.rotationIndex()
      onActivated: function (index) {
        AppearanceHost.setRotation([0, 30, 120, 360][index])
      }
    }

    PanelSectionHeader {
      width: card.contentWidth
      label: "Bar background"
    }

    ButtonGroup {
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
      visible: AppearanceHost && AppearanceHost.lastError && String(AppearanceHost.lastError) !== ""
      text: AppearanceHost ? String(AppearanceHost.lastError) : ""
      color: Theme.danger
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
      renderType: Text.NativeRendering
    }

    Button {
      width: card.contentWidth
      label: "Theme doctor"
      value: "Check"
      glyph: Util.palette
      navigational: false
      onClicked: Commands.runQuoted("kitty", ["-e", "theme", "doctor"])
    }
  }
}
