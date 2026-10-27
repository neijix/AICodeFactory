# The session-start hook

Every project gets a Claude Code `SessionStart` hook that runs the factory's sync engine each
time a session starts. This page lists exactly what it runs, reads, writes, commits and sends
over the network, so you can decide whether to install it.

The hook is a shell command in the project's `.claude/settings.json`, a copy of
`templates/.claude/settings.json.template`. Claude Code runs it with `sh -c` on macOS and Linux
and with Git Bash on Windows. Agents without hooks (Codex, Copilot, Cursor, Gemini CLI,
Antigravity) are told by `AGENTS.md`, step 1 of "Session start", to run the same engine
themselves.

## How the hook finds the factory

It takes the first candidate that holds **both** `sync-ai-templates.sh` and
`templates-manifest.txt` (`P` is the project folder):

| # | Candidate | Covers |
|---|---|---|
| 1 | `$AI_TEMPLATE_DIR` | Explicit override; `aicf setup` writes it into `~/.claude/settings.json` |
| 2 | `$P/../AICodeFactory` | The factory as a sibling of the project, the common case |
| 3 | `$P/../../Code/AICodeFactory` | A project in a second code root beside `Code/` |
| 4 | `~/Code/AICodeFactory` | Repos under your home folder |
| 5 | the path in `~/.ai-template-dir` | The marker `aicf setup` writes, any layout |
| 6 | any sibling folder of the project holding both files | A renamed or moved factory |

Candidate 6 means that **any folder next to your project that holds those two files is run**.
Keep only trusted checkouts beside your projects, and never put `sync-ai-templates.sh` in an
overlay (the overlay would be taken for the factory).

When no candidate matches, the hook prints one line and the session goes on:

```text
ai-sync: AICodeFactory not found - shared AI files not refreshed. Run its install-global once on this machine, or set AI_TEMPLATE_DIR.
```

## What it runs

```sh
bash "<factory>/sync-ai-templates.sh" "<project>" --quiet --commit --pull --agents --skills
```

The hook gives it 60 seconds. `--quiet` keeps it silent when nothing changed; every line it does
print starts with `ai-sync:` and is shown to the agent. In order:

1. **Pull** (`--pull`). The code root's `.ai-root` checkout, if you have one, is fast-forwarded,
   and pushed when it holds a registry commit whose push failed. Then the factory and the
   overlay get `git pull --ff-only`, each only when its working tree is clean. When the factory
   moved, the engine starts again so the new version runs.
2. **Hidden repo.** For a project in private or team mode only: the hidden repo
   `.git/ai-context` is committed, rebased on its remote and pushed (see
   [team and private docs](../how-to/team-and-private-docs.md)).
3. **Sync** (`--commit`). Pointer files are copied where they differ from the templates, missing
   living docs are created, obsolete files are removed, and the paths it changed are committed.
   Then the context-budget check, the dev-context file and the factory section of
   `CLAUDE.local.md`, and a one-line conformance check of the project's mode.
4. **AGENTS.md** (`--agents`). `refresh-agents-sections.py` replaces the generic sections of
   `AGENTS.md` you never edited ([how](../explanation/agents-sections-refresh.md)). It runs with
   `uv run --no-project` when `uv` is installed, else `python3` or `python`, else it is skipped.
5. **Skills** (`--skills`). Every folder of `skills/` (the overlay's first) is linked or copied
   into each tool's global skill folder that already exists.

## What it reads

- The factory checkout: `templates-manifest.txt`, `templates/`, `skills/`, `engine/`.
- The overlay, when one is configured ([overlay](overlay.md)).
- The project's git state: `git status`, the managed block of `.git/info/exclude`, `.gitignore`.
- Machine files in your home folder: `~/.ai-template-dir`, `~/.ai-template-overlay-dir`,
  `~/.ai-work-roots`, `~/.ai-context-remote`, `~/.private-terms`, `~/.ai-skills-stamp`.
- In the code root, when it has them: `.ai-root/` (project registry, `environment.json`,
  `dev-context/`, `private-terms.txt`, `owner-emails`) and `.ai-context-remote`.
- For a private or team project, once per machine: Claude Code's auto-memory folder
  `~/.claude/projects/<slug>/memory`, imported into the project's `.claude/memory`.
- The [environment variables](environment.md).

## What it writes

In the project:

- the pointer files and, once, the living docs ([project files](project-files.md));
- `.gitignore`: adds `.env`, `.claude/settings.local.json` and `CLAUDE.local.md` when missing;
  in shared mode, also the pointer files under a `# ai-templates: local-only` line;
- `.git/info/exclude`: a managed block (`# ai-templates: <mode>` … `# ai-templates: end`) in
  private and team mode; your own lines outside the block are kept;
- `.git/hooks/pre-commit`: the private-terms guard, in every mode but tracked. A hook that is not
  the factory's is left alone (one line says so); `core.hooksPath` set means no guard;
- `CLAUDE.local.md` (gitignored): your code root's development rules and factory settings, when
  the code root has them;
- `.claude/settings.local.json` (gitignored): `autoMemoryDirectory` in private and team mode,
  and `skillOverrides` for skills your environment turns off;
- `.git/ai-context/`: the hidden repo, in private and team mode.

In your home folder:

- the global skill folders that exist: `~/.agents/skills`, `~/.claude/skills`,
  `~/.copilot/skills`, `~/.cursor/skills`, `~/.gemini/config/skills`. A skill installed by
  another source is left alone. Dangling symbolic links in those folders are removed, and so
  are copies of skills the factory retired;
- `~/.ai-skills-stamp` (and `.ai-skills-stamp.running` during an install), so an unchanged skill
  set is not reinstalled.

## What it commits

Only the paths the run changed, in the project's own repo, with a paths-only commit: work in
progress stays uncommitted and out of the commit.

| Message | When |
|---|---|
| `docs: sync AI instruction templates` | Pointer files changed |
| `docs: bootstrap project documentation` | Living docs were created |
| `docs(agents): refresh generic sections from template` | The `--agents` pass changed `AGENTS.md` (tracked mode only) |

It commits nothing while a merge or rebase is in progress (`MERGE_HEAD`, `rebase-merge` or
`rebase-apply` exists); it prints
`ai-sync: merge/rebase in progress in <project> — synced files left uncommitted`.

In private or team mode it also commits in the hidden repo (`ai-context: <files>`) and, when the
mode changes, in the code root's `.ai-root` registry (`chore(registry): <project> = <mode>`).

## Network

Only `git` against remotes you configured: `pull --ff-only` of the factory and the overlay,
fetch and push of `.ai-root` and of the hidden repo, and `ls-remote` of the hidden repo's
remote. Each step waits at most `AI_SYNC_PULL_WAIT` seconds (10), all of them together at most
`AI_SYNC_NET_BUDGET` (30); after the first timeout the rest are skipped. Git runs with
`GIT_TERMINAL_PROMPT=0`, so it never waits for a password.

The hook **never pushes your project's code repo**. Only `aicf sync --push`, `aicf update --push`
and `aicf doctor --yes --push` do, and only when you type them. `uv`, when it runs step 4, may
download a Python interpreter if none is installed, following its own settings.

## The other hooks in `.claude/settings.json`

| Event | What it does |
|---|---|
| `SessionStart` (`compact`) | Prints `git log --oneline -5` and `git status --short` after Claude Code summarized the context. |
| `UserPromptSubmit` | Touches `.git/ai-turn-start`, the start time of the turn. |
| `PreToolUse` (Bash) | Refuses a `git commit` or `gh pr create/edit` that carries an AI attribution line (`Co-Authored-By: Claude`, `Generated with Claude Code`, `Claude-Session`). |
| `PostToolUse` (Write, Edit) | Warns when a code file grew past the line limit (`file_lines` in `.code-health.json`, default 800). |
| `Stop` | Reminds the agent to commit the files it changed during the turn. |
| `Stop` | Private and team mode: syncs the hidden repo (`--ai-context-sync --quiet`). |

The same file also sets Claude Code options for the project: `permissions.allow` is `Bash(*)`
(the agent runs shell commands without asking) with a deny list (force push, `reset --hard`,
`filter-branch`/`filter-repo`, `clean -x`, `rm -rf` of `/` or the home folder, worktree
switching); `attribution` empty and `includeCoAuthoredBy: false`; and
`CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000`. Per-machine permissions belong in the gitignored
`.claude/settings.local.json`. To change any of this for every project, override the template
in your [overlay](overlay.md).

## The global hook

`aicf setup` also merges one `SessionStart` hook into `~/.claude/settings.json`
(`templates/global/claude-global-hook.json`). It runs `sync-ai-templates.sh --global-hook` from
`$AI_TEMPLATE_DIR` or `~/.ai-template-dir`. It does nothing unless the project sits in a code
root and its own `.claude/settings.json` lacks the sync hook, as in a fresh clone of a private
project. Then, when the code root's registry knows the project or the project has a mode, it
runs the project hook's sync once, so the project gets its files back; otherwise it prints one
line naming the command to run.
