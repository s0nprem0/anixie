import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."
import "../components"

// The one-off windows that do not belong to a bar or a screen model: the polkit
// prompt, the OSD, the dock and the capture preview.
Item {
  // The polkit prompt. A surface of its own rather than anything to do with the
  // bar: a privilege request is not a bar event, and this has to cover the whole
  // output and hold the keyboard for as long as it is up.
  //
  // It only takes keyboard focus while it is showing. Holding it permanently
  // would keep the compositor from ever delivering keys to windows underneath.
  PanelWindow {
    id: polkitWindow
    screen: Screens.focused

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    visible: PolkitHost.awaiting

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-polkit"
    WlrLayershell.keyboardFocus: PolkitHost.awaiting
      ? WlrKeyboardFocus.Exclusive
      : WlrKeyboardFocus.None

    PolkitPrompt {
      anchors.fill: parent
      message: PolkitHost.message
      prompt: PolkitHost.prompt
      detail: PolkitHost.detail
      detailIsError: PolkitHost.detailIsError

      onSubmitted: function (value) { PolkitHost.submit(value) }
      onCancelled: PolkitHost.cancel()
    }
  }

  // The on-screen display for volume, microphone and brightness. Anchored to
  // the bottom edge alone, which centres a layer surface on the axis it does
  // not anchor, so the window is only as wide as the card and cannot swallow
  // clicks across the whole width of the screen.
  PanelWindow {
    id: osdWindow
    screen: OsdHost.screenName !== "" ? (Screens.byName(OsdHost.screenName) || Screens.focused) : Screens.focused

    // Bar geometry is resolved for this output rather than assumed from the
    // global bar context. The fallback keeps the previous behaviour when a bar
    // has not registered yet.
    readonly property var osdBar: PanelHost.barFor(osdWindow.screen ? osdWindow.screen.name : "")
    readonly property string osdBarPosition: {
      const bar = osdWindow.osdBar
      const screen = osdWindow.screen
      if (bar && screen) {
        try {
          const window = bar.Window && bar.Window.window ? bar.Window.window : null
          if (window) {
            if (window.y <= screen.y + 1) return "top"
            if (window.y + window.height >= screen.y + screen.height - 1) return "bottom"
            if (window.x <= screen.x + 1) return "left"
            if (window.x + window.width >= screen.x + screen.width - 1) return "right"
          }
        } catch (e) {
        }
      }
      return BarContext.position
    }
    readonly property bool osdOnTop: OsdHost.position === "top"
      || (OsdHost.position === "bar" && osdWindow.osdBarPosition === "top")
    readonly property real osdBarExtent: (osdWindow.osdBarPosition === "left" || osdWindow.osdBarPosition === "right")
      ? Style.bar.sizeVertical
      : Style.bar.sizeHorizontal

    anchors.top: osdWindow.osdOnTop
    anchors.bottom: !osdWindow.osdOnTop
    margins.top: osdWindow.osdOnTop ? osdWindow.osdBarExtent + Style.space(24) : 0
    margins.bottom: osdWindow.osdOnTop ? 0 : osdWindow.osdBarExtent + Style.space(24)
    implicitWidth: osdCard.implicitWidth
    implicitHeight: osdCard.implicitHeight

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    // Keep the surface mapped while it fades out, then let it go. Binding
    // `visible` to `shown` alone would unmap it on the first frame of the fade.
    visible: OsdHost.opened || osdCard.opacity > 0

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Osd {
      id: osdCard
      anchors.fill: parent
      icon: OsdHost.icon
      message: OsdHost.message
      hasProgress: OsdHost.hasProgress
      value: OsdHost.value
      maxValue: OsdHost.maxValue
      mediaOsd: OsdHost.mediaOsd

      opacity: OsdHost.opened ? 1 : 0
      scale: OsdHost.opened ? 1 : 0.96
      transformOrigin: Item.Center
      Behavior on opacity {
        NumberAnimation { duration: Style.duration(Style.motion.fast); easing.type: Easing.OutCubic }
      }
      Behavior on scale {
        NumberAnimation { duration: Style.duration(Style.motion.fast); easing.type: Easing.OutCubic }
      }
    }
  }

  // The dock. Left edge, reserving a strip like the bar does, so windows are laid
  // out beside it rather than running underneath — a dock that windows slide
  // under would be worse than no dock at all.
  // Edge reveal for the auto-hidden dock: a thin strip on the left that brings
  // the dock back on hover. It costs no exclusive zone, so it never pushes
  // windows around.
  PanelWindow {
    id: dockEdgeReveal
    screen: dockScreen

    anchors.top: true
    anchors.bottom: true
    anchors.left: true

    implicitWidth: Style.space(12)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    visible: !DockHost.shown && DockHost.autoHide

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-dock-edge"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onEntered: DockHost.show()
    }
  }

  //
  // `Ignore` is not used here, unlike the popups. The bar had to state its zone
  // as a size because exclusionMode left hyprctl reporting no reservation at
  // all, and the same is true of this window; an invisible-but-present dock must
  // not cost screen space when it is closed, so the zone follows `shown`.
  PanelWindow {
    id: dockWindow
    screen: dockScreen

    anchors.top: true
    anchors.bottom: true
    anchors.left: true

    exclusiveZone: DockHost.shown ? dockWindow.dockWidth : 0
    visible: DockHost.shown

    color: Theme.surface

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-dock"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Stated here rather than measured from the content. Measuring it meant
    // asking the content column for a width that the column then took from the
    // window, and the two agreed on nothing at all: the dock came up one pixel
    // wide and Hyprland reserved one pixel.
    readonly property real dockWidth: Style.space(360)
    implicitWidth: dockWindow.dockWidth

    Dock {
      anchors.fill: parent
    }
  }

  // Workspace overview. A full-screen overlay listing workspaces and their
  // windows. Hyprland-only for now (gated by CompositorHost).
  PanelWindow {
    id: workspaceOverviewWindow
    screen: Screens.focused

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    visible: CompositorHost.supportsWorkspaceOverview && (WorkspaceOverviewHost.shown || workspaceOverviewContent.opacity > 0)

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-workspace-overview"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Declared behind the overview so interactive rows and controls keep their
    // own clicks; only clicks on empty overview background dismiss it.
    MouseArea {
      anchors.fill: parent
      z: -1
      onClicked: WorkspaceOverviewHost.hide()
    }

    WorkspaceOverview {
      id: workspaceOverviewContent
      anchors.fill: parent

      opacity: WorkspaceOverviewHost.shown ? 1 : 0
      scale: WorkspaceOverviewHost.shown ? 1 : 0.97
      Behavior on opacity {
        NumberAnimation { duration: Style.duration(Style.motion.base); easing.type: Easing.InOutCubic }
      }
      Behavior on scale {
        NumberAnimation { duration: Style.duration(Style.motion.base); easing.type: Easing.InOutCubic }
      }
    }
  }

  // The screenshot preview. Bottom right, over the desktop, gone on its own after
  // ten seconds unless it is pinned.
  //
  // `Ignore` for the exclusive zone and `None` for the keyboard, like the popups:
  // it floats over whatever is there and must not push windows around or take the
  // keyboard from the window being worked in. Only the two buttons want clicks,
  // and they take them as buttons rather than by the window claiming input.
  PanelWindow {
    id: capturePreviewWindow
    screen: Screens.focused

    readonly property var captureBar: PanelHost.barFor(capturePreviewWindow.screen ? capturePreviewWindow.screen.name : "")
    readonly property string captureBarPosition: {
      const bar = capturePreviewWindow.captureBar
      const screen = capturePreviewWindow.screen
      if (bar && screen) {
        try {
          const window = bar.Window && bar.Window.window ? bar.Window.window : null
          if (window) {
            if (window.y <= screen.y + 1) return "top"
            if (window.y + window.height >= screen.y + screen.height - 1) return "bottom"
            if (window.x <= screen.x + 1) return "left"
            if (window.x + window.width >= screen.x + screen.width - 1) return "right"
          }
        } catch (e) {
        }
      }
      return BarContext.position
    }

    anchors.right: true
    anchors.bottom: true
    // The same clearance the notifications get, from the other corner.
    margins.right: capturePreviewWindow.captureBarPosition === "right"
      ? Style.bar.sizeVertical + Style.space(24)
      : Style.space(24)
    margins.bottom: capturePreviewWindow.captureBarPosition === "bottom"
      ? Style.bar.sizeHorizontal + Style.space(24)
      : Style.space(24)
    implicitWidth: previewCard.implicitWidth
    implicitHeight: previewCard.implicitHeight

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    visible: CapturePreview.shown

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-capture-preview"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    CapturePreviewCard {
      id: previewCard
      anchors.fill: parent
      source: CapturePreview.path
      revision: CapturePreview.revision
      pinned: CapturePreview.pinned
      onOpened: {
        const path = CapturePreview.path
        if (path !== "") Commands.run("if [ -f " + Util.shellQuote(path) + " ]; then xdg-open " + Util.shellQuote(path) + "; fi")
      }
      onAnnotated: {
        const path = CapturePreview.path
        if (path !== "") {
          Commands.run("if [ -f " + Util.shellQuote(path) + " ]; then wl-copy --type image/png < " + Util.shellQuote(path) + "; fi")
          CapturePreview.reveal(path)
        }
      }
      onPinToggled: CapturePreview.togglePin()
      onDismissed: CapturePreview.hide()
    }
  }
}
