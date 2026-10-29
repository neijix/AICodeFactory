# AICodeFactory

One rule set for Claude Code, Codex, Copilot, Cursor, Gemini CLI and Antigravity, kept in sync
across every repo you own without symbolic links.

You write how you want agents to work once. Every project on every machine gets it at its next
session start, as plain files that every tool reads, and each project keeps its own notes.

## How it works

```text
  AICodeFactory checkout               your overlay (optional, private)
  templates/, skills/                  your own templates, appends, skills
            │                                     │
            └──────────────────┬──────────────────┘
                               │  session-start hook, in each project
                               ▼
   ~/Code/app-a            ~/Code/app-b            ~/Code/app-c
   AGENTS.md          ◄─── the project's own rules, written once, then yours
   CLAUDE.md, .claude/, .github/copilot-instructions.md, .gemini/, .antigravity/
                      ◄─── small pointer files to AGENTS.md, refreshed copies
```

Three ideas:

1. **One rule file per project.** `AGENTS.md` holds the project's rules; every tool is pointed
   at it, natively or through a small pointer file. Edit it like any other project file.
2. **Each project pulls, at session start.** A hook in the project runs the factory's sync
   engine whenever an agent starts there. It copies plain files, so it works on Windows without
   Developer Mode, in CI and in a teammate's clone. Nothing reaches into a project from outside.
3. **Your taste lives in an overlay.** Personal rules, skills and replacement templates go in a
   second folder that is layered on top of the factory, so you keep pulling upstream without
   a fork.

What the hook does, in order (each step is time-boxed and never fails the session):

1. **Pull**: fast-forward the factory and your overlay, when their working trees are clean.
2. **Hidden repo**: in a private project, commit and sync the AI docs kept out of the code repo.
3. **Sync**: copy the pointer files that changed, create missing docs, remove obsolete files,
   and commit only those paths. It never pushes.
4. **Refresh `AGENTS.md`**: update its generic sections you never edited.
5. **Skills**: install the shared skills into every tool's skill folder.

It prints one `ai-sync:` line when something changed, and nothing otherwise. The full contract
(what it reads, writes, commits and sends over the network) is in the
[hook reference](docs/reference/hook.md).

## Quickstart

Needs `git` and `bash` (on Windows, Git for Windows and PowerShell 7). `uv` or Python 3 is
optional.

```bash
curl -fsSL https://raw.githubusercontent.com/neijix/AICodeFactory/HEAD/install.sh | bash
~/Code/AICodeFactory/bin/aicf init my-app       # or: aicf update <folder> for an existing repo
cd ~/Code/my-app && claude                      # or open it in Codex, Copilot, Cursor, Gemini CLI
```

1. The installer clones the factory into `~/Code/AICodeFactory` (`--code-root` for another
   folder) and runs `aicf setup`: global skills, the global instructions, a few marker files in
   your home folder. It changes none of your projects.
2. `aicf init` creates a sibling project with its AI files and a first commit. An existing repo
   next to the factory is bootstrapped with `aicf update <name>`.
3. On its first session the agent fills in `AGENTS.md` and the project docs from your code.

Windows: `irm https://raw.githubusercontent.com/neijix/AICodeFactory/HEAD/install.ps1 | iex`,
then `bin\aicf.ps1` ([Windows](docs/how-to/windows.md)). Prefer to read before you run? Clone
the repo and run `bin/aicf setup`: the [tutorial](docs/getting-started.md) does it step by step.

## Supported tools

| Tool | Reads | Refreshed by |
|---|---|---|
| Claude Code | `CLAUDE.md` (imports `AGENTS.md`), `.claude/` | Its `SessionStart` hook, automatically |
| OpenAI Codex | `AGENTS.md` | The agent, following `AGENTS.md` step 1 |
| GitHub Copilot | `AGENTS.md`, `.github/copilot-instructions.md` | The agent, following `AGENTS.md` step 1 |
| Cursor 1.6+ | `AGENTS.md` | The agent, following `AGENTS.md` step 1 |
| Gemini CLI | `AGENTS.md`, through `.gemini/settings.json` | The agent, following `AGENTS.md` step 1 |
| Antigravity | `.antigravity/rules.md`, pointing to `AGENTS.md` | The agent, following its rules file |

Other agents that read `AGENTS.md` natively work too. Global skill folders and per-tool files:
[supported tools](docs/reference/supported-tools.md).

## What a project gets

- **Pointer files** (`CLAUDE.md`, `.claude/settings.json`, `.github/copilot-instructions.md`,
  `.gemini/settings.json`, `.antigravity/rules.md`, a few agents and commands): the same in
  every project and overwritten by each sync. Never edit them in a project.
- **Living docs** (`AGENTS.md`, `.github/PROJECT_STATE.md`, `.github/KNOWLEDGE.md`,
  `.env.example`): created once, then owned by the project.

`templates-manifest.txt` is the complete list ([project files](docs/reference/project-files.md),
[why two kinds](docs/explanation/pointers-vs-living-docs.md)).

A project chooses who sees its AI files:

| Mode | The code repo tracks | Use it for |
|---|---|---|
| private (`aicf init` default) | no AI file; the docs live in a hidden repo inside `.git` | your repos, public or not |
| tracked (`--tracked`) | everything | a repo where the AI docs are part of the project |
| shared (`--shared`) | the living docs only | a team repo where not everyone uses AICodeFactory |

[Team projects and private docs](docs/how-to/team-and-private-docs.md) covers switching and the
private-terms guard.

## Your own rules: the overlay

Create a folder named `AICodeFactory-private` next to the factory (or point `aicf setup
--overlay <dir>` at one). A file there wins over the factory's file of the same path:

```text
AICodeFactory-private/
├── templates/CLAUDE.md.template.append     added to every project's CLAUDE.md
├── templates/AGENTS.md.template.append     added to every new project's AGENTS.md
└── skills/my-skill/SKILL.md                installed for every tool
```

Keep it in a private git repo and every machine pulls it at session start. Start from
[`examples/overlay/`](examples/overlay/README.md); details in
[private overlay](docs/how-to/private-overlay.md) and the
[overlay reference](docs/reference/overlay.md).

## Everyday commands

```bash
aicf init <name> [--tracked]     # new project next to the factory
aicf update                      # preview a refresh of every project; --yes applies
aicf update <name>               # refresh (or first bootstrap) one project now
aicf sync [<dir>] --dry-run      # the engine for one project, without writing
aicf doctor                      # check the machine and every project; --yes fixes
aicf projects --open             # page: which projects are bootstrapped, which skills each uses
aicf config                      # settings page: code roots, skill folders (Windows: double-click config.bat)
aicf setup                       # re-run after an upgrade that changes the global files
aicf uninstall                   # preview what would be undone; --yes applies
```

`aicf` is `~/Code/AICodeFactory/bin/aicf` (`bin\aicf.ps1` on Windows); add `bin/` to your `PATH`
if you like. Every option: [CLI reference](docs/reference/cli.md).

## Uninstall

`aicf uninstall` lists what `aicf setup` installed (skill folders, global hook and settings, the
global instruction files, the marker files) and removes it with `--yes`. It never touches your
projects, their hidden repos or the checkout. Removing the AI files from a project is a separate,
manual step: [uninstall](docs/how-to/uninstall.md).

## Documentation

- [Getting started](docs/getting-started.md): a ten-minute tutorial.
- How-to: [add a skill](docs/how-to/add-a-skill.md),
  [private overlay](docs/how-to/private-overlay.md),
  [several code roots](docs/how-to/several-code-roots.md),
  [team and private docs](docs/how-to/team-and-private-docs.md),
  [refresh every project](docs/how-to/update-projects.md),
  [new machine](docs/how-to/new-machine.md), [Windows](docs/how-to/windows.md),
  [upgrade](docs/how-to/upgrade.md), [uninstall](docs/how-to/uninstall.md).
- Reference: [CLI](docs/reference/cli.md), [manifest](docs/reference/manifest.md),
  [overlay](docs/reference/overlay.md), [environment](docs/reference/environment.md),
  [project files](docs/reference/project-files.md), [hook](docs/reference/hook.md),
  [supported tools](docs/reference/supported-tools.md).
- Explanation: [how the sync works](docs/explanation/how-sync-works.md),
  [pointers vs living docs](docs/explanation/pointers-vs-living-docs.md),
  [the `AGENTS.md` refresh](docs/explanation/agents-sections-refresh.md),
  [design decisions](docs/explanation/design-decisions.md).
- [Troubleshooting](docs/troubleshooting.md) and [FAQ](docs/faq.md).

## Project

[Contributing](CONTRIBUTING.md) · [Security policy](SECURITY.md) · [Changelog](CHANGELOG.md)

Released under the [MIT License](LICENSE).
