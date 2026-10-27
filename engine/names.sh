# shellcheck shell=bash
# Project and code-root name spelling: the registry's and the root repo's, so every clone of a
# project on every machine (any folder case) shares one hidden branch. Sourced by
# sync-ai-templates.sh; kept here so the engine script stays under the code-health line record.

# _registry_name <projects dir> <folder name> — the registry entry's own spelling of the folder
# name: the exact entry, else the one differing only by case (a d3skhand clone of D3SKHAND), else
# the folder name. The hidden repo's branch uses it, so every clone shares one branch.
_registry_name() {
  local f n lower ci=""
  lower="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
  for f in "$1"/*; do
    [ -f "$f" ] || continue
    n="${f##*/}"
    if [ "$n" = "$2" ]; then printf '%s\n' "$n"; return 0; fi
    [ -n "$ci" ] || [ "$(printf '%s' "$n" | tr '[:upper:]' '[:lower:]')" != "$lower" ] || ci="$n"
  done
  printf '%s\n' "${ci:-$2}"
}

# _root_spelling <code root> — the root folder's name as the root repo's branches spell it: the
# exact <name>/… branch, else one differing only by case (a Linux CODE checkout of a Code root),
# else the folder name. Read from .ai-root's remote-tracking refs (local, no network), so every
# machine's clone of a project shares one hidden branch.
_root_spelling() {
  local base lower seg ci="" refs
  base="$(basename "$1")"
  if [ -e "$1/.ai-root/.git" ]; then
    lower="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
    refs="$(git -C "$1/.ai-root" for-each-ref --format='%(refname)' refs/remotes/origin/ 2>/dev/null)" || refs=""
    while IFS= read -r seg; do
      seg="${seg#refs/remotes/origin/}"
      case "$seg" in */*) seg="${seg%%/*}" ;; *) continue ;; esac
      if [ "$seg" = "$base" ]; then printf '%s\n' "$seg"; return 0; fi
      [ -n "$ci" ] || [ "$(printf '%s' "$seg" | tr '[:upper:]' '[:lower:]')" != "$lower" ] || ci="$seg"
    done <<EOF
$refs
EOF
  fi
  printf '%s\n' "${ci:-$base}"
}
