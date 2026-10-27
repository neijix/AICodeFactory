# Choose who sees the AI files: tracked, private, shared, team

Each project is in one of four modes that decide which AI files its git repo carries. Pick the
mode from who clones the repo and whether your AI notes may be public.

| Mode | Use it when | Code repo carries | Your AI docs live in |
|---|---|---|---|
| **private** (default of `aicf init`) | The repo is yours, maybe public, and your AI notes are not for others | `.gitignore`, `.env.example` | A hidden repo in `.git/ai-context` |
| **tracked** | Everything may be public, and you want one repo | Every AI file | The code repo |
| **shared** | Other people clone it and should get `AGENTS.md`, but not your tool settings | `AGENTS.md`, `PROJECT_STATE.md`, `KNOWLEDGE.md`, `.env.example` | The code repo |
| **team** | A repo with other authors where you want your own AI layer | Whatever the team already tracks | A hidden repo, for the files the team does not track |

The [project files reference](../reference/project-files.md#which-files-git-tracks-per-mode)
lists every file per mode.

## Switch a project

Both switches need a clean index (nothing staged) and make one commit.

```bash
cd ~/Code/my-project
~/Code/AICodeFactory/bin/aicf sync . --private-layer --commit   # private (team is detected)
~/Code/AICodeFactory/bin/aicf sync . --shared --commit          # shared
```

`--private-docs` is the former name of `--private-layer` and still works.

A switch untracks files; it never deletes them from disk and never rewrites history. Files
committed before the switch stay in the old commits: if they must disappear from a public repo,
rewriting history is a separate decision.

## Private mode: the hidden repo

`--private-layer` moves your living docs (`AGENTS.md`, `.github/PROJECT_STATE.md`,
`.github/KNOWLEDGE.md`, `docs/state/`, `docs/plans/`, `config.local/`) into a bare git repo at
`.git/ai-context`, and lists them, with every pointer file, in `.git/info/exclude`. The code
repo keeps working as before; `git status` stays clean.

Each sync commits changes of those docs to the hidden repo. With no remote they exist on this
machine only:

```text
ai-sync: private AI docs kept in a local hidden repo only — install-global --ai-context-remote <url> shares them between machines
```

(`install-global` is what `aicf setup` runs.) Give the code root a private remote to carry them
between machines, one branch per project:

```bash
~/Code/AICodeFactory/bin/aicf setup --ai-context-remote git@github.com:you/ai-docs.git
```

From then on every session pushes the hidden repo, and a fresh clone on another machine gets its
docs back at its first session start. Without a remote, deleting the clone deletes the docs.

## Team mode

`--private-layer` turns into team mode by itself when the repo's recent history has authors
other than you (your `user.email`, plus any address listed in `<code root>/.ai-root/owner-emails`).
In team mode the engine never writes, untracks or commits a file the team tracks. It only keeps
your untracked AI files out of git and versions them in the hidden repo.

## Shared mode

`--shared` lists the pointer files (`CLAUDE.md`, `.claude/`, …) in `.gitignore` under
`# ai-templates: local-only` and untracks them; the living docs stay committed for everyone. A
teammate who uses AICodeFactory gets the pointer files back, untracked, with one run in their
clone:

```bash
~/Code/AICodeFactory/bin/aicf sync . --commit
```

## The private-terms guard

In every mode but tracked, the sync installs a `pre-commit` hook in `.git/hooks`. It refuses a
commit whose added lines or author identity hold one of your private terms (names, hosts,
employers), from a list kept outside every repo: `$AI_PRIVATE_TERMS_FILE`, else
`<code root>/.ai-root/private-terms.txt`, else `~/.private-terms`. One term per line; `re:`
starts a regular expression. No list, no check. Bypass it once with `git commit --no-verify`.
A `pre-commit` hook of your own is left alone; rename it `pre-commit.local` to keep it and get
the guard too.

Before publishing a repo, scan it:

```bash
~/Code/AICodeFactory/bin/aicf sync . --scan-private --history
```
