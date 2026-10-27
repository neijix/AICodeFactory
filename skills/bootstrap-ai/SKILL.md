---
name: bootstrap-ai
description: "Use when a project has no AGENTS.md / AI instructions yet, still carries <!-- BOOTSTRAP_PENDING --> or [PLACEHOLDER] tokens, uses a legacy copilot-instructions.md or symlink setup, or needs a refresh from the template: copies the AI-tool pointer files, generates and fills AGENTS.md, PROJECT_STATE.md and KNOWLEDGE.md, then commits."
compatibility: Requires git and a local AICodeFactory clone in your code root (falls back to cloning it from GitHub)
metadata:
  argument-hint: "Optional: project type / language hints"
---

# Bootstrap this project with my AI instruction template

Set up the current workspace so **every** AI tool reads the same rules. Do all of this yourself,
then report a short summary. Do not ask for permission unless something is destructive.

## Canonical source of truth
My template repo (single source of truth):
- **Local:** an `AICodeFactory` clone in this machine's code root — `~/Code/AICodeFactory` on
  macOS, `F:\Code\AICodeFactory` on a Windows box. **Never assume `$HOME/Code`**: it does not
  exist on a machine whose repos live off the home volume.
- **Remote (fallback):** `https://github.com/neijix/AICodeFactory.git`

Resolve the template directory `$T` in this order — the same chain the SessionStart hook walks,
so a project bootstrapped here keeps working at every later session start:
1. `$AI_TEMPLATE_DIR` if set (`install-global` sets it per machine).
2. `<project>/../AICodeFactory` — the template repo as a sibling of the project.
3. `<project>/../../Code/AICodeFactory` — the project sits under a *second* root, e.g. work repos
   in `F:\Work\` beside personal ones in `F:\Code\`.
4. `$(cat ~/.ai-template-dir)` — the machine-local marker `install-global` writes.
5. Otherwise `git clone --depth 1` the remote into a temp dir and use that. Copies made from a
   temp clone are perfectly valid (nothing links back to it), but tell the user the session-start
   auto-refresh needs a permanent clone in the code root, and that running its `install-global`
   once on this machine records the marker so every root is covered.

## How files stay in sync — no symlinks

Every shared file is a **plain copy** owned by the project's git history. Freshness comes from
re-running the sync, not from links: `.claude/settings.json` ships a Claude Code `SessionStart`
hook that runs `$T/sync-ai-templates.sh <project> --quiet --commit --pull --agents --skills`, and
`AGENTS.md` tells every other agent to run the same command at session start. The sync copies
pointer files that differ from the template, creates missing living docs, removes obsolete
files, and commits exactly those paths. Never hand-edit a pointer copy — change the
`*.template` in `$T`.

## Needs-bootstrap check

A project **still needs the full bootstrap** (fill + commit) when any of these is true:

1. Root `AGENTS.md` is missing, or is a symlink into the template repo (legacy pointer), **or**
2. Any of these files still contains the literal marker `<!-- BOOTSTRAP_PENDING -->` **at the
   start of a line** (the marker is always emitted on its own line; a backticked mention inside
   prose — e.g. docs quoting the marker — does not count):
   - `AGENTS.md`
   - `.github/PROJECT_STATE.md`
   - `.github/KNOWLEDGE.md`
3. **Or** (belt-and-suspenders for older copies without the marker) any of those files still
   contains an unfilled token matching `\[[A-Z][A-Z0-9_]{2,}\]` — e.g. `[PROJECT_NAME]`,
   `[PRIMARY_LANGUAGE]`, `[FRAMEWORK]`. Ignore `[NEEDS HUMAN INPUT]` (that is intentional), and
   use judgment: a token quoted in backticks as documentation (common in filled KNOWLEDGE.md
   entries, or in the template repo itself) is not an unfilled placeholder.

Quick check:

```bash
rg -n '^<!-- BOOTSTRAP_PENDING -->|\[[A-Z][A-Z0-9_]{2,}\]' \
  AGENTS.md .github/PROJECT_STATE.md .github/KNOWLEDGE.md 2>/dev/null
```

## Steps

1. **Guard** — If `AGENTS.md` exists as a real file and the needs-bootstrap check is **false**,
   the project is already bootstrapped: skip straight to step 3 (still worth re-running — it
   refreshes pointer copies, migrates leftover symlinks and cleans up obsolete files), then
   report. Do **not** re-fill living docs.

2. **Init git** — If there is no `.git` directory, run `git init`.

3. **Sync templates** — Run `$T/sync-ai-templates.sh "$(pwd)"` (Windows PowerShell:
   `$T\sync-ai-templates.ps1 (Get-Location)`). This is the single source of truth for which
   files go where — do not hand-roll the file list; the manifest
   (`$T/templates-manifest.txt`) is authoritative. It:
   - Copies every AI-tool pointer file from `$T` (creating, updating, or replacing an old
     symlink — including the text-file leftovers a Windows checkout makes of symlinks).
   - Creates living docs (`AGENTS.md`, `.github/PROJECT_STATE.md`, `.github/KNOWLEDGE.md`,
     `.env.example`) from the templates **only if they don't already exist** — and migrates a
     leftover `AGENTS.md` pointer symlink into an owned copy.
   - Removes obsolete files (old launcher scripts, `GEMINI.md`,
     `.cursor/rules/project.mdc`, an unmodified per-project
     `.mcp.json`) — never touches project source.
   - Ensures `.env` is gitignored.

   Add `--dry-run` first if you want to show the plan. Don't pass `--commit` here — step 11
   makes one bootstrap commit for everything.

   **Already-bootstrapped project?** The session-start hook's `--agents` pass already carries
   template improvements into its owned `AGENTS.md`; to see the plan (and the `KEPT` sections
   it will never touch) run `uv run $T/skills/bootstrap-ai/scripts/refresh-agents-sections.py
   "$(pwd)" --dry-run` (then without `--dry-run`, add `--commit` to commit `AGENTS.md`). It
   replaces only the *generic* sections (session start, bootstrap mode, checkpoint policy,
   on-demand skills, delegation, living documents) and only when the project's text still
   matches some historical version of the template — a customized section is reported as
   `KEPT` and left for you to merge by hand. `--all` does every bootstrapped sibling. No
   `./check.sh`, or no CI workflow running it? Add them as step 7 describes.

4. **Migrate legacy projects** — If `.github/copilot-instructions.md` is a **filled legacy
   master** (large file, no `BOOTSTRAP_PENDING`, contains project-specific sections) while
   `AGENTS.md` is still the fresh template:
   1. Carry over everything project-specific from it: header (type/language/framework),
      core-rule choices, taste rules and "Project-specific notes" into `AGENTS.md`; project
      structure and key commands into `.github/PROJECT_STATE.md` (Architecture / Key
      Commands). Keep `AGENTS.md` **slim** — only what an agent cannot derive from the code:
      generic procedures live in the shared skills (`tech-research`, the secrets skill,
      `launch-and-deploy`) — do not copy those sections over.
   2. Re-run step 3 so `.github/copilot-instructions.md` becomes the thin pointer copy again
      (it is a pointer file now, refreshed on every sync).
   3. Leave `PROJECT_STATE.md` / `KNOWLEDGE.md` untouched — they carry over as-is.

5. **Scan the codebase** — Read `package.json`, `requirements.txt`, `pyproject.toml`, `*.csproj`,
   `go.mod`, `Cargo.toml`, `Dockerfile`, `README.md`, and key entry points to determine: project
   type, primary language, framework, key commands, and architecture. If no `.gitignore` exists
   yet, add one appropriate to the detected language/framework.

6. **Fill placeholders** — Replace every unfilled token in `AGENTS.md`,
   `.github/PROJECT_STATE.md`, and `.github/KNOWLEDGE.md` (`[PROJECT_NAME]`,
   `[PRIMARY_LANGUAGE]`, `[FRAMEWORK]`, project type, conventions, commands, structure, etc.)
   with discovered values. Use the current folder name for `[PROJECT_NAME]` if it wasn't
   already filled. Leave a clearly marked `[NEEDS HUMAN INPUT]` note only for true secrets/URLs
   you cannot infer. **Remove every `<!-- BOOTSTRAP_PENDING -->` marker** once the living docs
   are filled. (The pointer copies have no placeholders — that's the point.)

7. **Write `.github/PROJECT_STATE.md`** — What the project does, architecture overview, key
   commands, required env vars, and the **Audience** line (`public` by default under a personal
   root, `team` under a work root, `owner-only` only with a stated reason — `portable-project`
   skill; run its scanner and list what it finds in `docs/state/limitations.md`). No
   dates/history — git handles that. It is loaded into **every
   session**: keep it an index of **≤ ~80 lines / 6 KB**; features, known limitations and other
   per-area detail go in `docs/state/<area>.md` (`features.md`, `limitations.md`, …), linked from
   its **Detail** table.

   **`./check.sh`** — create a root `check.sh` (+ `check.ps1` if the project is cross-platform)
   that runs the project's lint + tests and exits non-zero on any failure (nothing to check yet →
   a stub that says so and exits 0). It must finish in ~5 min: slower tests go behind
   `./check.sh --full` (`test-tiers` skill). Name it in the AGENTS.md **Testing** rule and under
   PROJECT_STATE Key Commands; it is the one gate every agent and the `verifier` subagent run.
   Where the language has a type checker (pyright/mypy, `tsc --noEmit`, …), run it from
   `check.sh` too — strict at least on the modules other modules depend on (events, DTOs,
   schemas): typed boundaries are the contracts agents read. If the project parses another
   CLI's output or an external API, seed `tests/fixtures/` with one recorded real sample per
   source and a replay test (the **Testing** rule).

   **CI** — if the project has a GitHub remote, add `.github/workflows/check.yml` that runs
   `./check.sh --full` (`check.ps1` on Windows runners) on every push to the default branch, one job
   per OS the project actually ships on (an OS-specific bug is only caught on that OS). Agents
   commit on every response; CI is what checks those commits when nobody is watching. Filter
   `paths:` so docs-only commits skip it on a private repo (macOS minutes bill at 10x).

8. **Initialize `.github/KNOWLEDGE.md`** — Replace the `## <Area>` placeholder with one heading
   per component, subsystem or tool (from the code's own layout), then add entries for any
   non-obvious patterns or decisions found.

9. **Launcher + fixed port** — If this project is (or will be) locally startable with a
   long-lived process, make sure it has a one-command start script (root `start.sh` +
   `start.ps1`) and a **fixed** listen port (never random / auto-increment; document it in
   `.env.example` + `PROJECT_STATE.md`), and document them under Key Commands. Pure libraries /
   docs-only / template / one-shot repos may skip. Follow the
   `launch-and-deploy` skill: ship macOS `start.command` + `stop.command` + `kill.command`
   (graceful vs force; port-based cleanup), opt it into the owner's launcher or tray app when
   one is in use (its skill says how), keep the port unique across the code root, and document
   the triad under Key Commands. If it needs
   another of the owner's repos at runtime, prefer a package or an optional integration
   (`portable-project`); only a public repo that cannot be one goes in `sibling-deps.txt`, with
   `scripts/sibling-deps.*` wired into install / start / update (same skill).

10. **Self-check** — Re-run the needs-bootstrap check. It must now be **false**. If anything
    remains, finish filling before committing.

11. **Commit** — `git add -A && git commit -m "docs: bootstrap project documentation"`.

12. **Report** — Confirm every pointer file is a real file identical to its template (no
    symlinks left: `find . -maxdepth 3 -type l -not -path './.git/*'` should list none of
    them), confirm `AGENTS.md` is a real owned file, list what was discovered/filled/migrated,
    whether the project has a launcher (and is opted into a launcher app, if one is in use), and
    flag any `[NEEDS HUMAN INPUT]` items.

## Alternative: from the terminal

For bootstrapping a brand-new project, or refreshing one or many existing ones, in one command
instead of a chat session, use `$T/bin/aicf init <name>` or `$T/bin/aicf update [name]`
(same engine as step 3). See `$T/README.md`.

After this, the project's own root `AGENTS.md` becomes the source of truth for all future
sessions — every tool reads it natively or through a thin wrapper, and the shared files stay
fresh through the session-start sync.
