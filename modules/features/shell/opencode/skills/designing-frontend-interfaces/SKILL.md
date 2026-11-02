---
name: designing-frontend-interfaces
description: Use when building or restyling a web interface — landing pages, dashboards, marketing sites, web apps, React/Vue components, HTML/CSS layouts — or when asked to make a UI look better, more polished, more distinctive, less generic, or less "AI-generated". Also use when a design brief, art direction, visual identity, type scale, or color system is needed before implementation. Not for localized fixes inside an existing design system — reuse that system's tokens instead (see When the Iron Law does not apply).
license: Complete terms in LICENSE.txt
---

# Designing Frontend Interfaces

## Overview

Distinctive interfaces come from **committing to one aesthetic direction and executing it with a locked system of values**. Generic interfaces come from picking each value ad hoc at the moment it is needed.

**Core principle:** Decide the system before you write the components. Every number in the finished CSS should trace back to a scale you chose deliberately.

This skill covers **visual craft**. Two companion skills cover the rest of interface quality:

- **REQUIRED SUB-SKILL** for anything with flows, forms, or non-trivial state: use `designing-user-experience`
- **REQUIRED SUB-SKILL** before shipping: use `building-accessible-interfaces`
- To critique a finished UI, use `reviewing-interface-quality`

## The Iron Law

```
NO COMPONENT CODE BEFORE THE DESIGN BRIEF AND TOKEN BLOCK EXIST
```

The brief is 8 lines. The token block is one CSS block. Together they cost about ninety seconds and they are what separates a designed interface from a decorated one.

Wrote components first? The values are already arbitrary. Extract them into a real scale before continuing — do not rationalize the numbers you happened to type.

### When the Iron Law does not apply

The brief and the token block are for **new surfaces and restyles**. Following
them on a bug fix causes real damage.

Skip both when:

- The project **already has a design system**. Find its tokens and use them.
  Writing a new `:root` block beside an existing one starts a second, competing
  system — the most common way generated UI lands badly in a real codebase.
- The change is **localized**: one component, one state, one breakpoint fix. An
  8-line brief and a fresh type scale for a two-line fix is scope inflation.
- The user asked for a **specific** visual outcome. Execute it; do not substitute
  your own direction.

The discipline still applies in those cases — aimed at the existing system. Match
its spacing scale, radius, and ink levels. If you need a value it lacks, add one
token to *its* scale in *its* convention and say that you did.

For scoped implementation inside an existing UI, prefer `frontend-developer`. Use
this skill when the surface is new or the visual direction is genuinely in
question.

### Before Step 1: find the existing system

On any real project, run this first. It takes seconds and it decides whether the
rest of this skill applies.

```bash
# CSS custom properties / design tokens
rg -l -e '^\s*--[a-z-]+\s*:' -g '*.css' -g '*.scss' -g '*.less' -g '*.ts' -g '*.tsx' . 2>/dev/null
# theme objects and token frameworks
rg -l -e 'theme\.' -e '@theme' -e '--color-' -e '--space-' -e 'tailwind\.config' . 2>/dev/null
# where the styles live at all
fd -e css -e scss -e less . src app styles components 2>/dev/null | head
```

All three are silent when there is nothing to find — that is a valid answer meaning
"no existing system", not a failure. You are looking for a token file, a Tailwind
or vanilla-extract theme object, a `tailwind.config` theme block, or a block of
CSS custom properties. If one exists, **that** is the system — read it, extend it,
and jump to Step 3.

Only start from the blank token block in Step 2 when there is genuinely nothing to
extend: a new page, a prototype, a static artifact.

## Checklist

Create a task for each item and complete them in order:

1. **Write the design brief** — 8 lines, in your response, before any file is created
2. **Choose an aesthetic direction** — from `references/aesthetic-directions.md`, or invent one, and name it
3. **Lock the token block** — type scale, color ramp, space scale, radius, shadow, motion. One CSS block.
4. **Build the layout skeleton** — structure and spacing, no decoration yet
5. **Build components** — every interactive element gets all five states
6. **Add the one memorable moment** — the single thing someone will remember
7. **Self-review against the rubric** — see Self-Review below; fix what fails
8. **Verify visually** — render it and actually look at it

## Step 1: The Design Brief

Write this out before creating any file. It is 8 lines of plain text in your response — not a document, not a file.

```
Purpose:    What job does this interface do?
Audience:   Who uses it, in what context, on what device?
Tone:       One named direction (see references/aesthetic-directions.md)
Reference:  A real-world visual analogue — a magazine, a era, a discipline
Palette:    Base / surface / ink / one accent — as hue intentions, not hex yet
Type:       Display face + text face, and why this pairing
Memorable:  The one thing someone will describe to a friend
Restraint:  What this design deliberately does NOT do
```

The `Restraint` line matters most. A design with no stated restraint becomes a design with every effect applied at once.

**Worked example:**

```
Purpose:    Changelog for a developer infrastructure tool
Audience:   Engineers skimming on a wide monitor, 30 seconds per visit
Tone:       Technical Broadsheet — newspaper density meets terminal precision
Reference:  Financial Times print edition, 1990s man pages
Palette:    Warm newsprint base, near-black ink, one signal red for breaking changes
Type:       Instrument Serif display / IBM Plex Mono text — editorial authority, machine detail
Memorable:  Version numbers set enormous in the left margin, hanging outside the text column
Restraint:  No cards. No shadows. No rounded corners. Rules and space only.
```

## Step 2: Lock the Token Block

Every value the interface uses comes from here. If a number is not in this block, it does not belong in a component.

```css
:root {
  /* TYPE — one ratio, applied consistently. 1.200 minor third (dense UI),
     1.250 major third (general), 1.333 perfect fourth (marketing),
     1.500 perfect fifth (editorial/poster). Pick ONE. */
  --font-display: "Instrument Serif", Georgia, serif;
  --font-text:    "IBM Plex Mono", ui-monospace, monospace;
  --step--1: 0.833rem;  --step-0: 1rem;     --step-1: 1.25rem;
  --step-2:  1.563rem;  --step-3: 1.953rem; --step-4: 2.441rem;
  --step-5:  3.052rem;  --step-6: 3.815rem;

  /* SPACE — one base unit and its multiples. Never a value in between. */
  --space-3xs: 0.25rem; --space-2xs: 0.5rem; --space-xs: 0.75rem;
  --space-s:   1rem;    --space-m:   1.5rem; --space-l:  2rem;
  --space-xl:  3rem;    --space-2xl: 4.5rem; --space-3xl: 7rem;

  /* COLOR — a ramp, not a set of one-offs. One accent, used sparingly. */
  --base:    #f4f1ea;   /* page */
  --surface: #ffffff;   /* raised */
  --ink:     #12100e;   /* primary text */
  --ink-2:   #55504a;   /* secondary text */
  --ink-3:   #8b857c;   /* tertiary / meta */
  --line:    #ddd7cc;   /* borders, rules */
  --accent:  #c1362f;   /* <10% of visible surface */

  /* FORM */
  --radius: 0;          /* commit: 0, or 2-4px, or a full 999px pill. Not "some of each". */
  --border: 1px solid var(--line);
  --shadow: none;       /* if using shadows, define 2 — near and far. Never 5. */

  /* MOTION */
  --dur-fast: 120ms; --dur: 220ms; --dur-slow: 420ms;
  --ease:     cubic-bezier(0.2, 0, 0, 1);
  --ease-out: cubic-bezier(0.16, 1, 0.3, 1);
}
```

**Rules for the block:**

| Token | Rule |
|---|---|
| Type scale | One ratio for the whole page. Deriving sizes by eye produces muddy hierarchy. |
| Space scale | Every margin/padding/gap is a `--space-*` token. No `13px`. No `0.85rem`. |
| Color ramp | Three ink levels is enough. A fourth means the hierarchy is unclear. |
| Accent | Exactly one, unless the direction is explicitly maximalist. Under 10% of surface. |
| Radius | One value. Mixed radii is the single loudest amateur signal. |
| Shadow | Zero or two. Two shadows = one tight contact shadow + one wide ambient. |
| Motion | Three durations, two easings. That covers every transition an interface needs. |

## Step 3: Hierarchy

**Vary one dimension at a time.** Amateur hierarchy changes size *and* weight *and* color *and* spacing simultaneously; everything shouts and nothing leads.

| Need | Change | Keep fixed |
|---|---|---|
| Section heading vs. body | Size (2+ steps) | Weight, color |
| Emphasis inside a paragraph | Weight | Size, color |
| Metadata / captions | Color (to `--ink-3`) | Size, weight |
| Grouping | Space (a full step) | Everything else |

**Space groups more reliably than lines or boxes.** Before adding a border or a card, try doubling the gap between groups and halving it within them. Most "needs a card" instincts are actually "needs correct spacing."

## Step 4: Anti-Slop

Generic AI interface output has a specific, enumerable signature. These are not stylistic preferences — they are the exact defaults that make output identifiable on sight.

| Never | Instead |
|---|---|
| Inter, Roboto, Arial, `system-ui` as the display face | A face with an opinion — see `references/typography.md` |
| Purple/violet → blue gradient on white | Commit to a real palette from a real reference |
| `rounded-lg` / `rounded-xl` on everything | One radius, chosen; or zero radius |
| A `shadow-md` on every surface | Shadows only where something genuinely floats |
| Hero → 3 feature cards → CTA | Let the content decide the structure |
| A centered `max-w-4xl` column for the whole page | Vary measure by content type; break the grid at least once |
| `text-gray-500` body text on white | Real ink colors with intent; body text at full contrast |
| Emoji standing in for icons | A real icon set, or no icons |
| Six weights of one neutral sans | Two faces, three weights, maximum |
| Every section the same vertical rhythm | Vary section spacing to express importance |

**The convergence trap:** across separate generations, do not keep reaching for the same "safe distinctive" choices. Space Grotesk, a dark slate background, and a lime-green accent is now its own cliché. Vary light and dark, serif and sans and mono, dense and airy, across designs. Check `references/aesthetic-directions.md` and pick one you did not pick last time.

**Rationalization table:**

| Thought | Reality |
|---|---|
| "The user didn't specify a style, so neutral is safest" | Unspecified means you choose. Neutral is a choice, and it is the worst one. |
| "It's just a quick demo" | Demos are what people look at. The brief takes ninety seconds. |
| "Inter is genuinely a good typeface" | It is. It is also the single strongest generic-AI signal. Use it for body text at most, never for display. |
| "A card grid is the clearest way to show features" | It is the most *common* way. Try a table, a list with rules, a stepped layout, an editorial spread. |
| "I'll add the distinctive touches at the end" | Distinctiveness is structural. Bolted on at the end it reads as decoration. |
| "Tailwind defaults are a design system" | They are a *palette* of defaults. Configure them, or you ship the defaults everyone ships. |

## Step 5: Component States

Every interactive element gets all five. Missing states are the most common gap in generated UI.

```css
.btn              { /* rest */ }
.btn:hover        { /* pointer only — must not be the sole affordance */ }
.btn:active       { /* pressed — a real transform, not just a color shift */ }
.btn:focus-visible{ outline: 2px solid var(--accent); outline-offset: 2px; }
.btn:disabled     { /* visibly inert, and still readable */ }
.btn[aria-busy]   { /* loading — reserve the space, don't collapse the layout */ }
```

Never remove focus outlines. If the default outline is ugly, restyle it — do not set `outline: none`. See `building-accessible-interfaces`.

## Step 6: Verify Visually

Rendering code and reading it back is not verification. Look at the actual pixels.

**Preflight first — do not skip to the screenshot script:**

```bash
python3 -c "import playwright" 2>/dev/null && echo "playwright: ready" || echo "playwright: MISSING"
```

If it reports MISSING, do not fake the verification and do not describe the render
from reading the code. Say plainly that the visual check could not run, and offer
the install:

```bash
uv venv ~/.local/opencode-venv && uv pip install --python ~/.local/opencode-venv/bin/python playwright
~/.local/opencode-venv/bin/playwright install chromium
```

Use that venv's interpreter for the script below. It is a real dependency and
pulls a browser — ask before installing it, do not assume it is there.

**Screenshot a static page:**

```bash
~/.local/opencode-venv/bin/python -c "
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page(viewport={'width':1440,'height':900})
    pg.goto('file:///abs/path/index.html'); pg.wait_for_timeout(600)
    pg.screenshot(path='/tmp/desktop.png', full_page=True)
    pg.set_viewport_size({'width':390,'height':844})
    pg.screenshot(path='/tmp/mobile.png', full_page=True)
    b.close()"
```

Then **Read both PNGs** — the Read tool displays images, so the check is real —
and grade them against the rubric.

**For a dev server, never run it in the foreground.** Start it backgrounded, poll
the log, then screenshot, then kill it:

```bash
npm run dev > /tmp/dev.log 2>&1 &
sleep 4; tail -20 /tmp/dev.log        # confirm it is actually up
# ... screenshot http://localhost:PORT ...
kill %1
```

**This machine is NixOS (Hyprland, x86_64-linux).** Notes that save real time:

- Playwright is not on `PATH` and is not in the profile — it only exists inside a
  per-project virtualenv (see the preflight above). Never assume
  `npx playwright` or a system `playwright` works.
- Playwright's `install chromium` writes to `~/.cache/ms-playwright`, outside the
  Nix store. `nix-store --gc` does not reclaim it; clear it by hand if disk
  gets tight.
- Headless Chromium renders with the system fonts only, and this machine's font
  set is managed by NixOS. A screenshot shows what NixOS renders, not what a
  user's browser on another platform shows. Do not present it as such.
- Add `--force-color-profile=srgb` to `launch()` args if a screenshot looks
  washed out; the compositor manages the display's profile, not headless Chromium.
- Projects are expected under `~/`, not on a foreign filesystem. If a path is on
  an external or network mount, build there and copy the result back before
  verifying — file watchers are unreliable across such mounts.

**What to look for that only shows in the render:** text overflowing containers,
collapsed layouts at 390px, invisible low-contrast text, elements touching
viewport edges, a heading that wraps to one orphaned word, images without
dimensions causing layout shift.

## Self-Review

Score each line honestly. Any `no` means fix it, not explain it.

- [ ] Every spacing value in the CSS is a token from the block
- [ ] If the project had an existing token system, it was extended, not replaced
- [ ] The type scale is one ratio; no size was chosen by eye
- [ ] Exactly one accent color, under 10% of visible surface
- [ ] One radius value throughout
- [ ] A stranger could name the aesthetic direction from a screenshot
- [ ] The `Memorable` line from the brief is actually present in the build
- [ ] The `Restraint` line was actually respected
- [ ] Nothing from the Anti-Slop table appears
- [ ] All five states exist on every interactive element
- [ ] Focus is visible and never suppressed
- [ ] Verified at 1440px and 390px by looking at screenshots
- [ ] Body text passes 4.5:1; large text passes 3:1

## Reference Files

Load these when you reach the relevant decision — not upfront.

| File | Load when |
|---|---|
| `references/aesthetic-directions.md` | Step 1 — choosing and parameterizing a direction |
| `references/typography.md` | Choosing faces, building the scale, setting text |
| `references/color-and-theme.md` | Building the ramp, dark mode, contrast math |
| `references/layout-and-composition.md` | Grids, breakpoints, breaking the grid, z-index |
| `references/motion.md` | Any animation beyond a hover color change |

## Common Mistakes

**Tokens declared, then ignored.** The `:root` block exists but components use `padding: 14px`. Grep your CSS for raw px values before finishing.

**Distinctive typeface, default everything else.** Swapping Inter for a display face while keeping the card grid, the uniform radius, and the gray body text produces generic output in a costume.

**Maximalism as an excuse for incoherence.** Maximalist directions still need one type scale, one space scale, one palette. More elements, same system.

**The brief describes a design the build does not deliver.** Re-read the brief at Step 7. If `Restraint: no shadows` and the build has shadows, the build is wrong.

**Complexity mismatched to the vision.** A refined-minimal direction implemented with elaborate scroll animations reads as confused. Match implementation effort to the stated tone.

**A parallel token system.** The most damaging outcome, and the reason the
"find the existing system" step exists. A fresh `:root` block next to the
project's real tokens looks like good discipline and is the opposite: two scales,
two palettes, no way to know which one wins. Extend what is there.

---

## Local changes

Forked from [osmontero/opencode-skills](https://github.com/osmontero/opencode-skills)
`skills/designing-frontend-interfaces` (MIT, see `LICENSE.txt`). Upstream content
is intact except for the changes below, so a re-vendoring diff stays readable.

| Change | Why |
|---|---|
| Added "When the Iron Law does not apply" | The Iron Law demands a brief and token block for *any* interface work. On a localized fix that is scope inflation, and it collided with `frontend-developer`'s smallest-coherent-change rule. |
| Added "Before Step 1: find the existing system" | Upstream assumes a blank slate. In a real codebase the tokens already exist, and the original steps produce a competing second system. |
| Added "extended, not replaced" to Self-Review | Makes the above enforceable rather than advisory. |
| Rewrote Step 6 preflight and machine notes | Upstream calls Playwright unconditionally. It is not installed here, and the failure mode is an agent describing a render it never saw. Now it checks, and says so when it cannot verify. The machine notes were ported from WSL2 to NixOS. |
| Dev-server guidance | Replaced a cross-skill dependency on `testing-webapps` (not installed) with background-and-poll, matching the global AGENTS.md rule against foreground servers. |
| Narrowed `description` | Added the exclusion so small fixes route to `frontend-developer` instead of pulling in 300+ lines. |

To re-sync from upstream and keep the delta, diff against the original:

```bash
git diff --no-index \
  <(curl -sL https://raw.githubusercontent.com/osmontero/opencode-skills/main/skills/designing-frontend-interfaces/SKILL.md) \
  .config/opencode/skills/designing-frontend-interfaces/SKILL.md
```
