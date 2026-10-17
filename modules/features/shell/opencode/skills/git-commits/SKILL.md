---
name: git-commits
description: |-
  Write clear conventional commit messages and structure pull request
  descriptions consistently. Use when committing changes, drafting a PR,
  writing a changelog entry, naming a branch, or deciding how to split a
  diff into multiple commits.
  Examples:
  - user: "commit these changes" → format as a conventional commit with
    the right type and scope
  - user: "write a PR description for this branch" → structure with
    Summary / Changes / Testing sections
  - user: "what type should I use for a typo fix" → fix vs chore guidance
  - user: "should this be one commit or two" → split by logical unit of
    change, not by file
---

# Git Commits & Pull Requests

Help the user write commit messages and PR descriptions that stay useful
months later, when nobody remembers the conversation that produced them.

## Commit message format

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Subject line**
- Imperative mood: "add", "fix", "remove" — not "added", "fixes", "removes"
- No period at the end
- Keep it under ~50 characters; if the change needs more explanation, that
  belongs in the body, not a longer subject
- Lowercase the type and scope; subject text itself follows normal
  sentence casing

**Type** — pick the one that matches what changed, not how it felt to write:

| type | when to use it |
|---|---|
| `feat` | a new capability the user can see or call |
| `fix` | corrects broken behavior |
| `docs` | documentation only, no code change |
| `style` | formatting, whitespace, semicolons — no logic change |
| `refactor` | restructures code without changing behavior |
| `perf` | improves performance without changing behavior |
| `test` | adds or fixes tests only |
| `build` | build system, dependencies, tooling config |
| `ci` | CI pipeline configuration |
| `chore` | maintenance that doesn't fit elsewhere (renaming files, bumping a version) |
| `revert` | reverts a previous commit |

A typo fix in a comment is `docs` or `chore`, not `fix` — `fix` implies a
behavior change a user would notice.

**Scope** — the area of the codebase affected, lowercase, no spaces:
`feat(auth):`, `fix(checkout):`, `chore(deps):`. Omit the scope entirely if
the change is genuinely cross-cutting rather than guessing one.

**Body** — required for anything non-trivial. Wrap at ~72 characters.
Explain *what changed and why*, not a line-by-line narration of the diff
(the diff already shows that). Past tense or present tense is fine as
long as it's consistent; what matters is that it answers "why would
someone have made this change."

**Footer** — used for two things only:
- `BREAKING CHANGE: <description>` when the change breaks a public API,
  config format, or CLI interface
- Issue references: `Closes #123`, `Refs #456`

## Splitting changes into commits

Split by logical unit of change, not by file count or by "I worked on
this for an hour so it's a commit." A good split means each commit could
be reverted independently without breaking the others. If a diff mixes
an unrelated formatting pass with an actual fix, separate them — the
formatting noise makes the real change hard to review.

If the user hands you a large, mixed diff, propose a split before
committing: list the logical groups and ask for confirmation, rather
than committing everything as one lump or guessing at boundaries.

## Pull request descriptions

Default structure, adjusted to fit the size of the change:

```
## Summary
One or two sentences: what this PR does and why, written for someone who
has not been following the work.

## Changes
- Bullet list of the meaningful changes, grouped logically, not a raw
  list of every file touched.

## Testing
How this was verified: tests added, manual steps taken, edge cases
checked. If nothing was tested, say so explicitly rather than omitting
the section — a reviewer needs to know.

## Notes
Anything a reviewer needs but that doesn't fit above: follow-up work
intentionally left out of scope, a tradeoff that was made on purpose,
a screenshot for UI changes.
```

For a one-line fix, collapse this to a single sentence — don't force the
full template onto a trivial change. For a large or risky change, expand
the Testing section rather than the Summary; reviewers trust a PR more
when they can see how it was verified.

## Branch naming

`<type>/<short-description>`, lowercase, hyphenated: `fix/checkout-timeout`,
`feat/dark-mode-toggle`. Match the type vocabulary used in commits so the
branch name predicts the commit type before you even open the diff.

See `references/conventional-commits-cheatsheet.md` for a condensed
type lookup table.
