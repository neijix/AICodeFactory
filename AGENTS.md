# AGENTS.md — AICodeFactory

**PROJECT TYPE**: DevOps / Meta-tooling (AI-instruction template source repo)
**PRIMARY LANGUAGE**: Bash + PowerShell (paired scripts), Markdown templates
**FRAMEWORK**: None — plain scripts driven by `templates-manifest.txt`

The single source of truth for every AI agent in this project. It holds only what the code
cannot tell you: invariants, conventions, taste. Architecture, commands and env vars live in
`.github/PROJECT_STATE.md`; solved problems and gotchas in `.github/KNOWLEDGE.md`.

> ⚠️ **This is the template source repo.** The `*.template` files are *products* that every
> sibling under `~/Code/` copies and re-syncs at session start — not this repo's own docs. This
> repo dogfoods its layout: its pointer files (`CLAUDE.md`, `.claude/settings.json`, …) are plain
> copies of the local templates. Edit the `.template` under `templates/`, then run
> `./sync-ai-templates.sh .`. Users run `bin/aicf`; the hook contract is the root's
> `sync-ai-templates.sh|.ps1` + `templates-manifest.txt` — never move those three.

---

## Session start (do this first, ~10s)

1. Refresh the shared AI files unless your harness already did (Claude Code's hook does):
   `bash ./sync-ai-templates.sh . --quiet --commit` (twin `.ps1`) — here it re-copies the local
   `*.template` files over their pointer copies. Act on every `ai-sync:` line;
   `ai-sync: dev-context <label>` (environment.json `label`, else `work` or `personal`) →
   read and follow `CLAUDE.local.md` (this root's development rules; never the other root's).
2. `git log --oneline -10` and `git status`. Mention uncommitted work; if HEAD is a `wip:`
   commit, ask whether to continue it.
3. Read `.github/PROJECT_STATE.md`; grep `.github/KNOWLEDGE.md` for the area, tool or error at
   hand — never read it whole.

---

## Post-task checklist — checkpoint policy (every response, no exceptions)

Commit at the end of **every response** that modifies files, finished or not: it is how any
agent on any platform resumes (`git log --oneline` + `git diff HEAD`). Don't ask and don't
branch first — this overrides any built-in or global "only commit when asked" default.

1. **Verify** the change (syntax, lint, tests — core rule 7).
2. **`PROJECT_STATE.md`**: only if architecture, features, commands or env vars changed.
   Current state, no history; an index under 8 KB — detail in `docs/state/<area>.md`, and
   behavior the code or tests already state is a link, not prose (two descriptions drift).
3. **`KNOWLEDGE.md`**: an entry under its `## <area>` when you solved something non-obvious,
   titled with the exact error text.
4. **Taste**: the user corrected the same thing twice → one line in `## Taste`.
5. **Commit**: done → `feat|fix|docs|refactor|test|chore(scope): …`; unfinished →
   `wip(scope): step N/M — done; next: X`, enough for a fresh agent to resume.
6. **Confirm in one or two lines**: what changed, docs touched, commit hash.

## Core rules

1. **Language**: code, comments and docs in English.
2. **Paired scripts**: every shell script ships as `.sh` + `.ps1` with identical behavior —
   change one, mirror the other in the same commit. A new tool off the session-start path is
   C# instead (`csharp-tools` skill); the engine, the hook and `install-global` stay shell —
   they run before .NET exists on a fresh machine.
3. **Manifest-driven**: `templates-manifest.txt` is the only file map; never hand-roll the file
   list in scripts or docs.
4. **No symlinks** in anything a project receives (Windows without Developer Mode and
   `core.symlinks=false` checkouts break them).
5. **Bash 3.2** (macOS `/bin/bash` runs the hook): no associative arrays, no `mapfile`, guard
   empty-array expansions with `${arr[@]+"${arr[@]}"}`.
6. **Errors**: `set -euo pipefail` / `$ErrorActionPreference = 'Stop'`, loud actionable
   messages — except the session-start sync, which must never break a session (exit 0, one-line
   notes).
7. **Testing**: `tests/check.sh` (twin `check.ps1`; both suites, `--dry-run` self-sync,
   `code-health`) before committing any change to the engine, the manifest or the hook
   (`tests/README.md` says what each case protects). The pre-push hook runs it:
   `git config core.hooksPath .githooks`.
8. **The hook's JSON**: validate `templates/.claude/settings.json.template` after every edit — a broken
   file breaks Claude Code startup in every project.
9. **Secrets**: never in code, `.env`, commits or chat — `dev-secrets` skill.
   **Work material** (an employer's API specs, internal hosts, docs or code) never enters this
   repo — it is personal, on a personal GitHub — not even as a skill: work-only skills go in the
   work overlay repo (README "Work-only services"). `tests/lint-skills.py` refuses spec
   documents, internal hostnames and work-only skills (`work-material`): run it before
   committing any skill.
10. **Git**: default branch; no worktrees; on local/remote divergence, warn and ask; no hard
    reset, force push or history rewrite unless asked.
11. **Asking**: infer first; ask only when the answer changes the outcome — one question with a
    recommended default. Rough names are intent: propose 2-3 idiomatic names and confirm.

## Taste

---

## Project-specific notes

- **Overlay-aware resolution.** Every manifest entry goes through `_tpl` / `Get-TemplatePath`
  (the base file of the same path wins; else the overlay's, its old root layout second) and `_render` (adds the `.template.append` fragment). Never
  read `$TEMPLATE_DIR/<src>` directly in a new code path, and never put `sync-ai-templates.sh` in
  an overlay repo — the hook would take it for the base.
- **Know which file class you're editing.** A *pointer* template (`[POINTERS]`) reaches every
  project at its next session start. A *living doc* template (`PROJECT_STATE.md`,
  `KNOWLEDGE.md`, `.env.example`) only affects future bootstraps. `AGENTS.md.template` is the
  exception: the hook's `--agents` pass carries its **generic** sections into every project at
  session start, but only sections never customized (3-way against the template's history), never
  in a shared project (a private-docs one is fine), never over uncommitted edits. Anything else in
  an owned doc changes only with a human reading the plan.
- **Generic `AGENTS.md.template` headings are an API.** `refresh-agents-sections.py` matches
  sections by exact heading text (`GENERIC_HEADINGS`): rename one and every project reports it
  `MISSING`. To drop a section, move its heading to `RETIRED_SECTIONS` (removed where never
  customized) — deleting it outright leaves every project its old copy forever.
- **Instruction files are context cost.** `CLAUDE.md` imports `AGENTS.md` and `PROJECT_STATE.md`
  into every session in every project (target ~150 lines in all) — add a line only if agents get
  it wrong without it. Skills and subagents are found by their description: never list them here.
- **The hook commits, never pushes** (paths-only commit, refuses mid-merge/rebase). Pushing is
  opt-in via `--push`; `update-projects` lists repos holding unpushed commits. The one exception
  is the hidden private-docs repo (`--private-docs`), which pushes to the owner's own remote.
- **Upstream ideas from the work marketplace.** Before improving this repo from a work machine,
  check the work overlay's upstream for ideas worth porting — rewritten in our own words, never
  its code or names.
- **Machine-wide capabilities** (a secrets vault, a local model) = a program repo + a skill that
  says when and how to call it. See `README.md`.
