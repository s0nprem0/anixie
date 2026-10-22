pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import ".."

// The session lock.
//
// WlSessionLock asks the compositor for an ext-session-lock session and builds
// one surface per screen from the component below. The compositor keeps the
// session covered even if this process dies, which is what makes the lock a
// security boundary rather than a window that can be dismissed by killing the
// shell.
//
// Password and fingerprint are separate PAM services: `quickshell-lock` uses
// pam_unix, and `quickshell-lock-fingerprint` uses pam_fprintd. They are wired in
// modules/system/lock.nix. The fingerprint service is only attempted when
// fprintd-list reports an enrolled finger.
//
// A shell restart while locked is recoverable: the state file records that the
// lock was requested, and the replacement shell re-acquires it. The lock file is
// cleared on a successful unlock, and when the acquire timeout falls back to
// hyprlock.
QtObject {
  id: root

  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")
  readonly property string fprintdList: "@FPRINTD_LIST@"
  readonly property string hyprlock: "@HYPRLOCK@"

  // The lock state is only recoverable within the compositor instance that
  // requested it. A logout or reboot gives Hyprland a new signature, which is
  // what stops "locked before shutdown" from locking the next login.
  readonly property string sessionSignature: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""

  readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
    + "/anixie/lock"

  // What the UI shows. `requested` is ours; the other two are the compositor's.
  property bool requested: false
  property bool authenticatingPassword: false
  property string pendingPassword: ""
  property string failure: ""
  property int failedAttempts: 0

  property bool fingerprintConfigured: false
  property bool fingerprintTrying: false
  property bool fingerprintUnavailable: false
  property int fingerprintFailures: 0

  property bool suspendAfterLock: false

  readonly property bool locked: root.requested || sessionLock.locked || sessionLock.secure
  readonly property bool secure: sessionLock.secure

  // A lock requested from the session survives a shell restart only if the
  // compositor still covers the session; the state file is the only place that
  // says the old process had asked for it.
  property WlSessionLock sessionLock: WlSessionLock {
    id: sessionLock
    locked: false

    WlSessionLockSurface {
      color: Theme.bg
      LockSurface { anchors.fill: parent }
    }

    onSecureStateChanged: {
      if (sessionLock.secure && root.requested) root.startFingerprint()
    }

    onLockStateChanged: {
      // The compositor dropping a lock we still want is not something to hide:
      // forget it so a stale state file cannot re-lock forever.
      if (!sessionLock.locked && root.requested) {
        root.requested = false
        root.remember("unlocked\n")
        root.resetAuthentication()
      }
    }
  }

  // Reading the file is enough: the compositor is still locked after a crash,
  // and the new instance has to put a surface on it again.
  property FileView stateFile: FileView {
    path: Qt.resolvedUrl(root.statePath)
    printErrors: false
    blockLoading: true
  }

  Component.onCompleted: {
    try {
      const lines = String(root.stateFile.text()).split("\n").map(function (line) { return line.trim() })
      if (lines[0] === root.sessionSignature && lines[1] === "locked") root.startupLock.start()
    } catch (e) {
      // No state file: a normal first start.
    }
  }

  property Timer startupLock: Timer {
    interval: 1200
    repeat: false
    onTriggered: if (!root.locked) root.lock()
  }

  function remember(state) {
    try {
      root.stateFile.setText(root.sessionSignature + "\n" + String(state) + "\n")
    } catch (e) {
    }
  }

  function lock() {
    if (root.locked) return

    root.resetAuthentication()
    root.requested = true
    root.remember("locked\n")
    root.sessionLock.locked = true
  }

  function lockAndSuspend() {
    root.suspendAfterLock = true
    root.lock()
  }

  function unlock() {
    if (!root.requested && !root.sessionLock.locked) return

    root.requested = false
    root.suspendAfterLock = false
    root.sessionLock.locked = false
    root.remember("unlocked\n")
    root.resetAuthentication()
    root.wakeDisplay()
  }

  // The compositor would not give us the session lock — most likely another lock
  // client (hyprlock) is already up. Hand over rather than leave a lock request
  // with no surface behind it.
  function fallbackLock() {
    if (!root.requested || root.sessionLock.secure) return

    const suspend = root.suspendAfterLock
    root.requested = false
    root.suspendAfterLock = false
    root.sessionLock.locked = false
    root.remember("unlocked\n")
    root.resetAuthentication()

    Quickshell.execDetached([root.hyprlock])
    if (suspend) fallbackSuspend.start()
  }

  function resetAuthentication() {
    root.authenticatingPassword = false
    root.pendingPassword = ""
    root.failure = ""
    root.failedAttempts = 0
    root.fingerprintTrying = false
    root.fingerprintUnavailable = false
    root.fingerprintFailures = 0

    if (root.passwordPam.active) root.passwordPam.abort()
    if (root.fingerprintPam.active) root.fingerprintPam.abort()
    fingerprintRetry.stop()
  }

  function clearFailure() {
    if (root.failure !== "") root.failure = ""
  }

  function submitPassword(value) {
    const password = String(value || "")
    if (password === "" || root.authenticatingPassword) return

    root.failure = ""
    root.pendingPassword = password
    root.authenticatingPassword = true

    if (!root.passwordPam.start()) {
      root.authenticatingPassword = false
      root.pendingPassword = ""
      root.failure = "Authentication is unavailable."
      return
    }

    // A PAM stack may have the prompt ready before start() returns.
    Qt.callLater(root.respondToPasswordPrompt)
  }

  function respondToPasswordPrompt() {
    if (!root.authenticatingPassword || !root.passwordPam.active || !root.passwordPam.responseRequired) return
    root.passwordPam.respond(root.pendingPassword)
  }

  function finishPassword(result) {
    root.authenticatingPassword = false
    root.pendingPassword = ""

    if (!root.requested) return

    if (result === PamResult.Success) {
      root.unlock()
      return
    }

    root.failedAttempts += 1
    root.failure = "Incorrect password"
    if (result === PamResult.MaxTries) root.failure = "Too many attempts. Wait a moment and try again."
  }

  function failPassword() {
    if (!root.authenticatingPassword) return

    root.authenticatingPassword = false
    root.pendingPassword = ""
    if (!root.requested) return

    root.failedAttempts += 1
    root.failure = "Authentication failed. Try again."
  }

  function startFingerprint() {
    if (!root.requested || !root.sessionLock.secure) return
    if (!root.fingerprintConfigured || root.fingerprintUnavailable) return
    if (root.fingerprintPam.active || root.fingerprintTrying) return

    root.fingerprintTrying = true
    if (!root.fingerprintPam.start()) {
      root.fingerprintTrying = false
      root.noteFingerprintFailure()
    }
  }

  function finishFingerprint(result) {
    root.fingerprintTrying = false
    if (!root.requested) return

    if (result === PamResult.Success) {
      root.unlock()
      return
    }

    root.noteFingerprintFailure()
  }

  function noteFingerprintFailure() {
    root.fingerprintFailures += 1

    // fprintd can wedge or the reader can disappear. Stop trying and leave the
    // password path in front of the user rather than spin forever.
    if (root.fingerprintFailures >= 5) {
      root.fingerprintUnavailable = true
      root.failure = "Fingerprint unavailable — use your password."
      return
    }

    if (root.requested) fingerprintRetry.restart()
  }

  function retryFingerprint() {
    root.fingerprintFailures = 0
    root.fingerprintUnavailable = false
    root.failure = ""
    root.startFingerprint()
  }

  function wakeDisplay() {
    Quickshell.execDetached([
      "hyprctl", "dispatch", "hl.dsp.dpms({action = \"on\"})"
    ])
  }

  // ---- compensate for the compositor ----

  property Timer acquireTimeout: Timer {
    interval: 5000
    repeat: false
    running: root.requested && !root.sessionLock.secure
    onTriggered: root.fallbackLock()
  }

  property Timer fallbackSuspend: Timer {
    interval: 800
    repeat: false
    onTriggered: Quickshell.execDetached(["systemctl", "suspend"])
  }

  property Timer suspendWait: Timer {
    interval: 50
    repeat: true
    running: root.suspendAfterLock && root.requested
    onTriggered: {
      if (!root.sessionLock.secure) return
      stop()
      root.suspendAfterLock = false
      Quickshell.execDetached(["systemctl", "suspend"])
    }
  }

  // ---- authentication backends ----

  property Process fingerprintProbe: Process {
    running: true
    command: [root.fprintdList, root.userName]

    stdout: StdioCollector {
      onStreamFinished: {
        const text = String(this.text || "")
        root.fingerprintConfigured = /^\s*-\s*#\d+:/m.test(text)
      }
    }

    onExited: if (root.fingerprintConfigured && root.requested && root.sessionLock.secure) root.startFingerprint()
  }

  property PamContext passwordPam: PamContext {
    config: "quickshell-lock"
    user: root.userName

    onResponseRequiredChanged: root.respondToPasswordPrompt()
    onPamMessage: root.respondToPasswordPrompt()
    onCompleted: function (result) { root.finishPassword(result) }
    onError: function (error) { if (root.authenticatingPassword) root.failPassword() }
  }

  property PamContext fingerprintPam: PamContext {
    config: "quickshell-lock-fingerprint"
    user: root.userName

    onCompleted: function (result) { root.finishFingerprint(result) }
    onError: function (error) {
      if (!root.fingerprintTrying) return
      root.fingerprintTrying = false
      root.noteFingerprintFailure()
    }
  }

  property Timer fingerprintRetry: Timer {
    interval: 1500
    repeat: false
    onTriggered: root.startFingerprint()
  }
}
