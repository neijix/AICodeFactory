# Pointer files vs living docs

A pointer file is the same in every project and belongs to the factory, so the sync overwrites
it whenever the template changes. A living doc describes one project and belongs to that
project, so the sync creates it once and never overwrites it.

## Why two kinds

Some instructions are about how you work, whatever the project: how an agent starts a session,
when it commits, which hooks guard the repo. Those should change in one place and reach every
project. Other instructions are about one codebase: its architecture, commands, gotchas and
conventions. Those must never be replaced by a template.

The factory keeps the first kind short and generic (pointer files) and the second kind in a few
files the project owns (living docs). Every tool-specific pointer file points at `AGENTS.md`,
so the project's own rules exist once.

## What this means for you

| You want to… | Edit |
|---|---|
| Change a rule for every project | The template in the factory, or better, a `.template` or `.template.append` in your [overlay](../how-to/private-overlay.md) |
| Change a rule for one project | That project's `AGENTS.md` (the `## Taste` or `## Project-specific notes` section) |
| Record a solved problem | That project's `.github/KNOWLEDGE.md` |
| Give Claude Code a permission on one machine | That project's `.claude/settings.local.json` (gitignored) |

Editing a pointer file in a project is lost at the next session start. The
[project files reference](../reference/project-files.md) says which file is which.

## The exception: generic sections of `AGENTS.md`

`AGENTS.md` is a living doc, but two of its sections are about how you work, not about the
project: "Session start" and "Post-task checklist". When the template improves them, the hook's
`--agents` pass carries the new text into every project whose copy of that section is still
some past version of the template's. A section you edited is never touched.
[How the refresh decides](agents-sections-refresh.md).

## The overlay applies to both

A `.template.append` or replacement `.template` in your overlay is applied whenever a file is
rendered. For a pointer that is every session start, so the change reaches every project at
once. For a living doc that is only when the doc is created, so the change reaches new projects
only; copy it by hand into the existing ones that need it.

## Who can read what

Living docs can describe private things: hosts, accounts, internal decisions. A project you
share can keep them out of its repo: in private mode they live in a hidden repo next to the
code repo, in shared mode the pointer files stay local. See
[team and private docs](../how-to/team-and-private-docs.md).
