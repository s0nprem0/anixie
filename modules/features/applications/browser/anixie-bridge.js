/* anixie-bridge: live theme vars for LibreWolf.
   Loaded only when `anixie.applications.browser.liveBridge` is enabled
   (autoconfig). Polls the profile's chrome/palette.json and updates
   --anixie-* custom properties on every open window so chrome CSS can
   recolor without a restart. Defensive: any failure is logged, never fatal. */
try {
  const { Services } = ChromeUtils.import("resource://gre/modules/Services.jsm");

  const POLL_MS = 3000;

  function profFile(name) {
    try {
      const dir = Services.dirsvc.get("ProfD", Ci.nsIFile);
      const f = dir.clone();
      f.append("chrome");
      f.append(name);
      return f;
    } catch (e) { return null; }
  }

  async function readPalette() {
    try {
      const f = profFile("palette.json");
      if (!f || !f.exists()) return null;
      const { IOUtils } = ChromeUtils.import("resource://gre/modules/IOUtils.jsm");
      return await IOUtils.readJSON(f.path);
    } catch (e) {
      console.error("anixie-bridge: readPalette", e);
      return null;
    }
  }

  function mapVars(p) {
    if (!p) return null;
    const g = (k, fb) => (p[k] && typeof p[k] === "string" ? p[k] : fb);
    return {
      bg: g("background", "#15130c"),
      bgDark: g("bgDark", "#0f0f0f"),
      bgLight: g("bgLight", "#222017"),
      fg: g("foreground", "#e8e2d4"),
      fgLight: g("fgLight", "#cdc6b4"),
      surface: g("surface", "#222017"),
      surfaceContainer: g("surfaceContainer", "#2c2a21"),
      surfaceVariant: g("surfaceVariant", "#4a4739"),
      muted: g("muted", "#cdc6b4"),
      outline: g("outline", "#969080"),
      primary: g("primary", "#d9c76f"),
      accent: g("accent", "#a8d0b4"),
      accentAlt: g("accentAlt", "#d0c7a2"),
      secondary: g("secondary", "#a8d0b4"),
      tertiary: g("tertiary", "#d9c76f"),
      danger: g("danger", "#ffb4ab"),
      success: g("success", "#a6e3a1"),
      yellow: g("yellow", "#f0c674"),
      focus: g("focus", "#d9c76f"),
    };
  }

  function applyVars(doc, vars) {
    if (!doc || !vars) return;
    let style = doc.getElementById("anixie-vars");
    if (!style) {
      style = doc.createElement("style");
      style.id = "anixie-vars";
      const host = doc.head || doc.documentElement;
      if (host) host.appendChild(style);
    }
    const lines = [":root {"];
    for (const k in vars) {
      lines.push("  --anixie-" + k + ": " + vars[k] + ";");
    }
    lines.push("}");
    style.textContent = lines.join("\n");
  }

  async function refreshDoc(doc) {
    const p = await readPalette();
    const v = mapVars(p);
    if (v) applyVars(doc, v);
  }

  Services.obs.addObserver(function (subject) {
    try {
      const win = subject;
      const doc = win && win.document;
      if (doc) {
        if (doc.readyState === "complete" || doc.readyState === "interactive") {
          refreshDoc(doc);
        } else {
          win.addEventListener("DOMContentLoaded", function () { refreshDoc(doc); }, { once: true });
        }
      }
    } catch (e) {
      console.error("anixie-bridge: window", e);
    }
  }, "domwindowopened", false);

  setInterval(async function () {
    try {
      const en = Services.wm.getEnumerator("navigator:browser");
      while (en.hasMoreElements()) {
        const win = en.getNext();
        if (win && win.document) await refreshDoc(win.document);
      }
    } catch (e) {
      console.error("anixie-bridge: poll", e);
    }
  }, POLL_MS);

  // Initial pass for already-open windows at load time.
  try {
    const en = Services.wm.getEnumerator("navigator:browser");
    while (en.hasMoreElements()) {
      const win = en.getNext();
      if (win && win.document) refreshDoc(win.document);
    }
  } catch (e) {}
} catch (e) {
  console.error("anixie-bridge: init", e);
}
