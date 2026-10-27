# Set up a new machine

Clone the factory (and your overlay), run `aicf setup`, and let `aicf doctor` tell you what is
left. Your projects then refresh themselves as you open them.

## macOS and Linux

Clone your overlay first, if you have one, so that setup finds it; then install:

```bash
mkdir -p ~/Code && cd ~/Code
git clone git@github.com:you/AICodeFactory-private.git      # your overlay, if you have one
curl -fsSL https://raw.githubusercontent.com/neijix/AICodeFactory/HEAD/install.sh | bash
```

The installer clones the factory into `~/Code/AICodeFactory` and runs `aicf setup`; options after
`bash -s --` go to it, then to setup (`--code-root DIR`, `--channel main`, `--overlay <dir>`).
Cloning the factory by hand and running `~/Code/AICodeFactory/bin/aicf setup` does the same.

Requirements: `git` and `bash`; `uv` or `python3` for the `AGENTS.md` refresh. `gh` is
optional (`--clone`).

If the overlay is not a sibling named `AICodeFactory-private`, add
`--overlay <dir>`. If your code roots have private remotes for their AI docs, pass them now:
`--ai-context-remote <root>=<url>` (see [several code roots](several-code-roots.md)).

## Windows

See [Windows](windows.md): the same steps with `bin\aicf.ps1` in PowerShell 7.

## Get your projects

```bash
~/Code/AICodeFactory/bin/aicf update --yes --clone --pull
```

`--clone` clones every GitHub repo of yours that has no folder yet (needs `gh auth login`),
`--pull` fast-forwards the ones you have. In a private project the first session start restores
the AI docs from the code root's remote.

## Check

```bash
~/Code/AICodeFactory/bin/aicf doctor
```

One line per item: `OK`, `FIX` (`aicf doctor --yes` repairs it), `TODO` (only you can; the
line says how), `WARN` (worth knowing). Exit 0 when nothing is `FIX` or `TODO`.

Finally reload VS Code and Cursor (Developer: Reload Window); Claude Code, Codex and Gemini CLI
pick the changes up in their next session.
