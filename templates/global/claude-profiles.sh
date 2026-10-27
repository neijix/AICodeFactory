# Claude Code profiles (AICodeFactory install-global; edit templates/global/claude-profiles.sh there):
# `claude` started inside a code root listed in ~/.claude-profiles runs with that root's
# CLAUDE_CONFIG_DIR (its own login, settings, memory and history). An explicit CLAUDE_CONFIG_DIR wins.
function claude {
  local _acp_cfg="" _acp_root _acp_dir _acp_here
  if [ -z "${CLAUDE_CONFIG_DIR:-}" ] && [ -r "$HOME/.claude-profiles" ]; then
    _acp_here="$(pwd -P)/"
    while IFS=$'\t' read -r _acp_root _acp_dir; do
      _acp_dir="${_acp_dir%$'\r'}"
      [ -n "$_acp_root" ] && [ -n "$_acp_dir" ] || continue
      case "$_acp_here" in "$_acp_root"/*) _acp_cfg="$_acp_dir"; break ;; esac
    done < "$HOME/.claude-profiles"
  fi
  if [ -n "$_acp_cfg" ]; then CLAUDE_CONFIG_DIR="$_acp_cfg" command claude "$@"; else command claude "$@"; fi
}
