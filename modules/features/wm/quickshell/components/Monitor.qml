import QtQuick
import ".."
import "../Ui"
import Quickshell
import Quickshell.Io

// Display and keyboard brightness. The wheel adjusts the display from the bar;
// left click opens a popup with a slider for each.
//
// Reads come from sysfs, writes go through brightnessctl. That split is not
// arbitrary: sysfs brightness files are root-owned, and brightnessctl is what
// carries the udev rules that let a user write them.
//
// Devices are named rather than pathed in settings, since brightnessctl wants
// the device name anyway and the two sysfs classes differ only by prefix.
BarWidget {
  id: root

  // Reachable by hotkey as well as by click.
  Component.onCompleted: PanelRegistry.register("display", readout, controls)

  readonly property string displayDevice: String(root.setting("device", "amdgpu_bl1"))
  readonly property string keyboardDevice: String(root.setting("keyboard", "asus::kbd_backlight"))
  readonly property int step: Number(root.setting("step", 5))

  readonly property string displayPath: "/sys/class/backlight/" + root.displayDevice
  readonly property string keyboardPath: "/sys/class/leds/" + root.keyboardDevice

  // sysfs reads go through FileView, whose text() throws until the first read
  // lands, so every access is funnelled through these.
  function readNum(view, fallback) {
    try {
      const n = parseInt(String(view.text()).trim(), 10)
      return isFinite(n) ? n : fallback
    } catch (e) {
      return fallback
    }
  }

  readonly property int value: root.readNum(displayValueView, -1)
  readonly property int maximum: root.readNum(displayMaxView, 0)
  readonly property bool present: root.maximum > 0
  readonly property int percent: root.present ? Math.round(root.value * 100 / root.maximum) : 0

  // The global text size as a percentage, which is how the `textsize` command
  // states it and how the row beside the stepper reads it.
  readonly property int textSize: Math.round(Style.textScale * 100)

  readonly property int keyboardValue: root.readNum(keyboardValueView, -1)
  readonly property int keyboardMax: root.readNum(keyboardMaxView, 0)
  readonly property bool keyboardPresent: root.keyboardMax > 0
  readonly property int keyboardPercent: root.keyboardPresent
    ? Math.round(root.keyboardValue * 100 / root.keyboardMax)
    : 0

  function setDisplay(percent) {
    if (!root.present) return
    displaySet.command = ["brightnessctl", "--device", root.displayDevice,
                          "set", String(Math.round(percent * root.maximum / 100))]
    displaySet.running = true
  }

  function setKeyboard(percent) {
    if (!root.keyboardPresent) return
    keyboardSet.command = ["brightnessctl", "--device", root.keyboardDevice,
                           "set", String(Math.round(percent * root.keyboardMax / 100))]
    keyboardSet.running = true
  }

  function adjust(delta) {
    if (!root.present) return
    const next = Math.max(0, Math.min(100, root.percent + (delta > 0 ? root.step : -root.step)))
    if (next !== root.percent) root.setDisplay(next)
  }

  visible: root.present && !root.vertical
  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  BarIconButton {
    id: readout
    anchors.centerIn: parent
    text: Util.sun
    // Icon only; the level is in the tooltip and the OSD shows it while it changes.
    labelText: ""
    tooltipText: "Brightness " + root.percent + "% · scroll to change"

    onPressed: function (button) {
      if (button === Qt.LeftButton || button === Qt.MiddleButton) {
        PanelHost.toggle(readout, controls)
      }
    }
    onWheelMoved: function (delta) {
      root.adjust(delta)
    }
  }

  Process { id: displaySet }
  Process { id: keyboardSet }

  FileView {
    id: displayValueView
    path: root.displayPath + "/brightness"
    printErrors: false
    watchChanges: true
    blockLoading: true
  }

  FileView {
    id: displayMaxView
    path: root.displayPath + "/max_brightness"
    printErrors: false
    blockLoading: true
  }

  FileView {
    id: keyboardValueView
    path: root.keyboardPath + "/brightness"
    printErrors: false
    watchChanges: true
    blockLoading: true
  }

  FileView {
    id: keyboardMaxView
    path: root.keyboardPath + "/max_brightness"
    printErrors: false
    blockLoading: true
  }

  Component {
    id: controls

    Panel {
      id: card
      title: "Display"
      maxWidth: Style.space(320)

      PanelRow {
        id: displayRow
        width: card.contentWidth
        hasControl: true
        label: "Brightness"
        value: root.percent + "%"

        Slider {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: displayRow.controlWidth
          from: 0
          to: 100
          stepSize: 1
          enabled: root.present
          value: root.percent
          onMoved: root.setDisplay(value)
        }
      }

      // Only for hardware that has one; the device is named in settings so a
      // machine without a backlit keyboard simply shows nothing here.
      PanelRow {
        id: keyboardRow
        width: card.contentWidth
        hasControl: true
        visible: root.keyboardPresent
        height: visible ? implicitHeight : 0
        label: "Keyboard"
        value: root.keyboardPercent + "%"

        Slider {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: keyboardRow.controlWidth
          from: 0
          to: 100
          stepSize: 1
          enabled: root.keyboardPresent
          value: root.keyboardPercent
          onMoved: root.setKeyboard(value)
        }
      }

      PanelSeparator {}

      PanelSectionHeader {
        width: card.contentWidth
        label: "Text"
      }

      // Text size belongs here rather than in a settings panel of its own: it is
      // what you reach for when something is hard to read, and this is where the
      // other "make the screen comfortable" controls already are.
      PanelRow {
        id: textSizeRow
        width: card.contentWidth
        hasControl: true
        label: "Text size"
        value: root.textSize + "%"

        NumberField {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: textSizeRow.controlWidth
          from: 80
          to: 200
          step: 10
          // Seeded once rather than bound. A stepper writes its own `value` when
          // it is pressed, which destroys any binding on it, and a binding that
          // silently stops applying is worse than no binding at all. The value
          // shown beside the label is read from the scale directly, so it stays
          // the truth whatever happens here.
          value: root.textSize
          onChanged: function (next) {
            Style.setTextScale(next / 100)
            Commands.runQuoted("textsize", ["set", String(Math.round(next))])
          }
        }
      }
    }
  }
}
