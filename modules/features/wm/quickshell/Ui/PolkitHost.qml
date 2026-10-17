pragma Singleton

import QtQuick
import Quickshell.Services.Polkit

// The polkit authentication agent.
//
// Without one registered, a program that asks polkit for privilege has nowhere
// to send its prompt: the request simply fails and the user sees nothing. The
// agent registers itself on creation; `registered` reports whether it took.
//
// Everything the prompt needs is read from the current flow rather than copied,
// so a retry after a wrong password updates in place.
QtObject {
  id: root

  property PolkitAgent agent: PolkitAgent {
    path: "/org/quickshell/polkit"
  }

  readonly property var flow: root.agent.flow

  // A flow stays around after it ends, so it is not enough for it to exist.
  readonly property bool awaiting: root.flow !== null && !root.flow.isCompleted
  readonly property bool registered: root.agent.isRegistered

  readonly property string message: root.flow ? String(root.flow.message || "") : ""
  readonly property string prompt: root.flow ? String(root.flow.inputPrompt || "") : ""
  readonly property string detail: root.flow ? String(root.flow.supplementaryMessage || "") : ""
  readonly property bool detailIsError: root.flow ? !!root.flow.supplementaryIsError : false
  readonly property bool needsResponse: root.flow ? !!root.flow.isResponseRequired : false

  function submit(value) {
    if (root.flow && !root.flow.isCompleted) root.flow.submit(String(value))
  }

  function cancel() {
    if (root.flow && !root.flow.isCompleted) root.flow.cancelAuthenticationRequest()
  }
}
