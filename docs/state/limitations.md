# Known limitations & tech debt — detail

> Read on demand; the index is `.github/PROJECT_STATE.md`.

- [ ] `alveodentaire.com` is an empty placeholder repo — AGENTS.md header carries
      `[NEEDS HUMAN INPUT]` for stack/hosting until the project actually starts.
- [ ] Only generic `AGENTS.md` sections follow the template (the hook's `--agents` pass, 3-way
      safe); customized sections (HomeAssistantAgent / HomeDevOps skills tables, HomeDevOps
      checkpoint policy) and the other living docs must be merged by hand.
- [ ] A skill deleted from `skills/` leaves its installed **copy** behind unless its
      name goes in `skills/RETIRED`; even then only a copy whose `.ai-template-origin`
      names this dir is removed (a renamed, unmarked or other repo's copy might be the user's).
      Dangling links are always removed.
- [ ] Extra skill folders (`overlays` in `environment.json`) are **installed** only from the
      AICodeFactory root's file (`overlay_skill_dirs`); another root's list only turns skills
      on/off. Installing every root's would put a work root's skills in the personal config dir.
- [ ] The hook runs `git commit` in the project at session start — intended (checkpoint
      policy), but a repo without `user.name`/`user.email` gets a one-line
      `ai-sync: git commit failed` note instead.
- [ ] Sibling repos' migration commits are local-only until each repo is pushed to its own
      remote (repos without remotes stay local by design).
- [ ] `install-global` must be run **once per machine** to record `~/.ai-template-dir` and the
      `AI_TEMPLATE_DIR` / `AI_CODE_ROOT` env keys. Until then that machine relies on the relative
      candidates, which already cover any project sitting beside the template repo or one root over.
- [ ] Skills installed by an overlay that is later **unconfigured** (marker/env removed) look like
      another template repo's property to the origin guard and are left in place — neither
      reverted to the base version nor removed. Re-run `install-global --overlay` or delete them
      by hand.
- [ ] An overlay can add or replace manifest entries but cannot **remove** a base entry (there is
      no `[REMOVE]` section) — list the file under `[OBSOLETE]` in `overlay-manifest.txt` only if
      the base no longer ships it as a pointer.
- [ ] The private-terms guard only protects a machine that holds the list, and only shared
      projects already synced there (a fresh clone has no hook until its first sync). A term that
      matches the owner's own commit identity blocks every commit in shared projects — use a
      per-repo `user.email` (e.g. a GitHub noreply address) there. A project with a foreign
      `pre-commit` hook or `core.hooksPath` gets no guard until the hook is renamed
      `pre-commit.local` (chained) — run `--scan-private` before publishing either way.
- [ ] On Windows both test suites skip the symlink cases (4, 7, link halves of 9/9b/15): creating a
      symlink needs Developer Mode or elevation, and Git Bash otherwise fakes `ln -s` by copying.
      Skips are announced, never silent. Full symlink coverage requires a Mac or an elevated shell.
- [ ] Private layer (phase 1) gaps: a `config.local/` inside a wholly untracked folder is not
      found by the filter; a legacy private-docs project that tracks `docs/plans/` pauses its
      hidden sync until switched; a team folder holding any tracked file is left out of the
      exclude block whole.
- [ ] Private layer untested: the network budget across the engine's re-`exec`, an invalid
      `AI_SYNC_NET_BUDGET`, a rebase of a team-tracked file between machines, an unborn `HEAD`,
      the 2000-commit cap, an empty `AI_CONTEXT_REMOTE` under a work root, and PowerShell's
      home-ancestor stop under a symlinked macOS `TMPDIR`.
- [ ] sh/ps1 parity nits: symlinks in `config.local/` (PS `LinkType` vs `-type f -o -type l`);
      PS prints the staged-changes line to stdout (bash: stderr); a few PS lines differ in the
      dash; the `using <root>` path form differs; PowerShell cannot set an empty env var.
- [ ] Claude auto memory: `autoMemoryDirectory` is ignored when
      `permissions.blockReadsOutsideWorkingDirectories` is on; slugs over 200 characters (which
      Claude Code truncates and hashes) and `CLAUDE_CODE_PROJECT_DIR_NAME` are not handled, so
      such a project's old memory is not imported.
- [ ] No global `Stop` hook: a registry-known project's first session is synced by the global
      hook, but its turn edits reach the hidden repo only once the project's own hook exists
      (built by that same sync, so from the next session on).
