# Security policy

## What runs on your machine

AICodeFactory installs a **session-start hook** in your AI tools. Every time you open a project,
the hook runs `sync-ai-templates.sh` (or `.ps1`) from your AICodeFactory checkout. It copies
instruction files into the project, may commit the files it wrote (never pushes, unless you
opted in with `--push`), and may run `git pull` on the factory checkout. Exactly what it reads,
writes and commits: [docs/reference/hook.md](docs/reference/hook.md). Read it before installing.

Rules the project holds itself to:

- No secrets in any file it writes, commits or prints.
- No network call except `git fetch`/`pull`/`push` against remotes you configured, each
  bounded by a timeout.
- `localhost` is not a trust boundary: nothing is handed to a process because it is local.

## Supported versions

The latest release and `main`. Older tags get no fixes.

## Reporting a vulnerability

Use GitHub's **private vulnerability reporting**:
[Security → Report a vulnerability](https://github.com/neijix/AICodeFactory/security/advisories/new).
Do not open a public issue. Expect a first answer within 7 days. Please include the OS, the
`aicf --version` output and the smallest steps that reproduce the issue.
