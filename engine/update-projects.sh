#!/usr/bin/env bash
# Refresh the AI-instruction files across sibling projects of this template repo — and, on
# request, first bring the code root itself up to date with GitHub.
#
# Normally unnecessary: every project re-syncs itself at session start (Claude Code
# SessionStart hook / AGENTS.md session-start step). Use this for a one-shot bulk refresh —
# e.g. right after a template change, on a new machine, or to migrate old symlink layouts — or
# to bootstrap a project that has no AI files yet.
#
# Usage:
#   aicf update <project-name>               # refresh (or first-time bootstrap) one project
#   aicf update <path>                       # the same for a project of another code root
#   aicf update                              # preview every bootstrapped sibling (dry-run)
#   aicf update --yes                        # apply to every bootstrapped sibling
#   aicf update --dry-run [name]             # explicit preview, no writes
#   aicf update --yes --push                 # also push each sync commit (needs an upstream branch)
#   aicf update --yes --clone --pull --push  # the whole code root, GitHub included
#   aicf update --check                      # table: each repo's mode against the private-layer plan
#   aicf update --migrate                    # preview the switches (no writes)
#   aicf update --migrate --yes              # apply them; never pushes a code repo (--push ignored)
#     --clone   clone every GitHub repo of yours (gh repo list) that has no local folder yet:
#               not archived, not empty, not *-private-archive. A local folder matches by name
#               (case-insensitive) or by its origin's repo name. Needs an authenticated gh.
#     --pull    first fast-forward this template repo (re-running itself when it moved), then
#               every git sibling that tracks a remote. A dirty tree or a branch that diverged
#               from its remote is reported and left alone — never merged, never stashed.
#               A preview only fetches and says how far behind each one is. The code root's
#               .ai-root (the project registry) is fast-forwarded once per run, not previewed.
#
# Each processed project also gets its generic AGENTS.md sections refreshed
# (refresh-agents-sections.py: never a customized section, never a shared project).
# Every run ends with a report of the repos holding commits that are not on their remote —
# the one thing the session-start sync deliberately never does on its own.
#
# Bulk runs only touch projects that already own an AGENTS.md; un-bootstrapped repos are
# listed and left alone (bootstrap those explicitly by name, or with /bootstrap-ai).
# Commits are paths-only, so a project with work in progress is refreshed without that work
# being swept into the sync commit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # the template repo (this file is in engine/)
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATE_NAME="$(basename "$SCRIPT_DIR")"

# shellcheck source=../sync-ai-templates.sh
source "$SCRIPT_DIR/sync-ai-templates.sh"

DRY_RUN=false
CONFIRM=false
PUSH=false
CLONE=false
PULL=false
CHECK=false
MIGRATE=false
TEMPLATE_PULLED=false   # --template-pulled: internal, set by the re-run after the template moved
ONLY=""
RERUN=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --yes) CONFIRM=true ;;
    --push) PUSH=true ;;
    --clone) CLONE=true ;;
    --pull) PULL=true ;;
    --check) CHECK=true ;;
    --migrate) MIGRATE=true ;;
    --template-pulled) TEMPLATE_PULLED=true ;;
    -h|--help) sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "Unknown option: $arg" >&2; exit 2 ;;
    *) ONLY="$arg" ;;
  esac
  RERUN+=("$arg")
done

PROCESSED=()
# A name is a sibling; a path (it holds a slash) is any project, another code root's included.
ONLY_DIR=""
case "$ONLY" in
  "") ;;
  */*|*\\*) ONLY_DIR="${ONLY%/}" ;;
  *) ONLY_DIR="$PARENT_DIR/$ONLY" ;;
esac

# Bulk runs (no specific project named) default to a preview unless --yes is passed.
# Targeting a single project by name is low blast-radius enough to just run directly.
if [ -z "$ONLY" ] && [ "$DRY_RUN" = false ] && [ "$CONFIRM" = false ] && [ "$CHECK" = false ] && [ "$MIGRATE" = false ]; then
  echo "No project named — previewing changes for ALL bootstrapped sibling projects."
  echo "Pass --yes to apply to all of them, or name one project to update it directly."
  echo
  DRY_RUN=true
fi

# The template first: everything below should run with the latest engine and templates.
if [ "$PULL" = true ] && [ "$DRY_RUN" = false ] && [ "$TEMPLATE_PULLED" = false ]; then
  pull_template
  if [ "$PULL_UPDATED" = true ]; then
    echo "PULLED        $TEMPLATE_NAME — re-running with the new version"
    exec "$BASH" "${BASH_SOURCE[0]}" "${RERUN[@]}" --template-pulled
  fi
fi

# --clone: GitHub repos of the authenticated user that have no local folder yet.
clone_missing() {
  local nl=$'\n' listing known dir slug full name lower
  known="$nl"   # newline-delimited, so a match is *"$nl$name$nl"* (no grep: SIGPIPE + pipefail)
  if ! command -v gh >/dev/null 2>&1; then
    echo "SKIP          --clone (gh not installed)"
    return 0
  fi
  if ! listing="$(gh repo list --limit 1000 --json nameWithOwner,isArchived,isEmpty \
      --jq '.[] | select(.isArchived | not) | select(.isEmpty | not) | .nameWithOwner' 2>/dev/null)"; then
    echo "SKIP          --clone (gh repo list failed — run gh auth login)"
    return 0
  fi
  # Local names, lowercased: folder names and the repo name each origin points at. Dot-folders
  # are left out, except .ai-root: its origin (the root's config repo) is never a project to clone.
  for dir in "$PARENT_DIR"/*/ "$PARENT_DIR/.ai-root/"; do
    [ -d "$dir" ] || continue
    dir="${dir%/}"
    known="$known$(basename "$dir" | tr '[:upper:]' '[:lower:]')$nl"
    slug="$(git -C "$dir" remote get-url origin 2>/dev/null)" || continue
    slug="${slug%/}"; slug="${slug%.git}"; slug="${slug##*/}"; slug="${slug##*:}"
    [ -z "$slug" ] || known="$known$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]')$nl"
  done
  while IFS= read -r full; do
    full="${full%$'\r'}"
    [ -n "$full" ] || continue
    name="${full##*/}"
    case "$name" in *-private-archive) continue ;; esac
    lower="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
    case "$known" in *"$nl$lower$nl"*) continue ;; esac
    if [ "$DRY_RUN" = true ]; then
      echo "PLAN          clone $full -> $name"
    elif gh repo clone "$full" "$PARENT_DIR/$name" -- -q >/dev/null 2>&1; then
      echo "CLONED        $name"
    else
      echo "CLONE-FAILED  $name (gh repo clone $full)"
    fi
    known="$known$lower$nl"
  done <<EOF
$listing
EOF
}

# --pull: fast-forward one sibling. Never merges, never stashes.
pull_one() {
  local dir="$1" name behind
  name="$(basename "$dir")"
  [ "$name" = "$TEMPLATE_NAME" ] && return 0
  [ -e "$dir/.git" ] || return 0
  git -C "$dir" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1 || { echo "PULL-SKIP     $name (no upstream branch)"; return 0; }
  if ! GIT_TERMINAL_PROMPT=0 git -C "$dir" fetch -q 2>/dev/null; then
    echo "PULL-SKIP     $name (fetch failed — offline or auth)"
    return 0
  fi
  behind="$(git -C "$dir" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)"
  [ "$behind" != 0 ] || return 0
  if [ "$DRY_RUN" = true ]; then
    echo "PLAN          pull $name ($behind commit(s) behind)"
    return 0
  fi
  if [ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]; then
    echo "PULL-SKIP     $name ($behind behind, uncommitted changes — commit or stash, then pull)"
    return 0
  fi
  if git -C "$dir" merge -q --ff-only '@{u}' >/dev/null 2>&1; then
    echo "PULLED        $name ($behind commit(s))"
  else
    echo "DIVERGED      $name (local and remote both moved — merge or rebase by hand)"
  fi
}

process_one() {
  local dir="$1" name explicit="$2" ahead
  name="$(basename "$dir")"

  [ "$name" = "$TEMPLATE_NAME" ] && return 0
  [[ "$name" == *.worktrees ]] && { echo "SKIP          $name (git worktree folder)"; return 0; }
  [ -d "$dir" ] || { echo "SKIP          $name (no such directory)"; return 0; }

  if [ ! -e "$dir/.git" ]; then
    echo "SKIP          $name (not a git repo — use aicf init style setup if this should become one)"
    return 0
  fi

  # Bootstrapped = owns a real (non-symlink) AGENTS.md master.
  local was_bootstrapped=true
  { [ -f "$dir/AGENTS.md" ] && [ ! -L "$dir/AGENTS.md" ]; } || was_bootstrapped=false
  if [ "$was_bootstrapped" = false ] && [ "$explicit" = false ]; then
    echo "SKIP          $name (not bootstrapped — run aicf update $name or /bootstrap-ai to opt in)"
    return 0
  fi

  PROCESSED+=("$dir")

  if [ "$DRY_RUN" = true ]; then
    echo "PLAN          $name:"
    sync_ai_templates "$dir" --dry-run
    [ "$was_bootstrapped" = true ] && refresh_agents_md "$dir" --dry-run
    ai_context_sync "$dir" --dry-run
    return 0
  fi

  # Private AI docs (--private-docs): pull the other machines' edits first, push ours last.
  # Each project gets its own network budget (AI_SYNC_NET_BUDGET): one offline remote must
  # not starve the next project.
  net_budget_reset
  ai_context_sync "$dir"
  sync_ai_templates "$dir" --commit
  if [ ${#SYNC_CHANGED[@]} -eq 0 ]; then
    echo "OK            $name (already up to date)"
  elif [ "$SYNC_COMMITTED" = true ] && [ "$SYNC_BOOTSTRAPPED" = true ]; then
    echo "BOOTSTRAPPED  $name"
  elif [ "$SYNC_COMMITTED" = true ]; then
    echo "UPDATED       $name"
  else
    echo "UPDATED       $name (left uncommitted — see message above)"
  fi
  # A fresh bootstrap's AGENTS.md is the current template already (and still unfilled).
  # Quiet: one line when it changed; the preview lists customized (KEPT) sections.
  if [ "$was_bootstrapped" = true ]; then
    SYNC_QUIET=true
    refresh_agents_md "$dir" --commit
    SYNC_QUIET=false
  fi
  ai_context_sync "$dir" --no-fetch
  if [ "$PUSH" = true ]; then
    ahead="$(ahead_count "$dir")"
    case "$ahead" in
      ""|0|no-remote|"?") ;;
      *) _push_changes "$dir"; [ "$SYNC_PUSHED" = true ] && echo "PUSHED        $name ($ahead commit(s))" ;;
    esac
  fi
  return 0
}

# --check: the conformance table, one row per git repo of this root. No writes, no network.
# --migrate: preview (or --yes, apply) the switch for each repo that misses the plan. Never
# pushes a code repo, even with --push: the hidden-repo push inside a switch is the engine's.
conform_table() {
  local dir name actual expected
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    name="$(basename "$dir")"
    actual="$(_project_mode "$dir")"
    if _conforms "$dir"; then
      printf 'OK            %s  %s\n' "$name" "$actual"
    else
      expected="$(_expected_mode "$dir")"
      [ "$actual" != "$expected" ] || actual="$actual (AI files still tracked)"
      printf 'CHECK         %s  %s -> %s\n' "$name" "$actual" "$expected"
    fi
  done < <(_conform_repos "$PARENT_DIR" | LC_ALL=C sort)
}

migrate_one() {
  local dir="$1" name expected flag
  name="$(basename "$dir")"
  if [ ! -e "$dir/.git" ]; then
    echo "SKIP          $name (not a git repo)"
    return 0
  fi
  _conforms "$dir" && return 0
  expected="$(_expected_mode "$dir")"
  [ -n "$expected" ] || return 0
  if [ "$expected" = tracked ]; then
    echo "SKIP          $name (registry says tracked — not switched)"
    return 0
  fi
  if [ "$expected" = shared ]; then flag=--shared; else flag=--private-layer; fi
  if [ "$CONFIRM" = true ]; then
    echo "MIGRATE       $name $flag"
    # Its own network budget: the switch's hidden-repo round trip must not inherit what the
    # previous projects used up.
    net_budget_reset
    sync_ai_templates "$dir" "$flag" --commit
  else
    echo "PLAN          migrate $name $flag --commit"
  fi
}

if [ "$CHECK" = true ]; then
  conform_table
  exit 0
fi
if [ "$MIGRATE" = true ]; then
  if [ -n "$ONLY" ]; then
    migrate_one "$ONLY_DIR"
  else
    while IFS= read -r dir; do
      [ -n "$dir" ] || continue
      migrate_one "$dir"
    done < <(_conform_repos "$PARENT_DIR" | LC_ALL=C sort)
  fi
  exit 0
fi

if [ "$CLONE" = true ]; then clone_missing; fi

if [ "$PULL" = true ]; then
  # The code root's .ai-root (its project registry), once for the whole run — not per project:
  # process_one below calls the engine's functions, never its --pull.
  [ "$DRY_RUN" = true ] || ai_root_pull "$PARENT_DIR"
  if [ -n "$ONLY" ]; then
    pull_one "$ONLY_DIR"
  else
    for dir in "$PARENT_DIR"/*/; do pull_one "${dir%/}"; done
  fi
fi

if [ -n "$ONLY" ]; then
  process_one "$ONLY_DIR" true
else
  for dir in "$PARENT_DIR"/*/; do
    process_one "${dir%/}" false
  done
fi

# Unpushed work — this template repo included. Nothing here pushes unless asked, so a machine
# that only ever runs the session-start sync accumulates local commits silently.
report_unpushed() {
  local dir name ahead lines=()
  for dir in "$TEMPLATE_DIR" ${PROCESSED[@]+"${PROCESSED[@]}"}; do
    name="$(basename "$dir")"
    ahead="$(ahead_count "$dir")"
    case "$ahead" in
      ""|0) ;;
      no-remote) lines+=("  $name: no remote (local only)") ;;
      *)        lines+=("  $name: $ahead commit(s) not on origin") ;;
    esac
  done
  [ ${#lines[@]} -gt 0 ] || return 0
  echo
  echo "Not on their remote:"
  printf '%s\n' "${lines[@]}"
  [ "$PUSH" = true ] || echo "  (re-run with --push, or push them yourself)"
}
report_unpushed
