# Design decisions

AICodeFactory makes a few choices that look odd at first: copies instead of links, shell
commands instead of MCP servers, Bash 3.2, commits it never pushes. Each one answers a failure
seen in practice, and this page says which.

## Plain copies, never symbolic links

A project receives real files, refreshed by the sync. Symbolic links need Developer Mode or admin
rights on Windows, become text files in a `core.symlinks=false` checkout, point at nothing in a
CI runner or a teammate's clone, and record a machine path in git. A copy works everywhere and
records what the agent actually read. The one place links remain is the global skill folders on
macOS and Linux, which never enter a repo (Windows gets copies there too).
[How the sync works](how-sync-works.md#why-copies-not-symbolic-links).

## Skills and shell commands, not MCP servers

Every shared capability is a skill: a `SKILL.md` that says when to act and which command or API
to call. No MCP server is registered anywhere, not even a third-party one.

- **Context cost.** An MCP server puts its tool schemas into every session, used or not. A skill
  costs one description line until the task matches.
- **One wiring for every tool.** A skill folder works in each agent that reads skills; an MCP
  server needs its own configuration, and often its own authentication, per tool.
- **Managed machines.** Endpoint-security software on company laptops flags MCP servers. A
  command the agent runs through its shell is the same as any command you type.

A capability that needs a running process is a program with a command-line client, plus a skill
that says how to call it. `aicf setup` removes the MCP entries older versions installed.

## The `gh` CLI, not the GitHub MCP server

The GitHub MCP server added little over `gh`, which agents already run through the shell, and
cost a permanent tool-schema footprint plus per-tool token setup. `gh auth login` once is enough
for every agent.

## Each project pulls at session start

Nothing pushes files into your projects from outside. A project refreshes itself when an agent
starts in it, so a project you never open costs nothing and a project you open always starts
from the latest rules. `aicf update` exists for when you want every commit now.

## Commit, never push

The engine commits the paths it wrote, and only those, so `git status` stays clean and your own
work never lands in a sync commit. It never pushes your code repo: what leaves the machine stays
your decision. `aicf update --push` is the explicit opt-in.

## Shell on the session-start path

The hook, the engine and `aicf setup` are Bash and PowerShell, because they run on a fresh machine
before any other runtime is installed. Each script has a twin with the same behavior. Tools that
run later may use other languages.

## Bash 3.2

macOS still ships Bash 3.2 as `/bin/bash`, and that is what the hook runs. The engine avoids
associative arrays, `mapfile` and other Bash 4 features, so it runs unmodified on every macOS
install.

## The manifest is the only file map

`templates-manifest.txt` lists every file a project receives. The engine, `aicf doctor`, the
tests and the [project files reference](../reference/project-files.md) all follow it, so a new
file is one line, and no script holds a second list that can drift.

## A session never breaks

The session-start sync always exits 0. Offline, a diverged factory, a merge in progress, a
missing tool: each becomes one `ai-sync:` line and the session starts with the files already on
disk. Network steps are time-boxed for the same reason.

## An overlay, not a fork

Your personal rules, skills and replacement templates live in a second repo that the engine
layers on top of the factory. You keep pulling upstream without merge conflicts, and the
private part stays private. [Overlay reference](../reference/overlay.md).

## No machine path in any repo

The code root differs per machine (`~/Code`, `D:\Code`, …). The factory's location lives in
`~/.ai-template-dir` and `AI_TEMPLATE_DIR`, outside every repo, and the hook finds the factory
by looking next to the project first.
