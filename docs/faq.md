# FAQ

Short answers, each with a link to the page that has the detail.

## Do I need Claude Code?

No. Codex, Copilot, Cursor, Gemini CLI and Antigravity all read the same `AGENTS.md`. The
difference is who runs the session-start sync: Claude Code runs it from a hook, the other agents
run it because step 1 of `AGENTS.md` tells them to. See [supported tools](reference/supported-tools.md).

## Does it push anything?

It commits only the files it wrote, and never pushes your code repos unless you ask:
`aicf update --push` or `aicf sync --push`. The one thing pushed without a flag is the hidden
repo of a private project, and only to the remote you configured for it
([team and private docs](how-to/team-and-private-docs.md)).

## Where do my personal rules go?

| Scope | Where |
|---|---|
| Every project on every machine | Your [private overlay](how-to/private-overlay.md) |
| Every project in one code root (work vs personal) | `<code root>/.ai-root/dev-context/rules.md`, delivered as `CLAUDE.local.md` ([several code roots](how-to/several-code-roots.md)) |
| One project | That project's `AGENTS.md`, under `## Taste` or `## Project-specific notes` |
| One project on one machine (Claude Code permissions) | `.claude/settings.local.json`, gitignored |

Never edit a pointer file such as `CLAUDE.md` in a project: the next session start overwrites it
([pointer files vs living docs](explanation/pointers-vs-living-docs.md)).

## Why plain copies instead of symbolic links? Why no MCP servers?

Links break on Windows, in `core.symlinks=false` checkouts and in other people's clones. MCP
servers put their tool schemas into every session and need per-tool setup. See
[design decisions](explanation/design-decisions.md).

## What does it cost per session?

- **Time.** The sync is a local file comparison; with nothing to do it prints nothing. Network
  steps (pulling the factory and overlay) wait at most 10 seconds each and 30 seconds per run
  in total, then go on in the background ([environment variables](reference/environment.md#limits)).
- **Context.** `CLAUDE.md` imports `AGENTS.md` and `.github/PROJECT_STATE.md`, so both are read
  at every Claude Code session; the sync warns when an imported file passes 8 KB. Each skill
  costs one description line until a task matches it.

## Does it trust programs because they run on my machine?

No. AICodeFactory runs no server and opens no port, and nothing it ships treats `localhost` or
a local process as trusted. Mind what does run: the project hook executes the sync script of
the factory checkout it finds ([lookup order](reference/hook.md#how-the-hook-finds-the-factory)).
Treat your code root like your shell profile: whoever can write there can run code at your
next session start.

## Why does Claude Code run shell commands without asking?

The project's `.claude/settings.json` allows `Bash(*)` and denies the destructive git and `rm`
commands (force push, `reset --hard`, history rewrites, `rm -rf` of the home folder). Gemini CLI
gets `auto_edit`. To be asked more often, override `templates/.claude/settings.json.template` or
`templates/gemini-settings.json.template` in your overlay
([hook reference](reference/hook.md#the-other-hooks-in-claudesettingsjson)).

## Can teammates who do not use AICodeFactory work in the repo?

Yes. In tracked mode they get plain files that their agent reads; the Claude Code hook prints
one `ai-sync: AICodeFactory not found` line and the session starts normally. In shared mode the
pointer files are not in the repo at all, only the project's living docs. In private mode the
repo holds no AI files ([the modes](how-to/team-and-private-docs.md)).

## What is `CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000` in the project settings?

It makes Claude Code summarize the conversation as if its context window held 200,000 tokens,
also with a model that has a larger window. Long sessions stay cheaper and the summary keeps
them focused; the `compact` hook then prints the latest commits and `git status` so the agent
starts again from the repo. Set another value in the `env` block of
`.claude/settings.local.json` for one machine, or in your overlay for every project.

## How do I remove it?

`aicf uninstall` previews what it would undo on this machine; `--yes` applies it. Projects keep
their files until you remove them ([uninstall](how-to/uninstall.md)).
