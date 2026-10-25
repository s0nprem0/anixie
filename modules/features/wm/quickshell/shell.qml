//@ pragma UseQApplication
import QtQuick
import Quickshell
import "Ui"
import "components"

// Blocky status bar in five sections. `center` is pinned to the exact middle of
// the bar, and centerBegin/centerEnd hang off its edges so they grow outward
// instead of shifting the clock off centre.
//
// The bar runs on whichever edge bar.json names. On a side edge it becomes a
// column, the modules drop their labels, and the five sections run top-to-bottom
// instead of left-to-right — so "left" means the start of the bar, which is the
// top when it is vertical.
//
// The surfaces, the one-off overlays, the notification popups, the IPC targets
// and the shortcuts each live in their own component. This file is the shell's
// assembly point.
ShellRoot {
  id: shell

  ShellLayers {}

  // The low-battery warning. Lives on the shell rather than on the bar's readout
  // so it keeps working regardless of which modules the bar is showing.
  PowerAlert {}

  ShellOverlays {}
  NotificationPopups {}
  PickerLayer {}
  ShellIpc {}
  ShellShortcuts {}
}
