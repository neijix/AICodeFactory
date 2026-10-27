# Bootstrap a brand new project as a sibling of this template repo.
#
# Usage: bin\aicf.ps1 init <project-name> [-Tracked]   (or engine\new-project.ps1)
#
# Creates <this repo's parent>\<project-name> — i.e. the same code root this repo sits in, so it
# works whether that is ~/Code or F:\Code. Git-inits it, copies every AI-tool pointer file and the
# per-project living docs from this repo (no symlinks — the project refreshes itself from the
# template at every session start), commits, then — if the `claude` CLI is available — runs
# the AI bootstrap to finish the smart fill.
#
# PRIVATE by default (sync-ai-templates.ps1 -PrivateLayer, see its header): the owner's AI layer
# stays out of the code repo — the exclude block in .git\info\exclude, the hidden repo
# .git\ai-context (pushed to the root's remote, if any), mode=private in the code root's registry
# when it has .ai-root\. The first commit holds no layer path (.gitignore and .env.example only);
# a staged one stops the script before it commits. When the switch waits for an unreachable
# remote, nothing is committed: one error with the command to re-run.
#   -Tracked    the code repo commits every AI file instead (the former default). --tracked works too.

param([string]$Name, [switch]$Tracked, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)

# Windows PowerShell 5.1 (all a fresh Windows has) cannot run this script: hand over to pwsh.
if ($PSVersionTable.PSVersion.Major -lt 7) {
  $fwd = @(foreach ($k in $PSBoundParameters.Keys) { $v = $PSBoundParameters[$k]; if ($k -eq 'Rest') { $v } elseif ($v -is [switch]) { if ($v) { "-$k" } } else { "-$k"; $v } })
  if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) { Write-Host "Error: this script needs PowerShell 7 (this is Windows PowerShell $($PSVersionTable.PSVersion)). Install it with ``winget install --id Microsoft.PowerShell -e``, open a new terminal and run it again."; exit 1 }
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @fwd; exit $LASTEXITCODE
}

$ErrorActionPreference = 'Stop'
$usage = 'Usage: aicf init <project-name> [-Tracked]'
# --tracked, the bash twin's spelling, lands in $Name or $Rest when the script is called with &.
$words = @()
if ($Name) { $words += $Name }
if ($Rest) { $words += $Rest }
$Name = ''
foreach ($w in $words) {
  if ($w -ceq '--tracked') { $Tracked = $true }
  elseif ($w -in @('-h', '--help')) { Write-Host $usage; exit 0 }
  elseif ($w.StartsWith('-')) { $host.UI.WriteErrorLine("Unknown option: $w ($usage)"); exit 2 }
  elseif ($Name) { $host.UI.WriteErrorLine("Error: one project name only ($usage)"); exit 2 }
  else { $Name = $w }
}
if (-not $Name) { $host.UI.WriteErrorLine($usage); exit 2 }
$ScriptDir = Split-Path -Parent $PSScriptRoot   # the template repo (this file is in engine\)
$ParentDir = Split-Path -Parent $ScriptDir
$Target = Join-Path $ParentDir $Name

if (Test-Path $Target) {
  Write-Error "$Target already exists. Use aicf update `"$Name`" to refresh it instead."
  exit 1
}

Write-Host "Creating $Target ..."
New-Item -ItemType Directory -Force -Path $Target | Out-Null
git -C $Target init -q

$gitignorePath = Join-Path $Target ".gitignore"
if (-not (Test-Path $gitignorePath)) {
  @"
.DS_Store
.env
node_modules/
__pycache__/
*.pyc
.venv/
"@ | Set-Content $gitignorePath
}

. (Join-Path $ScriptDir "sync-ai-templates.ps1")
if ($Tracked) {
  Sync-AiTemplates -Target $Target
  git -C $Target add -A
} else {
  Sync-AiTemplates -Target $Target -PrivateLayer
  if ((Get-ProjectMode $Target) -notin @('private', 'team')) {
    $eng = Join-Path $ScriptDir 'sync-ai-templates.ps1'
    $host.UI.WriteErrorLine("Error: $Target is not private yet (the switch waits for its remote — see above). Nothing committed. Re-run when online: $eng $Target --private-layer --commit")
    exit 1
  }
  # The hidden repo's first commit (and push), as the session-start sync does after a switch.
  Sync-AiContext -Target $Target -NoFetch
  git -C $Target add -A
  $leaked = @(Get-TrackedLayerPaths $Target)
  if ($leaked.Count -gt 0) {
    git -C $Target reset -q
    $host.UI.WriteErrorLine("Error: the first commit would hold private-layer paths ($($leaked -join ' ')) — nothing committed.")
    exit 1
  }
}
git -C $Target commit -q -m "docs: bootstrap project documentation"
Write-Host "Mechanical bootstrap done: AI files copied, git init, first commit."

$claude = Get-Command claude -ErrorAction SilentlyContinue
if ($claude) {
  Write-Host "claude CLI found - running AI bootstrap to fill in project-specific details ..."
  Push-Location $Target
  claude -p "/bootstrap-ai" --permission-mode acceptEdits
  $success = ($LASTEXITCODE -eq 0)
  Pop-Location
  if ($success) {
    Write-Host "AI bootstrap complete."
  } else {
    Write-Host "AI bootstrap didn't finish automatically - open '$Target' in your AI tool and run /bootstrap-ai to finish."
  }
} else {
  Write-Host "Next: open '$Target' in your AI tool (Claude Code, Copilot, ...) so it can scan the code and finish filling in the project details."
}

Write-Host "Done: $Target"
