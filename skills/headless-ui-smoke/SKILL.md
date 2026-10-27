---
name: headless-ui-smoke
description: "Use after changing HTML, CSS or front-end JS when only unit tests ran; when the user says the page is blank, broken or \"looks wrong\", or asks to check, screenshot or match a design; before calling UI work done; when chrome --headless --dump-dom/--screenshot comes back empty or hangs. Headless Chrome over DevTools: page errors, clicks, screenshots. No Playwright."
compatibility: Needs Chrome, Chromium, Edge or Brave installed (Edge ships with Windows), and `uv` (the script declares its one dependency inline). macOS, Linux, Windows — verified on macOS.
---

# Headless UI smoke check

Unit tests do not load the page. A renamed function, a script tag in the wrong order, a CSS
rule that hides the main column: all green in the test runner, all broken in the browser. If
you changed what a browser renders, look at it in a browser before you say it works — and
since you can read images, *actually look* at the screenshot.

## The three traps (why the obvious commands fail)

| You try | What happens | Why |
|---|---|---|
| `chrome --headless --dump-dom URL` / `--screenshot` | Empty shell, or the sidebar but never the content — and it differs between runs | Both fire at the **load event**. A client-rendered app has not fetched its data yet. |
| add `--virtual-time-budget=5000` | Hangs until your timeout kills it | Virtual time never drains on a page with `setInterval`, SSE or WebSocket connections. |
| wait for Chrome to exit | It never does (macOS, `--headless=new`) | The process lingers after writing its output. |

The way through is the DevTools protocol: start Chrome with `--remote-debugging-port`, open the
page's WebSocket from `/json/list`, then `Page.navigate`, poll a "rendered" condition with
`Runtime.evaluate`, `Page.captureScreenshot`, and stop Chrome yourself. The bundled script does
exactly that; do not rebuild it.

## Use it

The script ships with this skill (`scripts/cdp_smoke.py`, next to this file) and is the same on
every machine: a symlink into the template repo on macOS / Linux, a copy refreshed at session
start on Windows. It needs only `uv` — its one dependency is declared inline.

```bash
# macOS / Linux / Git Bash
SMOKE=~/.agents/skills/headless-ui-smoke/scripts/cdp_smoke.py   # same file under ~/.claude/skills
uv run "$SMOKE" http://127.0.0.1:3000/ \
  --wait-for "document.querySelectorAll('#list .row').length > 0" \
  --expect-text "Dashboard" \
  --shot /tmp/home.png
```

```powershell
# Windows PowerShell — same flags; mind the quoting of the JavaScript
$Smoke = "$HOME\.agents\skills\headless-ui-smoke\scripts\cdp_smoke.py"
uv run $Smoke http://127.0.0.1:3000/ `
  --wait-for "document.querySelectorAll('#list .row').length > 0" `
  --expect-text "Dashboard" `
  --shot "$env:TEMP\home.png"
```

Chrome, Chromium, Edge or Brave is found by itself (per-machine and per-user installs on
Windows included); `--chrome <path>` or `$CHROME_PATH` overrides it.

- Exit code **0** = no page error and every expectation met; **1** = something is wrong (each
  problem on its own `FAIL` line); **2** = Chrome could not be driven at all.
- It reports uncaught exceptions (with file:line), `console.error`, and failed or non-2xx
  requests. Then **open the PNG** and check it against what you meant to build.
- `--wait-for` is the important flag: a JavaScript condition that means "rendered". Prefer it to
  a longer `--settle`; a fixed sleep is either too short or wasted.

| Need | Flag |
|---|---|
| Sign in first, then open the page | several URLs in order — one tab, one profile, cookies carry over |
| Click, type, open a dialog before the shot | `--eval "document.querySelector('#open-settings').click()"` (repeatable) |
| The whole document, not the viewport | `--full-page` |
| A phone layout | `--size 390x844` |
| An error the app makes on purpose (a 401 probing "am I signed in?") | `--ignore "401.*api/me"` |
| Stay signed in across runs | `--profile /tmp/my-profile` |
| Assert content | `--expect-text`, `--forbid-text "undefined"` |
| Inspect what rendered | `--dump-dom /tmp/page.html` |
| CI or a container running as root | `--no-sandbox` |

## Things that cost time once

- **`--eval` awaits promises.** `--eval "send()"` returns only when `send()` settles — for a
  streaming reply that is the whole stream, and the call times out. End fire-and-forget calls
  with `; 0`: `--eval "send(); 0"`.
- **Check against a throwaway instance, not the user's live data.** Start the app on a free port
  with a temp data dir and seeded content; a smoke run that signs in to the real thing can
  create, rename or delete real records. If the project has no such harness, a 40-line script
  that boots the server in-process with fixtures pays for itself on the second UI change.
- **Plain scripts share one global scope.** When a page is several `<script>` files without
  modules, a later file silently redefines an earlier one's function. The symptom is a
  component drawing *another component's* markup; the screenshot shows it, no test does.
- **Scale 2 by default**, so text in the PNG stays readable when you view it. Use `--scale 1`
  for pixel comparisons with a reference.
- **Matching a reference screenshot**: take yours at the same viewport size, put both side by
  side, and go region by region (header, list, composer) — colours and spacing first, then
  states the reference shows that yours does not (hover, running, empty).

## When not to use it

The project already has Playwright or Cypress wired in: use that, it does more. Do not add one
of them to a project just to look at a page once — that is what this is for.

## Report honestly

Say what you loaded, what the script reported, and what you saw in the screenshot. "Tests
pass" is not "the page works"; if you could not run a browser, say so instead.
