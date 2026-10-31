pragma Singleton

import QtQuick
import Quickshell
import ".."

QtObject {
  id: root

  property bool shown: false

  function toggle() { root.shown = !root.shown }
  function show() { root.shown = true }
  function hide() { root.shown = false }
}
