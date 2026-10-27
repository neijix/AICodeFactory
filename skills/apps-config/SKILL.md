---
name: apps-config
description: "Use when an app reads or writes the owner's personal settings (~/.<app>.json, settings.json, a sync/backup folder option), when adding a setting, when the user wants to share or open-source an app \"without my config\", asks where config should live, or mentions ~/.apps-config-dir or config.local. Rule: <app folder>/config.local/, else built-in defaults. Not for secrets or app data."
---

# apps-config — personal settings in `config.local/`, never in the repo

The owner shares apps with friends. A clone must work with **built-in defaults** and carry
**nothing personal**. The owner's settings live in the app's own folder, in `config.local/`:
gitignored and kept out of the code repo by `.git/info/exclude`, versioned by the project's
**private layer** (the hidden `.git/ai-context` repo that AICodeFactory's engine syncs to the
root's config repo), so they follow the owner to every PC of that root and never mix one code
root (say a personal one) with another (a work one).

## The rule

1. **Where**: `<app folder>/config.local/<file>`. The app folder is the checkout the app runs
   from (the repo root, not the current directory).
2. **Fallback**: no `config.local/<file>` → built-in defaults. A friend's clone has no
   `config.local/`: they get exactly the defaults, with no error and no prompt. Never create
   `config.local/` on your own, except in the one-time migration below or when the owner asks
   (a "Save in config.local/" button).
3. **Env override** (optional, for tests and one-off runs): `<APP>_CONFIG_LOCAL` = another folder
   used in its place; `none` or empty = local only. Process environment only.
4. **What goes there**: preferences and settings, small JSON/TOML/text, no secrets, the same on
   every PC of the owner's. **Per-machine values** (this PC's folders, its name, its port) stay
   local, or go in `config.local/machines/<hostname>/` when they must follow a re-install.
5. **What never goes there** (the engine also refuses to version these: `*.db`, `*.sqlite*`,
   `*.log`, `.env*`, `*.key`, `*.pem`, `cache/`, `__pycache__/`, files over 1 MB):
   - **Secrets** (passwords, tokens, keys) → OS keychain / the secrets skill for this code
     root, if one is installed.
   - **Databases, logs, caches, attachments, worktrees, models** → the app's local data dir.
6. **Repo**: ship `config.local.example/` (or a documented default), never the owner's file.
   `.gitignore` lists `config.local/`; the repo never mentions the owner's paths.
7. **Work-root exception**: an app that runs in several roots but lives in the personal one
   lets the owner point its settings at a folder under the work root's `.ai-root/` (a setting),
   so work-network values never reach the personal remote.

`~/.apps-config-dir`, `APPS_CONFIG_DIR` and the old shared sync folder they point at are **retired**:
read only by the one-time migration (remove it after 2027-01).

## One-time migration (legacy apps-config)

While `config.local/<file>` does not exist and the legacy `<root>/<AppName>/<file>` does
(`<root>` = `$APPS_CONFIG_DIR`, else the first line of `~/.apps-config-dir`): create
`config.local/`, copy the file in, log one line. Never overwrite, never delete the source, and
catch `OSError` (a cloud placeholder can `stat` fine and still fail to open). A friend has no
legacy file, so nothing is created for them.

## Resolving and reading (copy for the app's language)

Python:

```python
import os
import shutil
from pathlib import Path

APP_DIR = Path(__file__).resolve().parents[1]  # the checkout; adjust to the package depth


def config_local_dir(env_var: str = "MYAPP_CONFIG_LOCAL") -> Path | None:
    """config.local/ of this checkout (or $<APP>_CONFIG_LOCAL), None when local only."""
    override = os.environ.get(env_var)
    if override is not None:
        return None if override.strip() in ("", "none") else Path(override).expanduser()
    return APP_DIR / "config.local"


def migrate_legacy(app: str, name: str, target: Path) -> None:
    """Copy <apps-config root>/<app>/<name> into config.local once (remove after 2027-01)."""
    if (target / name).exists():
        return
    root = os.environ.get("APPS_CONFIG_DIR")
    if root is None:
        try:
            root = (Path.home() / ".apps-config-dir").read_text(encoding="utf-8").splitlines()[0].strip()
        except (OSError, IndexError):
            return
    if not root or root == "none":
        return
    source = Path(root).expanduser() / app / name
    try:
        if source.is_file():
            target.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target / name)
            print(f"{app}: copied {name} from the old apps-config folder into config.local/")
    except OSError:
        pass
```

Bash (3.2-safe) and PowerShell: the same two steps — `"$APP_DIR/config.local/$file"` if it is a
file, else defaults; `Join-Path $AppDir 'config.local'` with `Test-Path -LiteralPath`.

- Read **once per use or at start**; catch every read error, fall back to defaults and log one
  line — never crash, never 500.
- **Writes** from the app's UI go where it read from, atomically (temp file in the same folder +
  rename), so a sync never commits half a file.

## Moving an app onto the rule (checklist)

1. List what the app persists; sort each item into settings / secret / data / per-machine.
2. Read settings from `config.local/` (snippet above), keep the migration for the legacy file.
3. Add `config.local/` to `.gitignore`, ship `config.local.example/` with a README.
4. Test with `<APP>_CONFIG_LOCAL=none` (friend's view: defaults) and a temp folder (owner's view).
5. Document the file names and the fallback in the README (for friends) and PROJECT_STATE.
6. The project must be in `private` (or `team`) mode for the private layer to version
   `config.local/`: `update-projects --check` lists the ones that are not.

## Known consumers

Keep the list of the owner's apps on this rule (file names, env overrides, legacy folders) in
the owner's private overlay, not in this shared skill. AICodeFactory's own per-root files (dev
context, private terms) are not app settings: they live in `<code root>/.ai-root/`.
