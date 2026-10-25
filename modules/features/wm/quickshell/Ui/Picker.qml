import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import ".."

// The picker's contents: a search field, the list, and a hint row.
//
// Fills the whole window rather than sitting in it, so that the curtain behind
// it — which is what makes a click anywhere dismiss the picker instead of going
// through to the window underneath — is part of the same thing.
//
// Everything is drawn from PickHost, which is where the entries, the filter and
// the selection live. This file is the view of that and holds no state of its
// own beyond the field's text, which it pushes into the host on every keystroke,
// and the window the Shift+arrows are on, which is the one list PickHost does
// not own.
//
// The launcher adds three things to the card: the open windows as live
// thumbnails, a tab strip, and section rows that are drawn but cannot be chosen.
// Every other picker is still the search field and one list.
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
    NumberAnimation { duration: Style.duration(Style.motion.fast); easing.type: Easing.OutCubic }
  }

  // The height of one row, in one place: the list's area and the rows themselves
  // both draw from it.
  readonly property int rowHeight: Style.space(32)

  // The live windows above the tabs. Only the launcher has them, only while the
  // query is empty — once something is typed the list is the answer and a strip
  // of pictures above it is in the way — and only on the tabs whose content is
  // applications.
  readonly property bool windowsVisible: PickHost.tabs && PickHost.tab <= 1
    && PickHost.query === "" && MenuHost.windows.length > 0

  // Which window the Shift+arrows are on; -1 is the list. Kept apart from
  // PickHost.selected because the two lists can both be on screen.
  property int windowIndex: -1

  function moveWindow(delta) {
    const count = MenuHost.windows.length
    if (!root.windowsVisible || count === 0) return

    let next = root.windowIndex + delta
    if (next >= count) next = -1
    if (next < -1) next = count - 1
    root.windowIndex = next
  }

  function activateWindow() {
    if (root.windowIndex < 0) return false
    const window = MenuHost.windows[root.windowIndex]
    if (!window) return false

    window.activate()
    PickHost.dismiss()
    return true
  }

  // What the footer counts. The launcher counts applications the way the
  // reference does — a total while the list is whole, a slice while a query is
  // narrowing it — while every other picker keeps the old chosen-of-sent form.
  readonly property bool countVisible: PickHost.tabs
    ? (PickHost.tab <= 1 || PickHost.query !== "")
    : (!PickHost.isInput && PickHost.query !== "")

  readonly property string countLabel: {
    if (!PickHost.tabs) return PickHost.results.length + " / " + PickHost.entries.length
    if (PickHost.query === "" && PickHost.tab <= 1) return MenuHost.apps.length + " applications found"
    if (PickHost.tab === 1) return PickHost.results.length + " of " + MenuHost.apps.length
    return PickHost.results.length + (PickHost.results.length === 1 ? " result" : " results")
  }

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
    color: Theme.curtain
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

    // Above the curtain for input, not just for drawing. The card is declared
    // after it already, but a full-output MouseArea behind a childless surface
    // was still taking every press; the explicit z is what makes the card and
    // its rows, tabs and window thumbnails the thing the click lands on.
    z: 1

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
    border.color: Theme.border
    border.width: Style.strokeWidth

    // Clicks on the card's own padding belong to the card. Without this they
    // fall through the surface to the curtain behind and dismiss the picker.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
    }

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
          // The full menu has no title and opens on its search placeholder
          // instead, so the prompt must not reserve an empty slot.
          visible: PickHost.title !== ""
          color: Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          renderType: Text.NativeRendering
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
          renderType: Text.NativeRendering
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
          onTextChanged: {
            root.windowIndex = -1
            PickHost.setQuery(text)
          }

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
              if (root.windowIndex >= 0 && root.activateWindow()) {
                event.accepted = true
                return
              }
              PickHost.accept()
              event.accepted = true
              return
            }

            if (key === Qt.Key_Escape) {
              PickHost.dismiss()
              event.accepted = true
              return
            }

            // Shift and the up/down keys walk the live windows; the plain keys
            // walk the list. Two lists on one surface need two gestures, and
            // Shift is what the reference uses for the window strip.
            if ((key === Qt.Key_Down || key === Qt.Key_Up) && (event.modifiers & Qt.ShiftModifier)) {
              root.moveWindow(key === Qt.Key_Down ? 1 : -1)
              event.accepted = true
              return
            }

            // Up and down are the list's, not the field's: a picker is navigated
            // with the same keys whatever is in the field, so they must not move
            // a caret through the query.
            if (key === Qt.Key_Down || (key === Qt.Key_N && (event.modifiers & Qt.ControlModifier))) {
              root.windowIndex = -1
              PickHost.move(1)
              event.accepted = true
              return
            }

            if (key === Qt.Key_Up || (key === Qt.Key_P && (event.modifiers & Qt.ControlModifier))) {
              root.windowIndex = -1
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

            if (key === Qt.Key_Home) {
              PickHost.first()
              event.accepted = true
              return
            }

            if (key === Qt.Key_End) {
              PickHost.last()
              event.accepted = true
              return
            }

            // Tab switches tabs in the menu, where the strip is the thing above
            // the list and the arrows already move through the list. Everywhere
            // else it walks the list: there is nothing else on the surface to
            // focus, and a Tab that does nothing reads as a broken one.
            if (key === Qt.Key_Tab || key === Qt.Key_Backtab) {
              if (PickHost.tabs) {
                const backward = key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier)
                const next = (PickHost.tab + (backward ? -1 : 1) + PickHost.tabCount) % PickHost.tabCount
                MenuHost.selectTab(next)
              } else {
                PickHost.move((key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier)) ? -1 : 1)
              }
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
          height: Style.strokeWidth
          color: Theme.separator
        }
      }

      // Live windows, as pictures rather than titles: what the reference puts
      // above its tabs, and the only way to tell two terminals apart at a
      // glance. Shift and the arrows choose one; a click does the same.
      Item {
        id: windowStrip

        width: parent.width
        height: root.windowsVisible ? Style.space(50) : 0
        visible: root.windowsVisible
        clip: true

        ListView {
          anchors.fill: parent
          anchors.leftMargin: Style.space(16)
          anchors.rightMargin: Style.space(16)
          orientation: ListView.Horizontal
          spacing: Style.space(6)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: MenuHost.windows

          delegate: Rectangle {
            id: windowTile
            required property int index
            required property var modelData

            readonly property bool chosen: root.windowIndex === index
            readonly property var hypr: modelData.HyprlandToplevel
            readonly property var workspace: hypr ? hypr.workspace : null
            readonly property var monitor: hypr ? hypr.monitor : null

            // Only the windows on their monitor's visible workspace can be
            // captured: a window on a workspace that is not being composited
            // comes back black. Those get the app's mark and a workspace badge
            // instead, so the strip stays a switcher rather than a row of black
            // rectangles. Clicking one still moves to its workspace.
            readonly property bool onActiveWorkspace: {
              if (!workspace || !monitor || !monitor.activeWorkspace) return true
              return workspace.id === monitor.activeWorkspace.id
            }
            readonly property bool captured: capture.hasContent && onActiveWorkspace

            readonly property string iconSource:
              Quickshell.iconPath(String(modelData.appId || ""), true)
            readonly property string workspaceLabel:
              workspace ? String(workspace.name || workspace.id || "") : ""
            readonly property string initial: {
              const text = String(modelData.appId || modelData.title || "?")
              const dot = text.indexOf(".")
              return (dot > 0 ? text.slice(0, dot) : text).charAt(0).toUpperCase()
            }

            width: Style.space(56)
            height: Style.space(40)
            y: (ListView.view.height - height) / 2
            radius: Theme.cornerRadius
            color: Theme.bg
            clip: true
            border.width: Style.strokeWidth
            border.color: chosen
              ? Theme.primary
              : (modelData.activated
                ? Theme.accent
                : (windowMouse.containsMouse ? Theme.borderStrong : Theme.border))

            // What a window that cannot be photographed looks like: its mark,
            // large enough to identify, and the workspace it lives on.
            Item {
              anchors.fill: parent
              visible: !windowTile.captured

              Image {
                anchors.centerIn: parent
                width: Style.space(20)
                height: width
                source: windowTile.iconSource
                visible: windowTile.iconSource !== ""
                fillMode: Image.PreserveAspectFit
                smooth: true
              }

              Text {
                anchors.centerIn: parent
                visible: windowTile.iconSource === ""
                text: windowTile.initial
                color: Theme.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.subtitle
                font.weight: Font.DemiBold
                renderType: Text.NativeRendering
              }
            }

            ScreencopyView {
              id: capture

              anchors.fill: parent
              anchors.margins: Style.strokeWidth
              captureSource: modelData
              live: windowStrip.visible && windowTile.onActiveWorkspace
              paintCursor: false
              visible: windowTile.captured
            }

            // The application's own mark, in the corner, so two windows of the
            // same shape are still distinguishable when the screenshots are.
            Rectangle {
              visible: windowTile.captured && windowTile.iconSource !== ""
              width: Style.space(12)
              height: width
              anchors.left: parent.left
              anchors.bottom: parent.bottom
              anchors.margins: Style.space(2)
              color: Theme.surface
              opacity: 0.9

              Image {
                anchors.fill: parent
                anchors.margins: 1
                source: windowTile.iconSource
                fillMode: Image.PreserveAspectFit
                smooth: true
              }
            }

            // The workspace badge is what tells two black previews apart; the
            // reference puts one in the same corner.
            Rectangle {
              visible: windowTile.workspaceLabel !== ""
              anchors.top: parent.top
              anchors.right: parent.right
              anchors.margins: Style.space(2)
              width: workspaceText.implicitWidth + Style.space(4)
              height: workspaceText.implicitHeight + Style.space(1)
              color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.8)
              radius: Theme.cornerRadius

              Text {
                id: workspaceText
                anchors.centerIn: parent
                text: windowTile.workspaceLabel
                color: Theme.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.weight: Font.DemiBold
                renderType: Text.NativeRendering
              }
            }

            MouseArea {
              id: windowMouse
              anchors.fill: parent
              hoverEnabled: true
              preventStealing: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                modelData.activate()
                PickHost.dismiss()
              }
            }
          }
        }
      }

      // The tabs: the reference's apps/web/files, plus "all" so the commands
      // and themes this menu existed for are still one click away.
      Item {
        id: tabStrip

        width: parent.width
        height: PickHost.tabs ? Style.space(28) : 0
        visible: PickHost.tabs

        Row {
          anchors.centerIn: parent
          spacing: 0

          Repeater {
            model: MenuHost.tabNames

            delegate: Row {
              required property int index
              required property string modelData

              spacing: Style.space(8)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: parent.modelData
                color: PickHost.tab === index ? Theme.accent : Theme.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.weight: PickHost.tab === index ? Font.DemiBold : Font.Normal
                renderType: Text.NativeRendering

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: MenuHost.selectTab(index)
                }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: index < MenuHost.tabNames.length - 1
                text: "|"
                color: Theme.muted
                opacity: 0.4
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                renderType: Text.NativeRendering
              }
            }
          }
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
          // so has somewhere to be drawn. The entries set the size where there
          // are any — typing narrows the list inside a card that keeps its
          // shape — while a tab whose rows come from the query (web, files) is
          // as tall as what that query returned.
          : Math.max(1, Math.min(
              Math.max(PickHost.entries.length, PickHost.results.length),
              PickHost.maxVisible)) * root.rowHeight

        ListView {
          id: list

          visible: PickHost.hasResults
          anchors.fill: parent
          clip: true
          model: PickHost.results
          currentIndex: PickHost.selected
          boundsBehavior: Flickable.StopAtBounds

          // The field owns the keyboard, so the view never scrolls itself when
          // the selection moves. Keep the chosen row on screen, otherwise a
          // twelve-row card hides the highlight after the twelfth entry.
          //
          // Only when it is actually outside the view: scrolling for a row that
          // is already visible moves the list under a hovering pointer, which
          // then hovers a different row and scrolls again.
          onCurrentIndexChanged: {
            if (currentIndex < 0 || currentIndex >= count) return
            const first = Math.floor(contentY / root.rowHeight)
            const last = Math.floor((contentY + height - 1) / root.rowHeight)
            if (currentIndex < first || currentIndex > last) {
              positionViewAtIndex(currentIndex, ListView.Contain)
            }
          }

          ScrollBar.vertical: ScrollBar {
            id: verticalBar
            visible: list.contentHeight > list.height
          }

          delegate: Item {
            id: rowHolder

            required property int index
            required property var modelData

            readonly property var row: rowHolder.modelData.row
            readonly property bool isHeader: row && row.header === true

            width: list.width
            height: root.rowHeight

            // Section labels are rows like any other here, so the list's height
            // and its scrolling stay a single row grid. They are not choices —
            // PickHost walks past them — but they are what separates "most
            // used" from the rest without a second list.
            Text {
              visible: rowHolder.isHeader
              anchors.fill: parent
              anchors.leftMargin: Style.space(12)
              text: rowHolder.row && rowHolder.row.label !== undefined
                ? String(rowHolder.row.label)
                : ""
              color: Theme.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.weight: Font.DemiBold
              verticalAlignment: Text.AlignVCenter
              renderType: Text.NativeRendering
              elide: Text.ElideRight
            }

            PickRow {
              anchors.fill: parent
              visible: !rowHolder.isHeader
              label: rowHolder.row && rowHolder.row.label !== undefined ? String(rowHolder.row.label) : ""
              group: PickHost.groupOf(rowHolder.index)
              state: rowHolder.row && rowHolder.row.state !== undefined ? String(rowHolder.row.state) : ""
              detail: rowHolder.row && rowHolder.row.detail !== undefined ? String(rowHolder.row.detail) : ""
              icon: rowHolder.row && rowHolder.row.icon !== undefined ? String(rowHolder.row.icon) : ""
              preview: rowHolder.row && rowHolder.row.preview !== undefined ? String(rowHolder.row.preview) : ""
              positions: rowHolder.modelData.positions
              selected: rowHolder.index === PickHost.selected
            }

            // Hover only lights the row; it does not move the selection. The
            // list changes under a stationary pointer while typing, and hover
            // selection would chase whichever row moved underneath instead of
            // leaving the keyboard on the top result. A click still chooses.
            MouseArea {
              anchors.fill: parent
              enabled: !rowHolder.isHeader
              hoverEnabled: true
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: {
                PickHost.selected = rowHolder.index
                PickHost.accept()
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
            : (PickHost.tabs && PickHost.tabHint !== "" ? PickHost.tabHint : "Nothing to show")
          color: Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          renderType: Text.NativeRendering
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
          height: Style.strokeWidth
          color: Theme.separator
        }

        Text {
          anchors.centerIn: parent
          text: PickHost.isInput
            ? "↵ to accept · esc to dismiss"
            : (PickHost.tabs
              ? "tab switches · ↑↓ to choose · ↵ to run · esc to dismiss"
              : "↑↓ to choose · ↵ to run · esc to dismiss")
          color: Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          renderType: Text.NativeRendering
        }

        // How many of how many, once a query is narrowing the list and the
        // number is the thing being watched. The launcher instead names the
        // size of the application set, which is the reference's footer.
        Text {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(16)
          anchors.verticalCenter: parent.verticalCenter

          visible: root.countVisible
          text: root.countLabel
          color: Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.italic: PickHost.tabs
          renderType: Text.NativeRendering
        }
      }
    }
  }

  // Back to the top whenever the list is replaced or the query changes. The
  // selection returning to index zero is not enough on its own: if it was
  // already zero while the view was scrolled, CurrentIndex did not change and
  // the new list opened halfway down.
  function resetScroll() {
    list.positionViewAtBeginning()
  }


  // Shown again on every open. A window that has had focus once does not take it
  // back on its own, so without this the second use of any picker would open
  // with the keyboard still going to whatever had it last.
  Connections {
    target: PickHost

    function onShownChanged() {
      if (PickHost.shown) {
        root.windowIndex = -1
        search.text = PickHost.query
        search.refocus()
        Qt.callLater(root.resetScroll)
      }
    }

    function onTabChanged() {
      root.windowIndex = -1
      search.text = PickHost.query
      search.refocus()
      Qt.callLater(root.resetScroll)
    }

    function onQueryChanged() {
      Qt.callLater(root.resetScroll)
    }
  }
}