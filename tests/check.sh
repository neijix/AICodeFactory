#!/usr/bin/env bash
# The local gate (~6 min): everything the Linux CI job runs — that job calls this script. Twin:
# check.ps1. The pre-push hook runs it (.githooks/pre-push; enable: git config core.hooksPath .githooks).
# This repo's own dev script, not a product: in no manifest section, never synced to projects.
set -euo pipefail
cd "$(dirname "$0")/.."

for tool in pwsh uv; do
  command -v "$tool" >/dev/null 2>&1 || { echo "check.sh: '$tool' not found on PATH — install it (PowerShell 7 / astral uv)" >&2; exit 1; }
done
PY=python3; "$PY" -c '' 2>/dev/null || PY=python   # Windows: python3 may be the Store stub
step() { printf '\n== %s\n' "$*"; }

step "Hook JSON parses (a broken file breaks Claude Code startup everywhere)"
pwsh -NoProfile -Command 'Get-Content -Raw templates/.claude/settings.json.template | ConvertFrom-Json | Out-Null'

step "Docs: links, env vars, CLI reference"
"$PY" tests/check-docs.py

step "Bash suite (/bin/bash, the shell the hook runs)"
tests/run-tests.sh

step "PowerShell suite"
pwsh -NoProfile -File tests/run-tests.ps1

step "ui-doctor (static rules; live half when Chrome is present)"
"$PY" tests/test-ui-doctor.py

step "Factory config"
uv run -q python -m unittest tests.test_factory_env

step "Projects page"
uv run -q python -m unittest tests.test_projects_page

step "Settings page"
uv run -q python -m unittest tests.test_config_ui

step "code-health"
uv run -q skills/code-health/scripts/code_health.py check

step "Self-sync dry run"
./sync-ai-templates.sh . --dry-run

printf '\ncheck.sh: all green\n'
