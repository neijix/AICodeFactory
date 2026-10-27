# Project files

Every file the factory puts in a project is either a pointer file, which the factory owns and
refreshes, or a living doc, which the project owns after it is created. This page lists each
one, as the [manifest](manifest.md) defines them, plus the few files the engine writes outside
the manifest.

## Pointer files: owned by the factory

Refreshed whenever the template changes. Never edit them in a project: the next session start
replaces your edit. To change one everywhere, edit its template in the factory, or override it
in your [overlay](overlay.md).

| File | Read by | Purpose |
|---|---|---|
| `CLAUDE.md` | Claude Code | Imports `AGENTS.md` and `.github/PROJECT_STATE.md` with `@`, plus Claude-specific notes |
| `.claude/settings.json` | Claude Code | The [session-start hook](hook.md), the other hooks, permissions |
| `.claude/commands/learn.md` | Claude Code | `/learn`: save what the session learned to `KNOWLEDGE.md` |
| `.claude/commands/architect.md` | Claude Code | `/architect`: run the `architect-flow` workflow |
| `.claude/agents/devops.md` | Claude Code | Subagent for local environment work (services, dependencies, `.env`) |
| `.claude/agents/verifier.md` | Claude Code | Subagent that checks a claimed result from zero context |
| `.claude/agents/planner.md` | Claude Code | `architect-flow` subagent: writes the plan |
| `.claude/agents/spec-analyst.md` | Claude Code | `architect-flow` subagent: checks the plan |
| `.claude/agents/implementer.md` | Claude Code | `architect-flow` subagent: implements one subtask |
| `.claude/agents/converger.md` | Claude Code | `architect-flow` subagent: checks the code delivers the plan |
| `.claude/agents/reviewer.md` | Claude Code | Subagent for an independent read-only review |
| `.github/copilot-instructions.md` | GitHub Copilot (older surfaces) | Points to `AGENTS.md` |
| `.github/agents/quick-tasks.agent.md` | GitHub Copilot (VS Code) | Custom agent for small mechanical tasks |
| `.gemini/settings.json` | Gemini CLI | Sets `context.fileName` to `AGENTS.md` |
| `.antigravity/rules.md` | Antigravity | Points to `AGENTS.md`, with the session-start step |

## Living docs: owned by the project

Created once with `[PROJECT_NAME]` filled in, then never overwritten. The `bootstrap-ai` skill,
run by your agent on the first session, fills in the rest. The one exception is the generic
sections of `AGENTS.md`, refreshed only while you never edited them
([how](../explanation/agents-sections-refresh.md)).

| File | Purpose |
|---|---|
| `AGENTS.md` | The rules every agent reads: session start, checkpoint policy, core rules, taste, project notes |
| `.github/PROJECT_STATE.md` | Current architecture, commands, environment variables; an index kept small |
| `.github/KNOWLEDGE.md` | Solved problems and gotchas, each titled with the exact error, searched on demand |
| `.env.example` | The environment variables the project needs, without values |

## Written by the engine, outside the manifest

| File | In git? | Purpose |
|---|---|---|
| `.gitignore` | tracked | Gains `.env`, `.claude/settings.local.json` and `CLAUDE.local.md` when missing; in shared mode, the pointer files too |
| `CLAUDE.local.md` | ignored | Your code root's development rules and factory settings, when the code root has them |
| `.claude/settings.local.json` | ignored | Per-machine Claude Code settings: auto-memory folder, skills turned off |
| `.git/info/exclude` | never | The managed block listing the files kept out of the code repo (private and team mode) |
| `.git/hooks/pre-commit` | never | The private-terms guard (every mode but tracked) |
| `.git/ai-context/` | never | The hidden repo of private AI docs (private and team mode) |

## Which files git tracks, per mode

`aicf init` creates a project in **private** mode; `aicf init --tracked` in **tracked** mode.
See [team and private docs](../how-to/team-and-private-docs.md) to switch.

| Mode | Pointer files | Living docs (`.env.example` aside) | `.env.example` |
|---|---|---|---|
| tracked | committed | committed | committed |
| private | on disk, kept out of git | kept in the hidden repo | committed |
| team | untouched if the team tracks them, else kept out of git | as for pointers, hidden repo for the rest | as the team has it |
| shared | on disk, gitignored and untracked | committed | committed |

## Removed when found

The sync deletes these leftovers of older versions: `GEMINI.md`, `.cursor/rules/project.mdc`,
`init-ai.*`, `init-project.ps1`, `update-all*`, and a `.mcp.json` still identical to the old
template (a customized one is kept). Symbolic links left by the old symlink layout are replaced
by copies.
