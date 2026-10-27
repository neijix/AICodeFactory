# Keep your own rules in a private overlay

An overlay is a second repo, usually private, that the factory layers on top of its own files:
your skills, extra rules and replacement templates reach every project without a fork. This page
creates one from [`examples/overlay/`](../../examples/overlay/README.md).

## 1. Create the repo

Put it next to the factory and name it `<factory folder>-private`: the engine then finds it with
no setup at all.

```bash
cp -R ~/Code/AICodeFactory/examples/overlay ~/Code/AICodeFactory-private
cd ~/Code/AICodeFactory-private
git init
git add -A
git commit -m "Start my overlay"
```

Push it to a **private** remote of your own to share it between machines.

Anywhere else, record its path once per machine:

```bash
~/Code/AICodeFactory/bin/aicf setup --overlay ~/somewhere/my-overlay
```

That writes `~/.ai-template-overlay-dir` and installs the overlay's skills in the same run.

## 2. Add what you need

| You want | Add to the overlay |
|---|---|
| A personal skill | `skills/<name>/SKILL.md` |
| A few lines at the end of a project file | `templates/<file>.template.append`, for example `templates/CLAUDE.md.template.append` |
| A different version of a project file | `templates/<file>.template`, same path as in the factory's `templates/` |
| A file the factory does not ship | `templates/<file>.template` plus a line in `overlay-manifest.txt` |

Paths follow the factory's [manifest](../reference/manifest.md); the
[overlay reference](../reference/overlay.md) has every rule.

## 3. See it applied

Commit in the overlay, then start a session in any project, or run the sync by hand:

```bash
~/Code/AICodeFactory/bin/aicf sync ~/Code/my-project --dry-run
```

The dry run lists the files the overlay changes (`[update] CLAUDE.md`). At session start the
hook says the same in one line that names both sources:

```text
ai-sync: refreshed CLAUDE.md from AICodeFactory+AICodeFactory-private
```

## What reaches existing projects

- Pointer files (`CLAUDE.md`, `.claude/…`, …): at the next session start of each project.
- Living docs (`AGENTS.md`, `PROJECT_STATE.md`, …): only projects created from now on, because a
  project owns its living docs. Copy the line by hand where you need it.
- Skills: at the next session start, on every machine where the overlay is checked out.

## Keep it private

The overlay is where personal material goes: hosts, accounts, employer rules. Never put it in
the factory, and never put `sync-ai-templates.sh` in the overlay: the hook would take the overlay
for the factory.

Turn the overlay off for one command with `AI_TEMPLATE_OVERLAY_DIR=none`.
