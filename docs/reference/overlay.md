# Overlay reference

An overlay is a second git repo, usually private, that the engine layers on top of the factory:
its files extend the factory's templates and add skills. The factory takes precedence: an
overlay file or skill never replaces one of the same name. This page is its exact
layout and lookup order; [Set up a private overlay](../how-to/private-overlay.md) walks you
through creating one.

## Lookup order

The engine takes the first that applies:

1. `$AI_TEMPLATE_OVERLAY_DIR`. When the variable is set, steps 2 and 3 are skipped; `none` or an
   empty value means no overlay.
2. The first line of `~/.ai-template-overlay-dir` (written by `aicf setup --overlay <dir>`).
3. A sibling folder of the factory named `<factory folder name>-private`, for example
   `~/Code/AICodeFactory-private`.

A configured overlay that does not exist on this machine is one line, never an error:

```text
ai-sync: overlay <dir> not found — using AICodeFactory alone
```

The overlay is pulled (`git pull --ff-only`, clean tree only) by the same `--pull` step as the
factory, so pushing to it reaches your other machines at their next session start.

## Layout

```text
<overlay>/
├── templates/
│   ├── <src>.template          used only where the factory has no file of that path
│   └── <src>.template.append   appended to the rendered file
├── skills/
│   └── <name>/SKILL.md         installed like the factory's skills
└── overlay-manifest.txt        optional: extra or replacement manifest entries
```

`<src>` is the path a [manifest](manifest.md) entry names under `templates/`, for example
`templates/CLAUDE.md.template` or `templates/.claude/settings.json.template`.

| In the overlay | Effect |
|---|---|
| `templates/<src>.template` | The template of a manifest entry the factory has no file for (an `overlay-manifest.txt` entry). A factory file of the same path wins. |
| `templates/<src>.template.append` | Added after the rendered template (a newline is inserted when the template lacks a final one). Works for pointers and living docs alike. |
| `skills/<name>/` | Installed into every tool's skill folder by `--skills` and `aicf setup`. A name the factory ships too installs the factory's. |
| `overlay-manifest.txt` | Same format as `templates-manifest.txt`. Adds entries, or replaces the factory entry that targets the same destination. |

A pointer file is re-rendered at every session start, so a change to its `.template` or
`.append` reaches every project at once. A living doc is rendered only when it is created, so a
change reaches new projects only.

The factory's own checkout never gets overlay content in its pointer copies; skills keep the
overlay.

## Extra overlays and skill scope

The personal overlay's `factory.json` can name more overlays, for example a work overlay:

```json
{
  "overlays": ["AICodeFactory-Work"],
  "skills.scope": "global"
}
```

- `overlays`: a folder name is looked up in every code root (the factory's parent first), so
  the file holds no machine path; a path is taken as written. An overlay not cloned on this
  machine is skipped. Only its `skills/` are used, installed after the factory's and the
  personal overlay's (the first source wins a name clash).
- `skills.scope`: `environment` (default) keeps a personal overlay's skills off at work and a
  work overlay's (one under a work root, or named `*-work`) on only at work. `global` turns
  every overlay's skills on in every environment. An environment's `skills.off` still wins.

## Rules

- **Never put `sync-ai-templates.sh` in the overlay.** The hook's last candidate runs any
  sibling folder that holds `sync-ai-templates.sh` and `templates-manifest.txt`; an overlay
  holding both would be taken for the factory.
- A `--quiet` summary names both sources: `ai-sync: refreshed CLAUDE.md from
  AICodeFactory+AICodeFactory-private`.

## Old layout

Overlays made before the `templates/` and `skills/` folders still work. The engine reads, after
the new paths:

| Old path | New path |
|---|---|
| `<src>.template` at the overlay root | `templates/<src>.template` |
| `vscode-global/<file>` | `templates/global/<file>` |
| `vscode-global/skills/<name>/` | `skills/<name>/` |

While an old path is present, every run prints one note:

```text
ai-sync: overlay uses the old layout (<paths>) — move it to templates/ and skills/
```

Move the files with `git mv` and the note goes away.

## Example

[`examples/overlay/`](../../examples/overlay/README.md) is a working overlay: one skill and one
`AGENTS.md` fragment.
