pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// Sharing the active network: a QR code, and the plain password copied to the
// clipboard for the cases a phone cannot scan.
//
// The QR holds the network password, so it is off by default, generated only
// when switched on, and the file it draws is removed again when it is switched
// off. `qrPath` is what the image is given and only set once a file exists. The
// password is copied rather than shown, so the secret does not stay on screen
// after the click.
QtObject {
  id: shareState

  // The first line of a failed action, for the panel to show.
  signal failed(string message)

  property bool qrVisible: false
  property string qrPath: ""
  property string qrError: ""
  readonly property bool qrReady: shareState.qrPath !== ""

  property bool passwordBusy: false
  property bool passwordCopied: false

  // QR generation is invalidated by a token, so a late process cannot install a
  // path from an earlier or cancelled request.
  property int qrGeneration: 0

  readonly property string stateDir: {
    const state = Quickshell.env("XDG_STATE_HOME")
    if (state) return state + "/anixie"

    const home = Quickshell.env("HOME")
    return home !== "" ? home + "/.local/state/anixie" : ""
  }

  function copyPassword() {
    shareState.passwordBusy = true
    shareState.passwordCopied = false
    passwordCopy.running = false
    passwordCopy.running = true
  }

  function setQr(on) {
    shareState.qrVisible = on

    if (on) {
      shareState.qrGeneration += 1
      shareState.qrPath = ""
      shareState.qrError = ""
      qrQuery.expectedGeneration = shareState.qrGeneration
      qrQuery.running = false
      qrQuery.running = true
    } else {
      // Invalidate any in-flight generation before stopping it, so a late
      // completion cannot install a path after the toggle is off.
      shareState.qrGeneration += 1
      qrQuery.running = false
      shareState.qrPath = ""
      shareState.qrError = ""
      // Take the image away with the toggle. Leaving a password-bearing QR in
      // the state directory after the switch that put it there is off is the
      // kind of thing nobody remembers to clean up.
      rmQr.running = true
    }
  }

  // A code for one network is not a code for another, so a change of network,
  // or the radio going off, takes the code and the copied state away.
  function reset() {
    shareState.passwordCopied = false
    if (shareState.qrVisible) shareState.setQr(false)
  }

  // Remove any code left on disk. A code from a previous run is a password left
  // behind; the toggle that made it is off in a fresh panel.
  function discard() {
    qrQuery.running = false
    if (shareState.stateDir !== "") rmQr.running = true
  }

  property Process qrQuery: Process {
    id: qrQuery
    property int expectedGeneration: 0
    command: ["wifi", "qr"]
    stdout: StdioCollector {
      onStreamFinished: {
        // A cancelled or replaced request must not install its path.
        if (qrQuery.expectedGeneration !== shareState.qrGeneration) return
        if (!shareState.qrVisible) {
          shareState.qrPath = ""
          rmQr.running = true
          return
        }

        const path = String(this.text || "").trim()
        if (path === "" || shareState.stateDir === "" || !path.startsWith(shareState.stateDir + "/")) {
          shareState.qrPath = ""
          shareState.qrError = "Could not read the network password"
          return
        }

        shareState.qrPath = path
        shareState.qrError = ""
      }
    }
    stderr: StdioCollector { id: qrErr }
    onExited: function (exitCode) {
      if (qrQuery.expectedGeneration !== shareState.qrGeneration) return
      if (!shareState.qrVisible) return

      if (exitCode === 0) {
        shareState.qrError = ""
        return
      }

      // The script says why (open network, 802.1X, no encoder); a generic line
      // only when it does not.
      const message = String(qrErr.text || "").trim().split("\n")[0]
      shareState.qrPath = ""
      shareState.qrError = message !== "" ? message : "Could not read the network password"
    }
  }

  property Process rmQr: Process {
    id: rmQr
    command: shareState.stateDir !== ""
      ? ["sh", "-c", 'rm -f "$1"', "_", shareState.stateDir + "/wifi-qr.png"]
      : ["true"]
  }

  property Process passwordCopy: Process {
    id: passwordCopy
    running: false
    command: ["wifi", "password", "--copy"]
    stderr: StdioCollector { id: passwordCopyErr }
    onExited: function (exitCode) {
      shareState.passwordBusy = false

      if (exitCode !== 0) {
        const message = String(passwordCopyErr.text || "").trim().split("\n")[0]
        shareState.failed(message !== "" ? message : "Could not copy the network password")
        return
      }

      shareState.passwordCopied = true
      passwordCopiedTimer.restart()
    }
  }

  property Timer passwordCopiedTimer: Timer {
    id: passwordCopiedTimer
    interval: 2000
    onTriggered: shareState.passwordCopied = false
  }
}
