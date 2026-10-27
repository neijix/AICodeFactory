# Upgrade AICodeFactory

The factory is a git checkout that follows a channel: the latest release (`stable`, the
installer's default) or the development branch (`main`). Upgrading is running the installer
again, or a pull, plus `aicf setup` when the release notes say the machine-wide files changed.

## 1. See what changed

Read [CHANGELOG.md](../../CHANGELOG.md) for the versions between yours and the latest:

```bash
~/Code/AICodeFactory/bin/aicf --version
```

## 2. Update the checkout

Run the installer again, with the same command you installed with:

```bash
curl -fsSL https://raw.githubusercontent.com/neijix/AICodeFactory/HEAD/install.sh | bash
```

It fast-forwards the checkout to its channel (recorded as `git config aicf.channel`), never
resets it, refuses a checkout with uncommitted changes, then runs `aicf setup`. Pass
`--channel main` or `--channel stable` to switch. On Windows, the same with `install.ps1`
([Windows](windows.md)).

A checkout on a branch (the `main` channel, or a clone you made yourself) can also be pulled:

```bash
git -C ~/Code/AICodeFactory pull --ff-only
```

The session-start hook does that pull (`--pull`) for a checkout on a branch with no uncommitted
changes. A checkout pinned at a release tag is left as it is until you run the installer again.
With uncommitted changes the hook says so and uses the files on disk:

```text
ai-sync: AICodeFactory has uncommitted changes — pull skipped, using the templates on disk
```

Do the same in your overlay if you have one.

## 3. Re-run setup when needed

The installer already ran it. After a pull, skills and project files take care of themselves at
the next session start; re-run setup when a release changes the machine-wide files (the global instructions, the global hook):

```bash
~/Code/AICodeFactory/bin/aicf setup
```

It is safe to re-run any time: it keeps your other settings and records.

## 4. Check

```bash
~/Code/AICodeFactory/bin/aicf doctor
```

`aicf doctor --yes` runs every step above in order (pull, setup, re-sync, switch the projects
that miss their planned mode, refresh every project) and checks again.

## Projects

Each project picks up the new templates at its next session start. To refresh them all now:
[refresh every project](update-projects.md).
