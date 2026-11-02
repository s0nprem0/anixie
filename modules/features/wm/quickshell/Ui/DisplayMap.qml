import QtQuick
import ".."

// The physical arrangement, drawn from Hyprland's own coordinates.
//
// A row of "Left of others" options makes the user hold the layout in their
// head. This draws it: one rectangle per extended output, scaled to fit the
// panel, in the place the compositor has put it. Mirrored outputs are left out
// because they do not occupy a place of their own.
Item {
  id: root

  property var outputs: []

  readonly property var placed: {
    const list = Array.isArray(root.outputs) ? root.outputs : []
    const out = []
    for (let i = 0; i < list.length; i++) {
      const output = list[i]
      if (output.disabled === true) continue
      if (String(output.mirrorOf || "none") !== "none") continue
      out.push(output)
    }
    return out
  }

  // One box per output, already mapped into this item's pixels. Rebuilt from
  // the live coordinates, so applying a placement redraws the map.
  readonly property var boxes: {
    const list = root.placed
    if (list.length === 0) return []

    let minX = Infinity
    let minY = Infinity
    let maxX = -Infinity
    let maxY = -Infinity
    for (let i = 0; i < list.length; i++) {
      const output = list[i]
      const scale = Number(output.scale || 1)
      const width = Number(output.width || 0) / (scale > 0 ? scale : 1)
      const height = Number(output.height || 0) / (scale > 0 ? scale : 1)
      minX = Math.min(minX, Number(output.x || 0))
      minY = Math.min(minY, Number(output.y || 0))
      maxX = Math.max(maxX, Number(output.x || 0) + width)
      maxY = Math.max(maxY, Number(output.y || 0) + height)
    }

    const pad = Style.space(2)
    const spanX = Math.max(1, maxX - minX)
    const spanY = Math.max(1, maxY - minY)
    const availableWidth = Math.max(0, root.width - pad * 2)
    const availableHeight = Math.max(0, root.height - pad * 2)
    const scale = Math.min(availableWidth / spanX, availableHeight / spanY)
    const offsetX = pad + (availableWidth - spanX * scale) / 2 - minX * scale
    const offsetY = pad + (availableHeight - spanY * scale) / 2 - minY * scale

    const out = []
    for (let i = 0; i < list.length; i++) {
      const output = list[i]
      const outputScale = Number(output.scale || 1)
      const width = Number(output.width || 0) / (outputScale > 0 ? outputScale : 1)
      const height = Number(output.height || 0) / (outputScale > 0 ? outputScale : 1)
      out.push({
        name: String(output.name),
        label: /^(eDP|LVDS|DSI)/.test(String(output.name)) ? "Laptop" : String(output.name),
        focused: output.focused === true,
        x: offsetX + Number(output.x || 0) * scale,
        y: offsetY + Number(output.y || 0) * scale,
        width: Math.max(1, width * scale),
        height: Math.max(1, height * scale)
      })
    }
    return out
  }

  // A single screen has no arrangement to show, and an empty strip would only
  // push the controls down. Based on the inputs, not on `boxes`: those are
  // measured against this item's height, and reading them here would make the
  // height and the boxes depend on each other.
  readonly property bool useful: root.placed.length > 1

  visible: root.useful
  implicitHeight: root.useful ? Style.space(88) : 0
  height: implicitHeight

  Repeater {
    model: root.boxes

    delegate: Item {
      required property var modelData

      x: modelData.x
      y: modelData.y
      width: modelData.width
      height: modelData.height

      Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: modelData.focused
          ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, Style.control.hoverFillAlpha)
          : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.hoverFillAlpha * 0.4)
        border.color: modelData.focused ? Theme.primary : Theme.border
        border.width: Style.strokeWidth
      }

      Text {
        anchors.centerIn: parent
        width: parent.width - Style.space(6)
        text: modelData.label
        color: modelData.focused ? Theme.primary : Theme.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.weight: modelData.focused ? Font.DemiBold : Font.Normal
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        renderType: Text.NativeRendering
      }
    }
  }
}
