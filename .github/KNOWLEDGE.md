# KNOWLEDGE BASE — AICodeFactory

Solved problems, workarounds, quirks and decisions with their why. **Searched with `grep`,
never loaded whole**: one `## <area>` per component or tool, entry titles that are the exact
error text or a greppable phrase. Update an existing entry rather than adding a near-duplicate.

---

## Decisions

### 📦 Agent Skills open standard (agentskills.io) — SKILL.md format

**Date researched**: 2026-07-18
**Why chosen**: one skill definition readable by Copilot CLI, Claude Code, Cursor 2.4+,
Antigravity, and Codex — replaces per-tool prompt files. Personal/private skills need no
registry: any folder with a conformant `SKILL.md` works.
**Alternative considered**: per-tool command files (`.claude/commands`, Gemini TOML) — kept
only for tool-specific verbs; shared procedures moved to skills.
**Official docs**: https://agentskills.io/
**Key patterns**: YAML frontmatter `name` + `description` (write the description as *trigger
conditions*, not a summary — it is what the agent matches against), optional `compatibility`;
body is free-form markdown. Supporting files sit next to SKILL.md in the folder.
**Gotchas**:
- Tools discover skills from different dirs; we symlink one source into all five
  (`~/.agents/skills/` is the open-standard one).
- A skill can be an **interface to a program repo** (dev-secrets → `~/Code/BitwardenAuto`);
  keep the implementation in the program, the *when/how to call it* in the skill.

### 📝 Making the template repo shareable: a private overlay repo, not a fork or a branch

**Date**: 2026-09-25
**Context**: the engine is generic but the repo carried personal material everywhere — home-lab
and work-overlay / home-lab skills (examples of overlay skills),
Bitwarden / MLX_Local / Switchboard wiring in `AGENTS.md.template` and `install-global.*`, the
`## Taste` rules, and employer-host / `192.168.x.x` strings in ~50 historical diffs. The goal:
publish the engine, keep the personal parts private, and still have them follow the owner to
every machine.
**Options weighed**: (a) private fork merging the public upstream — every edit to
`AGENTS.md.template` conflicts, and one `git push` to the wrong remote leaks; (b) private
submodule inside the public repo — broken submodule pointer for strangers, painful on Windows
without Developer Mode, against the "plain copies, no links" rule; (c) public/private branches —
worst of both. (d) **overlay repo**: separation by *file*, not by commit.
**Decision**: (d). The engine resolves every manifest entry through `_tpl` (overlay file of the
same name wins), appends `<src>.template.append` fragments at render time, merges an optional
`overlay-manifest.txt` by destination, installs skills from both dirs (overlay first, so a
personal `dev-secrets` shadows the generic one), and `--pull` fast-forwards both repos.
Discovery: `$AI_TEMPLATE_OVERLAY_DIR` → `~/.ai-template-overlay-dir` → sibling
`<repo>-private`; `install-global --overlay <dir>` records the first two. A configured overlay
that is missing prints one `ai-sync:` line and the run continues (session-start must never break).
**Gotchas met while building it**:
- Bash 3.2 has no associative arrays or namerefs: `_merge_entry` replaces-by-key with `eval` on a
  fixed array name. Keep the array names literal.
- The overlay must never ship `sync-ai-templates.sh`: the hook's last-resort candidate is "any
  sibling holding the engine + `templates-manifest.txt`", so an overlay carrying both would be
  taken for the base.
- Pointers are compared against the *rendered* content (a scratch file), not the raw template —
  otherwise a `.append` fragment makes every run report `[update]`.
- Tests: `${TMPDIR}` on macOS ends with `/`, so a sandbox path built as `"$S/overlay"` reads
  `.../T//ai-template-tests.X/overlay` while the engine canonicalizes with `cd && pwd`. Compare
  origin markers against a canonicalized path. Also case 9b leaves `tech-research` owned by a
  foreign repo — later cases must not assert on that skill.
- Review caught four real ones: tests had to opt out of overlay discovery (`AI_TEMPLATE_OVERLAY_DIR=none`,
  otherwise a real overlay on the machine fails case 1); the obsolete guard must compare against
  the *rendered* reference (fragment included); a dest-keyed manifest entry must evict the same
  destination from the other map (pointer vs living doc) or both loops fight over the file every
  run; and the PowerShell pointer path had to go back to bytes (`ReadAllBytes`) — `ReadAllText`
  strips a BOM and the two engines would ping-pong commits.
- Writing a bash file that itself contains `<<'PY'` heredocs through a `python3 - <<'PY'` heredoc
  terminates the outer heredoc early; use a distinct delimiter (`PYEOF`).
**Next steps** (not done yet): move the personal material into the overlay, generalize
`install-global.*` (Bitwarden/MLX registration should come from the overlay), create the public
repo from a clean export rather than rewriting this history, rename this repo to the overlay.

### 📝 Renaming the repo was a naming decision, not a migration — because of one lookup change

**Date**: 2026-09-08
**Context**: `CopilotInstructionTemplate` was misleading on two counts (Copilot stopped being
the master when `AGENTS.md` took over, and this is a sync engine, not a folder of
instructions), but 19 projects looked the template up **by name** in their SessionStart hook,
so a rename meant 19 silently broken hooks.
**Decision**: make the lookup content-based first (`sync-ai-templates.sh` +
`templates-manifest.txt` in any sibling), *then* rename to `AICodeFactory`. Order matters:
the projects that already had the new hook kept working through the rename, and
`update-projects.sh --yes` plus `refresh-agents-sections.py --all` only had to fix the *text*
of the name afterwards.
**Full checklist for a future rename**: folder, `gh repo rename` (GitHub redirects the old URL
and updates the local remote), every in-repo reference, `~/.claude/CLAUDE.md`, the session
memory files, global skill symlinks (a `--skills` pass relinks them: dangling links count as
ours), `bin/aicf update --yes`, then `refresh-agents-sections.py --all --commit`.
**Lessons Learned**: when a thing is looked up by name in many places, making the lookup
structural is the prerequisite for ever renaming it. Do that first, then rename.

### 📝 Dropped the downstream template feature (single-consumer filter had no purpose)

**Date**: 2026-09-10
**Context**: `derive-downstream.py` + `downstreams/*.ini` published a personal-content-free
copy of this repo to `~/WorkCode/<filtered-factory>`, gated by `<!-- personal:start -->`
markers, a `[forbid]` regex backstop, and `.upstream-managed` sha256 tracking. It was built
so a second consumer (a work machine or a teammate) could clone a filtered copy.
**Decision**: removed the whole apparatus — script, ini, tests, markers, doc sections, the
downstream repo. The owner is the only consumer of their own docs, so the filter had no one
to protect. Kept: the two roots (personal + work) for `update-projects.sh` scope
isolation; work projects refresh through their per-session SessionStart hook.
**Superseded 2026-09-16**: the `$HOME/Code/AICodeFactory` fallback named here does **not** work on
the Windows boxes, where the roots are on `F:` and `$HOME` is on `C:` — see
"`ai-sync: AICodeFactory not found` on a second root".
**Lessons Learned**: a filter is dead weight without a downstream consumer. Every marker in
the source, every `[forbid]` regex, every entry in `.upstream-managed` was maintenance cost
paid for nothing. Delete the feature, not the personal content — this repo *is* the personal
one, so unwrapping the markers preserved every wrapped sentence in place.

### 📝 Pivot: symlinked pointer files → plain copies + session-start pull

**Date**: 2026-09-08
**Context**: pointer files (`CLAUDE.md`, `.claude/settings.json`, …) were relative symlinks
into this repo. On the Windows machine that broke three ways: creating symlinks needs
Developer Mode/admin (the `.ps1` silently fell back to stale copies), a checkout with
`core.symlinks=false` turns each link into a **text file containing the link path**, and
server-side clones (Copilot coding agent) never see the target at all. The template repo's
own self-symlinks (`CLAUDE.md -> CLAUDE.md.template`) had the same problem when cloned on PC.
**Decision**: no symlinks in anything a project receives. Pointer files are plain copies;
freshness comes from **each project pulling from the template at session start**:
`.claude/settings.json.template` carries a Claude Code `SessionStart` hook (POSIX one-liner that
resolves the template dir — see "`ai-sync: AICodeFactory not found` on a second root" for the
current candidate order — then runs
`bash sync-ai-templates.sh <project> --quiet --commit --pull --skills`), and
`AGENTS.md.template` / the global Copilot instruction / `.antigravity/rules.md` tell every
other agent to run the same command as step 1. The engine copies pointers that differ,
migrates old symlinks (including the Windows text-file leftovers), removes obsolete files
(guarded: `.mcp.json` only while byte-identical to `engine/obsolete/mcp.json`), and commits **only
those paths**. `--pull` = background `git pull --ff-only` of this repo, once per 24 h, only
when its tree is clean. Skills stay symlinked on macOS/Linux (live edits) and are copies on
Windows, refreshed by `--skills`; `install-global.*` iterates `vscode-global/skills/*`
instead of a hand-maintained list (4 skills had been missing from 3 tool dirs).
**Alternatives Considered**: keep symlinks + require Developer Mode — rejected, still breaks
`core.symlinks=false` checkouts and server-side clones. VS Code `folderOpen` task in
`.vscode/tasks.json` — rejected, per-project clutter and collides with real task files, and
only fires in VS Code. Git `post-checkout` hook — rejected, fires on checkout, not on "open".
Auto-bootstrapping un-bootstrapped siblings in bulk runs — rejected (`qbo-app-pages` is a
GitHub Pages site that must stay untouched); bulk = refresh only, bootstrap is explicit.
Skipping dirty siblings in bulk runs — no longer needed since commits are paths-only.
**Outcome**: 19 siblings migrated (`typechange` commits), this repo's self-symlinks replaced
by copies, `tui.json.template` (unused) removed, `.mcp.json` per project retired in favor of
the user-scope MCP registration (also kills Claude Code's "approve project MCP servers"
prompt on every new project).

### 📝 AGENTS.md as master instruction file; copilot-instructions.md demoted to pointer

**Date**: 2026-07-18
**Context**: every AI tool grew native support for `AGENTS.md`; maintaining a filled
`.github/copilot-instructions.md` master duplicated content per tool.
**Decision**: `AGENTS.md` (owned per project) is the single source of truth; every other file
is either a thin pointer or a symlinked wrapper (`CLAUDE.md` @imports it). Big generic
procedures were extracted into shared skills so AGENTS.md stays slim.
**Alternatives Considered**: keeping copilot-instructions.md as master (legacy layout) —
rejected, Copilot reads AGENTS.md natively now.
**Outcome**: template restructured; sibling rollout via `./update-projects.sh` pending.

### 📝 Self-bootstrap (dogfooding) — the template repo follows its own rules

**Date**: 2026-07-18
**Context**: the repo that enforces AGENTS.md everywhere didn't have one itself; sessions here
relied on a hand-written CLAUDE.md.
**Decision**: `sync_ai_templates` gained a **self mode**: when the target *is* the template
repo, pointer symlinks target the local `*.template` directly (`CLAUDE.md ->
CLAUDE.md.template`) instead of routing through the parent dir. The old hand-written
CLAUDE.md content moved into AGENTS.md "Project-specific notes".
**Alternatives Considered**: hand-rolling the repo's own docs outside the engine — rejected;
the manifest must stay the only file map.
**Outcome**: repo bootstrapped; `update-projects.sh` still skips it in bulk runs (self-refresh
is explicit: `./sync-ai-templates.sh .`).

### 📝 Lean instruction context: KNOWLEDGE.md searched on demand, AGENTS.md cut to invariants and taste

**Date**: 2026-09-16
**Context**: every session in every project loaded ~9,200 words of instructions before the first
task (global `CLAUDE.md` 1,418 + this repo's `CLAUDE.md` 413 + `AGENTS.md` 2,239 +
`PROJECT_STATE.md` 1,360 + `KNOWLEDGE.md` 3,810, dated history included). Prompted by DHH on
Lex Fridman #501: the Opus 5 system prompt reportedly shrank ~80% because over-prescriptive
instructions degrade current models; his own `AGENTS.md` mostly carries taste rules the agent
keeps getting wrong.
**Decision**:
- `CLAUDE.md.template` imports `AGENTS.md` + `PROJECT_STATE.md` only; `KNOWLEDGE.md` is grepped
  for the area at hand (said in the AGENTS.md session start and the Copilot/Antigravity pointers).
- `AGENTS.md.template` 1,332 → ~760 words: dropped what models already do unprompted (naming
  style, "handle errors gracefully", JSON hygiene), and the Project structure / Key commands
  sections that duplicated `PROJECT_STATE.md`. Generic section *headings* kept byte-identical so
  `refresh-agents-sections.py` could still propagate the bodies.
- New `## Taste` section fed by a rule in "Living documents" and in `/learn`: a correction made
  twice becomes a one-line rule.
- Global `~/.claude/CLAUDE.md` Bitwarden/SSH section (~700 words) moved into the `dev-secrets`
  skill, leaving a short pointer.
**Alternatives Considered**: moving `PROJECT_STATE.md` out of the imports too — rejected for
now, it is the one doc every task needs. Renaming or merging generic sections — rejected, the
refresh script keys on exact headings.
**Lessons Learned**: instruction files are a per-session cost paid in every project; an entry
earns its place only if agents get something wrong without it.

### 📝 Context diet II: ~150 lines per session, retired AGENTS.md sections (2026-10-11)

**Context**: a fresh project loaded ~300 instruction lines per session (`CLAUDE.md` 30 +
`AGENTS.md` 117 + `PROJECT_STATE.md` index up to 150); the work overlay's guidelines put the
useful ceiling near 200, and every line competes with the task.
**Decision**: `AGENTS.md.template` 117 → 78 lines, `PROJECT_STATE.md.template` index ≤ ~80 lines /
6 KB (features and limitations move to `docs/state/`), `CLAUDE.md.template` 30 → 23, budget
warning 12 → 8 KB. Four sections retired — Bootstrap mode (one line in Session start), On-demand
skills and Delegation (skills and subagents are found by their description; listing them is
noise), Living documents (folded into the Post-task checklist). `refresh-agents-sections.py`
gained `RETIRED_SECTIONS`: a retired section is removed only where its text still matches a past
template version, else reported KEPT. Area-only rules go to `.claude/rules/<topic>.md` with
`paths:` globs, loaded only when Claude touches matching files.
**Why not delete headings outright**: projects would keep their old copy forever; why not rename:
the refresh script keys on exact headings (a rename reports `MISSING` everywhere).

### 📝 What was taken from a corporate Claude Code plugin marketplace, and what was not

**Date**: 2026-09-29
**Context**: reviewed a work plugin marketplace (~260 skills, a CI that validates every plugin)
for ideas worth bringing here. Nearly all skills were domain-specific; the value was in its CI.
**Taken** (vendor mentions and the vendor-only regex branches removed):
- `tests/lint-skills.py` + `tests/skill-security-patterns.json`: its 28 regex security rules
  (prompt injection, `curl | sh`, `iex (iwr …)`, invisible Unicode, cleartext-secret phrasing),
  run over skill markdown and the hook commands, plus our own invariants (SKILL.md `name` =
  folder, LF only, no machine path). High/critical fails, the rest warns; `security-allow: <id>
  <reason>` on the line or the line above suppresses a reviewed hit. Its "non-approved domain"
  URL rule was dropped — a public, generic repo links everywhere.
- `.gitattributes` (`* text=auto eol=lf`): `arr-library/SKILL.md` had been committed CRLF from
  Windows. A CRLF template is copied byte-for-byte into every project, and a CRLF `.sh` breaks bash.
  Fixing an already-CRLF worktree file: `git add --renormalize .` fixes the index only, and
  `git checkout -- <file>` is a no-op when git thinks it is clean — rewrite it (`perl -pi -e
  's/\r\n/\n/'`).
- `permissions.deny: [EnterWorktree, ExitWorktree]` in the settings template: enforces the
  no-worktree rule and drops ~2.4k tokens of tool schema from every request.
- `threat-modeling` skill (STRIDE/OWASP → `THREAT-MODEL.md`), copied as-is minus its license line.
- `uv run x.py`, never a bare `python3 x.py`, in skills (lint warns): on Windows `python3` is
  often the Store stub; uv brings the interpreter.
**Not taken**: a desktop-notification hook (contradicts "D3SKHAND owns its Notification hook");
its `bash-on-windows` skill — the one rule that matters is below; `/learn`, `skill-creator` and
the GitLab commit commands (ours already exist, or branch-per-change contradicts the checkpoint
policy).
**Git Bash on Windows**: `2>nul` creates a literal file named `nul` — write `2>/dev/null`. Use
`command -v x`, not `which x`.

### The owner's tools through the shell — no MCP registration (pivot)

Endpoint security on managed machines flags MCP servers, so the owner removed every MCP server
from their own apps. `mlx-local` (MLX_Local) and `d3skwebscout` (D3SKWEBSCOUT) are now
command-line clients run through the agent's shell tool (`mlx-local offload --task-type …`,
`d3skwebscout search|fetch|status`), each behind its skill (`mlx-offload`, `web-scout`).
Discarded: the user-scope `mlx-local` MCP registration in every harness and the hand-registered
`d3skwebscout` one. `install-global.*` now removes stale entries of exactly those two names from
`~/.claude.json` (top level and `projects.*.mcpServers`), `~/.cursor/mcp.json`, the Gemini /
Antigravity configs, `~/.copilot/mcp-config.json` and VS Code's `mcp.json`, writing
`<file>.bak` first and never rewriting a file that has none (idempotent). Later the owner
extended it to **no MCP server at all, third-party included**: the `bitwarden` server
(`vscode-global/mcp.json`, `copilot-cli-mcp-config.json`) is no longer installed and joins the
stale list; agents reach the vault through `bw-auto` in their shell. The availability gate for MLX is now `mlx-local health` answering,
not "the `offload` tool is in the tool list". `engine/obsolete/mcp.json` stays only as the reference
that lets the sync delete an untouched old per-project `.mcp.json`.
- Agent shells may not have `~/.local/bin` on `PATH`: the skills give the by-path fallbacks
  (`~/.local/bin/mlx-local`, `uv --directory "$AI_CODE_ROOT/<repo>" run <cmd>`).
- `~/.claude/CLAUDE.md` (global Claude instructions) is **not** produced by this repo — it is
  hand-maintained on each machine. Root-specific rules (personal MLX and secrets, work
  secrets) live in each code root's `.ai-root/dev-context/` pack, not in that global file.

### 📝 Every session starts from the latest template: synchronous `--pull` + `--agents` in the hook (pivot)

**Date**: 2026-10-09
**Context**: `--pull` used to be a background `git pull --ff-only` at most once per 24 h, so a
session ran on yesterday's templates and only the *next* session saw a template edit; and
generic `AGENTS.md` sections only moved with a manual `refresh-agents-sections.py --all
--commit`. The owner asked that every project open take the latest version.
**Decision**: the hook runs `--quiet --commit --pull --agents --skills`.
- `--pull` runs **first and synchronously**, bounded by `AI_SYNC_PULL_WAIT` (default 10 s): the
  pull starts in the background and the engine polls it, so an offline machine still starts at
  once and a slow pull finishes on its own for the next run. A dirty template tree is never
  pulled. When `HEAD` moved, the engine `exec`s itself without `--pull` — the copy already in
  memory is the *old* engine and must not apply the new templates.
- `--agents` reverses the earlier "never wire the AGENTS refresh into the hook" rule, made safe
  by three guards in `refresh-agents-sections.py`: shared projects skipped, an `AGENTS.md` with
  uncommitted edits skipped under `--commit`, nothing during a merge/rebase; customized sections
  were already never touched (3-way against the template's history).
- `update-projects --clone --pull` covers repos never opened on this machine: it clones the
  owner's non-archived, non-empty GitHub repos missing locally (matched by folder name *and*
  origin slug, `*-private-archive` skipped) and fast-forwards every sibling with an upstream
  (dirty or diverged ones are reported, never touched).
**Alternatives Considered**: a pull on every run without a time bound — rejected, an offline
or captive-portal network would hang Claude Code's startup. Pulling but not re-executing —
rejected, the new templates would be applied by the old engine's logic.

### Claude Code profiles: AICodeFactory provisions, AgentCliBridge launches (2026-10-15)

Personal and work Claude Code side by side = one `CLAUDE_CONFIG_DIR` per code root (separate
login, keychain entry, settings, memory). The declaration lives in the root's `.ai-root`
(`claude-profile.json`), so the work gateway URL stays in the work root's repo, never in this
public one. `install-global` provisions the dir and writes `~/.claude-profiles`, the one contract
every launcher reads: the terminal through the managed `claude` function, apps through
AgentCliBridge (it spawns `claude` itself, so the shell function never runs there).

## Sync engine

### 📝 Session-start hook now finds the template by content, not only by name

**Date**: 2026-09-08
**Context**: the hook looked for `../AICodeFactory` then
`$HOME/Code/AICodeFactory`. Renaming or moving the template repo would leave 19
projects printing "not found" at every session start — the exact kind of silent breakage that
makes a rename scary.
**Solution**: the `for` list is `"${AI_TEMPLATE_DIR:-}"` (explicit override first), the
name-based paths, then the glob `"$P"/../*/` — accepting the first candidate that holds **both**
`sync-ai-templates.sh` and `templates-manifest.txt`. An unmatched glob stays literal in POSIX
`sh`, and the `-f` tests reject it, so no nullglob is needed. Because each family of projects
lives next to exactly one template repo, the glob can never pick the wrong one.
**Extended 2026-09-16**: two candidates were inserted before the glob —
`../../Code/AICodeFactory` (a project under a second root) and `$(cat ~/.ai-template-dir)`. See
"`ai-sync: AICodeFactory not found` on a second root" for the current, complete order.
**Lessons Learned**: identify a dependency by a property it must have, not by the name someone
chose for it — that is what made renaming this repo a cheap decision instead of a migration.

### 📝 `ai-sync: AICodeFactory not found` on a second root — `$HOME/Code` is macOS-shaped

**Date**: 2026-09-16
**Problem**: a project under `WorkCode/<name>` on the Windows boxes hits **every** hook
fallback and prints `ai-sync: AICodeFactory not found ... shared AI files not refreshed` at every
session start. `README.md` had claimed work projects find the template via the
`~/Code/AICodeFactory` fallback — true on macOS, false on Windows.
**Root Cause**: `$HOME` on Windows is `C:\Users\<user>`, a **different volume** from the repos on
`F:`. So `$HOME/Code/AICodeFactory` → `C:\Users\<user>\Code\AICodeFactory`, which does not exist;
`../AICodeFactory` → `F:\WorkCode\AICodeFactory`, also absent; and the sibling glob `$P/../*/`
cannot cross from one root to the other. The same applies to
`install-global.ps1`'s `%USERPROFILE%\Code\MLX_Local` and to every skill that hardcoded
`~/Code/<sibling>`.
**Solution**: prefer **relative** candidates over `$HOME`, plus a machine-local marker.
The hook now walks: `$AI_TEMPLATE_DIR` → `../AICodeFactory` → `../../Code/AICodeFactory` →
`~/Code/AICodeFactory` (kept for back-compat) → `$(cat ~/.ai-template-dir)` → content-based
sibling glob. Candidate 3 is the key one: from `<root>/WorkCode/proj` it resolves
`<root>/Code/AICodeFactory` on *any* machine, because it keys off the layout rather than `$HOME` —
one `stat`, no glob. `install-global.*` writes `~/.ai-template-dir` (this repo's absolute path) and
upserts `AI_TEMPLATE_DIR` + `AI_CODE_ROOT` into `~/.claude/settings.json` `env`; both live outside
every repo, so they never travel through git. Skills now say `$AI_CODE_ROOT/BitwardenAuto`, with
`: "${AI_CODE_ROOT:=$HOME/Code}"` starting each pasteable snippet. Covered by test cases 10b/10c.
**Alternatives Considered**: a content-based two-level glob `$P/../../*/*/` — works and is fast
(34 candidates, 11 ms on `F:`), but on macOS it walks `~/Documents` etc. and can trip TCC prompts
inside a startup hook, so it was dropped in favour of the named relative candidate + the marker.
Setting `AI_TEMPLATE_DIR` by hand on each machine — rejected as a manual step to redo per machine,
though it remains the documented escape hatch.
**Gotcha**: an empty marker file collapses to `[ -f "/sync-ai-templates.sh" ]`, which is simply
false — no special-casing needed. And note the hook passes a path still containing `../..`; the
engine normalizes it via its own `cd … && pwd`, so it is only cosmetic. The two roots are
**`Code`** (personal) and a **work root** (e.g. `WorkCode`). A dropped 2026-09-10 name
is not a folder on disk. Candidate 3 does
not depend on the second root's name.

### 📝 Dual-machine: stash + ff-only + stash pop — JSON keys merge, table rows conflict

**Date**: 2026-09-16
**Problem**: Windows had uncommitted portability work; macOS had already pushed the AgentDesk
`Notification` hook and the Odysseus doc drop. Same files, different hunks.
**What git did**: `stash` → `pull --ff-only` → `stash pop`. Different JSON keys in
`.claude/settings.json.template` (SessionStart command vs new `Notification` block) auto-merged.
`tests/run-tests.sh` (cases 10b/10c vs appended case 14) and `launch-and-deploy` (`$AI_CODE_ROOT`
vs one-line Odysseus drop) auto-merged too. Only `.github/PROJECT_STATE.md` conflicted: both
sides inserted a row after the commit-guard line in the Active Features table.
**Resolution**: keep both rows (AgentDesk + portability), count bash cases as 16 (13 + 10b + 10c
+ Notification). Point AgentDesk at `$AI_CODE_ROOT/AgentDesk`, not `~/Code/AgentDesk`.
**Do not**: `git checkout --theirs` / `--ours` on the overlapping files — that would drop either
the Windows discovery one-liner or the Notification hook.

### 📝 Hook-safe partial commit: `git status --porcelain -- <paths>` + `git commit -- <paths>`

**Date**: 2026-09-08
**Problem**: the session-start sync must commit the files it refreshed without sweeping in
whatever the user has staged or modified elsewhere in the project — and without failing when
one of "its" paths is an untracked file it just deleted.
**Root Cause**: `git add -A` + `git commit` commits everything; `git add -- <path>` on a
pathspec that matches nothing (deleted untracked file) is fatal.
**Solution**: collect the real changed subset with
`git status --porcelain --untracked-files=all -- "${SYNC_CHANGED[@]}"` (a pathspec matching
nothing is fine there), then `git add -A -- <subset>` and
`git commit -q -m "…" -- <subset>` — the pathspec form of `commit` records HEAD + those paths
only, leaving other staged changes staged. Guard with `MERGE_HEAD` / `rebase-merge` /
`rebase-apply` in `--absolute-git-dir` and refuse. Run git with `-C "$(git rev-parse
--show-toplevel)"` because porcelain paths are root-relative.
**Lessons Learned**: a sync that restores a file to exactly its HEAD content produces *no*
commit (nothing differs) — tests that "hand-edit then sync" must commit the drift first.

### 📝 `basename "."` leaked "." into [PROJECT_NAME] fills

**Date**: 2026-07-18
**Problem**: running the engine as `./sync-ai-templates.sh .` created living docs titled
"PROJECT STATE — ." because `project_name="$(basename "$target")"` doesn't resolve `.`.
**Root Cause**: basename of a relative path is taken literally; `.` and trailing slashes never
hit the sed fill correctly.
**Solution**: canonicalize first — `project_name="$(basename "$(cd "$target" && pwd)")"` when
the dir exists (mirrored with `Resolve-Path` in the .ps1).
**Lessons Learned**: any script that derives names from a user-supplied path must resolve the
path before `basename`/`Split-Path -Leaf`.

### 📝 `new-project.sh` on an empty folder: the nested bootstrap asks questions, yet reports success

**Date**: 2026-09-13
**Problem**: `./new-project.sh AgentDesk` ended with "AI bootstrap complete", but `AGENTS.md`,
`.github/PROJECT_STATE.md` and `.github/KNOWLEDGE.md` still carried `<!-- BOOTSTRAP_PENDING -->`
and every placeholder.
**Root Cause**: with no source code to scan, the nested `claude -p "/bootstrap-ai"` follows
rule 8 and stops to ask for the project's purpose and stack — printed to stdout, unanswerable in
`-p` mode — and still exits 0, so the script reports success.
**Workaround**: after creating an empty project, fill the living docs from the design decisions
(or run `/bootstrap-ai` once code exists) and check with `grep -rl BOOTSTRAP_PENDING <project>`.
**Possible fix (not done)**: have `new-project.sh|.ps1` re-run the needs-bootstrap check after the
nested call and print "bootstrap still pending — open the project and run /bootstrap-ai"
instead of "complete".

### 📝 `new-project.sh` can't create a project under a work root

**Date**: 2026-10-16
**Problem**: the script always creates `<AICodeFactory's parent>/<name>`, i.e. the personal root;
a name like `../WorkCode/x` yields a path holding both `Code` and `WorkCode` components,
which root detection (registry, remote, dev-context) must not be trusted with.
**Workaround**: run its steps by hand with the resolved work-root path — `mkdir` + `git init`,
`.gitignore`, then in bash `source ./sync-ai-templates.sh`, `sync_ai_templates "$T" --private-layer`,
check `_project_mode "$T"` is `private`, `ai_context_sync "$T" --no-fetch`, `git add -A`, check
`_tracked_layer_paths "$T"` is empty, commit. Done this way for a work-root project.
**Possible fix (not done)**: a `--root <dir>` option on `new-project.sh|.ps1`.

### 📝 Three distinct sync semantics — know which file class you're editing

**Setting**: `templates-manifest.txt` sections
**Behavior**:
- `[POINTERS]` → plain copies; a template edit reaches every project at its **next session
  start** (hook / agent step), or immediately with `bin/aicf update --yes`.
- `[LIVING_DOCS]` → copied once at bootstrap; template edit affects only *future* bootstraps.
- Skills (`skills/`) → symlinked into global tool dirs on macOS/Linux (edits
  live immediately), copied on Windows (refreshed at session start). Adding a folder is
  enough — no install list.
- `[OBSOLETE]` entries with `|reference.template` are only removed while byte-identical to
  that reference; a customized file is kept and reported as `[keep]`.
**Why this matters**: editing the wrong class gives silent no-ops (living doc template) or
surprising machine-wide changes (skills). This repo's own `CLAUDE.md` etc. are pointer
*copies* too — edit the `.template`, then `./sync-ai-templates.sh .`.

## Claude Code hooks & harness

### 📝 Agents skipped checkpoint commits — Claude Code's built-in "commit only when asked" won

**Date**: 2026-09-16
**Problem**: `AGENTS.md` says to commit at the end of every response that modifies files, yet
agents routinely finished without committing.
**Root Cause**: Claude Code's own system prompt says "commit or push only when the user asks; if
on the default branch, branch first". The project rule ("overrides any global preference") did
not name that built-in default, and every repo here works on the default branch, so the agent
fell back to not committing.
**Solution**: the checklist now says "don't ask and don't branch first — this overrides any
built-in or global default", and `~/.claude/CLAUDE.md` carries the same rule for every repo.
A detour through "ask before committing" (`1faabb5`) was reverted: the owner wants the commit,
not the question.

### 📝 `Co-Authored-By: Claude …` trailer in commits despite the owner's rule

**Date**: 2026-10-19
**Problem**: commits carried `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
**Root Cause**: Claude Code's built-in git instructions (and harness system reminders) add the
trailer by default; a prose rule loses to them.
**Solution**: three layers in the templates — `"attribution": {"commit": "", "pr": ""}` plus
the legacy `"includeCoAuthoredBy": false` in `.claude/settings.json.template` (the harness stops
asking for it); a `PreToolUse` Bash hook that exits 2 when a `git … commit` / `gh pr create|edit`
command holds a Claude/Anthropic co-author, `Generated with Claude` or `Claude-Session` line;
and one line in `CLAUDE.md.template` / `AGENTS.md.template` for other agents.
**Gotcha**: the hook also fires on *your own* Bash command when it merely contains those strings
alongside `git commit` (tests, a commit message describing the feature): put test inputs in a
file, and phrase such commit messages without the literal trailer.

### 📝 Commit guard: a Stop hook that only flags what *this turn* changed

**Date**: 2026-09-16
**Problem**: agents ended responses without the checkpoint commit. A naive Stop hook
("working tree dirty → block") nags forever in repos that carry unrelated uncommitted work, and
re-blocks after the agent explains itself.
**Solution** (two POSIX one-liners in `.claude/settings.json.template`): `UserPromptSubmit`
touches `<git-dir>/ai-turn-start`; `Stop` lists `git diff --name-only --relative HEAD` +
untracked files, keeps those `-nt` (newer than) the marker, and exits 2 with the list on stderr —
Claude Code feeds it back and the agent commits. `stop_hook_active: true` in the input means the
agent already got one nudge this stop: exit 0, never loop.
**Gotchas**: `-nt` has one-second resolution under macOS `sh` (bash 3.2), so the test sets
mtimes with `touch -t` instead of sleeping. `[ file -nt missing ]` is *true* — hence the explicit
`[ -f "$M" ]` guard. Deleted files are not flagged (no mtime). Files the user edits by hand during
a turn are flagged too; the message tells the agent to leave them and say so.

### 📝 Claude Code hook one-liner must be POSIX `sh`, and SessionStart stdout is context

**Date**: 2026-09-08
**Problem**: needed one hook command that works on macOS, Linux and Windows without
Developer Mode, and doesn't spam the model.
**Root Cause / facts** (from the hooks reference): shell-form command hooks run via `sh -c` on
macOS/Linux and **Git Bash on Windows** (PowerShell only when Git Bash is absent — and Claude
Code needs Git Bash anyway). For `SessionStart` (also `UserPromptSubmit`), plain-text stdout
is **added to the model's context**; other events only log it. `${CLAUDE_PROJECT_DIR}` is
exported into the hook environment. Project-level `.claude/settings.json` hooks run without a
per-hook approval dialog.
**Solution**: a bash-free POSIX one-liner in `.claude/settings.json.template` that `exec`s
`bash sync-ai-templates.sh` with `--quiet` (prints only when something changed) and
`"timeout": 60`; the engine always exits 0 so a missing template never breaks startup. The
`--pull` runs `nohup git pull … &` so an offline machine never blocks the session.

### 📝 D3SKHAND owns its Notification hook — the template no longer ships one

**Decision** (2026-09-24): the "waiting for you" spool hook moved out of
`.claude/settings.json.template` into D3SKHAND itself, which upserts one user-scope entry in
`~/.claude/settings.json` at every node start (`agentdesk/node/claude_hook.py`, marker
`: d3skhand-notify;`). **Why**: a product other people install cannot depend on the owner's
template repo, and user scope covers every project, bootstrapped or not. A machine whose node
has not restarted on the new D3SKHAND yet shows no waiting sessions until it does.

### Auto-compact: context meter at 100% (455k / 200k) but nothing compacts (2026-09-29)

On a 1M-window model, Claude Code only auto-compacts near 1M, so a chat drifts to 400k+ tokens:
every turn re-reads it, and recall degrades. `CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000` (set in the
pointer `.claude/settings.json` `env`) caps the window auto-compact works against; it applies to
`claude -p` too (D3SKHAND). Chosen over the `autoCompactWindow` settings key because the binary
shows the env var "takes precedence" and it is read from `process.env` for sure; `/autocompact`
changes the key, not the env var. The `SessionStart` hook with matcher `compact` prints the last
commits and uncommitted files right after a summary — with the commit-guard `Stop` hook the repo
is always checkpointed, so it is a better resume source than the summary. Raise the value, or
set `DISABLE_AUTO_COMPACT=1` in `.claude/settings.local.json`, per project if needed.

## Skills & templates

### 📝 Per-folder skill switch-off for Claude Code: `skillOverrides` in `.claude/settings.local.json`

**Date**: 2026-10-23
**Context**: designing skills per environment (`docs/state/environments.md`). Skills install
machine-wide, so a per-root choice needs a per-folder switch. `skillOverrides` is missing from the
official settings reference (anthropics/claude-code#56494) and an older issue called it a no-op.
**Verified** on Windows: two headless `claude -p --model haiku` runs, one in a folder whose
`.claude/settings.local.json` held `{"skillOverrides": {"unifi-api": "off", "portainer-deploy":
"off", "ui-craft": "user-invocable-only"}}`. The `system/init` record listed 59 skills instead of 61:
both `off` skills gone from `skills` **and** `slash_commands`; `user-invocable-only` stays listed.
Values: `on`, `name-only`, `user-invocable-only`, `off`. Also verified: a `CLAUDE.md` in the
**parent** of a project (the root folder) is loaded by a session started in the project. No such
switch is known for Codex, Copilot, Cursor, Gemini or Antigravity.

### 📝 Web-UI skills are our own rewrites, not vendored packs

**Date**: 2026-10-21 (replaces the 2026-10-20 vendoring)
**Problem**: Emil Kowalski's pack (`emilkowalski/skill@2d22863`), Impeccable
(`pbakaus/impeccable@dad8dbb`) and Taste Skill v2 (`Leonxlnx/taste-skill@63aba5f`) were vendored
as-is. An audit found no prompt injection, but behaviour we don't want an agent to pick up:
Impeccable treats its binary's `_instructions` as authoritative, says not to ask permission, asks
for an escalated sandbox, sends telemetry, uploads to image generation, downloads an unsigned
binary and writes settings files from hooks; Taste serves the working directory (`.env` included)
from a local server, downloads assets and hotlinks images and CDN scripts without integrity;
Emil's pack plans work in a git worktree and binds a dev server on `0.0.0.0` for phone testing.
Reading them (or `tests/skill-security-patterns.json`) can trip InjectionGuard: the agent loses write access for
the rest of its turn, so a rewrite agent must work from a summary, not the originals.
**Solution**: seven skills in our own words replace the 17 vendored folders — `ui-craft`,
`ui-motion`, `web-art-direction`, `web-accessibility`, `ui-stress-test`, `mobile-web`,
`ui-variants` (user-invoked). Swift, Expo, Sonner and library-picking were dropped (no project uses
them). Each ends with a `Background: distilled from …` credit line. Safety rules they carry: no
downloads or hotlinks without the user, no telemetry, preview on the project's own `127.0.0.1`
server, phones through USB port forwarding (LAN only on request, via `launch-and-deploy`), no
worktrees. Retiring a skill = delete its folder **and** add its name to `skills/RETIRED`:
the sync then removes an installed copy of that exact name whose `.ai-template-origin` names our dir
(tests case 9c), so it leaves Windows machines too. Pruning every marked copy the source no longer
ships was rejected in review: it deleted folders the user had copied or renamed (they keep the marker)
and wiped everything when a source dir was briefly empty.

### 📝 `architect-flow`: one independent agent per step (planner → spec-analyst → implementers → converger → reviewer → verifier)

**Date**: 2026-09-10, revised 2026-10-16
**Context**: the owner wants "a real project workflow" — an architect that asks design
questions, delegates to devs, then sends the code to review and tests. The 2026-09-10 version
kept a single orchestrator skill on `general-purpose` + `/code-review`: the review then ran in
the very conversation that wrote the code, so only the `verifier` judged the work with fresh
eyes.
**Decision (2026-10-16, owner's call)**: one Claude Code agent per role, each a pointer
template in `.claude/agents/` with a precise brief and a fixed report shape — `planner`
(writes the plan only), `spec-analyst` (read-only, GitHub Spec Kit's `/speckit.analyze` grid:
coverage, ambiguity, AGENTS.md conflicts = CRITICAL, parallel safety), `implementer` (one
subtask inside its `Files`, never commits), `converger` (read-only, Spec Kit's
`/speckit.converge`: code vs every plan line, returns missing rows), `reviewer` (read-only),
`verifier`. The architect designs with the user, briefs, checks diffs and commits; it writes
no feature code. Subtasks marked `P` with disjoint `Files` run as a parallel wave (same tree —
worktrees are forbidden — hence implementers never touch the index or the plan).
**Still true from 2026-09-10**: no cross-tool shell-outs (Gemini / Cursor CLI wrappers break
silently on syntax changes), no OpenRouter (adds cost on top of a subscription), MLX offload
for mechanical rows.
**Lessons Learned**: the value of a separate agent is independence, not capability — a fresh
context that only reads the repo catches what the author's context explains away. Roles stay
useful only with hard boundaries (read-only, `Files` scope, no self-grading) and a fixed
report shape the architect can check.

### 📝 Propagating template edits into owned AGENTS.md files — 3-way section refresh

**Date**: 2026-09-08
**Problem**: `AGENTS.md` is copied once and then owned by each project, so improvements to
generic sections of `AGENTS.md.template` (e.g. the new session-start sync step, new skill
rows) never reached the 19 existing siblings, while some of them had customized those very
sections (HomeAssistantAgent's 9-row skills table, HomeDevOps' checkpoint policy).
**Root Cause**: no way to tell "still the template text" from "deliberately edited" by
looking at one file.
**Solution**: `vscode-global/skills/bootstrap-ai/scripts/refresh-agents-sections.py` — split
the file into `## ` sections (a section ends at the next heading or a bare `---`), build the
set of every historical version of each generic section from `git log -- AGENTS.md.template`
(`git show <sha>:AGENTS.md.template`), and replace a project's section only if its
whitespace-normalized text is in that set. Anything else is reported `KEPT`. Commits are
`git commit -- AGENTS.md` only. Result: 19 siblings refreshed, 3 sections kept as customized.
**Lessons Learned**: a template's git history is a free "was this ever the canonical text"
oracle — cheaper and safer than markers or diff heuristics. Keep this a manual, dry-run-first
step; owned docs must never change from a hook.

### 📝 mlx-local must be upserted into every harness — Cursor was empty, VS Code had stale paths

> **Superseded** (see "The owner's tools through the shell — no MCP registration"): `mlx-local`
> is no longer an MCP server; `install-global.*` now deletes the entries this fix upserted.

**Setting**: `install-global.sh` MLX registration block
**Expected Behavior**: every agent harness (Cursor, Claude Code, VS Code Copilot, Copilot CLI,
Gemini/Antigravity) exposes `mlx-local` → `offload`, and agents actually call it for mechanical
work.
**Actual Behavior (before fix)**:
- `~/.cursor/mcp.json` was `{"mcpServers": {}}` — Cursor never saw MLX.
- VS Code `mcp.json` still pointed at `/Users/<user>/...` after a machine/user rename; the old
  merge logic skipped already-present keys, so stale paths never healed.
- Claude had project `.mcp.json` symlinks but no user-scope entry; soft AGENTS.md wording
  ("when present / proceed normally") let agents skip offload even when tools existed.
- No `mlx-offload` skill, so harnesses that match on skill descriptions never triggered.
**Solution**: upsert (not skip-if-present) mlx-local into Cursor / Claude / VS Code / Copilot
CLI / Gemini configs with absolute `$HOME/Code/MLX_Local` + resolved `uv`; add
`vscode-global/skills/mlx-offload/` with available+makes-sense gates; harden AGENTS.md +
ai-autobootstrap. Re-run `bin/aicf setup`, then reload Cursor/VS Code.
**Lessons Learned**: "register once, never refresh" breaks on path moves; soft opt-outs defeat
delegation; blind "always offload if tool exists" is as bad as never offloading — require both
availability and a sense check; shared MCP capabilities need a skill interface like `dev-secrets`.

## Shared projects & private terms

### 🐛 Employer API specs shipped from the personal repo (`horizon-api` skill) — 2026-10-15

**Symptom**: `vscode-global/skills/horizon-api/specs/*.json` (the employer platform's internal
OpenAPI documents) and its internal hostnames sat in this repo, pushed to the owner's personal
GitHub, from the MCP → skill migration on.
**Cause**: nothing stood in the way. The private-terms guard only runs in shared projects, and
it cannot run here: this repo used to name the employer on purpose (work-root skills).
**Fix**: the skill left the repo (it belongs in a work overlay under the work root); AGENTS.md
core rule 9 forbids work material; `tests/lint-skills.py` `work-material` fails on any tracked
OpenAPI/Swagger document or employer-internal hostname (case 18, CI on push). The skills
the work overlay's skills followed it out. Purging the history is the owner's
own step — agents' deny rules and auto mode forbid `git filter-repo` and force push, rightly:
in a scratch clone, `git filter-repo --invert-paths` on the three skills and
`vscode-global/horizon-openapi/`, `--replace-text` / `--replace-message` on the internal
hostnames, then a `--force-with-lease` push.

**Every clone made before the rewrite is stale**: `git pull` there says `fatal: Not possible to
fast-forward, aborting.` (or merges the old history back). Never merge it: lint-skills then
fails with `history: work-material — commit … holds a purged work-only path`. With a clean tree:
`git fetch origin` then `git reset --keep origin/main`; a branch with its own commits:
`git rebase --onto origin/main <its-old-base>` (or cherry-pick them), then delete the old one.

### 🐛 `git commit -- <path>` re-adds a file you just `git rm --cached` (shared-project switch)

**Symptom**: `git rm --cached CLAUDE.md`, add `CLAUDE.md` to `.gitignore`, then the engine's
usual paths-only `git commit -m … -- CLAUDE.md .gitignore` → the commit only holds
`.gitignore`, and `git ls-files` still lists `CLAUDE.md`. Separately, `git add -A -- CLAUDE.md`
on the now-ignored path exits 1 ("The following paths are ignored…") and aborts the add of
every other path in the same call.
**Cause**: a pathspec on `git commit` means `--only`: git re-reads those paths **from the
working tree**, and the file is still there, so the untracking is undone.
**Fix**: `--shared` refuses to run unless the index is empty (`git diff --cached --quiet`),
skips `D  ` lines when building the `git add` list, and makes that one switch commit
**without** a pathspec — the whole index, which holds only the switch.
**Why**: verified in a scratch repo (git 2.5x); covered by test 14 (bash) / 12 (pwsh).

### 📝 Shared projects: why a `.gitignore` line, not a marker file or a user-scope hook

**Decision**: a project is shared when its `.gitignore` holds `# ai-templates: local-only`.
The marker must survive a fresh clone (so the owner's next machine keeps the pointers local
and never commits them) and must not add an owner-specific file to a repo other people
clone — a gitignore line serves both, and it is exactly the list of what is kept out. On a
fresh clone the pointers (and so the SessionStart hook) are absent until the first sync:
run `bin/aicf update <name>` or `./sync-ai-templates.sh ../<name>` once on that machine.
A user-scope hook in `~/.claude/settings.json` was rejected: it would fire in every folder.

### 📝 Private-terms guard: why a `.git/hooks` pre-commit in POSIX sh, and never over a foreign hook

**Decision** (2026-09-30): shared projects get `git-hooks/pre-commit.sh.template` (manifest
`[SHARED_HOOKS]`) copied into `<git-common-dir>/hooks/pre-commit`; a commit whose staged *added*
lines or author/committer identity match the owner's private-terms list is refused.
**Why**: `.git/hooks` is never tracked, so nothing owner-specific reaches the people who clone the
project; the list itself lives outside every repo (`AI_PRIVATE_TERMS_FILE` → the code root's
`.ai-root/private-terms.txt` → `~/.private-terms`), so a friend's clone has no list and the
hook passes silently. One POSIX `sh` script does both the hook and `--scan-private`: git runs hooks
with `sh` everywhere (Git Bash's on Windows), so the `.ps1` engine installs the same bytes (CR
stripped — `sh` chokes on `\r`) and runs the scan through `sh` too, which keeps the twins identical
by construction. A pre-existing hook without the `# ai-templates: managed git hook` line is left
alone with a note — chaining it automatically would rewrite someone else's tooling (and the
pre-commit framework / husky reinstall theirs anyway); renaming it `pre-commit.local` opts into
chaining. `core.hooksPath` set = another tool owns hooks, nothing installed. Installed *after* the
sync commit so the `--shared` switch commit is never held up by its own guard.
**Gotcha**: a term matching the owner's own `user.email` blocks every commit in a shared project —
set a per-repo noreply `user.email` there. Covered by tests case 17 (both suites).

### 📝 Private AI docs: a hidden bare repo in `.git/ai-context`, not a submodule or a second clone (2026-10-11)

**Need**: in a team repo (work), the owner's `AGENTS.md` / `PROJECT_STATE.md` / `KNOWLEDGE.md`
/ `docs/state/` must not be committed, yet must follow the owner between machines.
**Decision**: `--private-docs` = `--shared` + those paths gitignored under
`# ai-templates: private AI docs` and versioned in a bare repo at `<git-common-dir>/ai-context`
used with `--git-dir`/`--work-tree` over the same tree (files stay where every agent reads them),
one branch `<root>/<project>` per project on one owner remote. The sync fetches/rebases before the
copy and pushes after it; the `Stop` hook pushes each turn. A submodule or nested clone was
rejected: both leave a trace in the team repo (`.gitmodules`, a gitlink) or move the files.
**Remote order**: `$AI_CONTEXT_REMOTE` → `<root>/.ai-context-remote` → `~/.ai-context-remote`.
Under a work root (since 2026-10-14) only the root file counts: the env var can only disable it
(`none`), `~` is never read and a github.com URL is refused, so work docs cannot land on a personal
remote even by a stray env var. Covered by tests cases 23 and 27 (both suites).

### 🐛 `update-projects --migrate --yes`: `the private-layer switch waits — … does not have the hidden branch yet` on most projects

**Cause**: `--migrate` runs every switch in one process, so they shared one 30 s
`AI_SYNC_NET_BUDGET`: after the first project, the hidden repo's push was skipped (silently —
a switch prints only the "waits" line). Resetting the budget per project was not enough on
Windows: Git Bash process spawning makes the local work before the first network step take
30–60 s, so a clock started at the project's start ran out before the push. **Fix**: the budget
counts only the time network steps wait (`AI_SYNC_NET_LEFT`, seconds left, never a wall-clock
deadline), and `migrate_one` / `Invoke-Migrate` reset it per project. Diagnose with a manual
`git --git-dir=.git/ai-context push origin HEAD:refs/heads/<root>/<project>`: if it succeeds in
seconds, the budget is the culprit, not the network. A re-run finishes a switch that waited.

### 🐛 Git Bash: `fatal: ambiguous argument 'WorkCode\pd;.github\KNOWLEDGE.md'`

**Cause**: MSYS path conversion rewrites an argument shaped like `ref:path` whose ref has a `/`
(`WorkCode/pd:.github/KNOWLEDGE.md`) into a Windows path list. **Fix**: in the engine, never
pass `ref:path` — compare with `git diff --quiet <ref> -- <file>` instead of `cat-file blob`. In
tests, `MSYS_NO_PATHCONV=1` — but that also stops converting `--git-dir=/tmp/…`, so give it
`cygpath -m` output.

### `private AI docs: push to … failed` and blank docs on a `d3skhand` clone of `D3SKHAND` (2026-10-15)

**Cause**: on a case-insensitive disk the registry file `projects/D3SKHAND` answers for a
`d3skhand` folder, but the hidden repo's branch was built from the folder name: `Code/d3skhand`,
a new empty branch instead of `Code/D3SKHAND`, so the sync created blank docs and pushed them.
**Fix**: `_registry_name` / `Get-RegistryName` — the branch and the mode lookup use the
registry entry's spelling (exact name first, else a case-only match). Case 30, both suites.
Related setup trap: the root repo cloned as `code-config` instead of `<root>/.ai-root` makes every
project read as `tracked` (`update-projects --check` all `OK … tracked`) and nothing private syncs.

### `AI files: Not set up` for every project on a second machine, doctor `All good` (2026-10-28)

**Cause**: the projects were switched to the private layer on another machine (commit `chore: move
the personal AI layer out of the repo`, `AGENTS.md` deleted), but this machine's code root has no
`.ai-root` and no `.ai-context-remote`: no registry, no mode, no hidden repo to restore from, so each
project reads as a bare `tracked` repo (`not-bootstrapped`). Doctor said only `WARN`, with an
`aicf update <name>` hint that would bootstrap blank docs. **Fix**: `aicf setup --ai-context-remote
<url>` (the URL in `<root>/.ai-context-remote` on the first machine), then a session in each
project restores it. Doctor now makes such a repo (history deleted `AGENTS.md`, root knows no
remote) a `TODO` naming that command. Case 33, both suites.

### 📝 Renaming a private-layer project's folder: its hidden branch and registry entry follow by hand (2026-10-30)

The hidden branch is `<root>/<registry name>` and the registry name is the folder name
(`_registry_name` matches the `.ai-root/projects/` file by name, not by origin). A bare `mv`
leaves the project unregistered and its private docs on a branch no sync reads. Rename all three:
the folder; `git -C <root>/.ai-root mv projects/<old> projects/<new>` (commit, push `_root`);
`git --git-dir=<new>/.git/ai-context branch -m <root>/<old> <root>/<new>` then
`push -u origin <root>/<new>`. The old remote branch stays until deleted by hand.

## Portability (Windows, PowerShell, Bash 3.2, macOS)

### `Unexpected token '}' in expression or statement.` — install-global.ps1 / doctor.ps1 on a fresh Windows (2026-10-16)

**Problem**: on a new Windows PC the setup never happened: `.\install-global.ps1` (and `doctor`,
`update-projects`, `new-project`, `sync-ai-templates`, `kp`) died with parser errors.
**Root Cause**: a fresh Windows only has Windows PowerShell 5.1, which reads a BOM-less `.ps1` as
ANSI. The UTF-8 em dash `E2 80 94` becomes `â€”`, and `0x94` is `"` in cp1252 — PowerShell
takes it for a closing quote, so a string like `"… — carrying on"` ends early. pwsh 7 assumes
UTF-8, which is why it only broke on machines without pwsh. The scripts also use pwsh-only
features (`ConvertFrom-Json -AsHashtable`), so 5.1 compatibility was never an option.
**Solution**: every non-ASCII `.ps1` starts with a UTF-8 BOM (`tests/lint-skills.py`
`ps-encoding` enforces it), and each entry script hands a 5.1 run over to `pwsh` right after
`param()` — or prints the `winget install --id Microsoft.PowerShell -e` line and exits 1. Check a
file the way 5.1 sees it: `powershell.exe -NoProfile` +
`[System.Management.Automation.Language.Parser]::ParseFile(…)`.

### 📝 `Unknown option:  (usage: .\doctor.ps1 …)` with no argument at all

**Date**: 2026-10-15
**Problem**: `doctor.ps1` run bare refused its own empty command line (exit 2, blank option name).
**Root Cause**: a `[Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest` that received
nothing is `$null`, and `@($Rest)` is then **one `$null` element**, not an empty array — the
`foreach` ran once and the `switch` hit `default`.
**Solution**: iterate `@($Rest | Where-Object { $null -ne $_ })`. Any script that parses `--flag`
style arguments this way needs the same filter (`install-global.ps1` indexes `$Rest.Count`, which is
safe).

### 📝 `FIX   Claude global SessionStart hook missing` right after install-global registered it

**Date**: 2026-10-15
**Problem**: `doctor.ps1` never saw the hook entry that `Install-ClaudeGlobalHook` had just written.
**Root Cause**: `$node = if (Test-Path …) { $J::Parse(…) } else { $null }` — an `if` used as an
expression sends its output down the pipeline, which enumerates it; a `JsonObject` is an
`IEnumerable` of key/value pairs, so `$node` became an `Object[]` and `-is [JsonObject]` was false.
Hashtables are not enumerated, which is why the same pattern works for `ConvertFrom-Json -AsHashtable`.
**Solution**: assign inside the branch (`if (…) { $node = $J::Parse(…) }`), never from an
`if`/`foreach`/function output, whenever the value is a `System.Text.Json.Nodes` node.

### 📝 Windows breaks both test suites in three unrelated ways

**Date**: 2026-09-16
**Problem**: `tests/run-tests.ps1` died at case 4 with `New-Item: Administrator privilege required`
and `tests/run-tests.sh` at `FAIL: dry-run did not plan the migration`; once past those, the pwsh
suite reported `copy mode said nothing` and then `origin marker not written`.
**Root Cause**: four separate Windows-only issues. (1) Creating a symlink needs Developer Mode or
elevation; Git Bash otherwise **fakes `ln -s` by copying the target**, so `[ -L ]` is false and the
symlink cases cannot even be staged. (2) `python3` on PATH is often the **Microsoft Store stub**,
which exists but exits non-zero instead of interpreting. (3) A native Windows python cannot open a
Git Bash POSIX path like `/f/Code/…`. (4) PowerShell's automatic `$HOME` — which the engine uses for
the global skill folders — is derived from **`USERPROFILE`** and ignores `$env:HOME`, so the suite
was reaching into the **real** user profile (`~/.copilot/skills` exists there) instead of its
sandbox. Separately, the origin-marker assertion compared against a hardcoded `/` separator while
the engine builds the value with `Join-Path` (backslashes).
**Solution**: both suites probe symlink capability once and **skip the affected cases loudly**
(4, 7, link halves of 9/9b), still covering the no-symlink half of case 4 (the `core.symlinks=false`
text-file pointer). The bash suite picks the first of `python3`/`python`/`py` that actually runs and
feeds it the hook JSON on **stdin** rather than by path. The pwsh suite sets `$env:USERPROFILE`
alongside `$env:HOME`, and builds the expected marker with `Join-Path`.
**Gotcha**: before the `USERPROFILE` fix the suite could silently rewrite the skills installed in
the real profile. If a run ever looks like it "did nothing", check whether it is reading your real
`~/.copilot/skills` rather than the sandbox.
**Later (2026-10-09), three more on a box with only uv-managed python:** `FAIL: no working python
found` → both suites fall back to `uv python find`. `lint-skills` died on `git ls-files` exit 128
(`detected dubious ownership`: the drive was owned by another Windows install's SID, and the
sandbox `GIT_CONFIG_GLOBAL` dropped the real `safe.directory` list) → the sandbox sets
`safe.directory '*'`. Bash case 15 `FAIL: base skill origin marker wrong`: cases 10b/10c/11 run the
hook from **copies** of this repo, and in copy mode their origin markers make every skill "owned
elsewhere" → case 15 empties the sandbox skill roots first. And `chmod 000` is a no-op under Git
Bash, so the unreadable-input halves of 15 and 19 are probed and skipped loudly.
**Later (2026-10-28):** `tests/check.sh` on Windows stops at `check-docs` (`docs/reference/cli.md is
stale`, then `UnicodeEncodeError: 'charmap'` printing it): `aicf doctor --help` there hands over
to the `.ps1` twin, so never regenerate `cli.md` on Windows — run the suites directly. The pwsh
suite needs a UTF-8 console (`chcp 65001` + `[Console]::OutputEncoding`) or case 15c fails on `…`.

### 📝 After a macOS upgrade, `git` and `python3` fail: "You have not agreed to the Xcode license agreements"

**Date**: 2026-09-16
**Symptom**: every `git …` or `python3 …` exits 69 with that message (macOS 27 upgrade). The
SessionStart hook runs `git` from `PATH` too, so the sync commit fails silently in every project.
**Cause**: `/usr/bin/git` and `/usr/bin/python3` are Xcode shims; an OS upgrade resets the license
acceptance.
**Fix**: the human runs `sudo xcodebuild -license accept` once. **Until then**: put Homebrew
first — `export PATH=/opt/homebrew/bin:$PATH` for `git` — and use a non-shim interpreter
(`/opt/homebrew/bin/python3.11`, or `uv run python`) for `refresh-agents-sections.py`.

### 📝 Windows symlinks need Developer Mode — so nothing a project receives is a symlink

**Setting**: `New-Item -ItemType SymbolicLink` in `install-global.ps1` (skills only, now)
**Expected Behavior**: symlink created like on macOS.
**Actual Behavior**: fails without admin rights or Windows Developer Mode. Project files are
therefore always plain copies (see the pivot entry above); the only remaining symlinks are
the global skill folders on macOS/Linux. On Windows `install-global.ps1` copies skills
outright and the session-start `--skills` pass keeps them fresh; `AI_SKILLS_MODE=copy` (or
`bin/aicf setup --copy`) forces copies on macOS too.
**Why**: Windows restricts `SeCreateSymbolicLinkPrivilege` by default, and a git checkout with
`core.symlinks=false` materializes links as text files anyway.

### 📝 PowerShell twin gotchas: `switch -Regex` fall-through and dot-sourced `param()`

**Setting**: `sync-ai-templates.ps1` argument parsing / dot-sourcing
**Expected Behavior**: like a C `switch`, one case runs; a script's `param()` is local to it.
**Actual Behavior**: PowerShell `switch` evaluates **every** matching case unless the block
ends with `break` — `'^-'` (unknown option) fired after `'^(--commit|-Commit)$'` had already
matched. And dot-sourcing a script that declares `param([switch]$DryRun)` **overwrites the
caller's own `$DryRun`** (`update-projects.ps1` had one).
**Correct Configuration**: `break` at the end of each `switch -Regex` case; no `param()` in
the engine — it parses `$args` only when `$MyInvocation.InvocationName -ne '.'`. Also run
native git through a helper that flips `$ErrorActionPreference` to `Continue` and reads
`$LASTEXITCODE`, so a non-zero git exit under `Stop` doesn't throw (pwsh 7.4+ can).
**Why**: PowerShell semantics, verified with the scratch test suite under pwsh 7.6.

### Bash: `line N: dir�: unbound variable` — a `…` right after `$var` (2026-10-02)

Under a UTF-8 locale, bash reads the bytes of `…` (U+2026) glued to `$dir` as part of the name:
`echo "into $dir…"` expands `$dir\xe2…`, and `set -u` aborts. Write `${dir}…` whenever a
non-ASCII character follows a variable. Hit in `launch-and-deploy/scripts/sibling-deps.sh`.

### pwsh on macOS/Linux: `Could not find item …/.ai-context-remote` — dotfiles are hidden (2026-10-13)

On Unix, pwsh flags every dotfile as Hidden. `Test-Path` still finds one, but `Get-Item` /
`Get-ChildItem` without `-Force` say `Could not find item`, and `Remove-Item` without `-Force` says
`the item is hidden, system, or read only`. Pass `-Force` to every `Get-Item` / `Remove-Item` on a
dotfile. Hit in `Get-AiContextRemote` (tests case 23, pwsh only — bash's `[ -s ]` doesn't care).

### Claude memory import misses `~/.claude/projects` — the slug used Git Bash's `/d/...` path (2026-10-14)

Claude Code names `~/.claude/projects/<slug>` by turning every non-alphanumeric character of the
project's **native** absolute path into `-`. On Windows that path is `D:\Code\Foo` (`cygpath -w`,
`[IO.Path]::GetFullPath`), not Git Bash's `/d/Code/Foo`: the msys form slugs to a different
directory, so the import copies nothing and never retries (the stamp is written only after a
real source directory was seen). `:` and both separators are non-alphanumeric, so `D:\Code\Foo`
and `D:/Code/Foo` slug the same (`D--Code-Foo`). `autoMemoryDirectory` is the forward-slash form
(`cygpath -m`) because a relative value is ignored. Hit in `_memory_slug` / `Get-MemorySlug`.

### `nothing to commit` on an unchanged `.ai-root` registry entry — CRLF checkout (2026-10-13)

Under `core.autocrlf=true` a checked-out `projects/<name>` has CRLF endings while the engine
writes LF, so a byte compare said "changed", the file was rewritten, and `git commit` found
nothing to commit (git normalizes on add). Compare CR-blind (`tr -d '\r' | cmp`; a byte filter in
pwsh) before writing. In tests, detect CRs with `tr -d '\r' < f | cmp -s - f`, not `grep $'\r'`:
Git for Windows' `grep` drops CRs. Hit in `_registry_write` / `Save-RegistryEntry` (case 25).

### `OK  <project>  private` from `update-projects --check` while git still tracks `AGENTS.md` (2026-10-15)

A project switched on another PC gets `mode=private` in `.ai-root`; on a PC that pulled the
registry but not the switch, the project has no exclude block and no legacy marker, so
`_project_mode` falls back to the registry and says `private` — the plan was "met" while the code
repo still tracked layers B and C, and `--migrate` skipped it. `_conforms` / `Test-Conforms` now
also require `_tracks_layer` (one `git ls-files` over the layer paths) to be empty. Fix on such a
PC: code repo behind an upstream untrack commit → `git pull --ff-only`, then a hook-mode sync
restores B from the hidden branch; upstream still tracking → `--private-layer --commit` (it
adopts the existing hidden branch; differing local copies go to `.git/ai-context.bak/`).

### A team repo shows ` M .claude/settings.local.json` after `--private-layer` (2026-10-15)

`invictus-live-calendar` (team mode) commits its `.claude/settings.local.json`; the memory merge
wrote `autoMemoryDirectory` into it anyway, breaking the team rule "tracked files are never
written". `_memory_settings` / `Merge-AutoMemorySettings` now return early in team mode when the
code repo tracks that file: Claude's memory stays machine-local there (case 28).

### `Unable to index into an object of type "System.Text.Json.Nodes.JsonObject"` (2026-10-15)

`$v = if ($x) { $node.DeepClone() } else { $null }` stores an array of `KeyValuePair`s, not the
node: a JsonObject is enumerable, and PowerShell enumerates whatever leaves a statement. Assign
in plain statements (`$v = $null; if ($x) { $v = $node.DeepClone() }`) — see
`Install-ClaudeProfiles`.

### `Cannot bind argument to parameter 'Path' because it is an empty string.` — install-global.ps1 under a redirected USERPROFILE (2026-10-16)

`[Environment]::GetFolderPath('MyDocuments')` returns `''` once `USERPROFILE` points anywhere
but the account's real profile, so the pwsh suite's case 30 died in `Install-ClaudeProfiles`
(`Join-Path $docs …`). Fall back to `$HOME/Documents` when it is empty.

### 🐛 `FAIL: a retired name a source still ships was removed` (case 9c, macOS only) (2026-10-23)

APFS folds case like NTFS, but the RETIRED match folded it on Windows only: the `OV-KEPT` line
missed the shipped `ov-kept`, and `$K/OV-KEPT` then opened the installed `ov-kept` and removed
it. Both twins now compare without case on every OS (it can only keep more). Linux CI cannot see
this: its file system keeps `OV-KEPT` and `ov-kept` apart.

### `unexpected EOF while looking for matching `"'` — engine/uninstall.sh on macOS only (2026-10-27)

Bash 3.2 misparses a quoted heredoc inside `"$( … )"` when the heredoc body holds quotes: the
first public CI run failed case 34 on macOS while Linux (bash 5) was green. Put the command and
its heredoc in a function and call `"$(_edits)"` (`engine/uninstall.sh`). `bash -n` on Linux does
not catch it.

### 🐛 `FAIL: a private term of the list not caught` — Windows only, the em dash came out as `�` (2026-10-27)

Python writes to a pipe in the console code page on Windows (cp1252: the em dash is one byte,
`0x97`), so a test matching `work-material — private term` failed in Git Bash and in PowerShell.
Both suites set `PYTHONUTF8=1` (UTF-8 mode, the default from Python 3.15, PEP 686); a PowerShell
match on Python output stays ASCII-only, since `[Console]::OutputEncoding` decides the decoding.

### 🐛 `FAIL: uninstall --yes must give the home back exactly` — Windows only (2026-10-27)

Three Windows-only causes, each fixed where it starts:
- **Git Bash**: Python records `~/.claude-profiles` as `D:\…\.claude-code`, which `case "$d" in
  "$HOME"/*` never matches (`$HOME` is `/tmp/…` or `/d/…`). `engine/uninstall.sh` rewrites a
  recorded dir under `$HOME`'s own spelling (`cygpath -m` on both sides). `cygpath -u` alone is
  not enough: it gives `/c/Users/…/Temp/…`, not `/tmp/…`.
- **pwsh**: `JsonNode.ToJsonString` with `WriteIndented` writes `Environment.NewLine`, which is CRLF
  on Windows. Every settings writer now applies ``.Replace("`r`n", "`n")``, as the Python twin does.
- **The test**: pwsh run with `USERPROFILE` set to the sandbox creates `AppData\Local` there.
  Case 34 warms pwsh inside the sandbox before it takes the snapshot.

A symlink's `LinkTarget` comes back in Windows form. Compare it with
`[IO.Path]::GetFullPath(…)` on both sides, never as a raw string.

### 🐛 `python3.exe : Python was not found; run without arguments to install from the Microsoft Store` stops `aicf projects|config` (2026-10-29)
**Problem**: under Windows PowerShell 5.1, `bin\aicf.ps1 config` died on its Python probe instead
of moving on to `python`.
**Root Cause**: with `$ErrorActionPreference = 'Stop'`, 5.1 turns a native command's stderr into
a terminating `NativeCommandError`, even with `2>$null`. The Store stub writes to stderr. pwsh 7
does not.
**Solution**: probe as `engine/doctor.ps1` does, with
`try { & $py -c 'import sys' 2>$null | Out-Null } catch { continue }`, then check `$LASTEXITCODE`.

## Tests & CI

### 🐛 `docs/reference/cli.md is stale — run: python3 tests/gen-cli-reference.py` on Windows only (2026-10-29)

On Windows `check.sh` stops at `check-docs` even on a clean HEAD: under Git Bash `doctor.sh`
hands over to `doctor.ps1`, whose `--help` differs (`-Yes` spellings, ASCII dashes), so the
generated page never matches. Regenerating there rewrites the `doctor` section wrongly. Fix:
regenerate on macOS/Linux, or add the new command's lines by hand from a Windows run (only the
`doctor` section differs) and let the Linux CI judge. The same Windows console also turns `…`/`—`
into `.`/`-` in case 15c of `run-tests.ps1` unless the console is UTF-8
(`[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)`).

### 🐛 `new      function_lines     109 > 80  …ui_audit.js::uiAudit` locally, not in CI (2026-10-24)

`uv run code_health.py` reuses its cached script environment (lizard 1.24.2 here) while CI
resolves the latest (1.24.3), and the two parse nested JS functions differently: one counted
`uiAudit` as 109 lines, the other 79. Run the gate (and any `baseline --accept`) with
`uv run -q --upgrade-package lizard …/code_health.py check` before trusting a JS length.

### 🐛 `Process completed with exit code 1.` right after `ALL OK — pwsh` (GitHub Actions) (2026-10-23)

A `shell: pwsh` step ends with `exit $LASTEXITCODE`, and case 33's last `doctor` call exits 1 on
purpose: a green suite failed the job. `run-tests.ps1` ends with `exit 0`.

### 🐛 `FAIL: a remote without the branch lets the docs be created and pushed` (case 26, Git Bash only) (2026-10-22)

**Cause**: the run's 30 s `AI_SYNC_NET_BUDGET` was a wall-clock deadline started at its first
network step (the `ls-remote`), and the local commit between it and the push ran past it — one
engine run took 73 s on a machine where a Git Bash fork costs ~200 ms (pwsh passed the same case).
The push was then skipped silently; at session start the hidden repo never pushed on that machine.
**Fix** (2026-10-24): the budget counts only the time network steps wait (`AI_SYNC_NET_LEFT`).
Check: the case alone with `AI_SYNC_NET_BUDGET=600
AI_SYNC_PULL_WAIT=120` pushes. `fail` exits, so every later bash case is skipped too: run the
case you changed alone (preamble lines + its block) to cover it. Cases 26-33 run alone from the
lines before case 1, `export AI_SYNC_NET_BUDGET=600`, the `hook_cmd`, `mkproj`, `EN` and
`has_cr` one-liners, then everything from case 26 on (2026-10-23: ALL OK in ~70 min).

### 🐛 `claude must use the profile inside its root only: cfg=<real profile> cfg=<real profile>` (case 30) (2026-10-22)

The suites ran inside a session that exports `CLAUDE_CONFIG_DIR` (a D3SKHAND account): the
profile function leaves an already-set value alone, so the sandbox root's profile never applied.
Case 30 clears it for that call (`env -u CLAUDE_CONFIG_DIR`; pwsh saves, nulls and restores it).

### 🐛 Case 30 under Git Bash created `C:\Users\<u>\.claude-w30` — a test wrote into the real home (2026-10-22)

Windows python's `os.path.expanduser("~")` reads `USERPROFILE`, never `HOME`, so `IG` (faked
install-global.sh) with only `HOME="$IGH"` wrote the profile into the real home. `IG` now sets
`USERPROFILE` too, and the Claude-profile block is skipped under Git Bash (its python writes
`C:\` paths the bash `claude` function never meets; `run-tests.ps1` covers Windows). Still open
under Git Bash, older than this fix: `FAIL: an unknown project gets one suggestion line:` (empty
— `--global-hook` prints nothing for an unknown project in a code root).

### 🐛 Case 30-32 fail on a staged-only change (`check-only must write nothing`, `context budget … 9 KB`) (2026-10-16)

Case 30 builds its engine clone from `HEAD` plus `git ls-files -m -o`: a file staged and not
modified since is neither, so the clone tests `HEAD`'s copy. Run the suites on an unstaged tree
(`git reset -q` keeps the work) — or the result is not about your change.

### 📝 The test suite lives in the repo now (it used to live in a session scratchpad)

**Date**: 2026-09-08
**Context**: `AGENTS.md` required running an engine test suite before committing, but the
suite only ever existed in the agent's scratch directory — it disappeared with the session, so
"run the tests" really meant "rewrite the tests".
**Solution**: `tests/run-tests.sh` and `tests/run-tests.ps1`, each building a sandbox with
`mktemp -d`, an isolated `HOME` **and** `GIT_CONFIG_GLOBAL` (otherwise
`git config --global user.email` inside a test writes into the real `~/.gitconfig`). Twelve
engine cases per twin, each tied to a bug that actually happened: the `.gitignore` newline,
the paths-only commit, symlink migration including the Windows text-file form, the
foreign-skill guard, the hook under `sh -c`.
**Lessons Learned**: a test that is not committed does not exist. Writing the expectation
first also caught one of my own wrong assumptions.

### Testing a network timeout: a remote that hangs, not one that fails (2026-10-13)

An unreachable path or host fails at once, so it never exercises a timeout. A hanging remote that
works from bash and pwsh on every OS: `AI_CONTEXT_REMOTE=ssh://hang.invalid/x.git`,
`GIT_SSH_VARIANT=simple` (no `-G` probe, no options) and `GIT_SSH_COMMAND="echo x >> '<log>'; sleep
6; echo done >> '<log>'; exit 1;"`: each `x` line in the log is one network step. In pwsh, write
the log path with forward slashes. On Windows the hung `sh` keeps its cwd busy, so wait for `done`
before the sandbox is removed. Used in case 26 (network budget).

### A sandboxed project's root walk reaches the real `~/.ai-context-remote` — the temp dir is under the real home (2026-10-14)

`_ancestor_root` / `Get-AncestorRoot` walk up from a project to the nearest folder holding
`.ai-root/` or `.ai-context-remote`. On Windows the test sandbox lives in
`C:\Users\<u>\AppData\Local\Temp`, so the walk climbed out of it into the real home and took its
`.ai-context-remote` (the personal fallback) for a code root — a test could push to the owner's
remote, and a work-root test would read `~` by the back door. Fix: the walk stops at `$HOME` and
every folder above it; with the sandbox `HOME=$S/home`, `$S` is such an ancestor, so the walk never
leaves the sandbox. Compare physical paths (`pwd -P`; `GetFullPath` + ordinal-ignore-case in pwsh).

### `FAIL: a second quiet run must be only the plan line` on Windows only — `rev-parse --show-toplevel` prints `C:/…` (2026-10-15)

Under Git Bash, `git rev-parse --show-toplevel` returns a mixed path (`C:/Users/…/Temp/…`) while
the engine prints the POSIX form (`/tmp/…`), so an expected line built from it never matches.
For "the path the engine prints" in `run-tests.sh` use `$(cd "$dir" && pwd -P)`: it resolves
macOS's `/var` symlink too, so one expression serves both OSes.

### A captured pwsh plan line has a hyphen where the engine wrote U+2014 (2026-10-14)

The conformance lines (`ai-sync: … plan — switch`) use an em dash. On this machine
`[Console]::OutputEncoding` is cp850. A child `pwsh -File` inherits that code page, so the
parent's captured string contains U+002D and an exact `-cne` against the source line fails.
Set `[Console]::OutputEncoding` and `$OutputEncoding` to a no-BOM UTF-8 before the child
starts: the child then reports code page 65001 and the em dash comes back as U+2014. Hit in
`tests/run-tests.ps1` case 29. Bash compares the bytes directly and needs no equivalent.

### `Unsupported OS. Use install-global.ps1 on Windows.` — running install-global.sh in the bash suite (2026-10-14)

`install-global.sh` exits on `uname -s` = `MINGW*`, and its inline python is `python3`, which on
Windows is often the Store stub. To exercise it end to end under Git Bash (case 30), put a
`$S/…/bin` first on its `PATH` with a `uname` that prints `Linux` and a `python3` that `exec`s the
python the suite found, and set `HOME`, `XDG_CONFIG_HOME` and `AI_SKILLS_MODE=copy` to the
sandbox. The PowerShell twin needs `USERPROFILE`, `HOME` **and** `APPDATA` pointed into the
sandbox (pwsh's `$HOME` follows `USERPROFILE` on Windows). Also in case 30: pwsh's origin-slug
split must include `\`, or a local `C:\…\x.git` origin never matches (`update-projects -Clone`).

## Launchers & tray apps

### 📝 Switchboard is the control plane for every startable `~/Code` project

**Superseded** by the entry below: the Switchboard app is retired. Do not start it and do not
call `http://127.0.0.1:2600`. `switchboard.json` and the fixed-port rule are unchanged; the
D3SKHAND tray is the control plane.

**Date**: 2026-07-20
**Context**: Switchboard (`~/Code/Switchboard`) already scans `~/Code` and lists every folder,
but projects without a discoverable launcher stay `unavailable` — so new siblings often never
became startable from the tray/dashboard unless an agent remembered the convention.
**Decision**: bake Switchboard inclusion into the shared `launch-and-deploy` skill (detection
order, `switchboard.json` schema, **fixed-port policy**, port/URL discovery,
`POST /api/refresh`) and into `bootstrap-ai` step 9 so every startable project gets a root
`start.sh`/`start.ps1` (or an explicit `switchboard.json`) plus a stable listen port as part of
normal bootstrap / launcher work. Pure libraries/docs/template repos may skip.
**Alternatives Considered**: generating a stub `switchboard.json` from `new-project.sh` for
every empty sibling — rejected; empty projects have no start command yet and would spam
`unavailable` with a broken override. Auto-registering into a Switchboard allowlist — rejected;
discovery is folder-scan based by design. Letting frameworks pick a free port — rejected;
Switchboard's Open URL and bookmarks need a known address.
**Outcome**: agents creating or changing how a project starts leave it controllable from
the tray without a separate registration step; web UIs always bind a documented fixed port
unique across the code root. (The dashboard URL in the original outcome is gone — see below.)

### 📝 The Switchboard app is retired — the D3SKHAND tray lists the apps

**Context**: two menu-bar icons (Switchboard's slider, D3SKHAND's mark) started and stopped
local apps, and Switchboard's Stop could signal an agent CLI working in a project folder.
**Decision**: Switchboard is uninstalled. Its discovery rules live in D3SKHAND
`d3skhand/tray/switchboard/`. `switchboard.json` stays the opt-in file. The tray's Apps
section starts, stops, kills and opens; it rescans on its own (~30 s) and from **Rescan apps**.
Nothing listens on port 2600, and there is no embeddable widget. Stop never signals an agent
CLI, D3SKHAND's hub or node, an editor or an interactive shell.
**What stays**: the fixed-port rule, the start/stop/kill triad, and `switchboard.json`. A
project still opts in with that file. Do not recreate the Switchboard repo's LaunchAgent.
**2026-10-09**: the `neijix/Switchboard` GitHub repo is deleted (restorable for 90 days from
GitHub settings → Repositories → Deleted repositories), so `update-projects --clone` no longer
offers it. The name `switchboard` survives only as the opt-in file and the D3SKHAND module.

### 📝 Long-running apps need start.command + stop.command + kill.command

**Date**: 2026-07-23
**Context**: Only a few siblings had Finder `start.command`; almost none had a dedicated
graceful `stop` vs force `kill`. The tray runs a project's stop/kill command when it has
one; otherwise it will not signal an agent, an editor or D3SKHAND, so a process it must leave
alone can still hold the fixed port and break the next start.
**Decision**: extend `launch-and-deploy` (and bootstrap-ai step 9) with a required **triad**
for every long-lived local process: root `start.command`, `stop.command` (SIGTERM /
compose stop), `kill.command` (SIGKILL on fixed ports). Idempotent; skip for libraries,
docs, one-shots, and `open`-only Switchboard stubs. Reference: `AI_token_status`.
**Alternatives Considered**: relying only on the tray's signals — rejected, a protected
process can still hold the port; a single `kill.command` that does TERM-then-KILL — rejected,
loses the Stop vs Kill distinction the tray already exposes.
**Outcome**: agents creating or hardening launchers always leave Finder-level stop/kill
next to start; port-based cleanup guarantees start → stop → start works.

### 📝 Install/start launchers must validate toolchain deps (auto-install when possible)

**Date**: 2026-07-23
**Context**: Double-clicking Switchboard `Install.command` failed with a bare
`ERROR: Go is required to build (brew install go)` — correct check, but a dead end for a
one-click installer. Sibling `start.*` scripts (e.g. AI_token_status) often called `npm`
with no prior `node`/`npm` check.
**Decision**: extend `launch-and-deploy` with a **Dependency validation** section: every
`install*`/`start*` checks hard tools up front (`command -v` / `Get-Command`), fails with
the OS install one-liner, **auto-installs via brew/winget when available**, and prepends
Homebrew to `PATH` for Finder `.command` shells. Reference implementations:
Switchboard `install.sh`/`.ps1`, Neijix_Odysseus `start-macos.sh`.
**Alternatives Considered**: fail-only (print brew/winget hint) — kept as fallback when
the package manager is missing; requiring a separate `setup` step — rejected, breaks
one-click.
**Outcome**: agents hardening launchers treat missing Go/Node/uv as a script bug, not a
user error; Switchboard install now installs Go via Homebrew when absent.

## Secrets & auth

### 📝 SSH keys: local-first in ~/.ssh, Bitwarden DEV_KEYS as backup

**Date**: 2026-09-16
**Context**: git/ssh went through the Bitwarden desktop SSH agent, so every connection depended
on the app being open and unlocked (plus the non-default macOS socket path, and only `ssh-key`
typed items being served).
**Decision** (owner's call): keys live as files in `~/.ssh` (600), loaded by the OS agent via
`~/.ssh/config` (`AddKeysToAgent`, `UseKeychain`, one `Host` block with `IdentityFile` +
`IdentitiesOnly` per key). Every key keeps a backup item in `DEV_KEYS`; restore is
`bw get item <name> | jq -r '.sshKey.privateKey // .notes'` under `umask 077`, which handles both
`ssh-key` and secure-note backups. The Bitwarden agent stays a per-shell fallback. Procedure:
`dev-secrets` skill.
**Gotcha**: in auto mode the safety classifier may refuse an agent writing a private key to
disk regardless of allow rules — hand the restore block to the human instead of working around it.

### 📝 `gh` HTTP 401 ≠ broken SSH — reconnect via device login

**Date**: 2026-07-20
**Problem**: Agents hit `HTTP 401: Bad credentials` on `gh` (Actions logs, PRs, API) even when
`git push` over SSH still works via the Bitwarden SSH Agent.
**Root Cause**: `gh` stores its own OAuth token separately from SSH keys; an expired/`GH_TOKEN`
override does not affect `git@github.com`.
**Solution**: in `dev-secrets` Step 2b — try `GITHUB_PAT` from Bitwarden with
`gh auth login --with-token` first; otherwise run
`gh auth login --hostname github.com --git-protocol https --web --skip-ssh-key`, show the user
**https://github.com/login/device** + the one-time code, and wait for `Logged in as` /
`authentication complete` before retrying.
**Lessons Learned**: never treat SSH success as proof that `gh` is authenticated; never ask the
user for a PAT when the device flow can reconnect them in-browser.

### KeePass vaults per root — `keepass-secrets`, Bitwarden as backup (2026-10-05)

The owner wanted one place for every key, Bitwarden kept as backup. Decision:
one KeePassXC database per code root (`$AI_CODE_ROOT/secrets.kdbx`, `<work-root>/secrets.kdbx`),
in the root folder so it is in no repo; master password in the OS store (Keychain service
`kp-secrets-<scope>`, Windows DPAPI file `%LOCALAPPDATA%\kp-secrets\<scope>.pw`); `kp backup`
upserts the personal vault into Bitwarden `DEV_KEYS`. **No work secret in Bitwarden** (owner,
2026-10-05): `import-bitwarden`/`backup` refuse the work scope; the work vault's only backup is a
copy of its encrypted `.kdbx`.

- `keepassxc-cli` reads the master password and then an entry value (`add/edit -p`) as
  successive stdin lines, `-q` hides the prompt; `db-create -p` wants it twice. `ls -R -f` on an
  empty database prints `[empty]`, groups end in `/`. `attachment-export --stdout` for text.
- `bw --nointeraction` everywhere: without it, a locked or mis-sessioned `bw` waits forever on a
  master-password prompt. `bw create|edit item` read the base64 JSON from stdin — no value in argv.
- `kp.sh` appends (not prepends) `/opt/homebrew/bin` to `PATH`, so a test's mock `bw` wins.
- PowerShell: a function named `Bw` shadows the `bw` executable (names are case-insensitive) →
  "The script failed due to call depth overflow". Call the resolved `Get-Command -CommandType
  Application` path. And `if (...) { @(x) } else { @() }` unrolls: build JSON arrays in an
  `ArrayList` or `ConvertTo-Json` emits `null` / a bare object.
- `security find-generic-password -w` prints the password **plus a newline**. Piped raw into
  `keepassxc-cli add -p`, that newline became an empty extra line, so every entry was stored with
  an **empty password** while `get` still exited 0. `kp.sh` strips it (`pw="$(…)"; printf '%s'`).
  The `KP_PASSWORD` test path has no newline, which is why mock tests missed it — verify a real
  vault by comparing `kp get` to the source, not by exit codes.

## Machine-local & dev-context

### 📝 Parallel agents: no worktrees; machine tooling lives in NeijixComputerConfigurator

**Date**: 2026-09-16
**Decision** (owner's call, from the DHH review): no `git worktree` — parallel agents means
parallel *repos*, never two agents in one checkout — one exception, the owner's call of
2026-10-16: architect-flow `P` waves, where implementers with disjoint `Files` share the tree
but never touch the index, the plan or a whole-tree gate (see `## Skills & templates`). The machine's CLI toolchain (gh, uv, bw, mise,
lazygit, tailscale…) is declared in `~/Code/NeijixComputerConfigurator` `config.json`
`Software[]` (winget ID + `Brew`/`BrewCask`), not in a Brewfile here — that repo already
installs, updates and syncs software on both OSes. "Agent is waiting" notifications belong in
AgentDesk, not in macOS notifications.

### 📝 Dev-context packs: personal and work rules stay out of git

**Date**: 2026-10-07
**Context**: one global instruction file was applying personal secrets and MLX rules to every
project, including work. The owner wanted the two sets split into different AppsSync folders.
**Solution**: each code root's `.ai-root/dev-context/` (since 2g; first the AppsSync
`AICodeFactory/<personal>/` and `<work>/` folders, now retired and never read) (`rules.md` is
development rules only; optional `settings.json` holds no credentials). Credential procedures
stay in the skills, not in these folders. The sync prints `ai-sync: dev-context <label>`
(environment.json `label`, else `work` or `personal`) and writes gitignored `CLAUDE.local.md`,
only when that file is missing or its first line is the `<!-- ai-templates: dev-context` marker.
`--quiet` prints one `ai-sync: dev-context` line and nothing when there is no pack, so case 2
stays empty.
**Why**: a cloud placeholder can `stat` and still fail to open (`Resource deadlock avoided`).
The read is guarded; the session-start sync still exits 0. A pack file over 16 KiB is truncated
so it cannot fill the context. The absolute pack path is never written into the project
(it contains the owner's account).

### 📝 `.dev-context.tmp.<pid>` committed in a project

**Date**: 2026-10-19
**Problem**: an agent's `git add -A` committed a `.dev-context.tmp.1309` leftover.
**Root Cause**: `CLAUDE.local.md` was built in the project's work tree, then moved; a killed hook
or failed move left the temp file there, untracked and not gitignored.
**Solution**: both engines now build it in the system temp dir and delete any old
`.dev-context.tmp.*` from the project root on each sync. An already-committed one needs
`git rm --cached` in that repo.

### 📝 New Linux machine: doctor lists every private project as "not bootstrapped"

**Date**: 2026-10-25
**Problem**: on a fresh Linux box (`~/CODE`), `doctor` said `20 git repo(s) not bootstrapped` and
`no .ai-root and no private AI docs remote`, while `code-config` sat beside the projects.
**Root Cause**: the root repo had been cloned as a plain sibling instead of `<root>/.ai-root`, so
the folder was no code root and nothing restored layer B. Beyond that, the hidden branch was
`<root folder>/<project>` with the folder's raw case: `CODE/D3SKHAND` on a case-sensitive disk,
while every branch on the remote is `Code/…` — the restore would have found nothing.
**Solution**: move the clone to `<root>/.ai-root` (or let `install-global --ai-context-remote`
clone it), then `install-global` and `doctor --yes`. The engine now spells the root part as
`.ai-root`'s remote-tracking branches do (`engine/names.sh` `_root_spelling`, twin `.ps1`).

---

## Factory config and the losses on push/pull

### 📝 No config file means the sync writes nothing new

**Date**: 2026-10-23
**Problem**: Personal taste, per-environment skills and the agent for each step had nowhere to
live, and a killed session-start hook dropped skill installs. A hidden-repo rebase conflict
printed one line that the Stop hook discarded. An edited Windows skill copy was overwritten.
D3SKHAND isolated copies of private and team projects do not contain the AI docs.
**Solution**: `engine/factory-env.py` is the only reader and writer (not a second C#
tool: the hook runs before .NET is required, and the engine already calls Python for JSON).
`factory.json` is in the personal overlay. `<root>/.ai-root/environment.json` is per code root.
The sync publishes skill overrides and a `CLAUDE.local.md` section only when one of those files
exists or something is off. The skill stamp hashes file bytes, not
only git HEAD, and line 1 of `.ai-template-origin` stays the source path so an older comparison
does not recopy forever. `config.local/*.json` merges three ways by key; a same-key clash or
any other conflict aborts and writes `sync-conflict.json`. Private and team projects queue instead of isolating.
**Why**: Tests and machines with no config must keep today's behavior. Work MLX is rejected on
write and clamped on read. The history purge of employer specs is still pending; the README
says so. Do not rewrite published history to finish it.

### 📝 `python -m engine.factory_env` runs the wrong code from a project folder

**Date**: 2026-10-23
**Problem**: The hook ran `python -m engine.factory_env` with `PYTHONPATH=<brain>` from inside
the project. `-m` puts the current folder first on `sys.path`, so a project with its own
`engine/` package shadowed the brain's: `No module named engine.factory_env` at best, the
project's code run at worst.
**Solution**: the launcher script `engine/factory-env.py`. Python puts a script's own folder
first, not the caller's, and the launcher adds the brain root.

### 📝 An installed skill copy looked "edited by hand" after its script ran once

**Date**: 2026-10-23
**Problem**: In copy mode a skill script run from the installed copy leaves `__pycache__` there.
The content hash then matched neither the source nor the recorded hash, so the copy was kept
("edited in the installed copy; not overwritten") and never updated again.
**Solution**: `tree_hash` and the stamp's freshness check skip `__pycache__`. Compare the copy
with its source before asking Python (`diff -rq` / `Test-SameDir` first): one Python start per
skill and tool made every install slow on Windows.

### 🐛 `FAIL: origin marker not written` (case 9b, Git Bash only)

**Cause**: the shell passed its skills-root path to native Python as an argument to write on line 1
of `.ai-template-origin`; MSYS converted `/d/Code/x` to `D:/Code/x` on the way. **Fix**: a
value the shell compares later is written by the shell: Python prints the hash only
(`skill-hash`), `_factory_skill_stamp` writes both lines. Any path the shell hands a native
program comes back in Windows spelling.

### 📝 Two writers of `CLAUDE.local.md` rewrote it at every session on Windows

**Date**: 2026-10-23
**Problem**: The PowerShell dev-context step put two blank lines before the kept Factory section,
`apply.py` one. Each session rewrote the file twice and printed `read the Factory section`.
**Solution**: one blank line in both twins, as `apply.py` splices it. Two writers of one file
must produce the same bytes, or each undoes the other.

### 🐛 `TypeError: write_text() got an unexpected keyword argument 'newline'`

**Date**: 2026-10-26
**Cause**: `Path.write_text(newline=)` is Python 3.10+. The engine runs the first `python3` on
PATH, which is `/usr/bin/python3` 3.9 on macOS; uv (tests, CI) ships newer, so nothing caught it.
It crashed `merge-rebase` mid hidden-repo pull ("resolve by hand" on a clean merge) and every
other write in `engine/factory_env`. **Fix**: `textio.write_lf` (`open(newline=)` is 3.0+), and
CI runs the unit tests on 3.9 on macOS. The engine's floor is 3.9: `uvx vermin -t=3.9- engine/`.

### 🐛 `aicf config`: empty root list, "Add folder" does nothing (page loads, `app.js` hangs)

**Date**: 2026-10-29
**Cause**: the settings server was a single-threaded `HTTPServer` speaking HTTP/1.1. A browser
keeps keep-alive sockets idle and opens spare ones ahead of time; the server sat in one idle
socket while `app.js`, `/api/state` or a POST waited on another, until the browser gave up.
Timing-dependent: it worked from Git Bash, hung when started by `aicf.ps1`. An action that
raised anything but `ConfigError` also dropped the connection mid-write (`environment.json`
written, `~/.ai-code-roots` not), so the page only said `Failed to fetch`.
**Fix**: `ThreadingHTTPServer` (`daemon_threads`, `block_on_close = False`) with a lock around
the actions, and every unexpected error answered as JSON 500. Any local page server: one thread
per connection; test it with an idle connection held open.

## External Resources

### Useful Links

- Agent Skills spec: https://agentskills.io/ — SKILL.md format all five tools read
- Anthropic CLAUDE.md→AGENTS.md bridge pattern: the `@AGENTS.md` import in `CLAUDE.md.template`

---

## Future Investigations

**Things to document when we encounter them**:
- [ ] Whether Copilot code-review surface honors AGENTS.md without the .github pointer
- [ ] Auto-detecting Developer Mode on Windows and prompting instead of silently copying
