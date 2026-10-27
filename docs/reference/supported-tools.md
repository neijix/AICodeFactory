# Supported tools

Every tool reads the same root `AGENTS.md`, either natively or through a small pointer file the
factory keeps in sync. This page lists, per tool, what it reads, what refreshes the files, and
where its global skills go.

`AGENTS.md` is the open standard most coding agents read on their own; the other files exist
only for tools that look elsewhere first, and hold no rules of their own.

| Tool | Reads in the project | Refreshed by | Global skills folder | Global file from `aicf setup` |
|---|---|---|---|---|
| Claude Code | `CLAUDE.md` (imports `@AGENTS.md`), `.claude/settings.json`, `.claude/commands/`, `.claude/agents/` | The `SessionStart` [hook](hook.md), automatically | `~/.claude/skills` | `~/.claude/settings.json`: `AI_TEMPLATE_DIR`, `AI_CODE_ROOT` and the [global hook](hook.md#the-global-hook) |
| OpenAI Codex | `AGENTS.md`, natively | The agent, following `AGENTS.md` "Session start" step 1 | `~/.agents/skills` | none |
| GitHub Copilot (VS Code, CLI, coding agent, code review) | `AGENTS.md` natively; `.github/copilot-instructions.md` for older surfaces; `.github/agents/quick-tasks.agent.md` | The agent, following `AGENTS.md` | `~/.copilot/skills`, `~/.agents/skills` | `~/.copilot/copilot-instructions.md` (Copilot CLI); `ai-autobootstrap.instructions.md` in the VS Code user prompts folder |
| Cursor (1.6 and later) | `AGENTS.md`, natively | The agent, following `AGENTS.md` | `~/.cursor/skills` | none |
| Gemini CLI | `AGENTS.md`, through `context.fileName` in `.gemini/settings.json` | The agent, following `AGENTS.md` | none | `~/.gemini/commands/bootstrap-ai.toml` (the `/bootstrap-ai` command) |
| Antigravity | `.antigravity/rules.md`, which points to `AGENTS.md` | The agent, following its rules file | `~/.gemini/config/skills` | none |

Other agents that read `AGENTS.md` natively (Windsurf, Amp, Devin, …) work the same way as
Codex: nothing extra is needed.

## What "refreshed by the agent" means

Only Claude Code runs a hook at session start. The other tools read `AGENTS.md`, whose first
step tells the agent to run the sync itself:

```bash
bash ../AICodeFactory/sync-ai-templates.sh . --quiet --commit --pull --agents
```

with `$AI_CODE_ROOT/AICodeFactory` or the path in `~/.ai-template-dir` when the factory is not a
sibling, and `sync-ai-templates.ps1` in PowerShell. If you use one of those tools alone, run
`aicf update --yes` now and then, or let a Claude Code session do it.

## Global skills

`aicf setup` installs every folder of `skills/` (and of your overlay's `skills/`) into each
skills folder above, and creates those folders. Later session starts keep them fresh, but only in
folders that exist. On macOS and Linux they are symbolic links to the checkout, so a skill edit
is live at once; on Windows they are copies, refreshed at the next session start
(`AI_SKILLS_MODE` overrides either default).

## Settings the pointer files apply

- `.claude/settings.json` grants Claude Code `Bash(*)` with a deny list; see
  [the hook page](hook.md#the-other-hooks-in-claudesettingsjson).
- `.gemini/settings.json` sets `general.defaultApprovalMode` to `auto_edit`: Gemini CLI applies
  file edits without asking.

Override either in your [overlay](overlay.md) if you want a stricter default.
