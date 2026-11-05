// Pure helpers for the menu tree: cloning and merging. Keeping these in a plain
// JavaScript module means they can be unit-tested without a QML engine and
// reused by anything that needs to combine menu entries.

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

// Merge the user's entries over the shipped ones, by group name for a group
// and by label within its group for a leaf. A user entry with the same identity
// replaces the shipped one; a new one is appended. `"hidden": true` removes the
// shipped entry instead, which is the only way to take something off the menu
// without a rebuild.
function mergeEntries(base, extra) {
  const out = (base || []).map(function (entry) { return clone(entry) })
  const items = Array.isArray(extra) ? extra : []

  for (const item of items) {
    if (!item || typeof item !== "object") continue

    const isGroup = item.group !== undefined && Array.isArray(item.entries)
    const key = isGroup ? "group" : "label"
    const value = String(item[key] || "")

    let found = -1
    if (value !== "") {
      for (let i = 0; i < out.length; i++) {
        const candidate = out[i]
        const candidateIsGroup = candidate && candidate.group !== undefined
          && Array.isArray(candidate.entries)
        if (candidateIsGroup === isGroup && String(candidate[key] || "") === value) {
          found = i
          break
        }
      }
    }

    if (item.hidden === true) {
      if (found >= 0) out.splice(found, 1)
      continue
    }

    if (isGroup) {
      if (found >= 0) out[found].entries = mergeEntries(out[found].entries, item.entries)
      else out.push(clone(item))
      continue
    }

    if (found >= 0) out[found] = clone(item)
    else out.push(clone(item))
  }

  return out
}

function isGroup(entry) {
  return !!entry && entry.group !== undefined && Array.isArray(entry.entries)
}