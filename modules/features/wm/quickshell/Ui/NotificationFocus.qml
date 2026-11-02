import QtQuick
import Quickshell
import Quickshell.Io
import "NotificationText.js" as NotificationText

// Click routing for notification cards. Kept apart from the daemon so the
// hyprctl probe and its scoring can be read without the notification state
// around them.
QtObject {
  id: focus

  // ---- click routing ----
  //
  // A chat notification usually carries no action: clicking it should take you
  // to the window that sent it, not just hide the card. `hyprctl clients` is
  // needed because this build's toplevels do not expose a class; it runs only on
  // a click, never while notifications are arriving.
  property var pendingFocus: null

  function activate(notification, link) {
    const app = String(notification && (notification.appName || notification.app) ? (notification.appName || notification.app) : "")
    const source = notification && (notification.source || notification.sourceKey)
      ? String(notification.source || notification.sourceKey)
      : NotificationText.source(notification)
    focus.focusSource(app, String(link || ""), source)
  }

  function focusSource(app, link, source) {
    focus.pendingFocus = {
      app: String(app || "").toLowerCase(),
      link: String(link || ""),
      source: String(source || "").toLowerCase()
    }
    focus.focusClients.running = false
    focus.focusClients.running = true
  }

  function focusFrom(text) {
    const pending = focus.pendingFocus
    focus.pendingFocus = null
    if (!pending) return

    let clients = []
    try {
      clients = JSON.parse(String(text || ""))
    } catch (e) {
      clients = []
    }
    if (!Array.isArray(clients)) clients = []

    const wanted = String(pending.app || "")
    const source = String(pending.source || "")
    const browser = NotificationText.isBrowser(wanted)
    const siteSource = source !== "" && source.indexOf(".") !== -1
    const sourceBrands = NotificationText.brands(source)
    let best = null

    for (let i = 0; i < clients.length; i++) {
      const client = clients[i]
      if (!client || !client.address) continue
      const klass = String(client.class || client.initialClass || "").toLowerCase()
      const title = String(client.title || "").toLowerCase()

      let score = 0
      if (wanted !== "") {
        if (klass === wanted) score = 3
        else if (klass.indexOf(wanted) !== -1) score = 2
        else if (title.indexOf(wanted) !== -1) score = 1
      }

      let sourceMatch = false
      if (browser && source !== "") {
        for (let b = 0; b < sourceBrands.length; b++) {
          if (title.indexOf(sourceBrands[b]) !== -1) {
            sourceMatch = true
            score = Math.max(score, 4)
            break
          }
        }
        // Without a site match, any browser window is only a fallback; opening
        // the site is more honest than focusing an unrelated tab.
        if (!sourceMatch && score > 0) score = 1
      }

      if (score === 0) continue

      const order = Number(client.focusHistoryID === undefined ? 9999 : client.focusHistoryID)
      if (!best || score > best.score || (score === best.score && order < best.order)) {
        best = { address: String(client.address), score: score, order: order, sourceMatch: sourceMatch }
      }
    }

    if (best && (!browser || !siteSource || best.sourceMatch)) {
      // Dispatched as Lua: the config manager rewrites the old
      // `focuswindow address:0x..` form before evaluating, and that is not a Lua
      // expression, so it fails. This is the form the dock uses.
      Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.focus({window = "' + best.address + '"})'])
      return
    }

    // A browser notification's site is a better target than a random browser
    // window. A link in the body is the last resort.
    if (browser && siteSource) {
      Quickshell.execDetached(["xdg-open", "https://" + source + "/"])
      return
    }
    if (pending.link !== "") Quickshell.execDetached(["xdg-open", pending.link])
  }

  property Process focusClients: Process {
    command: ["hyprctl", "clients", "-j"]
    running: false

    stdout: StdioCollector {
      onStreamFinished: focus.focusFrom(this.text)
    }

    onExited: {
      // A failed `hyprctl` still has to clear the pending click, or the next one
      // would think it already has an answer. If it produced no output at all,
      // the link is the only useful fallback left.
      const pending = focus.pendingFocus
      focus.pendingFocus = null
      if (pending && pending.link !== "") Quickshell.execDetached(["xdg-open", pending.link])
    }
  }
}
