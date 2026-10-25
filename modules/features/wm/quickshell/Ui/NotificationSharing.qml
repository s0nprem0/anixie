import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Screen-share detection and the one "snooze while sharing" offer. The daemon
// owns notifications; this only watches PipeWire and reports what it sees.
QtObject {
  id: sharing

  property var host: null

  // ---- screen sharing ----
  //
  // A portal screen share is a PipeWire video source named xdph-streaming-*.
  // Watching the node's lifetime, not frame activity, avoids treating a
  // screenshot or a VNC session as sharing.
  readonly property var sharingCandidates: {
    const nodes = Pipewire.nodes ? Pipewire.nodes.values : []
    const out = []
    for (let i = 0; i < nodes.length && out.length < 64; i++) {
      if (nodes[i].type === PwNodeType.VideoSource) out.push(nodes[i])
    }
    return out
  }

  property PwObjectTracker sharingTracker: PwObjectTracker {
    objects: sharing.sharingCandidates
  }

  readonly property int sharingStreams: {
    if (!Pipewire.ready) return 0
    let count = 0
    for (let i = 0; i < sharing.sharingCandidates.length; i++) {
      const node = sharing.sharingCandidates[i]
      if (!node.ready) continue
      const props = node.properties
      if (props["media.class"] === "Video/Source"
          && String(props["media.name"] || "").indexOf("xdph-streaming-") === 0) count++
    }
    return count
  }

  readonly property bool sharingActive: sharing.sharingStreams > 0
  readonly property bool sharingDetectionAvailable: Pipewire.ready
  property bool sharingOfferHandled: false
  readonly property bool sharingOfferPending: sharing.host.offerSnoozeWhenSharing
    && sharing.sharingActive
    && !sharing.sharingOfferHandled
    && !sharing.host.doNotDisturb
    && sharing.host.globalSnoozeUntil <= Date.now() / 1000

  onSharingActiveChanged: {
    sharing.sharingOfferHandled = sharing.sharingActive
      && (sharing.host.doNotDisturb || sharing.host.globalSnoozeUntil > Date.now() / 1000)
  }
  // The snooze lives on the quiet state object; a Connections keeps the offer
  // suppressed when it turns on while a share is already running.
  property Connections snoozeWatch: Connections {
    target: sharing.host
    function onGlobalSnoozeUntilChanged() {
      if (sharing.host.globalSnoozeUntil > Date.now() / 1000 && sharing.sharingActive)
        sharing.sharingOfferHandled = true
    }
  }

  function dismissSharingOffer() {
    if (sharing.sharingActive) sharing.sharingOfferHandled = true
  }

  function snoozeSharingOffer(seconds) {
    const value = Number(seconds)
    if (!sharing.sharingOfferPending || [1800, 3600, 14400].indexOf(value) === -1) return
    sharing.sharingOfferHandled = true
    sharing.host.snooze("*", value)
  }
}
