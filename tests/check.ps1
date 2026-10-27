# The local gate (~6 min): everything the Linux CI job runs (that job calls check.sh). Twin of
# check.sh, same steps. The bash steps need bash: on Windows, Git for Windows' bin\bash.exe.
# This repo's own dev script, not a product: in no manifest section, never synced to projects.
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

foreach ($tool in 'pwsh', 'uv') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "check.ps1: '$tool' not found on PATH - install it (PowerShell 7 / astral uv)"
    }
}
$bash = (Get-Command bash -ErrorAction SilentlyContinue).Source
if (-not $bash -and ($git = Get-Command git -ErrorAction SilentlyContinue)) {
    $candidate = Join-Path (Split-Path (Split-Path $git.Source)) 'bin\bash.exe'   # <Git>\cmd\git.exe
    if (Test-Path $candidate) { $bash = $candidate }
}
if (-not $bash) { throw "check.ps1: bash not found - install Git for Windows (it ships bin\bash.exe)" }
$py = 'python'   # Windows: python3 may be missing or the Store stub
try { & python3 -c '' 2>$null; if ($LASTEXITCODE -eq 0) { $py = 'python3' } } catch { }

function Step([string]$name, [scriptblock]$run) {
    Write-Host "`n== $name"
    & $run
    if ($LASTEXITCODE -ne 0) { throw "check.ps1: '$name' failed (exit $LASTEXITCODE)" }
}

Step 'Hook JSON parses (a broken file breaks Claude Code startup everywhere)' {
    pwsh -NoProfile -Command 'Get-Content -Raw templates/.claude/settings.json.template | ConvertFrom-Json | Out-Null'
}
Step 'Docs: links, env vars, CLI reference' { & $py tests/check-docs.py }
Step 'Bash suite (/bin/bash, the shell the hook runs)' { & $bash tests/run-tests.sh }
Step 'PowerShell suite' { pwsh -NoProfile -File tests/run-tests.ps1 }
Step 'ui-doctor (static rules; live half when Chrome is present)' { & $py tests/test-ui-doctor.py }
Step 'Factory config' { uv run -q python -m unittest tests.test_factory_env }
Step 'Projects page' { uv run -q python -m unittest tests.test_projects_page }
Step 'code-health' { uv run -q skills/code-health/scripts/code_health.py check }
Step 'Self-sync dry run' { & $bash ./sync-ai-templates.sh . --dry-run }

Write-Host "`ncheck.ps1: all green"
