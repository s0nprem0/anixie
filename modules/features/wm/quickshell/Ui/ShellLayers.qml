import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."
import "../components"

// Per-output layer surfaces: the background, the idle screensaver, the display
// name overlay and every bar. Each sits on its own screen and is destroyed and
// rebuilt when Variants' model changes.
Item {
  id: layers

  // Rebuilt when the bar switches edges. Layer surfaces cannot be re-anchored
  // reliably after they are mapped, so the window is recreated instead: the
  // position in the model makes Variants destroy and rebuild each per-screen bar.
  readonly property var barSurfaces: {
    const out = []
    const screens = Quickshell.screens
    for (let i = 0; i < screens.length; i++) {
      out.push({ screen: screens[i], position: BarContext.position })
    }
    return out
  }

  // The desktop background. One layer-shell surface per output, on the
  // Background layer so windows sit over it. It takes input only for the
  // desktop context menu: the surface claims the pointer, but windows are above
  // the background layer and keep theirs, and a left click still goes nowhere
  // because the MouseArea accepts only the right button. Each output has its
  // own path and video flag; video wallpapers are owned by mpvpaper, so the
  // surface on that output steps aside.
  Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
      required property var modelData
      screen: modelData

      implicitWidth: modelData.width
      implicitHeight: modelData.height

      anchors.top: true
      anchors.bottom: true
      anchors.left: true
      anchors.right: true

      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      mask: Region {
        item: backgroundInput
      }
      visible: !BackgroundHost.videoFor(String(modelData.name))

      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.namespace: "quickshell-background"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      BackgroundSurface {
        anchors.fill: parent
        source: BackgroundHost.videoFor(String(modelData.name))
          ? ""
          : BackgroundHost.pathFor(String(modelData.name))
        revision: BackgroundHost.revision
      }

      MouseArea {
        id: backgroundInput
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: function (mouse) {
          ContextMenuHost.openAt([
            { label: "Terminal", glyph: Util.keyboard, action: function () { Commands.app("kitty") } },
            { label: "Files", glyph: Util.menu, action: function () { Commands.app("thunar") } },
            { separator: true },
            { label: "Appearance", glyph: Util.palette, action: function () { Commands.run("appearance") } },
            { label: "Next theme", action: function () { Commands.run("theme next") } },
            { separator: true },
            { label: "Screen time & focus…", glyph: Util.clock, action: function () { Commands.run("screentime panel") } },
            { label: "Lock", glyph: Util.lock, action: function () { LockHost.lock() } }
          ], backgroundInput, mouse.x, mouse.y)
        }
      }
    }
  }

  // The idle screensaver. It covers every output and takes the keyboard while it
  // is up, so a key wakes it rather than reaching an application behind it. The
  // compositor's session lock, not this, is the security boundary; this hides the
  // desktop while the user is away and disappears on the first input.
  Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
      required property var modelData
      screen: modelData

      implicitWidth: modelData.width
      implicitHeight: modelData.height

      anchors.top: true
      anchors.bottom: true
      anchors.left: true
      anchors.right: true

      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      visible: IdleHost.screensaverShown && !LockHost.locked

      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "quickshell-screensaver"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

      Screensaver {
        anchors.fill: parent
        onWake: IdleHost.wake()
      }
    }
  }

  // The name of each output, on that output, for `monitors identify`. It draws
  // above everything but takes neither the keyboard nor the pointer: this is a
  // label on a screen, not a dialog, and needs no answer.
  Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
      id: identifyWindow
      required property var modelData
      screen: modelData

      implicitWidth: modelData.width
      implicitHeight: modelData.height

      anchors.top: true
      anchors.bottom: true
      anchors.left: true
      anchors.right: true

      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      visible: IdentifyHost.opened
      mask: Region {}

      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "quickshell-identify"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      readonly property string label:
        /^(eDP|LVDS|DSI)/.test(String(modelData.name)) ? "Laptop panel" : "External display"

      Rectangle {
        anchors.centerIn: parent
        width: identifyLabel.implicitWidth + Style.space(40)
        height: identifyLabel.implicitHeight + Style.space(28)
        radius: Theme.cornerRadius
        color: Theme.surface
        border.color: Theme.border
        border.width: Style.strokeWidth

        Text {
          id: identifyLabel
          anchors.centerIn: parent
          text: identifyWindow.label + "  ·  " + modelData.name
          color: Theme.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle * 2
          font.weight: Font.DemiBold
          renderType: Text.NativeRendering
        }
      }
    }
  }

  // One bar per connected screen. `Variants` builds and destroys them as
  // displays or the bar's edge change, and `screen: targetScreen` is what puts
  // each copy on its own output. Everything that hangs off a bar — panels, the
  // curtain, drag and drop — looks the bar up by screen name (see Ui/Screens.qml).
  Variants {
    model: layers.barSurfaces

    delegate: PanelWindow {
      id: bar
      required property var modelData
      // A screen can disappear between a hotplug event and Variants rebuilding
      // this delegate. Keep the window harmless for that frame rather than
      // reading a width off a screen object that is already gone.
      readonly property var targetScreen: modelData && modelData.screen ? modelData.screen : null
      screen: targetScreen

      // Edges are set from the position rather than by switching between four
      // blocks of anchors: a single anchors block can express any edge, and
      // clearing the ones that do not apply keeps Hyprland from seeing both.
      // A side bar spans top to bottom and is sized by width instead, a top or
      // bottom bar spans left to right and is sized by height.
      anchors {
        top: BarContext.vertical || BarContext.position === "top" ? true : false
        bottom: BarContext.vertical || BarContext.position === "bottom" ? true : false
        left: !BarContext.vertical || BarContext.position === "left" ? true : false
        right: !BarContext.vertical || BarContext.position === "right" ? true : false
      }

      // A side bar is as long as the screen and as wide as an icon; a top or bottom
      // bar is as wide as the screen and as tall as one row. Both dimensions are
      // stated rather than left to the anchors, because a window anchored top to
      // bottom is not given a height on its own. Each copy takes its size from its
      // own screen, so a laptop panel and an external display are not laid out to
      // the same width.
      implicitWidth: BarContext.vertical
        ? Style.bar.sizeVertical
        : (targetScreen ? targetScreen.width : 0)
      implicitHeight: BarContext.vertical
        ? (targetScreen ? targetScreen.height : 0)
        : Style.bar.sizeHorizontal

      color: "transparent"

      // The bar's thickness is reserved from the workspace, so Hyprland lays every
      // window out below it instead of underneath it.
      //
      // This has to be asked for as a size rather than through exclusionMode: the
      // bar used to set ExclusionMode.Ignore, which declares no zone at all, and
      // maximized windows took the full output height and ran under the bar. Since
      // the default background is a transparent "clear", the window showed straight
      // through it, which read as the bar and the window overlapping. Switching to
      // ExclusionMode.Normal did not fix it either — on this Quickshell it still
      // left hyprctl reporting "reserved: 0 0 0 0". Stating the zone directly does
      // register, and reports "reserved: 0 26 0 0".
      //
      // Stated as a size rather than left at exclusionMode's default of -1 (the
      // compositor guesses from the anchored edges), so the reserved strip always
      // matches the bar's own geometry rather than whatever Hyprland infers.
      //
      // Popups (PanelHost's panel and curtain, TooltipHost's window) keep the
      // default of no exclusive zone on purpose: they float over the desktop and
      // must not push windows around when they open.
      //
      // Zero while the bar is hidden, which is what gives the pixels back. The
      // window itself stays mapped: unmapping it would take the anchor every panel
      // hangs off with it, and a hotkey-opened panel would have nothing to attach
      // to. Hiding the contents is what makes it invisible.
      exclusiveZone: BarContext.shown
        ? (BarContext.vertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal)
        : 0

      // The panel popup anchors to this item rather than to whichever button was
      // used, because a popup resolves its anchor once, at creation. It cannot
      // anchor to the PanelWindow itself either: that is a QObject here, not an
      // item, so it has no coordinate space to place against. The tooltip has no
      // such need — it anchors to the button it describes directly.
      Item {
        id: barRoot
        anchors.fill: parent
      }

      // Registered by screen name rather than assigned to one shared host: every
      // output has a bar, and a panel belongs to the bar it was clicked on while
      // the hotkeys belong to the one under the pointer.
      Component.onCompleted: {
        PanelHost.registerBar(barRoot)
        BarDrag.registerBar(barRoot)
      }

      Component.onDestruction: {
        PanelHost.unregisterBar(barRoot)
        BarDrag.unregisterBar(barRoot)
      }

      Background {
        anchors.fill: parent
      }

      readonly property real gap: Style.space(2)

      // ---- start (left, or top when vertical) ----
      Section {
        anchors.top: BarContext.vertical ? parent.top : undefined
        anchors.left: BarContext.vertical ? undefined : parent.left
        anchors.horizontalCenter: BarContext.vertical ? undefined : undefined
        anchors.verticalCenter: BarContext.vertical ? undefined : parent.verticalCenter
        anchors.topMargin: BarContext.vertical ? bar.gap : undefined
        anchors.leftMargin: BarContext.vertical ? undefined : bar.gap
        name: "left"
        screenName: targetScreen ? targetScreen.name : ""
        entries: BarConfig.section("left")
      }

      // ---- centre ----
      Section {
        id: centerSection
        anchors.horizontalCenter: BarContext.vertical ? undefined : parent.horizontalCenter
        anchors.verticalCenter: BarContext.vertical ? parent.verticalCenter : undefined
        name: "center"
        screenName: targetScreen ? targetScreen.name : ""
        entries: BarConfig.section("center")
      }

      // ---- centerBegin: grows away from the centre group ----
      Section {
        anchors.right: BarContext.vertical ? undefined : centerSection.left
        anchors.bottom: BarContext.vertical ? centerSection.top : undefined
        anchors.verticalCenter: BarContext.vertical ? undefined : parent.verticalCenter
        anchors.rightMargin: BarContext.vertical ? undefined : bar.gap
        anchors.bottomMargin: BarContext.vertical ? bar.gap : undefined
        name: "centerBegin"
        screenName: targetScreen ? targetScreen.name : ""
        entries: BarConfig.section("centerBegin")
      }

      // ---- centerEnd ----
      Section {
        anchors.left: BarContext.vertical ? undefined : centerSection.right
        anchors.top: BarContext.vertical ? centerSection.bottom : undefined
        anchors.verticalCenter: BarContext.vertical ? undefined : parent.verticalCenter
        anchors.leftMargin: BarContext.vertical ? undefined : bar.gap
        anchors.topMargin: BarContext.vertical ? bar.gap : undefined
        name: "centerEnd"
        screenName: targetScreen ? targetScreen.name : ""
        entries: BarConfig.section("centerEnd")
      }

      // ---- end (right, or bottom when vertical) ----
      Section {
        anchors.bottom: BarContext.vertical ? parent.bottom : undefined
        anchors.right: BarContext.vertical ? undefined : parent.right
        anchors.verticalCenter: BarContext.vertical ? undefined : parent.verticalCenter
        anchors.bottomMargin: BarContext.vertical ? bar.gap : undefined
        anchors.rightMargin: BarContext.vertical ? undefined : bar.gap
        name: "right"
        screenName: targetScreen ? targetScreen.name : ""
        entries: BarConfig.section("right")
      }

      // The gap a release would fill. Full thickness of the bar so it reads as a
      // slot opening rather than a cursor drawn over the modules.
      Rectangle {
        id: dragIndicator

        visible: BarDrag.active && BarDrag.targetValid
        x: BarDrag.indicatorRect.x
        y: BarDrag.indicatorRect.y
        width: BarDrag.indicatorRect.width
        height: BarDrag.indicatorRect.height
        color: Theme.accent
        radius: 1
        z: 100
      }
    }
  }
}
