#!/usr/bin/env bash
# sync-ai-templates.sh — shared engine that keeps one project's AI-instruction files in step
# with this template repo. NO SYMLINKS: every file is a plain copy, so the result is identical
# on macOS, Linux, Windows (Git Bash) and in server-side clones that never see this repo.
#
#   pointer files  (manifest [POINTERS])     copied whenever they differ from the template
#   living docs    (manifest [LIVING_DOCS])  created once, then owned by the project
#   obsolete files (manifest [OBSOLETE])     removed (guarded entries only when unmodified)
#   git hooks      (manifest [SHARED_HOOKS]) every mode but tracked, into .git/hooks (untracked)
#
# Project modes: tracked (default — the code repo commits everything), private (--private-layer),
# shared (--shared), team (--private-layer on a repo with other authors). The mode is the first
# line of the managed block in <git-common-dir>/info/exclude ("# ai-templates: <mode>" …
# "# ai-templates: end"); without one, the legacy .gitignore markers ("# ai-templates: private AI
# docs" → private, "# ai-templates: local-only" → shared); else the code root's registry; else
# tracked.
#
# Code root: the folder holding the project (the parent of its git top level) when it holds
# .ai-root/ or .ai-context-remote. Its .ai-root/ is a git checkout of the owner's private root
# repo: projects/<name> records each project's mode ("mode=" and "origin=" lines; matched by
# folder name, else by normalized origin), written and pushed when --private-layer or --shared
# applies (lock, rebase, a commit of that file alone, never on --dry-run); it also holds
# private-terms.txt and dev-context/ (the only place the engine reads them). The hidden repo's remote and owner-emails
# come from the nearest folder above the project holding either (Root/group/proj finds Root).
#
# Usage (standalone):
#   sync-ai-templates.sh [<project-dir>] [--dry-run] [--commit] [--quiet] [--pull] [--agents] [--skills] [--shared|--private-layer]
#   sync-ai-templates.sh [<project-dir>] --ai-context-sync [--quiet]
#   sync-ai-templates.sh <code-root> --root-sync [--quiet]
#   sync-ai-templates.sh [<project-dir>] --scan-private [--history]
#   sync-ai-templates.sh [<project-dir>] --global-hook
#     --dry-run   print the plan, write nothing
#     --commit    commit only the files this run changed (paths-only commit — other work in
#                 the project stays untouched and uncommitted)
#     --quiet     hook mode: print one line when something changed, nothing otherwise.
#                 A project that has a dev-context pack also prints one
#                 `ai-sync: dev-context` line (see below) — that line is not a file change.
#     --push      after --commit, push that commit when the branch has an upstream. Off by
#                 default and never enabled by the session-start hook: pushing is the user's
#                 call, not a side effect of opening an editor.
#     --pull      `git pull --ff-only` of this template repo (and the overlay) FIRST, so this run
#                 uses the latest templates: only when its working tree is clean, and bounded —
#                 after $AI_SYNC_PULL_WAIT seconds (default 10; offline, slow network) the pull
#                 carries on in the background and this run uses what is on disk. When the pull
#                 moved the repo, the engine re-runs itself so the new engine applies too.
#                 Before that, once per run: the code root's .ai-root, fast-forwarded the same
#                 way and pushed when it is ahead (a registry commit whose push failed).
#                 Every network step of a run (these pulls, the .ai-root push, the hidden repo's
#                 ls-remote, fetch and push) shares one budget of $AI_SYNC_NET_BUDGET seconds
#                 of waiting (default 30), the re-run included; the local work between them
#                 does not count. After the first step that timed out, the rest are skipped.
#     --agents    also carry the template's generic AGENTS.md sections into the project
#                 (bootstrap-ai/scripts/refresh-agents-sections.py: only sections never
#                 customized, plus a missing ## Taste scaffold; shared projects and an AGENTS.md
#                 with uncommitted edits are left alone; in a private or team project the file
#                 is edited but never committed to the code repo). Needs uv or python3, else a
#                 no-op.
#     --skills    refresh the global skill folders (~/.claude/skills, ~/.agents/skills, …)
#                 from skills/ — symlinks on macOS/Linux, copies on Windows
#                 (override with AI_SKILLS_MODE=copy|link)
#     --shared    turn the project into a SHARED project (a repo other people clone): pointer
#                 files become local-only — gitignored under the "# ai-templates: local-only"
#                 line and untracked (they stay on disk). Needs an empty index; with --commit
#                 the switch is one commit. Later runs see that line and keep it that way.
#                 Shared projects also get the private-terms pre-commit hook (see
#                 git-hooks/pre-commit.sh.template): a commit adding one of the owner's private
#                 terms is refused. The list lives outside every repo — $AI_PRIVATE_TERMS_FILE,
#                 <code root>/.ai-root/private-terms.txt, ~/.private-terms.
#     --private-layer  turn the project PRIVATE: the owner's personal AI layer leaves the code
#                 repo. Layer B (living docs except .env.example, docs/state/, docs/plans/,
#                 config.local/, .claude/memory/) is versioned in a hidden repo instead; layer C
#                 (every [POINTERS] file, .claude/, CLAUDE.local.md) is rebuilt from the
#                 templates. Both are listed in the managed block of .git/info/exclude (anchored
#                 paths; config.local/ at any depth), never in .gitignore, which keeps only .env,
#                 .claude/settings.local.json and CLAUDE.local.md. The switch removes the legacy
#                 marker lines and the paths the engine listed under them from .gitignore (no
#                 other line), and untracks the B and C paths git still tracks (files stay on
#                 disk). Needs an empty index; with --commit it is one commit, "chore: move the
#                 personal AI layer out of the repo (private layer)". A later plain run keeps the
#                 block fresh and says when git still tracks a layer path. Private projects get
#                 the private-terms pre-commit hook too.
#                 TEAM instead of private when the repo's history (last 2000 commits) holds an
#                 author outside <code root>/.ai-root/owner-emails and its user.email (bots
#                 ignored; see _team_classify): its tracked files stay exactly as they are —
#                 never written, untracked or committed, .gitignore never gets a line — and the
#                 block lists only the B and C paths it does not track (plus .env when nothing
#                 ignores it yet). The switch commits only the legacy .gitignore cleanup, if any.
#                 The hidden repo (.git/ai-context, branch <root>/<project>) is committed, rebased
#                 and pushed by every later run to the owner's private remote —
#                 $AI_CONTEXT_REMOTE, else <code root>/.ai-context-remote, else
#                 ~/.ai-context-remote (legacy; install-global writes the root's); none = local only.
#                 Under a work root (_is_work_path) only the root's file counts: $AI_CONTEXT_REMOTE
#                 can only disable it, ~/.ai-context-remote is never read, a github.com URL is
#                 refused (one line each; local only). A fresh clone on another machine gets the
#                 docs back at its first run. The switch pushes the hidden branch first: until
#                 the remote has it, the code repo is left exactly as it was (one line; re-run).
#                 Safety rules of the hidden repo: see ai_context_sync and _aic_commit.
#                 Memory (private and team only): .claude/settings.local.json gains
#                 autoMemoryDirectory, an absolute forward-slash path to
#                 <project>/.claude/memory. Once per machine, after the hidden repo is
#                 restored, ~/.claude/projects/<slug>/memory is imported (missing files
#                 copied, differing ones under imported-<host>/, MEMORY.md union of lines).
#                 A tracked project gets no key, nor a team repo tracking settings.local.json.
#                 See _memory_settings and _aic_import_memory.
#                 Conformance (no network; a --private-layer / --shared switch is already the
#                 fix): in a code root the expected mode is the registry's, else private, and
#                 team conforms; the right mode with layer files still tracked does not. A
#                 miss prints one ai-sync: line with the switch command, in --quiet too.
#                 Syncing this template repo names this root's non-conforming projects and
#                 only counts a sibling root's. See _conform_line.
#     --private-docs  alias of --private-layer (its former name).
#     --ai-context-sync  sync nothing else: only that hidden repo (the Stop hook's call).
#     --root-sync  sync nothing else: <code-root>/.ai-root alone, the --pull step on its own
#                 (bounded pull --ff-only, push when ahead, under its lock; D3SKHAND's Sync all).
#     --scan-private  sync nothing: check the project's tracked files against that list
#                 (exit 1 on a hit); --history also every commit on every ref. Before publishing.
#     --global-hook  the global SessionStart hook's call (templates/global/claude-global-hook.json,
#                 merged into ~/.claude/settings.json by install-global; there is no global Stop
#                 hook). In a code root, a project whose .claude/settings.json lacks the sync hook
#                 (a fresh clone of a private project) gets the project hook's run (--quiet
#                 --commit --pull --agents --skills) when the registry knows it or it has a mode,
#                 else one conformance line. A silent no-op everywhere else; other flags are
#                 ignored. See _global_hook_plan.
#
# Dev context (never in the project's repo): <code root>/.ai-root/dev-context/, read when it holds
# rules.md or settings.json. rules.md is development rules; settings.json is optional and holds
# no credentials. Scope: environment.json "label", else its "kind", else work under a work root,
# else personal inside a code root (no scope, no pack — whatever the root holds).
# The sync writes gitignored CLAUDE.local.md when that file is absent or already ours, and a
# --quiet run prints one line telling the agent to read it. No pack: print nothing and remove a
# file we wrote. An unreadable pack file
# (a cloud placeholder) is one line and never fails the run.
#
# Overlay (optional): a second repo — typically private — layered on top of this one so the
# public template stays generic while personal skills, rules and configs still reach every
# machine. Found via $AI_TEMPLATE_OVERLAY_DIR, then ~/.ai-template-overlay-dir, then the sibling
# folder <this-repo>-private. AI_TEMPLATE_OVERLAY_DIR=none (or empty) disables the lookup
# altogether — what the test suites do. Inside the overlay, the same layout applies:
#   templates/<x>.template    replaces the base file of the same name (any manifest entry)
#   templates/<x>.template.append  appended to the rendered file (pointers and living docs alike)
#   overlay-manifest.txt      optional, same format: adds entries, or replaces the base entry
#                             that targets the same destination
#   skills/*                  installed with --skills; wins over a base skill of the same name
# The old overlay layout (<x>.template at its root, vscode-global/) is still read, second.
#
# Every project runs this at session start: Claude Code via the SessionStart hook shipped in
# .claude/settings.json, other agents via the "Session start" step in AGENTS.md. engine/new-project.sh,
# update-projects.sh, install-global.sh and doctor.sh source this file and call its functions.

set -euo pipefail

TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_NAME="$(basename "$TEMPLATE_DIR")"
MANIFEST_FILE="$TEMPLATE_DIR/templates-manifest.txt"
SKILLS_SRC="$TEMPLATE_DIR/skills"

# Overlay repo (see header). Empty when none is configured or found. A configured path that
# does not exist is reported once and ignored — a missing overlay must never break a session.
OVERLAY_DIR=""
OVERLAY_NAME=""
OVERLAY_MARKER="$HOME/.ai-template-overlay-dir"
_ov_candidate=""
if [ "${AI_TEMPLATE_OVERLAY_DIR+set}" = set ]; then
  case "$AI_TEMPLATE_OVERLAY_DIR" in
    ""|none) : ;;                          # explicit opt-out: no marker, no sibling lookup
    *) _ov_candidate="$AI_TEMPLATE_OVERLAY_DIR" ;;
  esac
elif [ -s "$OVERLAY_MARKER" ]; then
  _ov_candidate="$(head -n1 "$OVERLAY_MARKER" | tr -d '\r')"
elif [ -d "$TEMPLATE_DIR/../$TEMPLATE_NAME-private" ]; then
  _ov_candidate="$TEMPLATE_DIR/../$TEMPLATE_NAME-private"
fi
if [ -n "$_ov_candidate" ]; then
  # `cd` may fail on a dir that stats but cannot be entered — never let set -e kill the engine.
  if OVERLAY_DIR="$(cd "$_ov_candidate" 2>/dev/null && pwd)" && [ -n "$OVERLAY_DIR" ]; then
    OVERLAY_NAME="$(basename "$OVERLAY_DIR")"
  else
    OVERLAY_DIR=""
    echo "ai-sync: overlay $_ov_candidate not found — using $TEMPLATE_NAME alone"
  fi
fi
unset _ov_candidate
# Its layout, templates (_tpl, _render) and per-target choice: engine/overlay.sh.
. "$TEMPLATE_DIR/engine/overlay.sh"
# Label used in the one-line --quiet summary.
SOURCE_LABEL="$TEMPLATE_NAME${OVERLAY_NAME:++$OVERLAY_NAME}"
# Every tool's global skills dir (Agent Skills open standard + per-tool locations).
SKILL_ROOTS=(
  "$HOME/.agents/skills"
  "$HOME/.claude/skills"
  "$HOME/.copilot/skills"
  "$HOME/.cursor/skills"
  "$HOME/.gemini/config/skills"
)
# _profile_skill_roots — add <config-dir>/skills of every Claude Code profile install-global
# recorded in ~/.claude-profiles ("<root><TAB><config-dir>" per line) whose dir exists, once each.
_profile_skill_roots() {
  local root dir s have
  [ -n "${HOME:-}" ] && [ -r "$HOME/.claude-profiles" ] || return 0
  while IFS=$'\t' read -r root dir <&3; do
    dir="${dir%$'\r'}"
    [ -n "$dir" ] && [ -d "$dir" ] || continue
    have=false
    for s in "${SKILL_ROOTS[@]}"; do [ "$s" = "$dir/skills" ] && have=true; done
    [ "$have" = true ] || SKILL_ROOTS+=("$dir/skills")
  done 3< "$HOME/.claude-profiles"
  return 0
}
_profile_skill_roots

# Skills: symlinks are live-editable and work fine on macOS/Linux; on Windows they need
# Developer Mode, so copy there (the session-start --skills refresh keeps copies fresh).
case "$(uname -s 2>/dev/null || true)" in
  MINGW*|MSYS*|CYGWIN*) SKILL_MODE_DEFAULT=copy; ON_WINDOWS=true ;;
  *)                    SKILL_MODE_DEFAULT=link; ON_WINDOWS=false ;;
esac
SKILL_MODE="${AI_SKILLS_MODE:-$SKILL_MODE_DEFAULT}"
# Marker written into copied skill folders so two template repos that ship a skill with the
# same name (e.g. this repo and a downstream fork) never fight over ~/.claude/skills/<name>.
SKILL_ORIGIN_FILE=".ai-template-origin"
# Names a skills dir no longer ships; the sync removes our copies of them (see refresh_global_skills).
SKILL_RETIRED_FILE="RETIRED"
# A project whose .gitignore holds this exact line is SHARED: its pointer files are personal
# tooling, kept on disk and gitignored, never committed (see --shared).
SHARED_SENTINEL="# ai-templates: local-only"
# Legacy (before --private-layer): a .gitignore holding this line put the project in private
# mode. --private-layer removes it, with the paths the engine listed under it.
PRIVATE_DOCS_MARK="# ai-templates: private AI docs"
# The managed block in <git-common-dir>/info/exclude: "# ai-templates: <mode>" first, then the
# private layer's paths, then this line. Rewritten whole; the mode line is the project's mode.
EXCLUDE_END="# ai-templates: end"
# Commit message of the switch to the private layer (one commit: untrack + .gitignore cleanup).
PRIVATE_LAYER_MSG="chore: move the personal AI layer out of the repo (private layer)"
# First lines of a hook this engine installed ([SHARED_HOOKS]); a hook without it is foreign.
HOOK_MARKER="# ai-templates: managed git hook"

if [ ! -f "$MANIFEST_FILE" ]; then
  echo "Error: $MANIFEST_FILE not found." >&2
  exit 1
fi

POINTER_MAP=()
LIVING_DOCS_MAP=()
OBSOLETE_MAP=()
SHARED_HOOK_MAP=()

# _drop_entry <map-name> <dest> — remove every entry of the named map that targets <dest>.
# Bash 3.2: no associative arrays and no namerefs, so these go through eval on a fixed name.
_drop_entry() {
  local map="$1" key="$2" other i n
  local kept=()
  eval "n=\${#${map}[@]}"
  i=0
  while [ "$i" -lt "$n" ]; do
    eval "other=\${${map}[$i]}"
    [ "${other#*|}" = "$key" ] || kept+=("$other")
    i=$((i + 1))
  done
  eval "$map=(\${kept[@]+\"\${kept[@]}\"})"
}

# _merge_entry <map-name> <entry> <key-side> — append <entry> to the named map, replacing an
# existing entry with the same key (dest for pointers/living docs, path for obsolete). A
# destination can be a pointer OR a living doc, never both: a dest-keyed entry also evicts the
# same destination from the other dest-keyed map, so an overlay can change a file's class.
_merge_entry() {
  local map="$1" entry="$2" side="$3" key other i n
  if [ "$side" = dest ]; then key="${entry#*|}"; else key="${entry%%|*}"; fi
  if [ "$side" = dest ]; then
    case "$map" in
      POINTER_MAP)     _drop_entry LIVING_DOCS_MAP "$key" ;;
      LIVING_DOCS_MAP) _drop_entry POINTER_MAP "$key" ;;
    esac
  fi
  eval "n=\${#${map}[@]}"
  i=0
  while [ "$i" -lt "$n" ]; do
    eval "other=\${${map}[$i]}"
    if [ "$side" = dest ]; then other="${other#*|}"; else other="${other%%|*}"; fi
    if [ "$other" = "$key" ]; then
      eval "${map}[$i]=\"\$entry\""
      return 0
    fi
    i=$((i + 1))
  done
  eval "$map+=(\"\$entry\")"
}

# _read_manifest <file> — parse one manifest into the three maps (merging by destination).
_read_manifest() {
  local file="$1" line current_section=""
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"   # tolerate CRLF checkouts on Windows
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    if [[ "$line" =~ ^\[(.*)\]$ ]]; then
      current_section="${BASH_REMATCH[1]}"
      continue
    fi
    case "$current_section" in
      POINTERS)    _merge_entry POINTER_MAP "$line" dest ;;
      LIVING_DOCS) _merge_entry LIVING_DOCS_MAP "$line" dest ;;
      OBSOLETE)    _merge_entry OBSOLETE_MAP "$line" path ;;
      SHARED_HOOKS) _merge_entry SHARED_HOOK_MAP "$line" dest ;;
    esac
  done < "$file"
}

_read_manifest "$MANIFEST_FILE"
[ -n "$OVERLAY_MANIFEST_FILE" ] && [ -f "$OVERLAY_MANIFEST_FILE" ] && _read_manifest "$OVERLAY_MANIFEST_FILE"

SYNC_QUIET=false
SYNC_CHANGED=()          # project-relative paths touched by the last sync_ai_templates call
SYNC_BOOTSTRAPPED=false  # true when living docs were created (first bootstrap)
SYNC_COMMITTED=false
SYNC_PUSHED=false
SYNC_UNTRACKED=()        # paths --shared / --private-layer removed from the index (commit records it)
SYNC_SWITCH_MSG=""       # commit message of that switch (set with SYNC_UNTRACKED)
SYNC_HOOKS=()            # "action hook" notes from the last _sync_shared_hooks (never committed)
SYNC_EXCLUDE=false       # true when the last sync changed the info/exclude block (never committed)
SYNC_SWITCH_WAITS=false  # true when the last --private-layer switch waited for the remote (nothing changed)

_say() { [ "$SYNC_QUIET" = true ] || echo "$*"; }

# Context budget: the files a project's CLAUDE.md @imports ride along in EVERY session, so an
# oversized one silently costs tokens forever. Warn (one line per file, even with --quiet and
# --dry-run) but never fail. Import list = the relative `@path` lines of the project's CLAUDE.md,
# or AGENTS.md + .github/PROJECT_STATE.md when it has none. AI_CONTEXT_BUDGET_KB overrides 8.
_check_context_budget() {
  local target="$1" kb="${AI_CONTEXT_BUDGET_KB:-8}" imports="" rel bytes
  case "$kb" in ''|*[!0-9]*) kb=8 ;; esac
  if [ -f "$target/CLAUDE.md" ]; then
    imports="$(sed -n 's/^@\([^[:space:]]*\).*$/\1/p' "$target/CLAUDE.md" | tr -d '\r')" || imports=""
  fi
  [ -n "$imports" ] || imports="AGENTS.md
.github/PROJECT_STATE.md"
  while IFS= read -r rel; do
    case "$rel" in ''|/*|\~*) continue ;; esac
    rel="${rel#./}"
    [ -f "$target/$rel" ] || continue
    bytes="$(wc -c < "$target/$rel" | tr -d ' ')" || continue
    if [ "$bytes" -gt $((kb * 1024)) ]; then
      echo "ai-sync: context budget: $rel is $(( (bytes + 1023) / 1024 )) KB (> $kb KB), loaded into every session — move detail to docs/state/*.md and keep an index"
    fi
  done <<IMPORTS
$imports
IMPORTS
  return 0
}

# _git_common_dir <target> — absolute git dir shared by all the repo's worktrees (a submodule's
# lives under the superproject's .git/modules). Prints nothing outside a git work tree.
_git_common_dir() {
  local common
  git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  common="$(git -C "$1" rev-parse --git-common-dir 2>/dev/null)" || return 0
  (cd "$1" && cd "$common" 2>/dev/null && pwd) || true
  return 0
}

# _hooks_dir <target> — absolute hooks folder of the target's repo (shared by all worktrees).
# Prints nothing when the target is not a git work tree.
_hooks_dir() {
  local common
  common="$(_git_common_dir "$1")"
  [ -z "$common" ] || printf '%s/hooks' "$common"
  return 0
}

# _exclude_block_mode <exclude-file> — the mode named by the managed block's first line, or
# nothing when the file holds no block.
_exclude_block_mode() {
  [ -f "$1" ] || return 0
  awk '{ sub(/\r$/, "") }
       /^# ai-templates: (tracked|private|team|shared)[ \t]*$/ { sub(/[ \t]*$/, ""); print substr($0, 17); exit }' \
    "$1" 2>/dev/null || true
}

# _has_line <file> <line>... — true when the file holds one of these exact lines (a CR at the
# end of a line is ignored).
_has_line() {
  local f="$1"; shift
  [ -f "$f" ] || return 1
  awk 'BEGIN { for (i = 2; i < ARGC; i++) want[ARGV[i]] = 1; ARGC = 2 }
       { sub(/\r$/, "") } ($0 in want) { found = 1; exit } END { exit !found }' "$f" "$@" 2>/dev/null
}

# _git_top <target> — absolute top level of the target's work tree, or nothing outside git.
_git_top() {
  local top
  top="$(cd "$1" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)" || return 0
  [ -z "$top" ] || (cd "$top" 2>/dev/null && pwd) || true
  return 0
}

# _code_root <target> — the code root holding the project: the parent folder of its git top
# level, when that folder holds .ai-root/ or .ai-context-remote. Prints nothing otherwise.
_code_root() {
  local top root
  top="$(_git_top "$1")"
  [ -n "$top" ] || return 0
  root="$(dirname "$top")"
  if [ -d "$root/.ai-root" ] || [ -e "$root/.ai-context-remote" ]; then printf '%s\n' "$root"; fi
  return 0
}

# _ancestor_root <target> — the nearest folder above the project's git top level (its parent
# first) holding .ai-root/ or .ai-context-remote, so Root/group/proj finds Root: where the hidden
# repo's remote and the owner's emails come from. The walk stops below $HOME and every folder
# above it ($HOME's .ai-context-remote is the personal fallback, not a root; a sandbox HOME keeps
# the real one out of reach). Paths compared physically (pwd -P). Prints nothing when none does.
# The registry and the dev context keep _code_root (the parent folder only).
_ancestor_root() {
  local d home_p=""
  d="$(_git_top "$1")"
  [ -n "$d" ] || return 0
  d="$(cd "$d" 2>/dev/null && pwd -P)" || return 0
  [ -z "${HOME:-}" ] || home_p="$(cd "$HOME" 2>/dev/null && pwd -P)" || home_p=""
  while [ -n "$d" ] && [ "$d" != / ]; do
    d="${d%/*}"
    [ -n "$d" ] || d=/
    if [ -n "$home_p" ]; then
      case "${home_p%/}/" in "${d%/}/"*) return 0 ;; esac
    fi
    if [ -d "${d%/}/.ai-root" ] || [ -e "${d%/}/.ai-context-remote" ]; then
      printf '%s\n' "$d"
      return 0
    fi
  done
  return 0
}

# _team_classify <target> — true when the project is a TEAM repo: an author email of its last
# 2000 commits (HEAD) is neither the repo's user.email nor listed in <ancestor root>/.ai-root/
# owner-emails (one per line; # comments, blank lines and CRs ignored), compared without case.
# Bot authors (an email holding [bot], noreply@github.com) do not count; no history = not team.
# The history is read whole before awk sees it: an early exit would SIGPIPE git log.
_team_classify() {
  local top root owners="" me emails
  top="$(_git_top "$1")"
  [ -n "$top" ] || return 1
  root="$(_ancestor_root "$top")"
  if [ -n "$root" ] && [ -f "${root%/}/.ai-root/owner-emails" ]; then
    owners="$(awk '{ sub(/\r$/, ""); gsub(/^[ \t]+|[ \t]+$/, "") }
                   $0 != "" && substr($0, 1, 1) != "#" { printf " %s", tolower($0) }' \
      "${root%/}/.ai-root/owner-emails" 2>/dev/null)" || owners=""
  fi
  me="$(git -C "$top" config --get user.email 2>/dev/null)" || me=""
  emails="$(git -C "$top" log -n 2000 --format=%ae HEAD 2>/dev/null)" || return 1
  [ -n "$emails" ] || return 1
  printf '%s\n' "$emails" | awk -v own="$owners " -v me="$me" '
    BEGIN { me = tolower(me); gsub(/^[ \t]+|[ \t]+$/, "", me) }
    { e = tolower($0); sub(/\r$/, "", e); gsub(/^[ \t]+|[ \t]+$/, "", e) }
    e == "" || index(e, "[bot]") || e == "noreply@github.com" || e == me { next }
    index(own, " " e " ") { next }
    { found = 1 }
    END { exit !found }'
}

# _ai_root_checkout <root> — <root>/.ai-root when it is a git checkout of its own (not a folder
# inside another repo); nothing otherwise.
_ai_root_checkout() {
  local air="$1/.ai-root" cdup
  [ -n "$1" ] && [ -d "$air" ] || return 0
  cdup="$(git -C "$air" rev-parse --show-cdup 2>/dev/null)" || return 0
  [ -n "$cdup" ] || printf '%s\n' "$air"
  return 0
}

# _normalize_origin <url> — a remote URL reduced for comparison: lowercase, no https/http/ssh/git
# scheme, no user@ or credentials, git@host:owner/repo → host/owner/repo, no trailing / or .git.
_normalize_origin() {
  local u scheme=false head rest
  u="$(printf '%s' "$1" | tr -d '\r' | tr '[:upper:]' '[:lower:]' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  case "$u" in https://*|http://*|ssh://*|git://*) u="${u#*://}"; scheme=true ;; esac
  head="${u%%/*}"
  rest="${u#"$head"}"
  case "$head" in *@*) head="${head##*@}" ;; esac
  if [ "$scheme" = false ]; then
    case "$head" in *:*) rest="/${head#*:}$rest"; head="${head%%:*}" ;; esac
  fi
  u="$head$rest"
  while :; do
    case "$u" in
      */) u="${u%/}" ;;
      *.git) u="${u%.git}" ;;
      *) break ;;
    esac
  done
  printf '%s\n' "$u"
}

# _registry_value <file> <key> — the value of the file's first "<key>=" line (CR and surrounding
# blanks stripped), or nothing.
_registry_value() {
  [ -f "$1" ] || return 0
  awk -v k="$2=" '{ sub(/\r$/, "") }
       index($0, k) == 1 { v = substr($0, length(k) + 1); gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit }' \
    "$1" 2>/dev/null || true
}

# _registry_entry_mode <file> — the entry's mode= value when it is a valid mode, else nothing.
_registry_entry_mode() {
  local m
  m="$(_registry_value "$1" mode)"
  case "$m" in tracked|private|team|shared) printf '%s\n' "$m" ;; esac
  return 0
}

# _registry_mode <target> — the mode the code root's registry records for the project:
# <root>/.ai-root/projects/<folder name> (any case, _registry_name), else the entry whose origin=
# matches the project's remote.origin.url (both normalized, see _normalize_origin). An invalid
# mode is ignored.
_registry_mode() {
  local root reg top name mode="" origin want f o
  root="$(_code_root "$1")"
  [ -n "$root" ] || return 0
  reg="$root/.ai-root/projects"
  [ -d "$reg" ] || return 0
  top="$(_git_top "$1")"
  name="$(_registry_name "$reg" "$(basename "$top")")"
  mode="$(_registry_entry_mode "$reg/$name")"
  if [ -z "$mode" ]; then
    origin="$(git -C "$top" config --get remote.origin.url 2>/dev/null)" || origin=""
    [ -n "$origin" ] || return 0
    want="$(_normalize_origin "$origin")"
    for f in "$reg"/*; do
      [ -f "$f" ] || continue
      o="$(_registry_value "$f" origin)"
      [ -n "$o" ] && [ "$(_normalize_origin "$o")" = "$want" ] || continue
      mode="$(_registry_entry_mode "$f")"
      [ -z "$mode" ] || break
    done
  fi
  [ -z "$mode" ] || printf '%s\n' "$mode"
  return 0
}

# _project_mode <target> — tracked | private | team | shared. The managed block in
# <git-common-dir>/info/exclude first; else the legacy .gitignore markers (private AI docs →
# private, local-only → shared); else the registry; else tracked.
_project_mode() {
  local target="$1" mode="" common
  common="$(_git_common_dir "$target")"
  [ -z "$common" ] || mode="$(_exclude_block_mode "$common/info/exclude")"
  if [ -z "$mode" ]; then
    if _has_line "$target/.gitignore" "$PRIVATE_DOCS_MARK"; then
      mode=private
    elif _has_line "$target/.gitignore" "$SHARED_SENTINEL"; then
      mode=shared
    fi
  fi
  [ -n "$mode" ] || mode="$(_registry_mode "$target")"
  printf '%s\n' "${mode:-tracked}"
}

# _private_doc_paths — layer B, the paths the hidden repo versions, one per line (folders end
# in /): the living docs except .env.example, docs/state/, docs/plans/, config.local/ (the
# exclude block matches it at any depth), .claude/memory/.
_private_doc_paths() {
  local entry
  for entry in ${LIVING_DOCS_MAP[@]+"${LIVING_DOCS_MAP[@]}"}; do
    [ "${entry#*|}" = ".env.example" ] || printf '%s\n' "${entry#*|}"
  done
  printf '%s\n' "docs/state/" "docs/plans/" "config.local/" ".claude/memory/"
}

# _generated_paths — layer C, rebuilt from the templates on every machine: every [POINTERS]
# path, the whole .claude/ folder, CLAUDE.local.md.
_generated_paths() {
  local entry
  for entry in ${POINTER_MAP[@]+"${POINTER_MAP[@]}"}; do printf '%s\n' "${entry#*|}"; done
  printf '%s\n' ".claude/" "CLAUDE.local.md"
}

# _layer_paths — layers B and C, one per line, without duplicates or paths a listed folder
# already covers (.claude/ covers .claude/settings.json and .claude/memory/).
_layer_paths() {
  local all=() seen="|" p q covered
  while IFS= read -r p; do all+=("$p"); done < <(_private_doc_paths; _generated_paths)
  for p in ${all[@]+"${all[@]}"}; do
    case "$seen" in *"|$p|"*) continue ;; esac
    covered=false
    for q in ${all[@]+"${all[@]}"}; do
      [ "$q" != "$p" ] || continue
      case "$q" in */) case "$p" in "$q"*) covered=true ;; esac ;; esac
    done
    [ "$covered" = true ] && continue
    seen="$seen$p|"
    printf '%s\n' "$p"
  done
}

# _legacy_gitignore_lines — what --shared / --private-docs used to write into .gitignore: both
# marker lines, every [POINTERS] path, the old layer B (living docs except .env.example,
# docs/state/). --private-layer removes exactly these lines, nothing else.
_legacy_gitignore_lines() {
  local entry
  printf '%s\n' "$SHARED_SENTINEL" "$PRIVATE_DOCS_MARK"
  for entry in ${POINTER_MAP[@]+"${POINTER_MAP[@]}"}; do printf '%s\n' "${entry#*|}"; done
  for entry in ${LIVING_DOCS_MAP[@]+"${LIVING_DOCS_MAP[@]}"}; do
    [ "${entry#*|}" = ".env.example" ] || printf '%s\n' "${entry#*|}"
  done
  printf '%s\n' "docs/state/"
}

# _team_tracked <dir> — what a team repo tracks of layers B and C, one file per line: the tracked
# files of every B and C entry (a file, or a folder's files) and of every config.local/ folder at
# any depth. Team mode never writes, untracks or commits them; the hidden repo never adds them.
_team_tracked() {
  local dir="$1" p specs=()
  while IFS= read -r p; do
    [ "$p" = config.local/ ] || specs+=("$p")
  done < <(_private_doc_paths; _generated_paths)
  { [ ${#specs[@]} -eq 0 ] || git -C "$dir" -c core.quotepath=off ls-files -- "${specs[@]}" 2>/dev/null
    git -C "$dir" -c core.quotepath=off ls-files 2>/dev/null | awk 'index("/" $0, "/config.local/")'
  } | awk '!seen[$0]++' || true
}

# _team_has <entry> <tracked> — true when <tracked> (_team_tracked's output) holds the entry: the
# file itself, a file of the folder, or (config.local/) a file of one at any depth.
_team_has() {
  local nl=$'\n'
  case "$1" in
    config.local/) case "$nl$2" in *"${nl}config.local/"*|*"/config.local/"*) return 0 ;; esac ;;
    */) case "$nl$2" in *"$nl$1"*) return 0 ;; esac ;;
    *) case "$nl$2$nl" in *"$nl$1$nl"*) return 0 ;; esac ;;
  esac
  return 1
}

# _team_block_paths <target> <exclude-file> — the team block's paths, one per line: layers B and
# C minus what the repo tracks (a folder holding a tracked file is left out whole, except
# .claude/memory/: a tracked MEMORY.md stays tracked, and the directory pattern still hides the
# untracked personal files), without the paths a kept folder covers; then .env and
# .claude/settings.local.json when the repo neither
# tracks them nor ignores them outside this block (git check-ignore -v: a match on the block's own
# lines in <exclude-file> does not count, so every run gives the same answer).
_team_block_paths() {
  local target="$1" file="$2" tracked p q all=() kept=() seen="|" covered range="" start=0 end=0 v res
  tracked="$(_team_tracked "$target")"
  while IFS= read -r p; do all+=("$p"); done < <(_private_doc_paths; _generated_paths)
  for p in ${all[@]+"${all[@]}"}; do
    case "$seen" in *"|$p|"*) continue ;; esac
    seen="$seen$p|"
    # A tracked file keeps its folder out of the block, except .claude/memory/: the pattern
    # ignores only untracked files, so the team's MEMORY.md stays tracked.
    if [ "$p" = ".claude/memory/" ] || ! _team_has "$p" "$tracked"; then kept+=("$p"); fi
  done
  for p in ${kept[@]+"${kept[@]}"} .env .claude/settings.local.json; do
    covered=false
    for q in ${kept[@]+"${kept[@]}"}; do
      [ "$q" != "$p" ] || continue
      case "$q" in */) case "$p" in "$q"*) covered=true ;; esac ;; esac
    done
    [ "$covered" = false ] || continue
    case "$p" in
      .env|.claude/settings.local.json) ;;
      *) printf '%s\n' "$p"; continue ;;
    esac
    [ -z "$(git -C "$target" ls-files -- "$p" 2>/dev/null)" ] || continue
    if [ -f "$file" ] && [ -z "$range" ]; then
      range="$(awk -v endl="$EXCLUDE_END" '{ sub(/\r$/, "") }
        !s && /^# ai-templates: (tracked|private|team|shared)[ \t]*$/ { s = NR; next }
        s && $0 == endl { e = NR; exit }
        END { if (s) print s, (e ? e : 999999999) }' "$file" 2>/dev/null)" || range=""
      [ -z "$range" ] || { start="${range% *}"; end="${range#* }"; }
    fi
    v="$(git -C "$target" check-ignore -v -- "$p" 2>/dev/null)" || v=""
    if [ -n "$v" ]; then
      res="$(printf '%s\n' "$v" | awk -F'\t' 'NR == 1 { s = $1
        if (!match(s, /:[0-9]+:/)) { print "elsewhere"; exit }
        src = substr(s, 1, RSTART - 1); n = substr(s, RSTART + 1, RLENGTH - 2); pat = substr(s, RSTART + RLENGTH)
        if (substr(pat, 1, 1) == "!") print "none"; else if (src ~ /info\/exclude$/) print n; else print "elsewhere" }')" \
        || res=elsewhere
      case "$res" in
        none) ;;
        ''|*[!0-9]*) continue ;;
        *) [ "$start" -gt 0 ] && [ "$res" -ge "$start" ] && [ "$res" -le "$end" ] || continue ;;
      esac
    fi
    printf '%s\n' "$p"
  done
}

# _exclude_block <mode> <prefix> <target> <exclude-file> — the managed block: the mode line, a
# note, the layer paths anchored at the target (prefix = its path inside the work tree;
# config.local/ unanchored, so an app's folder at any depth matches), the end line. The paths:
# layers B and C (_layer_paths); in team mode only what the repo does not track
# (_team_block_paths, which reads the target and its exclude file).
_exclude_block() {
  local mode="$1" prefix="$2" p
  printf '%s\n' "# ai-templates: $mode" \
    "# Managed by sync-ai-templates (AICodeFactory), rewritten whole: keep your own lines outside it."
  while IFS= read -r p; do
    case "$p" in
      config.local/) printf '%s\n' "$p" ;;
      *) printf '/%s%s\n' "$prefix" "$p" ;;
    esac
  done < <(if [ "$mode" = team ]; then _team_block_paths "$3" "$4"; else _layer_paths; fi)
  printf '%s\n' "$EXCLUDE_END"
}

# _sync_exclude_block <target> <mode> <dry_run> — write or refresh the managed block in
# <git-common-dir>/info/exclude, so git ignores layers B and C without a .gitignore line (works
# in a worktree or a submodule). The block is replaced in place, or appended; lines outside it
# are kept. Written only when the result differs. Sets SYNC_EXCLUDE=true when it changed. A team
# block follows what the repo tracks: rewritten when that changes.
_sync_exclude_block() {
  local target="$1" mode="$2" dry_run="$3" common file prefix block action=modify
  SYNC_EXCLUDE=false
  common="$(_git_common_dir "$target")"
  [ -n "$common" ] || return 0
  file="$common/info/exclude"
  prefix="$(git -C "$target" rev-parse --show-prefix 2>/dev/null)" || prefix=""
  block="$(mktemp "${TMPDIR:-/tmp}/ai-sync-exclude.XXXXXX")"
  _exclude_block "$mode" "$prefix" "$target" "$file" > "$block"
  if [ -f "$file" ]; then
    awk -v endl="$EXCLUDE_END" '
      NR == FNR { blk = blk $0 "\n"; next }
      { l = $0; sub(/\r$/, "", l) }
      skip { if (l == endl) skip = 0; next }
      l ~ /^# ai-templates: (tracked|private|team|shared)[ \t]*$/ { if (!done) printf "%s", blk; done = 1; skip = 1; next }
      { print }
      END { if (!done) printf "%s", blk }' "$block" "$file" > "$block.new" 2>/dev/null \
      || { rm -f "$block" "$block.new"; echo "ai-sync: could not read $file — private layer not excluded"; return 0; }
    if cmp -s "$block.new" "$file"; then
      rm -f "$block" "$block.new"
      return 0
    fi
  else
    action=create
    cp "$block" "$block.new"
  fi
  _say "  [$action] .git/info/exclude"
  SYNC_EXCLUDE=true
  if [ "$dry_run" = false ]; then
    { mkdir -p "$common/info" && cat "$block.new" > "$file"; } 2>/dev/null \
      || echo "ai-sync: could not write $file — private layer not excluded"
  fi
  rm -f "$block" "$block.new"
  return 0
}

# _tracked_layer_paths <target> — the layer B and C paths git still tracks in the target, one per
# line (as the untrack takes them: a folder stays a folder). config.local/ is looked for at any
# depth.
_tracked_layer_paths() {
  local target="$1" p
  while IFS= read -r p; do
    if [ "$p" = "config.local/" ]; then
      git -C "$target" -c core.quotepath=off ls-files 2>/dev/null \
        | awk '{ i = index("/" $0, "/config.local/"); if (i) { p = substr($0, 1, i + 12); if (!(p in seen)) { seen[p] = 1; print p } } }' \
        || true
    elif [ -n "$(git -C "$target" ls-files -- "$p" 2>/dev/null)" ]; then
      printf '%s\n' "$p"
    fi
  done < <(_layer_paths)
}

# _sync_shared_hooks <target> <guard> <dry_run> — [SHARED_HOOKS] into the repo's hooks folder:
# created or refreshed while the project is shared, private or team (anything but tracked),
# removed once it is tracked. Only a hook that carries HOOK_MARKER is ours: a foreign hook of
# the same name is never touched (it can keep
# running — the private-terms hook chains to <name>.local). core.hooksPath means another tool
# owns the hooks: nothing is installed. Hooks live under .git, so nothing here is ever committed.
# The rendered file is written with LF endings whatever the checkout: sh chokes on CR.
_sync_shared_hooks() {
  local target="$1" guard="$2" dry_run="$3" hooks entry name dest rendered action
  SYNC_HOOKS=()
  [ ${#SHARED_HOOK_MAP[@]} -gt 0 ] || return 0
  [ -e "$target/.git" ] || return 0                 # cheap exit for non-repos and subfolders
  hooks="$(_hooks_dir "$target")"
  [ -n "$hooks" ] || return 0
  if [ "$guard" != true ]; then
    for entry in "${SHARED_HOOK_MAP[@]}"; do
      dest="$hooks/${entry#*|}"
      [ -f "$dest" ] && grep -qxF "$HOOK_MARKER" "$dest" 2>/dev/null || continue
      _say "  [remove] .git/hooks/${entry#*|} (tracked project)"
      SYNC_HOOKS+=("removed ${entry#*|}")
      [ "$dry_run" = true ] || rm -f "$dest"
    done
    return 0
  fi
  if [ -n "$(git -C "$target" config core.hooksPath 2>/dev/null)" ]; then
    _say "ai-sync: core.hooksPath is set in $target — private-terms guard not installed"
    return 0
  fi
  rendered="$(mktemp "${TMPDIR:-/tmp}/ai-sync-hook.XXXXXX")"
  for entry in "${SHARED_HOOK_MAP[@]}"; do
    name="${entry#*|}"
    dest="$hooks/$name"
    if [ ! -f "$(_tpl "${entry%%|*}")" ]; then
      echo "warning: template $(_tpl "${entry%%|*}") missing — skipped hook $name" >&2
      continue
    fi
    _render "${entry%%|*}" "$rendered"
    tr -d '\r' < "$rendered" > "$rendered.lf" && mv "$rendered.lf" "$rendered"
    if [ ! -e "$dest" ]; then
      action=create
    elif ! grep -qxF "$HOOK_MARKER" "$dest" 2>/dev/null; then
      _say "ai-sync: $name hook in $target is not ours — left alone; rename it $name.local to keep it and get the private-terms guard"
      continue
    elif cmp -s "$rendered" "$dest"; then
      continue
    else
      action=update
    fi
    _say "  [$action] .git/hooks/$name"
    SYNC_HOOKS+=("${action}d $name")
    [ "$dry_run" = true ] && continue
    { mkdir -p "$hooks" && cp "$rendered" "$dest" && chmod +x "$dest"; } 2>/dev/null \
      || echo "ai-sync: could not write $dest — private-terms guard not installed"
  done
  rm -f "$rendered"
  return 0
}

# scan_private_terms <target> [--history] — run the private-terms check (the [SHARED_HOOKS]
# pre-commit hook, in --scan mode) over the target's tracked files, and with --history over every
# commit. Returns the hook's code: 0 clean or no list, 1 hits, 2 not a git work tree.
scan_private_terms() {
  local target="$1" history="${2:-}" entry src="" tmp rc
  for entry in ${SHARED_HOOK_MAP[@]+"${SHARED_HOOK_MAP[@]}"}; do
    [ "${entry#*|}" = pre-commit ] && src="${entry%%|*}"
  done
  if [ -z "$src" ] || [ ! -f "$(_tpl "$src")" ]; then
    echo "ai-sync: no pre-commit entry under [SHARED_HOOKS] — nothing to scan with" >&2
    return 2
  fi
  tmp="$(mktemp "${TMPDIR:-/tmp}/ai-sync-scan.XXXXXX")"
  _render "$src" "$tmp"
  tr -d '\r' < "$tmp" > "$tmp.lf"
  rc=0
  sh "$tmp.lf" --scan $history "$target" || rc=$?
  rm -f "$tmp" "$tmp.lf"
  return $rc
}

# Commit exactly the paths this run touched. Uses `git commit -- <paths>` so anything else the
# user has in progress (staged or not) is left alone. Refuses to run mid-merge/rebase.
_commit_changes() {
  local target="$1" root gitdir line msg
  SYNC_COMMITTED=false
  [ ${#SYNC_CHANGED[@]} -gt 0 ] || return 0
  root="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)" || return 0
  gitdir="$(git -C "$target" rev-parse --absolute-git-dir 2>/dev/null)" || return 0
  if [ -e "$gitdir/MERGE_HEAD" ] || [ -d "$gitdir/rebase-merge" ] || [ -d "$gitdir/rebase-apply" ]; then
    echo "ai-sync: merge/rebase in progress in $target — synced files left uncommitted"
    return 0
  fi
  local paths=()
  while IFS= read -r line; do
    case "$line" in "D  "*) continue ;; esac   # untracked by --shared: already staged, file stays
    [ -n "$line" ] && paths+=("${line:3}")
  done < <(git -C "$target" status --porcelain --untracked-files=all -- "${SYNC_CHANGED[@]}" 2>/dev/null || true)
  [ ${#paths[@]} -gt 0 ] || [ ${#SYNC_UNTRACKED[@]} -gt 0 ] || return 0
  msg="docs: sync AI instruction templates"
  [ "$SYNC_BOOTSTRAPPED" = true ] && msg="docs: bootstrap project documentation"
  [ -z "$SYNC_SWITCH_MSG" ] || msg="$SYNC_SWITCH_MSG"
  if [ ${#paths[@]} -gt 0 ]; then
    git -C "$root" add -A -- "${paths[@]}" || { echo "ai-sync: git add failed in $root" >&2; return 0; }
  fi
  if [ ${#SYNC_UNTRACKED[@]} -gt 0 ]; then
    # `git commit -- <paths>` would re-add the untracked files from the working tree, so the
    # switch commits the whole index — sync_ai_templates checked it was empty beforehand.
    git -C "$root" commit -q -m "${SYNC_SWITCH_MSG:-chore: keep AI assistant files local-only (shared project)}" \
      || { echo "ai-sync: git commit failed in $root" >&2; return 0; }
  else
    git -C "$root" commit -q -m "$msg" -- "${paths[@]}" || { echo "ai-sync: git commit failed in $root" >&2; return 0; }
  fi
  SYNC_COMMITTED=true
}

# _push_changes <target> — push the commit we just made, when the branch tracks a remote.
_push_changes() {
  local target="$1" root name
  SYNC_PUSHED=false
  root="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)" || return 0
  name="$(basename "$root")"
  if ! git -C "$root" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    _say "ai-sync: $name has no upstream branch — commit stays local"
    return 0
  fi
  if git -C "$root" push -q 2>/dev/null; then
    SYNC_PUSHED=true
  else
    echo "ai-sync: push failed in $name (diverged, offline, or auth) — commit stays local" >&2
  fi
  return 0
}

# ahead_count <dir> — commits on HEAD not on its upstream. Prints a number, or "no-remote"
# when the branch tracks nothing, or "" when the path is not a git repo.
ahead_count() {
  local dir="$1"
  git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  if ! git -C "$dir" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    printf 'no-remote'
    return 0
  fi
  git -C "$dir" rev-list --count '@{u}..HEAD' 2>/dev/null || printf '?'
}

# sync_ai_templates <project-dir> [--dry-run] [--commit] [--quiet] [--push] [--shared|--private-layer]
# (--private-docs is an alias of --private-layer). --private-layer runs the hidden repo's round
# trip itself (the caller skips its own): a switch changes the code repo only once the remote
# holds the hidden branch, else it prints one line and sets SYNC_SWITCH_WAITS=true. A private
# project offline with no hidden commit yet gets no blank living doc (AIC_DOCS_WAIT).
# _expected_mode <target> — the registry's mode, else private, when the project sits in a code
# root. Nothing when it does not: there is no plan to conform to.
_expected_mode() {
  local root mode
  root="$(_code_root "$1")"
  [ -n "$root" ] || return 0
  mode="$(_registry_mode "$1")"
  printf '%s\n' "${mode:-private}"
}

# _conforms <target> — true when there is no plan, the mode is team, or it matches the plan and
# the code repo no longer tracks what that mode's switch untracks (_tracks_layer).
_conforms() {
  local expected actual
  expected="$(_expected_mode "$1")"
  [ -n "$expected" ] || return 0
  actual="$(_project_mode "$1")"
  [ "$actual" = team ] && return 0
  [ "$actual" = "$expected" ] || return 1
  ! _tracks_layer "$1" "$actual"
}

# _tracks_layer <target> <mode> — true when the code repo still tracks a path the mode's switch
# untracks: layers B and C (config.local/ at any depth) when private, the pointer files when
# shared. A mode read from the registry alone says nothing about the index. One git call.
_tracks_layer() {
  local target="$1" p specs=()
  case "$2" in
    private)
      while IFS= read -r p; do specs+=("$p"); done < <(_layer_paths)
      specs+=(':(glob)**/config.local/**') ;;
    shared)
      for p in ${POINTER_MAP[@]+"${POINTER_MAP[@]}"}; do specs+=("${p#*|}"); done ;;
    *) return 1 ;;
  esac
  [ ${#specs[@]} -gt 0 ] || return 1
  [ -n "$(git -C "$target" ls-files -- "${specs[@]}" 2>/dev/null)" ]
}

# _conform_switch <expected> <abs-path> — the command a non-conforming project should re-run.
_conform_switch() {
  case "$1" in
    shared) printf '%s %s --shared --commit\n' "$TEMPLATE_DIR/sync-ai-templates.sh" "$2" ;;
    *) printf '%s %s --private-layer --commit\n' "$TEMPLATE_DIR/sync-ai-templates.sh" "$2" ;;
  esac
}

# _conform_line <target> — one ai-sync: line when a code-root project misses the plan. Quiet
# too: a session start is how the owner hears it. No line outside a code root, and none when
# the mode is already the fix (--private-layer / --shared sets switching).
_conform_line() {
  local target="$1" top name expected cmd
  _conforms "$target" && return 0
  expected="$(_expected_mode "$target")"
  [ -n "$expected" ] || return 0
  # The right mode with layer files still tracked: the sync's own "still tracks" line says it.
  [ "$(_project_mode "$target")" = "$expected" ] && return 0
  top="$(_git_top "$target")"
  [ -n "$top" ] || return 0
  name="$(basename "$top")"
  if [ "$expected" = tracked ]; then
    echo "ai-sync: $name is not on the private-layer plan — registry says tracked"
    return 0
  fi
  cmd="$(_conform_switch "$expected" "$top")"
  echo "ai-sync: $name is not on the private-layer plan — switch: $cmd"
}

# _conform_repos <root> — git repos that are direct children, dot-directories left out.
_conform_repos() {
  local d base
  [ -d "$1" ] || return 0
  for d in "$1"/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"
    base="$(basename "$d")"
    case "$base" in .*) continue ;; esac
    [ -e "$d/.git" ] || continue
    printf '%s\n' "$d"
  done
}

_same_path() {
  local a b
  a="$(cd "$1" 2>/dev/null && pwd -P)" || return 1
  b="$(cd "$2" 2>/dev/null && pwd -P)" || return 1
  [ "$a" = "$b" ]
}

# _conform_report_root <target> — the line this template repo prints instead of its own: the
# names in its code root, and only a count for each sibling root.
_conform_report_root() {
  local root parent d base names="" sibs="" count
  root="$(_code_root "$1")"
  [ -n "$root" ] || return 0
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    _conforms "$d" && continue
    base="$(basename "$d")"
    [ -n "$names" ] && names="$names, "
    names="$names$base"
  done < <(_conform_repos "$root" | LC_ALL=C sort)
  parent="$(dirname "$root")"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    _same_path "$d" "$root" && continue
    { [ -d "$d/.ai-root" ] || [ -e "$d/.ai-context-remote" ]; } || continue
    count=0
    while IFS= read -r repo; do
      [ -n "$repo" ] || continue
      _conforms "$repo" || count=$((count + 1))
    done < <(_conform_repos "$d")
    [ "$count" -gt 0 ] || continue
    base="$(basename "$d")"
    [ -n "$sibs" ] && sibs="$sibs, "
    sibs="$sibs$base: $count"
  done < <(for x in "$parent"/*/; do [ -d "$x" ] && printf '%s\n' "${x%/}"; done | LC_ALL=C sort)
  [ -n "$names" ] || [ -n "$sibs" ] || return 0
  if [ -n "$names" ] && [ -n "$sibs" ]; then
    echo "ai-sync: not on the private-layer plan: $names ($sibs)"
  elif [ -n "$names" ]; then
    echo "ai-sync: not on the private-layer plan: $names"
  else
    echo "ai-sync: not on the private-layer plan: $sibs"
  fi
}

# _global_hook_plan <target> — what the global SessionStart hook (--global-hook) does here: "run"
# (the project hook's full sync), "suggest" (one conformance line) or nothing. Nothing outside
# git, in this template repo, outside a code root (the project's parent holds .ai-root/ or
# .ai-context-remote) and when the project's .claude/settings.json already carries the sync hook
# (that hook runs instead: nothing runs twice). "run" when the registry knows the project, or its
# exclude block or legacy markers name a mode; "suggest" otherwise. No network.
_global_hook_plan() {
  local top
  top="$(_git_top "$1")"
  [ -n "$top" ] || return 0
  if [ -f "$top/sync-ai-templates.sh" ] && [ -f "$top/templates-manifest.txt" ]; then return 0; fi
  if _same_path "$top" "$TEMPLATE_DIR"; then return 0; fi
  [ -n "$(_code_root "$top")" ] || return 0
  if [ -f "$top/.claude/settings.json" ] && grep -qF 'sync-ai-templates.sh' "$top/.claude/settings.json" 2>/dev/null; then
    return 0
  fi
  if [ -n "$(_registry_mode "$top")" ] || [ "$(_project_mode "$top")" != tracked ]; then
    echo run
  else
    echo suggest
  fi
  return 0
}

sync_ai_templates() {
  local target="$1"; shift
  local dry_run=false do_commit=false do_push=false make_shared=false make_private=false arg
  for arg in "$@"; do
    case "$arg" in
      --dry-run) dry_run=true ;;
      --commit)  do_commit=true ;;
      --quiet)   SYNC_QUIET=true ;;
      --push)    do_push=true ;;
      --shared)  make_shared=true ;;
      --private-layer|--private-docs) make_private=true ;;
      *) echo "sync_ai_templates: unknown option '$arg'" >&2; return 2 ;;
    esac
  done
  SYNC_CHANGED=()
  SYNC_BOOTSTRAPPED=false
  SYNC_COMMITTED=false
  SYNC_PUSHED=false
  SYNC_UNTRACKED=()
  SYNC_SWITCH_MSG=""
  SYNC_HOOKS=()
  SYNC_EXCLUDE=false
  SYNC_SWITCH_WAITS=false

  [ "$dry_run" = true ] || mkdir -p "$target"
  _overlay_for "$target"

  # The project's mode (see _project_mode). --private-layer switches a tracked or shared project
  # (or a legacy private-docs one, which has no block yet) to private — or to team when
  # _team_classify finds an author outside the owner's emails; a private or team project keeps
  # its mode (so does a registry entry). --shared switches a tracked one to shared.
  local mode switching=false block_mode
  mode="$(_project_mode "$target")"
  block_mode="$(_exclude_block_mode "$(_git_common_dir "$target")/info/exclude")"
  if [ "$make_private" = true ]; then
    switching=true
    if [ "$mode" = tracked ] || [ "$mode" = shared ] \
       || { [ "$mode" = private ] && [ -z "$block_mode" ] && _has_line "$target/.gitignore" "$PRIVATE_DOCS_MARK"; }; then
      mode=private
      if _team_classify "$target"; then
        mode=team
        _say "  [mode] team (authors outside owner-emails)"
      fi
    fi
  elif [ "$make_shared" = true ] && [ "$mode" = tracked ]; then
    mode=shared
  fi
  [ "$make_shared" = true ] && [ "$mode" = shared ] && switching=true

  # Canonicalize so "." or trailing-slash targets still yield the real folder name
  # (basename "." would otherwise leak into the [PROJECT_NAME] fill).
  local project_name project_name_sed
  if [ -d "$target" ]; then
    project_name="$(basename "$(cd "$target" && pwd)")"
  else
    project_name="$(basename "$target")"
  fi
  project_name_sed="$(printf '%s' "$project_name" | sed 's/[&\\]/\\&/g')"

  # Paths of the private layer (B and C) the code repo still tracks. --private-layer untracks
  # them (files stay on disk) in the same commit as the .gitignore cleanup below; a plain run
  # says how to finish the switch. Team mode never untracks: the team's tracked files are its
  # own (team_tracked, see _team_tracked) and only the legacy .gitignore cleanup is committed.
  local entry rel line tracked=() is_repo=false team_tracked="" gitignore="$target/.gitignore"
  git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1 && is_repo=true
  local blocked=false               # the switch is refused: the index holds someone's work
  if [ "$mode" = private ] && [ "$is_repo" = true ]; then
    while IFS= read -r rel; do tracked+=("$rel"); done < <(_tracked_layer_paths "$target")
    if [ ${#tracked[@]} -gt 0 ] && [ "$switching" = true ] \
       && ! git -C "$target" diff --cached --quiet 2>/dev/null; then
      blocked=true
      echo "ai-sync: $project_name has staged changes — commit or unstage them, then re-run --private-layer" >&2
    fi
  fi
  if [ "$mode" = team ] && [ "$is_repo" = true ]; then
    team_tracked="$(_team_tracked "$target")"
    if [ "$switching" = true ] && _has_line "$gitignore" "$SHARED_SENTINEL" "$PRIVATE_DOCS_MARK" \
       && ! git -C "$target" diff --cached --quiet 2>/dev/null; then
      blocked=true
      echo "ai-sync: $project_name has staged changes — commit or unstage them, then re-run --private-layer" >&2
    fi
  fi

  # Switch order: a switch still to apply (the block does not name the new mode yet, legacy
  # .gitignore markers are left, or a private project still tracks layers B/C) runs the hidden
  # repo's round trip first (ai_context_sync --switch, --team for a team repo), and touches the
  # code repo only once the remote's branch is the hidden HEAD (or no remote is set). Otherwise:
  # one line, and nothing here changes. Never on --dry-run (no network).
  local pending=false docs_wait=false
  if [ "$make_private" = true ] && [ "$dry_run" = false ] && [ "$is_repo" = true ] && [ "$blocked" = false ]; then
    if [ "$switching" = true ] && { [ ${#tracked[@]} -gt 0 ] || [ "$block_mode" != "$mode" ] \
         || _has_line "$gitignore" "$SHARED_SENTINEL" "$PRIVATE_DOCS_MARK"; }; then
      pending=true
    fi
    if [ "$pending" = true ]; then
      if [ "$mode" = team ]; then ai_context_sync "$target" --switch --team; else ai_context_sync "$target" --switch; fi
      if [ "$AIC_SWITCH_READY" != true ]; then
        echo "ai-sync: $project_name: the private-layer switch waits — ${AIC_REMOTE:-the remote} does not have the hidden branch yet; nothing changed in the code repo, re-run --private-layer --commit"
        SYNC_SWITCH_WAITS=true
        return 0
      fi
      for line in ${AIC_NOTES[@]+"${AIC_NOTES[@]}"}; do echo "$line"; done
    else
      ai_context_sync "$target"
    fi
    # Once per switch (never at a session start, which has no --private-layer).
    if [ "$mode" = team ]; then
      echo "ai-sync: $project_name is a team repo (authors outside owner-emails) — its tracked files stay as they are; only untracked personal files are excluded"
    fi
  fi
  # No blank docs: a private project whose hidden repo has no commit yet, with a remote that did
  # not answer this run, waits for the remote's copies instead (.env.example is still created).
  if [ "$mode" = private ] && [ "$AIC_DOCS_WAIT" = true ] && [ "$AIC_TREE" = "$(_git_top "$target")" ]; then
    docs_wait=true
  fi

  # Pointers are rendered (base or overlay file, plus any .append fragment) into one scratch
  # file, compared, then copied — so the project only ever sees the composed result. The scratch
  # is removed after the obsolete pass; only an abort under set -e (a hard failure) leaks it.
  # Team mode: a pointer, living doc or obsolete file the repo tracks is the team's, never
  # written or removed; no .env.example either (it would be a new file in the team's repo).
  local src dest action created_living=false
  local rendered
  rendered="$(mktemp "${TMPDIR:-/tmp}/ai-sync-render.XXXXXX")"
  for entry in ${POINTER_MAP[@]+"${POINTER_MAP[@]}"}; do
    rel="${entry#*|}"
    [ "$mode" != team ] || ! _team_has "$rel" "$team_tracked" || continue
    src="$(_tpl "${entry%%|*}")"
    dest="$target/$rel"
    if [ ! -f "$src" ]; then
      echo "warning: template $src missing — skipped $rel" >&2
      continue
    fi
    _render "${entry%%|*}" "$rendered"
    if [ -L "$dest" ]; then
      action="migrate"            # symlink (live or dangling, or from the old layout) → owned copy
    elif [ ! -e "$dest" ]; then
      action="create"
    elif cmp -s "$rendered" "$dest"; then
      continue
    else
      action="update"
    fi
    _say "  [$action] $rel"
    SYNC_CHANGED+=("$rel")
    [ "$dry_run" = true ] && continue
    mkdir -p "$(dirname "$dest")"
    rm -f "$dest"                 # never cp *through* a symlink onto the template itself
    cp "$rendered" "$dest"
  done

  for entry in ${LIVING_DOCS_MAP[@]+"${LIVING_DOCS_MAP[@]}"}; do
    rel="${entry#*|}"
    if [ "$mode" = team ]; then
      [ "$rel" != .env.example ] && ! _team_has "$rel" "$team_tracked" || continue
    fi
    src="$(_tpl "${entry%%|*}")"
    dest="$target/$rel"
    if [ ! -f "$src" ]; then
      echo "warning: template $src missing — skipped $rel" >&2
      continue
    fi
    if [ -L "$dest" ]; then
      action="migrate"            # leftover pointer symlink from the pre-2026 layout → owned copy
    elif [ -e "$dest" ]; then
      continue                    # owned by the project — never overwritten
    elif [ "$docs_wait" = true ] && [ "$rel" != ".env.example" ]; then
      continue                    # the remote's copy comes first (see docs_wait above)
    else
      action="create"
    fi
    _say "  [$action] $rel"
    SYNC_CHANGED+=("$rel")
    created_living=true
    [ "$dry_run" = true ] && continue
    mkdir -p "$(dirname "$dest")"
    rm -f "$dest"
    _render "${entry%%|*}" "$rendered"
    sed "s/\[PROJECT_NAME\]/$project_name_sed/g" "$rendered" > "$dest"
  done

  # The guard is the reference template as the project received it — rendered, fragment
  # included — otherwise a file that once carried a .append fragment reads as "customized".
  local guard
  for entry in ${OBSOLETE_MAP[@]+"${OBSOLETE_MAP[@]}"}; do
    rel="${entry%%|*}"
    guard=""
    if [ "$entry" != "$rel" ] && [ -f "$(_tpl "${entry#*|}")" ]; then
      _render "${entry#*|}" "$rendered"
      guard="$rendered"
    fi
    dest="$target/$rel"
    if [ "$mode" = team ] && { [ -e "$dest" ] || [ -L "$dest" ]; } \
       && [ -n "$(git -C "$target" ls-files -- "$rel" 2>/dev/null)" ]; then
      continue
    elif [ -L "$dest" ]; then
      :                           # symlink, live or dangling → always safe to remove
    elif [ -e "$dest" ]; then
      if [ -n "$guard" ] && ! cmp -s "$guard" "$dest"; then
        _say "  [keep]   $rel (obsolete but customized — remove by hand if unwanted)"
        continue
      fi
    else
      continue
    fi
    _say "  [remove] $rel (obsolete)"
    SYNC_CHANGED+=("$rel")
    [ "$dry_run" = true ] && continue
    rm -f "$dest"
  done
  rm -f "$rendered"

  # Private layer: layers B and C are hidden from the code repo by the managed block in
  # .git/info/exclude — written before the untrack below, so the switch commit cannot re-add them;
  # never by a refused switch. A team repo's block lists only what the team does not track.
  if { [ "$mode" = private ] || [ "$mode" = team ]; } && ! { [ "$switching" = true ] && [ "$blocked" = true ]; }; then
    _sync_exclude_block "$target" "$mode" "$dry_run"
  fi

  # Machine-local files must never travel between machines: secrets in .env, and per-machine
  # Claude Code permissions (absolute paths, drive letters) in .claude/settings.local.json.
  # A shared project also keeps every pointer file out of git, listed under the sentinel line.
  # A private one lists nothing more here: its layers are in .git/info/exclude. A team repo's
  # .gitignore is the team's: never a line added (its block covers these three).
  local pattern key removed=0
  local missing=() wanted=(".env" ".claude/settings.local.json" "CLAUDE.local.md") legacy=()
  [ "$mode" != team ] || wanted=()
  if [ "$mode" = shared ]; then
    wanted+=("$SHARED_SENTINEL")
    for entry in ${POINTER_MAP[@]+"${POINTER_MAP[@]}"}; do wanted+=("${entry#*|}"); done
  fi
  # Legacy migration (--private-layer only, private or team): drop the markers --shared /
  # --private-docs wrote, with the paths listed under them — nothing else (every user line and
  # the three lines above stay). Written back with LF line ends, the user's own CRs kept.
  if [ "$switching" = true ] && { [ "$mode" = private ] || [ "$mode" = team ]; } && [ "$blocked" = false ] \
     && _has_line "$gitignore" "$SHARED_SENTINEL" "$PRIVATE_DOCS_MARK"; then
    while IFS= read -r line; do legacy+=("$line"); done < <(_legacy_gitignore_lines)
    local stripped hit
    stripped="$(mktemp "${TMPDIR:-/tmp}/ai-sync-gitignore.XXXXXX")"
    while IFS= read -r line || [ -n "$line" ]; do
      key="${line%$'\r'}"
      key="${key%"${key##*[![:space:]]}"}"          # trailing blanks do not make a user line
      hit=false
      for entry in ${legacy[@]+"${legacy[@]}"}; do
        if [ "$key" = "$entry" ]; then hit=true; break; fi
      done
      if [ "$hit" = true ]; then
        removed=$((removed + 1))
        continue
      fi
      printf '%s\n' "$line" >> "$stripped"
    done < "$gitignore"
    if [ "$removed" -gt 0 ]; then
      _say "  [modify] .gitignore (remove $removed legacy line(s))"
      SYNC_CHANGED+=(".gitignore")
      SYNC_SWITCH_MSG="$PRIVATE_LAYER_MSG"
      [ "$dry_run" = true ] || cat "$stripped" > "$gitignore"
    fi
    rm -f "$stripped"
  fi
  for entry in ${wanted[@]+"${wanted[@]}"}; do
    pattern="^$(printf '%s' "$entry" | sed 's/\./\\./g')[[:space:]]*$"
    if [ ! -f "$gitignore" ] || ! grep -q "$pattern" "$gitignore"; then
      missing+=("$entry")
    fi
  done
  if [ ${#missing[@]} -gt 0 ]; then
    if [ -f "$gitignore" ]; then
      _say "  [modify] .gitignore (add ${#missing[@]} line(s))"
    else
      _say "  [create] .gitignore"
    fi
    [ "$removed" -gt 0 ] || SYNC_CHANGED+=(".gitignore")
    if [ "$dry_run" = false ]; then
      if [ -f "$gitignore" ]; then
        [ -s "$gitignore" ] && [ -n "$(tail -c1 "$gitignore")" ] && echo >> "$gitignore"
      fi
      for entry in "${missing[@]}"; do
        echo "$entry" >> "$gitignore"
      done
    fi
  fi

  if [ "$mode" = private ] && [ ${#tracked[@]} -gt 0 ] && [ "$blocked" = false ]; then
    if [ "$switching" = false ]; then
      # Layer B among them: the hidden repo synced nothing (ai_context_sync) — one line for both.
      if [ -n "$(_tracked_private_docs "$target")" ]; then
        _old_branch_line "$project_name" "${tracked[*]}"
      else
        echo "ai-sync: $project_name is on the private layer but git still tracks ${tracked[*]} — run sync-ai-templates.sh <project> --private-layer --commit"
      fi
    else
      # The hidden repo's round trip ran first (see Switch order above): untracking is safe now.
      _say "  [untrack] ${tracked[*]} (private layer from now on)"
      if [ "$dry_run" = false ]; then
        git -C "$target" rm -r -q --cached -- "${tracked[@]}"
        SYNC_UNTRACKED=("${tracked[@]}")
        SYNC_CHANGED+=("${tracked[@]}")
        SYNC_SWITCH_MSG="$PRIVATE_LAYER_MSG"
      fi
    fi
  fi

  # Pointer files a shared project still tracks: --shared untracks them (files stay on disk), a
  # plain run says how to finish the switch.
  if [ "$mode" = shared ] && [ "$is_repo" = true ]; then
    for entry in ${POINTER_MAP[@]+"${POINTER_MAP[@]}"}; do
      rel="${entry#*|}"
      [ -n "$(git -C "$target" ls-files -- "$rel" 2>/dev/null)" ] && tracked+=("$rel")
    done
    if [ ${#tracked[@]} -gt 0 ]; then
      if [ "$switching" = false ]; then
        echo "ai-sync: $project_name is shared but git still tracks ${tracked[*]} — run sync-ai-templates.sh <project> --shared --commit"
      elif ! git -C "$target" diff --cached --quiet 2>/dev/null; then
        blocked=true
        echo "ai-sync: $project_name has staged changes — commit or unstage them, then re-run --shared" >&2
      else
        _say "  [untrack] ${tracked[*]} (local-only from now on)"
        if [ "$dry_run" = false ]; then
          git -C "$target" rm -r -q --cached -- "${tracked[@]}"
          SYNC_UNTRACKED=("${tracked[@]}")
          SYNC_CHANGED+=("${tracked[@]}")
        fi
      fi
    fi
  fi

  [ "$created_living" = true ] && SYNC_BOOTSTRAPPED=true

  if [ "$dry_run" = false ] && [ "$do_commit" = true ]; then
    _commit_changes "$target"
    [ "$SYNC_COMMITTED" = true ] && [ "$do_push" = true ] && _push_changes "$target"
  fi
  # A switch that applied goes into the code root's registry (.ai-root/projects/<name>), so a
  # fresh clone on another machine starts in the same mode: --private-layer records private or
  # team, --shared records shared.
  if [ "$dry_run" = false ] && [ "$blocked" = false ]; then
    if [ "$make_private" = true ]; then
      _registry_record "$target" "$mode"
    elif [ "$make_shared" = true ] && [ "$mode" = shared ]; then
      _registry_record "$target" shared
    fi
  fi
  # After the commit: the switch commit is not held up by the new guard. Every mode but tracked
  # gets the private-terms guard.
  guard=true
  [ "$mode" = tracked ] && guard=false
  _sync_shared_hooks "$target" "$guard" "$dry_run"
  if [ "$SYNC_QUIET" = true ] && { [ ${#SYNC_CHANGED[@]} -gt 0 ] || [ "$SYNC_EXCLUDE" = true ]; }; then
    local note="" shown=()
    [ "$SYNC_COMMITTED" = true ] && note=" (committed)"
    [ "$SYNC_PUSHED" = true ] && note=" (committed, pushed)"
    shown=(${SYNC_CHANGED[@]+"${SYNC_CHANGED[@]}"})
    [ "$SYNC_EXCLUDE" = true ] && shown+=(".git/info/exclude")
    echo "ai-sync: refreshed ${shown[*]} from $SOURCE_LABEL$note"
  fi
  if [ "$SYNC_QUIET" = true ] && [ ${#SYNC_HOOKS[@]} -gt 0 ]; then
    echo "ai-sync: git hook ${SYNC_HOOKS[*]} (private-terms guard, .git/hooks)"
  fi
  [ -d "$target" ] && { _check_context_budget "$target" || true; }
  _apply_dev_context "$target" "$dry_run" || true
  _factory_apply_project "$target" "$dry_run" || true
  # After the run, so a registry mode this sync just applied is what gets judged. A switch is
  # the fix already; saying "switch" in the same breath would only repeat the command.
  if [ "$switching" = false ]; then
    if _same_path "$target" "$TEMPLATE_DIR"; then
      _conform_report_root "$target"
    else
      _conform_line "$target"
    fi
  fi
  return 0
}

# pull_template — refresh this template repo from origin before syncing, so every session starts
# from the latest templates. Fast-forward only, on a branch (a detached HEAD is a pinned release)
# with a clean tree (never fights local edits), bounded so an offline machine starts at once. Sets
# PULL_UPDATED=true when a repo moved.
PULL_UPDATED=false
pull_template() {
  _pull_repo "$TEMPLATE_DIR" "$TEMPLATE_NAME"
  [ -n "$OVERLAY_DIR" ] && _pull_repo "$OVERLAY_DIR" "$OVERLAY_NAME"
  return 0
}

# _pull_repo <dir> <name> — the per-repo half of pull_template (the overlay gets the same
# treatment): a bounded `git pull --ff-only` (_run_bounded: past its wait it is left to finish on
# its own and the next run sees the result).
_pull_repo() {
  local dir="$1" name="$2" before after out rc=0
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || return 0
  { git -C "$dir" remote get-url origin && git -C "$dir" symbolic-ref -q HEAD; } >/dev/null 2>&1 || return 0
  if [ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]; then
    echo "ai-sync: $name has uncommitted changes — pull skipped, using the templates on disk"
    return 0
  fi
  before="$(git -C "$dir" rev-parse HEAD 2>/dev/null)"
  out="$(mktemp "${TMPDIR:-/tmp}/ai-sync-pull.XXXXXX")"
  _run_bounded "$out" git -C "$dir" pull -q --ff-only || rc=$?
  rm -f "$out"
  if [ "$rc" -eq 124 ] && [ "$NET_SKIPPED" = true ]; then
    echo "ai-sync: $name pull skipped (no network time left in this run) — using the templates on disk"
    return 0
  elif [ "$rc" -eq 124 ]; then
    echo "ai-sync: $name pull still running after ${NET_LIMIT}s — using the templates on disk"
    return 0
  elif [ "$rc" -ne 0 ]; then
    echo "ai-sync: $name pull failed (offline, or diverged from origin) — using the templates on disk"
    return 0
  fi
  after="$(git -C "$dir" rev-parse HEAD 2>/dev/null)"
  if [ "$before" != "$after" ]; then
    PULL_UPDATED=true
    _say "ai-sync: pulled latest $name from origin"
  fi
  return 0
}

# refresh_agents_md <project> [--dry-run] [--commit] — the --agents pass: run
# refresh-agents-sections.py on one project. Its own guards decide what is safe (customized
# sections, shared projects, uncommitted AGENTS.md, merges; a private or team project's AGENTS.md
# is never committed to the code repo). No interpreter → silent no-op; a
# failure is one line, never an error.
refresh_agents_md() {
  local target="$1" script py=() c
  shift
  script="$TEMPLATE_DIR/skills/bootstrap-ai/scripts/refresh-agents-sections.py"
  [ -f "$script" ] && [ -f "$target/AGENTS.md" ] && [ ! -L "$target/AGENTS.md" ] || return 0
  if command -v uv >/dev/null 2>&1; then
    py=(uv run --quiet --no-project)
  else
    for c in python3 python; do
      if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys' >/dev/null 2>&1; then py=("$c"); break; fi
    done
  fi
  [ ${#py[@]} -gt 0 ] || return 0
  local flags=()
  [ "$SYNC_QUIET" = true ] && flags+=(--quiet)
  "${py[@]}" "$script" "$target" ${flags[@]+"${flags[@]}"} "$@" 2>/dev/null \
    || echo "ai-sync: AGENTS.md refresh failed — run refresh-agents-sections.py $target by hand"
  return 0
}

# Network budget: every network step of a run (the template and .ai-root pulls, the .ai-root
# push, the hidden repo's ls-remote, fetch and push) shares $AI_SYNC_NET_BUDGET seconds of waiting
# (default 30); each one waits at most $AI_SYNC_PULL_WAIT seconds (default 10), or what is left.
# The local work between them (over 30 s on a slow Windows run) does not count. After the first
# step that timed out (not one that failed at once), the remaining ones are skipped. The seconds
# left and the down flag are exported, so the --pull re-run keeps them.
NET_LIMIT=10            # the wait of the last _run_bounded call, in seconds (for its messages)
NET_SKIPPED=false       # true when the last _run_bounded call ran nothing (no network time left)

# net_budget_reset — start a new budget: a run with --pull, each project of update-projects.
# Otherwise the first network step starts one (or keeps the one a re-run inherited).
net_budget_reset() {
  local budget="${AI_SYNC_NET_BUDGET:-30}"
  case "$budget" in ''|*[!0-9]*) budget=30 ;; esac
  AI_SYNC_NET_LEFT=$((10#$budget))
  AI_SYNC_NET_DOWN=""
  export AI_SYNC_NET_LEFT AI_SYNC_NET_DOWN
}

# _run_bounded <out-file> <cmd…> — a network step: 0 done, 1 failed, 124 still running after its
# wait (left to finish on its own; the run's later network steps are skipped) or not run at all
# (NET_SKIPPED=true: no network time left). Stdout goes to <out-file>. NET_LIMIT = the wait used.
# The step's own time comes off AI_SYNC_NET_LEFT ($SECONDS: no fork, a Git Bash fork is slow).
_run_bounded() {
  local out="$1" limit pid ticks=0 start
  shift
  NET_SKIPPED=false
  case "${AI_SYNC_NET_LEFT:-}" in ''|*[!0-9]*) net_budget_reset ;; *) AI_SYNC_NET_LEFT=$((10#$AI_SYNC_NET_LEFT)) ;; esac
  limit="${AI_SYNC_PULL_WAIT:-10}"
  case "$limit" in ''|*[!0-9]*) limit=10 ;; esac
  limit=$((10#$limit))
  [ "$AI_SYNC_NET_LEFT" -ge "$limit" ] || limit="$AI_SYNC_NET_LEFT"
  NET_LIMIT="$limit"
  if [ -n "${AI_SYNC_NET_DOWN:-}" ] || [ "$limit" -le 0 ]; then
    NET_SKIPPED=true
    : > "$out"
    return 124
  fi
  start=$SECONDS
  GIT_TERMINAL_PROMPT=0 nohup "$@" >"$out" 2>/dev/null &
  pid=$!
  while kill -0 "$pid" 2>/dev/null && [ "$ticks" -lt $((limit * 5)) ]; do
    sleep 0.2
    ticks=$((ticks + 1))
  done
  AI_SYNC_NET_LEFT=$(( SECONDS - start < AI_SYNC_NET_LEFT ? AI_SYNC_NET_LEFT - (SECONDS - start) : 0 ))   # still exported
  if kill -0 "$pid" 2>/dev/null; then
    AI_SYNC_NET_DOWN=1
    export AI_SYNC_NET_DOWN
    return 124
  fi
  wait "$pid" || return 1
  return 0
}

# Locks: the .ai-root checkout's (<its git dir>/ai-sync.lock) and the hidden repo's (<hidden
# repo>/sync.lock). A folder made with mkdir, so taking one is atomic; one older than
# SYNC_LOCK_STALE_MIN minutes = a crashed run, taken over. Nobody waits: a held lock is a skip.
SYNC_LOCK_STALE_MIN=5

# _sync_lock <lock-dir> — take the lock: 0 taken, 1 held by another run.
_sync_lock() {
  local lock="$1" find=find
  mkdir "$lock" 2>/dev/null && return 0
  [ -x /usr/bin/find ] && find=/usr/bin/find     # not Windows' find.exe, when PATH puts it first
  [ -n "$("$find" "$lock" -maxdepth 0 -mmin +"$SYNC_LOCK_STALE_MIN" 2>/dev/null)" ] || return 1
  rm -rf "$lock"
  mkdir "$lock" 2>/dev/null
}

# Private layer B (--private-layer, see the header). The hidden repo is <git-common-dir>/ai-context
# driven with --git-dir/--work-tree, so the files stay where every tool expects them while the
# code repo ignores them. Active in private and team mode. Nothing here may fail a session:
# every problem is one line. Its paths: _private_doc_paths.
AIC_GIT=""
AIC_TREE=""
AIC_BRANCH=""
AIC_MODE=""
AIC_COMMITTED=""
AIC_REMOTE=""           # the remote of the last round trip (empty: none set)
AIC_REMOTE_STATE=""     # what it said: none (no remote) | absent (no hidden branch yet) | present |
                        # unreachable (no answer: offline, timeout, no network time, fetch failed,
                        # lock held); empty when the round trip did not ask
AIC_DOCS_WAIT=false     # private, no hidden commit yet, the remote did not answer: sync_ai_templates
                        # creates no blank living doc (they come from the remote once it answers)
AIC_OLD_BRANCH=""       # the layer paths the code repo still tracks, when that skipped the round trip
AIC_SWITCHING=false     # the round trip runs for a --private-layer switch (ai_context_sync --switch)
AIC_SWITCH_READY=false  # --switch: the remote holds the hidden HEAD (or no remote is set)
AIC_NOTES=()            # --switch: success lines, printed by the caller once the switch applies
AIC_CFG_FILES=()        # _aic_config_files: config.local/ files to version
AIC_SKIPPED=()          # _aic_config_files: config.local/ files never versioned
AIC_WORK=false          # _ai_context_remote: the project lives under a work root
AIC_SAID=""             # the remote-rule lines this run already printed (_aic_say_once)

# _aic_say_once <line> — print a line at most once per run (a run may sync the hidden repo twice).
_aic_say_once() {
  local nl=$'\n'
  case "$nl$AIC_SAID$nl" in *"$nl$1$nl"*) return 0 ;; esac
  AIC_SAID="$AIC_SAID$nl$1"
  echo "$1"
}

# _ai_context_remote — set AIC_REMOTE to the owner's private remote, or empty (the hidden repo
# stays local). Root = _ancestor_root (the nearest folder above the project holding .ai-root/ or
# .ai-context-remote). Outside a work root: $AI_CONTEXT_REMOTE (none or empty = local only), else
# the first line of <root>/.ai-context-remote, else of ~/.ai-context-remote. Under a work root
# (_is_work_path of the top level), whose docs must never land on a personal remote:
# only <root>/.ai-context-remote — $AI_CONTEXT_REMOTE can only disable it (none or empty; any
# other value is ignored with one line), ~/.ai-context-remote is never read, and a github.com URL
# is refused with one line. Sets AIC_WORK. Called in this shell, never in $(...), so its lines
# print once per run (_aic_say_once).
_ai_context_remote() {
  local r="" f="" root
  AIC_REMOTE=""
  AIC_WORK=false
  root="$(_ancestor_root "$AIC_TREE")"
  root="${root%/}"
  if _is_work_path "$AIC_TREE"; then AIC_WORK=true; fi
  if [ "$AIC_WORK" = true ]; then
    if [ -n "$root" ] && [ -s "$root/.ai-context-remote" ]; then f="$root/.ai-context-remote"; fi
    if [ "${AI_CONTEXT_REMOTE+set}" = set ]; then
      case "$AI_CONTEXT_REMOTE" in ''|none) return 0 ;; esac
      if [ -n "$f" ]; then
        _aic_say_once "ai-sync: private AI docs: AI_CONTEXT_REMOTE is ignored under a work root (only none disables the remote) — using $f"
      else
        _aic_say_once "ai-sync: private AI docs: AI_CONTEXT_REMOTE is ignored under a work root (only none disables the remote) — kept local"
      fi
    fi
  elif [ "${AI_CONTEXT_REMOTE+set}" = set ]; then
    r="$AI_CONTEXT_REMOTE"
  elif [ -n "$root" ] && [ -s "$root/.ai-context-remote" ]; then
    f="$root/.ai-context-remote"
  elif [ -s "${HOME:-/nonexistent}/.ai-context-remote" ]; then
    f="$HOME/.ai-context-remote"
  fi
  [ -z "$f" ] || r="$(head -n 1 "$f" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  case "$r" in ''|none) return 0 ;; esac
  if [ "$AIC_WORK" = true ]; then
    case "$(printf '%s' "$r" | tr '[:upper:]' '[:lower:]')" in
      *github.com*)
        _aic_say_once "ai-sync: private AI docs: $r is a github.com remote — refused under a work root, kept local"
        return 0 ;;
    esac
  fi
  AIC_REMOTE="$r"
  return 0
}

_aic() { git -C "$AIC_TREE" --git-dir="$AIC_GIT" --work-tree="$AIC_TREE" "$@"; }

# _aic_head — true when the hidden repo has a commit.
_aic_head() { _aic rev-parse -q --verify HEAD >/dev/null 2>&1; }

# _aic_setup <target> — AIC_TREE (the work tree's top level), AIC_GIT (<git-common-dir>/ai-context)
# and AIC_BRANCH (<root folder>/<project>, sanitized; spelled as the root repo's branches and the
# registry spell them, _root_spelling / _registry_name). Fails outside a git work tree.
_aic_setup() {
  local top name root
  top="$(cd "$1" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)" || return 1
  [ -n "$top" ] || return 1
  AIC_TREE="$(cd "$top" && pwd)"
  AIC_GIT="$(cd "$AIC_TREE" && cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd)" || return 1
  AIC_GIT="$AIC_GIT/ai-context"
  name="$(basename "$AIC_TREE")"
  root="$(_code_root "$AIC_TREE")"
  [ -z "$root" ] || [ ! -d "$root/.ai-root/projects" ] || name="$(_registry_name "$root/.ai-root/projects" "$name")"
  if [ -n "$root" ]; then root="$(_root_spelling "$root")"; else root="$(basename "$(dirname "$AIC_TREE")")"; fi
  AIC_BRANCH="$(printf '%s/%s' "$root" "$name" | sed 's#[^A-Za-z0-9._/-]#-#g')"
}

# _tracked_private_docs <dir> — the layer B paths the code repo's index still tracks, one per line
# (config.local/ at any depth: the first one found).
_tracked_private_docs() {
  local dir="$1" p
  while IFS= read -r p; do
    if [ "$p" = "config.local/" ]; then
      git -C "$dir" -c core.quotepath=off ls-files 2>/dev/null \
        | awk '!f { i = index("/" $0, "/config.local/"); if (i) { print substr($0, 1, i + 12); f = 1 } }' || true
    elif [ -n "$(git -C "$dir" ls-files -- "$p" 2>/dev/null)" ]; then
      printf '%s\n' "$p"
    fi
  done < <(_private_doc_paths)
}

# _old_branch_line <name> <paths> — the line of a private project whose code repo still tracks
# layer B (an old branch checked out, or a switch never finished): the hidden repo syncs nothing.
_old_branch_line() {
  echo "ai-sync: $1 is on the private layer but git still tracks $2 — private AI docs not synced until you run sync-ai-templates.sh <project> --private-layer --commit"
}

# _aic_note <line> — a success line: printed, or kept in AIC_NOTES during a --switch (the caller
# prints them once the switch applies).
_aic_note() {
  if [ "$AIC_SWITCHING" = true ]; then AIC_NOTES+=("$1"); else echo "$1"; fi
}

# _aic_offline_line <what> — the line of a round trip whose remote did not answer: synced next
# time; or, in a private project with no hidden commit yet and a living doc missing, none is
# created until the remote answers (AIC_DOCS_WAIT). Never printed during a --switch: the caller
# prints its single "switch waits" line.
_aic_offline_line() {
  local entry tail="synced next time"
  [ "$AIC_SWITCHING" = false ] || return 0
  if [ "$AIC_MODE" = private ] && ! _aic_head; then
    for entry in ${LIVING_DOCS_MAP[@]+"${LIVING_DOCS_MAP[@]}"}; do
      [ "${entry#*|}" != ".env.example" ] || continue
      if [ ! -e "$AIC_TREE/${entry#*|}" ]; then tail="living docs not created until it answers"; break; fi
    done
  fi
  echo "ai-sync: private AI docs: $1 — $tail"
}

# _aic_attributes — MEMORY.md merges by union in the hidden repo (two machines adding to the same
# memory index never conflict): one LF line in <hidden repo>/info/attributes, never twice.
_aic_attributes() {
  local f="$AIC_GIT/info/attributes"
  _has_line "$f" "MEMORY.md merge=union" && return 0
  mkdir -p "$AIC_GIT/info" 2>/dev/null || return 0
  { if [ -s "$f" ] && [ -n "$(tail -c1 "$f")" ]; then printf '\n'; fi
    printf '%s\n' "MEMORY.md merge=union"; } >> "$f" 2>/dev/null || true
  return 0
}

# _aic_adopt <commit> — make the remote's version the local branch and check its files out. A
# local file that differs from it is saved under <hidden repo>.bak/<timestamp>/ first. Team mode:
# a file the team repo tracks is neither saved nor checked out (the team's copy stays).
_aic_adopt() {
  local ref="$1" bak f saved=false team_tracked="" files=()
  [ "$AIC_MODE" != team ] || team_tracked="$(_team_tracked "$AIC_TREE")"
  bak="$AIC_GIT.bak/$(date +%Y%m%d-%H%M%S)"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -z "$team_tracked" ] || ! _team_has "$f" "$team_tracked" || continue
    files+=("$f")
    [ -f "$AIC_TREE/$f" ] || continue
    _aic diff --quiet "$ref" -- "$f" >/dev/null 2>&1 && continue   # no ref:path — Git Bash mangles it
    mkdir -p "$bak/$(dirname "$f")" && cp "$AIC_TREE/$f" "$bak/$f" && saved=true
  done < <(_aic -c core.quotepath=off ls-tree -r --name-only "$ref" 2>/dev/null)
  if ! { _aic update-ref "refs/heads/$AIC_BRANCH" "$ref" && _aic reset -q \
         && { [ ${#files[@]} -eq 0 ] || _aic checkout -f -- "${files[@]}"; }; } >/dev/null 2>&1; then
    echo "ai-sync: private AI docs: could not check out $AIC_BRANCH in $AIC_GIT"
    return 0
  fi
  [ "$saved" = false ] || echo "ai-sync: private AI docs: local copies that differed are saved in $bak"
  return 0
}

# _config_local_dirs — every config.local/ folder of the work tree at any depth (relative, with a
# trailing /): the ones the code repo tracks and the untracked or ignored ones it lists (never
# under .git; a wholly untracked folder is listed whole, so one inside it is not seen).
_config_local_dirs() {
  { git -C "$AIC_TREE" -c core.quotepath=off ls-files 2>/dev/null
    git -C "$AIC_TREE" -c core.quotepath=off ls-files -o --directory 2>/dev/null
  } | awk '{ i = index("/" $0, "/config.local/"); if (i) { p = substr($0, 1, i + 12); if (!(p in seen)) { seen[p] = 1; print p } } }' || true
}

# _aic_config_files — the files of every config.local/ folder, split into AIC_CFG_FILES (versioned)
# and AIC_SKIPPED (never staged, even when already tracked): *.db, *.sqlite*, *.log, .env*,
# *.key, *.pem, anything under cache/ or __pycache__/, files over 1 MiB. Both in C order.
_aic_config_files() {
  local find=find d f rel big nl=$'\n'
  AIC_CFG_FILES=()
  AIC_SKIPPED=()
  [ -x /usr/bin/find ] && find=/usr/bin/find
  while IFS= read -r d; do
    d="${d%/}"
    [ -d "$AIC_TREE/$d" ] || continue
    big="$(cd "$AIC_TREE" && "$find" "$d" -type f -size +1048576c 2>/dev/null)" || big=""
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      rel="${f#"$d"/}"
      case "/$rel" in */cache/*|*/__pycache__/*) AIC_SKIPPED+=("$f"); continue ;; esac
      case "${f##*/}" in *.db|*.sqlite*|*.log|.env*|*.key|*.pem) AIC_SKIPPED+=("$f"); continue ;; esac
      case "$nl$big$nl" in *"$nl$f$nl"*) AIC_SKIPPED+=("$f"); continue ;; esac
      AIC_CFG_FILES+=("$f")
    done < <(cd "$AIC_TREE" && "$find" "$d" \( -type f -o -type l \) 2>/dev/null | LC_ALL=C sort)
  done < <(_config_local_dirs)
  return 0
}

# _aic_commit — commit every private doc that changed; sets AIC_COMMITTED to the paths. Each path
# is named (add -f: the code repo's exclude block ignores them all): folders whole, config.local/
# file by file (_aic_config_files; one line whenever the skipped set changes). A living doc the
# hidden HEAD holds but the disk lost is restored, never committed as a deletion; any other path
# the hidden repo tracks and the disk lost is committed as one. Team mode: only the B files the
# team repo does not track — one it tracks is never added, and one the hidden repo already holds
# stays as it is there (reset to the hidden HEAD: never restored, updated or deleted).
_aic_commit() {
  local paths=() gone=() reset=() p entry names list team_tracked=""
  [ "$AIC_MODE" != team ] || team_tracked="$(_team_tracked "$AIC_TREE")"
  for entry in ${LIVING_DOCS_MAP[@]+"${LIVING_DOCS_MAP[@]}"}; do
    p="${entry#*|}"
    [ "$p" != ".env.example" ] || continue
    [ -z "$team_tracked" ] || ! _team_has "$p" "$team_tracked" || continue
    [ ! -e "$AIC_TREE/$p" ] && [ ! -L "$AIC_TREE/$p" ] || continue
    [ -n "$(_aic ls-tree --name-only HEAD -- "$p" 2>/dev/null)" ] || continue
    if _aic checkout HEAD -- "$p" >/dev/null 2>&1; then
      echo "ai-sync: private AI docs: $p was deleted — restored from the hidden repo"
    fi
  done
  while IFS= read -r p; do
    [ "$p" != "config.local/" ] || continue
    if [ -e "$AIC_TREE/$p" ] || [ -L "$AIC_TREE/${p%/}" ]; then paths+=("$p"); fi
  done < <(_private_doc_paths)
  _aic_config_files
  paths+=(${AIC_CFG_FILES[@]+"${AIC_CFG_FILES[@]}"})
  [ ${#paths[@]} -eq 0 ] || _aic add -f -A -- "${paths[@]}" >/dev/null 2>&1 || true
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ -n "$team_tracked" ] && _team_has "$p" "$team_tracked"; then
      reset+=("$p")
      continue
    fi
    [ -e "$AIC_TREE/$p" ] || [ -L "$AIC_TREE/$p" ] || gone+=("$p")
  done < <(_aic -c core.quotepath=off ls-files 2>/dev/null)
  [ ${#gone[@]} -eq 0 ] || _aic rm -q --cached --ignore-unmatch -- "${gone[@]}" >/dev/null 2>&1 || true
  if [ ${#reset[@]} -gt 0 ]; then
    if _aic_head; then
      _aic reset -q HEAD -- "${reset[@]}" >/dev/null 2>&1 || true
    else
      _aic rm -q --cached --ignore-unmatch -- "${reset[@]}" >/dev/null 2>&1 || true
    fi
  fi
  list="$(printf '%s\n' ${AIC_SKIPPED[@]+"${AIC_SKIPPED[@]}"})"
  if [ "$list" != "$(cat "$AIC_GIT/ai-sync-skipped" 2>/dev/null)" ]; then
    if [ ${#AIC_SKIPPED[@]} -gt 0 ]; then
      names="${AIC_SKIPPED[*]:0:3}"
      [ ${#AIC_SKIPPED[@]} -le 3 ] || names="$names …"
      echo "ai-sync: private AI docs: ${#AIC_SKIPPED[@]} config.local file(s) not versioned (secrets, databases, logs, caches or over 1 MB): $names"
    fi
    printf '%s' "$list" > "$AIC_GIT/ai-sync-skipped" 2>/dev/null || true
  fi
  _aic diff --cached --quiet >/dev/null 2>&1 && return 0
  names="$(_aic diff --cached --name-only 2>/dev/null | tr '\n' ' ')"
  names="${names% }"
  if _aic commit -q -m "ai-context: $names" >/dev/null 2>&1; then
    AIC_COMMITTED="$names"
  else
    echo "ai-sync: private AI docs: commit failed in $AIC_GIT (git identity?)"
  fi
  return 0
}

# Memory (private and team only; a tracked project never reaches ai_context_sync).
# autoMemoryDirectory in .claude/settings.local.json is the absolute forward-slash path of
# <project>/.claude/memory. The merge is python (python3, python, else `uv python find`) or,
# failing that, pwsh. A missing tool or malformed JSON is one line and the file stays as it is.
# Once per machine (stamp <hidden git dir>/memory-imported), after the restore and before the
# hidden commit, _aic_import_memory copies ~/.claude/projects/<slug>/memory: a missing file is
# copied, a file that differs goes to imported-<host>/, and MEMORY.md gains the lines it lacks.
# The source is never deleted. The slug is Claude Code's: every non-alphanumeric of the native
# absolute path (cygpath -w on Windows, not Git Bash's /d/ form) becomes "-". An unreachable
# remote with no hidden commit yet waits. A file the team repo tracks is never written.

# _memory_native_path — the work tree's native absolute path (D:\... on Windows). No trailing CR.
_memory_native_path() {
  local p=""
  if command -v cygpath >/dev/null 2>&1; then
    p="$(cygpath -w "$AIC_TREE" 2>/dev/null)" || p=""
  fi
  if [ -z "$p" ]; then
    p="$(cd "$AIC_TREE" 2>/dev/null && pwd -P)" || p="$AIC_TREE"
  fi
  printf '%s' "$p" | tr -d '\r'
}

# _memory_forward_path — the same path with forward slashes (D:/... on Windows), no trailing slash.
_memory_forward_path() {
  local p=""
  if command -v cygpath >/dev/null 2>&1; then
    p="$(cygpath -m "$AIC_TREE" 2>/dev/null)" || p=""
  fi
  if [ -z "$p" ]; then
    p="$(cd "$AIC_TREE" 2>/dev/null && pwd -P)" || p="$AIC_TREE"
    p="$(printf '%s' "$p" | sed 's#\\#/#g')"
  fi
  p="$(printf '%s' "$p" | tr -d '\r')"
  printf '%s' "${p%/}"
}

# _memory_slug — Claude Code's project directory name under ~/.claude/projects.
_memory_slug() { _memory_native_path | sed 's/[^A-Za-z0-9]/-/g'; }

# _memory_host — this machine's name, safe as one path segment.
_memory_host() {
  local h
  h="$(hostname 2>/dev/null | tr -d '\r' | awk 'NR==1{print; exit}')" || h=""
  h="$(printf '%s' "$h" | sed 's/[^A-Za-z0-9._-]/-/g')"
  [ -n "$h" ] || h="unknown"
  printf '%s' "$h"
}

# _memory_py — one interpreter that actually runs, or nothing.
_memory_py() {
  local c
  for c in python3 python; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys' >/dev/null 2>&1; then
      printf '%s\n' "$c"
      return 0
    fi
  done
  if command -v uv >/dev/null 2>&1; then
    # uv 0.12 paints the path even into a pipe (ESC[36m…ESC[39m). That string is not executable.
    c="$(NO_COLOR=1 uv python find 2>/dev/null | tr -d '\r' | sed $'s/\033\\[[0-9;]*m//g' | awk 'NR==1{print; exit}')" || c=""
    if [ -n "$c" ] && "$c" -c 'import sys' >/dev/null 2>&1; then
      printf '%s\n' "$c"
      return 0
    fi
  fi
  return 1
}

# _memory_once <line> — one identical memory note per run (the round trip is called more than once).
_memory_once() {
  case "|${MEMORY_ONCE-}|" in *"|$1|"*) return 0 ;; esac
  MEMORY_ONCE="${MEMORY_ONCE-}|$1"
  echo "$1"
}

# _memory_settings [dry] — merge autoMemoryDirectory. Always returns 0: a session must not break.
# "dry" reports a would-be write and does not touch the file.
_memory_settings() {
  local dry="${1:-write}" file value py="" rc=0 script=""
  [ -n "${AIC_TREE:-}" ] || return 0
  file="$AIC_TREE/.claude/settings.local.json"
  # A team repo that tracks the file owns it: never written (memory stays machine-local there).
  if [ "${AIC_MODE:-}" = team ] && [ -n "$(git -C "$AIC_TREE" ls-files -- .claude/settings.local.json 2>/dev/null)" ]; then
    return 0
  fi
  value="$(_memory_forward_path)/.claude/memory"
  case "$value" in /.claude/memory) return 0 ;; esac
  py="$(_memory_py 2>/dev/null)" || py=""
  if [ -n "$py" ]; then
    script="$(mktemp "${TMPDIR:-/tmp}/ai-sync-mem.XXXXXX.py")" || script=""
  fi
  if [ -n "$script" ]; then
    cat > "$script" <<'PY'
import json, os, sys
path, value, mode = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    if os.path.isfile(path) and os.path.getsize(path) > 0:
        with open(path, "r", encoding="utf-8-sig") as fh:
            raw = fh.read()
        data = {} if raw.strip() == "" else json.loads(raw)
    else:
        data = {}
except Exception:
    sys.exit(2)
if not isinstance(data, dict):
    sys.exit(2)
if data.get("autoMemoryDirectory") == value:
    sys.exit(0)
if mode == "dry":
    sys.exit(3)
data["autoMemoryDirectory"] = value
text = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
parent = os.path.dirname(path)
if parent:
    os.makedirs(parent, exist_ok=True)
tmp = path + ".ai-sync-tmp"
with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
    fh.write(text)
os.replace(tmp, path)
sys.exit(3)
PY
    "$py" "$script" "$file" "$value" "$dry" || rc=$?
    rm -f "$script"
  elif command -v pwsh >/dev/null 2>&1; then
    script="$(mktemp "${TMPDIR:-/tmp}/ai-sync-mem.XXXXXX.ps1")" || script=""
    if [ -z "$script" ]; then
      _memory_once "ai-sync: autoMemoryDirectory not merged into .claude/settings.local.json (no python or pwsh)"
      return 0
    fi
    cat > "$script" <<'PS1'
param([string]$SettingsFile, [string]$Value, [string]$Mode)
$ErrorActionPreference = 'Stop'
try {
  $node = $null
  if ((Test-Path -LiteralPath $SettingsFile -PathType Leaf) -and ((Get-Item -LiteralPath $SettingsFile -Force).Length -gt 0)) {
    $raw = [IO.File]::ReadAllText($SettingsFile)
    if ([string]::IsNullOrWhiteSpace($raw)) { $node = [System.Text.Json.Nodes.JsonNode]::Parse('{}') }
    else { $node = [System.Text.Json.Nodes.JsonNode]::Parse($raw) }
  } else { $node = [System.Text.Json.Nodes.JsonNode]::Parse('{}') }
} catch { exit 2 }
if ($node -isnot [System.Text.Json.Nodes.JsonObject]) { exit 2 }
$existing = $node['autoMemoryDirectory']
$current = $null
if ($null -ne $existing) {
  try { $current = [System.Text.Json.JsonSerializer]::Deserialize($existing.ToJsonString(), [string]) } catch { $current = $null }
}
if ($current -eq $Value) { exit 0 }
if ($Mode -eq 'dry') { exit 3 }
$node['autoMemoryDirectory'] = [System.Text.Json.Nodes.JsonValue]::Create($Value)
$opts = [System.Text.Json.JsonSerializerOptions]::new()
$opts.WriteIndented = $true
$dir = Split-Path -Parent $SettingsFile
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$tmp = $SettingsFile + '.ai-sync-tmp'
[IO.File]::WriteAllText($tmp, ($node.ToJsonString($opts) + "`n"))
Move-Item -LiteralPath $tmp -Destination $SettingsFile -Force
exit 3
PS1
    pwsh -NoProfile -File "$script" "$file" "$value" "$dry" || rc=$?
    rm -f "$script"
  else
    _memory_once "ai-sync: autoMemoryDirectory not merged into .claude/settings.local.json (no python or pwsh)"
    return 0
  fi
  case "$rc" in
    0) ;;
    2) _memory_once "ai-sync: autoMemoryDirectory not merged into .claude/settings.local.json (malformed JSON)" ;;
    3) _say "  [write]  .claude/settings.local.json (autoMemoryDirectory)" ;;
    *) _memory_once "ai-sync: autoMemoryDirectory not merged into .claude/settings.local.json (merge failed)" ;;
  esac
  return 0
}

# _memory_merge_lines <dest> <src> — dest keeps its lines; src lines it lacks are appended (LF).
_memory_merge_lines() {
  local dest="$1" src="$2" tmp line
  tmp="$(mktemp "${TMPDIR:-/tmp}/ai-sync-mem.XXXXXX")" || return 0
  if [ -f "$dest" ]; then
    sed 's/\r$//' "$dest" > "$tmp" || true
  else
    : > "$tmp"
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    if grep -qxF -e "$line" "$tmp" 2>/dev/null; then
      continue
    fi
    printf '%s\n' "$line" >> "$tmp"
  done < "$src"
  if [ -f "$dest" ] && sed 's/\r$//' "$dest" | cmp -s - "$tmp"; then
    rm -f "$tmp"
    return 0
  fi
  if [ ! -f "$dest" ] && [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    return 0
  fi
  mkdir -p "$(dirname "$dest")" 2>/dev/null || { rm -f "$tmp"; return 0; }
  mv -f "$tmp" "$dest" 2>/dev/null || rm -f "$tmp"
  return 0
}

# _memory_import_one <src-file> <dest-root> <rel> <host> <team-tracked>
# A team-tracked path is never written. MEMORY.md is a line union; anything else that differs
# is copied aside under imported-<host>/, leaving the destination as it is.
_memory_import_one() {
  local srcf="$1" destroot="$2" rel="$3" host="$4" team_tracked="$5"
  local dest="$destroot/$rel" side entry
  entry=".claude/memory/$rel"
  if [ -n "$team_tracked" ] && _team_has "$entry" "$team_tracked"; then return 0; fi
  if [ "$rel" = "MEMORY.md" ]; then
    _memory_merge_lines "$dest" "$srcf"
    return 0
  fi
  if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
    mkdir -p "$(dirname "$dest")" 2>/dev/null && cp "$srcf" "$dest"
    return 0
  fi
  cmp -s "$srcf" "$dest" && return 0
  entry=".claude/memory/imported-$host/$rel"
  side="$destroot/imported-$host/$rel"
  if [ -n "$team_tracked" ] && _team_has "$entry" "$team_tracked"; then return 0; fi
  if [ -e "$side" ] || [ -L "$side" ]; then return 0; fi
  mkdir -p "$(dirname "$side")" 2>/dev/null && cp "$srcf" "$side"
  return 0
}

# _aic_import_memory — the once-per-machine import. No stamp when there is nothing to import yet
# (no source directory, or the remote has not answered and this machine has no hidden commit).
_aic_import_memory() {
  local stamp="$AIC_GIT/memory-imported" slug src dest host rel team_tracked="" find=find
  [ -n "${AIC_GIT:-}" ] && [ -n "${AIC_TREE:-}" ] || return 0
  [ ! -e "$stamp" ] || return 0
  if [ "$AIC_REMOTE_STATE" = unreachable ] && ! _aic_head; then return 0; fi
  slug="$(_memory_slug)"
  [ -n "$slug" ] || return 0
  src="${HOME:-}/.claude/projects/$slug/memory"
  [ -d "$src" ] || return 0
  dest="$AIC_TREE/.claude/memory"
  host="$(_memory_host)"
  [ "$AIC_MODE" != team ] || team_tracked="$(_team_tracked "$AIC_TREE")"
  [ -x /usr/bin/find ] && find=/usr/bin/find
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    _memory_import_one "$src/$rel" "$dest" "$rel" "$host" "$team_tracked" || true
  done < <(cd "$src" && "$find" . -type f 2>/dev/null | sed 's#^\./##' | LC_ALL=C sort)
  : > "$stamp" 2>/dev/null || true
  return 0
}

# ai_context_sync <project> [--no-fetch] [--dry-run] [--switch [--team]] — the layer B round trip
# (private and team mode): create (or, on a fresh clone, attach) the hidden repo, commit the docs,
# rebase onto the remote branch, push. Sets AIC_REMOTE_STATE and AIC_DOCS_WAIT (see above).
# --no-fetch skips the download (the second call of a session, right after the first one).
# --switch: the round trip of a --private-layer switch, before the code repo changes (whatever
# its mode; as private, or as team with --team); AIC_SWITCH_READY=true once the remote's branch
# is the hidden HEAD, or no remote is set. The remote: _ai_context_remote.
# Safety: <hidden repo>/sync.lock (_sync_lock) — held by another run = a silent skip, and only
# its holder creates the repo or aborts a leftover rebase; a private project whose code repo
# still tracks layer B (an old branch) syncs nothing (AIC_OLD_BRANCH, no network).
ai_context_sync() {
  local target="$1" no_fetch=false dry_run=false switch=false team=false arg
  shift
  for arg in "$@"; do
    case "$arg" in
      --no-fetch) no_fetch=true ;;
      --dry-run)  dry_run=true ;;
      --switch)   switch=true ;;
      --team)     team=true ;;
      --quiet)    SYNC_QUIET=true ;;
    esac
  done
  AIC_COMMITTED=""
  AIC_REMOTE=""
  AIC_REMOTE_STATE=""
  AIC_DOCS_WAIT=false
  AIC_OLD_BRANCH=""
  AIC_SWITCH_READY=false
  AIC_NOTES=()
  AIC_SWITCHING="$switch"
  AIC_MODE=private
  [ "$team" = false ] || AIC_MODE=team
  if [ "$switch" = false ]; then
    AIC_MODE="$(_project_mode "$target")"
    case "$AIC_MODE" in private|team) ;; *) return 0 ;; esac
  fi
  _aic_setup "$target" || return 0
  if [ "$switch" = false ] && [ "$AIC_MODE" = private ] && [ -n "$(_tracked_private_docs "$AIC_TREE")" ]; then
    AIC_OLD_BRANCH="$(_tracked_layer_paths "$AIC_TREE" | tr '\n' ' ')"
    AIC_OLD_BRANCH="${AIC_OLD_BRANCH% }"
    _memory_settings || true
    return 0
  fi
  _ai_context_remote
  if [ "$dry_run" = true ]; then
    if [ -f "$AIC_GIT/HEAD" ]; then
      _say "  [ai-context] commit + sync private AI docs ($AIC_BRANCH)"
    else
      _say "  [ai-context] create hidden repo .git/ai-context ($AIC_BRANCH)"
    fi
    _memory_settings dry || true
    return 0
  fi
  if ! mkdir -p "$AIC_GIT" 2>/dev/null; then
    echo "ai-sync: private AI docs: could not create $AIC_GIT"
    return 0
  fi
  if ! _sync_lock "$AIC_GIT/sync.lock"; then
    # Another run is in the middle of it: skip quietly, as if the remote had not answered.
    if [ -n "$AIC_REMOTE" ]; then
      AIC_REMOTE_STATE=unreachable
      _aic_head || AIC_DOCS_WAIT=true
    else
      AIC_REMOTE_STATE=none
      AIC_SWITCH_READY=true
    fi
    return 0
  fi
  _aic_round_trip "$no_fetch" || true
  # A switch that is still waiting must not write settings or print a second line.
  if [ "$AIC_SWITCHING" != true ] || [ "$AIC_SWITCH_READY" = true ]; then
    _memory_settings || true
  fi
  rm -rf "$AIC_GIT/sync.lock"
  return 0
}

# _aic_round_trip <no_fetch> — the locked half of ai_context_sync.
_aic_round_trip() {
  local no_fetch="$1" remote="$AIC_REMOTE" cur out rc head_before remote_ref="" tracking unrelated=false
  tracking="refs/remotes/origin/$AIC_BRANCH"
  if [ ! -f "$AIC_GIT/HEAD" ]; then
    if ! { git init -q --bare "$AIC_GIT" && _aic symbolic-ref HEAD "refs/heads/$AIC_BRANCH" \
           && _aic config status.showUntrackedFiles no && _aic config core.autocrlf false; } >/dev/null 2>&1; then
      echo "ai-sync: private AI docs: could not create $AIC_GIT"
      return 0
    fi
    no_fetch=false
    [ -n "$remote" ] || echo "ai-sync: private AI docs kept in a local hidden repo only — aicf setup --ai-context-remote <url> shares them between machines"
  fi
  _aic_attributes
  if [ -d "$AIC_GIT/rebase-merge" ] || [ -d "$AIC_GIT/rebase-apply" ]; then
    _aic rebase --abort >/dev/null 2>&1 || true
  fi
  if [ -n "$remote" ]; then
    cur="$(_aic remote get-url origin 2>/dev/null)" || cur=""
    if [ -z "$cur" ]; then
      _aic remote add origin "$remote" >/dev/null 2>&1 || true
    elif [ "$cur" != "$remote" ]; then
      _aic remote set-url origin "$remote" >/dev/null 2>&1 || true
    fi
  else
    AIC_REMOTE_STATE=none
    # Under a work root a github.com origin (an earlier rule's) goes: nothing is ever pushed there.
    if [ "$AIC_WORK" = true ]; then
      cur="$(_aic remote get-url origin 2>/dev/null)" || cur=""
      case "$(printf '%s' "$cur" | tr '[:upper:]' '[:lower:]')" in
        *github.com*) _aic remote remove origin >/dev/null 2>&1 || true ;;
      esac
    fi
  fi
  out="$(mktemp "${TMPDIR:-/tmp}/ai-sync-aic.XXXXXX")"
  # Download first: a fresh clone must adopt the remote's docs before anything is committed.
  if [ -n "$remote" ] && [ "$no_fetch" = false ]; then
    rc=0
    _run_bounded "$out" git -C "$AIC_TREE" --git-dir="$AIC_GIT" ls-remote origin "refs/heads/$AIC_BRANCH" || rc=$?
    if [ "$rc" -ne 0 ]; then
      AIC_REMOTE_STATE=unreachable
      _aic_offline_line "$remote unreachable"
      remote=""
    elif [ -s "$out" ]; then
      rc=0
      _run_bounded "$out" git -C "$AIC_TREE" --git-dir="$AIC_GIT" fetch -q origin "+refs/heads/$AIC_BRANCH:$tracking" || rc=$?
      if [ "$rc" -eq 0 ]; then
        AIC_REMOTE_STATE=present
        remote_ref="$tracking"
      else
        AIC_REMOTE_STATE=unreachable
        _aic_offline_line "fetch from $remote failed"
        remote=""
      fi
    else
      AIC_REMOTE_STATE=absent
    fi
  fi
  rm -f "$out"
  if [ -n "$remote_ref" ]; then
    if ! _aic_head; then
      _aic_adopt "$remote_ref"
      _aic_note "ai-sync: private AI docs restored from $remote ($AIC_BRANCH)"
    elif [ -z "$(_aic merge-base HEAD "$remote_ref" 2>/dev/null)" ]; then
      # Unrelated histories (two machines started separately): the remote's wins over a single
      # local commit (differing files saved, see _aic_adopt); anything more is merged by hand.
      if [ "$(_aic rev-list --count HEAD 2>/dev/null)" = 1 ]; then
        _aic_adopt "$remote_ref"
        _aic_note "ai-sync: private AI docs updated from $remote"
      else
        unrelated=true
      fi
    fi
  fi
  _aic_import_memory || true
  _aic_commit
  if [ "$unrelated" = true ]; then
    echo "ai-sync: private AI docs: local and $remote histories are unrelated — nothing pushed; merge by hand: git --git-dir=$AIC_GIT --work-tree=$AIC_TREE merge --allow-unrelated-histories $remote_ref"
    return 0
  fi
  if [ -n "$remote_ref" ]; then
    head_before="$(_aic rev-parse HEAD 2>/dev/null)"
    _factory_rebase "$remote" "$remote_ref" || return 0
    if ! _aic merge-base --is-ancestor HEAD "$head_before" >/dev/null 2>&1; then
      _aic_note "ai-sync: private AI docs updated from $remote"
    fi
  fi
  # Never a push the remote would refuse: HEAD must contain the remote branch last seen (unrelated
  # or conflicting histories were reported by the download that fetched it). A push skipped for
  # lack of network time stays quiet: the step that timed out was reported.
  if [ -n "$remote" ] && _aic_head \
     && [ "$(_aic rev-parse HEAD)" != "$(_aic rev-parse -q --verify "$tracking" 2>/dev/null)" ] \
     && { ! _aic rev-parse -q --verify "$tracking" >/dev/null 2>&1 \
          || _aic merge-base --is-ancestor "$tracking" HEAD >/dev/null 2>&1; }; then
    out="$(mktemp "${TMPDIR:-/tmp}/ai-sync-aic.XXXXXX")"
    rc=0
    _run_bounded "$out" git -C "$AIC_TREE" --git-dir="$AIC_GIT" push -q origin "HEAD:refs/heads/$AIC_BRANCH" || rc=$?
    rm -f "$out"
    if [ "$rc" -eq 0 ]; then
      _aic update-ref "$tracking" HEAD >/dev/null 2>&1 || true
    elif [ "$AIC_SWITCHING" = false ] && [ "$NET_SKIPPED" = false ]; then
      echo "ai-sync: private AI docs: push to $remote failed — retried next time"
    fi
  fi
  [ -z "$AIC_COMMITTED" ] || _aic_note "ai-sync: private AI docs committed ($AIC_COMMITTED)"
  if [ "$AIC_REMOTE_STATE" = unreachable ] && ! _aic_head; then AIC_DOCS_WAIT=true; fi
  [ "$AIC_SWITCHING" = false ] || _aic_switch_ready
  return 0
}

# _aic_switch_ready — AIC_SWITCH_READY for a --switch round trip: no remote is set, or a bounded
# ls-remote shows the remote's branch at the hidden HEAD (with no hidden commit at all, the remote
# having answered is enough: there is nothing to lose).
_aic_switch_ready() {
  local out rc=0 sha=""
  if [ -z "$AIC_REMOTE" ]; then
    AIC_SWITCH_READY=true
    return 0
  fi
  case "$AIC_REMOTE_STATE" in absent|present) ;; *) return 0 ;; esac
  if ! _aic_head; then
    AIC_SWITCH_READY=true
    return 0
  fi
  out="$(mktemp "${TMPDIR:-/tmp}/ai-sync-aic.XXXXXX")"
  _run_bounded "$out" git -C "$AIC_TREE" --git-dir="$AIC_GIT" ls-remote origin "refs/heads/$AIC_BRANCH" || rc=$?
  [ "$rc" -ne 0 ] || sha="$(awk 'NR == 1 { print $1 }' "$out" 2>/dev/null)" || sha=""
  rm -f "$out"
  if [ -n "$sha" ] && [ "$sha" = "$(_aic rev-parse HEAD 2>/dev/null)" ]; then AIC_SWITCH_READY=true; fi
  return 0
}

# The code root's .ai-root checkout (see _code_root): projects/<name> records each project's
# mode ("mode=" and "origin=" lines), read by _registry_mode when a project has no exclude block
# yet (a fresh clone). Writers take <its git dir>/ai-sync.lock (_sync_lock) and never wait for it.

# _ai_root_upstream <air> — "<remote> <ref>" of the checked-out branch's upstream, or nothing.
_ai_root_upstream() {
  local br rem merge
  br="$(git -C "$1" symbolic-ref -q --short HEAD 2>/dev/null)" || return 0
  rem="$(git -C "$1" config --get "branch.$br.remote" 2>/dev/null)" || return 0
  merge="$(git -C "$1" config --get "branch.$br.merge" 2>/dev/null)" || return 0
  git -C "$1" rev-parse -q --verify '@{u}' >/dev/null 2>&1 || return 0
  printf '%s %s\n' "$rem" "$merge"
}

# _ai_root_busy <air> <git-dir> — true (and one line, $3 being its tail) when the checkout is
# mid-rebase/merge or has uncommitted changes.
_ai_root_busy() {
  if [ -d "$2/rebase-merge" ] || [ -d "$2/rebase-apply" ] || [ -e "$2/MERGE_HEAD" ]; then
    echo "ai-sync: .ai-root has a rebase or merge in progress — $3"
    return 0
  fi
  if [ -n "$(git -C "$1" status --porcelain 2>/dev/null)" ]; then
    echo "ai-sync: .ai-root has uncommitted changes — $3"
    return 0
  fi
  return 1
}

# _registry_record <target> <mode> — record the mode a switch just gave the project in
# <root>/.ai-root/projects/<name>, commit that file alone and push it. Only inside a known root
# whose .ai-root is a git checkout; the caller never calls it on --dry-run. A held lock, a dirty
# or mid-rebase checkout, or a pull still running is one line and a skip; a failed push is one
# line (the next session start's --pull pushes it).
_registry_record() {
  local target="$1" mode="$2" root air gitdir top name
  root="$(_code_root "$target")"
  [ -n "$root" ] || return 0
  air="$(_ai_root_checkout "$root")"
  [ -n "$air" ] || return 0
  gitdir="$(git -C "$air" rev-parse --absolute-git-dir 2>/dev/null)" || return 0
  top="$(_git_top "$target")"
  name="$(basename "$top")"
  if ! _sync_lock "$gitdir/ai-sync.lock"; then
    echo "ai-sync: .ai-root is locked by another sync — $name = $mode not recorded"
    return 0
  fi
  _registry_write "$air" "$gitdir" "$top" "$name" "$mode" || true
  rm -rf "$gitdir/ai-sync.lock"
  return 0
}

# _registry_write <air> <git-dir> <top> <name> <mode> — the locked half of _registry_record.
_registry_write() {
  local air="$1" gitdir="$2" top="$3" name="$4" mode="$5" skip upstream rc out file rel new origin was_tracked=false
  skip="$name = $mode not recorded"
  _ai_root_busy "$air" "$gitdir" "$skip" && return 0
  upstream="$(_ai_root_upstream "$air")"
  if [ -n "$upstream" ]; then
    out="$(mktemp "${TMPDIR:-/tmp}/ai-sync-root.XXXXXX")"
    rc=0
    _run_bounded "$out" git -C "$air" pull -q --rebase || rc=$?
    rm -f "$out"
    if [ "$rc" -eq 124 ] && [ "$NET_SKIPPED" = false ]; then
      echo "ai-sync: .ai-root pull still running — $skip"
      return 0
    fi
    # Offline, or no network time left: record locally, the push below fails and says so. A
    # conflict: leave it as it was.
    if [ "$rc" -ne 0 ] && { [ -d "$gitdir/rebase-merge" ] || [ -d "$gitdir/rebase-apply" ]; }; then
      git -C "$air" rebase --abort >/dev/null 2>&1 || true
      echo "ai-sync: .ai-root pull --rebase failed — $skip"
      return 0
    fi
  fi
  rel="projects/$name"
  file="$air/$rel"
  origin="$(git -C "$top" config --get remote.origin.url 2>/dev/null | tr -d '\r')" || origin=""
  new="$(mktemp "${TMPDIR:-/tmp}/ai-sync-registry.XXXXXX")"
  {
    printf 'mode=%s\n' "$mode"
    [ -z "$origin" ] || printf 'origin=%s\n' "$origin"
    if [ -f "$file" ]; then
      tr -d '\r' < "$file" | grep -v -e '^mode=' -e '^origin=' -e '^[[:space:]]*$' || true
    fi
  } > "$new"
  # CR-blind: a Windows checkout (core.autocrlf) holds the same entry with CRLF endings.
  if [ -f "$file" ] && tr -d '\r' < "$file" | cmp -s "$new" -; then
    rm -f "$new"
    return 0
  fi
  git -C "$air" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1 && was_tracked=true
  mkdir -p "$air/projects"
  cat "$new" > "$file"
  rm -f "$new"
  if ! { git -C "$air" add -- "$rel" && git -C "$air" commit -q -m "chore(registry): $name = $mode" -- "$rel"; } >/dev/null 2>&1; then
    if [ "$was_tracked" = true ]; then
      git -C "$air" checkout -q HEAD -- "$rel" >/dev/null 2>&1 || true
    else
      git -C "$air" rm -q --cached -- "$rel" >/dev/null 2>&1 || true
      rm -f "$file"
    fi
    echo "ai-sync: .ai-root commit failed (git identity?) — $skip"
    return 0
  fi
  _say "  [registry] .ai-root/$rel: mode=$mode"
  [ -n "$upstream" ] || return 0
  out="$(mktemp "${TMPDIR:-/tmp}/ai-sync-root.XXXXXX")"
  rc=0
  _run_bounded "$out" git -C "$air" push -q "${upstream%% *}" "HEAD:${upstream#* }" || rc=$?
  rm -f "$out"
  [ "$rc" -eq 0 ] || echo "ai-sync: $name = $mode committed in .ai-root — pushed at the next session start"
  return 0
}

# ai_root_pull <code-root> — the session start's --pull of <root>/.ai-root: a bounded
# `git pull --ff-only`, then a push when it is ahead of its upstream (a registry commit whose
# push failed). Once per run, before anything reads the registry. Never fails: a dirty checkout,
# a held lock, offline or a timeout is one line; nothing to do (or no upstream) is silent.
ai_root_pull() {
  local air gitdir upstream rc out before ahead
  air="$(_ai_root_checkout "${1:-}")"
  [ -n "$air" ] || return 0
  gitdir="$(git -C "$air" rev-parse --absolute-git-dir 2>/dev/null)" || return 0
  upstream="$(_ai_root_upstream "$air")"
  [ -n "$upstream" ] || return 0
  if ! _sync_lock "$gitdir/ai-sync.lock"; then
    echo "ai-sync: .ai-root is locked by another sync — pull skipped"
    return 0
  fi
  if ! _ai_root_busy "$air" "$gitdir" "pull skipped"; then
    before="$(git -C "$air" rev-parse HEAD 2>/dev/null)"
    out="$(mktemp "${TMPDIR:-/tmp}/ai-sync-root.XXXXXX")"
    rc=0
    _run_bounded "$out" git -C "$air" pull -q --ff-only || rc=$?
    if [ "$rc" -eq 124 ] && [ "$NET_SKIPPED" = true ]; then
      echo "ai-sync: .ai-root pull skipped (no network time left in this run) — using the registry on disk"
    elif [ "$rc" -eq 124 ]; then
      echo "ai-sync: .ai-root pull still running after ${NET_LIMIT}s — using the registry on disk"
    elif [ "$rc" -ne 0 ]; then
      echo "ai-sync: .ai-root pull failed (offline, or diverged from its upstream) — using the registry on disk"
    else
      [ "$(git -C "$air" rev-parse HEAD 2>/dev/null)" = "$before" ] || _say "ai-sync: pulled latest .ai-root"
      ahead="$(git -C "$air" rev-list --count '@{u}..HEAD' 2>/dev/null)" || ahead=0
      if [ "${ahead:-0}" != 0 ]; then
        rc=0
        _run_bounded "$out" git -C "$air" push -q "${upstream%% *}" "HEAD:${upstream#* }" || rc=$?
        if [ "$rc" -eq 0 ]; then
          _say "ai-sync: pushed .ai-root ($ahead commit(s))"
        else
          echo "ai-sync: .ai-root push failed — retried next time"
        fi
      fi
    fi
    rm -f "$out"
  fi
  rm -rf "$gitdir/ai-sync.lock"
  return 0
}

# --- install-global helpers (sourced by install-global.sh; the tests call them directly) -------

# root_remote_parse <arg> <default-root> — aicf setup --ai-context-remote: sets ROOT_REMOTE_DIR
# (absolute) and ROOT_REMOTE_URL. "<root>=<url>" when the part before the first = is an existing
# folder; else the whole argument is the URL of <default-root> (the root holding this repo),
# refused when that root is a work root (none excepted: it only disables). A github.com URL is
# refused for a work root (_is_work_path). A refusal is one Error: line on stderr and status 2.
root_remote_parse() {
  local arg="$1" root="$2" url="$1" head explicit=false
  ROOT_REMOTE_DIR=""
  ROOT_REMOTE_URL=""
  case "$arg" in
    *=*)
      head="${arg%%=*}"
      if [ -n "$head" ] && [ -d "$head" ]; then
        root="$head"
        url="${arg#*=}"
        explicit=true
      fi ;;
  esac
  if [ -z "$url" ]; then
    echo "Error: --ai-context-remote needs a git URL (or none): <url> or <root>=<url>" >&2
    return 2
  fi
  if ! root="$(cd "$root" 2>/dev/null && pwd)"; then
    echo "Error: code root not found: $2" >&2
    return 2
  fi
  if _is_work_path "$root"; then
    if [ "$explicit" = false ] && [ "$url" != none ]; then
      echo "Error: --ai-context-remote <url> sets the remote of $root, a work root — name the root: --ai-context-remote <root>=<url>" >&2
      return 2
    fi
    case "$(printf '%s' "$url" | tr '[:upper:]' '[:lower:]')" in
      *github.com*)
        echo "Error: $url is a github.com remote — refused for the work root $root" >&2
        return 2 ;;
    esac
  fi
  ROOT_REMOTE_DIR="$root"
  ROOT_REMOTE_URL="$url"
  return 0
}

# root_remote_write — write ROOT_REMOTE_URL to $ROOT_REMOTE_DIR/.ai-context-remote (LF, one line).
root_remote_write() {
  [ -n "$ROOT_REMOTE_DIR" ] && [ -n "$ROOT_REMOTE_URL" ] || return 0
  printf '%s\n' "$ROOT_REMOTE_URL" > "$ROOT_REMOTE_DIR/.ai-context-remote"
  echo "Recorded the private AI docs remote of $ROOT_REMOTE_DIR: $ROOT_REMOTE_DIR/.ai-context-remote -> $ROOT_REMOTE_URL"
}

# ai_root_clone <root> — clone the owner's root repo (branch _root of the first line of
# <root>/.ai-context-remote) into <root>/.ai-root when it is missing. An existing .ai-root, no
# remote file, an empty one or none: nothing. A github.com remote under a work root is refused.
# Bounded like every network step (_run_bounded) and never fatal: one line, always status 0.
ai_root_clone() {
  local root="${1%/}" url out rc=0
  [ -n "$root" ] && [ -d "$root" ] || return 0
  [ ! -e "$root/.ai-root" ] || return 0
  [ -s "$root/.ai-context-remote" ] || return 0
  url="$(head -n 1 "$root/.ai-context-remote" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  case "$url" in ''|none) return 0 ;; esac
  if _is_work_path "$root"; then
    case "$(printf '%s' "$url" | tr '[:upper:]' '[:lower:]')" in
      *github.com*)
        echo "NOTE: $root/.ai-root not cloned — $url is a github.com remote, refused under a work root"
        return 0 ;;
    esac
  fi
  out="$(mktemp "${TMPDIR:-/tmp}/ai-sync-clone.XXXXXX")" || return 0
  _run_bounded "$out" git clone -q -b _root "$url" "$root/.ai-root" || rc=$?
  rm -f "$out"
  if [ "$rc" -eq 0 ]; then
    echo "Cloned the root repo: $root/.ai-root (branch _root of $url)"
  elif [ "$rc" -eq 124 ] && [ "$NET_SKIPPED" = true ]; then
    echo "NOTE: $root/.ai-root not cloned (no network time left) — re-run aicf setup"
  elif [ "$rc" -eq 124 ]; then
    echo "NOTE: $root/.ai-root clone still running after ${NET_LIMIT}s — it finishes in the background"
  else
    echo "NOTE: $root/.ai-root not cloned from $url (offline, or no _root branch) — re-run aicf setup"
  fi
  return 0
}

# install_claude_global_hook <settings-file> — merge the global SessionStart hook
# (templates/global/claude-global-hook.json: the engine with --global-hook) into Claude Code's user
# settings. Every other key and hook is kept; ours is the SessionStart entry whose JSON holds
# "--global-hook": replaced in place when it differs, appended when absent, extra copies dropped.
# A missing or empty file starts as {}. A file that does not parse, or whose root, "hooks" or
# "hooks.SessionStart" has the wrong type, is left untouched. One line either way; needs python
# (else pwsh: Install-ClaudeGlobalHook of the twin). Always status 0.
install_claude_global_hook() {
  local file="$1" entry="$TEMPLATE_DIR/templates/global/claude-global-hook.json" py="" script="" rc=0
  py="$(_memory_py 2>/dev/null)" || py=""
  if [ -n "$py" ]; then
    script="$(mktemp "${TMPDIR:-/tmp}/ai-sync-hook.XXXXXX.py")" || script=""
  fi
  if [ -n "$script" ]; then
    cat > "$script" <<'PY'
import json, os, sys
path, entry_path = sys.argv[1], sys.argv[2]
try:
    with open(entry_path, "r", encoding="utf-8-sig") as fh:
        entry = json.load(fh)
except Exception:
    sys.exit(6)
try:
    if os.path.isfile(path) and os.path.getsize(path) > 0:
        with open(path, "r", encoding="utf-8-sig") as fh:
            raw = fh.read()
        data = {} if raw.strip() == "" else json.loads(raw)
    else:
        data = {}
except Exception:
    sys.exit(2)
if not isinstance(data, dict):
    sys.exit(2)
hooks = data.get("hooks")
if hooks is None:
    hooks = {}
if not isinstance(hooks, dict):
    sys.exit(4)
starts = hooks.get("SessionStart")
if starts is None:
    starts = []
if not isinstance(starts, list):
    sys.exit(4)
ours = [i for i, e in enumerate(starts) if e is not None and "--global-hook" in json.dumps(e)]
if len(ours) == 1 and starts[ours[0]] == entry:
    sys.exit(0)
if ours:
    starts = [entry if i == ours[0] else e for i, e in enumerate(starts) if i == ours[0] or i not in ours]
    code = 3
else:
    starts = starts + [entry]
    code = 5
hooks["SessionStart"] = starts
data["hooks"] = hooks
parent = os.path.dirname(path)
if parent:
    os.makedirs(parent, exist_ok=True)
tmp = path + ".ai-sync-tmp"
with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
    fh.write(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
os.replace(tmp, path)
sys.exit(code)
PY
    "$py" "$script" "$file" "$entry" || rc=$?
    rm -f "$script"
  elif command -v pwsh >/dev/null 2>&1; then
    # The twin does the merge: one implementation of the rules.
    script="$(mktemp "${TMPDIR:-/tmp}/ai-sync-hook.XXXXXX.ps1")" || script=""
    if [ -n "$script" ]; then
      printf '%s\n' 'param([string]$Engine, [string]$SettingsFile)' '. $Engine' \
        'Install-ClaudeGlobalHook $SettingsFile' > "$script"
      pwsh -NoProfile -File "$script" "$TEMPLATE_DIR/sync-ai-templates.ps1" "$file" || true
      rm -f "$script"
      return 0
    fi
    rc=7
  else
    rc=7
  fi
  case "$rc" in
    0) echo "  global SessionStart hook up to date: $file" ;;
    3) echo "  refreshed global SessionStart hook: $file" ;;
    5) echo "  registered global SessionStart hook: $file" ;;
    2) echo "  skipped global SessionStart hook (unparseable JSON, or its root is not an object): $file" ;;
    4) echo "  skipped global SessionStart hook (hooks or hooks.SessionStart has an unexpected type): $file" ;;
    7) echo "NOTE: global SessionStart hook not merged into $file (no python or pwsh)" ;;
    *) echo "  skipped global SessionStart hook (merge failed): $file" ;;
  esac
  return 0
}

# install_claude_profiles <code-root> — one Claude Code profile per code root that declares one in
# <root>/.ai-root/claude-profile.json ({"config_dir": "~/.claude-<x>", "settings": {…}}), looked
# for in the code root and its sibling folders. Each profile's config dir gets the "settings"
# merged into its settings.json (top-level keys replaced, object values such as env merged key by
# key, other keys kept) plus AI_TEMPLATE_DIR / AI_CODE_ROOT, the global SessionStart hook and the
# skills. ~/.claude-profiles records "<root><TAB><config-dir>" per profile (removed when none), and
# a managed block in ~/.zshrc and ~/.bashrc (those that exist; AI_SHELL_PROFILES, a
# path-separator list, overrides) defines `claude` from templates/global/claude-profiles.sh: run
# inside a recorded root, it sets CLAUDE_CONFIG_DIR. Secrets never go in the profile file: an
# apiKeyHelper or /login. One line per file; needs python. Always status 0.
install_claude_profiles() {
  local code_root="$1" py root dir
  py="$(_memory_py 2>/dev/null)" || py=""
  if [ -z "$py" ]; then
    echo "NOTE: Claude Code profiles not installed (no python)"
    return 0
  fi
  "$py" - "$code_root" "$HOME" "$TEMPLATE_DIR" "${OVERLAY_DIR:-}" "${AI_SHELL_PROFILES:-}" <<'PY' || true
import json, os, sys
code_root, home, tdir, odir, rcs_env = sys.argv[1:6]
BEGIN, END = "# >>> AICodeFactory claude-profiles >>>", "# <<< AICodeFactory claude-profiles <<<"
parent = os.path.dirname(os.path.realpath(code_root))
profiles = []
for name in sorted(os.listdir(parent)):
    root = os.path.join(parent, name)
    f = os.path.join(root, ".ai-root", "claude-profile.json")
    if not os.path.isfile(f):
        continue
    try:
        with open(f, encoding="utf-8-sig") as fh:
            p = json.load(fh)
        cfg, settings = p.get("config_dir"), p.get("settings", {})
        if not (isinstance(cfg, str) and cfg.strip() and isinstance(settings, dict)):
            raise ValueError
    except Exception:
        print(f"NOTE: {f} skipped (a JSON object with a config_dir string and an optional settings object)")
        continue
    cfg = os.path.abspath(os.path.expanduser(cfg.strip()))
    os.makedirs(os.path.join(cfg, "skills"), exist_ok=True)
    sf = os.path.join(cfg, "settings.json")
    try:
        raw = open(sf, encoding="utf-8-sig").read() if os.path.isfile(sf) else ""
        data = json.loads(raw) if raw.strip() else {}
        if not isinstance(data, dict):
            raise ValueError
    except Exception:
        print(f"  skipped Claude profile settings (unparseable JSON, or its root is not an object): {sf}")
        profiles.append((os.path.realpath(root), cfg))
        continue
    want = json.loads(json.dumps(data))
    env = {"AI_TEMPLATE_DIR": tdir, "AI_CODE_ROOT": code_root}
    if odir:
        env["AI_TEMPLATE_OVERLAY_DIR"] = odir
    for k, v in list(settings.items()) + [("env", env)]:  # a null (define's tombstone) drops a key
        base = want[k] if isinstance(v, dict) and isinstance(want.get(k), dict) else {}
        want[k] = {n: x for n, x in {**base, **v}.items() if v.get(n, 0) is not None} if isinstance(v, dict) else v
    if want == data:
        print(f"  Claude profile settings up to date: {sf}")
    else:
        with open(sf + ".ai-sync-tmp", "w", encoding="utf-8", newline="\n") as fh:
            fh.write(json.dumps(want, indent=2, ensure_ascii=False) + "\n")
        os.replace(sf + ".ai-sync-tmp", sf)
        print(f"  {'refreshed' if raw.strip() else 'registered'} Claude profile settings: {sf}")
    profiles.append((os.path.realpath(root), cfg))
record = os.path.join(home, ".claude-profiles")
if profiles:
    body = "".join(f"{r}\t{c}\n" for r, c in profiles)
    old = open(record, encoding="utf-8").read() if os.path.isfile(record) else None
    if old != body:
        with open(record, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(body)
    print(f"  Claude profiles: {', '.join(os.path.basename(r) + ' -> ' + c for r, c in profiles)} ({record})")
elif os.path.isfile(record):
    os.remove(record)
    print(f"  removed {record} (no code root declares a Claude profile)")
if rcs_env:
    rcs = [r for r in rcs_env.split(os.pathsep) if r]
else:
    rcs = [os.path.join(home, r) for r in (".zshrc", ".bashrc") if os.path.isfile(os.path.join(home, r))]
    if not rcs and profiles:
        rcs = [os.path.join(home, ".zshrc" if os.environ.get("SHELL", "").endswith("zsh") else ".bashrc")]
snippet = open(os.path.join(tdir, "templates", "global", "claude-profiles.sh"), encoding="utf-8").read().replace("\r\n", "\n")
block = f"{BEGIN}\n{snippet.rstrip()}\n{END}\n"
for rc in rcs:
    text = open(rc, encoding="utf-8").read() if os.path.isfile(rc) else ""
    i, j = text.find(BEGIN), text.find(END)
    has = i >= 0 and j > i
    if has:
        j = text.find("\n", j)
        j = len(text) if j < 0 else j + 1
    if not profiles:
        if has:
            new = text[:i].rstrip("\n") + ("\n" if text[:i].strip() else "") + text[j:]
            with open(rc, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(new)
            print(f"  removed the claude profile function: {rc}")
        continue
    new = text[:i] + block + text[j:] if has else text + ("\n" if text and not text.endswith("\n") else "") + ("\n" if text else "") + block
    if new == text:
        print(f"  claude profile function up to date: {rc}")
        continue
    with open(rc, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(new)
    print(f"  {'refreshed' if has else 'added'} the claude profile function: {rc}")
PY
  [ -r "$HOME/.claude-profiles" ] || return 0
  while IFS=$'\t' read -r root dir <&3; do
    dir="${dir%$'\r'}"
    [ -n "$dir" ] && install_claude_global_hook "$dir/settings.json"
  done 3< "$HOME/.claude-profiles"
  _profile_skill_roots
  return 0
}

# Skills install and dev-context: engine/sync-skills.sh; name spelling: engine/names.sh; work roots:
# engine/work-roots.sh; the overlay per target: engine/overlay.sh (this file stays under its record).
. "$TEMPLATE_DIR/engine/names.sh"
. "$TEMPLATE_DIR/engine/work-roots.sh"
. "$TEMPLATE_DIR/engine/factory-hook.sh"
. "$TEMPLATE_DIR/engine/sync-skills.sh"

_usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Standalone invocation: ./sync-ai-templates.sh [<project-dir>] [flags]
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  target="."
  opts=()
  rerun=()
  do_pull=false
  do_agents=false
  do_skills=false
  do_scan=false
  do_aic_only=false
  do_root_sync=false
  do_global_hook=false
  scan_history=""
  for arg in "$@"; do
    [ "$arg" = "--pull" ] || rerun+=("$arg")
    case "$arg" in
      --dry-run|--commit|--quiet|--push|--shared|--private-layer|--private-docs) opts+=("$arg") ;;
      --ai-context-sync) do_aic_only=true ;;
      --root-sync) do_root_sync=true ;;
      --pull)   do_pull=true ;;
      --agents) do_agents=true ;;
      --skills) do_skills=true ;;
      --scan-private) do_scan=true ;;
      --history) scan_history="--history" ;;
      --global-hook) do_global_hook=true ;;
      -h|--help) _usage; exit 0 ;;
      -*) echo "Unknown option: $arg" >&2; _usage >&2; exit 2 ;;
      *) target="$arg" ;;
    esac
  done
  # The global hook (~/.claude/settings.json): its own plan, whatever else was passed.
  if [ "$do_global_hook" = true ]; then
    case "$(_global_hook_plan "$target")" in
      run)
        opts=(--quiet --commit)
        rerun=("$target" --quiet --commit --agents --skills)
        do_pull=true; do_agents=true; do_skills=true; do_scan=false; do_aic_only=false ;;
      suggest) _conform_line "$target"; exit 0 ;;
      *) exit 0 ;;
    esac
  fi
  skills_flag=""
  agents_flags=()
  aic_flags=()
  main_dry=false
  make_private_opt=false
  for arg in ${opts[@]+"${opts[@]}"}; do
    [ "$arg" = "--quiet" ] && SYNC_QUIET=true
    [ "$arg" = "--dry-run" ] && main_dry=true && skills_flag="--dry-run" && agents_flags+=(--dry-run) && aic_flags+=(--dry-run)
    [ "$arg" = "--commit" ] && agents_flags+=(--commit)
    case "$arg" in --private-layer|--private-docs) make_private_opt=true ;; esac
  done
  [ "$main_dry" = false ] || make_private_opt=false
  if [ "$do_scan" = true ]; then
    rc=0; scan_private_terms "$target" $scan_history || rc=$?
    exit $rc
  fi
  if [ "$do_root_sync" = true ]; then
    [ "$main_dry" = false ] || exit 0
    net_budget_reset
    ai_root_pull "$(cd "$target" 2>/dev/null && pwd)"
    exit 0
  fi
  if [ "$do_aic_only" = true ]; then
    ai_context_sync "$target" ${aic_flags[@]+"${aic_flags[@]}"}
    [ -z "$AIC_OLD_BRANCH" ] || _old_branch_line "$(basename "$AIC_TREE")" "$AIC_OLD_BRANCH"
    exit 0
  fi
  if [ "$do_pull" = true ]; then
    # A new network budget (AI_SYNC_NET_BUDGET) for this run; the re-run below inherits it.
    [ "$main_dry" = true ] || net_budget_reset
    # The code root's .ai-root first, exactly once: the re-run below has no --pull, and the
    # registry must be current before ai_context_sync reads a fresh clone's mode from it.
    [ "$main_dry" = true ] || ai_root_pull "$(_code_root "$target")"
    pull_template
    # The pull may have changed this very script: re-run the new one, without --pull.
    [ "$PULL_UPDATED" = true ] && exec "$BASH" "${BASH_SOURCE[0]}" ${rerun[@]+"${rerun[@]}"}
  fi
  # Private AI docs: download before the sync (a fresh clone gets its docs back instead of blank
  # templates), upload after it and the AGENTS.md refresh. Both are no-ops in other projects.
  # --private-layer: sync_ai_templates runs the download itself (the switch order needs it there).
  # A switch that waits for the remote changes nothing more: no AGENTS.md refresh, no upload.
  [ "$make_private_opt" = true ] || ai_context_sync "$target" ${aic_flags[@]+"${aic_flags[@]}"}
  sync_ai_templates "$target" ${opts[@]+"${opts[@]}"}
  if [ "$SYNC_SWITCH_WAITS" = false ]; then
    if [ "$do_agents" = true ]; then refresh_agents_md "$target" ${agents_flags[@]+"${agents_flags[@]}"}; fi
    [ ${#aic_flags[@]} -gt 0 ] || ai_context_sync "$target" --no-fetch
  fi
  if [ "$do_skills" = true ]; then refresh_global_skills $skills_flag; fi
  exit 0
fi
