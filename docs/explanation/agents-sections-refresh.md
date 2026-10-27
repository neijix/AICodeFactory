# How the generic AGENTS.md sections are refreshed

`AGENTS.md` belongs to the project, yet two of its sections come from the template and should
improve everywhere when the template does. The refresh replaces such a section only when the
project's text is still exactly some version the template once had, so nothing you wrote is
ever overwritten.

## The sections

`skills/bootstrap-ai/scripts/refresh-agents-sections.py` handles three lists of headings, matched
by exact text:

| List | Headings | What happens |
|---|---|---|
| Generic | `## Session start (do this first, ~10s)`, `## Post-task checklist — checkpoint policy (every response, no exceptions)` | Replaced with the current template's text while never customized |
| Retired | `## Bootstrap mode — delegate only`, `## On-demand skills (…)`, `## Delegation — …`, `## Living documents` | Removed while never customized |
| Scaffold | `## Taste` | Added from the template when missing; never touched again |

## How it decides a section was never customized

For each generic or retired section, the script reads every version of
`templates/AGENTS.md.template` in the factory's git history (and of `AGENTS.md.template`, its
path before `templates/` existed). If the project's section equals one of those versions,
ignoring trailing whitespace and trailing blank lines, nobody edited it: it is replaced, or removed for a retired one.
Otherwise it is left alone and reported as `KEPT`, for you to merge by hand.

This is why the factory must stay a git checkout with its history: a shallow or exported copy
cannot prove a section was never edited, so it would keep everything.

## When it runs

- At every session start, as the hook's `--agents` step.
- With every `aicf update` run, for each processed project.
- By hand: `uv run skills/bootstrap-ai/scripts/refresh-agents-sections.py --dry-run <project>`
  (or `--all` for every bootstrapped sibling; `--commit` to commit).

## What it never touches

- A **shared** project (`--shared`): its `AGENTS.md` speaks to every contributor.
- A **team** project that tracks `AGENTS.md`: the file is the team's.
- With `--commit`, an `AGENTS.md` that has uncommitted edits: the commit would sweep them in.
- In a **private** project it writes the file but never commits it to the code repo; the hidden
  repo picks it up.

## What it prints

In the hook (`--quiet`), one line when something changed:

```text
ai-sync: AGENTS.md generic sections refreshed — <sections> (committed)
```

By hand, one line per project and outcome: `UPDATED` (or `PLAN` with `--dry-run`), `KEPT`
(customized, merge by hand if you want the new text), `MISSING` (heading not found), `SKIP`
(shared project, team-owned `AGENTS.md`, or uncommitted edits).

## For template authors

The headings are an interface: renaming one in the template makes every project report it
`MISSING`. To drop a section, move its heading to the retired list instead of deleting it, so
untouched copies are removed and customized ones are kept. `tests/lint-skills.py` checks that
every listed heading is still a line of the template.
