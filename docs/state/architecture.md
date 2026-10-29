# Architecture — detail

> Read on demand; the index is `.github/PROJECT_STATE.md`.

Five layers, all driven by `templates-manifest.txt`. **No symlinks anywhere** — every file a
project receives is a plain copy, and freshness comes from a **pull at session start**:

1. **Pointer files** (`[POINTERS]`) — identical everywhere, copied into each project and
   re-copied whenever the template changes. The trigger is per project:
   - Claude Code: a `SessionStart` hook in `.claude/settings.json` (itself a pointer) runs
     `sync-ai-templates.sh <project> --quiet --commit --pull --agents --skills`.
   - Other agents: step 1 of the `AGENTS.md` session-start list (also in the global Copilot
     instruction and `.antigravity/rules.md`) tells them to run the same command.
2. **Living docs** (`[LIVING_DOCS]`) — `AGENTS.md`, `PROJECT_STATE.md`, `KNOWLEDGE.md`,
   `.env.example`. Copied once at bootstrap, then owned and filled by each project. The one
   automatic exception is the `--agents` pass (`refresh-agents-sections.py`): `AGENTS.md`
   sections listed in its `GENERIC_HEADINGS` follow the template while the project's text still
   matches some historical template version; a customized section is never touched.
3. **Global skills** — `skills/*/` installed into every tool's global
   skills dir by `engine/install-global.*` (symlinks on macOS/Linux, copies on Windows) and refreshed
   by the session-start `--skills` pass. Own tools are shell commands behind skills, never MCP
   (`mlx-local`, `d3skwebscout`); no MCP server is configured, third-party ones included.
4. **Machine-local state** — `engine/install-global.*` (once per machine) records this repo's path in
   `~/.ai-template-dir` and publishes `AI_TEMPLATE_DIR` + `AI_CODE_ROOT` into
   `~/.claude/settings.json` `env`. Both sit outside every repo, which is the point: the code root
   differs per machine (`~/Code`, `F:\Code`, …) and a committed path would be wrong on the next one.
5. **Private overlay** (optional) — a second repo layered on top of this one so this repo can be
   public and generic. Found via `$AI_TEMPLATE_OVERLAY_DIR` → `~/.ai-template-overlay-dir` →
   sibling `<this-repo>-private`. Same layout: `templates/<src>.template` replaces the base file
   of the same path, `templates/<src>.template.append` is appended to the rendered pointer/living
   doc, an optional `overlay-manifest.txt` adds or replaces entries by destination, `skills/*` are
   installed too and win on a name clash. The old layout (`<src>` at the overlay's root,
   `vscode-global/`) is read after the new paths, with one `ai-sync:` note per run
   (`engine/overlay.sh|.ps1`); installs made from a `vscode-global/skills` source are re-pointed
   by the next `--skills` pass (`engine/sync-skills.sh|.ps1`, tests cases 9d and 15c). `--pull` refreshes both repos. Never holds the engine
   script (the hook's content-based candidate would mistake it for the base).

The sync engine (`sync-ai-templates.sh`/`.ps1`) treats every target the same way (sibling,
this repo itself, or any path): copy pointers that differ, create missing living docs, remove
obsolete files (guarded entries only when byte-identical to their reference template), ensure
`.env` **and `.claude/settings.local.json`** are gitignored, then optionally commit **only those
paths** (`git commit -- <paths>`), refusing mid-merge/rebase. `--pull` runs **first**: it
fast-forwards this repo (and the overlay) from `origin` when the tree is clean, waiting at most
`AI_SYNC_PULL_WAIT` seconds (default 10) so an offline machine still starts at once — past that
the pull finishes in the background and the next run sees it. When `HEAD` moved, the engine
`exec`s itself again without `--pull`, so the new engine — not the one already in memory —
applies the new templates. A dirty tree, a failed pull or a timeout prints one line even in
`--quiet` mode (the session then runs on the templates on disk). `--agents` runs after the copy.

**Private layer** (detail: the engine header). A project is in one
of four modes: **tracked** (the code repo commits everything — the default outside a code root),
**private** (`--private-layer`, alias `--private-docs`), **team** (`--private-layer` on a repo
with other authors) or **shared** (`--shared`). The mode is the first line of a managed block in
`<git-common-dir>/info/exclude`, else the legacy `.gitignore` markers, else the code root's
registry. The owner's AI layer has two parts, both listed in that block and never in
`.gitignore`:

- **Layer B** — living docs except `.env.example`, plus `docs/state/`, `docs/plans/`, `config.local/` (filtered),
  `.claude/memory/` — versioned in a hidden bare repo `<git-common-dir>/ai-context` (branch
  `<root>/<project>`, same work tree; both spelled as `.ai-root`'s branches and registry spell them,
  so a Linux `CODE/d3skhand` clone shares `Code/D3SKHAND`). Every run fetches, adopts it on a fresh clone, commits,
  rebases and pushes; the `Stop` hook runs that pass alone (`--ai-context-sync`). Safety: a lock,
  the switch pushes the hidden branch before it touches the code repo, a blank doc never
  overwrites a real one, unrelated histories and deletions are refused, `config.local/` is
  filtered, and every network step shares `AI_SYNC_NET_BUDGET` (their wait only, not the local
  work between them).
- **Layer C** — every `[POINTERS]` file, `.claude/`, `CLAUDE.local.md` — rebuilt from the
  templates at each session start.

**Code root** = a folder holding `.ai-root/` (a checkout of the owner's private root repo:
`projects/<name>` registry, `owner-emails`, optional `private-terms.txt`, `dev-context/`) or
`.ai-context-remote` (the hidden repos' remote). `--pull` fast-forwards `.ai-root` (and pushes
it when ahead) before anything reads it; `--root-sync <root>` runs that step alone (D3SKHAND's
Sync all, which also runs `--ai-context-sync` in every project). A work root is declared in
`~/.ai-work-roots` (one folder name or absolute path per line), or `$AI_WORK_ROOTS`
(path-separator list; `none` disables), or `"label": "work"` in the root's
`.ai-root/environment.json`; `install-global --work-root <name-or-path>` appends to
`~/.ai-work-roots`. Under a work root `AI_CONTEXT_REMOTE` can only disable,
`~/.ai-context-remote` is not read, and github.com remotes are refused. **Team** mode is
chosen when the last 2000 commits hold an author outside `owner-emails`: tracked files are
never written, untracked or committed. Private
and team projects point Claude auto memory at `<project>/.claude/memory` and import the
machine's old memory folder once. A project whose mode differs from the registry's (else
`private`) prints one conformance line; `update-projects --check|--migrate` acts on the root.

**Global hook** (`install-global` → `~/.claude/settings.json`): one SessionStart entry
(`--global-hook`) that is a no-op unless the project's parent is a code root and the project's
own `.claude/settings.json` lacks the sync hook — so it never runs twice. A project the registry
knows (or whose exclude block names a mode) gets the full hook-mode sync (restores B, builds C);
any other prints one line suggesting
the switch. There is no global `Stop` hook: the project hook takes over once C is built.
