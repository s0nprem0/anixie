import QtQuick
import Quickshell

// Global shortcuts, as Wayland events the shell already listens for. The binds
// are in hyprland/lua.nix as `hl.dsp.global("quickshell:<name>")`.
Item {
  // The menu's keys, as Hyprland global shortcuts rather than commands. A bind
  // that runs `menu` starts a process, which starts `quickshell ipc`, which is a
  // Qt application starting up to deliver one message — about 140ms before the
  // shell has even heard of the keypress. A global shortcut is a Wayland event
  // the shell is already listening for. The binds are in hyprland/lua.nix, as
  // `hl.dsp.global("quickshell:<name>")`.
  GlobalShortcut {
    name: "menu"
    description: "Open the menu"
    onPressed: MenuHost.open("")

    // Builds the menu's singleton and starts the desktop-entry scan now, rather
    // than on the first keypress (see MenuHost.warm).
    Component.onCompleted: MenuHost.warm()
  }

  GlobalShortcut {
    name: "menu-capture"
    description: "Open the capture menu"
    onPressed: MenuHost.open("Capture")
  }
}
