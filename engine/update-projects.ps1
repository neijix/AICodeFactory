# Refresh the AI-instruction files across sibling projects of this template repo — and, on
# request, first bring the code root itself up to date with GitHub.
#
# Normally unnecessary: every project re-syncs itself at session start (Claude Code
# SessionStart hook / AGENTS.md session-start step). Use this for a one-shot bulk refresh —
# e.g. right after a template change, on a new machine, or to migrate old symlink layouts — or
# to bootstrap a project that has no AI files yet.
#
# Usage:
#   aicf update <project-name>           # refresh (or first-time bootstrap) one project
#   aicf update <path>                   # the same for a project of another code root
#   aicf update                          # preview every bootstrapped sibling (dry-run)
#   aicf update -Yes                     # apply to every bootstrapped sibling
#   aicf update -DryRun <name>           # explicit preview, no writes
#   aicf update -Yes -Push               # also push each sync commit (needs an upstream)
#   aicf update -Yes -Clone -Pull -Push  # the whole code root, GitHub included
#   aicf update -Check                   # table: each repo's mode against the plan
#   aicf update -Migrate                 # preview the switches (no writes)
#   aicf update -Migrate -Yes            # apply them; never pushes a code repo (-Push ignored)
#     -Clone    clone every GitHub repo of yours (gh repo list) that has no local folder yet:
#               not archived, not empty, not *-private-archive. A local folder matches by name
#               (case-insensitive) or by its origin's repo name. Needs an authenticated gh.
#     -Pull     first fast-forward this template repo (re-running itself when it moved), then
#               every git sibling that tracks a remote. A dirty tree or a branch that diverged
#               from its remote is reported and left alone — never merged, never stashed.
#               A preview only fetches and says how far behind each one is. The code root's
#               .ai-root (the project registry) is fast-forwarded once per run, not previewed.
#
# Each processed project also gets its generic AGENTS.md sections refreshed
# (refresh-agents-sections.py: never a customized section, never a shared project).
# Every run ends with a report of the repos holding commits that are not on their remote.
#
# Bulk runs only touch projects that already own an AGENTS.md; un-bootstrapped repos are
# listed and left alone (bootstrap those explicitly by name, or with /bootstrap-ai).
# Commits are paths-only, so a project with work in progress is refreshed without that work
# being swept into the sync commit.

param(
  [string]$Name,
  [switch]$DryRun,
  [switch]$Yes,
  [switch]$Push,
  [switch]$Clone,
  [switch]$Pull,
  [switch]$Check,
  [switch]$Migrate,
  [switch]$TemplatePulled   # internal: set by the re-run after the template moved
)

# Windows PowerShell 5.1 (all a fresh Windows has) cannot run this script: hand over to pwsh.
if ($PSVersionTable.PSVersion.Major -lt 7) {
  $fwd = @(foreach ($k in $PSBoundParameters.Keys) { $v = $PSBoundParameters[$k]; if ($k -eq 'Rest') { $v } elseif ($v -is [switch]) { if ($v) { "-$k" } } else { "-$k"; $v } })
  if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) { Write-Host "Error: this script needs PowerShell 7 (this is Windows PowerShell $($PSVersionTable.PSVersion)). Install it with ``winget install --id Microsoft.PowerShell -e``, open a new terminal and run it again."; exit 1 }
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @fwd; exit $LASTEXITCODE
}

if ($Name -in @('-h', '--help', '-Help') -or @($args | Where-Object { $_ -in @('-h', '--help') }).Count) {
  foreach ($line in @(Get-Content -LiteralPath $PSCommandPath)) {
    if ($line -notmatch '^#') { break }
    $line -replace '^# ?', ''
  }
  exit 0
}

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $PSScriptRoot   # the template repo (this file is in engine\)
$ParentDir = Split-Path -Parent $ScriptDir
$TemplateName = Split-Path -Leaf $ScriptDir

. (Join-Path $ScriptDir "sync-ai-templates.ps1")

$Processed = [System.Collections.ArrayList]::new()
# A name is a sibling; a path (it holds a slash) is any project, another code root's included.
$OnlyDir = if (-not $Name) { '' } elseif ($Name -match '[\\/]') { $Name.TrimEnd('\', '/') } else { Join-Path $ParentDir $Name }

if (-not $Name -and -not $DryRun -and -not $Yes -and -not $Check -and -not $Migrate) {
  Write-Host "No project named - previewing changes for ALL bootstrapped sibling projects."
  Write-Host "Pass -Yes to apply to all of them, or name one project to update it directly."
  Write-Host ""
  $DryRun = $true
}

# The template first: everything below should run with the latest engine and templates.
if ($Pull -and -not $DryRun -and -not $TemplatePulled) {
  Update-TemplateRepo
  if ($script:PullUpdated) {
    Write-Host "PULLED        $TemplateName - re-running with the new version"
    # A child process, not `& $PSCommandPath`: in-process, a normal end would hand back the last
    # git command's exit code instead of the script's own.
    $again = @('-Pull', '-TemplatePulled')
    if ($Yes) { $again += '-Yes' }
    if ($Push) { $again += '-Push' }
    if ($Clone) { $again += '-Clone' }
    if ($Check) { $again += '-Check' }
    if ($Migrate) { $again += '-Migrate' }
    if ($Name) { $again += '-Name', $Name }
    & (Get-Process -Id $PID).Path -NoProfile -File $PSCommandPath @again
    exit $LASTEXITCODE
  }
}

# -Clone: GitHub repos of the authenticated user that have no local folder yet.
function Copy-MissingRepos {
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Write-Host "SKIP          -Clone (gh not installed)"; return }
  $listing = @()
  try {
    $listing = @(& gh repo list --limit 1000 --json nameWithOwner,isArchived,isEmpty `
        --jq '.[] | select(.isArchived | not) | select(.isEmpty | not) | .nameWithOwner' 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'gh failed' }
  } catch { Write-Host "SKIP          -Clone (gh repo list failed - run gh auth login)"; return }
  # Local names, lowercased: folder names and the repo name each origin points at. Dot-folders
  # are left out, except .ai-root: its origin (the root's config repo) is never a project to clone.
  $known = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $dirs = @(Get-ChildItem -LiteralPath $ParentDir -Directory -Force |
    Where-Object { -not $_.Name.StartsWith('.') -or $_.Name -eq '.ai-root' })
  foreach ($d in $dirs) {
    [void]$known.Add($d.Name)
    $url = (Invoke-Git @('-C', $d.FullName, 'remote', 'get-url', 'origin')) | Select-Object -First 1
    if ($script:GitExit -ne 0 -or -not $url) { continue }
    $slug = ($url.TrimEnd('/') -replace '\.git$', '') -split '[/\\:]' | Select-Object -Last 1
    if ($slug) { [void]$known.Add($slug) }
  }
  foreach ($full in $listing) {
    $full = "$full".Trim()
    if (-not $full) { continue }
    $repo = ($full -split '/')[-1]
    if ($repo -like '*-private-archive') { continue }
    if ($known.Contains($repo)) { continue }
    if ($DryRun) {
      Write-Host "PLAN          clone $full -> $repo"
    } else {
      & gh repo clone $full (Join-Path $ParentDir $repo) -- -q 2>$null | Out-Null
      if ($LASTEXITCODE -eq 0) { Write-Host "CLONED        $repo" }
      else { Write-Host "CLONE-FAILED  $repo (gh repo clone $full)" }
    }
    [void]$known.Add($repo)
  }
}

# -Pull: fast-forward one sibling. Never merges, never stashes.
function Update-Sibling([string]$Dir) {
  $projName = Split-Path -Leaf $Dir
  if ($projName -eq $TemplateName -or -not (Test-Path (Join-Path $Dir '.git'))) { return }
  Invoke-Git @('-C', $Dir, 'rev-parse', '--abbrev-ref', '@{u}') | Out-Null
  if ($script:GitExit -ne 0) { Write-Host "PULL-SKIP     $projName (no upstream branch)"; return }
  $prompt = $env:GIT_TERMINAL_PROMPT
  $env:GIT_TERMINAL_PROMPT = '0'
  try { Invoke-Git @('-C', $Dir, 'fetch', '-q') | Out-Null } finally { $env:GIT_TERMINAL_PROMPT = $prompt }
  if ($script:GitExit -ne 0) { Write-Host "PULL-SKIP     $projName (fetch failed - offline or auth)"; return }
  $behind = (Invoke-Git @('-C', $Dir, 'rev-list', '--count', 'HEAD..@{u}')) | Select-Object -First 1
  if ($script:GitExit -ne 0 -or -not $behind -or $behind -eq '0') { return }
  if ($DryRun) { Write-Host "PLAN          pull $projName ($behind commit(s) behind)"; return }
  $dirty = @(Invoke-Git @('-C', $Dir, 'status', '--porcelain') | Where-Object { $_ })
  if ($dirty.Count -gt 0) {
    Write-Host "PULL-SKIP     $projName ($behind behind, uncommitted changes - commit or stash, then pull)"
    return
  }
  Invoke-Git @('-C', $Dir, 'merge', '-q', '--ff-only', '@{u}') | Out-Null
  if ($script:GitExit -eq 0) { Write-Host "PULLED        $projName ($behind commit(s))" }
  else { Write-Host "DIVERGED      $projName (local and remote both moved - merge or rebase by hand)" }
}

function Sync-Project([string]$Dir, [bool]$Explicit) {
  $projName = Split-Path -Leaf $Dir
  if ($projName -eq $TemplateName) { return }
  if ($projName -like "*.worktrees") { Write-Host "SKIP          $projName (git worktree folder)"; return }
  if (-not (Test-Path $Dir -PathType Container)) { Write-Host "SKIP          $projName (no such directory)"; return }

  if (-not (Test-Path (Join-Path $Dir ".git"))) {
    Write-Host "SKIP          $projName (not a git repo - use aicf init style setup if this should become one)"
    return
  }

  # Bootstrapped = owns a real (non-symlink) AGENTS.md master.
  $agentsItem = Get-Item (Join-Path $Dir "AGENTS.md") -Force -ErrorAction SilentlyContinue
  $wasBootstrapped = ($null -ne $agentsItem) -and ($agentsItem.LinkType -ne 'SymbolicLink')
  if (-not $wasBootstrapped -and -not $Explicit) {
    Write-Host "SKIP          $projName (not bootstrapped - run aicf update $projName or /bootstrap-ai to opt in)"
    return
  }

  [void]$Processed.Add($Dir)

  if ($DryRun) {
    Write-Host "PLAN          ${projName}:"
    Sync-AiTemplates -Target $Dir -DryRun
    if ($wasBootstrapped) { Update-AgentsMd -Target $Dir -DryRun }
    Sync-AiContext -Target $Dir -DryRun
    return
  }

  # Private AI docs (-PrivateDocs): pull the other machines' edits first, push ours last.
  # Each project gets its own network budget (AI_SYNC_NET_BUDGET): one offline remote must
  # not starve the next project.
  Reset-NetBudget
  Sync-AiContext -Target $Dir
  Sync-AiTemplates -Target $Dir -Commit
  if ($script:SyncChanged.Count -eq 0) {
    Write-Host "OK            $projName (already up to date)"
  } elseif ($script:SyncCommitted -and $script:SyncBootstrapped) {
    Write-Host "BOOTSTRAPPED  $projName"
  } elseif ($script:SyncCommitted) {
    Write-Host "UPDATED       $projName"
  } else {
    Write-Host "UPDATED       $projName (left uncommitted - see message above)"
  }
  # A fresh bootstrap's AGENTS.md is the current template already (and still unfilled).
  # Quiet: one line when it changed; the preview lists customized (KEPT) sections.
  if ($wasBootstrapped) {
    $script:SyncQuiet = $true
    try { Update-AgentsMd -Target $Dir -Commit } finally { $script:SyncQuiet = $false }
  }
  Sync-AiContext -Target $Dir -NoFetch
  if ($Push) {
    $ahead = Get-AheadCount $Dir
    if ($ahead -match '^[1-9][0-9]*$') {
      Invoke-SyncPush $Dir
      if ($script:SyncPushed) { Write-Host "PUSHED        $projName ($ahead commit(s))" }
    }
  }
}

if ($Clone) { Copy-MissingRepos }

# Siblings are the folders a bash glob sees: no dot-folder (.ai-root is the root's registry).
function Get-Siblings { Get-ChildItem -Path $ParentDir -Directory | Where-Object { -not $_.Name.StartsWith('.') } }

# -Check: the conformance table, one row per git repo of this root. No writes, no network.
# -Migrate: preview (or -Yes, apply) the switch for each repo that misses the plan. Never pushes
# a code repo, even with -Push: the hidden-repo push inside a switch is the engine's.
function Write-ConformTable {
  foreach ($dir in @(Get-ConformRepos $ParentDir)) {
    if (-not $dir) { continue }
    $projName = Split-Path -Leaf $dir
    $actual = Get-ProjectMode $dir
    if (Test-Conforms $dir) { Write-Host "OK            $projName  $actual" }
    else {
      $expected = Get-ExpectedMode $dir
      if ($actual -eq $expected) { $actual = "$actual (AI files still tracked)" }
      Write-Host "CHECK         $projName  $actual -> $expected"
    }
  }
}

function Invoke-Migrate([string]$Dir) {
  $projName = Split-Path -Leaf $Dir
  if (-not (Test-Path -LiteralPath (Join-Path $Dir '.git'))) {
    Write-Host "SKIP          $projName (not a git repo)"
    return
  }
  if (Test-Conforms $Dir) { return }
  $expected = Get-ExpectedMode $Dir
  if (-not $expected) { return }
  if ($expected -eq 'tracked') {
    Write-Host "SKIP          $projName (registry says tracked — not switched)"
    return
  }
  $flag = if ($expected -eq 'shared') { 'shared' } else { 'private' }
  $shown = if ($flag -eq 'shared') { '--shared' } else { '--private-layer' }
  if ($Yes) {
    Write-Host "MIGRATE       $projName $shown"
    # Its own network budget: the switch's hidden-repo round trip must not inherit what the
    # previous projects used up.
    Reset-NetBudget
    if ($flag -eq 'shared') { Sync-AiTemplates -Target $Dir -Shared -Commit }
    else { Sync-AiTemplates -Target $Dir -PrivateLayer -Commit }
  } else {
    Write-Host "PLAN          migrate $projName $shown --commit"
  }
}

if ($Check) { Write-ConformTable; exit 0 }
if ($Migrate) {
  if ($Name) { Invoke-Migrate $OnlyDir }
  else { foreach ($dir in @(Get-ConformRepos $ParentDir)) { if ($dir) { Invoke-Migrate $dir } } }
  exit 0
}

if ($Pull) {
  # The code root's .ai-root (its project registry), once for the whole run - not per project:
  # Sync-Project below calls the engine's functions, never its --pull.
  if (-not $DryRun) { Update-AiRoot $ParentDir }
  if ($Name) { Update-Sibling $OnlyDir }
  else { Get-Siblings | ForEach-Object { Update-Sibling $_.FullName } }
}

if ($Name) {
  Sync-Project $OnlyDir $true
} else {
  Get-Siblings | ForEach-Object { Sync-Project $_.FullName $false }
}

# Unpushed work - this template repo included. Nothing pushes unless asked, so a machine that
# only ever runs the session-start sync accumulates local commits silently.
$lines = @()
foreach ($dir in @($TemplateDir) + $Processed) {
  $name = Split-Path -Leaf $dir
  $ahead = Get-AheadCount $dir
  if ($ahead -eq '' -or $ahead -eq '0') { continue }
  if ($ahead -eq 'no-remote') { $lines += "  $name`: no remote (local only)" }
  else { $lines += "  $name`: $ahead commit(s) not on origin" }
}
if ($lines.Count -gt 0) {
  Write-Host ""
  Write-Host "Not on their remote:"
  $lines | ForEach-Object { Write-Host $_ }
  if (-not $Push) { Write-Host "  (re-run with -Push, or push them yourself)" }
}
