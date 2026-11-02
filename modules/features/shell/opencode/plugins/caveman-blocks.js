// Caveman Blocks for OpenCode V2. Forwards each shell call to
// `caveman-blocks hook --harness generic` and appends the returned hint to the
// tool result. Never blocks, never rewrites, fails open: without the binary, or
// on any error, OpenCode runs exactly as it would without this file.
//
// The V2 API is a default export with an id and setup(ctx), so this file needs
// no SDK import: Plugin.define is an identity helper, and keeping the plugin
// dependency-free lets it load from the read-only Nix store copy.
//
// `caveman-blocks hooks install --harness opencode` (0.1.0-rc.5) still writes
// the V1 template; this is the V2 port, managed here so a reinstall cannot
// silently bring the broken version back.

import { spawnSync } from "node:child_process"
import { existsSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

const INSTALLED = "/home/son/.local/share/caveman-blocks/bin/caveman-blocks"
const SHELL_TOOLS = new Set(["bash", "shell"])

function binary() {
  const candidates = [
    process.env.CAVEMAN_BLOCKS_BIN,
    INSTALLED,
    join(homedir(), ".local/share/caveman-blocks/bin/caveman-blocks" + (process.platform === "win32" ? ".exe" : "")),
  ]
  for (const path of candidates) {
    if (path && existsSync(path)) return path
  }
  return "caveman-blocks" // PATH; a missing binary is swallowed by hook()
}

function hook(request) {
  try {
    const result = spawnSync(binary(), ["hook", "--harness", "generic"], {
      input: JSON.stringify({ protocol: 1, harness: "opencode", ...request }),
      encoding: "utf8",
      timeout: 5000,
    })
    return result.status === 0 && result.stdout ? JSON.parse(result.stdout).hint || "" : ""
  } catch {
    return ""
  }
}

// A tool result may carry its visible text as a string, as content blocks, or
// as a structured `output`. Append where the text already lives; if there is
// nowhere to append, make the hint the content rather than drop it.
function withHint(result, hint) {
  const content = result.content
  if (typeof content === "string") return { ...result, content: content + "\n\n" + hint }
  if (Array.isArray(content)) return { ...result, content: [...content, { type: "text", text: hint }] }
  if (typeof result.output === "string") return { ...result, output: result.output + "\n\n" + hint }
  return { ...result, content: hint }
}

export default {
  id: "caveman-blocks",
  async setup(ctx) {
    const hints = new Map() // call id -> hint from the pre phase, delivered after the call

    await ctx.tool.hook("execute.before", (event) => {
      if (!SHELL_TOOLS.has(event.tool)) return

      const input = event.input || {}
      const hint = hook({
        phase: "pre",
        session: event.sessionID,
        call_id: event.id,
        cwd: input.workdir || ctx.location.directory,
        command: String(input.command ?? ""),
      })
      if (hint) hints.set(event.id, hint)
    })

    await ctx.tool.hook("execute.after", (event) => {
      const hint = hints.get(event.id)
      hints.delete(event.id)
      if (!hint || event.status !== "completed") return

      event.result = withHint(event.result, hint)
    })
  },
}
