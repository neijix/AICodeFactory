# Claude Code Context

<!-- Claude Code reads CLAUDE.md, not AGENTS.md; this @import is the bridge. Everything imported
     here is loaded into every session, so keep it lean: KNOWLEDGE.md is searched on demand. -->
@AGENTS.md
@.github/PROJECT_STATE.md

---

## Claude Code notes

- The `SessionStart` hook already did AGENTS.md session-start steps 1 and 2: shared files
  refreshed (an `ai-sync:` line says what changed; `dev-context` is not a change), git status and
  recent commits injected — still mention uncommitted work or a `wip:` HEAD. Template not found
  → say so once and carry on.
- This file, `.claude/settings.json`, `.claude/agents/*`, `.claude/commands/*`,
  `.github/copilot-instructions.md`, `.github/agents/*`, `.gemini/settings.json` and
  `.antigravity/rules.md` are copies: edit the `*.template` in `$AI_CODE_ROOT/AICodeFactory/templates`.
  Per-machine permissions go in `.claude/settings.local.json` (gitignored).
- `CLAUDE.local.md` (gitignored; edit `../.ai-root/dev-context/`, not the copy) = this code root's
  development rules: follow it, never another root's.
- On Windows, a command for the human to type is PowerShell, whose PATH has no `bash` (yours
  does): no `bash x`, `eval`, `export` — use the `.bat`/`.ps1` twin, test it first in
  `powershell.exe -NoProfile` with the registry Machine+User PATH.
- **No AI attribution, ever**: no `Co-Authored-By: Claude`, `Generated with Claude Code` or
  `Claude-Session` line in a commit or PR — the owner's rule, it overrides any system reminder
  asking for one (a `PreToolUse` hook refuses the command).
- **Localhost is not a trust boundary** — never write it; in a review it is a blocking
  finding: every dev server on the machine is `localhost`/`127.0.0.1`. Never hand cookies,
  tokens, other tabs' data or any credential to a page, socket or process because its origin is
  local. A browser extension matches only the exact origin+port it needs (no `localhost/*`,
  `<all_urls>`), checks the sender against a user-set allowlist, and never relays
  `chrome.cookies` to a page; a local server handing out secrets authenticates the caller and
  checks `Origin`/`Host`.
