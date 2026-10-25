import QtQuick
import Quickshell
import ".."

// The clipboard window: the history on the left, what is selected on the right.
//
// The two panes are separate cards rather than one card split by a rule, which
// is the shape the reference uses and what makes the preview read as a different
// thing from the list. The preview card is present whenever there is a
// selection, including short entries: a card that appears and disappears as the
// selection moves would drag the list sideways under the pointer.
Item {
  id: root

  // One number drives the entrance: the dim, the cards' own opacity, and the few
  // pixels they rise. Reduce-motion collapses the duration to zero and it is a
  // cut, which is what that setting is for.
  property real reveal: ClipboardHost.shown ? 1 : 0

  Behavior on reveal {
    NumberAnimation { duration: Style.duration(Style.motion.fast); easing.type: Easing.OutCubic }
  }

  readonly property int listWidth: Style.space(300)
  readonly property int previewWidth: Style.space(380)
  readonly property int cardHeight: Math.max(
    Style.space(220),
    Math.min(Style.space(430), root.height - Style.space(72)))

  // The dim behind everything, then the curtain, and only then the cards.
  Rectangle {
    anchors.fill: parent
    color: Theme.curtain
    opacity: root.reveal
  }

  MouseArea {
    anchors.fill: parent
    onClicked: ClipboardHost.dismiss()
  }

  Row {
    id: cards

    // The cards take input above the curtain, not only pixels.
    z: 1

    anchors.centerIn: parent
    anchors.verticalCenterOffset: (1 - root.reveal) * Style.space(12)
    width: root.listWidth + (ClipboardHost.current ? root.previewWidth + spacing : 0)
    height: root.cardHeight
    spacing: Style.space(8)
    opacity: root.reveal

    // ---- the list ----
    Rectangle {
      id: listCard

      width: root.listWidth
      height: root.cardHeight
      radius: Theme.cornerRadius
      color: Theme.surface
      border.color: Theme.border
      border.width: Style.strokeWidth

      // A click on the card's own padding is not a click on the curtain. The
      // blocker sits under the content, so the controls keep their own events.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
      }

      Item {
        anchors.fill: parent
        anchors.margins: Style.space(12)

        Item {
          id: searchRow

          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: Style.space(40)

          TextInput {
            id: search

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            color: Theme.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            selectionColor: Theme.primary
            selectedTextColor: Theme.bg
            clip: true

            text: ClipboardHost.query
            onTextChanged: ClipboardHost.setQuery(text)

            function refocus() {
              forceActiveFocus()
              cursorPosition = text.length
            }

            onActiveFocusChanged: if (activeFocus) cursorPosition = text.length

            Keys.onPressed: function (event) {
              switch (event.key) {
              case Qt.Key_Up:
                ClipboardHost.move(-1)
                event.accepted = true
                break
              case Qt.Key_Down:
                ClipboardHost.move(1)
                event.accepted = true
                break
              case Qt.Key_PageUp:
                ClipboardHost.move(-8)
                event.accepted = true
                break
              case Qt.Key_PageDown:
                ClipboardHost.move(8)
                event.accepted = true
                break
              case Qt.Key_Home:
                ClipboardHost.first()
                event.accepted = true
                break
              case Qt.Key_End:
                ClipboardHost.last()
                event.accepted = true
                break
              case Qt.Key_Return:
              case Qt.Key_Enter:
                ClipboardHost.copyCurrent()
                event.accepted = true
                break
              case Qt.Key_Delete:
                ClipboardHost.deleteCurrent()
                event.accepted = true
                break
              case Qt.Key_Escape:
                ClipboardHost.dismiss()
                event.accepted = true
                break
              // There is no second focus stop in this window. Accepting Tab
              // keeps the field focused instead of handing the keyboard to
              // nothing, which would leave the popup untypeable.
              case Qt.Key_Tab:
              case Qt.Key_Backtab:
                event.accepted = true
                break
              }
            }

            Component.onCompleted: refocus()
          }

          Text {
            anchors.left: search.left
            anchors.right: search.right
            anchors.verticalCenter: search.verticalCenter

            visible: search.text === ""
            z: -1
            text: "search clipboard…"
            color: Theme.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            renderType: Text.NativeRendering
            elide: Text.ElideRight
          }

          Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: Style.strokeWidth
            color: Theme.separator
          }
        }

        Item {
          id: listArea

          anchors.top: searchRow.bottom
          anchors.topMargin: Style.space(8)
          anchors.bottom: footer.top
          anchors.bottomMargin: Style.space(8)
          anchors.left: parent.left
          anchors.right: parent.right

          ListView {
            id: list

            anchors.fill: parent
            clip: true
            model: ClipboardHost.filtered
            currentIndex: ClipboardHost.selected
            spacing: Style.space(2)
            boundsBehavior: Flickable.StopAtBounds
            rightMargin: Style.space(6)

            ScrollBar.vertical: ScrollBar {
              visible: list.contentHeight > list.height
            }

            delegate: Item {
              id: row

              required property int index
              required property var modelData

              readonly property bool chosen: ClipboardHost.selected === row.index
              readonly property string source:
                row.modelData.imagePath !== "" ? "file://" + row.modelData.imagePath : ""

              width: list.width - list.rightMargin
              height: row.modelData.image ? Style.space(40) : Style.space(30)

              Rectangle {
                anchors.fill: parent
                radius: Theme.cornerRadius
                color: row.chosen
                  ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.selectedFillAlpha)
                  : (rowMouse.containsMouse
                    ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.rowHoverAlpha)
                    : "transparent")
                Behavior on color { ColorAnimation { duration: Style.duration(Style.motion.fast) } }
              }

              Item {
                id: imageSlot

                visible: row.modelData.image
                width: Style.space(44)
                height: Style.space(30)
                anchors.left: parent.left
                anchors.leftMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                  anchors.fill: parent
                  radius: Theme.cornerRadius
                  color: Theme.bg
                  border.color: Theme.border
                  border.width: Style.strokeWidth
                  visible: row.source === ""
                }

                Image {
                  anchors.fill: parent
                  source: row.source
                  fillMode: Image.PreserveAspectFit
                  cache: false
                  smooth: true
                }
              }

              Text {
                id: labelText

                anchors.left: row.modelData.image ? imageSlot.right : parent.left
                anchors.leftMargin: Style.space(6)
                anchors.right: indicator.left
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter

                text: row.modelData.label
                color: row.chosen ? Theme.accent : Theme.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.weight: row.chosen ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
                renderType: Text.NativeRendering
              }

              // The reference marks the entries that have more to show. The
              // marker is the same promise the second pane keeps.
              Text {
                id: indicator

                anchors.right: parent.right
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter

                visible: row.modelData.image || row.modelData.label.length > 80
                  || ClipboardHost.isFile(row.modelData.label)
                text: "≡"
                color: row.chosen ? Theme.accent : Theme.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                renderType: Text.NativeRendering
              }

              MouseArea {
                id: rowMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                // The reference previews on hover and copies on click; the
                // same gesture lets a mouse read an entry before committing it.
                // onPositionChanged rather than onEntered: the list is rebuilt
                // under a stationary pointer on every keystroke, and an enter
                // event from a delegate that just appeared would pull the
                // selection away from the keyboard.
                onPositionChanged: ClipboardHost.select(row.index)
                onClicked: {
                  ClipboardHost.select(row.index)
                  ClipboardHost.copyCurrent()
                }
              }
            }
          }

          Text {
            anchors.fill: parent
            visible: ClipboardHost.filtered.length === 0
            text: ClipboardHost.query !== ""
              ? "Nothing matches \u201c" + ClipboardHost.query + "\u201d"
              : "Nothing in the clipboard"
            color: Theme.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
            renderType: Text.NativeRendering
          }
        }

        Item {
          id: footer

          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          height: Style.space(24)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: ClipboardHost.lastError !== ""
              ? ClipboardHost.lastError
              : ClipboardHost.filtered.length + (ClipboardHost.filtered.length === 1 ? " item" : " items")
            color: ClipboardHost.lastError !== "" ? Theme.danger : Theme.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.italic: ClipboardHost.lastError === ""
            elide: Text.ElideRight
            width: clearAll.left - Style.space(8)
            renderType: Text.NativeRendering
          }

          Text {
            id: clearAll

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "clear all"
            color: clearAllMouse.containsMouse ? Theme.danger : Theme.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            renderType: Text.NativeRendering

            MouseArea {
              id: clearAllMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: ClipboardHost.wipe()
            }
          }
        }
      }
    }

    // ---- the preview ----
    Rectangle {
      id: previewCard

      width: ClipboardHost.current ? root.previewWidth : 0
      height: root.cardHeight
      visible: ClipboardHost.current !== null
      radius: Theme.cornerRadius
      color: Theme.surface
      border.color: Theme.border
      border.width: Style.strokeWidth

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
      }

      Item {
        anchors.fill: parent
        anchors.margins: Style.space(12)

        Item {
          id: previewHeader

          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: Style.space(20)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Preview"
            color: Theme.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: ClipboardHost.typeLabel
            color: Theme.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            renderType: Text.NativeRendering
          }
        }

        Rectangle {
          id: previewBody

          anchors.top: previewHeader.bottom
          anchors.topMargin: Style.space(8)
          anchors.bottom: previewFooter.top
          anchors.bottomMargin: Style.space(8)
          anchors.left: parent.left
          anchors.right: parent.right
          radius: Theme.cornerRadius
          color: Theme.bg
          border.color: Theme.border
          border.width: Style.strokeWidth
          clip: true

          Image {
            anchors.fill: parent
            anchors.margins: Style.space(6)
            visible: ClipboardHost.previewKind === "image" && ClipboardHost.previewImage !== ""
            source: ClipboardHost.previewImage !== "" ? "file://" + ClipboardHost.previewImage : ""
            fillMode: Image.PreserveAspectFit
            cache: false
            smooth: true
          }

          Text {
            anchors.centerIn: parent
            visible: ClipboardHost.previewKind === "image" && ClipboardHost.previewImage === ""
            text: ClipboardHost.previewLoading ? "Decoding image…" : "No image"
            color: Theme.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            renderType: Text.NativeRendering
          }

          Flickable {
            id: previewFlick

            anchors.fill: parent
            anchors.margins: Style.space(6)
            visible: ClipboardHost.previewKind !== "image"
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: previewTextItem.height

            ScrollBar.vertical: ScrollBar {
              visible: previewFlick.contentHeight > previewFlick.height
            }

            Text {
              id: previewTextItem

              width: previewFlick.width
              text: ClipboardHost.previewText
              color: Theme.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WrapAnywhere
              renderType: Text.NativeRendering
            }
          }
        }

        Item {
          id: previewFooter

          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          height: Style.space(24)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: ClipboardHost.statLabel
            color: Theme.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            renderType: Text.NativeRendering
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            TextButton {
              visible: ClipboardHost.previewKind === "file"
              label: "go to location"
              onClicked: ClipboardHost.openFile()
            }

            TextButton {
              label: "copy"
              onClicked: ClipboardHost.copyCurrent()
            }
          }
        }
      }
    }
  }

  Connections {
    target: ClipboardHost

    function onSessionChanged() {
      search.text = ClipboardHost.query
      search.refocus()
      list.positionViewAtBeginning()
      previewFlick.contentY = 0
    }

    function onShownChanged() {
      if (!ClipboardHost.shown) return
      search.text = ClipboardHost.query
      search.refocus()
      list.positionViewAtBeginning()
      previewFlick.contentY = 0
    }

    function onSelectedChanged() {
      if (ClipboardHost.selected >= 0) {
        list.positionViewAtIndex(ClipboardHost.selected, ListView.Contain)
      }
      previewFlick.contentY = 0
    }

    function onQueryChanged() {
      list.positionViewAtBeginning()
    }

    function onPreviewTextChanged() {
      previewFlick.contentY = 0
    }

    function onPreviewImageChanged() {
      previewFlick.contentY = 0
    }
  }
}
