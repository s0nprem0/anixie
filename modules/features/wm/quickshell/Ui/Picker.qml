import QtQuick
import Quickshell
import ".."

// The picker's contents: a search field, the list, and a hint row.
//
// Fills the whole window rather than sitting in it, so that the curtain behind
// it — which is what makes a click anywhere dismiss the picker instead of going
// through to the window underneath — is part of the same thing.
//
// Everything is drawn from PickHost, which is where the entries, the filter and
// the selection live. This file is the view of that and holds no state of its
// own beyond the field's text, which it pushes into the host on every keystroke.

Item {
  id: root

  // The card. Centred, and narrower than the output so there is a curtain to
  // click, which is the gesture for "not this one".
  Rectangle {
    id: card

    anchors.centerIn: parent
    width: Math.min(root.width * 0.6, Style.space(640))
    height: cardColumn.implicitHeight

    radius: Theme.cornerRadius
    color: Theme.surface
    border.color: Theme.muted
    border.width: 1

    Column {
      id: cardColumn

      anchors.fill: parent
      spacing: 0

      // The search field. Its own row rather than a bare input so the prompt —
      // "theme", "clipboard", "record audio" — is visible: the picker is
      // shared by a dozen callers, and without the prompt there is nothing to
      // tell you what this list is for.
      Item {
        id: searchRow

        width: parent.width
        height: Style.space(48)

        Text {
          id: promptText

          anchors.left: parent.left
          anchors.leftMargin: Style.space(16)
          anchors.verticalCenter: parent.verticalCenter

          text: PickHost.title
          color: Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
        }

        TextInput {
          id: search

          anchors.left: promptText.visible ? promptText.right : parent.left
          anchors.leftMargin: promptText.visible ? Style.space(8) : Style.space(16)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(16)
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(0, parent.width - anchors.leftMargin - anchors.rightMargin)

          color: Theme.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          selectionColor: Theme.primary
          selectedTextColor: Theme.bg
          clip: true

          text: PickHost.query
          onTextChanged: PickHost.setQuery(text)

          // Returned to on every keystroke, so the selection is always visible
          // even after a long search moved it off the first row.
          function refocus() {
            forceActiveFocus()
            cursorPosition = text.length
          }

          onActiveFocusChanged: if (activeFocus) cursorPosition = text.length

          Keys.onPressed: function (event) {
            const key = event.key

            if (key === Qt.Key_Return || key === Qt.Key_Enter) {
              PickHost.accept()
              event.accepted = true
              return
            }

            if (key === Qt.Key_Escape) {
              PickHost.dismiss()
              event.accepted = true
              return
            }

            // Up and down are the list's, not the field's: a picker is navigated
            // with the same keys whatever is in the field, so they must not move
            // a caret through the query.
            if (key === Qt.Key_Down || (key === Qt.Key_N && (event.modifiers & Qt.ControlModifier))) {
              PickHost.move(1)
              event.accepted = true
              return
            }

            if (key === Qt.Key_Up || (key === Qt.Key_P && (event.modifiers & Qt.ControlModifier))) {
              PickHost.move(-1)
              event.accepted = true
              return
            }

            if (key === Qt.Key_PageDown) {
              PickHost.page(1)
              event.accepted = true
              return
            }

            if (key === Qt.Key_PageUp) {
              PickHost.page(-1)
              event.accepted = true
              return
            }

            // Tab walks the list rather than moving focus: there is nothing
            // else on this surface to focus, and a Tab that does nothing reads
            // as a broken one.
            if (key === Qt.Key_Tab) {
              PickHost.move(event.modifiers & Qt.ShiftModifier ? -1 : 1)
              event.accepted = true
              return
            }
          }

          Component.onCompleted: refocus()
        }

        Rectangle {
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.leftMargin: Style.space(16)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(16)
          height: 1
          color: Theme.muted
        }
      }

      // The list. Hidden in input mode, where the field is the whole picker.
      ListView {
        id: list

        visible: !PickHost.isInput
        width: parent.width
        height: visible
          ? Math.min(PickHost.results.length, PickHost.maxVisible) * Style.space(32)
          : 0
        clip: true
        model: PickHost.results
        currentIndex: PickHost.selected
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
          id: verticalBar
          visible: list.contentHeight > list.height
        }

        delegate: Item {
          id: rowHolder

          required property int index
          required property var modelData

          width: list.width
          height: Style.space(32)

          PickRow {
            anchors.fill: parent
            label: rowHolder.modelData.row.label !== undefined ? String(rowHolder.modelData.row.label) : ""
            group: PickHost.grouped && rowHolder.modelData.row.group !== undefined
              ? String(rowHolder.modelData.row.group)
              : ""
            state: rowHolder.modelData.row.state !== undefined ? String(rowHolder.modelData.row.state) : ""
            icon: rowHolder.modelData.row.icon !== undefined ? String(rowHolder.modelData.row.icon) : ""
            positions: rowHolder.modelData.positions
            selected: rowHolder.index === PickHost.selected

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onClicked: {
                PickHost.selected = rowHolder.index
                PickHost.accept()
              }
              onEntered: PickHost.selected = rowHolder.index
            }
          }
        }
      }

      // Nothing matched. Said plainly rather than showing an empty box, which
      // looks like a picker that failed to load.
      Text {
        id: emptyNote

        visible: !PickHost.isInput && !PickHost.hasResults
        width: parent.width
        height: visible ? Style.space(48) : 0
        text: "Nothing matches"
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }

      // The keys. Every picker in the shell is driven the same way, so the
      // bindings are worth stating once here rather than being discovered.
      Item {
        width: parent.width
        height: Style.space(28)

        Rectangle {
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.leftMargin: Style.space(16)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(16)
          height: 1
          color: Theme.muted
        }

        Text {
          anchors.centerIn: parent
          text: PickHost.isInput ? "↵ to accept · esc to dismiss" : "↑↓ to choose · ↵ to run · esc to dismiss"
          color: Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  // The curtain. Only as wide as the card, so a click beside the card dismisses
  // without covering it.
  MouseArea {
    anchors.fill: parent
    onClicked: PickHost.dismiss()
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.35)
    z: -1
  }

  // Shown again on every open. A window that has had focus once does not take it
  // back on its own, so without this the second use of any picker would open
  // with the keyboard still going to whatever had it last.
  Connections {
    target: PickHost
    function onShownChanged() {
      if (PickHost.shown) search.refocus()
    }
  }
}