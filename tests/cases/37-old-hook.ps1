# Dot-sourced by tests/run-tests.ps1 after case 34 ($F30, With-Env): a project bootstrapped long ago
# keeps the SessionStart hook it was given. Twin: 37-old-hook.sh.
Write-Host "--- 37. an old project's SessionStart hook (fa65ed9) still finds and runs the current engine"
# The hook command of .claude/settings.json.template at fa65ed9, verbatim: a literal, never read from git.
$oldHook37 = @'
P="${CLAUDE_PROJECT_DIR:-.}"; for T in "${AI_TEMPLATE_DIR:-}" "$P/../AICodeFactory" "$P/../../Code/AICodeFactory" "$HOME/Code/AICodeFactory" "$(cat "$HOME/.ai-template-dir" 2>/dev/null)" "$P"/../*/; do [ -f "$T/sync-ai-templates.sh" ] && [ -f "$T/templates-manifest.txt" ] && exec bash "$T/sync-ai-templates.sh" "$P" --quiet --commit --pull --agents --skills; done; echo "ai-sync: AICodeFactory not found - shared AI files not refreshed. Run its install-global once on this machine, or set AI_TEMPLATE_DIR."
'@.Trim()
# Claude Code runs a hook with sh (Git Bash's on Windows); no sh here, nothing to test.
$sh37 = Get-Command sh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $sh37 -or -not (Get-Command bash -CommandType Application -ErrorAction SilentlyContinue)) {
  Write-Host "    SKIP: no sh/bash on PATH (Claude Code runs hooks through Git Bash on Windows)"
} else {
  $R37 = Join-Path $S 'r37'; $P37 = Join-Path $R37 'Code/old37'; $H37 = Join-Path $R37 'home'
  New-Item -ItemType Directory -Force -Path $P37, $H37 | Out-Null
  # The current layout in a code root beside the project (found as $P/../AICodeFactory), no origin.
  git clone -q $F30 "$R37/Code/AICodeFactory" 2>$null
  if ($LASTEXITCODE -ne 0) { Fail "setup: clone the engine" }
  git -C "$R37/Code/AICodeFactory" remote remove origin
  git -C $P37 init -q; [IO.File]::WriteAllText("$P37/app.txt", "x`n"); git -C $P37 add -A; git -C $P37 commit -qm init | Out-Null
  $out = With-Env @{ HOME = $H37; USERPROFILE = $H37; CLAUDE_PROJECT_DIR = $P37; AI_TEMPLATE_DIR = $null; AI_SKILLS_MODE = 'copy' } {
    Push-Location ([IO.Path]::GetTempPath())
    try { Out-Text (& $sh37.Source -c $oldHook37 2>&1 | ForEach-Object { "$_" }); $script:rc37 = $LASTEXITCODE } finally { Pop-Location }
  }
  if ($rc37 -ne 0 -or $out -match 'not found') { Fail "the old hook must find the factory and run (rc=$rc37): $out" }
  foreach ($f in 'CLAUDE.md', '.claude/settings.json', '.github/copilot-instructions.md', 'AGENTS.md', '.github/PROJECT_STATE.md') {
    git -C $P37 ls-files --error-unmatch $f 2>$null | Out-Null
    if (-not (Test-Path -LiteralPath (Join-Path $P37 $f)) -or $LASTEXITCODE -ne 0) { Fail "the old hook must write and commit ${f}: $out" }
  }
  if ((Get-FileHash "$P37/.claude/settings.json").Hash -ne (Get-FileHash "$R37/Code/AICodeFactory/templates/.claude/settings.json.template").Hash) {
    Fail "the old hook must install the current settings template (the new hook)"
  }
  if (git -C $P37 status --porcelain) { Fail "the old hook leaves a clean tree: $(git -C $P37 status --porcelain)" }
}
