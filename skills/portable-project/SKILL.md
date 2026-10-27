---
name: portable-project
description: "Use before a project starts needing something only the owner has: another of the owner's repos (sibling path, private git URL, path dependency), an absolute or home path (~/Code, F:\\Code, $AI_CODE_ROOT in app code), a LAN IP or home-lab host (192.168.x, *.lan, Portainer, Home Assistant, NAS), an owner-only tool or account. Also when writing install steps or a README, when the user says share, open-source, a friend should install it, installable, or asks for a portability audit. Proposes the fix: package, optional feature, config with defaults."
---

# portable-project — a stranger can clone it and run it

**The test:** someone with a fresh machine, public internet and no access to the owner's
accounts, repos or LAN runs `git clone` and the README's one install command — and the app
works. Features that genuinely need the owner's infrastructure are **off with a one-line
message**, never a crash, a hang or a silent failure.

Every project meets it unless its `PROJECT_STATE.md` says otherwise (see *Audience* below).

## The rule — agent behavior

1. **Before** adding anything from the table below, stop and **propose the better practice**
   in one or two lines (what breaks for a stranger, the fix, its cost). Do the portable version
   unless the owner chooses otherwise; record a kept exception in `PROJECT_STATE.md`.
2. Spotted one already in the code while working nearby → mention it once at the end of the
   reply with the fix; don't rewrite unrelated code unasked.
3. Asked for an audit → run the scanner and the clean-room test below, then report.

## Problem → better practice

| Found | Why a stranger fails | Do instead |
|---|---|---|
| Runtime need for another of the owner's repos (`../Sibling`, `$AI_CODE_ROOT/X`, `sibling-deps.txt`) | Repo missing or private → clone fails or feature breaks | 1) a **published package** (PyPI / npm / crates) or a git dependency on a **public** repo pinned to a tag; 2) vendor the small part used; 3) make it an **optional integration**: detect, else disable with a message. `sibling-deps.txt` (`launch-and-deploy`) only for public repos, and still optional |
| Path dependency (`path = "../X"` in `[tool.uv.sources]`, `"file:../X"` in `package.json`, `replace => ../x` in `go.mod`) | Path doesn't exist on their machine | Version or git+tag dependency in the committed manifest; the local checkout as a **dev-only override** (uv workspace member, `npm link`, a gitignored override file) |
| Absolute or home path in code, scripts or config (`/Users/…`, `C:\Users\…`, `F:\Code`, `~/Code`, `$AI_CODE_ROOT` in app code) | Different user, drive and layout | Path relative to the app (`Path(__file__).resolve().parent`, `$SCRIPT_DIR`, `$PSScriptRoot`); data in the OS app-data dir (`platformdirs`, XDG, `%APPDATA%`); a configurable setting with a default |
| LAN IP or home-lab host (`192.168.x.x`, `10.x`, `*.lan`, `*.local`, Portainer, Home Assistant, NAS share, `\\server\share`) | Not on that network | A setting (`.env` / `config.local/`) whose **empty default disables the feature**; `.env.example` holds a placeholder (`HA_URL=` with a comment), never the owner's address |
| Owner-only tool or service (the owner's local scraping service, local-model CLI or vault helper script, vault item names, the owner's password manager) required by the app | Not installed, no account | Optional backend behind a clear interface; standard fallback (plain HTTP fetch, env var for a secret, the OS keychain); the owner's helper is a convenience, not a requirement |
| Secret looked up by the owner's vault item name | Their vault has no such item | Read a **documented env var** (`OPENAI_API_KEY`); how the owner fills it (their secrets skill) stays out of the app |
| Personal identity in code (owner email, username, machine name, GitHub handle as a default) | Wrong for everyone else | Setting with a neutral default, or derived at runtime (`git config user.email`, `os.getlogin()`) |
| Deploy only to the owner's server (fixed Portainer stack, host IP in scripts) | Can't deploy at all | `docker compose up` works locally with no home-lab; deploy target = parameters (`DEPLOY_HOST`, …) in a gitignored file; the owner's values in `config.local/` |
| Install steps that live in the owner's head or in this machine's state | Nobody else can reproduce them | README *Quick start*: prerequisites with versions, one install command (`install.sh` + `install.ps1`), lockfile committed, `.env.example` complete with safe defaults |

Personal values belong in **`config.local/`** (`apps-config` skill), `.env` (gitignored) or the
project's private layer — never in tracked code, defaults or examples.

## Audience

`PROJECT_STATE.md` → *What This Is* states who must be able to install it:

- **public** (default under a personal root): anyone — the full test above.
- **team** (default under a work root): a colleague on the company network — internal
  registries, GitLab and company hosts are fine; the owner's own paths, machines and personal
  tools are not.
- **owner-only**: infrastructure that only makes sense on the owner's setup (home-lab IaC, this
  template repo). Say so in one line with the reason; the audit then only checks that secrets
  and machine paths stay out of git.

## Audit

1. **Scanner** (stdlib, advisory; ships with this skill):

   ```bash
   SCAN=~/.agents/skills/portable-project/scripts/scan_portability.py   # same file under ~/.claude/skills
   uv run "$SCAN" .                    # tracked files of the repo at .
   uv run "$SCAN" . --strict           # exit 1 when anything is found (CI)
   ```

   PowerShell: `uv run "$HOME\.agents\skills\portable-project\scripts\scan_portability.py" .`

   It reports machine paths, private-network addresses and LAN host names, path dependencies,
   references to sibling folders of the code root and `sibling-deps.txt` entries. The owner's
   personal terms (email, names) are checked by AICodeFactory's
   `sync-ai-templates.sh <project> --scan-private`.
2. **Clean-room test** — the only proof: a fresh clone in a temp folder, outside the code root,
   with the owner's environment hidden, then the README's install and test commands:

   ```bash
   tmp=$(mktemp -d) && git clone --depth 1 "$(git remote get-url origin)" "$tmp/app" && cd "$tmp/app"
   env -u AI_CODE_ROOT -u AI_TEMPLATE_DIR HOME="$tmp/home" ./install.sh   # then ./check.sh
   ```

   Better still, CI: a GitHub Actions runner has no siblings, no LAN and no owner tools — a
   workflow running install + tests from the checkout proves the test on every push.
3. **Report** one table — finding (`file:line`), what breaks for a stranger, proposed fix,
   effort (S/M/L) — ordered by what blocks install first. Fix only what the owner picks.
