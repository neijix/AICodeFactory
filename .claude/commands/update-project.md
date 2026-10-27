---
description: "Refresh AI-instruction pointer files for one sibling project, or preview/apply across all of them."
argument-hint: "[project-name] — omit to preview every sibling project"
allowed-tools: Bash, Read
---

# Update Project(s)

Argument: `$ARGUMENTS`

Normally unnecessary: every project re-syncs its shared AI files from this repo at session
start (Claude Code `SessionStart` hook / AGENTS.md session-start step). Use this for a one-shot
bulk refresh right after a template change, to migrate old symlink layouts, or to bootstrap a
sibling that has no AI files yet. Bulk runs only touch siblings that already own an
`AGENTS.md`; commits are paths-only (a project's work in progress is never swept in).

- If a project name was given: run `bin/aicf update "$ARGUMENTS"` — this applies for real,
  a single named project is low-risk enough not to need a preview step first.
- If no argument was given: run `bin/aicf update` (dry-run by default across every sibling
  project when no name and no flag is given), show the plan to the user, and only re-run with
  `--yes` after they confirm they want it applied to every project.

Report per project: bootstrapped / updated / already up to date / skipped (and why, e.g.
not bootstrapped or not a git repo).
