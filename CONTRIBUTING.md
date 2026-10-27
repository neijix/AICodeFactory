# Contributing to AICodeFactory

Thanks for helping. This page is the bridge between the user docs (`docs/`) and the maintainer
docs (`AGENTS.md`, `.github/PROJECT_STATE.md`, `docs/state/`): read it before your first change.

## Set up

```bash
git clone https://github.com/neijix/AICodeFactory.git
cd AICodeFactory
git config core.hooksPath .githooks     # pre-push runs the full gate
```

You need `git`, `bash` (3.2 or newer), PowerShell 7 (`pwsh`), Python 3 and
[`uv`](https://docs.astral.sh/uv/). On Windows, Git for Windows provides `bash`.

Your checkout can be your installed factory too: `bin/aicf setup` points this machine at it.

## Where things are

| Path | What it holds |
|---|---|
| `sync-ai-templates.sh` / `.ps1`, `templates-manifest.txt` | The hook contract: every project's session-start hook looks for these three at the root. Never move them. |
| `bin/aicf`, `bin/aicf.ps1` | The CLI; each command runs a script in `engine/` |
| `engine/` | Engine parts, `new-project`, `update-projects`, `install-global`, `doctor`, `uninstall`, Python helpers |
| `templates/` | Every `*.template` at the path it takes in a project |
| `skills/` | Shared skills (agentskills.io format), installed into every tool's skills folder |
| `tests/` | Engine suites (`run-tests.sh` / `.ps1`, one case per file in `tests/cases/`), lints, `check.sh` |
| `docs/` | User docs; `docs/state/` and `docs/plans/` are maintainer docs |

The repo dogfoods its own product: `AGENTS.md`, `CLAUDE.md`, `.claude/`, `.gemini/` and the
other pointer files at the root are copies of `templates/`. Edit the `.template`, then run
`./sync-ai-templates.sh .` to refresh the copies.

## Rules that reviews enforce

- **Paired scripts.** Every shell script ships as `.sh` and `.ps1` with identical behavior; a
  change to one changes the other in the same commit.
- **Bash 3.2.** macOS runs the hook with `/bin/bash` 3.2: no associative arrays, no `mapfile`,
  guard empty arrays with `${arr[@]+"${arr[@]}"}`.
- **The session-start sync never breaks a session.** It exits 0 and prints one-line notes;
  everything else fails loudly with an actionable message.
- **Manifest-driven.** `templates-manifest.txt` is the only file map; scripts and docs never
  repeat the list.
- **No symlinks** in anything a project receives.
- **No secrets, no private material.** Nothing from an employer, no internal hostnames, no
  tokens. `tests/lint-skills.py` checks skills; `./sync-ai-templates.sh . --scan-private` checks
  tracked files against your own private-terms list.
- **Docs move with the code.** A user-visible change updates its page in `docs/` and adds a
  line to `CHANGELOG.md` under *Unreleased*.

## Test

```bash
tests/check.sh                 # the whole gate (~6 min): both suites, lints, code-health, docs
tests/run-tests.sh             # bash suite only
pwsh -NoProfile -File tests/run-tests.ps1   # PowerShell suite only
```

`tests/README.md` says what each case protects. A bug fix comes with the case that would have
caught it. The pre-push hook runs `tests/check.sh`; `SKIP_CHECK=1 git push` skips it when you
just ran it.

## Commits and pull requests

Conventional commits: `feat|fix|docs|refactor|test|chore(scope): summary`, one logical change
per commit. Open the pull request against `main` and fill in the template's checklist.

## Releases

Maintainers bump `engine/VERSION`, move the *Unreleased* entries of `CHANGELOG.md` under the new
version, and push the tag `vX.Y.Z`. The release workflow checks that the tag matches
`engine/VERSION` and writes the GitHub Release from the changelog.
