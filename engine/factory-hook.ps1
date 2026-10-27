# factory-hook.ps1 — dot-sourced by sync-ai-templates.ps1. Python does the work.
# A missing Python leaves the old behaviour. Never fails the caller.

# Looked up once per run: each lookup spawns processes (Store stubs, then uv). Same order as
# _memory_py in the bash engine.
function Get-FactoryPython {
  if ($null -eq $script:FactoryPython) {
    $script:FactoryPython = "$(Find-FactoryPython)"
  }
  if ($script:FactoryPython) { return $script:FactoryPython }
  return $null
}

function Find-FactoryPython {
  foreach ($name in @('python3', 'python')) {
    if (-not (Get-Command $name -CommandType Application -ErrorAction SilentlyContinue)) { continue }
    & $name -c 'import sys' 2>$null
    if ($LASTEXITCODE -eq 0) { return $name }
  }
  if (Get-Command uv -CommandType Application -ErrorAction SilentlyContinue) {
    $found = (& uv python find 2>$null | Select-Object -First 1)
    if ($found) {
      & $found -c 'import sys' 2>$null
      if ($LASTEXITCODE -eq 0) { return "$found" }
    }
  }
  return $null
}

function Invoke-FactoryPy([string[]]$FactoryArgs, [switch]$Quiet) {
  $script:FactoryOutput = @()
  $py = Get-FactoryPython
  if (-not $py) { $script:FactoryExit = 1; return }
  # A script, not `python -m`: -m puts the cwd (the project) first on sys.path, and a project
  # with its own engine/ package would shadow the brain's.
  $script:FactoryOutput = @(& $py (Join-Path $TemplateDir 'engine/factory-env.py') @FactoryArgs)
  $script:FactoryExit = $LASTEXITCODE
  if (-not $Quiet) {
    foreach ($line in @($script:FactoryOutput)) { if ("$line" -ne '') { Write-Host $line } }
  }
}

function Invoke-FactoryApply([string]$Target, [bool]$DryRun) {
  if ($DryRun) { Invoke-FactoryPy @('apply', $Target, '--dry-run') }
  else { Invoke-FactoryPy @('apply', $Target) }
}

function Test-FactorySkillKeep([string]$Dest, [string]$Source) {
  Invoke-FactoryPy -Quiet @('skill-keep', $Dest, $Source)
  if ($script:FactoryExit -eq 0) {
    foreach ($line in @($script:FactoryOutput)) { if ("$line" -ne '') { Write-Host $line } }
    return $true
  }
  return $false
}

function Write-FactorySkillStamp([string]$Dest, [string]$Source, [string]$Origin) {
  if ($Origin) { Invoke-FactoryPy -Quiet @('skill-stamp', $Dest, $Source, $Origin) }
  else { Invoke-FactoryPy -Quiet @('skill-stamp', $Dest, $Source) }
  return ($script:FactoryExit -eq 0)
}

function Test-FactorySkillsCurrent {
  $prev = $env:AI_SKILL_ROOTS
  $env:AI_SKILL_ROOTS = (@($SkillRoots) -join "`n")
  Invoke-FactoryPy @('skills-current')
  if ($null -eq $prev) { Remove-Item Env:AI_SKILL_ROOTS -ErrorAction SilentlyContinue }
  else { $env:AI_SKILL_ROOTS = $prev }
  return ($script:FactoryExit -eq 0)
}

function Start-FactorySkillsInstall { Invoke-FactoryPy @('skills-begin') }
function Complete-FactorySkillsInstall { Invoke-FactoryPy @('skills-finish') }

function Add-FactorySkillSources {
  Invoke-FactoryPy -Quiet @('overlay-dirs')
  if ($script:FactoryExit -ne 0) { return }
  foreach ($dir in @($script:FactoryOutput)) {
    if (-not $dir -or -not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
    $have = $false
    foreach ($src in @($script:SkillSrcs)) { if ($src -eq $dir) { $have = $true } }
    if (-not $have) { $script:SkillSrcs = @($dir) + @($script:SkillSrcs) }
  }
}

# Puts the hidden repo on top of its remote branch. $false when it stopped on a conflict (said,
# and recorded for the next session start).
function Invoke-FactoryRebase([string]$Remote, [string]$RemoteRef) {
  Invoke-Aic @('merge-base', '--is-ancestor', $RemoteRef, 'HEAD') | Out-Null
  if ($script:GitExit -ne 0) {
    Invoke-Aic @('rebase', '-q', $RemoteRef) | Out-Null
    if ($script:GitExit -ne 0 -and -not (Invoke-FactoryRebaseRecover $Remote $RemoteRef)) { return $false }
  }
  # Settled since: by this rebase or by hand.
  Remove-Item -LiteralPath (Join-Path $script:AicGit 'sync-conflict.json') -Force -ErrorAction SilentlyContinue
  return $true
}

# $true when the rebase was finished. Python merges config.local JSON by key; whatever happens
# (no Python, a clash, a crash, a timeout), a rebase still open is aborted here and said once.
function Invoke-FactoryRebaseRecover([string]$Remote, [string]$RemoteRef) {
  if (Get-FactoryPython) {
    Invoke-FactoryPy @('merge-rebase', '--git-dir', $script:AicGit, '--work-tree', $script:AicTree, '--ref', $RemoteRef)
    if ($script:FactoryExit -eq 0) { return $true }
  }
  $open = (Test-Path -LiteralPath (Join-Path $script:AicGit 'rebase-merge')) -or
    (Test-Path -LiteralPath (Join-Path $script:AicGit 'rebase-apply'))
  if ($open) { Invoke-Aic @('rebase', '--abort') | Out-Null }
  # The Stop hook drops this line: the marker makes the next session start say it again.
  $marker = Join-Path $script:AicGit 'sync-conflict.json'
  if (-not (Test-Path -LiteralPath $marker)) {
    try {
      $json = '{"clashes": {}, "other": [], "ref": "' + $RemoteRef + '"}' + "`n"
      [IO.File]::WriteAllText($marker, $json, (New-Object Text.UTF8Encoding $false))
    } catch { }
  }
  Write-Host "ai-sync: private AI docs: conflict with $Remote - resolve by hand: git --git-dir=$($script:AicGit) --work-tree=$($script:AicTree) rebase $RemoteRef"
  return $false
}
