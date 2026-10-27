# Environment variables

No variable is required: with none set, AICodeFactory finds its checkout, its overlay and your
code root by itself. Set one only to override that discovery or a limit for one machine, a
shell, or a test run.

Values that are lists use the platform path separator: `:` on macOS and Linux, `;` on Windows.

## Discovery

| Variable | Default | Effect |
|---|---|---|
| `AI_TEMPLATE_DIR` | unset | Path of the AICodeFactory checkout. The project hook tries it **first**, before the [other candidates](hook.md#how-the-hook-finds-the-factory). `aicf setup` writes it into the `env` block of `~/.claude/settings.json`. |
| `AI_CODE_ROOT` | unset | This machine's code root, the folder that holds the factory and your projects. `aicf setup` writes it into `~/.claude/settings.json`; skills use it to reach a program in a sibling repo instead of hardcoding `~/Code`. The engine does not need it. |
| `AI_TEMPLATE_OVERLAY_DIR` | unset | Path of your [private overlay](overlay.md). Tried first; when it is set, `~/.ai-template-overlay-dir` and the `<factory>-private` sibling are not looked at. `none` or an empty value turns the overlay off. |
| `AI_WORK_ROOTS` | unset | Work roots, a path-separator list of folder names or absolute paths. When set it **replaces** `~/.ai-work-roots`. `none` or an empty value means "no work roots" (the file is not read). See [Several code roots](../how-to/several-code-roots.md). |
| `AI_CONTEXT_REMOTE` | unset | Git remote of the hidden repo that carries private AI docs between machines. Tried before `<code root>/.ai-context-remote` and `~/.ai-context-remote`. `none` or empty means local only. Under a work root it can only turn the remote off. |
| `AI_PRIVATE_TERMS_FILE` | unset | Your private-terms list (one term per line), used by the pre-commit guard and `aicf sync --scan-private`. Tried first, before `<code root>/.ai-root/private-terms.txt` and `~/.private-terms`. `none` or empty turns the check off. |

## Limits

| Variable | Default | Effect |
|---|---|---|
| `AI_SYNC_PULL_WAIT` | `10` | Seconds one network step may wait (a `git pull` of the factory or overlay, a fetch or push of the hidden repo). Past it, the step goes on in the background and the run uses what is on disk. |
| `AI_SYNC_NET_BUDGET` | `30` | Seconds of network waiting one run may spend in total. After the first step that timed out, the remaining network steps of the run are skipped. |
| `AI_CONTEXT_BUDGET_KB` | `8` | Size above which a file that `CLAUDE.md` imports with `@` makes the sync print the `context budget` line: that file is loaded into every Claude Code session. |

## Behavior

| Variable | Default | Effect |
|---|---|---|
| `AI_SKILLS_MODE` | `link` on macOS and Linux, `copy` on Windows | How skills reach the tools' global skill folders: `link` (a symbolic link to the checkout, edits are live) or `copy`. `aicf setup --copy` does the same for one run. |
| `AI_SHELL_PROFILES` | `~/.zshrc` and `~/.bashrc` that exist, else the one of your `$SHELL` | Shell profile files (path-separator list) that receive the managed `claude` profile function. The test suites point it at scratch files. |

## Installer

Read only by `install.sh` and `install.ps1`; each has a command-line option that wins over it.

| Variable | Default | Effect |
|---|---|---|
| `AICF_REPO` | the GitHub repo | Where the installer clones from (`--repo`). |
| `AICF_CHANNEL` | `stable` | `stable` follows the latest release tag, `main` the development branch (`--channel`). A repo without a release gets `main`. |

The installer also reads `AI_CODE_ROOT` (`--code-root`): the factory goes to
`$AI_CODE_ROOT/AICodeFactory`, else `~/Code/AICodeFactory`.

## Read by skills, not by the engine

| Variable | Effect |
|---|---|
| `AI_SUBTASK_TARGET` | Who implements the subtasks of the `architect-flow` skill: `subagent[:<model>]`, `helpers` or `self`. Set it by hand. |

## Internal, do not set

The engine exports these to its own child processes. Setting them yourself changes nothing
useful and may confuse a run.

| Variable | Purpose |
|---|---|
| `AI_SYNC_NET_LEFT` | Seconds of network budget left, handed to the re-run after a pull moved the factory. |
| `AI_SYNC_NET_DOWN` | Set once a network step has timed out, so the re-run skips the rest. |
| `AI_SKILL_ROOTS` | The skill folders of this run, handed from the shell engine to its Python helper. |

`tests/check-docs.py` fails when the engine mentions an `AI_*` variable this page does not list.
