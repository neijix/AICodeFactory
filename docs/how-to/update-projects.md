# Refresh every project at once

Projects refresh themselves at session start, so this is optional. Use `aicf update` when you
want every project's sync commit now: after a template change, on a new machine, or for
projects you rarely open.

## Preview, then apply

```bash
~/Code/AICodeFactory/bin/aicf update          # preview: what each sibling project would get
~/Code/AICodeFactory/bin/aicf update --yes    # apply and commit, project by project
```

It covers every folder next to the factory that already has an `AGENTS.md`. Each project gets
the same treatment as a session start: pointer files refreshed, generic `AGENTS.md` sections
refreshed where you never edited them, one commit holding only those files. Your uncommitted
work is never part of it.

The run ends with the repos holding commits that are not on their remote. Nothing is pushed
unless you ask:

```bash
~/Code/AICodeFactory/bin/aicf update --yes --push
```

## One project

```bash
~/Code/AICodeFactory/bin/aicf update my-project
```

A project without AI files yet is bootstrapped by this command (in the mode the code root's
registry records for it, else tracked; see
[team and private docs](team-and-private-docs.md) to switch). Bulk runs never bootstrap: they
list such folders and leave them alone.

## Bring the whole code root up to date

```bash
~/Code/AICodeFactory/bin/aicf update --yes --clone --pull
```

- `--pull` fast-forwards the factory first, then every project that tracks a remote. A dirty
  tree or a diverged branch is reported and left alone.
- `--clone` clones your GitHub repos that have no local folder yet (needs an authenticated `gh`).

## Check the modes

```bash
~/Code/AICodeFactory/bin/aicf update --check            # each project's mode against the plan
~/Code/AICodeFactory/bin/aicf update --migrate          # preview the switches
~/Code/AICodeFactory/bin/aicf update --migrate --yes    # apply them
```

In a code root, the plan is the mode recorded in `.ai-root/projects/<name>`, else private.

Every option: [`aicf update`](../reference/cli.md#aicf-update).
