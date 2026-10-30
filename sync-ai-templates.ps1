# sync-ai-templates.ps1 — PowerShell twin of sync-ai-templates.sh (identical behavior).
# Keeps one project's AI-instruction files in step with this template repo. NO SYMLINKS for
# project files: every file is a plain copy, so it works without Developer Mode on Windows.
#
#   pointer files  (manifest [POINTERS])     copied whenever they differ from the template
#   living docs    (manifest [LIVING_DOCS])  created once, then owned by the project
#   obsolete files (manifest [OBSOLETE])     removed (guarded entries only when unmodified)
#   git hooks      (manifest [SHARED_HOOKS]) every mode but tracked, into .git/hooks (untracked)
#
# Project modes: tracked (default — the code repo commits everything), private (--private-layer),
# shared (--shared), team (--private-layer on a repo with other authors). The mode is the first
# line of the managed block in <git-common-dir>/info/exclude ("# ai-templates: <mode>" …
# "# ai-templates: end"); without one, the legacy .gitignore markers ("# ai-templates: private AI
# docs" → private, "# ai-templates: local-only" → shared); else the code root's registry; else
# tracked.
#
# Code root: the folder holding the project (the parent of its git top level) when it holds
# .ai-root\ or .ai-context-remote. Its .ai-root\ is a git checkout of the owner's private root
# repo: projects\<name> records each project's mode ("mode=" and "origin=" lines; matched by
# folder name, else by normalized origin), written and pushed when --private-layer or --shared
# applies (lock, rebase, a commit of that file alone, never on --dry-run); it also holds
# private-terms.txt and dev-context\ (the only place the engine reads them). The hidden repo's remote and owner-emails
# come from the nearest folder above the project holding either (Root\group\proj finds Root).
#
# Standalone:
#   .\sync-ai-templates.ps1 [<project-dir>] [--dry-run] [--commit] [--quiet] [--pull] [--agents] [--skills] [--shared|--private-layer]
#   .\sync-ai-templates.ps1 [<project-dir>] --ai-context-sync [--quiet]
#   .\sync-ai-templates.ps1 <code-root> --root-sync [--quiet]
#   .\sync-ai-templates.ps1 [<project-dir>] --scan-private [--history]
#   .\sync-ai-templates.ps1 [<project-dir>] --global-hook
#   (PowerShell-style -DryRun / -Commit / -Quiet / -Pull / -Agents / -Skills / -Shared /
#   -PrivateLayer / -PrivateDocs / -AiContextSync / -RootSync / -ScanPrivate / -History / -GlobalHook are
#   accepted too)
#     --dry-run   print the plan, write nothing
#     --commit    commit only the files this run changed (paths-only commit)
#     --quiet     hook mode: print one line when something changed, nothing otherwise.
#                 A project that has a dev-context pack also prints one
#                 `ai-sync: dev-context` line (see below) — that line is not a file change.
#     --push      after --commit, push that commit when the branch has an upstream. Off by
#                 default and never enabled by the session-start hook.
#     --pull      `git pull --ff-only` of this template repo (and the overlay) FIRST, so this run
#                 uses the latest templates: only when its working tree is clean, and bounded —
#                 after $env:AI_SYNC_PULL_WAIT seconds (default 10; offline, slow network) the
#                 pull carries on in the background and this run uses what is on disk. When the
#                 pull moved the repo, the engine re-runs itself so the new engine applies too.
#                 Before that, once per run: the code root's .ai-root, fast-forwarded the same
#                 way and pushed when it is ahead (a registry commit whose push failed).
#                 Every network step of a run (these pulls, the .ai-root push, the hidden repo's
#                 ls-remote, fetch and push) shares one budget of $env:AI_SYNC_NET_BUDGET seconds
#                 of waiting (default 30), the re-run included; the local work between them
#                 does not count. After the first step that timed out, the rest are skipped.
#     --agents    also carry the template's generic AGENTS.md sections into the project
#                 (bootstrap-ai/scripts/refresh-agents-sections.py: only sections never
#                 customized, plus a missing ## Taste scaffold; shared projects and an AGENTS.md
#                 with uncommitted edits are left alone; in a private or team project the file
#                 is edited but never committed to the code repo). Needs uv or python3, else a
#                 no-op.
#     --skills    refresh the global skill folders from skills/ — copies on
#                 Windows, symlinks elsewhere (override with $env:AI_SKILLS_MODE = copy|link)
#     --shared    turn the project into a SHARED project (a repo other people clone): pointer
#                 files become local-only — gitignored under the "# ai-templates: local-only"
#                 line and untracked (they stay on disk). Needs an empty index; with --commit
#                 the switch is one commit. Later runs see that line and keep it that way.
#                 Shared projects also get the private-terms pre-commit hook (see
#                 git-hooks/pre-commit.sh.template): a commit adding one of the owner's private
#                 terms is refused. The list lives outside every repo - $env:AI_PRIVATE_TERMS_FILE,
#                 <code root>/.ai-root/private-terms.txt, ~/.private-terms.
#     --private-layer  turn the project PRIVATE: the owner's personal AI layer leaves the code
#                 repo. Layer B (living docs except .env.example, docs/state/, docs/plans/,
#                 config.local/, .claude/memory/) is versioned in a hidden repo instead; layer C
#                 (every [POINTERS] file, .claude/, CLAUDE.local.md) is rebuilt from the
#                 templates. Both are listed in the managed block of .git/info/exclude (anchored
#                 paths; config.local/ at any depth), never in .gitignore, which keeps only .env,
#                 .claude/settings.local.json and CLAUDE.local.md. The switch removes the legacy
#                 marker lines and the paths the engine listed under them from .gitignore (no
#                 other line), and untracks the B and C paths git still tracks (files stay on
#                 disk). Needs an empty index; with --commit it is one commit, "chore: move the
#                 personal AI layer out of the repo (private layer)". A later plain run keeps the
#                 block fresh and says when git still tracks a layer path. Private projects get
#                 the private-terms pre-commit hook too.
#                 TEAM instead of private when the repo's history (last 2000 commits) holds an
#                 author outside <code root>/.ai-root/owner-emails and its user.email (bots
#                 ignored; see Test-TeamRepo): its tracked files stay exactly as they are -
#                 never written, untracked or committed, .gitignore never gets a line - and the
#                 block lists only the B and C paths it does not track (plus .env when nothing
#                 ignores it yet). The switch commits only the legacy .gitignore cleanup, if any.
#                 The hidden repo (.git/ai-context, branch <root>/<project>) is committed, rebased
#                 and pushed by every later run to the owner's private remote -
#                 $env:AI_CONTEXT_REMOTE, else <code root>/.ai-context-remote, else
#                 ~/.ai-context-remote (legacy; install-global writes the root's); none = local only.
#                 Under a work root (Test-WorkPath) only the root's file counts: $env:AI_CONTEXT_REMOTE
#                 can only disable it, ~/.ai-context-remote is never read, a github.com URL is
#                 refused (one line each; local only). A fresh clone on another machine gets the
#                 docs back at its first run. The switch pushes the hidden branch first: until
#                 the remote has it, the code repo is left exactly as it was (one line; re-run).
#                 Safety rules of the hidden repo: see Sync-AiContext and Invoke-AicCommit.
#                 Memory (private and team only): .claude/settings.local.json gains
#                 autoMemoryDirectory, an absolute forward-slash path to
#                 <project>/.claude/memory. Once per machine, after the hidden repo is
#                 restored, ~/.claude/projects/<slug>/memory is imported (missing files
#                 copied, differing ones under imported-<host>/, MEMORY.md union of lines).
#                 A tracked project gets no key, nor a team repo tracking settings.local.json.
#                 See Merge-AutoMemorySettings and
#                 Import-ClaudeMemory.
#                 Conformance (no network; a -PrivateLayer / -Shared switch is already the
#                 fix): in a code root the expected mode is the registry's, else private, and
#                 team conforms; the right mode with layer files still tracked does not. A
#                 miss prints one ai-sync: line with the switch command, in -Quiet too.
#                 Syncing this template repo names this root's non-conforming projects and
#                 only counts a sibling root's. See Write-ConformLine.
#     --private-docs  alias of --private-layer (its former name).
#     --ai-context-sync  sync nothing else: only that hidden repo (the Stop hook's call).
#     --root-sync  sync nothing else: <code-root>\.ai-root alone, the --pull step on its own
#                 (bounded pull --ff-only, push when ahead, under its lock; D3SKHAND's Sync all).
#     --scan-private  sync nothing: check the project's tracked files against that list
#                 (exit 1 on a hit); --history also every commit on every ref. Runs the same
#                 POSIX sh script as the hook (sh on PATH, else Git for Windows' bin\sh.exe).
#     --global-hook  the global SessionStart hook's call (templates\global\claude-global-hook.json,
#                 merged into ~\.claude\settings.json by install-global; there is no global Stop
#                 hook). In a code root, a project whose .claude\settings.json lacks the sync hook
#                 (a fresh clone of a private project) gets the project hook's run (--quiet
#                 --commit --pull --agents --skills) when the registry knows it or it has a mode,
#                 else one conformance line. A silent no-op everywhere else; other flags are
#                 ignored. See Get-GlobalHookPlan. (The hook itself runs the bash twin.)
#
# Dev context (never in the project's repo): <code root>\.ai-root\dev-context\, read when it holds
# rules.md or settings.json. rules.md is development rules; settings.json is optional and holds
# no credentials. Scope: environment.json "label" (else the legacy "kind"), else work under a work
# root, else personal inside a code root (no scope, no pack — whatever the root holds).
# The sync writes gitignored CLAUDE.local.md when that file is absent or already ours, and a
# --quiet run prints one line telling the agent to read it. No pack: print nothing and remove a
# file we wrote. An unreadable pack file
# (a cloud placeholder) is one line and never fails the run.
#
# Overlay (optional): a second repo — typically private — layered on top of this one so the
# public template stays generic while personal skills, rules and configs still reach every
# machine. Found via $env:AI_TEMPLATE_OVERLAY_DIR, then ~\.ai-template-overlay-dir, then the
# sibling folder <this-repo>-private. Inside it, the same layout applies:
#   templates\<x>.template    replaces the base file of the same name (any manifest entry)
#   templates\<x>.template.append  appended to the rendered file (pointers and living docs alike)
#   overlay-manifest.txt      optional, same format: adds entries, or replaces the base entry
#                             that targets the same destination
#   skills\*                  installed with --skills; wins over a base skill of the same name
# The old overlay layout (<x>.template at its root, vscode-global\) is still read, second.
#
# Dot-source from engine\new-project.ps1 / update-projects.ps1 / install-global.ps1, then call
# Sync-AiTemplates, Sync-GlobalSkills, Update-TemplateRepo, Update-AiRoot, Update-AgentsMd. (No param() block on purpose:
# dot-sourcing one would clobber the caller's own -DryRun / -Yes parameters.)

$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1 (all a fresh Windows has) cannot run this script: hand a standalone run
# over to pwsh (a dot-sourcing caller has already done so).
if ($PSVersionTable.PSVersion.Major -lt 7 -and $MyInvocation.InvocationName -ne '.') {
  if (Get-Command pwsh -ErrorAction SilentlyContinue) {
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @args
    exit $LASTEXITCODE
  }
  Write-Host "Error: this script needs PowerShell 7 (this is Windows PowerShell $($PSVersionTable.PSVersion)). Install it with ``winget install --id Microsoft.PowerShell -e``, open a new terminal and run it again."
  exit 1
}

$TemplateDir = $PSScriptRoot
$TemplateName = Split-Path -Leaf $TemplateDir
$ManifestFile = Join-Path $TemplateDir 'templates-manifest.txt'
$SkillsSrc = Join-Path $TemplateDir 'skills'

# Overlay repo (see header). Empty when none is configured or found. A configured path that
# does not exist is reported once and ignored - a missing overlay must never break a session.
$OverlayDir = ''
$OverlayName = ''
$OverlayMarker = Join-Path $HOME '.ai-template-overlay-dir'
$ovCandidate = ''
if ($null -ne $env:AI_TEMPLATE_OVERLAY_DIR) {
  # Set (even to '' or 'none') means explicit: no marker, no sibling lookup.
  if ($env:AI_TEMPLATE_OVERLAY_DIR -and $env:AI_TEMPLATE_OVERLAY_DIR -ne 'none') { $ovCandidate = $env:AI_TEMPLATE_OVERLAY_DIR }
} elseif ((Test-Path -LiteralPath $OverlayMarker -PathType Leaf) -and ((Get-Item -LiteralPath $OverlayMarker).Length -gt 0)) {
  $ovFirst = Get-Content -LiteralPath $OverlayMarker -TotalCount 1
  if ($null -ne $ovFirst) { $ovCandidate = ([string]$ovFirst).Trim() }
} elseif (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $TemplateDir) "$TemplateName-private") -PathType Container) {
  $ovCandidate = Join-Path (Split-Path -Parent $TemplateDir) "$TemplateName-private"
}
if ($ovCandidate) {
  # A dir that stats but cannot be entered must not kill the engine either.
  $ovOk = $false
  try {
    if (Test-Path -LiteralPath $ovCandidate -PathType Container) {
      $OverlayDir = (Resolve-Path -LiteralPath $ovCandidate).Path
      Get-ChildItem -LiteralPath $OverlayDir -Force -ErrorAction Stop | Out-Null
      $OverlayName = Split-Path -Leaf $OverlayDir
      $ovOk = $true
    }
  } catch { $ovOk = $false }
  if (-not $ovOk) {
    $OverlayDir = ''; $OverlayName = ''
    Write-Host "ai-sync: overlay $ovCandidate not found - using $TemplateName alone"
  }
}
# Its layout, templates (Get-TemplatePath, Get-RenderedBytes) and per-target choice: engine\overlay.ps1.
. (Join-Path $PSScriptRoot 'engine\overlay.ps1')
# Label used in the one-line --quiet summary.
$SourceLabel = $TemplateName
if ($OverlayName) { $SourceLabel = "$TemplateName+$OverlayName" }
$SkillRoots = @('.agents/skills', '.claude/skills', '.copilot/skills', '.cursor/skills', '.gemini/config/skills') |
  ForEach-Object { Join-Path $HOME $_ }
# Add <config-dir>/skills of every Claude Code profile install-global recorded in ~/.claude-profiles
# ("<root><TAB><config-dir>" per line) whose dir exists, once each.
function Add-ProfileSkillRoots {
  $rec = Join-Path $HOME '.claude-profiles'
  if (-not (Test-Path -LiteralPath $rec -PathType Leaf)) { return }
  foreach ($line in Get-Content -LiteralPath $rec) {
    $root, $dir = $line -split "`t", 2
    if (-not $dir -or -not (Test-Path -LiteralPath $dir.Trim() -PathType Container)) { continue }
    $skills = Join-Path $dir.Trim() 'skills'
    if ($script:SkillRoots -notcontains $skills) { $script:SkillRoots = @($script:SkillRoots) + $skills }
  }
}
Add-ProfileSkillRoots

$OnWindows = ($env:OS -eq 'Windows_NT')
$SkillMode = if ($env:AI_SKILLS_MODE) { $env:AI_SKILLS_MODE } elseif ($OnWindows) { 'copy' } else { 'link' }
# Marker written into copied skill folders so two template repos that ship a skill with the
# same name (e.g. this repo and a downstream fork) never fight over ~/.claude/skills/<name>.
$SkillOriginFile = '.ai-template-origin'
# Names a skills dir no longer ships; the sync removes our copies of them (see Sync-GlobalSkills).
$SkillRetiredFile = 'RETIRED'
# A project whose .gitignore holds this exact line is SHARED: its pointer files are personal
# tooling, kept on disk and gitignored, never committed (see --shared).
$SharedSentinel = '# ai-templates: local-only'
# Legacy (before --private-layer): a .gitignore holding this line put the project in private
# mode. --private-layer removes it, with the paths the engine listed under it.
$PrivateDocsMark = '# ai-templates: private AI docs'
# The managed block in <git-common-dir>/info/exclude: "# ai-templates: <mode>" first, then the
# private layer's paths, then this line. Rewritten whole; the mode line is the project's mode.
$ExcludeEnd = '# ai-templates: end'
$ExcludeModeRe = '^# ai-templates: (tracked|private|team|shared)[ \t]*$'
# Commit message of the switch to the private layer (one commit: untrack + .gitignore cleanup).
$PrivateLayerMsg = 'chore: move the personal AI layer out of the repo (private layer)'
# First lines of a hook this engine installed ([SHARED_HOOKS]); a hook without it is foreign.
$HookMarker = '# ai-templates: managed git hook'

if (-not (Test-Path -LiteralPath $ManifestFile)) {
  Write-Error "Manifest file not found: $ManifestFile"
  exit 1
}

$PointerMap = @()
$LivingDocsMap = @()
$ObsoleteMap = @()
$SharedHookMap = @()

# The merge key of a manifest entry: the destination (after "|") for pointers and living docs,
# the path (before "|") for obsolete entries. An entry without "|" is its own key.
function Get-EntryKey([string]$Entry, [string]$Side) {
  $parts = $Entry -split '\|', 2
  if ($Side -eq 'dest' -and $parts.Count -gt 1) { return $parts[1] }
  return $parts[0]
}

# Remove every entry of a dest-keyed map that targets <Dest>. Returns the new array.
function Remove-MapDest([string[]]$Map, [string]$Dest) {
  $out = @()
  foreach ($e in @($Map)) { if ((Get-EntryKey $e 'dest') -ne $Dest) { $out += $e } }
  return ,$out
}

# Append <Entry> to a map, replacing an existing entry with the same key in place. Returns the
# new array (always as an array, even with a single element).
function Merge-MapEntry([string[]]$Map, [string]$Entry, [string]$Side) {
  $out = @($Map)
  $key = Get-EntryKey $Entry $Side
  for ($i = 0; $i -lt $out.Count; $i++) {
    if ((Get-EntryKey $out[$i] $Side) -eq $key) { $out[$i] = $Entry; return ,$out }
  }
  $out += $Entry
  return ,$out
}

# Parse one manifest into the three maps (merging by destination).
function Read-Manifest([string]$File) {
  $section = ''
  foreach ($raw in Get-Content -LiteralPath $File) {
    $line = $raw.Trim()      # tolerate CRLF checkouts on Windows
    if ([string]::IsNullOrEmpty($line) -or $line.StartsWith('#')) { continue }
    if ($line -match '^\[(.*)\]$') { $section = $Matches[1]; continue }
    # A destination is a pointer OR a living doc, never both: a dest-keyed entry evicts the same
    # destination from the other map, so an overlay can change a file's class.
    switch ($section) {
      'POINTERS'    { $script:LivingDocsMap = Remove-MapDest $script:LivingDocsMap (Get-EntryKey $line 'dest')
                      $script:PointerMap = Merge-MapEntry $script:PointerMap $line 'dest' }
      'LIVING_DOCS' { $script:PointerMap = Remove-MapDest $script:PointerMap (Get-EntryKey $line 'dest')
                      $script:LivingDocsMap = Merge-MapEntry $script:LivingDocsMap $line 'dest' }
      'OBSOLETE'    { $script:ObsoleteMap = Merge-MapEntry $script:ObsoleteMap $line 'path' }
      'SHARED_HOOKS' { $script:SharedHookMap = Merge-MapEntry $script:SharedHookMap $line 'dest' }
    }
  }
}

Read-Manifest $ManifestFile
if ($OverlayManifestFile -and (Test-Path -LiteralPath $OverlayManifestFile -PathType Leaf)) { Read-Manifest $OverlayManifestFile }

$script:SyncQuiet = $false
$script:SyncChanged = @()        # project-relative paths touched by the last Sync-AiTemplates call
$script:SyncBootstrapped = $false
$script:SyncCommitted = $false
$script:SyncPushed = $false
$script:SyncUntracked = @()      # paths --shared / --private-layer removed from the index (commit records it)
$script:SyncSwitchMsg = ''       # commit message of a mode switch (--private-layer), '' otherwise
$script:SyncHooks = @()          # "action hook" notes from the last Sync-SharedHooks (never committed)
$script:SyncExclude = $false     # the last run wrote (or would write) the .git/info/exclude block
$script:SyncSwitchWaits = $false # the last -PrivateLayer switch waited for the remote (nothing changed)
$script:GitExit = 0

function Write-Sync([string]$Message) { if (-not $script:SyncQuiet) { Write-Host $Message } }

# Context budget: the files a project's CLAUDE.md @imports ride along in EVERY session, so an
# oversized one silently costs tokens forever. Warn (one line per file, even with --quiet and
# --dry-run) but never fail. Import list = the relative `@path` lines of the project's CLAUDE.md,
# or AGENTS.md + .github/PROJECT_STATE.md when it has none. AI_CONTEXT_BUDGET_KB overrides 8.
function Test-ContextBudget([string]$Target) {
  try {
    $kb = 8
    if ("$env:AI_CONTEXT_BUDGET_KB" -match '^[0-9]+$') { $kb = [int]$env:AI_CONTEXT_BUDGET_KB }
    $imports = @()
    $claude = Join-Path $Target 'CLAUDE.md'
    if (Test-Path -LiteralPath $claude -PathType Leaf) {
      foreach ($line in [IO.File]::ReadAllLines($claude)) {
        if ($line -match '^@(\S+)') { $imports += $Matches[1] }
      }
    }
    if ($imports.Count -eq 0) { $imports = @('AGENTS.md', '.github/PROJECT_STATE.md') }
    foreach ($rel in $imports) {
      if ($rel -match '^[/\\~]' -or $rel -match '^[A-Za-z]:') { continue }
      if ($rel.StartsWith('./')) { $rel = $rel.Substring(2) }
      $path = Join-Path $Target $rel
      if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
      $bytes = (Get-Item -LiteralPath $path).Length
      if ($bytes -gt $kb * 1024) {
        $size = [math]::Floor(($bytes + 1023) / 1024)
        Write-Host "ai-sync: context budget: $rel is $size KB (> $kb KB), loaded into every session - move detail to docs/state/*.md and keep an index"
      }
    }
  } catch { }
}

function Invoke-Git([string[]]$GitArgs) {
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $out = & git @GitArgs 2>&1
    $script:GitExit = $LASTEXITCODE
    return @($out | Where-Object { $_ -is [string] })
  } finally { $ErrorActionPreference = $prev }
}

function Get-LinkTarget($Item) {
  if ($Item.PSObject.Properties['LinkTarget']) { return $Item.LinkTarget }
  return ($Item.Target | Select-Object -First 1)
}

function Test-SymLink([string]$Path) {
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if ($null -eq $item) { return $false }
  return ($item.LinkType -eq 'SymbolicLink') -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Test-SameFile([string]$A, [string]$B) {
  if (-not (Test-Path -LiteralPath $A -PathType Leaf) -or -not (Test-Path -LiteralPath $B -PathType Leaf)) { return $false }
  return (Get-FileHash -LiteralPath $A -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $B -Algorithm SHA256).Hash
}

function Get-DirSignature([string]$Dir) {
  $root = (Get-Item -LiteralPath $Dir).FullName.TrimEnd('\', '/')
  Get-ChildItem -LiteralPath $root -Recurse -File -Force | Where-Object { $_.Name -ne $SkillOriginFile } | Sort-Object FullName | ForEach-Object {
    $_.FullName.Substring($root.Length).Replace('\', '/') + '|' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
  }
}

function Test-SameDir([string]$A, [string]$B) {
  return ((Get-DirSignature $A) -join "`n") -eq ((Get-DirSignature $B) -join "`n")
}

function Remove-PathSafely([string]$Path) {
  # A symlink is removed as a link (never followed into the template); anything else recursively.
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if ($null -eq $item) { return }
  if ($item.LinkType -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { $item.Delete(); return }
  Remove-Item -LiteralPath $Path -Recurse -Force
}

# The rendered hook with LF endings whatever the checkout (sh chokes on CR) - the bytes the bash
# twin writes, so both engines install an identical file.
function Get-HookBytes([string]$Rel) {
  return ,[byte[]]@((Get-RenderedBytes $Rel) | Where-Object { $_ -ne 13 })
}

# Absolute git dir shared by all the repo's worktrees (a submodule's lives under the
# superproject's .git/modules), or '' outside a git work tree.
function Get-GitCommonDir([string]$Target) {
  Invoke-Git @('-C', $Target, 'rev-parse', '--is-inside-work-tree') | Out-Null
  if ($script:GitExit -ne 0) { return '' }
  $common = (Invoke-Git @('-C', $Target, 'rev-parse', '--git-common-dir')) | Select-Object -First 1
  if ($script:GitExit -ne 0 -or -not $common) { return '' }
  if (-not [IO.Path]::IsPathRooted($common)) { $common = Join-Path $Target $common }
  try { return (Resolve-Path -LiteralPath $common).Path } catch { return '' }
}

# Absolute hooks folder of the target's repo (shared by all worktrees), or '' outside git.
function Get-HooksDir([string]$Target) {
  $common = Get-GitCommonDir $Target
  if (-not $common) { return '' }
  return (Join-Path $common 'hooks')
}

# The mode named by the managed block's first line in an exclude file, or '' when it holds none.
function Get-ExcludeBlockMode([string]$File) {
  if (-not $File -or -not (Test-Path -LiteralPath $File -PathType Leaf)) { return '' }
  try {
    foreach ($line in [IO.File]::ReadAllLines($File)) {
      if ($line -cmatch $ExcludeModeRe) { return $Matches[1] }
    }
  } catch { }
  return ''
}

# True when the file holds one of these exact lines (a CR at the end of a line is ignored).
function Test-HasLine([string]$File, [string[]]$Lines) {
  if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { return $false }
  try {
    foreach ($line in @(Get-Content -LiteralPath $File -ErrorAction Stop)) {
      if ($Lines -ccontains ([string]$line -replace "`r$", '')) { return $true }
    }
  } catch { }
  return $false
}

# Absolute top level of the target's work tree, or '' outside git.
function Get-GitTop([string]$Target) {
  if (-not $Target -or -not (Test-Path -LiteralPath $Target -PathType Container)) { return '' }
  $top = (Invoke-Git @('-C', $Target, 'rev-parse', '--show-toplevel')) | Select-Object -First 1
  if ($script:GitExit -ne 0 -or -not $top) { return '' }
  return [IO.Path]::GetFullPath($top)
}

# The code root holding the project: the parent folder of its git top level, when that folder
# holds .ai-root\ or .ai-context-remote. '' otherwise.
function Get-CodeRoot([string]$Target) {
  $top = Get-GitTop $Target
  if (-not $top) { return '' }
  $root = Split-Path -Parent $top
  if (-not $root) { return '' }
  if ((Test-Path -LiteralPath (Join-Path $root '.ai-root') -PathType Container) -or
      (Test-Path -LiteralPath (Join-Path $root '.ai-context-remote'))) { return $root }
  return ''
}

# The nearest folder above the project's git top level (its parent first) holding .ai-root\ or
# .ai-context-remote, so Root\group\proj finds Root: where the hidden repo's remote and the
# owner's emails come from. The walk stops below $HOME and every folder above it ($HOME's
# .ai-context-remote is the personal fallback, not a root; a sandbox HOME keeps the real one out
# of reach). '' when none does. The registry and the dev context keep Get-CodeRoot (the parent
# folder only).
function Get-AncestorRoot([string]$Target) {
  $d = Get-GitTop $Target
  if (-not $d) { return '' }
  $sep = [IO.Path]::DirectorySeparatorChar
  $homeDir = ''
  if ($HOME) { try { $homeDir = [IO.Path]::GetFullPath($HOME).TrimEnd('\', '/') + $sep } catch { $homeDir = '' } }
  while ($true) {
    $d = Split-Path -Parent $d
    if (-not $d) { return '' }
    if ($homeDir -and $homeDir.StartsWith($d.TrimEnd('\', '/') + $sep, [StringComparison]::OrdinalIgnoreCase)) { return '' }
    if ((Test-Path -LiteralPath (Join-Path $d '.ai-root') -PathType Container) -or
        (Test-Path -LiteralPath (Join-Path $d '.ai-context-remote'))) { return $d }
  }
}

# True when the project is a TEAM repo: an author email of its last 2000 commits (HEAD) is
# neither the repo's user.email nor listed in <ancestor root>\.ai-root\owner-emails (one per line;
# # comments, blank lines and CRs ignored), compared without case. Bot authors (an email holding
# [bot], noreply@github.com) do not count; no history = not team.
function Test-TeamRepo([string]$Target) {
  $top = Get-GitTop $Target
  if (-not $top) { return $false }
  $owners = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  $root = Get-AncestorRoot $top
  if ($root) {
    $file = Join-Path (Join-Path $root '.ai-root') 'owner-emails'
    if (Test-Path -LiteralPath $file -PathType Leaf) {
      try {
        foreach ($raw in [IO.File]::ReadAllLines($file)) {
          $o = $raw.Trim()
          if ($o -and -not $o.StartsWith('#')) { [void]$owners.Add($o) }
        }
      } catch { }
    }
  }
  $me = ((Invoke-Git @('-C', $top, 'config', '--get', 'user.email')) | Select-Object -First 1)
  if ($script:GitExit -ne 0 -or -not $me) { $me = '' }
  $me = $me.Trim()
  $emails = @(Invoke-Git @('-C', $top, 'log', '-n', '2000', '--format=%ae', 'HEAD'))
  if ($script:GitExit -ne 0) { return $false }
  foreach ($raw in $emails) {
    $e = ([string]$raw).Trim()
    if (-not $e -or $e.ToLowerInvariant().Contains('[bot]') -or $e -eq 'noreply@github.com') { continue }
    if ($me -and $e -eq $me) { continue }
    if ($owners.Contains($e)) { continue }
    return $true
  }
  return $false
}

# <root>\.ai-root when it is a git checkout of its own (not a folder inside another repo); ''
# otherwise.
function Get-AiRootCheckout([string]$Root) {
  if (-not $Root) { return '' }
  $air = Join-Path $Root '.ai-root'
  if (-not (Test-Path -LiteralPath $air -PathType Container)) { return '' }
  $cdup = @(Invoke-Git @('-C', $air, 'rev-parse', '--show-cdup') | Where-Object { $_ })
  if ($script:GitExit -ne 0 -or $cdup.Count -gt 0) { return '' }
  return $air
}

# A remote URL reduced for comparison: lowercase, no https/http/ssh/git scheme, no user@ or
# credentials, git@host:owner/repo -> host/owner/repo, no trailing / or .git.
function Get-NormalizedOrigin([string]$Url) {
  $u = ("$Url" -replace "`r", '').Trim().ToLowerInvariant()
  $scheme = $false
  if ($u -match '^(https|http|ssh|git)://') { $u = $u.Substring($Matches[0].Length); $scheme = $true }
  $slash = $u.IndexOf('/')
  if ($slash -ge 0) { $head = $u.Substring(0, $slash); $rest = $u.Substring($slash) } else { $head = $u; $rest = '' }
  $at = $head.LastIndexOf('@')
  if ($at -ge 0) { $head = $head.Substring($at + 1) }
  if (-not $scheme) {
    $colon = $head.IndexOf(':')
    if ($colon -ge 0) { $rest = '/' + $head.Substring($colon + 1) + $rest; $head = $head.Substring(0, $colon) }
  }
  $u = $head + $rest
  while ($true) {
    if ($u.EndsWith('/')) { $u = $u.Substring(0, $u.Length - 1) }
    elseif ($u.EndsWith('.git')) { $u = $u.Substring(0, $u.Length - 4) }
    else { break }
  }
  return $u
}

# The value of the file's first "<key>=" line (CR and surrounding blanks stripped), or ''.
function Get-RegistryValue([string]$File, [string]$Key) {
  if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { return '' }
  try {
    foreach ($line in ([IO.File]::ReadAllText($File) -split "`n")) {
      $l = $line -replace "`r$", ''
      if ($l.StartsWith("$Key=", [StringComparison]::Ordinal)) { return $l.Substring($Key.Length + 1).Trim(' ', "`t") }
    }
  } catch { }
  return ''
}

# The entry's mode= value when it is a valid mode, else ''.
function Get-RegistryEntryMode([string]$File) {
  $m = Get-RegistryValue $File 'mode'
  if (@('tracked', 'private', 'team', 'shared') -ccontains $m) { return $m }
  return ''
}

# The mode the code root's registry records for the project: <root>\.ai-root\projects\<folder
# name> (any case, Get-RegistryName), else the entry whose origin= matches the project's
# remote.origin.url (both normalized, see Get-NormalizedOrigin). An invalid mode is ignored.
function Get-RegistryMode([string]$Target) {
  $root = Get-CodeRoot $Target
  if (-not $root) { return '' }
  $reg = Join-Path (Join-Path $root '.ai-root') 'projects'
  if (-not (Test-Path -LiteralPath $reg -PathType Container)) { return '' }
  $top = Get-GitTop $Target
  $mode = Get-RegistryEntryMode (Join-Path $reg (Get-RegistryName $reg (Split-Path -Leaf $top)))
  if (-not $mode) {
    $origin = (Invoke-Git @('-C', $top, 'config', '--get', 'remote.origin.url')) | Select-Object -First 1
    if ($script:GitExit -ne 0 -or -not $origin) { return '' }
    $want = Get-NormalizedOrigin $origin
    # The files a bash glob sees: no dot-file.
    foreach ($f in @(Get-ChildItem -LiteralPath $reg -File -Force | Where-Object { -not $_.Name.StartsWith('.') } | Sort-Object Name)) {
      $o = Get-RegistryValue $f.FullName 'origin'
      if (-not $o -or (Get-NormalizedOrigin $o) -cne $want) { continue }
      $mode = Get-RegistryEntryMode $f.FullName
      if ($mode) { break }
    }
  }
  return $mode
}

# tracked | private | team | shared. The managed block in <git-common-dir>/info/exclude first;
# else the legacy .gitignore markers (private AI docs -> private, local-only -> shared); else the
# registry; else tracked.
function Get-ProjectMode([string]$Target) {
  $mode = ''
  $common = Get-GitCommonDir $Target
  if ($common) { $mode = Get-ExcludeBlockMode (Join-Path (Join-Path $common 'info') 'exclude') }
  if (-not $mode) {
    $gi = Join-Path $Target '.gitignore'
    if (Test-HasLine $gi @($PrivateDocsMark)) { $mode = 'private' }
    elseif (Test-HasLine $gi @($SharedSentinel)) { $mode = 'shared' }
  }
  if (-not $mode) { $mode = Get-RegistryMode $Target }
  if (-not $mode) { $mode = 'tracked' }
  return $mode
}

# Layer B, the paths the hidden repo versions (folders end in /): the living docs except
# .env.example, docs/state/, docs/plans/, config.local/ (the exclude block matches it at any
# depth), .claude/memory/.
function Get-PrivateDocPaths {
  foreach ($entry in $LivingDocsMap) {
    $rel = ($entry -split '\|', 2)[1]
    if ($rel -ne '.env.example') { $rel }
  }
  'docs/state/'; 'docs/plans/'; 'config.local/'; '.claude/memory/'
}

# Layer C, rebuilt from the templates on every machine: every [POINTERS] path, the whole .claude/
# folder, CLAUDE.local.md.
function Get-GeneratedPaths {
  foreach ($entry in $PointerMap) { ($entry -split '\|', 2)[1] }
  '.claude/'; 'CLAUDE.local.md'
}

# Layers B and C, without duplicates or paths a listed folder already covers (.claude/ covers
# .claude/settings.json and .claude/memory/).
function Get-LayerPaths {
  $all = @(Get-PrivateDocPaths) + @(Get-GeneratedPaths)
  $seen = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($p in $all) {
    if ($seen.Contains($p)) { continue }
    $covered = $false
    foreach ($q in $all) {
      if ($q -cne $p -and $q.EndsWith('/') -and $p.StartsWith($q, [StringComparison]::Ordinal)) { $covered = $true; break }
    }
    if ($covered) { continue }
    [void]$seen.Add($p)
    $p
  }
}

# What --shared / --private-docs used to write into .gitignore: both marker lines, every
# [POINTERS] path, the old layer B (living docs except .env.example, docs/state/).
# --private-layer removes exactly these lines, nothing else.
function Get-LegacyGitignoreLines {
  $SharedSentinel; $PrivateDocsMark
  foreach ($entry in $PointerMap) { ($entry -split '\|', 2)[1] }
  foreach ($entry in $LivingDocsMap) {
    $rel = ($entry -split '\|', 2)[1]
    if ($rel -ne '.env.example') { $rel }
  }
  'docs/state/'
}

# What a team repo tracks of layers B and C, one file per item: the tracked files of every B and
# C entry (a file, or a folder's files) and of every config.local/ folder at any depth. Team mode
# never writes, untracks or commits them; the hidden repo never adds them.
function Get-TeamTracked([string]$Dir) {
  $specs = @(@(Get-PrivateDocPaths) + @(Get-GeneratedPaths) | Where-Object { $_ -cne 'config.local/' })
  $seen = New-Object 'System.Collections.Generic.HashSet[string]'
  if ($specs.Count -gt 0) {
    foreach ($f in @(Invoke-Git (@('-C', $Dir, '-c', 'core.quotepath=off', 'ls-files', '--') + $specs))) {
      if ($f -and $seen.Add($f)) { $f }
    }
  }
  foreach ($f in @(Invoke-Git @('-C', $Dir, '-c', 'core.quotepath=off', 'ls-files'))) {
    if ($f -and ('/' + $f).Contains('/config.local/') -and $seen.Add($f)) { $f }
  }
}

# True when $Tracked (Get-TeamTracked's output) holds the entry: the file itself, a file of the
# folder, or (config.local/) a file of one at any depth.
function Test-TeamHas([string]$Entry, [string[]]$Tracked) {
  foreach ($t in @($Tracked)) {
    if ($Entry -ceq 'config.local/') { if (('/' + $t).Contains('/config.local/')) { return $true } }
    elseif ($Entry.EndsWith('/')) { if ($t.StartsWith($Entry, [StringComparison]::Ordinal)) { return $true } }
    elseif ($t -ceq $Entry) { return $true }
  }
  return $false
}

# The team block's paths: layers B and C minus what the repo tracks (a folder holding a tracked
# file is left out whole, except .claude/memory/: a tracked MEMORY.md stays tracked, and the
# directory pattern still hides the untracked personal files), without the paths a kept folder
# covers; then .env and .claude/settings.local.json when the repo neither tracks them nor ignores
# them outside this
# block (git check-ignore -v: a match on the block's own lines in $File does not count, so every
# run gives the same answer).
function Get-TeamBlockPaths([string]$Target, [string]$File) {
  $tracked = @(Get-TeamTracked $Target)
  $kept = New-Object 'System.Collections.Generic.List[string]'
  foreach ($p in @(@(Get-PrivateDocPaths) + @(Get-GeneratedPaths))) {
    if ($kept.Contains($p)) { continue }
    # A tracked file keeps its folder out of the block, except .claude/memory/: the pattern
    # ignores only untracked files, so the team's MEMORY.md stays tracked.
    if ($p -cne '.claude/memory/' -and (Test-TeamHas $p $tracked)) { continue }
    $kept.Add($p)
  }
  $start = 0; $end = 0; $rangeRead = $false
  foreach ($p in @($kept) + @('.env', '.claude/settings.local.json')) {
    $covered = $false
    foreach ($q in $kept) {
      if ($q -cne $p -and $q.EndsWith('/') -and $p.StartsWith($q, [StringComparison]::Ordinal)) { $covered = $true; break }
    }
    if ($covered) { continue }
    if ($p -cne '.env' -and $p -cne '.claude/settings.local.json') { $p; continue }
    if (@(Invoke-Git @('-C', $Target, 'ls-files', '--', $p) | Where-Object { $_ }).Count -gt 0) { continue }
    if (-not $rangeRead -and $File -and (Test-Path -LiteralPath $File -PathType Leaf)) {
      $rangeRead = $true
      try {
        $n = 0
        foreach ($l in [IO.File]::ReadAllLines($File)) {
          $n++
          $l = $l -replace "`r$", ''
          if ($start -eq 0) { if ($l -cmatch $ExcludeModeRe) { $start = $n } }
          elseif ($l -ceq $ExcludeEnd) { $end = $n; break }
        }
        if ($start -gt 0 -and $end -eq 0) { $end = [int]::MaxValue }
      } catch { $start = 0 }
    }
    $v = @(Invoke-Git @('-C', $Target, 'check-ignore', '-v', '--', $p)) | Select-Object -First 1
    if ($script:GitExit -eq 0 -and $v) {
      $s = ($v -split "`t", 2)[0]
      $m = [regex]::Match($s, ':([0-9]+):')
      if (-not $m.Success) { continue }
      $src = $s.Substring(0, $m.Index)
      $pat = $s.Substring($m.Index + $m.Length)
      if (-not $pat.StartsWith('!')) {
        if (-not $src.EndsWith('info/exclude')) { continue }
        $ln = [long]$m.Groups[1].Value
        if (-not ($start -gt 0 -and $ln -ge $start -and $ln -le $end)) { continue }
      }
    }
    $p
  }
}

# The managed block: the mode line, a note, the layer paths anchored at the target (prefix = its
# path inside the work tree; config.local/ unanchored, so an app's folder at any depth matches),
# the end line. The paths: layers B and C (Get-LayerPaths); in team mode only what the repo does
# not track (Get-TeamBlockPaths, which reads the target and its exclude file).
function Get-ExcludeBlock([string]$Mode, [string]$Prefix, [string]$Target, [string]$File) {
  "# ai-templates: $Mode"
  '# Managed by sync-ai-templates (AICodeFactory), rewritten whole: keep your own lines outside it.'
  $paths = if ($Mode -ceq 'team') { @(Get-TeamBlockPaths $Target $File) } else { @(Get-LayerPaths) }
  foreach ($p in $paths) {
    if ($p -ceq 'config.local/') { $p } else { "/$Prefix$p" }
  }
  $ExcludeEnd
}

# Write or refresh the managed block in <git-common-dir>/info/exclude, so git ignores layers B
# and C without a .gitignore line (works in a worktree or a submodule). The block is replaced in
# place, or appended; lines outside it are kept. Written only when the result differs. Sets
# $script:SyncExclude when it changed. A team block follows what the repo tracks: rewritten when
# that changes.
function Sync-ExcludeBlock([string]$Target, [string]$Mode, [bool]$DryRun) {
  $script:SyncExclude = $false
  $common = Get-GitCommonDir $Target
  if (-not $common) { return }
  $info = Join-Path $common 'info'
  $file = Join-Path $info 'exclude'
  $prefix = (Invoke-Git @('-C', $Target, 'rev-parse', '--show-prefix')) | Select-Object -First 1
  if ($script:GitExit -ne 0 -or -not $prefix) { $prefix = '' }
  $block = @(Get-ExcludeBlock $Mode $prefix $Target $file)
  $action = 'modify'
  $old = $null
  if (Test-Path -LiteralPath $file -PathType Leaf) {
    try { $old = [IO.File]::ReadAllText($file) }
    catch { Write-Host "ai-sync: could not read $file — private layer not excluded"; return }
    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($l in ($old -split "`n")) { $lines.Add($l) }
    if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') { $lines.RemoveAt($lines.Count - 1) }
    $out = New-Object 'System.Collections.Generic.List[string]'
    $skip = $false; $done = $false
    foreach ($raw in $lines) {
      $l = $raw -replace "`r$", ''
      if ($skip) { if ($l -ceq $ExcludeEnd) { $skip = $false }; continue }
      if ($l -cmatch $ExcludeModeRe) {
        if (-not $done) { $out.AddRange([string[]]$block) }
        $done = $true; $skip = $true
        continue
      }
      $out.Add($raw)
    }
    if (-not $done) { $out.AddRange([string[]]$block) }
    $new = ($out -join "`n") + "`n"
    if ($new -ceq $old) { return }
  } else {
    $action = 'create'
    $new = ($block -join "`n") + "`n"
  }
  Write-Sync "  [$action] .git/info/exclude"
  $script:SyncExclude = $true
  if (-not $DryRun) {
    try {
      New-Item -ItemType Directory -Force -Path $info | Out-Null
      [IO.File]::WriteAllText($file, $new, (New-Object Text.UTF8Encoding $false))
    } catch { Write-Host "ai-sync: could not write $file — private layer not excluded" }
  }
}

# The layer B and C paths git still tracks in the target (as the untrack takes them: a folder
# stays a folder). config.local/ is looked for at any depth.
function Get-TrackedLayerPaths([string]$Target) {
  foreach ($p in @(Get-LayerPaths)) {
    if ($p -ceq 'config.local/') {
      $seen = New-Object 'System.Collections.Generic.HashSet[string]'
      foreach ($f in @(Invoke-Git @('-C', $Target, '-c', 'core.quotepath=off', 'ls-files'))) {
        $i = ('/' + $f).IndexOf('/config.local/', [StringComparison]::Ordinal)
        if ($i -ge 0) {
          $d = $f.Substring(0, $i + 13)
          if ($seen.Add($d)) { $d }
        }
      }
    } elseif (@(Invoke-Git @('-C', $Target, 'ls-files', '--', $p)).Count -gt 0) { $p }
  }
}

# [SHARED_HOOKS] into the repo's hooks folder: created or refreshed while the project is shared,
# private or team (anything but tracked), removed once it is tracked. Only a hook that carries
# $HookMarker is ours: a foreign hook of the same name is never touched (it can keep running -
# the private-terms hook chains to <name>.local). core.hooksPath means another tool owns the
# hooks: nothing is installed. Hooks live under .git, so nothing here is ever committed.
function Sync-SharedHooks([string]$Target, [bool]$Guard, [bool]$DryRun) {
  $script:SyncHooks = @()
  if (@($SharedHookMap).Count -eq 0) { return }
  if (-not (Test-Path -LiteralPath (Join-Path $Target '.git'))) { return }   # cheap exit for non-repos
  $hooks = Get-HooksDir $Target
  if (-not $hooks) { return }
  if (-not $Guard) {
    foreach ($entry in $SharedHookMap) {
      $name = ($entry -split '\|', 2)[1]
      $dest = Join-Path $hooks $name
      if (-not (Test-Path -LiteralPath $dest -PathType Leaf)) { continue }
      if (-not ([IO.File]::ReadAllLines($dest) -ccontains $HookMarker)) { continue }
      Write-Sync "  [remove] .git/hooks/$name (tracked project)"
      $script:SyncHooks += "removed $name"
      if (-not $DryRun) { Remove-Item -LiteralPath $dest -Force }
    }
    return
  }
  $hooksPath = (Invoke-Git @('-C', $Target, 'config', 'core.hooksPath')) | Select-Object -First 1
  if ($hooksPath) { Write-Sync "ai-sync: core.hooksPath is set in $Target — private-terms guard not installed"; return }
  foreach ($entry in $SharedHookMap) {
    $srcRel, $name = $entry -split '\|', 2
    $dest = Join-Path $hooks $name
    $src = Get-TemplatePath $srcRel
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { Write-Warning "template $src missing - skipped hook $name"; continue }
    [byte[]]$bytes = Get-HookBytes $srcRel
    $action = $null
    if (-not (Test-Path -LiteralPath $dest)) { $action = 'create' }
    elseif (-not ([IO.File]::ReadAllLines($dest) -ccontains $HookMarker)) {
      Write-Sync "ai-sync: $name hook in $Target is not ours — left alone; rename it $name.local to keep it and get the private-terms guard"
      continue
    } elseif ([Convert]::ToBase64String([IO.File]::ReadAllBytes($dest)) -eq [Convert]::ToBase64String($bytes)) { continue }
    else { $action = 'update' }
    Write-Sync "  [$action] .git/hooks/$name"
    $script:SyncHooks += "${action}d $name"
    if ($DryRun) { continue }
    try {
      New-Item -ItemType Directory -Force -Path $hooks | Out-Null
      [IO.File]::WriteAllBytes($dest, $bytes)
      if (-not $OnWindows) { & chmod +x $dest 2>$null }   # Git for Windows runs a hook by its #! line
    } catch { Write-Host "ai-sync: could not write $dest — private-terms guard not installed" }
  }
}

# A POSIX sh for the private-terms scan: sh on PATH, else the one Git for Windows ships.
function Get-PosixSh {
  $c = Get-Command sh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { return $c.Source }
  $g = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($g) {
    foreach ($rel in @('..\bin\sh.exe', '..\..\bin\sh.exe', '..\usr\bin\sh.exe')) {
      $p = Join-Path (Split-Path -Parent $g.Source) $rel
      if (Test-Path -LiteralPath $p -PathType Leaf) { return (Resolve-Path -LiteralPath $p).Path }
    }
  }
  return $null
}

# Run the private-terms check (the [SHARED_HOOKS] pre-commit hook, in --scan mode) over the
# target's tracked files, and with -History over every commit. Returns the hook's exit code:
# 0 clean or no list, 1 hits, 2 not a git work tree / no sh / no hook entry.
function Invoke-PrivateTermsScan([string]$Target, [bool]$History) {
  $src = $null
  foreach ($entry in $SharedHookMap) { if (($entry -split '\|', 2)[1] -eq 'pre-commit') { $src = ($entry -split '\|', 2)[0] } }
  if (-not $src -or -not (Test-Path -LiteralPath (Get-TemplatePath $src) -PathType Leaf)) {
    Write-Host "ai-sync: no pre-commit entry under [SHARED_HOOKS] - nothing to scan with"; return 2
  }
  $sh = Get-PosixSh
  if (-not $sh) { Write-Host "ai-sync: no POSIX sh found (install Git for Windows) - cannot scan"; return 2 }
  $tmp = [IO.Path]::GetTempFileName()
  try {
    [IO.File]::WriteAllBytes($tmp, (Get-HookBytes $src))
    $shArgs = @($tmp, '--scan')
    if ($History) { $shArgs += '--history' }
    $shArgs += $Target
    # Host output, not pipeline output: the caller gets the exit code alone.
    & $sh @shArgs | ForEach-Object { Write-Host $_ }
    return $LASTEXITCODE
  } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

# Commit exactly the paths this run touched (`git commit -- <paths>`), leaving any other work
# in the project alone. Refuses to run mid-merge/rebase.
function Invoke-SyncCommit([string]$Target) {
  $script:SyncCommitted = $false
  if ($script:SyncChanged.Count -eq 0) { return }
  $root = (Invoke-Git @('-C', $Target, 'rev-parse', '--show-toplevel')) | Select-Object -First 1
  if ($script:GitExit -ne 0 -or -not $root) { return }
  $gitDir = (Invoke-Git @('-C', $Target, 'rev-parse', '--absolute-git-dir')) | Select-Object -First 1
  if ($script:GitExit -ne 0 -or -not $gitDir) { return }
  foreach ($marker in @('MERGE_HEAD', 'rebase-merge', 'rebase-apply')) {
    if (Test-Path -LiteralPath (Join-Path $gitDir $marker)) {
      Write-Host "ai-sync: merge/rebase in progress in $Target - synced files left uncommitted"
      return
    }
  }
  $status = Invoke-Git (@('-C', $Target, 'status', '--porcelain', '--untracked-files=all', '--') + $script:SyncChanged)
  # 'D  ' = untracked by --shared: already staged, and the file stays on disk.
  $paths = @($status | Where-Object { $_ -and -not $_.StartsWith('D  ') } | ForEach-Object { $_.Substring(3) })
  if ($paths.Count -eq 0 -and $script:SyncUntracked.Count -eq 0) { return }
  $msg = if ($script:SyncBootstrapped) { 'docs: bootstrap project documentation' } else { 'docs: sync AI instruction templates' }
  if ($script:SyncSwitchMsg) { $msg = $script:SyncSwitchMsg }
  if ($paths.Count -gt 0) {
    Invoke-Git (@('-C', $root, 'add', '-A', '--') + $paths) | Out-Null
    if ($script:GitExit -ne 0) { Write-Host "ai-sync: git add failed in $root"; return }
  }
  if ($script:SyncUntracked.Count -gt 0) {
    # `git commit -- <paths>` would re-add the untracked files from the working tree, so the
    # switch commits the whole index - Sync-AiTemplates checked it was empty beforehand.
    $switchMsg = if ($script:SyncSwitchMsg) { $script:SyncSwitchMsg } else { 'chore: keep AI assistant files local-only (shared project)' }
    Invoke-Git @('-C', $root, 'commit', '-q', '-m', $switchMsg) | Out-Null
  } else {
    Invoke-Git (@('-C', $root, 'commit', '-q', '-m', $msg, '--') + $paths) | Out-Null
  }
  if ($script:GitExit -ne 0) { Write-Host "ai-sync: git commit failed in $root"; return }
  $script:SyncCommitted = $true
}

# Push the commit we just made, when the branch tracks a remote.
function Invoke-SyncPush([string]$Target) {
  $script:SyncPushed = $false
  $root = (Invoke-Git @('-C', $Target, 'rev-parse', '--show-toplevel')) | Select-Object -First 1
  if ($script:GitExit -ne 0 -or -not $root) { return }
  $name = Split-Path -Leaf $root
  Invoke-Git @('-C', $root, 'rev-parse', '--abbrev-ref', '@{u}') | Out-Null
  if ($script:GitExit -ne 0) { Write-Sync "ai-sync: $name has no upstream branch - commit stays local"; return }
  Invoke-Git @('-C', $root, 'push', '-q') | Out-Null
  if ($script:GitExit -eq 0) { $script:SyncPushed = $true }
  else { Write-Host "ai-sync: push failed in $name (diverged, offline, or auth) - commit stays local" }
}

# Commits on HEAD not on its upstream: a number, 'no-remote', or '' when not a git repo.
function Get-AheadCount([string]$Dir) {
  Invoke-Git @('-C', $Dir, 'rev-parse', '--is-inside-work-tree') | Out-Null
  if ($script:GitExit -ne 0) { return '' }
  Invoke-Git @('-C', $Dir, 'rev-parse', '--abbrev-ref', '@{u}') | Out-Null
  if ($script:GitExit -ne 0) { return 'no-remote' }
  $n = (Invoke-Git @('-C', $Dir, 'rev-list', '--count', '@{u}..HEAD')) | Select-Object -First 1
  if ($script:GitExit -ne 0) { return '?' }
  return $n
}

# -PrivateLayer runs the hidden repo's round trip itself (the caller skips its own): a switch
# changes the code repo only once the remote holds the hidden branch, else it prints one line and
# sets $script:SyncSwitchWaits. A private project offline with no hidden commit yet gets no blank
# living doc (AicDocsWait).
# The registry's mode, else private, when the project sits in a code root. '' when it does not:
# there is no plan to conform to.
function Get-ExpectedMode([string]$Target) {
  if (-not (Get-CodeRoot $Target)) { return '' }
  $mode = Get-RegistryMode $Target
  if (-not $mode) { return 'private' }
  return $mode
}

# True when there is no plan, the mode is team, or it matches the plan and the code repo no
# longer tracks what that mode's switch untracks (Test-TracksLayer).
function Test-Conforms([string]$Target) {
  $expected = Get-ExpectedMode $Target
  if (-not $expected) { return $true }
  $actual = Get-ProjectMode $Target
  if ($actual -eq 'team') { return $true }
  if ($actual -ne $expected) { return $false }
  return (-not (Test-TracksLayer $Target $actual))
}

# True when the code repo still tracks a path the mode's switch untracks: layers B and C
# (config.local/ at any depth) when private, the pointer files when shared. A mode read from the
# registry alone says nothing about the index. One git call.
function Test-TracksLayer([string]$Target, [string]$Mode) {
  $specs = @()
  if ($Mode -eq 'private') { $specs = @(Get-LayerPaths) + @(':(glob)**/config.local/**') }
  elseif ($Mode -eq 'shared') { $specs = @($PointerMap | ForEach-Object { ($_ -split '\|', 2)[1] }) }
  if ($specs.Count -eq 0) { return $false }
  return (@(Invoke-Git (@('-C', $Target, 'ls-files', '--') + $specs)).Count -gt 0)
}

function Test-SamePath([string]$A, [string]$B) {
  if (-not $A -or -not $B) { return $false }
  try {
    $pa = [IO.Path]::GetFullPath($A).TrimEnd('\', '/')
    $pb = [IO.Path]::GetFullPath($B).TrimEnd('\', '/')
  } catch { return $false }
  return ($pa -eq $pb)
}

# Git repos that are direct children; dot-directories left out. Always an array.
function Get-ConformRepos([string]$Root) {
  if (-not $Root -or -not (Test-Path -LiteralPath $Root -PathType Container)) { return @() }
  $repos = @()
  foreach ($d in @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue)) {
    if ($d.Name.StartsWith('.')) { continue }
    if (Test-Path -LiteralPath (Join-Path $d.FullName '.git')) { $repos += $d.FullName }
  }
  return @($repos | Sort-Object)
}

# One ai-sync: line when a code-root project misses the plan. Quiet too: a session start is how
# the owner hears it. No line outside a code root.
function Write-ConformLine([string]$Target) {
  if (Test-Conforms $Target) { return }
  $expected = Get-ExpectedMode $Target
  if (-not $expected) { return }
  # The right mode with layer files still tracked: the sync's own "still tracks" line says it.
  if ((Get-ProjectMode $Target) -eq $expected) { return }
  $top = Get-GitTop $Target
  if (-not $top) { return }
  $name = Split-Path -Leaf $top
  if ($expected -eq 'tracked') {
    Write-Host "ai-sync: $name is not on the private-layer plan — registry says tracked"
    return
  }
  $eng = [IO.Path]::GetFullPath((Join-Path $TemplateDir 'sync-ai-templates.ps1'))
  $flag = if ($expected -eq 'shared') { '--shared' } else { '--private-layer' }
  Write-Host "ai-sync: $name is not on the private-layer plan — switch: $eng $top $flag --commit"
}

# The line this template repo prints instead of its own: the names in its code root, and only a
# count for each sibling root.
function Write-ConformReport([string]$Target) {
  $root = Get-CodeRoot $Target
  if (-not $root) { return }
  $names = @()
  foreach ($d in @(Get-ConformRepos $root)) {
    if (-not (Test-Conforms $d)) { $names += (Split-Path -Leaf $d) }
  }
  $sibs = @()
  $parent = Split-Path -Parent $root
  if ($parent) {
    foreach ($d in @(Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
      if ($d.Name.StartsWith('.')) { continue }
      if (Test-SamePath $d.FullName $root) { continue }
      $mark = (Test-Path -LiteralPath (Join-Path $d.FullName '.ai-root') -PathType Container) -or
              (Test-Path -LiteralPath (Join-Path $d.FullName '.ai-context-remote'))
      if (-not $mark) { continue }
      $count = 0
      foreach ($repo in @(Get-ConformRepos $d.FullName)) {
        if (-not (Test-Conforms $repo)) { $count++ }
      }
      if ($count -gt 0) { $sibs += "$($d.Name): $count" }
    }
  }
  if ($names.Count -eq 0 -and $sibs.Count -eq 0) { return }
  $nameText = $names -join ', '
  $sibText = $sibs -join ', '
  if ($nameText -and $sibText) { Write-Host "ai-sync: not on the private-layer plan: $nameText ($sibText)" }
  elseif ($nameText) { Write-Host "ai-sync: not on the private-layer plan: $nameText" }
  else { Write-Host "ai-sync: not on the private-layer plan: $sibText" }
}

# What the global SessionStart hook (--global-hook) does here: 'run' (the project hook's full
# sync), 'suggest' (one conformance line) or ''. '' outside git, in this template repo, outside a
# code root (the project's parent holds .ai-root\ or .ai-context-remote) and when the project's
# .claude\settings.json already carries the sync hook (that hook runs instead: nothing runs
# twice). 'run' when the registry knows the project, or its exclude block or legacy markers name a
# mode; 'suggest' otherwise. No network.
function Get-GlobalHookPlan([string]$Target) {
  $top = Get-GitTop $Target
  if (-not $top) { return '' }
  if ((Test-Path -LiteralPath (Join-Path $top 'sync-ai-templates.sh') -PathType Leaf) -and
      (Test-Path -LiteralPath (Join-Path $top 'templates-manifest.txt') -PathType Leaf)) { return '' }
  if (Test-SamePath $top $TemplateDir) { return '' }
  if (-not (Get-CodeRoot $top)) { return '' }
  $settings = Join-Path $top '.claude/settings.json'
  if (Test-Path -LiteralPath $settings -PathType Leaf) {
    try { if ([IO.File]::ReadAllText($settings).Contains('sync-ai-templates.sh')) { return '' } } catch { }
  }
  if ((Get-RegistryMode $top) -or ((Get-ProjectMode $top) -ne 'tracked')) { return 'run' }
  return 'suggest'
}

function Sync-AiTemplates {
  param(
    [Parameter(Mandatory = $true)][string]$Target,
    [switch]$DryRun,
    [switch]$Commit,
    [switch]$Quiet,
    [switch]$Push,
    [switch]$Shared,
    [switch]$PrivateLayer,
    [switch]$PrivateDocs              # alias of -PrivateLayer (its former name)
  )
  if ($PrivateDocs) { $PrivateLayer = [switch]$true }
  if ($Quiet) { $script:SyncQuiet = $true }
  $script:SyncChanged = @()
  $script:SyncBootstrapped = $false
  $script:SyncCommitted = $false
  $script:SyncPushed = $false
  $script:SyncUntracked = @()
  $script:SyncSwitchMsg = ''
  $script:SyncHooks = @()
  $script:SyncExclude = $false
  $script:SyncSwitchWaits = $false
  $createdLiving = $false

  if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $Target | Out-Null }
  Set-OverlayFor $Target

  # Canonicalize so "." or trailing-slash targets still yield the real folder name (and so the
  # .NET file APIs below get absolute paths).
  $projectName = Split-Path -Leaf $Target
  if (Test-Path -LiteralPath $Target) {
    $Target = (Resolve-Path -LiteralPath $Target).Path
    $projectName = Split-Path -Leaf $Target
  }
  $projectNameReplacement = $projectName -replace '\$', '$$$$'

  # The project's mode (see Get-ProjectMode). -PrivateLayer switches a tracked or shared project
  # (or a legacy private-docs one, which has no block yet) to private - or to team when
  # Test-TeamRepo finds an author outside the owner's emails; a private or team project keeps
  # its mode (so does a registry entry). -Shared switches a tracked one to shared.
  $gitignore = Join-Path $Target '.gitignore'
  $mode = Get-ProjectMode $Target
  $switching = $false
  $blockMode = ''
  $commonDir = Get-GitCommonDir $Target
  if ($commonDir) { $blockMode = Get-ExcludeBlockMode (Join-Path (Join-Path $commonDir 'info') 'exclude') }
  if (-not $blockMode) { $blockMode = '' }
  if ($PrivateLayer) {
    $switching = $true
    if ($mode -eq 'tracked' -or $mode -eq 'shared' -or
        ($mode -eq 'private' -and -not $blockMode -and (Test-HasLine $gitignore @($PrivateDocsMark)))) {
      $mode = 'private'
      if (Test-TeamRepo $Target) {
        $mode = 'team'
        Write-Sync '  [mode] team (authors outside owner-emails)'
      }
    }
  }
  elseif ($Shared -and $mode -eq 'tracked') { $mode = 'shared' }
  if ($Shared -and $mode -eq 'shared') { $switching = $true }

  # Paths of the private layer (B and C) the code repo still tracks. -PrivateLayer untracks them
  # (files stay on disk) in the same commit as the .gitignore cleanup below; a plain run says how
  # to finish the switch. Team mode never untracks: the team's tracked files are its own
  # ($teamTracked, see Get-TeamTracked) and only the legacy .gitignore cleanup is committed.
  $tracked = @()
  $teamTracked = @()
  Invoke-Git @('-C', $Target, 'rev-parse', '--is-inside-work-tree') | Out-Null
  $isRepo = ($script:GitExit -eq 0)
  $blocked = $false                 # the switch is refused: the index holds someone's work
  if ($mode -eq 'private' -and $isRepo) {
    $tracked = @(Get-TrackedLayerPaths $Target)
    if ($tracked.Count -gt 0 -and $switching) {
      Invoke-Git @('-C', $Target, 'diff', '--cached', '--quiet') | Out-Null
      if ($script:GitExit -ne 0) {
        $blocked = $true
        Write-Host "ai-sync: $projectName has staged changes — commit or unstage them, then re-run --private-layer"
      }
    }
  }
  if ($mode -eq 'team' -and $isRepo) {
    $teamTracked = @(Get-TeamTracked $Target)
    if ($switching -and (Test-HasLine $gitignore @($SharedSentinel, $PrivateDocsMark))) {
      Invoke-Git @('-C', $Target, 'diff', '--cached', '--quiet') | Out-Null
      if ($script:GitExit -ne 0) {
        $blocked = $true
        Write-Host "ai-sync: $projectName has staged changes — commit or unstage them, then re-run --private-layer"
      }
    }
  }

  # Switch order: a switch still to apply (the block does not name the new mode yet, legacy
  # .gitignore markers are left, or a private project still tracks layers B/C) runs the hidden
  # repo's round trip first (Sync-AiContext -Switching, -Team for a team repo), and touches the
  # code repo only once the remote's branch is the hidden HEAD (or no remote is set). Otherwise:
  # one line, and nothing here changes. Never on -DryRun (no network).
  $pending = $false
  $docsWait = $false
  if ($PrivateLayer -and -not $DryRun -and $isRepo -and -not $blocked) {
    if ($switching -and ($tracked.Count -gt 0 -or $blockMode -cne $mode -or
        (Test-HasLine $gitignore @($SharedSentinel, $PrivateDocsMark)))) {
      $pending = $true
    }
    if ($pending) {
      Sync-AiContext -Target $Target -Switching -Team:($mode -eq 'team')
      if (-not $script:AicSwitchReady) {
        $remoteName = if ($script:AicRemote) { $script:AicRemote } else { 'the remote' }
        Write-Host "ai-sync: ${projectName}: the private-layer switch waits — $remoteName does not have the hidden branch yet; nothing changed in the code repo, re-run --private-layer --commit"
        $script:SyncSwitchWaits = $true
        return
      }
      foreach ($note in $script:AicNotes) { Write-Host $note }
    } else {
      Sync-AiContext -Target $Target
    }
    # Once per switch (never at a session start, which has no -PrivateLayer).
    if ($mode -eq 'team') {
      Write-Host "ai-sync: $projectName is a team repo (authors outside owner-emails) — its tracked files stay as they are; only untracked personal files are excluded"
    }
  }
  # No blank docs: a private project whose hidden repo has no commit yet, with a remote that did
  # not answer this run, waits for the remote's copies instead (.env.example is still created).
  if ($mode -eq 'private' -and $script:AicDocsWait -and $script:AicTree -eq (Get-GitTop $Target)) {
    $docsWait = $true
  }

  # Pointers are rendered (base or overlay file, plus any .append fragment) into one scratch
  # file, compared, then copied - so the project only ever sees the composed result. The scratch
  # lives until after the obsolete pass (its guard is rendered too) and is removed in `finally`.
  # Team mode: a pointer, living doc or obsolete file the repo tracks is the team's, never
  # written or removed; no .env.example either (it would be a new file in the team's repo).
  $rendered = [IO.Path]::GetTempFileName()
  try {
  foreach ($entry in $PointerMap) {
    $srcRel, $destRel = $entry -split '\|', 2
    if ($mode -eq 'team' -and (Test-TeamHas $destRel $teamTracked)) { continue }
    $src = Get-TemplatePath $srcRel
    $dest = Join-Path $Target $destRel
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { Write-Warning "template $src missing - skipped $destRel"; continue }
    [IO.File]::WriteAllBytes($rendered, (Get-RenderedBytes $srcRel))
    $action = $null
    if (Test-SymLink $dest) { $action = 'migrate' }             # symlink (any layout) -> owned copy
    elseif (-not (Test-Path -LiteralPath $dest)) { $action = 'create' }
    elseif (Test-SameFile $rendered $dest) { continue }
    else { $action = 'update' }
    Write-Sync "  [$action] $destRel"
    $script:SyncChanged += $destRel
    if ($DryRun) { continue }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    Remove-PathSafely $dest                                      # never copy *through* a symlink
    Copy-Item -LiteralPath $rendered -Destination $dest -Force
  }

  foreach ($entry in $LivingDocsMap) {
    $srcRel, $destRel = $entry -split '\|', 2
    if ($mode -eq 'team' -and ($destRel -ceq '.env.example' -or (Test-TeamHas $destRel $teamTracked))) { continue }
    $src = Get-TemplatePath $srcRel
    $dest = Join-Path $Target $destRel
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { Write-Warning "template $src missing - skipped $destRel"; continue }
    $action = $null
    if (Test-SymLink $dest) { $action = 'migrate' }             # pre-2026 pointer symlink -> owned copy
    elseif (Test-Path -LiteralPath $dest) { continue }          # owned by the project - never overwritten
    elseif ($docsWait -and $destRel -ne '.env.example') { continue }   # the remote's copy comes first (see $docsWait above)
    else { $action = 'create' }
    Write-Sync "  [$action] $destRel"
    $script:SyncChanged += $destRel
    $createdLiving = $true
    if ($DryRun) { continue }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    Remove-PathSafely $dest
    $content = Get-RenderedTemplate $srcRel
    [IO.File]::WriteAllText($dest, ($content -replace '\[PROJECT_NAME\]', $projectNameReplacement))
  }

  # The guard is the reference template as the project received it - rendered, fragment
  # included - otherwise a file that once carried a .append fragment reads as "customized".
  foreach ($entry in $ObsoleteMap) {
    $parts = $entry -split '\|', 2
    $rel = $parts[0]
    $guard = $null
    if ($parts.Count -gt 1 -and (Test-Path -LiteralPath (Get-TemplatePath $parts[1]) -PathType Leaf)) {
      [IO.File]::WriteAllBytes($rendered, (Get-RenderedBytes $parts[1]))
      $guard = $rendered
    }
    $dest = Join-Path $Target $rel
    if ($mode -eq 'team' -and ((Test-SymLink $dest) -or (Test-Path -LiteralPath $dest)) -and
        @(Invoke-Git @('-C', $Target, 'ls-files', '--', $rel) | Where-Object { $_ }).Count -gt 0) { continue }
    if (-not (Test-SymLink $dest)) {
      if (-not (Test-Path -LiteralPath $dest)) { continue }
      if ($guard -and -not (Test-SameFile $guard $dest)) {
        Write-Sync "  [keep]   $rel (obsolete but customized - remove by hand if unwanted)"
        continue
      }
    }
    Write-Sync "  [remove] $rel (obsolete)"
    $script:SyncChanged += $rel
    if ($DryRun) { continue }
    Remove-PathSafely $dest
  }
  } finally { Remove-Item -LiteralPath $rendered -Force -ErrorAction SilentlyContinue }

  # Private layer: layers B and C are hidden from the code repo by the managed block in
  # .git/info/exclude - written before the untrack below, so the switch commit cannot re-add them;
  # never by a refused switch. A team repo's block lists only what the team does not track.
  if (($mode -eq 'private' -or $mode -eq 'team') -and -not ($switching -and $blocked)) { Sync-ExcludeBlock -Target $Target -Mode $mode -DryRun ([bool]$DryRun) }

  # Machine-local files must never travel between machines: secrets in .env, and per-machine
  # Claude Code permissions (absolute paths, drive letters) in .claude/settings.local.json.
  # A shared project also keeps every pointer file out of git, listed under the sentinel line.
  # A private one lists nothing more here: its layers are in .git/info/exclude. A team repo's
  # .gitignore is the team's: never a line added (its block covers these three).
  $exists = Test-Path -LiteralPath $gitignore -PathType Leaf
  $content = ''
  if ($exists) {
    $content = Get-Content -LiteralPath $gitignore -Raw
    if ($null -eq $content) { $content = '' }
  }
  $missing = @()
  $wanted = @('.env', '.claude/settings.local.json', 'CLAUDE.local.md')
  if ($mode -eq 'team') { $wanted = @() }
  if ($mode -eq 'shared') { $wanted += $SharedSentinel; $wanted += @($PointerMap | ForEach-Object { ($_ -split '\|', 2)[1] }) }
  # Legacy migration (-PrivateLayer only, private or team): drop the markers --shared /
  # --private-docs wrote, with the paths listed under them - nothing else (every user line and
  # the three lines above stay). Written back with LF line ends, the user's own CRs kept.
  $removed = 0
  if ($switching -and ($mode -eq 'private' -or $mode -eq 'team') -and -not $blocked -and (Test-HasLine $gitignore @($SharedSentinel, $PrivateDocsMark))) {
    $legacy = @(Get-LegacyGitignoreLines)
    $lines = @([IO.File]::ReadAllText($gitignore) -split "`n")
    if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') { $lines = @($lines | Select-Object -First ($lines.Count - 1)) }
    $kept = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in $lines) {
      $key = ($line -replace "`r$", '').TrimEnd()   # trailing blanks do not make a user line
      if ($legacy -ccontains $key) { $removed++; continue }
      $kept.Add($line)
    }
    if ($removed -gt 0) {
      Write-Sync "  [modify] .gitignore (remove $removed legacy line(s))"
      $script:SyncChanged += '.gitignore'
      $script:SyncSwitchMsg = $PrivateLayerMsg
      if (-not $DryRun) {
        $content = if ($kept.Count -gt 0) { ($kept -join "`n") + "`n" } else { '' }
        [IO.File]::WriteAllText($gitignore, $content)
      }
    }
  }
  foreach ($entry in $wanted) {
    if ($content -notmatch ('(?m)^' + [regex]::Escape($entry) + '\s*$')) { $missing += $entry }
  }
  if ($missing.Count -gt 0) {
    if ($exists) { Write-Sync "  [modify] .gitignore (add $($missing.Count) line(s))" }
    else { Write-Sync "  [create] .gitignore" }
    if ($removed -eq 0) { $script:SyncChanged += '.gitignore' }
    if (-not $DryRun) {
      if ($content.Length -gt 0 -and -not $content.EndsWith("`n")) { $content += "`n" }
      [IO.File]::WriteAllText($gitignore, $content + (($missing | ForEach-Object { "$_`n" }) -join ''))
    }
  }

  if ($mode -eq 'private' -and $tracked.Count -gt 0 -and -not $blocked) {
    if (-not $switching) {
      # Layer B among them: the hidden repo synced nothing (Sync-AiContext) - one line for both.
      if (@(Get-TrackedPrivateDocs $Target).Count -gt 0) {
        Write-OldBranchLine $projectName ($tracked -join ' ')
      } else {
        Write-Host "ai-sync: $projectName is on the private layer but git still tracks $($tracked -join ' ') — run sync-ai-templates.ps1 <project> --private-layer --commit"
      }
    } else {
      # The hidden repo's round trip ran first (see Switch order above): untracking is safe now.
      Write-Sync "  [untrack] $($tracked -join ' ') (private layer from now on)"
      if (-not $DryRun) {
        Invoke-Git (@('-C', $Target, 'rm', '-r', '-q', '--cached', '--') + $tracked) | Out-Null
        $script:SyncUntracked = $tracked
        $script:SyncChanged += $tracked
        $script:SyncSwitchMsg = $PrivateLayerMsg
      }
    }
  }

  # Pointer files a shared project still tracks: -Shared untracks them (files stay on disk), a
  # plain run says how to finish the switch.
  if ($mode -eq 'shared' -and $isRepo) {
    $tracked = @()
    foreach ($rel in @($PointerMap | ForEach-Object { ($_ -split '\|', 2)[1] })) {
      $hit = @(Invoke-Git @('-C', $Target, 'ls-files', '--', $rel) | Where-Object { $_ })
      if ($script:GitExit -eq 0 -and $hit.Count -gt 0) { $tracked += $rel }
    }
    if ($tracked.Count -gt 0) {
      if (-not $switching) {
        Write-Host "ai-sync: $projectName is shared but git still tracks $($tracked -join ' ') — run sync-ai-templates.ps1 <project> --shared --commit"
      } else {
        Invoke-Git @('-C', $Target, 'diff', '--cached', '--quiet') | Out-Null
        if ($script:GitExit -ne 0) {
          $blocked = $true
          Write-Host "ai-sync: $projectName has staged changes — commit or unstage them, then re-run --shared"
        } else {
          Write-Sync "  [untrack] $($tracked -join ' ') (local-only from now on)"
          if (-not $DryRun) {
            Invoke-Git (@('-C', $Target, 'rm', '-r', '-q', '--cached', '--') + $tracked) | Out-Null
            $script:SyncUntracked = $tracked
            $script:SyncChanged += $tracked
          }
        }
      }
    }
  }

  if ($createdLiving) { $script:SyncBootstrapped = $true }
  if (-not $DryRun -and $Commit) {
    Invoke-SyncCommit -Target $Target
    if ($script:SyncCommitted -and $Push) { Invoke-SyncPush -Target $Target }
  }
  # A switch that applied goes into the code root's registry (.ai-root/projects/<name>), so a
  # fresh clone on another machine starts in the same mode: -PrivateLayer records private or
  # team, -Shared records shared.
  if (-not $DryRun -and -not $blocked) {
    if ($PrivateLayer) { Set-RegistryMode $Target $mode }
    elseif ($Shared -and $mode -eq 'shared') { Set-RegistryMode $Target 'shared' }
  }
  # After the commit: the switch commit is not held up by the new guard. Every mode but tracked
  # gets the private-terms guard.
  Sync-SharedHooks -Target $Target -Guard ($mode -ne 'tracked') -DryRun ([bool]$DryRun)
  if ($script:SyncQuiet -and ($script:SyncChanged.Count -gt 0 -or $script:SyncExclude)) {
    $note = if ($script:SyncPushed) { ' (committed, pushed)' } elseif ($script:SyncCommitted) { ' (committed)' } else { '' }
    $shown = @($script:SyncChanged)
    if ($script:SyncExclude) { $shown += '.git/info/exclude' }
    Write-Host "ai-sync: refreshed $($shown -join ' ') from $SourceLabel$note"
  }
  if ($script:SyncQuiet -and $script:SyncHooks.Count -gt 0) {
    Write-Host "ai-sync: git hook $($script:SyncHooks -join ' ') (private-terms guard, .git/hooks)"
  }
  if (Test-Path -LiteralPath $Target -PathType Container) { Test-ContextBudget -Target $Target }
  try { Apply-DevContext -Target $Target -DryRun ([bool]$DryRun) } catch { Write-Host "ai-sync: dev-context: $($_.Exception.Message)" }
  try { Invoke-FactoryApply $Target ([bool]$DryRun) } catch { Write-Host "ai-sync: factory: $($_.Exception.Message)" }
  # After the run, so a registry mode this sync just applied is what gets judged. A switch is
  # the fix already; saying "switch" in the same breath would only repeat the command.
  if (-not $switching) {
    if (Test-SamePath $Target $TemplateDir) { Write-ConformReport $Target }
    else { Write-ConformLine $Target }
  }
}

# Refresh this template repo (and the overlay, when there is one) from origin before syncing,
# so every session starts from the latest templates. Fast-forward only, on a branch (a detached
# HEAD is a pinned release) with a clean tree (never fights local edits), and bounded so an
# offline machine still starts at once. Sets $script:PullUpdated when a repo moved.
$script:PullUpdated = $false
function Update-TemplateRepo {
  Update-OneRepo $TemplateDir $TemplateName
  if ($OverlayDir) { Update-OneRepo $OverlayDir $OverlayName }
}

# The per-repo half of Update-TemplateRepo (the overlay gets the same treatment), through
# Invoke-Bounded (the run's network budget). Past the limit the pull is left to finish on its own
# and the next run sees the result.
function Update-OneRepo([string]$Dir, [string]$Name) {
  $gitDir = (Invoke-Git @('-C', $Dir, 'rev-parse', '--absolute-git-dir')) | Select-Object -First 1
  if ($script:GitExit -ne 0 -or -not $gitDir) { return }
  Invoke-Git @('-C', $Dir, 'remote', 'get-url', 'origin') | Out-Null
  if ($script:GitExit -ne 0 -or -not (Invoke-Git @('-C', $Dir, 'symbolic-ref', '-q', 'HEAD'))) { return }
  $dirty = @(Invoke-Git @('-C', $Dir, 'status', '--porcelain') | Where-Object { $_ })
  if ($dirty.Count -gt 0) { Write-Host "ai-sync: $Name has uncommitted changes - pull skipped, using the templates on disk"; return }
  $before = (Invoke-Git @('-C', $Dir, 'rev-parse', 'HEAD')) | Select-Object -First 1
  $out = [IO.Path]::GetTempFileName()
  try { $rc = Invoke-Bounded $out @('-C', $Dir, 'pull', '-q', '--ff-only') }
  finally { Remove-Item -LiteralPath $out, "$out.err" -Force -ErrorAction SilentlyContinue }
  if ($rc -eq 124 -and $script:NetSkipped) {
    Write-Host "ai-sync: $Name pull skipped (no network time left in this run) — using the templates on disk"
    return
  }
  if ($rc -eq 124) {
    Write-Host "ai-sync: $Name pull still running after $($script:NetLimit)s - using the templates on disk"
    return
  }
  if ($rc -ne 0) {
    Write-Host "ai-sync: $Name pull failed (offline, or diverged from origin) - using the templates on disk"
    return
  }
  $after = (Invoke-Git @('-C', $Dir, 'rev-parse', 'HEAD')) | Select-Object -First 1
  if ($before -ne $after) {
    $script:PullUpdated = $true
    Write-Sync "ai-sync: pulled latest $Name from origin"
  }
}

# The --agents pass: run refresh-agents-sections.py on one project. Its own guards decide what
# is safe (customized sections, shared projects, uncommitted AGENTS.md, merges; a private or team
# project's AGENTS.md is never committed to the code repo). No interpreter
# -> silent no-op; a failure is one line, never an error.
function Update-AgentsMd([string]$Target, [switch]$DryRun, [switch]$Commit) {
  $refresher = Join-Path $TemplateDir 'skills/bootstrap-ai/scripts/refresh-agents-sections.py'
  $agents = Join-Path $Target 'AGENTS.md'
  if (-not (Test-Path -LiteralPath $refresher -PathType Leaf) -or -not (Test-Path -LiteralPath $agents -PathType Leaf)) { return }
  if ((Get-Item -LiteralPath $agents -Force).LinkType) { return }
  $py = @()
  if (Get-Command uv -CommandType Application -ErrorAction SilentlyContinue) { $py = @('uv', 'run', '--quiet', '--no-project') }
  else {
    foreach ($c in 'python3', 'python') {
      if (-not (Get-Command $c -CommandType Application -ErrorAction SilentlyContinue)) { continue }
      try { & $c -c 'import sys' 2>$null | Out-Null } catch { continue }
      if ($LASTEXITCODE -eq 0) { $py = @($c); break }
    }
  }
  if ($py.Count -eq 0) { return }
  $a = @()
  if ($py.Count -gt 1) { $a += $py[1..($py.Count - 1)] }
  $a += @($refresher, $Target)
  if ($script:SyncQuiet) { $a += '--quiet' }
  if ($DryRun) { $a += '--dry-run' }
  if ($Commit) { $a += '--commit' }
  $ok = $true
  try {
    & $py[0] @a 2>$null | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { $ok = $false }
  } catch { $ok = $false }
  if (-not $ok) { Write-Host "ai-sync: AGENTS.md refresh failed - run refresh-agents-sections.py $Target by hand" }
}

# Network budget: every network step of a run (the template and .ai-root pulls, the .ai-root
# push, the hidden repo's ls-remote, fetch and push) shares $env:AI_SYNC_NET_BUDGET seconds of
# waiting (default 30); each one waits at most $env:AI_SYNC_PULL_WAIT seconds (default 10), or
# what is left. The local work between them (over 30 s on a slow Windows run) does not count.
# After the first step that timed out (not one that failed at once), the remaining ones are
# skipped. The seconds left and the down flag live in the environment, so the --pull re-run keeps them.
$script:NetLimit = 10           # the wait of the last Invoke-Bounded call, in seconds (for its messages)
$script:NetSkipped = $false     # true when the last Invoke-Bounded call ran nothing (no network time left)

# Start a new budget: a run with --pull, each project of update-projects. Otherwise the first
# network step starts one (or keeps the one a re-run inherited).
function Reset-NetBudget {
  $budget = [long]30
  if ("$env:AI_SYNC_NET_BUDGET" -match '^[0-9]+$') {
    $parsed = [long]0
    if ([long]::TryParse($env:AI_SYNC_NET_BUDGET, [ref]$parsed)) { $budget = $parsed }
  }
  $env:AI_SYNC_NET_LEFT = [string]$budget
  $env:AI_SYNC_NET_DOWN = ''
}

# A network git command: 0 done, 1 failed, 124 still running after its wait (left to finish on its
# own; the run's later network steps are skipped) or not run at all ($script:NetSkipped: no
# network time left). Stdout goes to $Out. $script:NetLimit = the wait used.
function Invoke-Bounded([string]$Out, [string[]]$GitArgs) {
  $script:NetSkipped = $false
  $left = [long]0
  if ("$env:AI_SYNC_NET_LEFT" -notmatch '^[0-9]+$' -or -not [long]::TryParse($env:AI_SYNC_NET_LEFT, [ref]$left)) { Reset-NetBudget; $left = [long]$env:AI_SYNC_NET_LEFT }
  $limit = 10
  if ("$env:AI_SYNC_PULL_WAIT" -match '^[0-9]+$') { $limit = [int]$env:AI_SYNC_PULL_WAIT }
  if ($left -lt $limit) { $limit = [int]$left }
  $script:NetLimit = $limit
  if ($env:AI_SYNC_NET_DOWN -or $limit -le 0) {
    $script:NetSkipped = $true
    [IO.File]::WriteAllText($Out, '')
    return 124
  }
  $quoted = @($GitArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } })
  $sp = @{ FilePath = 'git'; ArgumentList = $quoted; RedirectStandardOutput = $Out; RedirectStandardError = "$Out.err"; PassThru = $true }
  if ($OnWindows) { $sp.WindowStyle = 'Hidden' } else { $sp.NoNewWindow = $true }
  $prompt = $env:GIT_TERMINAL_PROMPT
  $env:GIT_TERMINAL_PROMPT = '0'      # never wait on a credential prompt nobody sees
  $clock = [Diagnostics.Stopwatch]::StartNew()
  try { $proc = Start-Process @sp; $null = $proc.Handle }
  catch { return 1 }
  finally { $env:GIT_TERMINAL_PROMPT = $prompt }
  $done = $proc.WaitForExit($limit * 1000)
  $env:AI_SYNC_NET_LEFT = [string][math]::Max([long]0, $left - [long][math]::Round($clock.Elapsed.TotalSeconds))
  if (-not $done) {
    $env:AI_SYNC_NET_DOWN = '1'
    return 124
  }
  if ($proc.ExitCode -ne 0) { return 1 }
  return 0
}

# Locks: the .ai-root checkout's (<its git dir>\ai-sync.lock) and the hidden repo's (<hidden
# repo>\sync.lock). A new folder, so taking one is atomic; one older than SyncLockStaleMin
# minutes = a crashed run, taken over. Nobody waits: a held lock is a skip.
$script:SyncLockStaleMin = 5

# Take the lock: $true taken, $false held by another run.
function Enter-SyncLock([string]$Lock) {
  try { New-Item -ItemType Directory -Path $Lock -ErrorAction Stop | Out-Null; return $true } catch { }
  $item = Get-Item -LiteralPath $Lock -Force -ErrorAction SilentlyContinue
  if ($null -ne $item -and $item.LastWriteTime -ge (Get-Date).AddMinutes(-$script:SyncLockStaleMin)) { return $false }
  Remove-Item -LiteralPath $Lock -Recurse -Force -ErrorAction SilentlyContinue
  try { New-Item -ItemType Directory -Path $Lock -ErrorAction Stop | Out-Null; return $true } catch { return $false }
}

function Exit-SyncLock([string]$Lock) {
  Remove-Item -LiteralPath $Lock -Recurse -Force -ErrorAction SilentlyContinue
}

# Private layer B (--private-layer, see the header). The hidden repo is <git-common-dir>/ai-context
# driven with --git-dir/--work-tree, so the files stay where every tool expects them while the
# code repo ignores them. Active in private and team mode. Nothing here may fail a session:
# every problem is one line. Its paths: Get-PrivateDocPaths.
$script:AicGit = ''
$script:AicTree = ''
$script:AicBranch = ''
$script:AicMode = ''
$script:AicCommitted = ''
$script:AicRemote = ''          # the remote of the last round trip ('' : none set)
$script:AicRemoteState = ''     # what it said: none (no remote) | absent (no hidden branch yet) |
                                # present | unreachable (no answer: offline, timeout, no network
                                # time, fetch failed, lock held); '' when the round trip did not ask
$script:AicDocsWait = $false    # private, no hidden commit yet, the remote did not answer:
                                # Sync-AiTemplates creates no blank living doc
$script:AicOldBranch = ''       # the layer paths the code repo still tracks, when that skipped the round trip
$script:AicSwitching = $false   # the round trip runs for a --private-layer switch (Sync-AiContext -Switching)
$script:AicSwitchReady = $false # -Switching: the remote holds the hidden HEAD (or no remote is set)
$script:AicNotes = @()          # -Switching: success lines, printed by the caller once the switch applies
$script:AicCfgFiles = @()       # Set-AicConfigFiles: config.local/ files to version
$script:AicSkipped = @()        # Set-AicConfigFiles: config.local/ files never versioned
$script:AicWork = $false        # Set-AiContextRemote: the project lives under a work root
$script:AicSaid = @()           # the remote-rule lines this run already printed (Write-AicSayOnce)

# Print a line at most once per run (a run may sync the hidden repo twice).
function Write-AicSayOnce([string]$Line) {
  if ($script:AicSaid -ccontains $Line) { return }
  $script:AicSaid += $Line
  Write-Host $Line
}

# True when the file exists and is not empty.
function Test-NonEmptyFile([string]$Path) {
  if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  return ((Get-Item -Force -LiteralPath $Path).Length -gt 0)
}

# Set $script:AicRemote to the owner's private remote, or '' (the hidden repo stays local). Root =
# Get-AncestorRoot (the nearest folder above the project holding .ai-root\ or .ai-context-remote).
# Outside a work root: $env:AI_CONTEXT_REMOTE (none or empty = local only), else the first line of
# <root>/.ai-context-remote, else of ~/.ai-context-remote. Under a work root (Test-WorkPath of the
# top level), whose docs must never land on a personal remote: only
# <root>/.ai-context-remote - $env:AI_CONTEXT_REMOTE can only disable it (none or empty; any other
# value is ignored with one line), ~/.ai-context-remote is never read, and a github.com URL is
# refused with one line (Write-AicSayOnce: once per run). Sets $script:AicWork.
function Set-AiContextRemote {
  $script:AicRemote = ''
  $script:AicWork = (Test-WorkPath $script:AicTree)
  $root = Get-AncestorRoot $script:AicTree
  $r = ''
  $f = ''
  if ($script:AicWork) {
    if ($root -and (Test-NonEmptyFile (Join-Path $root '.ai-context-remote'))) { $f = Join-Path $root '.ai-context-remote' }
    if ($null -ne $env:AI_CONTEXT_REMOTE) {
      if ($env:AI_CONTEXT_REMOTE -eq '' -or $env:AI_CONTEXT_REMOTE -ceq 'none') { return }
      $tail = if ($f) { "using $f" } else { 'kept local' }
      Write-AicSayOnce "ai-sync: private AI docs: AI_CONTEXT_REMOTE is ignored under a work root (only none disables the remote) — $tail"
    }
  } elseif ($null -ne $env:AI_CONTEXT_REMOTE) {
    $r = $env:AI_CONTEXT_REMOTE
  } elseif ($root -and (Test-NonEmptyFile (Join-Path $root '.ai-context-remote'))) {
    $f = Join-Path $root '.ai-context-remote'
  } elseif (Test-NonEmptyFile (Join-Path $HOME '.ai-context-remote')) {
    $f = Join-Path $HOME '.ai-context-remote'
  }
  if ($f) {
    $first = Get-Content -LiteralPath $f -TotalCount 1
    if ($null -ne $first) { $r = ([string]$first).Trim() }
  }
  if (-not $r -or $r -ceq 'none') { return }
  if ($script:AicWork -and $r.ToLowerInvariant().Contains('github.com')) {
    Write-AicSayOnce "ai-sync: private AI docs: $r is a github.com remote — refused under a work root, kept local"
    return
  }
  $script:AicRemote = $r
}

function Invoke-Aic([string[]]$GitArgs) {
  Invoke-Git (@('-C', $script:AicTree, "--git-dir=$($script:AicGit)", "--work-tree=$($script:AicTree)") + $GitArgs)
}

# True when the hidden repo has a commit.
function Test-AicHead {
  Invoke-Aic @('rev-parse', '-q', '--verify', 'HEAD') | Out-Null
  return ($script:GitExit -eq 0)
}

# True when the path exists, or is a symlink (even a dangling one).
function Test-PathOrLink([string]$Path) {
  if (Test-Path -LiteralPath $Path) { return $true }
  return ($null -ne (Get-Item -LiteralPath $Path.TrimEnd('/', '\') -Force -ErrorAction SilentlyContinue))
}

# AicTree (the work tree's top level), AicGit (<git-common-dir>/ai-context) and AicBranch
# (<root folder>/<project>, sanitized; spelled as the root repo's branches and the registry spell
# them, Get-RootSpelling / Get-RegistryName). $false outside a git work tree.
function Set-AicPaths([string]$Target) {
  if (-not (Test-Path -LiteralPath $Target -PathType Container)) { return $false }
  $top = (Invoke-Git @('-C', $Target, 'rev-parse', '--show-toplevel')) | Select-Object -First 1
  if ($script:GitExit -ne 0 -or -not $top) { return $false }
  $script:AicTree = [IO.Path]::GetFullPath($top)
  $common = (Invoke-Git @('-C', $script:AicTree, 'rev-parse', '--git-common-dir')) | Select-Object -First 1
  if ($script:GitExit -ne 0 -or -not $common) { return $false }
  if (-not [IO.Path]::IsPathRooted($common)) { $common = Join-Path $script:AicTree $common }
  $script:AicGit = Join-Path ([IO.Path]::GetFullPath($common)) 'ai-context'
  $name = Split-Path -Leaf $script:AicTree
  $root = Get-CodeRoot $script:AicTree
  $rootName = Split-Path -Leaf (Split-Path -Parent $script:AicTree)
  if ($root) {
    $reg = Join-Path (Join-Path $root '.ai-root') 'projects'
    if (Test-Path -LiteralPath $reg -PathType Container) { $name = Get-RegistryName $reg $name }
    $rootName = Get-RootSpelling $root
  }
  $script:AicBranch = ($rootName + '/' + $name) -replace '[^A-Za-z0-9._/-]', '-'
  return $true
}

# The layer B paths the code repo's index still tracks (config.local/ at any depth: the first one
# found).
function Get-TrackedPrivateDocs([string]$Dir) {
  foreach ($p in @(Get-PrivateDocPaths)) {
    if ($p -ceq 'config.local/') {
      foreach ($f in @(Invoke-Git @('-C', $Dir, '-c', 'core.quotepath=off', 'ls-files'))) {
        $i = ('/' + $f).IndexOf('/config.local/', [StringComparison]::Ordinal)
        if ($i -ge 0) { $f.Substring(0, $i + 13); break }
      }
    } elseif (@(Invoke-Git @('-C', $Dir, 'ls-files', '--', $p)).Count -gt 0) { $p }
  }
}

# The line of a private project whose code repo still tracks layer B (an old branch checked out,
# or a switch never finished): the hidden repo syncs nothing.
function Write-OldBranchLine([string]$Name, [string]$Paths) {
  Write-Host "ai-sync: $Name is on the private layer but git still tracks $Paths — private AI docs not synced until you run sync-ai-templates.ps1 <project> --private-layer --commit"
}

# A success line: printed, or kept in AicNotes during -Switching (the caller prints them once the
# switch applies).
function Write-AicNote([string]$Line) {
  if ($script:AicSwitching) { $script:AicNotes += $Line } else { Write-Host $Line }
}

# The line of a round trip whose remote did not answer: synced next time; or, in a private
# project with no hidden commit yet and a living doc missing, none is created until the remote
# answers (AicDocsWait). Never printed during -Switching: the caller prints its single "switch
# waits" line.
function Write-AicOfflineLine([string]$What) {
  if ($script:AicSwitching) { return }
  $tail = 'synced next time'
  if ($script:AicMode -eq 'private' -and -not (Test-AicHead)) {
    foreach ($entry in $LivingDocsMap) {
      $rel = ($entry -split '\|', 2)[1]
      if ($rel -eq '.env.example') { continue }
      if (-not (Test-Path -LiteralPath (Join-Path $script:AicTree $rel))) { $tail = 'living docs not created until it answers'; break }
    }
  }
  Write-Host "ai-sync: private AI docs: $What — $tail"
}

# MEMORY.md merges by union in the hidden repo (two machines adding to the same memory index never
# conflict): one LF line in <hidden repo>/info/attributes, never twice.
function Set-AicAttributes {
  $f = Join-Path (Join-Path $script:AicGit 'info') 'attributes'
  if (Test-HasLine $f @('MEMORY.md merge=union')) { return }
  try {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $f) | Out-Null
    $prefix = ''
    if (Test-Path -LiteralPath $f -PathType Leaf) {
      $bytes = [IO.File]::ReadAllBytes($f)
      if ($bytes.Length -gt 0 -and $bytes[$bytes.Length - 1] -ne 10) { $prefix = "`n" }
    }
    [IO.File]::AppendAllText($f, "${prefix}MEMORY.md merge=union`n")
  } catch { }
}

# Make the remote's version the local branch and check its files out. A local file that differs
# from it is saved under <hidden repo>.bak/<timestamp>/ first. Team mode: a file the team repo
# tracks is neither saved nor checked out (the team's copy stays).
function Invoke-AicAdopt([string]$Ref) {
  $bak = "$($script:AicGit).bak/" + (Get-Date -Format 'yyyyMMdd-HHmmss')
  $saved = $false
  $teamTracked = @()
  if ($script:AicMode -eq 'team') { $teamTracked = @(Get-TeamTracked $script:AicTree) }
  $files = @()
  foreach ($f in @(Invoke-Aic @('-c', 'core.quotepath=off', 'ls-tree', '-r', '--name-only', $Ref) | Where-Object { $_ })) {
    if ($teamTracked.Count -gt 0 -and (Test-TeamHas $f $teamTracked)) { continue }
    $files += $f
    $local = Join-Path $script:AicTree $f
    if (-not (Test-Path -LiteralPath $local -PathType Leaf)) { continue }
    Invoke-Aic @('diff', '--quiet', $Ref, '--', $f) | Out-Null
    if ($script:GitExit -eq 0) { continue }
    try {
      $dest = Join-Path $bak $f
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
      Copy-Item -LiteralPath $local -Destination $dest -Force
      $saved = $true
    } catch { }
  }
  Invoke-Aic @('update-ref', "refs/heads/$($script:AicBranch)", $Ref) | Out-Null
  if ($script:GitExit -eq 0) { Invoke-Aic @('reset', '-q') | Out-Null }
  if ($script:GitExit -eq 0 -and $files.Count -gt 0) { Invoke-Aic (@('checkout', '-f', '--') + $files) | Out-Null }
  if ($script:GitExit -ne 0) {
    Write-Host "ai-sync: private AI docs: could not check out $($script:AicBranch) in $($script:AicGit)"
    return
  }
  if ($saved) { Write-Host "ai-sync: private AI docs: local copies that differed are saved in $bak" }
}

# Every config.local/ folder of the work tree at any depth (relative, with a trailing /): the
# ones the code repo tracks and the untracked or ignored ones it lists (never under .git; a wholly
# untracked folder is listed whole, so one inside it is not seen).
function Get-ConfigLocalDirs {
  $seen = New-Object 'System.Collections.Generic.HashSet[string]'
  $all = @(Invoke-Git @('-C', $script:AicTree, '-c', 'core.quotepath=off', 'ls-files')) +
    @(Invoke-Git @('-C', $script:AicTree, '-c', 'core.quotepath=off', 'ls-files', '-o', '--directory'))
  foreach ($f in $all) {
    $i = ('/' + $f).IndexOf('/config.local/', [StringComparison]::Ordinal)
    if ($i -ge 0) {
      $d = $f.Substring(0, $i + 13)
      if ($seen.Add($d)) { $d }
    }
  }
}

# The files of every config.local/ folder, split into AicCfgFiles (versioned) and AicSkipped (never
# staged, even when already tracked): *.db, *.sqlite*, *.log, .env*, *.key, *.pem, anything under
# cache/ or __pycache__/, files over 1 MiB. Both in ordinal (C) order.
function Set-AicConfigFiles {
  $script:AicCfgFiles = @()
  $script:AicSkipped = @()
  $treeLen = $script:AicTree.TrimEnd('\', '/').Length
  foreach ($dir in @(Get-ConfigLocalDirs)) {
    $d = $dir.TrimEnd('/')
    $abs = Join-Path $script:AicTree $d
    if (-not (Test-Path -LiteralPath $abs -PathType Container)) { continue }
    $big = New-Object 'System.Collections.Generic.HashSet[string]'
    $rels = New-Object 'System.Collections.Generic.List[string]'
    foreach ($item in @(Get-ChildItem -LiteralPath $abs -Recurse -Force -ErrorAction SilentlyContinue)) {
      if ($item.PSIsContainer -and -not $item.LinkType) { continue }
      $rel = $item.FullName.Substring($treeLen + 1) -replace '\\', '/'
      $rels.Add($rel)
      if (-not $item.PSIsContainer -and -not $item.LinkType -and $item.Length -gt 1048576) { [void]$big.Add($rel) }
    }
    $sorted = $rels.ToArray()
    [Array]::Sort($sorted, [StringComparer]::Ordinal)
    foreach ($f in $sorted) {
      $inner = '/' + $f.Substring($d.Length + 1)
      $base = $f.Substring($f.LastIndexOf('/') + 1)
      if ($inner -clike '*/cache/*' -or $inner -clike '*/__pycache__/*') { $script:AicSkipped += $f; continue }
      if ($base -clike '*.db' -or $base -clike '*.sqlite*' -or $base -clike '*.log' -or $base -clike '.env*' -or
          $base -clike '*.key' -or $base -clike '*.pem') { $script:AicSkipped += $f; continue }
      if ($big.Contains($f)) { $script:AicSkipped += $f; continue }
      $script:AicCfgFiles += $f
    }
  }
}

# Commit every private doc that changed; sets $script:AicCommitted to the paths. Each path is
# named (add -f: the code repo's exclude block ignores them all): folders whole, config.local/
# file by file (Set-AicConfigFiles; one line whenever the skipped set changes). A living doc the
# hidden HEAD holds but the disk lost is restored, never committed as a deletion; any other path
# the hidden repo tracks and the disk lost is committed as one. Team mode: only the B files the
# team repo does not track - one it tracks is never added, and one the hidden repo already holds
# stays as it is there (reset to the hidden HEAD: never restored, updated or deleted).
function Invoke-AicCommit {
  $teamTracked = @()
  if ($script:AicMode -eq 'team') { $teamTracked = @(Get-TeamTracked $script:AicTree) }
  foreach ($entry in $LivingDocsMap) {
    $p = ($entry -split '\|', 2)[1]
    if ($p -eq '.env.example') { continue }
    if ($teamTracked.Count -gt 0 -and (Test-TeamHas $p $teamTracked)) { continue }
    if (Test-PathOrLink (Join-Path $script:AicTree $p)) { continue }
    if (@(Invoke-Aic @('ls-tree', '--name-only', 'HEAD', '--', $p) | Where-Object { $_ }).Count -eq 0) { continue }
    Invoke-Aic @('checkout', 'HEAD', '--', $p) | Out-Null
    if ($script:GitExit -eq 0) { Write-Host "ai-sync: private AI docs: $p was deleted — restored from the hidden repo" }
  }
  $paths = @(Get-PrivateDocPaths | Where-Object { $_ -cne 'config.local/' -and (Test-PathOrLink (Join-Path $script:AicTree $_)) })
  Set-AicConfigFiles
  $paths += $script:AicCfgFiles
  if ($paths.Count -gt 0) { Invoke-Aic (@('add', '-f', '-A', '--') + $paths) | Out-Null }
  $gone = @()
  $reset = @()
  foreach ($p in @(Invoke-Aic @('-c', 'core.quotepath=off', 'ls-files') | Where-Object { $_ })) {
    if ($teamTracked.Count -gt 0 -and (Test-TeamHas $p $teamTracked)) { $reset += $p; continue }
    if (-not (Test-PathOrLink (Join-Path $script:AicTree $p))) { $gone += $p }
  }
  if ($gone.Count -gt 0) { Invoke-Aic (@('rm', '-q', '--cached', '--ignore-unmatch', '--') + $gone) | Out-Null }
  if ($reset.Count -gt 0) {
    if (Test-AicHead) { Invoke-Aic (@('reset', '-q', 'HEAD', '--') + $reset) | Out-Null }
    else { Invoke-Aic (@('rm', '-q', '--cached', '--ignore-unmatch', '--') + $reset) | Out-Null }
  }
  $list = $script:AicSkipped -join "`n"
  $state = Join-Path $script:AicGit 'ai-sync-skipped'
  $prev = ''
  if (Test-Path -LiteralPath $state -PathType Leaf) { try { $prev = [IO.File]::ReadAllText($state) -replace "`n+$", '' } catch { } }
  if ($list -cne $prev) {
    if ($script:AicSkipped.Count -gt 0) {
      $names = @($script:AicSkipped | Select-Object -First 3) -join ' '
      if ($script:AicSkipped.Count -gt 3) { $names += ' …' }
      Write-Host "ai-sync: private AI docs: $($script:AicSkipped.Count) config.local file(s) not versioned (secrets, databases, logs, caches or over 1 MB): $names"
    }
    try { [IO.File]::WriteAllText($state, $list) } catch { }
  }
  Invoke-Aic @('diff', '--cached', '--quiet') | Out-Null
  if ($script:GitExit -eq 0) { return }
  $names = (@(Invoke-Aic @('diff', '--cached', '--name-only') | Where-Object { $_ }) -join ' ')
  Invoke-Aic @('commit', '-q', '-m', "ai-context: $names") | Out-Null
  if ($script:GitExit -eq 0) { $script:AicCommitted = $names }
  else { Write-Host "ai-sync: private AI docs: commit failed in $($script:AicGit) (git identity?)" }
}

# Memory (private and team only; a tracked project never reaches Sync-AiContext).
# autoMemoryDirectory in .claude/settings.local.json is the absolute forward-slash path of
# <project>/.claude/memory. The merge uses System.Text.Json so a one-element array is not
# unwrapped. A malformed file is one line and stays as it is.
# Once per machine (stamp <hidden git dir>/memory-imported), after the restore and before the
# hidden commit, Import-ClaudeMemory copies ~/.claude/projects/<slug>/memory: a missing file is
# copied, a file that differs goes to imported-<host>/, and MEMORY.md gains the lines it lacks.
# The source is never deleted. The slug is Claude Code's: every non-alphanumeric of the native
# absolute path becomes "-". An unreachable remote with no hidden commit yet waits. A file the
# team repo tracks is never written.

function Get-MemoryNativePath {
  return [IO.Path]::GetFullPath($script:AicTree)
}

function Get-MemoryForwardPath {
  return ((Get-MemoryNativePath) -replace '\\', '/').TrimEnd('/')
}

function Get-MemorySlug {
  return [regex]::Replace((Get-MemoryNativePath), '[^A-Za-z0-9]', '-')
}

function Get-MemoryHost {
  $name = ''
  try { $name = (& hostname 2>$null | Select-Object -First 1) } catch { }
  if (-not $name) { $name = [Environment]::MachineName }
  $name = [regex]::Replace(([string]$name).Trim(), '[^A-Za-z0-9._-]', '-')
  if (-not $name) { $name = 'unknown' }
  return $name
}

# One identical memory note per run (the round trip is called more than once).
function Write-MemoryOnce([string]$Line) {
  if (-not $script:MemoryOnce) { $script:MemoryOnce = @{} }
  if ($script:MemoryOnce.ContainsKey($Line)) { return }
  $script:MemoryOnce[$Line] = $true
  Write-Host $Line
}

# Merge autoMemoryDirectory. -Dry reports a would-be write and does not touch the file.
# Never throws: a session must not break.
function Merge-AutoMemorySettings {
  param([switch]$Dry)
  try {
    if (-not $script:AicTree) { return }
    $value = (Get-MemoryForwardPath) + '/.claude/memory'
    if ($value -eq '/.claude/memory') { return }
    $file = Join-Path (Join-Path $script:AicTree '.claude') 'settings.local.json'
    # A team repo that tracks the file owns it: never written (memory stays machine-local there).
    if ($script:AicMode -eq 'team' -and @(Invoke-Git @('-C', $script:AicTree, 'ls-files', '--', '.claude/settings.local.json')).Count -gt 0) { return }
    $node = $null
    if ((Test-Path -LiteralPath $file -PathType Leaf) -and ((Get-Item -LiteralPath $file -Force).Length -gt 0)) {
      $raw = [IO.File]::ReadAllText($file)
      if ([string]::IsNullOrWhiteSpace($raw)) {
        $node = [System.Text.Json.Nodes.JsonNode]::Parse('{}')
      } else {
        try { $node = [System.Text.Json.Nodes.JsonNode]::Parse($raw) }
        catch {
          Write-MemoryOnce 'ai-sync: autoMemoryDirectory not merged into .claude/settings.local.json (malformed JSON)'
          return
        }
      }
    } else {
      $node = [System.Text.Json.Nodes.JsonNode]::Parse('{}')
    }
    if ($node -isnot [System.Text.Json.Nodes.JsonObject]) {
      Write-MemoryOnce 'ai-sync: autoMemoryDirectory not merged into .claude/settings.local.json (malformed JSON)'
      return
    }
    $existing = $node['autoMemoryDirectory']
    $current = $null
    if ($null -ne $existing) {
      try { $current = [System.Text.Json.JsonSerializer]::Deserialize($existing.ToJsonString(), [string]) } catch { $current = $null }
    }
    if ($current -eq $value) { return }
    if ($Dry) {
      Write-Sync '  [write]  .claude/settings.local.json (autoMemoryDirectory)'
      return
    }
    $node['autoMemoryDirectory'] = [System.Text.Json.Nodes.JsonValue]::Create($value)
    $opts = [System.Text.Json.JsonSerializerOptions]::new()
    $opts.WriteIndented = $true
    $dir = Split-Path -Parent $file
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $tmp = $file + '.ai-sync-tmp'
    [IO.File]::WriteAllText($tmp, ($node.ToJsonString($opts).Replace("`r`n", "`n") + "`n"))
    Move-Item -LiteralPath $tmp -Destination $file -Force
    Write-Sync '  [write]  .claude/settings.local.json (autoMemoryDirectory)'
  } catch {
    Write-MemoryOnce 'ai-sync: autoMemoryDirectory not merged into .claude/settings.local.json (merge failed)'
  }
}

# dest keeps its lines; src lines it lacks are appended (LF).
function Merge-MemoryLines([string]$Dest, [string]$Src) {
  $have = New-Object 'System.Collections.Generic.List[string]'
  $seen = New-Object 'System.Collections.Generic.HashSet[string]'
  $existed = Test-Path -LiteralPath $Dest -PathType Leaf
  if ($existed) {
    foreach ($line in @([IO.File]::ReadAllLines($Dest))) {
      [void]$have.Add($line)
      [void]$seen.Add($line)
    }
  }
  $changed = -not $existed
  foreach ($line in @([IO.File]::ReadAllLines($Src))) {
    if ($seen.Add($line)) { [void]$have.Add($line); $changed = $true }
  }
  if (-not $changed) { return }
  $parent = Split-Path -Parent $Dest
  if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $text = ''
  if ($have.Count -gt 0) { $text = ($have -join "`n") + "`n" }
  [IO.File]::WriteAllText($Dest, $text)
}

# The once-per-machine import. No stamp when there is nothing to import yet.
function Import-ClaudeMemory {
  try {
    if (-not $script:AicGit -or -not $script:AicTree) { return }
    $stamp = Join-Path $script:AicGit 'memory-imported'
    if (Test-Path -LiteralPath $stamp -PathType Leaf) { return }
    if ($script:AicRemoteState -eq 'unreachable' -and -not (Test-AicHead)) { return }
    $slug = Get-MemorySlug
    if (-not $slug) { return }
    $src = Join-Path (Join-Path (Join-Path $HOME '.claude/projects') $slug) 'memory'
    if (-not (Test-Path -LiteralPath $src -PathType Container)) { return }
    $destRoot = Join-Path (Join-Path $script:AicTree '.claude') 'memory'
    $memHost = Get-MemoryHost
    $tracked = @()
    if ($script:AicMode -eq 'team') { $tracked = @(Get-TeamTracked $script:AicTree) }
    $rootLen = ([IO.Path]::GetFullPath($src)).TrimEnd('\', '/').Length
    $sep = [IO.Path]::DirectorySeparatorChar
    foreach ($item in @(Get-ChildItem -LiteralPath $src -Recurse -File -Force -ErrorAction SilentlyContinue)) {
      if ($item.LinkType) { continue }
      $rel = ([IO.Path]::GetFullPath($item.FullName).Substring($rootLen + 1) -replace '\\', '/')
      if (-not $rel) { continue }
      if ($tracked.Count -gt 0 -and (Test-TeamHas ".claude/memory/$rel" $tracked)) { continue }
      $dest = Join-Path $destRoot ($rel -replace '/', $sep)
      if ($rel -ceq 'MEMORY.md') { Merge-MemoryLines $dest $item.FullName; continue }
      if (-not (Test-Path -LiteralPath $dest)) {
        $parent = Split-Path -Parent $dest
        if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        Copy-Item -LiteralPath $item.FullName -Destination $dest
        continue
      }
      if ((Get-FileHash -LiteralPath $item.FullName).Hash -eq (Get-FileHash -LiteralPath $dest).Hash) { continue }
      $sideRel = "imported-$memHost/$rel"
      if ($tracked.Count -gt 0 -and (Test-TeamHas ".claude/memory/$sideRel" $tracked)) { continue }
      $side = Join-Path $destRoot ($sideRel -replace '/', $sep)
      if (Test-Path -LiteralPath $side) { continue }
      $parent = Split-Path -Parent $side
      if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
      Copy-Item -LiteralPath $item.FullName -Destination $side
    }
    [IO.File]::WriteAllText($stamp, '')
  } catch {
    Write-Host "ai-sync: Claude memory import failed - $($_.Exception.Message)"
  }
}

# The layer B round trip (private and team mode): create (or, on a fresh clone, attach) the
# hidden repo, commit the docs, rebase onto the remote branch, push. Sets AicRemoteState and
# AicDocsWait (see above). -NoFetch skips the download (the second call of a session, right
# after the first one). -Switching: the round trip of a --private-layer switch, before the code
# repo changes (whatever its mode; as private, or as team with -Team); AicSwitchReady = $true
# once the remote's branch is the hidden HEAD, or no remote is set. The remote: Set-AiContextRemote.
# Safety: <hidden repo>/sync.lock (Enter-SyncLock) - held by another run = a silent skip, and only
# its holder creates the repo or aborts a leftover rebase; a private project whose code repo still
# tracks layer B (an old branch) syncs nothing (AicOldBranch, no network).
function Sync-AiContext {
  param(
    [Parameter(Mandatory = $true)][string]$Target,
    [switch]$NoFetch,
    [switch]$DryRun,
    [switch]$Switching,
    [switch]$Team,
    [switch]$Quiet
  )
  $lock = ''
  try {
    if ($Quiet) { $script:SyncQuiet = $true }
    $script:AicCommitted = ''
    $script:AicRemote = ''
    $script:AicRemoteState = ''
    $script:AicDocsWait = $false
    $script:AicOldBranch = ''
    $script:AicSwitchReady = $false
    $script:AicNotes = @()
    $script:AicSwitching = [bool]$Switching
    $script:AicMode = 'private'
    if ($Team) { $script:AicMode = 'team' }
    if (-not (Test-Path -LiteralPath $Target -PathType Container)) { return }
    if (-not $Switching) {
      $script:AicMode = Get-ProjectMode $Target
      if (@('private', 'team') -notcontains $script:AicMode) { return }
    }
    if (-not (Set-AicPaths $Target)) { return }
    if (-not $Switching -and $script:AicMode -eq 'private' -and @(Get-TrackedPrivateDocs $script:AicTree).Count -gt 0) {
      $script:AicOldBranch = @(Get-TrackedLayerPaths $script:AicTree) -join ' '
      Merge-AutoMemorySettings
      return
    }
    Set-AiContextRemote
    if ($DryRun) {
      if (Test-Path -LiteralPath (Join-Path $script:AicGit 'HEAD') -PathType Leaf) { Write-Sync "  [ai-context] commit + sync private AI docs ($($script:AicBranch))" }
      else { Write-Sync "  [ai-context] create hidden repo .git/ai-context ($($script:AicBranch))" }
      Merge-AutoMemorySettings -Dry
      return
    }
    try { New-Item -ItemType Directory -Force -Path $script:AicGit -ErrorAction Stop | Out-Null }
    catch { Write-Host "ai-sync: private AI docs: could not create $($script:AicGit)"; return }
    if (-not (Enter-SyncLock (Join-Path $script:AicGit 'sync.lock'))) {
      # Another run is in the middle of it: skip quietly, as if the remote had not answered.
      if ($script:AicRemote) {
        $script:AicRemoteState = 'unreachable'
        if (-not (Test-AicHead)) { $script:AicDocsWait = $true }
      } else {
        $script:AicRemoteState = 'none'
        $script:AicSwitchReady = $true
      }
      return
    }
    $lock = Join-Path $script:AicGit 'sync.lock'
    Invoke-AicRoundTrip ([bool]$NoFetch) | Out-Null
    # A switch that is still waiting must not write settings or print a second line.
    if (-not $script:AicSwitching -or $script:AicSwitchReady) { Merge-AutoMemorySettings }
  } catch { Write-Host "ai-sync: private AI docs: $($_.Exception.Message)" }
  finally { if ($lock) { Exit-SyncLock $lock } }
}

# The locked half of Sync-AiContext.
function Invoke-AicRoundTrip([bool]$NoFetch) {
  $remote = $script:AicRemote
  $tracking = "refs/remotes/origin/$($script:AicBranch)"
  $remoteRef = ''
  $unrelated = $false
  if (-not (Test-Path -LiteralPath (Join-Path $script:AicGit 'HEAD') -PathType Leaf)) {
    Invoke-Git @('init', '-q', '--bare', $script:AicGit) | Out-Null
    if ($script:GitExit -eq 0) { Invoke-Aic @('symbolic-ref', 'HEAD', "refs/heads/$($script:AicBranch)") | Out-Null }
    if ($script:GitExit -eq 0) { Invoke-Aic @('config', 'status.showUntrackedFiles', 'no') | Out-Null }
    if ($script:GitExit -eq 0) { Invoke-Aic @('config', 'core.autocrlf', 'false') | Out-Null }
    if ($script:GitExit -ne 0) { Write-Host "ai-sync: private AI docs: could not create $($script:AicGit)"; return }
    $NoFetch = $false
    if (-not $remote) { Write-Host "ai-sync: private AI docs kept in a local hidden repo only - aicf setup --ai-context-remote <url> shares them between machines" }
  }
  Set-AicAttributes
  if ((Test-Path -LiteralPath (Join-Path $script:AicGit 'rebase-merge')) -or (Test-Path -LiteralPath (Join-Path $script:AicGit 'rebase-apply'))) {
    Invoke-Aic @('rebase', '--abort') | Out-Null
  }
  if ($remote) {
    $cur = (Invoke-Aic @('remote', 'get-url', 'origin')) | Select-Object -First 1
    if ($script:GitExit -ne 0) { Invoke-Aic @('remote', 'add', 'origin', $remote) | Out-Null }
    elseif ($cur -ne $remote) { Invoke-Aic @('remote', 'set-url', 'origin', $remote) | Out-Null }
  } else {
    $script:AicRemoteState = 'none'
    # Under a work root a github.com origin (an earlier rule's) goes: nothing is ever pushed there.
    if ($script:AicWork) {
      $cur = (Invoke-Aic @('remote', 'get-url', 'origin')) | Select-Object -First 1
      if ($script:GitExit -eq 0 -and $cur -and ([string]$cur).ToLowerInvariant().Contains('github.com')) {
        Invoke-Aic @('remote', 'remove', 'origin') | Out-Null
      }
    }
  }
  # Download first: a fresh clone must adopt the remote's docs before anything is committed.
  if ($remote -and -not $NoFetch) {
    $out = [IO.Path]::GetTempFileName()
    try {
      $base = @('-C', $script:AicTree, "--git-dir=$($script:AicGit)")
      $rc = Invoke-Bounded $out ($base + @('ls-remote', 'origin', "refs/heads/$($script:AicBranch)"))
      if ($rc -ne 0) {
        $script:AicRemoteState = 'unreachable'
        Write-AicOfflineLine "$remote unreachable"
        $remote = ''
      } elseif ((Get-Item -LiteralPath $out).Length -gt 0) {
        $rc = Invoke-Bounded $out ($base + @('fetch', '-q', 'origin', "+refs/heads/$($script:AicBranch):$tracking"))
        if ($rc -eq 0) {
          $script:AicRemoteState = 'present'
          $remoteRef = $tracking
        } else {
          $script:AicRemoteState = 'unreachable'
          Write-AicOfflineLine "fetch from $remote failed"
          $remote = ''
        }
      } else { $script:AicRemoteState = 'absent' }
    } finally { Remove-Item -LiteralPath $out, "$out.err" -Force -ErrorAction SilentlyContinue }
  }
  if ($remoteRef) {
    if (-not (Test-AicHead)) {
      Invoke-AicAdopt $remoteRef
      Write-AicNote "ai-sync: private AI docs restored from $remote ($($script:AicBranch))"
    } elseif (@(Invoke-Aic @('merge-base', 'HEAD', $remoteRef) | Where-Object { $_ }).Count -eq 0) {
      # Unrelated histories (two machines started separately): the remote's wins over a single
      # local commit (differing files saved, see Invoke-AicAdopt); anything more is merged by hand.
      $count = (Invoke-Aic @('rev-list', '--count', 'HEAD')) | Select-Object -First 1
      if ("$count" -eq '1') {
        Invoke-AicAdopt $remoteRef
        Write-AicNote "ai-sync: private AI docs updated from $remote"
      } else { $unrelated = $true }
    }
  }
  Import-ClaudeMemory
  Invoke-AicCommit
  if ($unrelated) {
    Write-Host "ai-sync: private AI docs: local and $remote histories are unrelated — nothing pushed; merge by hand: git --git-dir=$($script:AicGit) --work-tree=$($script:AicTree) merge --allow-unrelated-histories $remoteRef"
    return
  }
  if ($remoteRef) {
    $headBefore = (Invoke-Aic @('rev-parse', 'HEAD')) | Select-Object -First 1
    if (-not (Invoke-FactoryRebase $remote $remoteRef)) { return }
    Invoke-Aic @('merge-base', '--is-ancestor', 'HEAD', $headBefore) | Out-Null
    if ($script:GitExit -ne 0) { Write-AicNote "ai-sync: private AI docs updated from $remote" }
  }
  # Never a push the remote would refuse: HEAD must contain the remote branch last seen (unrelated
  # or conflicting histories were reported by the download that fetched it). A push skipped for
  # lack of network time stays quiet: the step that timed out was reported.
  if ($remote -and (Test-AicHead)) {
    $head = (Invoke-Aic @('rev-parse', 'HEAD')) | Select-Object -First 1
    $pushed = (Invoke-Aic @('rev-parse', '-q', '--verify', $tracking)) | Select-Object -First 1
    if ($script:GitExit -ne 0) { $pushed = '' }
    $contained = $true
    if ($pushed) {
      Invoke-Aic @('merge-base', '--is-ancestor', $tracking, 'HEAD') | Out-Null
      $contained = ($script:GitExit -eq 0)
    }
    if ($head -ne $pushed -and $contained) {
      $out = [IO.Path]::GetTempFileName()
      try {
        $rc = Invoke-Bounded $out @('-C', $script:AicTree, "--git-dir=$($script:AicGit)", 'push', '-q', 'origin', "HEAD:refs/heads/$($script:AicBranch)")
      } finally { Remove-Item -LiteralPath $out, "$out.err" -Force -ErrorAction SilentlyContinue }
      if ($rc -eq 0) { Invoke-Aic @('update-ref', $tracking, 'HEAD') | Out-Null }
      elseif (-not $script:AicSwitching -and -not $script:NetSkipped) { Write-Host "ai-sync: private AI docs: push to $remote failed - retried next time" }
    }
  }
  if ($script:AicCommitted) { Write-AicNote "ai-sync: private AI docs committed ($($script:AicCommitted))" }
  if ($script:AicRemoteState -eq 'unreachable' -and -not (Test-AicHead)) { $script:AicDocsWait = $true }
  if ($script:AicSwitching) { Set-AicSwitchReady }
}

# AicSwitchReady for a -Switching round trip: no remote is set, or a bounded ls-remote shows the
# remote's branch at the hidden HEAD (with no hidden commit at all, the remote having answered is
# enough: there is nothing to lose).
function Set-AicSwitchReady {
  if (-not $script:AicRemote) { $script:AicSwitchReady = $true; return }
  if (@('absent', 'present') -notcontains $script:AicRemoteState) { return }
  if (-not (Test-AicHead)) { $script:AicSwitchReady = $true; return }
  $sha = ''
  $out = [IO.Path]::GetTempFileName()
  try {
    $rc = Invoke-Bounded $out @('-C', $script:AicTree, "--git-dir=$($script:AicGit)", 'ls-remote', 'origin', "refs/heads/$($script:AicBranch)")
    if ($rc -eq 0) {
      $first = Get-Content -LiteralPath $out -TotalCount 1
      if ($first) { $sha = ([string]$first -split '\s+')[0] }
    }
  } finally { Remove-Item -LiteralPath $out, "$out.err" -Force -ErrorAction SilentlyContinue }
  $head = (Invoke-Aic @('rev-parse', 'HEAD')) | Select-Object -First 1
  if ($sha -and $sha -eq $head) { $script:AicSwitchReady = $true }
}

# The code root's .ai-root checkout (see Get-CodeRoot): projects\<name> records each project's
# mode ("mode=" and "origin=" lines), read by Get-RegistryMode when a project has no exclude
# block yet (a fresh clone). Writers take <its git dir>\ai-sync.lock (Enter-SyncLock) and never
# wait for it.

# "<remote> <ref>" of the checked-out branch's upstream, or ''.
function Get-AiRootUpstream([string]$Air) {
  $br = (Invoke-Git @('-C', $Air, 'symbolic-ref', '-q', '--short', 'HEAD')) | Select-Object -First 1
  if ($script:GitExit -ne 0 -or -not $br) { return '' }
  $rem = (Invoke-Git @('-C', $Air, 'config', '--get', "branch.$br.remote")) | Select-Object -First 1
  if ($script:GitExit -ne 0 -or -not $rem) { return '' }
  $merge = (Invoke-Git @('-C', $Air, 'config', '--get', "branch.$br.merge")) | Select-Object -First 1
  if ($script:GitExit -ne 0 -or -not $merge) { return '' }
  Invoke-Git @('-C', $Air, 'rev-parse', '-q', '--verify', '@{u}') | Out-Null
  if ($script:GitExit -ne 0) { return '' }
  return "$rem $merge"
}

# True (and one line, $Tail being its tail) when the checkout is mid-rebase/merge or has
# uncommitted changes.
function Test-AiRootBusy([string]$Air, [string]$GitDir, [string]$Tail) {
  if ((Test-Path -LiteralPath (Join-Path $GitDir 'rebase-merge') -PathType Container) -or
      (Test-Path -LiteralPath (Join-Path $GitDir 'rebase-apply') -PathType Container) -or
      (Test-Path -LiteralPath (Join-Path $GitDir 'MERGE_HEAD'))) {
    Write-Host "ai-sync: .ai-root has a rebase or merge in progress — $Tail"
    return $true
  }
  $status = @(Invoke-Git @('-C', $Air, 'status', '--porcelain') | Where-Object { $_ })
  if ($status.Count -gt 0) {
    Write-Host "ai-sync: .ai-root has uncommitted changes — $Tail"
    return $true
  }
  return $false
}

# Record the mode a switch just gave the project in <root>\.ai-root\projects\<name>, commit that
# file alone and push it. Only inside a known root whose .ai-root is a git checkout; the caller
# never calls it on -DryRun. A held lock, a dirty or mid-rebase checkout, or a pull still running
# is one line and a skip; a failed push is one line (the next session start's --pull pushes it).
function Set-RegistryMode([string]$Target, [string]$Mode) {
  try {
    $root = Get-CodeRoot $Target
    if (-not $root) { return }
    $air = Get-AiRootCheckout $root
    if (-not $air) { return }
    $gitDir = (Invoke-Git @('-C', $air, 'rev-parse', '--absolute-git-dir')) | Select-Object -First 1
    if ($script:GitExit -ne 0 -or -not $gitDir) { return }
    $gitDir = [IO.Path]::GetFullPath($gitDir)
    $top = Get-GitTop $Target
    $name = Split-Path -Leaf $top
    $lock = Join-Path $gitDir 'ai-sync.lock'
    if (-not (Enter-SyncLock $lock)) {
      Write-Host "ai-sync: .ai-root is locked by another sync — $name = $Mode not recorded"
      return
    }
    try { Save-RegistryEntry $air $gitDir $top $name $Mode }
    finally { Exit-SyncLock $lock }
  } catch { Write-Host "ai-sync: .ai-root: $($_.Exception.Message)" }
}

# The locked half of Set-RegistryMode.
function Save-RegistryEntry([string]$Air, [string]$GitDir, [string]$Top, [string]$Name, [string]$Mode) {
  $skip = "$Name = $Mode not recorded"
  if (Test-AiRootBusy $Air $GitDir $skip) { return }
  $upstream = Get-AiRootUpstream $Air
  if ($upstream) {
    $out = [IO.Path]::GetTempFileName()
    try { $rc = Invoke-Bounded $out @('-C', $Air, 'pull', '-q', '--rebase') }
    finally { Remove-Item -LiteralPath $out, "$out.err" -Force -ErrorAction SilentlyContinue }
    if ($rc -eq 124 -and -not $script:NetSkipped) { Write-Host "ai-sync: .ai-root pull still running — $skip"; return }
    # Offline, or no network time left: record locally, the push below fails and says so. A
    # conflict: leave it as it was.
    if ($rc -ne 0 -and ((Test-Path -LiteralPath (Join-Path $GitDir 'rebase-merge')) -or (Test-Path -LiteralPath (Join-Path $GitDir 'rebase-apply')))) {
      Invoke-Git @('-C', $Air, 'rebase', '--abort') | Out-Null
      Write-Host "ai-sync: .ai-root pull --rebase failed — $skip"
      return
    }
  }
  $rel = "projects/$Name"
  $dir = Join-Path $Air 'projects'
  $file = Join-Path $dir $Name
  $origin = (Invoke-Git @('-C', $Top, 'config', '--get', 'remote.origin.url')) | Select-Object -First 1
  if ($script:GitExit -ne 0 -or $null -eq $origin) { $origin = '' }
  $origin = $origin -replace "`r", ''
  $lines = New-Object 'System.Collections.Generic.List[string]'
  $lines.Add("mode=$Mode")
  if ($origin) { $lines.Add("origin=$origin") }
  $exists = Test-Path -LiteralPath $file -PathType Leaf
  if ($exists) {
    foreach ($l in (([IO.File]::ReadAllText($file) -replace "`r", '') -split "`n")) {
      if ($l -match '^\s*$' -or $l.StartsWith('mode=', [StringComparison]::Ordinal) -or $l.StartsWith('origin=', [StringComparison]::Ordinal)) { continue }
      $lines.Add($l)
    }
  }
  $bytes = (New-Object System.Text.UTF8Encoding $false).GetBytes((($lines -join "`n") + "`n"))
  # CR-blind: a Windows checkout (core.autocrlf) holds the same entry with CRLF endings.
  if ($exists) {
    $cur = [byte[]]@([IO.File]::ReadAllBytes($file) | Where-Object { $_ -ne 13 })
    if ([Convert]::ToBase64String($cur) -ceq [Convert]::ToBase64String($bytes)) { return }
  }
  Invoke-Git @('-C', $Air, 'ls-files', '--error-unmatch', '--', $rel) | Out-Null
  $wasTracked = ($script:GitExit -eq 0)
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  [IO.File]::WriteAllBytes($file, $bytes)
  Invoke-Git @('-C', $Air, 'add', '--', $rel) | Out-Null
  if ($script:GitExit -eq 0) { Invoke-Git @('-C', $Air, 'commit', '-q', '-m', "chore(registry): $Name = $Mode", '--', $rel) | Out-Null }
  if ($script:GitExit -ne 0) {
    if ($wasTracked) { Invoke-Git @('-C', $Air, 'checkout', '-q', 'HEAD', '--', $rel) | Out-Null }
    else {
      Invoke-Git @('-C', $Air, 'rm', '-q', '--cached', '--', $rel) | Out-Null
      Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    }
    Write-Host "ai-sync: .ai-root commit failed (git identity?) — $skip"
    return
  }
  Write-Sync "  [registry] .ai-root/${rel}: mode=$Mode"
  if (-not $upstream) { return }
  $rem, $ref = $upstream -split ' ', 2
  $out = [IO.Path]::GetTempFileName()
  try { $rc = Invoke-Bounded $out @('-C', $Air, 'push', '-q', $rem, "HEAD:$ref") }
  finally { Remove-Item -LiteralPath $out, "$out.err" -Force -ErrorAction SilentlyContinue }
  if ($rc -ne 0) { Write-Host "ai-sync: $Name = $Mode committed in .ai-root — pushed at the next session start" }
}

# The session start's --pull of <root>\.ai-root: a bounded `git pull --ff-only`, then a push when
# it is ahead of its upstream (a registry commit whose push failed). Once per run, before anything
# reads the registry. Never fails: a dirty checkout, a held lock, offline or a timeout is one
# line; nothing to do (or no upstream) is silent.
function Update-AiRoot([string]$CodeRoot) {
  try {
    $air = Get-AiRootCheckout $CodeRoot
    if (-not $air) { return }
    $gitDir = (Invoke-Git @('-C', $air, 'rev-parse', '--absolute-git-dir')) | Select-Object -First 1
    if ($script:GitExit -ne 0 -or -not $gitDir) { return }
    $gitDir = [IO.Path]::GetFullPath($gitDir)
    $upstream = Get-AiRootUpstream $air
    if (-not $upstream) { return }
    $lock = Join-Path $gitDir 'ai-sync.lock'
    if (-not (Enter-SyncLock $lock)) { Write-Host "ai-sync: .ai-root is locked by another sync — pull skipped"; return }
    try {
      if (Test-AiRootBusy $air $gitDir 'pull skipped') { return }
      $before = (Invoke-Git @('-C', $air, 'rev-parse', 'HEAD')) | Select-Object -First 1
      $out = [IO.Path]::GetTempFileName()
      try {
        $rc = Invoke-Bounded $out @('-C', $air, 'pull', '-q', '--ff-only')
        if ($rc -eq 124 -and $script:NetSkipped) {
          Write-Host "ai-sync: .ai-root pull skipped (no network time left in this run) — using the registry on disk"
        } elseif ($rc -eq 124) {
          Write-Host "ai-sync: .ai-root pull still running after $($script:NetLimit)s — using the registry on disk"
        } elseif ($rc -ne 0) {
          Write-Host "ai-sync: .ai-root pull failed (offline, or diverged from its upstream) — using the registry on disk"
        } else {
          $after = (Invoke-Git @('-C', $air, 'rev-parse', 'HEAD')) | Select-Object -First 1
          if ($after -ne $before) { Write-Sync 'ai-sync: pulled latest .ai-root' }
          $ahead = (Invoke-Git @('-C', $air, 'rev-list', '--count', '@{u}..HEAD')) | Select-Object -First 1
          if ($script:GitExit -ne 0 -or -not $ahead) { $ahead = '0' }
          if ($ahead -ne '0') {
            $rem, $ref = $upstream -split ' ', 2
            $rc = Invoke-Bounded $out @('-C', $air, 'push', '-q', $rem, "HEAD:$ref")
            if ($rc -eq 0) { Write-Sync "ai-sync: pushed .ai-root ($ahead commit(s))" }
            else { Write-Host 'ai-sync: .ai-root push failed — retried next time' }
          }
        }
      } finally { Remove-Item -LiteralPath $out, "$out.err" -Force -ErrorAction SilentlyContinue }
    } finally { Exit-SyncLock $lock }
  } catch { Write-Host "ai-sync: .ai-root: $($_.Exception.Message)" }
}

# --- install-global helpers (dot-sourced by install-global.ps1; the tests call them directly) ---

# install-global --ai-context-remote: @{ Dir = <absolute root>; Url = <url> }, or $null after one
# 'Error:' line on stderr. "<root>=<url>" when the part before the first = is an existing folder;
# else the whole argument is the URL of $DefaultRoot (the root holding this repo), refused when
# that root is a work root (none excepted: it only disables). A github.com URL is refused for a
# work root (Test-WorkPath).
function Resolve-RootRemote([string]$Arg, [string]$DefaultRoot) {
  $root = $DefaultRoot; $url = $Arg; $explicit = $false
  $eq = $Arg.IndexOf('=')
  if ($eq -gt 0) {
    $head = $Arg.Substring(0, $eq)
    if (Test-Path -LiteralPath $head -PathType Container) {
      $root = $head; $url = $Arg.Substring($eq + 1); $explicit = $true
    }
  }
  if (-not $url) {
    $host.UI.WriteErrorLine('Error: --ai-context-remote needs a git URL (or none): <url> or <root>=<url>')
    return $null
  }
  try { $root = (Resolve-Path -LiteralPath $root -ErrorAction Stop).Path.TrimEnd('\', '/') }
  catch { $host.UI.WriteErrorLine("Error: code root not found: $DefaultRoot"); return $null }
  if (Test-WorkPath $root) {
    if (-not $explicit -and $url -ne 'none') {
      $host.UI.WriteErrorLine("Error: --ai-context-remote <url> sets the remote of $root, a work root — name the root: --ai-context-remote <root>=<url>")
      return $null
    }
    if ($url.ToLowerInvariant().Contains('github.com')) {
      $host.UI.WriteErrorLine("Error: $url is a github.com remote — refused for the work root $root")
      return $null
    }
  }
  return @{ Dir = $root; Url = $url }
}

# Write the remote to <Dir>\.ai-context-remote (LF, one line, no BOM).
function Write-RootRemote($Remote) {
  if ($null -eq $Remote -or -not $Remote.Dir -or -not $Remote.Url) { return }
  $file = Join-Path $Remote.Dir '.ai-context-remote'
  [IO.File]::WriteAllText($file, "$($Remote.Url)`n")
  Write-Host "Recorded the private AI docs remote of $($Remote.Dir): $file -> $($Remote.Url)"
}

# Clone the owner's root repo (branch _root of the first line of <Root>\.ai-context-remote) into
# <Root>\.ai-root when it is missing. An existing .ai-root, no remote file, an empty one or none:
# nothing. A github.com remote under a work root is refused. Bounded like every network step
# (Invoke-Bounded) and never fatal: one line, never throws.
function Copy-AiRoot([string]$Root) {
  try {
    if (-not $Root -or -not (Test-Path -LiteralPath $Root -PathType Container)) { return }
    $Root = $Root.TrimEnd('\', '/')
    $dest = Join-Path $Root '.ai-root'
    if (Test-Path -LiteralPath $dest) { return }
    $file = Join-Path $Root '.ai-context-remote'
    if (-not (Test-NonEmptyFile $file)) { return }
    $url = ([string](@(Get-Content -LiteralPath $file -TotalCount 1)[0])).Trim()
    if (-not $url -or $url -eq 'none') { return }
    if ((Test-WorkPath $Root) -and $url.ToLowerInvariant().Contains('github.com')) {
      Write-Host "NOTE: $dest not cloned — $url is a github.com remote, refused under a work root"
      return
    }
    $out = [IO.Path]::GetTempFileName()
    try { $rc = Invoke-Bounded $out @('clone', '-q', '-b', '_root', $url, $dest) }
    finally { Remove-Item -LiteralPath $out, "$out.err" -Force -ErrorAction SilentlyContinue }
    if ($rc -eq 0) { Write-Host "Cloned the root repo: $dest (branch _root of $url)" }
    elseif ($rc -eq 124 -and $script:NetSkipped) { Write-Host "NOTE: $dest not cloned (no network time left) — re-run aicf setup" }
    elseif ($rc -eq 124) { Write-Host "NOTE: $dest clone still running after $($script:NetLimit)s — it finishes in the background" }
    else { Write-Host "NOTE: $dest not cloned from $url (offline, or no _root branch) — re-run aicf setup" }
  } catch { Write-Host "NOTE: $Root\.ai-root not cloned: $($_.Exception.Message)" }
}

# Merge the global SessionStart hook (templates\global\claude-global-hook.json: the engine with
# --global-hook) into Claude Code's user settings. Every other key and hook is kept; ours is the
# SessionStart entry whose JSON holds "--global-hook": replaced in place when it differs, appended
# when absent, extra copies dropped. A missing or empty file starts as {}. A file that does not
# parse, or whose root, "hooks" or "hooks.SessionStart" has the wrong type, is left untouched. One
# line either way; never throws.
function Install-ClaudeGlobalHook([string]$SettingsFile) {
  $J = [System.Text.Json.Nodes.JsonNode]
  $up = "  global SessionStart hook up to date: $SettingsFile"
  try {
    $entryFile = Join-Path $TemplateDir 'templates/global/claude-global-hook.json'
    $entry = $J::Parse([IO.File]::ReadAllText($entryFile))
  } catch { Write-Host "  skipped global SessionStart hook (merge failed): $SettingsFile"; return }
  try {
    $raw = ''
    if (Test-Path -LiteralPath $SettingsFile -PathType Leaf) { $raw = [IO.File]::ReadAllText($SettingsFile) }
    if ([string]::IsNullOrWhiteSpace($raw)) { $node = $J::Parse('{}') } else { $node = $J::Parse($raw) }
  } catch { $node = $null }
  if ($node -isnot [System.Text.Json.Nodes.JsonObject]) {
    Write-Host "  skipped global SessionStart hook (unparseable JSON, or its root is not an object): $SettingsFile"
    return
  }
  try {
    $hooks = $node['hooks']
    if ($null -eq $hooks) { $hooks = [System.Text.Json.Nodes.JsonObject]::new() }
    $starts = $null
    if ($hooks -is [System.Text.Json.Nodes.JsonObject]) {
      $starts = $hooks['SessionStart']
      if ($null -eq $starts) { $starts = [System.Text.Json.Nodes.JsonArray]::new() }
    }
    if ($starts -isnot [System.Text.Json.Nodes.JsonArray]) {
      Write-Host "  skipped global SessionStart hook (hooks or hooks.SessionStart has an unexpected type): $SettingsFile"
      return
    }
    $ours = @()
    for ($i = 0; $i -lt $starts.Count; $i++) {
      $e = $starts[$i]
      if ($null -ne $e -and $e.ToJsonString().Contains('--global-hook')) { $ours += $i }
    }
    if ($ours.Count -eq 1) {
      $same = $false
      try { $same = $J::DeepEquals($starts[$ours[0]], $entry) }
      catch { $same = ($starts[$ours[0]].ToJsonString() -ceq $entry.ToJsonString()) }
      if ($same) { Write-Host $up; return }
    }
    if ($ours.Count -gt 0) {
      for ($k = $ours.Count - 1; $k -ge 1; $k--) { $starts.RemoveAt($ours[$k]) }
      $starts[$ours[0]] = $entry
      $line = "  refreshed global SessionStart hook: $SettingsFile"
    } else {
      $starts.Add($entry)
      $line = "  registered global SessionStart hook: $SettingsFile"
    }
    if ($null -eq $hooks['SessionStart']) { $hooks['SessionStart'] = $starts }
    if ($null -eq $node['hooks']) { $node['hooks'] = $hooks }
    $opts = [System.Text.Json.JsonSerializerOptions]::new()
    $opts.WriteIndented = $true
    $opts.Encoder = [System.Text.Encodings.Web.JavaScriptEncoder]::UnsafeRelaxedJsonEscaping
    $dir = Split-Path -Parent $SettingsFile
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $tmp = $SettingsFile + '.ai-sync-tmp'
    [IO.File]::WriteAllText($tmp, ($node.ToJsonString($opts).Replace("`r`n", "`n") + "`n"))
    Move-Item -LiteralPath $tmp -Destination $SettingsFile -Force
    Write-Host $line
  } catch { Write-Host "  skipped global SessionStart hook (merge failed): $SettingsFile" }
}

# One Claude Code profile per code root that declares one in <root>\.ai-root\claude-profile.json
# ({"config_dir": "~/.claude-<x>", "settings": {...}}), looked for in the code root and its sibling
# folders. Each profile's config dir gets the "settings" merged into its settings.json (top-level
# keys replaced, object values such as env merged key by key, other keys kept) plus
# AI_TEMPLATE_DIR / AI_CODE_ROOT, the global SessionStart hook and the skills.
# ~\.claude-profiles records "<root><TAB><config-dir>" per profile, forward slashes (removed when
# none), and a managed block in the PowerShell profiles (Documents\PowerShell and
# Documents\WindowsPowerShell profile.ps1; elsewhere the running edition's CurrentUserAllHosts;
# AI_SHELL_PROFILES, a path-separator list, overrides) defines `claude` from
# templates\global\claude-profiles.ps1: run inside a recorded root, it sets CLAUDE_CONFIG_DIR. Secrets
# never go in the profile file: an apiKeyHelper or /login. One line per file; never throws.
function Install-ClaudeProfiles([string]$CodeRoot) {
  $J = [System.Text.Json.Nodes.JsonNode]
  $opts = [System.Text.Json.JsonSerializerOptions]::new()
  $opts.WriteIndented = $true
  $opts.Encoder = [System.Text.Encodings.Web.JavaScriptEncoder]::UnsafeRelaxedJsonEscaping
  $begin = '# >>> AICodeFactory claude-profiles >>>'; $end = '# <<< AICodeFactory claude-profiles <<<'
  $profiles = @()
  $parent = Split-Path -Parent ((Resolve-Path -LiteralPath $CodeRoot).ProviderPath)
  foreach ($d in (Get-ChildItem -LiteralPath $parent -Directory -Force -ErrorAction SilentlyContinue | Sort-Object Name)) {
    $f = Join-Path $d.FullName '.ai-root/claude-profile.json'
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { continue }
    try {
      $p = $J::Parse([IO.File]::ReadAllText($f))
      $c = $p['config_dir']
      if ($c -isnot [System.Text.Json.Nodes.JsonValue] -or -not $c.ToJsonString().StartsWith('"')) { throw 'shape' }
      $cfg = $c.ToString()
      $settings = $p['settings']
      if (-not $cfg.Trim() -or ($null -ne $settings -and $settings -isnot [System.Text.Json.Nodes.JsonObject])) { throw 'shape' }
    } catch {
      Write-Host "NOTE: $f skipped (a JSON object with a config_dir string and an optional settings object)"
      continue
    }
    $cfg = $cfg.Trim()
    if ($cfg -eq '~' -or $cfg.StartsWith('~/') -or $cfg.StartsWith('~\')) { $cfg = $HOME + $cfg.Substring(1) }
    $cfg = [IO.Path]::GetFullPath($cfg).Replace('\', '/')
    $rootPath = $d.FullName
    # Physical, as the shell function's `pwd -P` sees it (macOS: /var is /private/var).
    if (-not $OnWindows) { $phys = "$(& /bin/sh -c 'cd "$1" && pwd -P' sh $rootPath 2>$null)".Trim(); if ($phys) { $rootPath = $phys } }
    $rootPath = $rootPath.Replace('\', '/')
    New-Item -ItemType Directory -Force -Path (Join-Path $cfg 'skills') | Out-Null
    $sf = Join-Path $cfg 'settings.json'
    try {
      $raw = ''
      if (Test-Path -LiteralPath $sf -PathType Leaf) { $raw = [IO.File]::ReadAllText($sf) }
      if ([string]::IsNullOrWhiteSpace($raw)) { $node = $J::Parse('{}') } else { $node = $J::Parse($raw) }
    } catch { $node = $null }
    if ($node -isnot [System.Text.Json.Nodes.JsonObject]) {
      Write-Host "  skipped Claude profile settings (unparseable JSON, or its root is not an object): $sf"
      $profiles += , @($rootPath, $cfg); continue
    }
    try {
      $before = $node.ToJsonString()
      $aiEnv = [System.Text.Json.Nodes.JsonObject]::new()
      $aiEnv['AI_TEMPLATE_DIR'] = $TemplateDir; $aiEnv['AI_CODE_ROOT'] = $CodeRoot
      if ($OverlayDir) { $aiEnv['AI_TEMPLATE_OVERLAY_DIR'] = $OverlayDir }
      $pairs = @()
      if ($null -ne $settings) { foreach ($kv in $settings) { $pairs += , @($kv.Key, $kv.Value) } }
      $pairs += , @('env', $aiEnv)
      foreach ($kv in $pairs) {
        # Never `$x = if (…) { $node }`: PowerShell enumerates a JsonObject that leaves a statement.
        $k = [string]$kv[0]; $v = $null
        if ($null -ne $kv[1]) { $v = $kv[1].DeepClone() }
        $drop = @()  # a null (define's tombstone) drops a key
        if ($v -is [System.Text.Json.Nodes.JsonObject]) { $drop = @(@($v) | Where-Object { $null -eq $_.Value } | ForEach-Object { $_.Key }) }
        foreach ($dk in $drop) { [void]$v.Remove($dk) }
        if ($v -is [System.Text.Json.Nodes.JsonObject] -and $node[$k] -is [System.Text.Json.Nodes.JsonObject]) {
          foreach ($dk in $drop) { [void]$node[$k].Remove($dk) }
          foreach ($e in @($v)) { $node[$k][$e.Key] = $e.Value.DeepClone() }
        } else { $node[$k] = $v }
      }
      if ($node.ToJsonString() -ceq $before) { Write-Host "  Claude profile settings up to date: $sf" }
      else {
        [IO.File]::WriteAllText("$sf.ai-sync-tmp", ($node.ToJsonString($opts).Replace("`r`n", "`n") + "`n"))
        Move-Item -LiteralPath "$sf.ai-sync-tmp" -Destination $sf -Force
        Write-Host ("  {0} Claude profile settings: $sf" -f $(if ($raw.Trim()) { 'refreshed' } else { 'registered' }))
      }
    } catch { Write-Host "  skipped Claude profile settings (merge failed): $sf" }
    $profiles += , @($rootPath, $cfg)
  }
  $record = Join-Path $HOME '.claude-profiles'
  if ($profiles.Count -gt 0) {
    $body = ($profiles | ForEach-Object { "$($_[0])`t$($_[1])`n" }) -join ''
    $old = if (Test-Path -LiteralPath $record) { [IO.File]::ReadAllText($record) } else { $null }
    if ($old -cne $body) { [IO.File]::WriteAllText($record, $body) }
    Write-Host "  Claude profiles: $(($profiles | ForEach-Object { (Split-Path -Leaf $_[0]) + ' -> ' + $_[1] }) -join ', ') ($record)"
  } elseif (Test-Path -LiteralPath $record) {
    Remove-Item -LiteralPath $record -Force
    Write-Host "  removed $record (no code root declares a Claude profile)"
  }
  if ($env:AI_SHELL_PROFILES) {
    $rcs = @($env:AI_SHELL_PROFILES.Split([IO.Path]::PathSeparator) | Where-Object { $_ })
  } elseif ($OnWindows) {
    # Empty when USERPROFILE points elsewhere than the account's real profile (the test suites).
    $docs = [Environment]::GetFolderPath('MyDocuments')
    if (-not $docs) { $docs = Join-Path $HOME 'Documents' }
    $rcs = @((Join-Path $docs 'PowerShell/profile.ps1'), (Join-Path $docs 'WindowsPowerShell/profile.ps1'))
  } else { $rcs = @($PROFILE.CurrentUserAllHosts) }
  $snippet = [IO.File]::ReadAllText((Join-Path $TemplateDir 'templates/global/claude-profiles.ps1')).Replace("`r`n", "`n")
  $block = "$begin`n$($snippet.TrimEnd())`n$end`n"
  foreach ($rc in $rcs) {
    try {
      $text = if (Test-Path -LiteralPath $rc -PathType Leaf) { [IO.File]::ReadAllText($rc) } else { '' }
      $i = $text.IndexOf($begin); $j = $text.IndexOf($end)
      $has = $i -ge 0 -and $j -gt $i
      if ($has) { $j = $text.IndexOf("`n", $j); $j = if ($j -lt 0) { $text.Length } else { $j + 1 } }
      if ($profiles.Count -eq 0) {
        if ($has) {
          $head = $text.Substring(0, $i).TrimEnd("`n")
          $new = $head + $(if ($head.Trim()) { "`n" } else { '' }) + $text.Substring($j)
          [IO.File]::WriteAllText($rc, $new)
          Write-Host "  removed the claude profile function: $rc"
        }
        continue
      }
      if ($has) { $new = $text.Substring(0, $i) + $block + $text.Substring($j) }
      else {
        $new = $text
        if ($text -and -not $text.EndsWith("`n")) { $new += "`n" }
        if ($text) { $new += "`n" }
        $new += $block
      }
      if ($new -ceq $text) { Write-Host "  claude profile function up to date: $rc"; continue }
      $dir = Split-Path -Parent $rc
      if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
      [IO.File]::WriteAllText($rc, $new)
      Write-Host ("  {0} the claude profile function: $rc" -f $(if ($has) { 'refreshed' } else { 'added' }))
    } catch { Write-Host "  skipped the claude profile function: $rc" }
  }
  foreach ($pr in $profiles) { Install-ClaudeGlobalHook (Join-Path $pr[1] 'settings.json') }
  Add-ProfileSkillRoots
}

# Skills install and dev-context: engine\sync-skills.ps1; name spelling: engine\names.ps1; work
# roots: engine\work-roots.ps1; the overlay per target: engine\overlay.ps1 (this file stays under
# its line record).
. (Join-Path $PSScriptRoot 'engine\names.ps1')
. (Join-Path $PSScriptRoot 'engine\work-roots.ps1')
. (Join-Path $PSScriptRoot 'engine\factory-hook.ps1')
. (Join-Path $PSScriptRoot 'engine\sync-skills.ps1')

# Standalone invocation (skipped when dot-sourced).
if ($MyInvocation.InvocationName -ne '.') {
  $target = '.'
  $dryRun = $false; $commit = $false; $quiet = $false; $pull = $false; $skills = $false; $push = $false; $shared = $false
  $scanPrivate = $false; $history = $false; $agentsMd = $false; $privateLayer = $false; $aicOnly = $false
  $globalHook = $false; $rootSync = $false
  $rerun = @()
  foreach ($arg in $args) {
    if ($arg -notmatch '^(--pull|-Pull)$') { $rerun += $arg }
    # `break` is required: PowerShell runs EVERY matching case of a switch otherwise.
    switch -Regex ($arg) {
      '^(--dry-run|-DryRun)$' { $dryRun = $true; break }
      '^(--commit|-Commit)$'  { $commit = $true; break }
      '^(--quiet|-Quiet)$'    { $quiet = $true; break }
      '^(--push|-Push)$'      { $push = $true; break }
      '^(--pull|-Pull)$'      { $pull = $true; break }
      '^(--agents|-Agents)$'  { $agentsMd = $true; break }
      '^(--skills|-Skills)$'  { $skills = $true; break }
      '^(--shared|-Shared)$'  { $shared = $true; break }
      '^(--private-layer|-PrivateLayer|--private-docs|-PrivateDocs)$' { $privateLayer = $true; break }
      '^(--ai-context-sync|-AiContextSync)$' { $aicOnly = $true; break }
      '^(--root-sync|-RootSync)$' { $rootSync = $true; break }
      '^(--scan-private|-ScanPrivate)$' { $scanPrivate = $true; break }
      '^(--history|-History)$' { $history = $true; break }
      '^(--global-hook|-GlobalHook)$' { $globalHook = $true; break }
      '^(-h|--help)$'         { $h = @(Get-Content -LiteralPath $PSCommandPath); $h[0..([array]::IndexOf($h, '') - 1)] | ForEach-Object { $_ -replace '^# ?', '' }; exit 0 }
      '^-'                    { Write-Error "Unknown option: $arg"; exit 2 }
      default                 { $target = $arg }
    }
  }
  # The global hook (~\.claude\settings.json): its own plan, whatever else was passed.
  if ($globalHook) {
    $plan = Get-GlobalHookPlan $target
    if ($plan -ne 'run') {
      if ($plan -eq 'suggest') { Write-ConformLine $target }
      exit 0
    }
    $dryRun = $false; $commit = $true; $quiet = $true; $push = $false; $pull = $true; $agentsMd = $true
    $skills = $true; $shared = $false; $privateLayer = $false; $aicOnly = $false; $scanPrivate = $false
    $rerun = @($target, '--quiet', '--commit', '--agents', '--skills')
  }
  if ($quiet) { $script:SyncQuiet = $true }
  if ($scanPrivate) { exit (Invoke-PrivateTermsScan -Target $target -History $history) }
  if ($rootSync) {
    if ($dryRun) { exit 0 }
    Reset-NetBudget
    $rootPath = Resolve-Path -LiteralPath $target -ErrorAction SilentlyContinue
    if ($rootPath) { Update-AiRoot $rootPath.Path }
    exit 0
  }
  if ($aicOnly) {
    Sync-AiContext -Target $target -DryRun:$dryRun
    if ($script:AicOldBranch) { Write-OldBranchLine (Split-Path -Leaf $script:AicTree) $script:AicOldBranch }
    exit 0
  }
  if ($pull) {
    # A new network budget (AI_SYNC_NET_BUDGET) for this run; the re-run below inherits it.
    if (-not $dryRun) { Reset-NetBudget }
    # The code root's .ai-root first, exactly once: the re-run below has no --pull, and the
    # registry must be current before Sync-AiContext reads a fresh clone's mode from it.
    if (-not $dryRun) { Update-AiRoot (Get-CodeRoot $target) }
    Update-TemplateRepo
    # The pull may have changed this very script: re-run the new one, without --pull.
    if ($script:PullUpdated) { & $PSCommandPath @rerun; exit $LASTEXITCODE }
  }
  # Private AI docs: download before the sync (a fresh clone gets its docs back instead of blank
  # templates), upload after it and the AGENTS.md refresh. Both are no-ops in other projects.
  # -PrivateLayer: Sync-AiTemplates runs the download itself (the switch order needs it there).
  # A switch that waits for the remote changes nothing more: no AGENTS.md refresh, no upload.
  if (-not ($privateLayer -and -not $dryRun)) { Sync-AiContext -Target $target -DryRun:$dryRun }
  Sync-AiTemplates -Target $target -DryRun:$dryRun -Commit:$commit -Quiet:$quiet -Push:$push -Shared:$shared -PrivateLayer:$privateLayer
  if (-not $script:SyncSwitchWaits) {
    if ($agentsMd) { Update-AgentsMd -Target $target -DryRun:$dryRun -Commit:$commit }
    if (-not $dryRun) { Sync-AiContext -Target $target -NoFetch }
  }
  if ($skills) { Sync-GlobalSkills -DryRun:$dryRun }
  exit 0
}
