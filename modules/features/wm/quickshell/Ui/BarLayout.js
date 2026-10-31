// Pure layout mutation helpers for the bar.
//
// Everything here operates on plain JSON-shaped config objects and returns a
// new object (or null when the request cannot be applied). Keeping this logic
// out of BarConfig.qml means it can be unit-tested with node without a QML
// runtime, and BarConfig becomes a thin adapter over these functions plus the
// file I/O.

var SECTIONS = ["left", "centerBegin", "center", "centerEnd", "tray", "right"]

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function isSection(name) {
  return SECTIONS.indexOf(String(name || "")) !== -1
}

function layoutOf(config) {
  return (config && config.layout && typeof config.layout === "object") ? config.layout : {}
}

function isEnabled(config, id) {
  const layout = layoutOf(config)
  for (const name in layout) {
    const list = layout[name]
    if (!Array.isArray(list)) continue
    for (let i = 0; i < list.length; i++) {
      if (list[i] && list[i].id === id) return true
    }
  }
  return false
}

function sectionOf(id, defaults) {
  defaults = defaults || {}
  const entry = defaults[id]
  if (typeof entry === "string") return entry
  if (entry && typeof entry === "object" && entry.section) return String(entry.section)
  return "right"
}

function move(config, id, toSection, index) {
  if (!id || !toSection) return null
  toSection = String(toSection)
  if (!isSection(toSection)) return null

  const next = clone(config || {})
  next.layout = next.layout || {}

  let fromSection = ""
  let fromIndex = -1
  let entry = null

  for (const name in next.layout) {
    const list = next.layout[name]
    if (!Array.isArray(list)) continue
    for (let i = 0; i < list.length; i++) {
      if (list[i] && list[i].id === id) {
        fromSection = name
        fromIndex = i
        entry = list[i]
        list.splice(i, 1)
        break
      }
    }
    if (entry) break
  }

  if (!entry) return null
  if (!next.layout[toSection]) next.layout[toSection] = []

  const target = next.layout[toSection]
  let at = Number(index)
  if (!isFinite(at) || at < 0) at = target.length
  if (fromSection === toSection && fromIndex >= 0 && fromIndex < at) at -= 1
  at = Math.max(0, Math.min(target.length, at))
  target.splice(at, 0, entry)

  return next
}

function remove(config, id) {
  if (!id) return null
  if (!isEnabled(config, id)) return null

  const next = clone(config || {})
  next.layout = next.layout || {}

  let found = false
  for (const name in next.layout) {
    const list = next.layout[name]
    if (!Array.isArray(list)) continue
    for (let i = 0; i < list.length; i++) {
      if (list[i] && list[i].id === id) {
        list.splice(i, 1)
        found = true
        break
      }
    }
    if (found) break
  }
  if (!found) return null
  return next
}

function disable(config, id) {
  if (!id) return null
  if (!isEnabled(config, id)) return null

  const next = clone(config || {})
  next.layout = next.layout || {}

  let entry = null
  let from = ""
  let at = -1

  for (const name in next.layout) {
    const list = next.layout[name]
    if (!Array.isArray(list)) continue
    for (let i = 0; i < list.length; i++) {
      if (list[i] && list[i].id === id) {
        entry = list[i]
        from = name
        at = i
        list.splice(i, 1)
        break
      }
    }
    if (entry) break
  }

  if (!entry) return null
  next.disabled = Array.isArray(next.disabled) ? next.disabled : []
  next.disabled.push({ section: from, index: at, entry: entry })
  return next
}

function enable(config, id, defaults) {
  if (!id) return null
  if (isEnabled(config, id)) return null

  const next = clone(config || {})
  next.layout = next.layout || {}

  const parked = Array.isArray(next.disabled) ? next.disabled : []
  let found = -1
  for (let i = 0; i < parked.length; i++) {
    if (parked[i] && parked[i].entry && parked[i].entry.id === id) {
      found = i
      break
    }
  }

  if (found >= 0) {
    const slot = parked[found]
    parked.splice(found, 1)
    next.disabled = parked

    const section = (slot && slot.section) ? String(slot.section) : "right"
    next.layout[section] = Array.isArray(next.layout[section]) ? next.layout[section] : []
    const list = next.layout[section]
    const idx = (slot && typeof slot.index === "number") ? slot.index : list.length
    list.splice(Math.max(0, Math.min(idx, list.length)), 0, slot.entry)
  } else {
    const section = sectionOf(id, defaults)
    next.layout[section] = Array.isArray(next.layout[section]) ? next.layout[section] : []
    next.layout[section].push({ id: id })
  }

  return next
}

function setBackground(config, mode) {
  mode = String(mode || "")
  if (["clear", "glassy", "opaque"].indexOf(mode) === -1) return null
  const next = clone(config || {})
  next.background = mode
  return next
}

function setPosition(config, value) {
  const position = String(value || "")
  if (["top", "bottom", "left", "right"].indexOf(position) === -1) return null
  const next = clone(config || {})
  next.position = position
  return next
}

function setSetting(config, id, key, value) {
  if (!id || !key) return null
  const next = clone(config || {})
  next.layout = next.layout || {}

  for (const name in next.layout) {
    const list = next.layout[name]
    if (!Array.isArray(list)) continue
    for (let i = 0; i < list.length; i++) {
      const entry = list[i]
      if (entry && entry.id === id) {
        entry[key] = value
        return next
      }
    }
  }
  return null
}

function setScreens(config, id, screens) {
  if (!id) return null
  const next = clone(config || {})
  next.layout = next.layout || {}

  let found = false
  for (const name in next.layout) {
    const list = next.layout[name]
    if (!Array.isArray(list)) continue
    for (let i = 0; i < list.length; i++) {
      const entry = list[i]
      if (entry && entry.id === id) {
        if (screens === null || screens === undefined || screens === "all"
            || (Array.isArray(screens) && screens.length === 0)) {
          delete entry.screens
        } else if (typeof screens === "string") {
          entry.screens = [screens]
        } else {
          entry.screens = Array.isArray(screens) ? screens.slice() : [String(screens)]
        }
        found = true
        break
      }
    }
    if (found) break
  }
  if (!found) return null
  return next
}

function visibleOnScreens(entry, screenName) {
  if (!entry) return true
  const screens = entry.screens
  if (screens === undefined || screens === null) return true
  if (typeof screens === "string") {
    if (screens === "" || screens === "all") return true
    return screens === screenName
  }
  if (!Array.isArray(screens) || screens.length === 0) return true
  if (screens.indexOf("all") !== -1) return true
  if (screenName === "" || screenName === undefined || screenName === null) return true
  return screens.indexOf(screenName) !== -1
}

function sectionFor(config, id, defaults) {
  const layout = layoutOf(config)
  for (const name in layout) {
    const list = layout[name]
    if (!Array.isArray(list)) continue
    for (let i = 0; i < list.length; i++) {
      if (list[i] && list[i].id === id) return name
    }
  }

  const parked = (config && Array.isArray(config.disabled)) ? config.disabled : []
  for (let i = 0; i < parked.length; i++) {
    if (parked[i] && parked[i].entry && parked[i].entry.id === id) {
      return String(parked[i].section || sectionOf(id, defaults))
    }
  }
  return sectionOf(id, defaults)
}

function knownModules(config, defaults, registryIds) {
  const out = []
  function add(id) {
    id = String(id || "")
    if (id !== "" && out.indexOf(id) === -1) out.push(id)
  }
  const reg = Array.isArray(registryIds) ? registryIds : []
  for (let i = 0; i < reg.length; i++) add(reg[i])
  const defs = defaults || {}
  for (const id in defs) add(id)

  const layout = layoutOf(config)
  for (const name in layout) {
    const list = layout[name]
    if (!Array.isArray(list)) continue
    for (let i = 0; i < list.length; i++) {
      if (list[i]) add(list[i].id)
    }
  }

  const parked = (config && Array.isArray(config.disabled)) ? config.disabled : []
  for (let i = 0; i < parked.length; i++) {
    if (parked[i] && parked[i].entry) add(parked[i].entry.id)
  }

  out.sort()
  return out
}

function enabledModules(config) {
  const out = []
  const layout = layoutOf(config)
  for (const name in layout) {
    const list = layout[name]
    if (!Array.isArray(list)) continue
    for (let i = 0; i < list.length; i++) {
      const entry = list[i]
      if (entry && entry.id && out.indexOf(String(entry.id)) === -1) out.push(String(entry.id))
    }
  }
  out.sort()
  return out
}

function availableModules(config, defaults, registryIds) {
  const known = knownModules(config, defaults, registryIds)
  return known.filter(function (id) { return !isEnabled(config, id) })
}

if (typeof module !== "undefined") {
  module.exports = {
    SECTIONS: SECTIONS,
    clone: clone,
    isSection: isSection,
    isEnabled: isEnabled,
    sectionOf: sectionOf,
    move: move,
    disable: disable,
    remove: remove,
    enable: enable,
    setBackground: setBackground,
    setPosition: setPosition,
    setSetting: setSetting,
    sectionFor: sectionFor,
    setScreens: setScreens,
    visibleOnScreens: visibleOnScreens,
    knownModules: knownModules,
    enabledModules: enabledModules,
    availableModules: availableModules
  }
}
