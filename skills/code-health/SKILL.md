---
name: code-health
description: "Use when reviewing a diff or a PR, before adding code to a file over ~800 lines or a function over ~80, when the user says a file is huge, spaghetti, copy-pasted, unmaintainable or needs splitting / refactoring / cleanup, when a project has no .code-health.json yet, or when setting up ./check.sh. Structural review rules, a ratchet gate (no file, function or copied block may be new over a limit or grow) and a safe recipe for splitting giant files. Script: scripts/code_health.py (uv, lizard)."
---

# Code health

AI-written code rots in one direction: everything gets appended to the file that already
works, and the second feature that needs the same logic gets a copy. Nobody notices until a
file is 15 000 lines and one function 4 000. This skill stops the growth (a gate every agent
runs) and pays the debt down (a refactor recipe), one project at a time.

## The script

`scripts/code_health.py`, next to this file — the same on every machine (a link on macOS /
Linux, a copy refreshed at session start on Windows). Needs only `uv`.

```bash
CH=~/.agents/skills/code-health/scripts/code_health.py     # same file under ~/.claude/skills
uv run -q "$CH" report            # hotspots, worst first: files, functions, complexity, copies
uv run -q "$CH" check             # gate: exit 1 on a new or grown offender
uv run -q "$CH" baseline          # 1st run: grandfather today's debt; later: lock gains in
uv run -q "$CH" baseline --accept # also record new/grown ones — only with the user's ok
```

PowerShell: `uv run -q "$HOME\.agents\skills\code-health\scripts\code_health.py" check`.

It scans tracked and untracked-not-ignored source files (minified, vendored, generated and
lock files skipped; add globs under `"exclude"`). Limits, overridable under `"limits"` in the
project's `.code-health.json`:

| Metric | Limit | Means |
|---|---|---|
| `file_lines` | 800 | physical lines of one source file |
| `function_lines` | 80 | lines of one function, nested functions included (lizard) |
| `function_ccn` | 20 | cyclomatic complexity of one function |
| `duplicate_lines` | 10 | a block of 10+ significant lines found at two places is a copy |

**The ratchet.** `.code-health.json` records every offender with its current size. `check`
fails when an offender is **new** or **grew**; existing debt passes. When one shrinks, run
`baseline` and commit: the record only ever goes down. A renamed giant file reads as new —
that is a `baseline --accept`, said in the commit message. No `.code-health.json` yet → `check`
compares with `HEAD`: the rule holds in every project before anyone adopts it.

Claude Code also gets a `PostToolUse` hint (project `.claude/settings.json`): an edit that
leaves a source file over the limit **and** longer than at `HEAD` prints one line to the agent.

## Adopt it in a project (once)

1. On a clean tree: `uv run -q "$CH" baseline`, commit `chore(code-health): baseline`.
2. Add to `./check.sh` (and the same guard to `check.ps1`), so every agent and the
   `verifier` subagent run it:
   ```sh
   CH="$HOME/.agents/skills/code-health/scripts/code_health.py"
   if [ -f "$CH" ]; then uv run -q "$CH" check; else echo "code-health: skill not installed, skipped"; fi
   ```
3. Note the giant files in `PROJECT_STATE.md` limitations only if a refactor is planned.

## Review rules (apply to every diff — yours, a subagent's, a PR)

A finding of rule 1-3 is **blocking**: fix it before the commit, don't list it as a nit.

1. **Size.** No new file over 800 lines, function over 80, complexity over 20; a recorded
   offender never grows. Need to touch a giant function? Extract the part you change first.
2. **No copy.** Logic that exists elsewhere is imported, not pasted. Second copy of 10+ lines
   → extract a shared module now, at two, not at three.
3. **New feature, new module.** Code goes where its name says: a feature gets its own file
   (route group, view, connector), never one more block at the bottom of `app.js` / `app.py`.
4. **No god factory.** `create_app()` wires things; it doesn't define 50 handlers as closures.
   Routes live in per-area modules (FastAPI `APIRouter`, Flask `Blueprint`) with explicit deps.
5. **Front-end in modules.** One ES module per view or component, a shared state/api module;
   browser-extension pages (popup, side panel) import the same files instead of copying them.
6. **Delete, don't comment out.** Dead code, unused exports and old variants go; git keeps them.
7. **Move ≠ change.** A refactor commit moves code without changing behavior; behavior changes
   go in their own commit, so a review can trust "pure move" diffs.
8. **Names carry the design.** A file or function whose honest name needs "and" or "utils"
   does two things — split it.
9. **Comments earn their place.** Two lines at most, one block. A comment states only what the
   code cannot: a unit or encoding the type does not carry; ownership, lifetime or thread
   affinity; a precondition a caller can break unseen; a gotcha where the code looks wrong and
   is right; an invariant whose violation is silent; an external pointer (spec, bug id). Never
   about other code (callers, "see foo.py", "mirrors X"), never a restatement or a narration
   of the body, never about the edit (task ids, plan refs, "was previously", commented-out
   code). Density check on a diff: added comment lines ≥ 1 in 10 added non-blank lines is too
   many. A project convention (`AGENTS.md`) wins on shape, not on these bans. Fix = delete.

## Paying the debt down — splitting a giant file

Never as a drive-by in a feature task; propose it, then work it as its own task
(`architect-flow` for anything past one extraction).

1. **Pick the target**: `report`, crossed with churn
   (`git log --since=6.months --format= --name-only | sort | uniq -c | sort -rn | head`) —
   a giant file nobody edits can wait; the one every feature touches cannot.
2. **Safety net first**: tests through public entry points must cover the area. Missing → add
   characterization tests (record today's behavior, even if odd); for UI, a smoke with the
   `headless-ui-smoke` skill before and after.
3. **One cohesive area per commit**: a route group, a view, a connector. Move it to its own
   module, keep the old call sites working (re-export if needed), run `./check.sh`, commit
   `refactor(scope): move <area> out of <file>`, then `baseline` and commit the lower record.
4. **Then deduplicate**: for each copy pair in `report`, extract the shared module and point
   both sides at it; check behavior on both sides.
5. **Delegate the mechanics**: each extraction is a precise subtask (source lines, target
   module, public names to keep) — a subagent or helper can do it; you review the diff, check
   it is a pure move, and run the gate.

Stop and ask when a split forces an API change other code (or another repo) depends on.
