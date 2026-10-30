# Add a skill

A skill is a folder with a `SKILL.md` that an agent loads when its description matches the
task. Add it to the factory (or your overlay) once, and the next session start installs it for
every tool on the machine.

## 1. Choose where it lives

- **Your overlay** (`<overlay>/skills/<name>/`) for anything personal: your accounts, your
  machines, your habits. See [private overlay](private-overlay.md).
- **The factory** (`skills/<name>/`) only for a skill useful to anyone. That is a contribution:
  see [CONTRIBUTING.md](../../CONTRIBUTING.md).

A factory skill wins over an overlay skill of the same name: pick a name the factory does not use.

## 2. Write `SKILL.md`

```markdown
---
name: changelog-entry
description: Use when the user asks to add a changelog entry, or a change is ready to ship
  and CHANGELOG.md has no line for it. Adds one line under ## [Unreleased].
---

# Changelog entry

1. Read `CHANGELOG.md` and find `## [Unreleased]`.
2. ...
```

The rules ([Agent Skills format](https://agentskills.io/specification)):

- `name` equals the folder name: lowercase letters, digits and hyphens, 64 characters at most.
- `description` is what the agent matches against, so it says **when** to use the skill, with
  the words a user would type. 1024 characters at most.
- Keep `SKILL.md` under 500 lines; put long material in files next to it (`references/…`) and
  link them with relative links.
- Commands in a skill are plain shell commands. No MCP server
  ([why](../explanation/design-decisions.md#skills-and-shell-commands-not-mcp-servers)).
- A skill that drives one of your own program repos names it in `metadata:` /
  `  project: <repo folder>`; `aicf projects` then shows the link on both rows.

[`examples/overlay/skills/example-skill/`](../../examples/overlay/skills/example-skill/SKILL.md)
is a complete one to copy.

## 3. Check it

```bash
uvx --from skills-ref agentskills validate skills/changelog-entry   # the format
uv run tests/lint-skills.py                                         # factory only: the repo's own lint
```

`tests/lint-skills.py` reads the files git tracks, so `git add` the folder first.

## 4. Install it

Start a new agent session in any project: the hook's `--skills` step installs it. Or now:

```bash
~/Code/AICodeFactory/bin/aicf setup
```

On macOS and Linux each installed skill is a link to your checkout, so later edits are live at
once; on Windows it is a copy, refreshed at the next session start.

## Remove a skill

Delete the folder and add its name to `skills/RETIRED` (one name per line). The next session
start removes the installed copies on every machine, but only those this checkout installed.
