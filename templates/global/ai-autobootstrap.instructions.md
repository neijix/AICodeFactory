---
name: "AI Auto-Bootstrap (global)"
description: "Always-on global rules that make every project self-bootstrap with my AI instruction template. Use when opening any workspace, starting a session, or when a project is missing a root AGENTS.md."
applyTo: "**"
---

# Global AI Behavior — Auto-Bootstrap Every Project

These rules apply to **every** project I open in VS Code. They are intentionally short.
The full, detailed ruleset lives **inside each project** (root `AGENTS.md`), generated on first
use by the bootstrap below.

## Standing rules

- **No MCP server, ever** — neither one of mine nor a third-party one. No `mcp.json` entry, no
  `claude mcp add`, no stdio or HTTP MCP server, no `--mcp-config`. A new tool is a shell command
  (or REST call) behind a skill. An MCP server still registered somewhere is a leftover: say so and
  offer to remove it. This holds after a project has its own `AGENTS.md`.

## 1. Session start (do this first, silently, ~10s)
- **Refresh the shared AI files** from my template — they are plain copies, kept fresh by this
  step: run `bash ../AICodeFactory/sync-ai-templates.sh . --quiet --commit`
  (not a sibling? try `$AI_CODE_ROOT/AICodeFactory` or the path in `~/.ai-template-dir` — never
  assume `~/Code`, which does not exist on every machine; PowerShell twin:
  `..\AICodeFactory\sync-ai-templates.ps1 . --quiet --commit`). It copies changed
  pointer files (`CLAUDE.md`, `.claude/*`, `.gemini/settings.json`, `.antigravity/rules.md`,
  `.github/copilot-instructions.md`, `.github/agents/*`) and commits just those. Skip silently
  if the template repo is not on this machine (e.g. a server-side clone). Never hand-edit
  those copies. If it prints `ai-sync: dev-context <name>`, read `CLAUDE.local.md` and follow
  it: this code root's development rules (from the root's `.ai-root/dev-context/`,
  gitignored). Never apply another root's.
- If a `.git` repo exists: skim `git log --oneline -10` and `git status` to see where things stand.
- If a root `AGENTS.md` **exists as a real filled file** → it is the source of truth. Follow it
  and ignore the bootstrap step below.
- If uncommitted changes or a `wip:` HEAD commit exist → mention them before doing new work.

## 2. Auto-bootstrap trigger
If the workspace has **no** root `AGENTS.md` (or it is still a leftover symlink / unfilled
copy of the template), or any of `AGENTS.md` / `.github/PROJECT_STATE.md` / `.github/KNOWLEDGE.md`
still contains `<!-- BOOTSTRAP_PENDING -->` (or leftover tokens like `[PROJECT_NAME]` /
`[PRIMARY_LANGUAGE]` / `[FRAMEWORK]`), then **before the user's first task**, run the bootstrap:

> Invoke the `bootstrap-ai` skill (type `/bootstrap-ai` in chat, or run it — same behavior).

Do **not** hand-roll the file list or placeholder fill — the skill owns that (including
migrating legacy projects whose master was `.github/copilot-instructions.md`). After it
finishes, defer to the project's own instructions.

Skip the bootstrap for throwaway/scratch folders or when the user explicitly declines.

## 3. Always-on baseline (until a project defines its own)
- **Checkpoint commits**: after any response that changes files, commit without asking. Conventional Commits for
  finished work (`feat:`, `fix:`, `docs:`…), `wip:` + a resume hint for in-progress work.
- **No worktrees**: never run `git worktree add`. Work in the main checkout only.
- **Diverged remote**: warn the user and ask for preference; never auto-reset to the server
  version unless the user explicitly opts in or asks to discard local changes.
- **Single source of truth**: the root `AGENTS.md` holds the rules; other AI tool files are thin
  wrappers or are read natively.
- **Credentials**: never hardcode secrets; fetch them from the team's secret manager at
  runtime. Private keys live only in `~/.ssh` (mode 600) — never in a project, `.env` or chat.
  For every credential need (SSH keys, tokens, vault setup), invoke the secrets skill for this
  code root, if one is installed. Help the user set things up yourself.
- **Naming & terminology**: when I give a quick/rough name for a feature, label, status, column,
  or variable in chat, treat it as intent, not a literal spec — propose 2-3 polished, idiomatic,
  domain-appropriate alternatives (matching existing conventions in the codebase) and confirm
  before implementing, instead of using my wording verbatim.

- **Offload easy work to a local model (when one is installed and it makes sense)**: if a
  local-model offload skill is installed, follow it for mechanical, self-contained subtasks
  (renames, reformatting, boilerplate, extraction, docstrings, simple transforms) and verify
  the output with a deterministic check. Keep high-reasoning work (architecture, debugging,
  multi-file edits, judgement calls, security) yourself.

