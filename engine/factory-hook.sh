# shellcheck shell=bash
# factory-hook.sh — sourced by sync-ai-templates.sh. Python does the work; a missing
# Python leaves the old behaviour (the session still starts). Never fails the caller.

# _factory_python — the interpreter, looked up once per run: each lookup spawns up to three
# processes (on Windows `python3`/`python` can be Store stubs, then uv is asked).
# Sets FACTORY_PY; 1 when there is none. Call it outside $(…) so the answer is kept.
_factory_python() {
  if [ -z "${FACTORY_PY-}" ]; then
    FACTORY_PY="$(_memory_py 2>/dev/null)" || FACTORY_PY=none
  fi
  [ "$FACTORY_PY" != none ]
}

# _factory_py <args...> — the factory-config command. Exit status is the command's.
# A script, not `python -m`: -m puts the cwd (the project) first on sys.path, and a project
# with its own engine/ package would shadow the brain's.
_factory_py() {
  _factory_python || return 1
  "$FACTORY_PY" "$TEMPLATE_DIR/engine/factory-env.py" "$@"
}

# _factory_skills_current — 0 when this install can be skipped.
# Roots are arguments: a multiline env var is only half-converted on Git Bash, so Python
# would not see ~/.claude/skills and would skip a hand-edited copy.
_factory_skills_current() {
  _factory_py skills-current ${SKILL_ROOTS[@]+"${SKILL_ROOTS[@]}"}
}

_factory_skills_begin() {
  _factory_py skills-begin >/dev/null || true
  return 0
}

_factory_skills_finish() {
  _factory_py skills-finish >/dev/null || true
  return 0
}

# _factory_skill_keep <dest> <src> — 0 when a hand-edited copy must be left as it is.
_factory_skill_keep() {
  _factory_py skill-keep "$1" "$2"
}

# _factory_skill_stamp <dest> <skill-dir> [origin-line]
# Exit 0 when the marker was written. The caller writes a one-line origin when this fails.
# Python only hashes: Git Bash hands a native program D:/x for /d/x, and line 1 must keep
# the spelling this shell compares.
_factory_skill_stamp() {
  local hash
  hash="$(_factory_py skill-hash "$2" 2>/dev/null | tr -d '\r')" || hash=""
  [ -n "$hash" ] || return 1
  printf '%s\n%s\n' "${3:-$2}" "$hash" > "$1/$SKILL_ORIGIN_FILE"
}

# _factory_apply_project <project> <true|false dry-run> — always returns 0.
_factory_apply_project() {
  local target="$1" dry="$2"
  if [ "$dry" = true ]; then
    _factory_py apply "$target" --dry-run || true
  else
    _factory_py apply "$target" || true
  fi
  return 0
}

# _factory_rebase <remote-name> <remote-ref> — put the hidden repo on top of its remote branch.
# 1 when it stopped on a conflict (said, and recorded for the next session start).
_factory_rebase() {
  if ! _aic merge-base --is-ancestor "$2" HEAD >/dev/null 2>&1 &&
     ! _aic rebase -q "$2" >/dev/null 2>&1; then
    _factory_rebase_recover "$1" "$2" || return 1
  fi
  rm -f "$AIC_GIT/sync-conflict.json"   # settled since: by this rebase or by hand
  return 0
}

# _factory_rebase_recover <remote-name> <remote-ref> — a failed rebase of the hidden repo.
# 0 when the rebase was finished. Python merges config.local JSON by key; whatever happens
# (no Python, a clash, a crash, a timeout), a rebase still open is aborted here and said once.
_factory_rebase_recover() {
  local remote="${1:-}" ref="${2:-}"
  if _factory_python; then
    if "$FACTORY_PY" "$TEMPLATE_DIR/engine/factory-env.py" merge-rebase \
      --git-dir "$AIC_GIT" --work-tree "$AIC_TREE" --ref "$ref"; then
      return 0
    fi
  fi
  if [ -d "$AIC_GIT/rebase-merge" ] || [ -d "$AIC_GIT/rebase-apply" ]; then
    _aic rebase --abort >/dev/null 2>&1 || true
  fi
  # The Stop hook drops this line: the marker makes the next session start say it again.
  [ -f "$AIC_GIT/sync-conflict.json" ] ||
    printf '{"clashes": {}, "other": [], "ref": "%s"}\n' "$ref" >"$AIC_GIT/sync-conflict.json" 2>/dev/null || true
  echo "ai-sync: private AI docs: conflict with $remote — resolve by hand: git --git-dir=$AIC_GIT --work-tree=$AIC_TREE rebase $ref"
  return 1
}

# _factory_extra_skill_srcs — append the extra overlays' skill dirs (factory.json, environments)
# that are not already sources: this repo's skills come first and win a name clash.
_factory_extra_skill_srcs() {
  local dir
  _factory_python || return 0
  while IFS= read -r dir; do
    [ -n "$dir" ] && [ -d "$dir" ] || continue
    local seen=false have
    for have in ${SKILL_SRCS[@]+"${SKILL_SRCS[@]}"}; do
      [ "$have" = "$dir" ] && seen=true
    done
    [ "$seen" = true ] || SKILL_SRCS+=("$dir")
  done <<EOF
$(_factory_py overlay-dirs 2>/dev/null || true)
EOF
  return 0
}
