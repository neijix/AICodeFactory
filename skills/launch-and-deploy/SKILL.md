---
name: launch-and-deploy
description: "Use when creating or changing how a project starts, stops or deploys: start/stop/kill.command triad, start or deploy scripts, making a project startable from a launcher or tray app, an app that needs another repo cloned beside it (sibling-deps.txt), assigning a fixed local PORT, a macOS LaunchAgent/launchd plist (or a background service that is mysteriously slow or stalls), exposing an app beyond localhost (LAN, port-forward, reverse proxy, public host: IP allowlist + firewall rules), or when the user says launch, run the full stack, or deploy to a server."
---

# One-Click Launch & Full-Stack Deployment Automation

## One-click launcher — always create and maintain one

- Every project MUST have a single launcher the user can double-click or run with one command to
  start the *entire* application — every process needed (frontend, backend, database, workers,
  etc.), not just one piece of it.
- Match the launcher to the platform: `start.bat`/`start.cmd` on Windows (or a compiled
  shortcut/`.exe` if the project already builds one), `start.sh`/`start.command` on macOS/Linux.
  If the repo targets both, provide both.
- Prefer **project-root** names launcher tools auto-detect: `start.sh` / `start.ps1` (also
  common: `launch|run|dev` + those extensions). Do not hide the only launcher under `scripts/`
  unless something at the root (a wrapper, a launcher app's manifest) points at it.
- The launcher must: start every required service in the right order, wait on dependencies
  (e.g. DB ready before backend), and open the app (browser tab, window) when ready.
- Keep it at the project root (or `scripts/` + a root pointer) and update it immediately
  whenever a new service, port, or startup step is introduced — a stale launcher is treated as
  a broken build.
- Document its name and usage in `.github/PROJECT_STATE.md` under Key Commands.


## macOS LaunchAgents — background services that start at login

When a project runs as a LaunchAgent (no Terminal window, starts at login), the plist decides
how macOS schedules it — and everything it spawns.

- **`ProcessType` must be `Interactive`** (or left out: `Standard`) for anything a person waits
  on — a web UI, an API, a daemon that launches other tools. **Never `Background`.** launchd
  puts a `Background` job in the throttled band: scheduler **priority 4 instead of 31**,
  efficiency cores, slowed I/O, and **child processes inherit it**. Typical symptom: a hub
  service stops answering for minutes whenever the machine is busy (WebSocket keepalive
  timeouts, a failing 30 s health check), and every tool it launches has been running
  throttled all along. Check a running job with:

  ```bash
  launchctl print gui/$(id -u)/<label> | grep "spawn type"    # "background" = throttled
  ps -o pid,pri,command -p "$(pgrep -f <pattern>)"            # PRI 4 = throttled, 31 = normal
  ```

  Keep a unit test on the rendered plist so nobody "tidies" it back.
- **A clean, explicit environment**: `HOME`, a fixed `PATH`
  (`~/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin`), `LANG`. Never copy
  the caller's environment — a restart from an agent's shell would leak its session variables
  into the service. No secrets in the plist (it is 0644): the service reads a 0600 env file.
- `KeepAlive: {SuccessfulExit: false}` restarts a crash but lets a clean exit (a "Quit" menu
  item) stay quit. A process that exits non-zero because a dependency is missing is relaunched
  every ~10 s, so only load the agent once its imports work.
- A menu-bar / tray helper also needs `LimitLoadToSessionType: Aqua` (GUI sessions only).
- **Reload** with `launchctl bootout gui/$UID <plist>` then `bootstrap`; a plist edit is not
  picked up otherwise. **A service that restarts itself** uses
  `launchctl kickstart -k gui/$UID/<label>` from a detached `sh -c 'sleep 1; …'`: launchd owns
  the relaunch, so nothing the dying process spawned has to outlive it.
- Scripts started *by* the service that reload it (a tray menu running `start.sh`) must run in
  their own session (`start_new_session=True` / `setsid`), or the `bootout` kills them mid-way.

## Start / Stop / Kill triad — required for every long-running local app

Every project that runs a **long-lived local process** (web UI, API, daemon, Docker Compose
stack, background workers) MUST ship these at the **project root** on macOS:

| File | Role |
|---|---|
| `start.command` | One-click start of the *entire* stack (same rules as the one-click launcher above) |
| `stop.command` | **Graceful** shutdown (SIGTERM / `docker compose stop` / app-specific clean exit) |
| `kill.command` | **Force** shutdown (SIGKILL / `kill -9` on the fixed listen port(s)) |

**When required:** any app you leave running in the background or reopen from a launcher or
tray app / Finder. **When to skip:** pure libraries, docs-only repos, one-shot CLIs, template
sources, and launcher entries that only `open` a file/folder (no process to stop).

### Behavior rules

1. **Idempotent** — `stop` / `kill` exit `0` and print a clear message when nothing is running.
   Never fail just because the app was already stopped.
2. **Port-based when needed** — a launcher or tray app that stops an app by signalling its
   own processes (never an agent CLI, an editor or a shell) can leave the port held by a
   process it must not touch. `stop.command` / `kill.command` MUST free the project's
   **fixed** listen port(s) (and any documented secondary ports) so a later `start.command`
   always works.
3. **Split graceful vs force** — do not combine both into one script. `stop` = SIGTERM (short
   wait, report leftovers); `kill` = SIGKILL immediately. `start.command` may still do its own
   kill-before-start (see below).
4. **Finder-safe** — prepend Homebrew to `PATH`; `cd` to the script directory; use
   `#!/bin/bash` or `#!/usr/bin/env bash` + `set -euo pipefail`.
5. **Cross-platform mirrors** — when the project targets Windows too, ship `stop.ps1` /
   `kill.ps1` (and/or `.bat`) with the same behavior. Prefer also keeping `start.sh` /
   `start.ps1` for non-Finder shells.
6. **Document** the triad under Key Commands in `.github/PROJECT_STATE.md`.

### Minimal port-based pattern (macOS)

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/sbin:/usr/bin:${PATH}"

# stop.command → use kill (SIGTERM); kill.command → use kill -9 (SIGKILL)
PORTS=(NNNN)   # project's fixed port(s)

stopped=0
for port in "${PORTS[@]}"; do
  pids="$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)"
  if [ -n "$pids" ]; then
    echo "Stopping process(es) on port $port: $pids"
    # shellcheck disable=SC2086
    kill $pids 2>/dev/null || true          # stop.command
    # kill -9 $pids 2>/dev/null || true     # kill.command
    stopped=1
  else
    echo "Nothing listening on port $port."
  fi
done
[ "$stopped" -eq 1 ] && echo "Stopped." || echo "Was not running."
```

## Dependency validation — install and start must check tools first

Every `install*` / `start*` / `launch*` / `dev*` script (`.sh`, `.command`, `.ps1`, `.bat`,
`.cmd`) MUST validate the toolchain it needs **before** building, installing packages, or
starting services. A double-clicked Finder `.command` that dies with a cryptic `command not
found` is a broken launcher.

**Rules:**

1. **Check every hard requirement up front** — `go`, `node`/`npm`, `python3`, `uv`, `docker`,
   `pwsh`, etc. Use `command -v` (Bash) / `Get-Command` (PowerShell). Soft/optional tools may
   warn and continue; hard requirements must stop the script.
2. **Fail loudly with the install command** — name the missing tool and how to install it on
   this OS (`brew install go`, `winget install GoLang.Go`, `brew install node`, …). Exit
   non-zero. Do not continue into a half-broken build.
3. **Prefer auto-install when the package manager is already present** — if `brew` (macOS) or
   `winget` (Windows) is on `PATH`, install the missing hard dependency and continue, then
   re-check. If the package manager itself is missing, print the one-liner to install *it*,
   then exit. Pattern: the Bash and PowerShell blocks below.
4. **Fix Finder / double-click PATH** — macOS `.command` / LaunchAgent shells often lack
   Homebrew. Prepend `/opt/homebrew/bin:/usr/local/bin` (and `$(brew --prefix)/bin` after a
   successful brew install) before any `command -v` checks.
5. **Mirror Bash ↔ PowerShell** — same checks and messages (adapted) in both members of a
   script pair, same commit.
6. **Start scripts check runtime tools too** — `install` alone is not enough. `start.*` must
   verify `node`/`npm`/`uv`/… (and optionally offer to run install / `npm install` /
   `uv sync` when `node_modules` / the venv is missing).

```bash
# Bash — required tool, auto-install via brew when possible
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if ! command -v go >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "Go not found — installing via Homebrew…"
    brew install go
    export PATH="$(brew --prefix)/bin:$PATH"
  fi
fi
command -v go >/dev/null 2>&1 || {
  echo "ERROR: Go is required (brew install go)"
  exit 1
}
```

```powershell
# PowerShell — required tool, auto-install via winget when possible
if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host 'Go not found — installing via winget…'
        winget install -e --id GoLang.Go --accept-package-agreements --accept-source-agreements
        $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                    [System.Environment]::GetEnvironmentVariable('Path', 'User')
    }
}
if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
    throw 'Go is required to build (winget install GoLang.Go)'
}
```

### Checklist add-on

- [ ] Hard toolchain deps checked at top of every install/start launcher
- [ ] Missing-tool message includes the OS install command; auto-install when brew/winget exists
- [ ] macOS scripts prepend Homebrew to `PATH` before checks
- [ ] Bash/PowerShell pair stays in sync

## Sibling-repo dependencies — install, start and update fetch them

When an app needs another of the owner's repos at runtime that is **not** a package of its
language (a local service run from its own checkout, a tool used in place), a friend who
clones only the app gets a silently broken feature. First choice: make it a package, vendor the
part used, or make the feature optional (`portable-project` skill). A **private** repo is never
fetchable by a friend — the feature must then work without it. Otherwise the app MUST fetch it
itself:

1. **List it** in a root `sibling-deps.txt`: `NAME  GIT_URL  [DIR_ENV_VAR]`, one per line.
   (A dependency that *is* a package — a library pulled via `[tool.uv.sources]` + `uv.lock` —
   stays in the package manager, not here.)
2. **Copy** [`scripts/sibling-deps.sh`](scripts/sibling-deps.sh) and
   [`scripts/sibling-deps.ps1`](scripts/sibling-deps.ps1) unchanged into the app's `scripts/`.
   They clone a missing repo beside the app (`../NAME`, or `$DIR_ENV_VAR`), look for an existing
   one in `$DIR_ENV_VAR` → `$AI_CODE_ROOT` → `~/Code` → `..`, fast-forward it when its tree is
   clean (at most once a day; always with `update`), then run its own `install.sh --start` /
   `install.ps1 -Start`. They only ever warn: a dependency that cannot be fetched never stops the app.
3. **Call it from every entry point**: `scripts/sibling-deps.sh start` in `start.*` (after the
   package sync), in `install.*` when it does not go through `start.*`, and
   `scripts/sibling-deps.sh update` in `update.*` **and** in the in-app updater (after the pull).
4. **The dependency ships an idempotent installer**: `install.sh [--start]` + `install.ps1
   [-Start]` at its root — packages, `.env` from `.env.example`, and with `--start` a background
   start unless its health URL already answers. Re-running it at every app start must be cheap.
5. **The app finds it where the script puts it**: its lookup must include the sibling folder
   (`../NAME`), not only `$AI_CODE_ROOT` / `~/Code` — a friend's bootstrap may clone elsewhere.
6. **Document it** in the README's requirements (the friend needs access to that repo too) and
   in `PROJECT_STATE.md` Key Commands.

## Fixed ports — required for every local web UI

A launcher or tray app (and bookmarks, embed widgets, dashboard cards, etc.) can only open an
app when the listen port is **stable and known ahead of time**. Random / OS-assigned /
auto-increment ports break that contract.

**Rules:**

1. Every process that serves a local HTTP/HTTPS (or WS) UI MUST bind a **fixed port** — a
   literal default like `3517`, never `0`, never "pick a free port", never silently bumping to
   the next free port (e.g. Vite without `--strictPort`).
2. Prefer `PORT="${PORT:-NNNN}"` (or the stack's equivalent) so `.env` can override without
   code edits, but **NNNN itself is fixed and committed** (in the launcher, `.env.example`,
   and/or a launcher app's manifest).
3. Document the port in **all** of: `.env.example` (`PORT=NNNN` or `# PORT=NNNN`),
   `.github/PROJECT_STATE.md` (Environment / Key Commands), and — when there is one — the
   launcher app's manifest.
4. **Unique across the code root**: before picking NNNN, scan siblings for collisions
   (`: "${AI_CODE_ROOT:=$HOME/Code}"; rg -n 'PORT=|WEB_PORT=|APP_PORT='
   "$AI_CODE_ROOT"/*/.env.example "$AI_CODE_ROOT"/*/start.sh 2>/dev/null`, plus any launcher
   manifests). Prefer the high 3xxx–8xxx band already used by siblings (e.g. 3077, 3517, 3847, 4390).
5. Framework gotchas — always pin:
   - Vite / Vite-based: `--port NNNN --strictPort` (fail if taken; do not auto-increment)
   - Next.js: `-p NNNN` / `PORT=NNNN`
   - Flask/FastAPI/uvicorn: `--port NNNN`
   - Docker Compose published ports: `"NNNN:containerPort"` with NNNN fixed on the host
6. If the port is already taken at launch, **fail loudly** with a message naming the port —
   do not hunt for another one. The user (or `stop` / `kill`) frees it.

Non-web tools (CLI-only, libraries, this template repo) skip the port rule.

## Kill-before-start — always free the port before binding it

A second launch attempt must never fail with "port already in use". The launcher (and every
npm/package script that starts a server) must kill any existing process holding the fixed port
**before** starting fresh.

**Why:** dev loops, tray restarts, and CI re-runs all assume a clean start. Leaving the
old process alive means the new one either crashes or silently binds a different port.

### Implementation patterns

**npm / package.json** — use `predev` and `prestart` hooks (they run automatically before `dev`
and `start`):

```json
"predev":   "lsof -ti:PORT | xargs kill -9 2>/dev/null; true",
"prestart": "lsof -ti:PORT | xargs kill -9 2>/dev/null; true"
```

Replace `PORT` with the project's fixed port literal. The `; true` prevents the hook from
failing when nothing is listening (exit 0 always).

**Shell launcher (`start.sh` / `start.command`)** — add at the top, before any `npm`/service
start:

```bash
# Free the port before starting
lsof -ti:PORT | xargs kill -9 2>/dev/null || true
```

**PowerShell launcher (`start.ps1`)** — equivalent:

```powershell
$proc = Get-NetTCPConnection -LocalPort PORT -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess
if ($proc) { Stop-Process -Id $proc -Force -ErrorAction SilentlyContinue }
```

**Docker Compose** — add `stop_grace_period: 0s` and handle restart in the compose file; the
launcher script still does the lsof kill for the **host-side** published port if needed.

### Checklist when adding or changing a launcher

- [ ] Fixed port chosen and documented (`.env.example`, `PROJECT_STATE.md`)
- [ ] Root triad present when long-running: `start.command` + `stop.command` + `kill.command`
- [ ] Kill-before-start added to every entry point that binds the port (`predev`, `prestart`,
      `start.sh`, `start.command`)
- [ ] Hard toolchain deps validated (and auto-installed via brew/winget when possible)
- [ ] Tested: start → stop → start again, and start → kill → start, without errors
- [ ] Vite / Next.js / framework pinned with `--strictPort` (fail loudly, do not increment)

## Launcher or tray apps — opting a project in

If projects are started from a launcher, dashboard or tray app that discovers them (a manifest
file at the project root, a conventional `start.*` name), follow that app's own skill, if one is
installed, for its manifest format, and keep the manifest's start / stop / kill commands and
fixed port or URL in step with the triad and the port rules above. Without such an app, the
root `start.*` / `stop.*` / `kill.*` scripts are the interface.

## Server deployment — always fully automated, never manual multi-step

- If the project deploys to a server, there MUST be one script or pipeline (`deploy.sh` /
  `deploy.ps1` / CI job) that calls **everything** required — build, push/upload, migrate,
  restart/reload services, invalidate caches — for **both frontend and backend** in the correct
  order, in a single invocation.
- Never leave the user to deploy the frontend, then separately SSH in or run backend steps by
  hand. If such manual steps currently exist, consolidate them into the deploy script as part of
  the next change that touches deployment.
- If different pieces deploy to different targets (e.g. static frontend host + backend server),
  the single script/pipeline still orchestrates all of them — the user runs one command.
- Document the deploy command and what it does in `.github/PROJECT_STATE.md` under Deployment.

## External exposure — always offer IP restriction and firewall rules

The moment an app is reachable beyond its own machine (LAN bind, router port-forward, reverse
proxy, cloud/VPS host, public URL), don't stop at "it listens": **propose access controls in the
same change**, as one question with a recommended default (below), then implement what the user
picks. Authentication stays mandatory either way — network rules are defense in depth, not a
login.

1. **Bind narrow by default.** `HOST=127.0.0.1` in the launcher and `.env.example`; `0.0.0.0` /
   a LAN address only when exposure is the point. Docker: publish `"127.0.0.1:NNNN:port"` unless
   it must be reachable, and remember Docker-published ports bypass `ufw` (filter in the
   `DOCKER-USER` chain or keep them on loopback behind the proxy).
2. **Prefer not opening a port at all** (recommended default): VPN / Tailscale / WireGuard, or an
   authenticating tunnel (Cloudflare Tunnel + Access). Only port-forward when that can't work.
3. **App-level IP allowlist**, off when unset: `ALLOWED_IPS` (comma-separated IPs/CIDRs) in
   `.env.example`, enforced in middleware (403 otherwise). Behind a proxy, read the client IP from
   `X-Forwarded-For` **only** when the peer is in `TRUSTED_PROXIES` — otherwise the header is
   spoofable and the allowlist is void.
4. **Ship the firewall rules, don't just mention them.** Write the rule for the actual target
   into a committed script or doc (`deploy/firewall.sh|.ps1` or `docs/exposure.md`), restricted to
   the allowed sources and the one port:
   - Linux: `ufw allow from <cidr> to any port NNNN proto tcp` (or nftables), default deny incoming
   - Windows: `New-NetFirewallRule -DisplayName <app> -Direction Inbound -Protocol TCP -LocalPort NNNN -RemoteAddress <cidr> -Action Allow`
   - macOS: `pf` anchor (the Application Firewall can't filter by source IP)
   - Reverse proxy: Caddy `remote_ip` matcher / nginx `allow <cidr>; deny all;`
   - Cloud: security group / VPC firewall with the source CIDRs, never `0.0.0.0/0` for admin ports
   - Router port-forward: set the source restriction when the gateway supports it
5. **Separate surfaces.** Admin UIs, metrics, debug and health-detail endpoints stay on loopback
   or the allowlist even when the public part is open; add TLS and rate limiting on anything public.
6. **Document the exposure** in `.github/PROJECT_STATE.md` (Deployment): what is reachable, from
   where, which rules enforce it, and how to revoke it. For a new public surface, run the
   `threat-modeling` skill.

## Secrets in launchers and deploy scripts

Never bake credentials into these scripts. Fetch them at runtime from the project's secret
manager, through the secrets skill for this code root if one is installed, or read documented
environment variables.
