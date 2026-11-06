pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import ".."

// Workspace overview with window focusing, drag-and-drop movement, and screenshot previews.
Item {
  id: root

  readonly property var workspacesList: WorkspaceAdapter.workspaces || []
  readonly property var workspaces: {
    const list = root.workspacesList || []
    const sorted = list.slice()
    sorted.sort(function(a, b) {
      const ai = a && a.id !== undefined && a.id !== null ? Number(a.id) : 0
      const bi = b && b.id !== undefined && b.id !== null ? Number(b.id) : 0
      if (ai < bi) return -1
      if (ai > bi) return 1
      return 0
    })
    let result = sorted
    const mf = String(root.monitorFilter || "").trim()
    if (mf !== "") {
      result = result.filter(function(ws) {
        return String(WorkspaceAdapter.monitorNameOf(ws) || "") === mf
      })
    }
    const q = String(root.searchQuery || "").trim().toLowerCase()
    if (q === "") return result
    return result.filter(function(ws) {
      const idText = String(ws && ws.id !== undefined ? ws.id : "")
      if (idText.toLowerCase().indexOf(q) !== -1) return true
      const name = String(ws && ws.name ? ws.name : "")
      if (name.toLowerCase().indexOf(q) !== -1) return true
      const toplevels = ws && ws.toplevels ? (ws.toplevels.values || []) : []
      for (let i = 0; i < toplevels.length; i++) {
        const w = toplevels[i] || {}
        const title = String(w.title || "")
        const klass = String(w.class || w.appId || w.initialClass || "")
        if (title.toLowerCase().indexOf(q) !== -1) return true
        if (klass.toLowerCase().indexOf(q) !== -1) return true
      }
      return false
    })
  }

  property string previewPath: ""
  property string previewTitle: ""
  property bool previewVisible: false
  property bool previewLoading: false
  property bool previewError: false

  // Move queue to support multiple outstanding moves
  property var moveQueue: []
  property bool moveRunning: false
  property int moveRetryCount: 0
  readonly property int maxMoveRetries: 5

  property string dragSourceAddress: ""
  property var dragSourceWorkspace: null
  property string dragTargetWorkspaceId: ""
  property bool isDragging: false
  property string dragSourceWorkspaceId: ""

  property string searchQuery: ""
  property string monitorFilter: ""

  readonly property var monitorsList: {
    const ws = root.workspacesList || []
    const seen = {}
    const out = []
    for (let i = 0; i < ws.length; i++) {
      const m = String(WorkspaceAdapter.monitorNameOf(ws[i]) || "")
      if (m === "" || seen[m]) continue
      seen[m] = true
      out.push(m)
    }
    out.sort()
    return out
  }

  property int selectedWorkspaceIndex: 0
  property int selectedWindowIndex: -1 // -1 means workspace selected
  property bool keyboardActive: false
  property string navContext: "workspace" // "workspace" or "window" - for Tab navigation

  function isValidPath(p) {
    if (p === undefined || p === null) return false
    const s = String(p).trim()
    return s !== ""
  }

  function urlForPath(p) {
    if (!root.isValidPath(p)) return ""
    const s = String(p)
    if (s.indexOf("file://") === 0) {
      try { return Qt.resolvedUrl(s) } catch (e) { return s }
    }
    if (s.indexOf(":/") !== -1) {
      try { return Qt.resolvedUrl(s) } catch (e) { return s }
    }
    if (s.indexOf("/") === 0) {
      try { return Qt.resolvedUrl("file://" + s) } catch (e) { return "file://" + encodeURI(s) }
    }
    try { return Qt.resolvedUrl(s) } catch (e) { return s }
  }

  function focusWindow(addr) {
    if (!addr) return
    const address = String(addr).replace(/^address:/, "")
    WorkspaceAdapter.focusWindow(address)
  }

  function focusWorkspace(id) {
    if (id === undefined || id === null) return
    WorkspaceAdapter.focusWorkspace(id)
  }

  function moveWindowToWorkspace(addr, toId) {
    if (!addr || toId === undefined || toId === null) return
    const address = String(addr).replace(/^address:/, "")
    WorkspaceAdapter.moveWindowToWorkspace(address, toId)
  }

  function findClient(addr) {
    return WorkspaceAdapter.findWindow(addr)
  }

  function enqueueMove(op) {
    if (!op || !op.address) return
    root.moveQueue.push(op)
    root.processMoves()
  }

  function processMoves() {
    if (root.moveRunning) return
    if (root.moveQueue.length === 0) return
    const op = root.moveQueue.shift()
    root.startMove(op)
  }

  function startMove(op) {
    root.moveRunning = true
    root.moveRetryCount = 0
    // Record current state
    const client = root.findClient(op.address)
    op.from = client ? client.workspace : op.from
    op.to = Number(op.to)
    if (op.to === op.from) {
      root.moveRunning = false
      root.processMoves()
      return
    }
    // Clear any preview issues
    root.moveWindowToWorkspace(op.address, op.to)
    moveRetryTimer.op = op
    moveRetryTimer.start()
  }

  property Timer moveRetryTimer: Timer {
    property var op: null
    interval: 600
    repeat: false
    onTriggered: {
      const pm = moveRetryTimer.op
      if (!pm) {
        root.moveRunning = false
        root.processMoves()
        return
      }
      const client = root.findClient(pm.address)
      if (!client) {
        // Client data may be stale; refresh and retry a few times before
        // giving up on the pending move.
        try { HyprlandAdapter.refresh() } catch (e) {}
        if (root.moveRetryCount < root.maxMoveRetries) {
          root.moveRetryCount += 1
          moveRetryTimer.start()
          return
        }
        moveRetryTimer.op = null
        root.moveRunning = false
        root.processMoves()
        return
      }
      if (client.workspace === pm.to) {
        // Already reached destination
        moveRetryTimer.op = null
        root.moveRunning = false
        root.processMoves()
        return
      }
      if (client.workspace !== pm.from) {
        // Changed workspace but not to destination - don't retry blindly
        moveRetryTimer.op = null
        root.moveRunning = false
        root.processMoves()
        return
      }
      if (root.moveRetryCount >= root.maxMoveRetries) {
        moveRetryTimer.op = null
        root.moveRunning = false
        root.processMoves()
        return
      }
      root.moveRetryCount += 1
      root.moveWindowToWorkspace(pm.address, pm.to)
      moveRetryTimer.start()
    }
  }

  property int captureToken: 0
  property int activeCaptureToken: 0

  property Process captureProc: Process {
    running: false
    property int captureToken: -1
    onExited: function (code) {
      if (root.captureProc.captureToken !== root.activeCaptureToken) return
      if (code === 0) {
        // Only publish when the file actually exists and is non-empty.
        root.previewError = false
        root.previewLoading = false
        root.previewVisible = true
      } else {
        root.previewError = true
        root.previewLoading = false
        root.previewVisible = false
      }
    }
  }

  function captureWindow(win) {
    // Clean up the previous capture to avoid /tmp accumulation.
    if (root.previewPath) {
      try { Commands.run("rm -f " + Util.shellQuote(root.previewPath)) } catch (e) {}
    }
    root.previewTitle = win ? String(win.title || win.class || win.appId || "") : ""
    if (!win || !win.at || !win.size) {
      root.previewError = true
      root.previewLoading = false
      root.previewVisible = false
      return
    }
    const x = win.at[0]
    const y = win.at[1]
    const w = win.size[0]
    const h = win.size[1]
    if (w <= 0 || h <= 0) {
      root.previewError = true
      root.previewLoading = false
      root.previewVisible = false
      return
    }
    // Use unique temp file to avoid races
    root.captureToken = (root.captureToken + 1) % 1000000
    const token = root.captureToken
    root.activeCaptureToken = token
    const path = "/tmp/quickshell-ws-preview-" + token + ".png"
    root.previewPath = path
    root.previewVisible = false
    root.previewError = false
    root.previewLoading = true
    try {
      root.captureProc.captureToken = token
      root.captureProc.command = ["grim", "-g", Math.round(x) + "," + Math.round(y) + " " + Math.round(w) + "x" + Math.round(h), path]
      root.captureProc.running = false
      root.captureProc.running = true
    } catch (e) {
      root.previewError = true
      root.previewLoading = false
      root.previewVisible = false
    }
  }

  Component.onCompleted: {
    try { HyprlandAdapter.enabled = WorkspaceOverviewHost.shown || DockHost.shown } catch (e) {}
    if (WorkspaceOverviewHost.shown) {
      try { HyprlandAdapter.refresh() } catch (e) {}
    }
  }

  Connections {
    target: WorkspaceOverviewHost
    function onShownChanged() {
      try { HyprlandAdapter.enabled = WorkspaceOverviewHost.shown || DockHost.shown } catch (e) {}
      if (WorkspaceOverviewHost.shown) {
        try { HyprlandAdapter.refresh() } catch (e) {}
        // Reset selection to the active workspace on each open.
        const ws = root.workspaces || []
        let activeIndex = -1
        for (let i = 0; i < ws.length; i++) {
          if (WorkspaceAdapter.focusedWorkspaceId !== null && ws[i] && ws[i].id === WorkspaceAdapter.focusedWorkspaceId) {
            activeIndex = i
            break
          }
        }
        root.selectedWorkspaceIndex = activeIndex >= 0 ? activeIndex : 0
        root.selectedWindowIndex = -1
        root.keyboardActive = false
        root.previewVisible = false
        root.previewLoading = false
        root.previewError = false
        root.previewTitle = ""
      } else {
        // Clean up while closed: cancel captures and pending moves.
        try { if (root.captureProc.running) root.captureProc.running = false } catch (e) {}
        if (root.previewPath) {
          try { Commands.run("rm -f " + Util.shellQuote(root.previewPath)) } catch (e) {}
        }
        root.previewPath = ""
        try { moveRetryTimer.stop() } catch (e) {}
        moveRetryTimer.op = null
        root.moveQueue = []
        root.moveRunning = false
      }
    }
  }

  Component.onDestruction: {
    try { moveRetryTimer.stop() } catch (e) {}
    try { if (root.captureProc.running) root.captureProc.running = false } catch (e) {}
    root.moveQueue = []
    root.moveRunning = false
  }

  function clampSelection() {
    const ws = root.workspaces || []
    if (ws.length === 0) {
      root.selectedWorkspaceIndex = 0
      root.selectedWindowIndex = -1
      root.keyboardActive = false
      return
    }
    if (root.selectedWorkspaceIndex < 0) root.selectedWorkspaceIndex = 0
    if (root.selectedWorkspaceIndex >= ws.length) root.selectedWorkspaceIndex = ws.length - 1
    if (root.selectedWindowIndex >= 0) {
      const curWs = ws[root.selectedWorkspaceIndex]
      const toplevels = curWs && curWs.toplevels ? (curWs.toplevels.values || []) : []
      if (toplevels.length === 0) {
        root.selectedWindowIndex = -1
      } else if (root.selectedWindowIndex >= toplevels.length) {
        root.selectedWindowIndex = toplevels.length - 1
      }
    }
  }

  function ensureVisible() {
    Qt.callLater(function() {
      scroll.ensureVisible()
    })
  }

  onWorkspacesChanged: {
    root.clampSelection()
    root.ensureVisible()
  }

  focus: true
  Keys.onPressed: function(event) {
    root.keyboardActive = true
    const ws = root.workspaces || []
    if (ws.length === 0) {
      if (event.key === Qt.Key_Escape) {
        if (typeof WorkspaceOverviewHost !== "undefined") WorkspaceOverviewHost.hide()
      }
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Escape) {
      if (typeof WorkspaceOverviewHost !== "undefined") WorkspaceOverviewHost.hide()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Slash) {
      searchField.forceActiveFocus()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
      if (root.selectedWindowIndex >= 0) {
        const curWs = ws[root.selectedWorkspaceIndex]
        const toplevels = curWs && curWs.toplevels ? (curWs.toplevels.values || []) : []
        const win = toplevels[root.selectedWindowIndex]
        if (win && win.address) {
          const address = String(win.address).replace(/^address:/, "")
          WorkspaceAdapter.closeWindow(address)
        }
      }
      event.accepted = true
      return
    }
    // Tab / Shift+Tab - switch between workspace and window navigation contexts
    if (event.key === Qt.Key_Tab) {
      if (event.modifiers & Qt.ShiftModifier) {
        if (root.selectedWindowIndex >= 0) {
          root.selectedWindowIndex = -1
          root.navContext = "workspace"
        } else {
          // Already at workspace level, wrap to last window of previous workspace
          root.selectedWorkspaceIndex = (root.selectedWorkspaceIndex - 1 + ws.length) % ws.length
          const curWs = ws[root.selectedWorkspaceIndex]
          const toplevels = curWs && curWs.toplevels ? (curWs.toplevels.values || []) : []
          if (toplevels.length > 0) {
            root.selectedWindowIndex = toplevels.length - 1
            root.navContext = "window"
          } else {
            root.navContext = "workspace"
          }
        }
      } else {
        if (root.selectedWindowIndex === -1) {
          const curWs = ws[root.selectedWorkspaceIndex]
          const toplevels = curWs && curWs.toplevels ? (curWs.toplevels.values || []) : []
          if (toplevels.length > 0) {
            root.selectedWindowIndex = 0
            root.navContext = "window"
          } else {
            root.selectedWorkspaceIndex = (root.selectedWorkspaceIndex + 1) % ws.length
            root.navContext = "workspace"
          }
        } else {
          const curWs = ws[root.selectedWorkspaceIndex]
          const toplevels = curWs && curWs.toplevels ? (curWs.toplevels.values || []) : []
          if (root.selectedWindowIndex < toplevels.length - 1) {
            root.selectedWindowIndex += 1
            root.navContext = "window"
          } else {
            root.selectedWindowIndex = -1
            root.selectedWorkspaceIndex = (root.selectedWorkspaceIndex + 1) % ws.length
            root.navContext = "workspace"
          }
        }
      }
      root.ensureVisible()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
      if (root.selectedWindowIndex >= 0) {
        const curWs = ws[root.selectedWorkspaceIndex]
        const toplevels = curWs && curWs.toplevels ? (curWs.toplevels.values || []) : []
        if (root.selectedWindowIndex < toplevels.length - 1) {
          root.selectedWindowIndex += 1
        } else {
          root.selectedWindowIndex = -1
          root.selectedWorkspaceIndex = (root.selectedWorkspaceIndex + 1) % ws.length
        }
      } else {
        root.selectedWorkspaceIndex = (root.selectedWorkspaceIndex + 1) % ws.length
        root.selectedWindowIndex = -1
      }
      root.navContext = root.selectedWindowIndex >= 0 ? "window" : "workspace"
      root.ensureVisible()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
      if (root.selectedWindowIndex >= 0) {
        if (root.selectedWindowIndex > 0) {
          root.selectedWindowIndex -= 1
        } else {
          root.selectedWindowIndex = -1
        }
      } else {
        root.selectedWorkspaceIndex = (root.selectedWorkspaceIndex - 1 + ws.length) % ws.length
        const curWs = ws[root.selectedWorkspaceIndex]
        const toplevels = curWs && curWs.toplevels ? (curWs.toplevels.values || []) : []
        if (toplevels.length > 0) {
          root.selectedWindowIndex = toplevels.length - 1
        } else {
          root.selectedWindowIndex = -1
        }
      }
      root.navContext = root.selectedWindowIndex >= 0 ? "window" : "workspace"
      root.ensureVisible()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Home) {
      root.selectedWorkspaceIndex = 0
      root.selectedWindowIndex = -1
      root.navContext = "workspace"
      root.ensureVisible()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_End) {
      root.selectedWorkspaceIndex = ws.length - 1
      root.selectedWindowIndex = -1
      root.navContext = "workspace"
      root.ensureVisible()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_PageDown) {
      // Jump down by ~3 workspaces
      root.selectedWorkspaceIndex = Math.min(ws.length - 1, root.selectedWorkspaceIndex + 3)
      root.selectedWindowIndex = -1
      root.navContext = "workspace"
      root.ensureVisible()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_PageUp) {
      root.selectedWorkspaceIndex = Math.max(0, root.selectedWorkspaceIndex - 3)
      root.selectedWindowIndex = -1
      root.navContext = "workspace"
      root.ensureVisible()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      const curWs = ws[root.selectedWorkspaceIndex]
      if (!curWs) { event.accepted = true; return }
      if (root.selectedWindowIndex >= 0) {
        const toplevels = curWs.toplevels ? (curWs.toplevels.values || []) : []
        const win = toplevels[root.selectedWindowIndex]
        if (win && win.address) {
          root.focusWindow(win.address)
        }
      } else {
        root.focusWorkspace(curWs.id)
      }
      if (typeof WorkspaceOverviewHost !== "undefined") WorkspaceOverviewHost.hide()
      event.accepted = true
      return
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.94)

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(24)
      spacing: Style.space(16)

      // Header
      Column {
        width: parent.width
        spacing: Style.space(4)

        Row {
          width: parent.width
          spacing: Style.space(12)

          Text {
            text: "Workspace Overview"
            color: Theme.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle + 4
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            text: root.workspaces.length + " workspaces"
            color: Theme.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            renderType: Text.NativeRendering
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Text {
          text: "←→/↑↓ navigate • Tab switch workspaces/windows • Enter focus • / search • Del close • Esc close"
          color: Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          renderType: Text.NativeRendering
          elide: Text.ElideRight
          width: parent.width
        }
      }

      // Search/filter
      TextField {
        id: searchField
        width: parent.width
        placeholderText: "Filter workspaces or windows…"
        text: root.searchQuery
        onTextChanged: root.searchQuery = text
        Keys.onEscapePressed: {
          if (text !== "") {
            text = ""
            root.searchQuery = ""
          } else if (typeof WorkspaceOverviewHost !== "undefined") {
            WorkspaceOverviewHost.hide()
          }
        }
      }

      // Monitor filter
      Row {
        width: parent.width
        spacing: Style.space(8)
        visible: root.monitorsList.length > 1

        Rectangle {
          width: allLabel.implicitWidth + Style.space(12)
          height: Style.space(24)
          radius: Theme.cornerRadius
          color: root.monitorFilter === "" ? Theme.accent : Theme.surface
          border.color: Theme.border
          border.width: Style.strokeWidth
          Text {
            id: allLabel
            anchors.centerIn: parent
            text: "All"
            color: root.monitorFilter === "" ? Theme.bg : Theme.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.monitorFilter = ""
          }
        }

        Repeater {
          model: root.monitorsList
          delegate: Rectangle {
            required property string modelData
            width: monLabel.implicitWidth + Style.space(12)
            height: Style.space(24)
            radius: Theme.cornerRadius
            color: root.monitorFilter === modelData ? Theme.accent : Theme.surface
            border.color: monitorDropArea.containsDrag ? Theme.accent : Theme.border
            border.width: Style.strokeWidth
            Text {
              id: monLabel
              anchors.centerIn: parent
              text: modelData
              color: root.monitorFilter === modelData ? Theme.bg : Theme.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.monitorFilter = modelData
            }
            DropArea {
              id: monitorDropArea
              anchors.fill: parent
              keys: ["workspace"]
              onDropped: function(drop) {
                let id = root.dragSourceWorkspaceId
                if (!id && drop.mimeData) {
                  try {
                    if (drop.mimeData["text/plain"]) id = String(drop.mimeData["text/plain"])
                  } catch (e) {}
                }
                if (!id) return
                WorkspaceAdapter.moveWorkspaceToMonitor(id, modelData)
                root.dragSourceWorkspaceId = ""
                root.isDragging = false
              }
            }
          }
        }
      }

      // Content area
      ScrollView {
        id: scroll
        width: parent.width
        height: parent.height - y
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: ScrollBar.AsNeeded

        function ensureVisible() {
          const ws = root.workspaces || []
          if (ws.length === 0) return
          // Try to make the selected workspace card visible
          if (root.selectedWorkspaceIndex < 0 || root.selectedWorkspaceIndex >= ws.length) return
          // Find the card item
          const cardItem = cardsRepeater.itemAt(root.selectedWorkspaceIndex)
          if (!cardItem) return
          try {
            const pos = cardItem.mapToItem(scroll.contentItem, 0, 0)
            const viewTop = scroll.contentItem.contentY
            const viewBottom = viewTop + scroll.height
            const cardTop = pos.y
            const cardBottom = pos.y + cardItem.height
            if (cardTop < viewTop) {
              scroll.contentItem.contentY = Math.max(0, cardTop - Style.space(8))
            } else if (cardBottom > viewBottom) {
              scroll.contentItem.contentY = Math.min(scroll.contentItem.contentHeight - scroll.height, cardBottom - scroll.height + Style.space(8))
            }
          } catch (e) {}
        }

        // The scroll view's flickable takes every press inside it, so the
        // window-level dismiss area behind the overview never sees a click on
        // the empty space below the cards. This one, behind the cards and at
        // least as tall as the view, covers that space.
        Item {
          implicitWidth: scroll.availableWidth
          implicitHeight: Math.max(cards.implicitHeight, scroll.availableHeight)

          MouseArea {
            anchors.fill: parent
            onClicked: {
              if (root.isDragging) return
              if (typeof WorkspaceOverviewHost !== "undefined") WorkspaceOverviewHost.hide()
            }
          }

          Column {
            id: cards
            width: scroll.availableWidth
            spacing: Style.space(10)

            Repeater {
              id: cardsRepeater
              model: root.workspaces

              delegate: Rectangle {
                id: wsCard
                required property var modelData
                required property int index
                property bool isActive: WorkspaceAdapter.focusedWorkspaceId !== null && WorkspaceAdapter.focusedWorkspaceId == modelData.id
                property bool isKeyboardSelected: root.keyboardActive && root.selectedWorkspaceIndex === index && root.selectedWindowIndex === -1
                width: parent.width
                implicitHeight: wsContent.implicitHeight + Style.space(14)
                radius: Theme.cornerRadius
                color: isActive ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14) : (cardMouseArea.containsMouse ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.04) : Theme.surface)
                border.color: (isKeyboardSelected || dropArea.containsDrag) ? Theme.accent : (isActive ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.9) : Theme.border)
                border.width: (isKeyboardSelected || dropArea.containsDrag) ? Style.strokeWidth + 0 : Style.strokeWidth
                Behavior on color { ColorAnimation { duration: Style.duration(Style.motion.fast) } }
                Behavior on border.color { ColorAnimation { duration: Style.duration(Style.motion.fast) } }
                scale: cardMouseArea.pressed && !dropArea.containsDrag ? 0.995 : 1.0
                Behavior on scale { NumberAnimation { duration: Style.duration(80); easing.type: Easing.OutCubic } }

                Column {
                  id: wsContent
                  anchors.fill: parent
                  anchors.margins: Style.space(10)
                  spacing: Style.space(6)

                  Row {
                    id: wsHeader
                    width: parent.width
                    spacing: Style.space(8)
                    Text {
                      text: (modelData.name && String(modelData.name).trim() !== "" ? String(modelData.name) : "Workspace " + modelData.id)
                      color: Theme.fg
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      font.weight: Font.DemiBold
                      renderType: Text.NativeRendering
                      elide: Text.ElideRight
                      maximumLineCount: 1
                    }
                     Text {
                       text: "⋮⋮"
                       color: Theme.muted
                       font.family: Style.font.family
                       font.pixelSize: Style.font.body
                       visible: root.monitorsList.length > 1
                       MouseArea {
                         id: wsDragArea
                         anchors.fill: parent
                         cursorShape: Qt.OpenHandCursor
                         drag.target: wsDragHandle
                         acceptedButtons: Qt.LeftButton
                         onPressed: {
                           root.dragSourceWorkspaceId = String(wsCard.modelData.id)
                           root.isDragging = true
                         }
                         onReleased: {
                           wsDragHandle.Drag.active = false
                           root.isDragging = false
                           root.dragSourceWorkspaceId = ""
                         }
                         onCanceled: {
                           wsDragHandle.Drag.active = false
                           root.isDragging = false
                           root.dragSourceWorkspaceId = ""
                         }
                       }
                     }
                     Item {
                       id: wsDragHandle
                       width: 1
                       height: 1
                       visible: false
                       Drag.active: wsDragArea.drag.active
                       Drag.keys: ["workspace"]
                       Drag.hotSpot.x: 0
                       Drag.hotSpot.y: 0
                       Drag.mimeData: { "text/plain": String(wsCard.modelData.id) }
                     }
                     Text {
                       visible: root.monitorsList.length > 1
                       text: WorkspaceAdapter.monitorNameOf(wsCard.modelData)
                       color: Theme.muted
                       font.family: Style.font.family
                       font.pixelSize: Style.font.bodySmall
                       renderType: Text.NativeRendering
                       anchors.verticalCenter: parent.verticalCenter
                     }
                    Rectangle {
                      visible: wsCard.isActive
                      width: activeText.implicitWidth + Style.space(8)
                      height: activeText.implicitHeight + Style.space(2)
                      radius: Theme.cornerRadius
                      color: Theme.accent
                      anchors.verticalCenter: parent.verticalCenter
                      Text {
                        id: activeText
                        anchors.centerIn: parent
                        text: "Active"
                        color: Theme.bg
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                      }
                    }
                    Rectangle {
                      visible: root.keyboardActive && root.selectedWorkspaceIndex === wsCard.index && root.selectedWindowIndex === -1 && !wsCard.isActive
                      width: selText.implicitWidth + Style.space(8)
                      height: selText.implicitHeight + Style.space(2)
                      radius: Theme.cornerRadius
                      color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                      border.color: Theme.accent
                      border.width: Style.strokeWidth
                      anchors.verticalCenter: parent.verticalCenter
                      Text {
                        id: selText
                        anchors.centerIn: parent
                        text: "Selected"
                        color: Theme.fg
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                      }
                    }
                    Item { width: 1; height: 1 }
                    Text {
                      text: ((modelData.toplevels && modelData.toplevels.values) ? modelData.toplevels.values.length : 0) + " window" + ((((modelData.toplevels && modelData.toplevels.values) ? modelData.toplevels.values.length : 0) === 1) ? "" : "s")
                      color: Theme.muted
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      renderType: Text.NativeRendering
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }

                  // Card click area covers header area
                  MouseArea {
                    id: cardMouseArea
                    anchors.left: parent.left
                    anchors.right: parent.right
                    y: wsHeader.y
                    height: wsHeader.height
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    z: 10
                    onClicked: {
                      root.keyboardActive = false
                      root.selectedWorkspaceIndex = wsCard.index
                      root.selectedWindowIndex = -1
                      root.focusWorkspace(modelData.id)
                      if (typeof WorkspaceOverviewHost !== "undefined") WorkspaceOverviewHost.hide()
                    }
                  }

                  Repeater {
                    model: modelData.toplevels ? (modelData.toplevels.values || []) : []

                    delegate: Rectangle {
                      id: winRow
                      required property var modelData
                      required property int index
                      property string address: String(modelData.address || "")
                      property bool isFocused: modelData.focused === true
                      property bool isKeyboardSelected: root.keyboardActive && root.selectedWorkspaceIndex === wsCard.index && root.selectedWindowIndex === index
                      property bool isDragged: dragArea.pressed && dragArea.drag.active
                      readonly property bool hovered: dragArea.containsMouse || closeMouseArea.containsMouse
                      width: parent.width
                      height: Style.space(30)
                      radius: Theme.cornerRadius / 2
                      color: isDragged ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22) : (isKeyboardSelected ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16) : (hovered ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.07) : "transparent"))
                      border.color: isKeyboardSelected ? Theme.accent : "transparent"
                      border.width: isKeyboardSelected ? Style.strokeWidth : 0
                      scale: dragArea.pressed && !dragArea.drag.active ? 0.995 : 1.0
                      Behavior on color { ColorAnimation { duration: Style.duration(Style.motion.fast) } }
                      Behavior on border.color { ColorAnimation { duration: Style.duration(Style.motion.fast) } }
                      Behavior on scale { NumberAnimation { duration: Style.duration(70); easing.type: Easing.OutCubic } }

                      Row {
                        anchors.fill: parent
                        anchors.leftMargin: Style.space(8)
                        anchors.rightMargin: Style.space(8)
                        spacing: Style.space(8)

                        Image {
                          width: Style.space(18)
                          height: Style.space(18)
                          anchors.verticalCenter: parent.verticalCenter
                          source: Quickshell.iconPath(String(modelData.class || modelData.appId || modelData.initialClass || ""), true)
                          visible: source !== ""
                          fillMode: Image.PreserveAspectFit
                          asynchronous: true
                          smooth: true
                        }
                        Rectangle {
                          visible: (Quickshell.iconPath(String(modelData.class || modelData.appId || modelData.initialClass || ""), true) === "")
                          width: Style.space(18)
                          height: Style.space(18)
                          anchors.verticalCenter: parent.verticalCenter
                          radius: Style.space(4)
                          color: Qt.rgba(Theme.muted.r, Theme.muted.g, Theme.muted.b, 0.18)
                          Text {
                            anchors.centerIn: parent
                            text: {
                              const id = String(modelData.class || modelData.appId || modelData.initialClass || "W")
                              return id.length > 0 ? id.substring(0,1).toUpperCase() : "W"
                            }
                            color: Theme.muted
                            font.pixelSize: Style.font.bodySmall
                            font.family: Style.font.family
                          }
                        }

                        Text {
                          width: parent.width - Style.space(52)
                          anchors.verticalCenter: parent.verticalCenter
                          text: String(modelData.title || modelData.class || modelData.appId || modelData.initialClass || "Untitled window")
                          color: isFocused ? Theme.fg : (isKeyboardSelected ? Theme.fg : Theme.muted)
                          font.family: Style.font.family
                          font.pixelSize: Style.font.bodySmall
                          font.weight: isFocused ? Font.DemiBold : Font.Normal
                          elide: Text.ElideRight
                          renderType: Text.NativeRendering
                          maximumLineCount: 1
                        }
                         Rectangle {
                           width: Style.space(20)
                           height: Style.space(20)
                           radius: Theme.cornerRadius
                           anchors.verticalCenter: parent.verticalCenter
                           color: closeMouseArea.containsMouse ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.12) : "transparent"
                           opacity: (winRow.hovered || winRow.isKeyboardSelected) ? 1 : 0.35
                           Text {
                             anchors.centerIn: parent
                             text: "×"
                             color: Theme.muted
                             font.family: Style.font.family
                             font.pixelSize: Style.font.body
                             renderType: Text.NativeRendering
                           }
                           MouseArea {
                             id: closeMouseArea
                             anchors.fill: parent
                             cursorShape: Qt.PointingHandCursor
                             hoverEnabled: true
                             onClicked: function(event) {
                               event.accepted = true
                               if (!winRow.address) return
                               const address = String(winRow.address).replace(/^address:/, "")
                               WorkspaceAdapter.closeWindow(address)
                             }
                           }
                         }
                      }

                      // One MouseArea for click, double-click, hover and drag.
                      MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        z: -1
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        drag.target: dragHandle
                        acceptedButtons: Qt.LeftButton
                        onPressed: {
                          root.isDragging = false
                          root.keyboardActive = false
                          root.selectedWorkspaceIndex = wsCard.index
                          root.selectedWindowIndex = winRow.index
                          if (winRow.address) {
                            root.dragSourceAddress = winRow.address
                            root.dragSourceWorkspace = wsCard.modelData
                          }
                        }
                        onReleased: {
                          dragHandle.Drag.active = false
                          root.isDragging = false
                          root.dragSourceAddress = ""
                          root.dragSourceWorkspace = null
                        }
                        onCanceled: {
                          dragHandle.Drag.active = false
                          root.isDragging = false
                          root.dragSourceAddress = ""
                          root.dragSourceWorkspace = null
                        }
                        onClicked: {
                          if (dragHandle.Drag.active) return
                          if (winRow.address) {
                            root.focusWindow(winRow.address)
                            if (typeof WorkspaceOverviewHost !== "undefined") WorkspaceOverviewHost.hide()
                          }
                        }
                        onDoubleClicked: {
                          if (dragHandle.Drag.active) return
                          if (winRow.address) {
                            root.captureWindow(modelData)
                          }
                        }
                      }

                      Item {
                        id: dragHandle
                        width: winRow.width
                        height: winRow.height
                        Drag.active: dragArea.drag.active

                        Drag.onActiveChanged: {
                          if (Drag.active) root.isDragging = true
                        }
                        Drag.source: winRow
                        Drag.keys: ["window"]
                        Drag.supportedActions: Qt.MoveAction
                        Drag.hotSpot.x: width / 2
                        Drag.hotSpot.y: height / 2
                        property string dragAddress: winRow.address
                        Drag.mimeData: {
                          "text/plain": winRow.address || "",
                          "application/x-hyprland-window-address": winRow.address || ""
                        }
                        visible: dragArea.drag.active
                        parent: root
                        onParentChanged: if (parent === null) parent = root
                        Rectangle {
                          anchors.fill: parent
                          radius: Theme.cornerRadius / 2
                          color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.32)
                          border.color: Theme.accent
                          border.width: Style.strokeWidth
                          opacity: 0.95
                        }
                      }
                    }
                  }

                  Text {
                    visible: ((modelData.toplevels && modelData.toplevels.values) ? modelData.toplevels.values.length : 0) === 0
                    text: "No windows • drop here to move"
                    color: Theme.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    leftPadding: Style.space(8)
                    opacity: dropArea.containsDrag ? 0.8 : 0.6
                    Behavior on opacity { NumberAnimation { duration: Style.duration(Style.motion.fast) } }
                  }
                }

                DropArea {
                  id: dropArea
                  anchors.fill: parent
                  keys: ["window"]
                  onEntered: function(drag) {
                    if (drag.source && drag.source.address) {
                      root.dragTargetWorkspaceId = String(modelData.id)
                    } else if (root.dragSourceAddress) {
                      root.dragTargetWorkspaceId = String(modelData.id)
                    } else if (drag.mimeData) {
                      root.dragTargetWorkspaceId = String(modelData.id)
                    }
                  }
                  onExited: {
                    if (root.dragTargetWorkspaceId === String(modelData.id)) {
                      root.dragTargetWorkspaceId = ""
                    }
                  }
                  onDropped: function(drop) {
                    let addr = ""
                    if (drop.source && drop.source.address) addr = drop.source.address
                    if (!addr && root.dragSourceAddress) addr = root.dragSourceAddress
                    if (!addr && drop.mimeData) {
                      try {
                        if (drop.mimeData["application/x-hyprland-window-address"]) addr = String(drop.mimeData["application/x-hyprland-window-address"])
                        else if (drop.mimeData["text/plain"]) addr = String(drop.mimeData["text/plain"])
                      } catch (e) {}
                    }
                    if (!addr) {
                      drop.accepted = false
                      root.dragTargetWorkspaceId = ""
                      root.isDragging = false
                      root.dragSourceAddress = ""
                      root.dragSourceWorkspace = null
                      return
                    }
                    const toId = modelData.id
                    const fromClient = root.findClient(addr)
                    if (fromClient && Number(fromClient.workspace) === Number(toId)) {
                      drop.accepted = false
                      root.dragTargetWorkspaceId = ""
                      root.isDragging = false
                      root.dragSourceAddress = ""
                      root.dragSourceWorkspace = null
                      return
                    }
                    drop.accepted = true
                    root.enqueueMove({ address: addr, to: toId })
                    root.dragTargetWorkspaceId = ""
                    root.isDragging = false
                    root.dragSourceAddress = ""
                    root.dragSourceWorkspace = null
                  }
                }
              }
            }

            Text {
              visible: (root.workspaces || []).length === 0
              text: "No workspaces available"
              color: Theme.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              anchors.horizontalCenter: parent.horizontalCenter
            }
          }
        }
      }
    }

    // Preview
    Rectangle {
      anchors.bottom: parent.bottom
      anchors.right: parent.right
      anchors.bottomMargin: Style.space(20)
      anchors.rightMargin: Style.space(20)
      width: Math.min(root.width * 0.35, Style.space(420))
      height: width * 0.5625
      visible: root.previewLoading || root.previewVisible || root.previewError
      radius: Theme.cornerRadius
      color: Theme.surface
      border.color: Theme.border
      border.width: Style.strokeWidth
      clip: true

      Text {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Style.space(8)
        visible: root.previewTitle !== ""
        text: root.previewTitle
        color: Theme.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.weight: Font.DemiBold
        elide: Text.ElideRight
        renderType: Text.NativeRendering
      }

      Text {
        anchors.centerIn: parent
        visible: root.previewLoading
        text: "Capturing..."
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        anchors.centerIn: parent
        visible: root.previewError && !root.previewLoading
        text: "Capture failed (grim unavailable or invalid region)"
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        horizontalAlignment: Text.AlignHCenter
        width: parent.width - Style.space(16)
        wrapMode: Text.WordWrap
      }
      Image {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: root.previewTitle !== "" ? Style.space(24) : 0
        anchors.margins: Style.space(8)
        visible: root.previewVisible && !root.previewLoading && !root.previewError && root.previewPath !== ""
        source: root.urlForPath(root.previewPath)
        fillMode: Image.PreserveAspectFit
        cache: false
        asynchronous: true
        onStatusChanged: {
          if (status === Image.Error) {
            root.previewError = true
            root.previewVisible = false
          }
        }
      }
    }
  }
}
