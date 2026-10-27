# Use AICodeFactory on Windows

Everything works on Windows with no Developer Mode and no admin rights: projects receive plain
copies, and global skills are installed as copies too. The commands are `bin\aicf.ps1` in
PowerShell 7; the session-start hook itself runs in Git Bash.

## Requirements

- **Git for Windows**, which provides Git Bash. Claude Code runs its hooks with it, so the
  project hook (`bash sync-ai-templates.sh …`) works as on macOS.
- **PowerShell 7** (`pwsh`). Windows ships only Windows PowerShell 5.1, which cannot run the
  scripts; started from 5.1 they hand over to `pwsh`, or tell you to install it:

  ```powershell
  winget install --id Microsoft.PowerShell -e
  ```

- `uv` or Python, for the `AGENTS.md` refresh (optional; skipped without them).

## Install

In PowerShell:

```powershell
irm https://raw.githubusercontent.com/neijix/AICodeFactory/HEAD/install.ps1 | iex
```

It clones the factory into `~\Code\AICodeFactory` (or `$env:AI_CODE_ROOT\AICodeFactory`) and
runs `aicf setup`. To pass options (`--code-root D:\Code`, `--channel main`, or any `aicf setup`
option):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/neijix/AICodeFactory/HEAD/install.ps1))) --code-root D:\Code
```

Or by hand:

```powershell
mkdir $HOME\Code -Force | Out-Null; cd $HOME\Code
git clone https://github.com/neijix/AICodeFactory.git
.\AICodeFactory\bin\aicf.ps1 setup
```

Your code root may be on another drive (`D:\Code`): the factory finds projects relative to
itself, and `aicf setup` records its own path in `~\.ai-template-dir` for the hook.

## Spell multi-word options the PowerShell way

`aicf.ps1` passes your arguments to a PowerShell script. A single-word option works in both
spellings (`--yes` or `-Yes`), but a multi-word one must be written in PowerShell style for the
commands that bind parameters:

| macOS and Linux | Windows |
|---|---|
| `bin/aicf update --dry-run` | `bin\aicf.ps1 update -DryRun` |
| `bin/aicf update --yes --push` | `bin\aicf.ps1 update -Yes -Push` |
| `bin/aicf sync . --private-layer --commit` | `bin\aicf.ps1 sync . --private-layer --commit` (both spellings work for `sync`) |

`aicf update` previews by default, so a dropped `--dry-run` still changes nothing.

## Differences from macOS and Linux

- **Skills are copies.** An edit in `skills/` reaches the installed copies at the next session
  start, not at once. A copy you edited by hand is kept, with a warning.
- **Other agents** run `sync-ai-templates.ps1` when `AGENTS.md` tells them to refresh, the
  PowerShell twin of the Bash engine, with the same behavior.
- **Line endings.** The factory's `.gitattributes` checks every file out with LF endings,
  whatever `core.autocrlf` says: Bash cannot run a `.sh` file with CRLF endings, and the engine
  copies templates byte for byte. Do not override it.

## Troubleshooting

See [troubleshooting](../troubleshooting.md), in particular the PowerShell 5.1 parser error.
