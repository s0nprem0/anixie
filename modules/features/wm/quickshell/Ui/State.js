// Versioning for the shell's saved state files.
//
// The bar layout, focus block, and anything else the shell keeps under
// ~/.local/state outlive a rebuild. A future change to their shape needs a
// place to say "this file is from before the change" and a single function
// that brings it forward. Keeping that seam here means each store reads and
// writes `version` the same way, instead of growing its own ad-hoc check.
//
// State is upgraded in place: unknown fields are left alone, so a newer shell
// that writes a field an older one does not know about does not have that field
// stripped by an older reader. A file with no version is version 1, which is
// what every store wrote before this existed.

var VERSION = 1

function versionOf(state) {
  if (!state || typeof state !== "object") return 0
  var version = Number(state.version)
  return isFinite(version) && version > 0 ? version : 1
}

function upgrade(state) {
  if (!state || typeof state !== "object" || Array.isArray(state)) return state

  var version = versionOf(state)
  var stated = Number(state.version)

  // A file from a newer shell is left at its version: this reader does not know
  // its shape, so rewriting the number would claim an upgrade it did not make
  // and the next newer reader would migrate an already-migrated file.
  if (isFinite(stated) && stated > VERSION) return state

  // There is only one version so far. A migration belongs here as a step that
  // reads the old shape and writes the new one, then bumps `version`; keeping
  // the loop means a file several versions behind is brought forward in order
  // rather than only from the last one.
  while (version < VERSION) {
    version++
  }

  state.version = VERSION
  return state
}

if (typeof module !== "undefined") {
  module.exports = {
    VERSION: VERSION,
    versionOf: versionOf,
    upgrade: upgrade
  }
}
