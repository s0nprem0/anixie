# Conventional Commits — Quick Lookup

| Type | Meaning | Triggers a release bump? |
|---|---|---|
| `feat` | new capability | minor |
| `fix` | bug fix | patch |
| `docs` | documentation only | none |
| `style` | formatting, no logic change | none |
| `refactor` | restructure, same behavior | none |
| `perf` | performance improvement | patch |
| `test` | test-only change | none |
| `build` | build system / dependencies | none |
| `ci` | CI configuration | none |
| `chore` | misc maintenance | none |
| `revert` | reverts a prior commit | depends on reverted commit |

`BREAKING CHANGE:` in the footer (any type) → major bump, regardless of
the type prefix.

## Subject line checklist

- [ ] Imperative mood ("add", not "added")
- [ ] No trailing period
- [ ] Under ~50 characters
- [ ] Type matches what actually changed, not how big it felt
- [ ] Scope present only if there's a clear, single area affected

## Good vs. weak examples

Weak: `fix: fixed stuff`
Better: `fix(checkout): retry failed payment requests once before erroring`

Weak: `update code`
Better: `refactor(api): extract pagination logic into shared helper`

Weak: `feat: added the thing we discussed`
Better: `feat(notifications): add daily digest email opt-in`
