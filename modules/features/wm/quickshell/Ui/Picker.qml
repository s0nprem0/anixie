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
//
// Two things about the shape are deliberate. The card is sized once per request
// — from the entries the caller sent, not from what is left of them once the
// query has had its say — so narrowing a search fills the list in a card that
// stays where it is. And opening and closing are animated, with the window kept
// mapped until the fade is over (shell.qml asks `reveal`), so the launcher
// arrives and leaves rather than blinking on and off.

Item {
  id: root

  // One number drives the whole entrance: the dim, the card's own opacity, and
  // the few pixels the card rises. Reduce-motion collapses the duration to zero
  // and it is a cut, which is what that setting is for.
  property real reveal: PickHost.shown ? 1 : 0

  Behavior on reveal {
    NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
  }

  // The height of one row, in one place: the list's area and the rows themselves
  // both draw from it.
  readonly property int rowHeight: Style.space(32)

  // The dim behind everything, then the curtain, and only then the card.
  //
  // The order is the whole of the click handling. A sibling declared later is
  // drawn on top and takes input first, so with the curtain declared *after* the
  // card it sat over it and swallowed every click — the card's own rows could
  // not be clicked at all, and any click anywhere dismissed. Declared before it,
  // the card takes clicks first and the curtain only gets the ones that land
  // outside it, which is the gesture for "not this one".
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.35)
    opacity: root.reveal
  }

  MouseArea {
    anchors.fill: parent
    onClicked: {
      PickHost.dismiss()
    }
  }

  // The card. Centred, and narrower than the output so there is a curtain to
  // click, which is the gesture for "not this one".
  Rectangle {
    id: card

    anchors.centerIn: parent
    width: Math.min(root.width * 0.6, Style.space(640))
    height: cardColumn.implicitHeight

    // A dozen pixels up from where it settles, so the card rises as it appears.
    // Anchored to the centre it would otherwise fade in exactly in place, which
    // reads as a still image rather than something opening.
    opacity: root.reveal
    anchors.verticalCenterOffset: (1 - root.reveal) * Style.space(12)

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

        // The caller's placeholder, drawn behind the field so the caret sits
        // over it rather than under it, and only while the field is empty. A
        // caller that passes one gets a hint at what to type; the menu passes
        // none, and the title beside the field is what it shows instead.
        Text {
          anchors.left: search.left
          anchors.right: search.right
          anchors.verticalCenter: search.verticalCenter

          visible: search.text === "" && PickHost.placeholder !== ""
          text: PickHost.placeholder
          color: Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          elide: Text.ElideRight
          clip: true
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

      // The list's area, held open at a height of its own — taken from the
      // entries the caller sent rather than from the results — so that typing
      // narrows what is listed inside a card that keeps its size. Sized to the
      // results, the card would shrink under the query and the field would move
      // up the screen while it was being typed into.
      //
      // Input mode has no list at all: the field is the whole picker there.
      Item {
        id: listArea

        width: parent.width
        height: PickHost.isInput
          ? 0
          // At least one row even for an empty request, so that the note saying
          // so has somewhere to be drawn.
          : Math.max(1, Math.min(PickHost.entries.length, PickHost.maxVisible)) * root.rowHeight

        ListView {
          id: list

          visible: PickHost.hasResults
          anchors.fill: parent
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
            height: root.rowHeight

            PickRow {
              anchors.fill: parent
              label: rowHolder.modelData.row.label !== undefined ? String(rowHolder.modelData.row.label) : ""
              group: PickHost.groupOf(rowHolder.index)
              state: rowHolder.modelData.row.state !== undefined ? String(rowHolder.modelData.row.state) : ""
              icon: rowHolder.modelData.row.icon !== undefined ? String(rowHolder.modelData.row.icon) : ""
              preview: rowHolder.modelData.row.preview !== undefined ? String(rowHolder.modelData.row.preview) : ""
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

        // Nothing matched. Named with the query, because "nothing matches" on
        // its own leaves you wondering what it is that nothing matches. In the
        // same area as the list rather than a height of its own, so the card
        // does not jump as the last result goes.
        Text {
          id: emptyNote

          visible: !PickHost.hasResults
          anchors.fill: parent
          text: PickHost.query !== ""
            ? "Nothing matches \u201c" + PickHost.query + "\u201d"
            : "Nothing to show"
          color: Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
        }
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

        // How many of how many, once a query is narrowing the list and the
        // number is the thing being watched. Absent on an unfiltered menu, where
        // it would only count the list you can already see.
        Text {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(16)
          anchors.verticalCenter: parent.verticalCenter

          visible: !PickHost.isInput && PickHost.query !== ""
          text: PickHost.results.length + " / " + PickHost.entries.length
          color: Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
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