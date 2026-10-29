# shellcheck shell=bash
# Work roots: code roots whose private AI docs must never reach a personal remote (the remote
# rules of _ai_context_remote, root_remote_parse and ai_root_clone). Sourced by
# sync-ai-templates.sh; kept here so the engine script stays under the code-health line record.

# _env_json_field <environment.json> <key> — the first "<key>": "<value>" of the file (value of
# letters, digits, . _ -), or nothing (no file, no such key).
_env_json_field() {
  [ -f "$1" ] || return 0
  sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([A-Za-z0-9._-]*\)\".*/\1/p" "$1" 2>/dev/null | sed -n '1p'
}

# _work_roots — the work-roots list, one entry per line (lowercase, backslashes as /, trailing /
# dropped): $AI_WORK_ROOTS when set (':' between entries; empty or none = no work roots, and the
# file is not read), else the lines of ~/.ai-work-roots (blank lines and # comments skipped, CR
# stripped, trimmed).
_work_roots() {
  local src
  if [ "${AI_WORK_ROOTS+set}" = set ]; then
    case "$AI_WORK_ROOTS" in ''|none) return 0 ;; esac
    src="$(printf '%s\n' "$AI_WORK_ROOTS" | tr ':' '\n')"
  elif [ -f "${HOME:-/nonexistent}/.ai-work-roots" ]; then
    src="$(cat "$HOME/.ai-work-roots" 2>/dev/null)" || return 0
  else
    return 0
  fi
  printf '%s\n' "$src" | awk '{ sub(/\r$/, ""); gsub(/^[ \t]+|[ \t]+$/, "") }
    $0 != "" && substr($0, 1, 1) != "#" { gsub(/\\/, "/"); sub(/\/+$/, ""); if ($0 != "") print tolower($0) }'
}

# _work_label <path> — true when the nearest folder at or above <path> holding .ai-root/ or
# .ai-context-remote (a code root; the walk stops at $HOME and every folder above it, as in
# _ancestor_root) has .ai-root/environment.json "label": "work" (any case; a file written before
# label replaced kind: "kind": "work").
_work_label() {
  local d home_p="" f v
  d="$(cd "$1" 2>/dev/null && pwd -P)" || d="$(printf '%s' "$1" | tr '\\' '/')"
  [ -z "${HOME:-}" ] || home_p="$(cd "$HOME" 2>/dev/null && pwd -P)" || home_p=""
  while [ -n "$d" ]; do
    if [ -n "$home_p" ]; then
      case "${home_p%/}/" in "${d%/}/"*) return 1 ;; esac
    fi
    if [ -d "${d%/}/.ai-root" ] || [ -e "${d%/}/.ai-context-remote" ]; then
      f="${d%/}/.ai-root/environment.json"
      [ "$(_env_json_field "$f" kind)" != work ] || return 0
      v="$(_env_json_field "$f" label | tr '[:upper:]' '[:lower:]')"
      [ "$v" = work ]
      return
    fi
    [ "$d" != / ] || return 1
    d="${d%/*}"
    [ -n "$d" ] || d=/
  done
  return 1
}

# _is_work_path <path> — true when the path lies under a work root: an entry of _work_roots
# matches it (a name without / = any path component, case-insensitive; a path = a prefix on whole
# components, case-insensitive), or its code root's label is work (_work_label).
_is_work_path() {
  local p e
  [ -n "$1" ] || return 1
  p="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr '\\' '/')"
  p="${p%/}"
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    case "$e" in
      */*) case "$p/" in "$e"/*) return 0 ;; esac ;;
      *) case "/$p/" in */"$e"/*) return 0 ;; esac ;;
    esac
  done <<EOF
$(_work_roots)
EOF
  _work_label "$1"
}
