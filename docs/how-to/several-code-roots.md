# Use several code roots (personal and work)

A code root is a folder that holds projects, such as `~/Code` for your own and `~/Work` for an
employer's. One factory serves every root on the machine, and each root can have its own
rules, its own remote for private AI docs and its own Claude Code account.

The examples use `~/Code` (holding the factory) and `~/Work`.

## 1. Let the projects of the second root find the factory

Nothing to do once `aicf setup` has run: the hook tries `../../Code/AICodeFactory` (a sibling
root named `Code`), then the path `aicf setup` wrote to `~/.ai-template-dir`.
[Full lookup order](../reference/hook.md#how-the-hook-finds-the-factory).

## 2. Give the root its settings folder

The engine treats a folder as a code root when it holds `.ai-root/` (or `.ai-context-remote`).
Make `.ai-root` a git repo so its files can travel between machines:

```bash
mkdir -p ~/Work/.ai-root && cd ~/Work/.ai-root && git init
```

What it can hold:

| File | Effect |
|---|---|
| `environment.json` | `"label"`: shown at session start; `"work"` makes the root a work environment (no label: `personal`) |
| `dev-context/rules.md` | Development rules for every project of this root, copied into each project's gitignored `CLAUDE.local.md` |
| `projects/<name>` | Written by the engine: each project's mode (`mode=private`, …) |
| `claude-profile.json` | Written by `aicf setup --claude-profile` (step 5) |

Keep credentials out of it; it is a plain git repo.

## 3. Mark the work root

A work root keeps its private AI docs away from your personal remotes. Declare it one of three
ways:

```bash
~/Code/AICodeFactory/bin/aicf setup --work-root Work      # appends to ~/.ai-work-roots
```

- `~/.ai-work-roots`: one folder name (matches that folder anywhere in a path, any case) or
  absolute path per line.
- `AI_WORK_ROOTS`: the same list in a variable (`:` between entries, `;` on Windows; `none`
  means no work root); it replaces the file.
- `"label": "work"` in the root's `.ai-root/environment.json` (any other label: personal).

Under a work root the engine reads the hidden-repo remote only from the root's own
`.ai-context-remote`, refuses a `github.com` remote there, and lets `AI_CONTEXT_REMOTE` only
disable it.

## 4. Give each root its remote for private AI docs (optional)

Private projects keep their AI docs in a hidden repo per project. To carry them to your other
machines, give each root a private git remote:

```bash
~/Code/AICodeFactory/bin/aicf setup --ai-context-remote ~/Code=git@github.com:you/code-ai-docs.git
~/Code/AICodeFactory/bin/aicf setup --ai-context-remote ~/Work=git@git.example.com:you/work-ai-docs.git
```

Each line writes `<root>/.ai-context-remote`. Without one, the docs stay on this machine.
[Team and private docs](team-and-private-docs.md).

## 5. Give each root its own Claude Code account (optional)

```bash
~/Code/AICodeFactory/bin/aicf setup --claude-profile ~/Work
~/Code/AICodeFactory/bin/aicf setup --claude-env ~/Work=ANTHROPIC_BASE_URL=https://llm-gateway.example.com
```

This gives `~/Work` its own Claude Code config folder (login, settings, memory; default
`~/.claude-work`) and adds a `claude` function to your shell profiles that picks that folder
whenever you start `claude` inside `~/Work`. A value that looks like a secret is refused,
because `claude-profile.json` is committed in `.ai-root`.

## 6. Create projects in the second root

`aicf init` creates projects next to the factory only. In another root, create the repo and
switch it to the private layer:

```bash
mkdir ~/Work/api && cd ~/Work/api && git init
~/Code/AICodeFactory/bin/aicf sync . --private-layer --commit
```

Then open it in your agent to fill in the docs. An existing repo of that root is the same
command without `git init`.
