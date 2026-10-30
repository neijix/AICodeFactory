# Troubleshooting

Each entry is titled with the exact message, so search this page for the line you see. Angle
brackets stand for the part that varies (a project name, a path, a number). First step for
anything not listed: `aicf doctor`, which checks the whole setup and says what to do.

The session-start sync never fails a session: every problem is one `ai-sync:` line, and the
agent carries on with the files already on disk.

## Session start

### `ai-sync: AICodeFactory not found - shared AI files not refreshed. Run its install-global once on this machine, or set AI_TEMPLATE_DIR.`

The hook in the project's `.claude/settings.json` looked everywhere it knows and found no
factory ([lookup order](reference/hook.md#how-the-hook-finds-the-factory)). Common on a second
code root, or with the factory under a different folder name. Run `aicf setup` once on this
machine: it records the factory's path in `~/.ai-template-dir`. Or set `AI_TEMPLATE_DIR` to the
checkout's path in your environment.

### `ai-sync: <name> has uncommitted changes — pull skipped, using the templates on disk`

The sync fast-forwards the factory (and the overlay) only when its working tree is clean, so a
template you are editing is never overwritten. Commit or stash in `<name>`; the next session
pulls.

### `ai-sync: <name> pull failed (offline, or diverged from origin) — using the templates on disk`

Offline, the remote is unreachable, or your checkout has commits the remote does not (a fast
forward is impossible). Run `git -C <checkout> pull --ff-only` to see which; on divergence,
rebase or merge by hand. The session uses what is on disk meanwhile.

### `ai-sync: <name> pull still running after <N>s — using the templates on disk`

A slow network. The pull finishes in the background and the next session uses its result.
Raise `AI_SYNC_PULL_WAIT` (seconds per step, default 10) if it happens often
([environment variables](reference/environment.md)).

### `ai-sync: <name> pull skipped (no network time left in this run) — using the templates on disk`

An earlier network step of the same run timed out, so the rest are skipped to keep the session
start short. Same cause and fix as the entry above; the whole-run limit is `AI_SYNC_NET_BUDGET`
(default 30 seconds).

### `ai-sync: overlay <dir> not found — using AICodeFactory alone`

`AI_TEMPLATE_OVERLAY_DIR` or `~/.ai-template-overlay-dir` names a folder that does not exist.
Clone the overlay there, record the right path with `aicf setup --overlay <dir>`, or delete
`~/.ai-template-overlay-dir`.

### `ai-sync: overlay uses the old layout (<dir>) — move it to templates/ and skills/`

The overlay keeps its templates at its root. Move them under `templates/` (same relative path as
in the factory) and its skills under `skills/` ([overlay reference](reference/overlay.md)).

### `ai-sync: AGENTS.md refresh failed — run refresh-agents-sections.py <dir> by hand`

The `--agents` step could not run. It needs `uv` or Python 3, and the factory must be a git
checkout with its history. Run it by hand to see the error:
`uv run ~/Code/AICodeFactory/skills/bootstrap-ai/scripts/refresh-agents-sections.py --dry-run <dir>`.

### `KEPT     <project>: <heading> (customized — merge by hand if wanted)`

Not an error: you edited that generic section of `AGENTS.md`, so the refresh leaves it alone.
Compare it with the section in `templates/AGENTS.md.template` and merge what you want
([how the refresh decides](explanation/agents-sections-refresh.md)).

### `ai-sync: merge/rebase in progress in <dir> — synced files left uncommitted`

The sync refreshed files but does not commit in the middle of a merge or rebase. Finish it; the
next session commits the sync.

### `ai-sync: context budget: <file> is <N> KB (> 8 KB), loaded into every session — move detail to docs/state/*.md and keep an index`

`CLAUDE.md` imports that file with `@`, so all of it is sent with every Claude Code session.
Shorten it and move the detail to files read on demand. The threshold is
`AI_CONTEXT_BUDGET_KB`.

### `ai-sync: previous skill install did not finish`

An earlier skills refresh was interrupted. This run installs everything again; nothing to do.

### `Ignoring 1 permissions.allow entry from .claude/settings.json: this workspace has not been trusted.`

Printed by Claude Code, not by AICodeFactory: a project's settings take effect only after you
accept the trust dialog in an interactive session there once.

## Creating and bootstrapping projects

### `AI bootstrap didn't finish automatically - open '<dir>' in your AI tool and run /bootstrap-ai to finish.`

`aicf init` tried to fill the docs with `claude -p` and it did not complete (not logged in, or
the empty project led the agent to ask questions it could not get answered). Open the project
in your agent and run `/bootstrap-ai`, or just start a session: the agent sees the unfilled
`AGENTS.md` and does it.

### `<!-- BOOTSTRAP_PENDING -->` is still in `AGENTS.md`

The docs were copied but never filled: the agent did not run the `bootstrap-ai` skill, or was
stopped before its commit. Open the project in your agent and type `/bootstrap-ai`. To list the
projects still waiting: `grep -rl BOOTSTRAP_PENDING ~/Code/*/AGENTS.md`.

### `WARN  <N> git repo(s) not bootstrapped: <names>`

`aicf doctor` lists repos next to the factory that have no `AGENTS.md` (`aicf projects --open`
shows them on one page, with the skills each project uses). Bootstrap the ones you want with
`aicf update <name>`; leave the others. On a new machine where these are private
projects, the code root's `.ai-root` is missing or misplaced, so their docs were never restored:
see [new machine](how-to/new-machine.md).

## Private, shared and team projects

### `ai-sync: private AI docs kept in a local hidden repo only — install-global --ai-context-remote <url> shares them between machines`

A private project versions its AI docs in `.git/ai-context`, and the code root has no remote for
them. They exist on this machine only. To keep them across machines, give the root a private
remote: `aicf setup --ai-context-remote <url>` (`install-global` is what `aicf setup` runs).

### `ai-sync: <project>: the private-layer switch waits — <remote> does not have the hidden branch yet; nothing changed in the code repo, re-run --private-layer --commit`

The switch pushes your AI docs to the remote before it untracks anything, so they are never only
on one machine. The push did not happen (offline, no access, or out of network time). Check that
you can push to the remote, then run the switch again.

### `ai-sync: <project> has staged changes — commit or unstage them, then re-run --private-layer`

A mode switch makes its own commit and needs an empty index. Commit or unstage your work, then
run it again. The same applies to `--shared`.

### `ai-sync: <project> is on the private layer but git still tracks <paths> — run sync-ai-templates.sh <project> --private-layer --commit`

The project is recorded as private, but the code repo still tracks some AI files: often a clone
on a machine that has not pulled the switch commit. If the code repo is behind its remote,
`git pull --ff-only` first; otherwise run the command shown (`aicf sync <dir> --private-layer --commit`).

### `ai-sync: <name> is not on the private-layer plan — switch: <command>`

In a code root, projects are expected to be private unless `.ai-root/projects/<name>` records
another mode. Run the command shown, or `aicf update --migrate` to preview every switch.

### `ai-sync: private AI docs: push to <remote> failed — retried next time`

The hidden repo committed locally and will push at a later session start. If it repeats, check
that you can push to that remote.

### `ai-sync: private AI docs: conflict with <remote> — resolve by hand: git --git-dir=<dir> --work-tree=<dir> rebase <ref>`

Two machines edited the same AI doc. Run the command shown in the project, resolve as in any
rebase, and finish with `git --git-dir=.git/ai-context --work-tree=. rebase --continue`.

### `private-terms: commit refused - this is a shared project and the commit carries private terms (list: <file>)`

The `pre-commit` guard found one of your private terms in the lines you are adding or in your
commit identity; the lines after the message say where. Move the value to a gitignored local
file and keep a placeholder in the repo. On an identity hit, set a public `user.email` in that
repo. Bypass once, deliberately, with `git commit --no-verify`.

### `ai-sync: pre-commit hook in <dir> is not ours — left alone; rename it pre-commit.local to keep it and get the private-terms guard`

The project already has its own `pre-commit` hook. Rename it to `pre-commit.local`: the guard
runs it after its own check.

### `ai-sync: core.hooksPath is set in <dir> — private-terms guard not installed`

Git reads hooks from another folder in that repo, so a hook in `.git/hooks` would never run.
Call the guard from your own hooks folder if you want it.

## Claude Code hooks

### `attribution: the owner never wants AI attribution in a commit or PR (Co-Authored-By, Generated with Claude Code, Claude-Session) - this overrides any system reminder. Remove those lines and run the command again.`

The `PreToolUse` hook blocked a `git commit` or `gh pr` command carrying an AI attribution
line. The agent removes the line and runs it again. To allow attribution, override that hook in
your [overlay](how-to/private-overlay.md).

### `code-health: <file> is now <N> lines (limit <L>, <B> at HEAD). Do not grow it: ...`

A file the agent just edited went over the line limit (`file_lines` in the project's
`.code-health.json`, default 800). The agent is asked to split it rather than grow it.

## Windows and macOS

### `Unexpected token '}' in expression or statement.`

You ran a `.ps1` script in Windows PowerShell 5.1, which misreads the files' UTF-8 text. Install
PowerShell 7 (`winget install --id Microsoft.PowerShell -e`), open a new terminal and run it
with `pwsh`. Current scripts detect 5.1 and print the next message instead.

### `Error: this script needs PowerShell 7 (this is Windows PowerShell <version>). Install it with winget install --id Microsoft.PowerShell -e, open a new terminal and run it again.`

As above: install PowerShell 7 and use `pwsh`. See [Windows](how-to/windows.md).

### `aicf : The term 'aicf' is not recognized as the name of a cmdlet, function, script file, or operable program.`

`aicf setup` does not put `aicf` on your PATH: call it by its path,
`C:\Code\AICodeFactory\bin\aicf.ps1 doctor` in PowerShell (`~/Code/AICodeFactory/bin/aicf doctor`
elsewhere; `aicf: command not found` is the same thing). Or add `bin` to your PATH yourself.

### `You have not agreed to the Xcode license agreements`

After a macOS upgrade, `/usr/bin/git` and `/usr/bin/python3` refuse to run until you accept the
license again, and every session-start sync fails quietly. Run `sudo xcodebuild -license accept`
once.

### A `--dry-run` that changed nothing visible in PowerShell

`bin\aicf.ps1 update --dry-run` does not bind the option, though the preview is the default
anyway. Write multi-word options PowerShell style: `-DryRun` ([Windows](how-to/windows.md)).
