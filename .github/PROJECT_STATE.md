# PROJECT STATE — AICodeFactory

> Architecture snapshot for AI agents — not a changelog (`git log`).
> Loaded into every session: under 8 KB; detail in `docs/state/`.

---

## What This Is

The single source of truth for AI-agent instructions across every project under `Code/`
(personal) and a work root (`work/`, `WorkCode`, or any folder declared as work). It ships a
master instruction file (`AGENTS.md`) plus per-tool pointer files (Copilot, Claude Code, Cursor,
Codex, Gemini CLI, Antigravity),
shared Agent Skills (agentskills.io format), and the scripts that bootstrap new projects and
keep existing ones in sync. Used only by the repo owner (macOS, Windows, Linux).

## Architecture

Everything is driven by `templates-manifest.txt`. The invariants (layer by layer, with the
engine's exact steps: `docs/state/architecture.md`):

- **No symlinks** in anything a project receives: plain copies, refreshed by a sync each project
  runs at session start (Claude Code `SessionStart` hook; `AGENTS.md` step 1 for other agents).
- **Pointer files** (`[POINTERS]`) are identical everywhere and overwritten; **living docs**
  (`[LIVING_DOCS]`) are created once, then owned by the project.
- **Global skills** (`skills/*`, every folder) install into every tool's skills
  dir — links on macOS/Linux, copies on Windows. Own tools are shell commands behind a skill,
  never MCP.
- **No machine path is committed**: `~/.ai-template-dir`, `AI_TEMPLATE_DIR` and `AI_CODE_ROOT`
  live outside every repo, because the code root differs per machine.
- **Optional private overlay** repo: same layout (`templates/`, `skills/`; the old root layout
  is read second, with a note), only adds — this repo wins by file name and skill name —, never
  holds the engine. Its `factory.json` names extra overlays and `skills.scope`.
  Factory config: `docs/state/environments.md`.
- **No work material here** (personal GitHub): an employer's API specs, internal hosts or docs
  go in a work overlay; `tests/lint-skills.py` (`work-material`) enforces it.
- **The engine commits only the paths it wrote**, never pushes, refuses mid-merge/rebase.
  `--pull`, `--agents` and the hidden-repo push: `docs/state/architecture.md`.
- **Global hook** and **Claude auto memory** (private and team projects): see
  `docs/state/architecture.md`.

```
AICodeFactory/
├── templates-manifest.txt          # authoritative file map      } hook contract: these three
├── sync-ai-templates.sh|.ps1       # shared engine               } stay at the root
├── install.sh|.ps1                 # one-line install: clone/fast-forward (--channel) + aicf setup
├── bin/aicf|aicf.ps1               # CLI: init|sync|update|doctor|setup|uninstall|projects|config → engine/
├── engine/                         # new-project, update-projects, install-global, doctor, uninstall,
│                                   #   engine parts, factory-env.py (config, stamp, merge; Python),
│                                   #   projects-page.py (aicf projects: status + skills page; Python),
│                                   #   config-ui.py (aicf config: settings page on 127.0.0.1; Python)
├── templates/                      # every *.template at its project path; .claude/settings.json.template
│                                   #   = permissions + SessionStart sync + commit/attribution guards + size hint
│                                   #   + private-docs Stop sync; git-hooks/ = [SHARED_HOOKS]; global/ = machine files
├── skills/                         # shared skills — every folder is installed
├── docs/ examples/overlay/         # user docs (Diátaxis); docs/state, docs/plans = maintainer only
├── tests/                          # run-tests.sh|.ps1 (engine suite, cases/), lint-skills.py, check-docs.py;
│                                   #   check.sh|.ps1 = local gate = Linux CI, run by .githooks/pre-push
└── .github/                        # living docs; workflows: tests.yml (suites, lint, fresh-machine), release.yml
```

## Detail (read on demand)

| File | Holds | Read when |
|---|---|---|
| `docs/state/architecture.md` | Layers, sync engine steps, private layer, global hook, auto memory | Changing the engine, the hook, overlays or install-global |
| `docs/state/features.md` | Every active feature, with its location | Changing or looking for a capability |
| `docs/state/limitations.md` | Known limitations & tech debt | Before touching overlays, Windows, skills cleanup, the hook's commit |
| `docs/state/machine-local.md` | Hook discovery, per-machine files, factory config (`environments.md`) | install-global, dev-context, skills per code root |

## Key Commands

```bash
./sync-ai-templates.sh .                       # re-sync this repo's pointer copies after a *.template edit
./sync-ai-templates.sh ../<name> --dry-run     # engine against one target (preview)
./sync-ai-templates.sh ../<name> --quiet --commit --pull --agents --skills   # hook mode
./sync-ai-templates.sh ../<name> --shared --commit        # team repo: pointer files local-only
./sync-ai-templates.sh ../<name> --private-docs --commit  # …and the AI docs move to .git/ai-context
./sync-ai-templates.sh ../<name> --scan-private [--history]   # tracked files vs private-terms list
uv run skills/bootstrap-ai/scripts/refresh-agents-sections.py --all --dry-run|--commit
bin/aicf init <name> [--tracked]
bin/aicf update [--yes] [--clone] [--pull] [--push] [--check|--migrate [--yes]] [<name>]   # preview by default; --check/--migrate never push a code repo
tests/check.sh                                 # ~6 min gate = Linux CI; pre-push: git config core.hooksPath .githooks
uv run tests/skill-evals.py [--model haiku] [--runs 3]   # opt-in, costs tokens: do skills trigger?
uv run tests/lint-skills.py --verbose          # shipped-content lint (also case 18)
bin/aicf doctor [--yes [--clone] [--push] [--copy] | --json]   # check (no writes); --yes fixes all
bin/aicf uninstall [--yes]                     # preview, then the exact reverse of setup
bin/aicf projects [--open] [--json]            # HTML page: bootstrap status + skills used, per project
bin/aicf config [--no-open]                    # local settings page: code roots, personal/extra skill folders, scan
python3 tests/gen-cli-reference.py             # regenerate docs/reference/cli.md after a --help change
bin/aicf setup [--overlay <dir>] [--work-root <name-or-path>] [--ai-context-remote [<root>=]<url>] [--claude-profile|--claude-env …] …
```

## Environment Variables

None at runtime. The optional overrides the engine reads (`AI_TEMPLATE_DIR`, `AI_CODE_ROOT`,
`AI_TEMPLATE_OVERLAY_DIR`, `AI_WORK_ROOTS`, `AI_CONTEXT_REMOTE`, `AI_SYNC_*`, …) are listed once,
in `docs/reference/environment.md`; `tests/check-docs.py` fails when one is missing there.

## AI Context

What surprises an agent reading the code for the first time:

- `*.template` files are **products**, but this repo's own config files are **copies of** them
  (dogfooding). Edit `templates/CLAUDE.md.template`, never `CLAUDE.md`.
- Claude Code shell-form hooks run via `sh -c` on macOS/Linux and **Git Bash on Windows**, so
  one POSIX one-liner in `.claude/settings.json.template` serves every platform; SessionStart
  stdout is injected into the model's context, hence `--quiet` (silent on no-op).
- `update-projects` skips this repo and siblings without an owned `AGENTS.md`.
- On macOS a skill edit is live at once (symlinks); on Windows it lands at the next session.
- **The code root is never hardcoded.** On Windows the roots may be `F:\Code` and `F:\WorkCode`
  while `$HOME` is `C:\Users\<user>`: use `$AI_CODE_ROOT`, or derive from the script's location
  (`dirname $SCRIPT_DIR`).
