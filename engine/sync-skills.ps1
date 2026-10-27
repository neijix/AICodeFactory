# Skills install and the dev-context pack. Dot-sourced by sync-ai-templates.ps1.
# Kept in this file so the engine script stays under the code-health line record.

# True when two origin markers name the same skills dir. On Windows the bash twin writes
# /f/Code/..., this engine F:\Code\... (-eq ignores case).
function Test-SameSkillSrc([string]$A, [string]$B) {
  if (-not $OnWindows) { return $A.Trim() -ceq $B.Trim() }
  if ($A.Trim() -eq $B.Trim()) { return $true }
  $keys = foreach ($p in $A, $B) {
    $p = $p.Trim().Replace('\', '/').TrimEnd('/')
    if ($p -match '^/([A-Za-z])(/.*)?$') { $p = $Matches[1] + ':' + $Matches[2] }
    $p
  }
  return $keys[0] -eq $keys[1]
}

# The pre-move home of a skills source (<repo>\vscode-global\skills, before skills\ moved to the
# repo root): an install naming it is ours, to re-install.
function Get-LegacySkillSrc([string]$Src) {
  return (Join-Path (Join-Path (Split-Path -Parent $Src.TrimEnd('\', '/')) 'vscode-global') 'skills')
}

# True when another template repo installed this skill name (a live symlink pointing outside
# every one of our skills dirs - base or overlay - or a copy whose origin marker names another
# repo). Whichever template installed first keeps it; dangling links and unmarked copies are
# ours to fix.
function Test-SkillOwnedElsewhere($Item, [bool]$IsLink) {
  if ($null -eq $Item) { return $false }
  if ($IsLink) {
    $t = Get-LinkTarget $Item
    if (-not $t -or -not (Test-Path -LiteralPath $t)) { return $false }
    $full = [IO.Path]::GetFullPath($t).TrimEnd('\', '/')
    foreach ($src in $SkillSrcs) {
      foreach ($s in $src, (Get-LegacySkillSrc $src)) {
        $prefix = $s.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        if ($OnWindows) {
          if ($full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $false }
        } elseif ($full.StartsWith($prefix)) { return $false }
      }
    }
    return $true
  }
  $marker = Join-Path $Item.FullName $SkillOriginFile
  if (Test-Path -LiteralPath $marker -PathType Leaf) {
    $origin = @(Get-Content -LiteralPath $marker -TotalCount 1)[0]
    if ($null -eq $origin) { $origin = '' }
    $origin = $origin.Trim()
    foreach ($src in $SkillSrcs) {
      if ((Test-SameSkillSrc $origin $src) -or (Test-SameSkillSrc $origin (Get-LegacySkillSrc $src))) { return $false }
    }
    return $true
  }
  return $false
}

# Remove installed copies of the names each skills source lists in RETIRED, unless a source ships
# that name again, in any case (Windows and macOS file systems fold it: a RETIRED line in another
# case would reach the shipped folder). Only a real folder whose origin marker names that source
# goes (a renamed or unmarked copy is the user's). A name must look like a skill folder name: no
# separator, so a line cannot leave the root. Returns the count.
function Remove-RetiredSkills([string[]]$Shipped, [switch]$DryRun) {
  $count = 0
  foreach ($src in $SkillSrcs) {
    $retired = Join-Path $src $SkillRetiredFile
    if (-not (Test-Path -LiteralPath $retired -PathType Leaf)) { continue }
    foreach ($name in Get-Content -LiteralPath $retired) {
      if ($name -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { continue }
      if ($Shipped -contains $name) { continue }                  # shipped again (here or by the overlay)
      foreach ($root in $SkillRoots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        $dest = Join-Path $root $name
        $item = Get-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
        if ($null -eq $item -or -not $item.PSIsContainer) { continue }
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        $marker = Join-Path $dest $SkillOriginFile
        if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) { continue }
        $origin = Get-Content -LiteralPath $marker -TotalCount 1 -ErrorAction SilentlyContinue
        if (-not ((Test-SameSkillSrc ([string]$origin) $src) -or (Test-SameSkillSrc ([string]$origin) (Get-LegacySkillSrc $src)))) { continue }
        Write-Sync "  [remove] $dest (skill retired from the template)"
        $count++
        if ($DryRun) { continue }
        try { Remove-PathSafely $dest }
        catch { Write-Host "ai-sync: could not remove $dest - delete it by hand ($($_.Exception.Message))" }
      }
    }
  }
  return $count
}

# Mirror skills/* (overlay first, then this repo; a name shipped by both installs
# the overlay's) into every tool's global skills dir that exists on this machine
# (install-global.* creates them). Copy mode replaces symlinks/outdated copies with fresh
# copies; link mode replaces stale copies with symlinks. A skill name already installed by
# another template repo is left alone.
function Sync-GlobalSkills {
  param([switch]$DryRun)
  Write-OverlayLayoutNote
  if (-not $DryRun) { Repair-GeminiBootstrap }
  Add-FactorySkillSources
  $sourcesCurrent = (-not $DryRun) -and (Test-FactorySkillsCurrent)
  if ((-not $DryRun) -and (-not $sourcesCurrent)) { Start-FactorySkillsInstall }
  $changed = 0
  if (-not $sourcesCurrent) {
  $doneNames = @()
  foreach ($src in $SkillSrcs) {
    if (-not (Test-Path -LiteralPath $src -PathType Container)) { continue }
    foreach ($skillDir in Get-ChildItem -LiteralPath $src -Directory) {
      if (-not (Test-Path -LiteralPath (Join-Path $skillDir.FullName 'SKILL.md'))) { continue }
      if ($doneNames -contains $skillDir.Name) { continue }     # an earlier (overlay) source already shipped it
      $doneNames += $skillDir.Name
      foreach ($root in $SkillRoots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }   # tool not installed here
        $dest = Join-Path $root $skillDir.Name
        $item = Get-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
        $isLink = ($null -ne $item) -and (($item.LinkType -eq 'SymbolicLink') -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0))
        if (Test-SkillOwnedElsewhere $item $isLink) { continue }
        if ($SkillMode -eq 'link') {
          if ($isLink -and ((Get-LinkTarget $item) -eq $skillDir.FullName)) { continue }
          Write-Sync "  [link]   $dest -> $($skillDir.FullName)"
        } else {
          # Up to date only when it is our copy FROM THIS SOURCE (a copy of the same name from the
          # other source must be replaced) and its content matches.
          $sameOrigin = $false
          if ($null -ne $item -and -not $isLink) {
            $markerPath = Join-Path $dest $SkillOriginFile
            if (Test-Path -LiteralPath $markerPath -PathType Leaf) {
              $origin = @(Get-Content -LiteralPath $markerPath -TotalCount 1)[0]
              if ($null -eq $origin) { $origin = '' }
              $sameOrigin = (Test-SameSkillSrc $origin $src)
            }
          }
          # Compare first: Python starts only for a copy that differs (one per skill and tool).
          if ($sameOrigin -and (Test-SameDir $skillDir.FullName $dest)) { continue }
          if ($sameOrigin -and (Test-FactorySkillKeep $dest $skillDir.FullName)) { continue }
          Write-Sync "  [copy]   $dest"
        }
        $changed++
        if ($DryRun) { continue }
        Remove-PathSafely $dest
        if ($SkillMode -eq 'link') {
          New-Item -ItemType SymbolicLink -Path $dest -Target $skillDir.FullName | Out-Null
        } else {
          Copy-Item -LiteralPath $skillDir.FullName -Destination $dest -Recurse -Force
          if (-not (Write-FactorySkillStamp $dest $skillDir.FullName $src)) {
            [IO.File]::WriteAllText((Join-Path $dest $SkillOriginFile), $src + "`n")
          }
        }
      }
    }
  }
  }
  # Skills deleted from the template: dangling links, and retired copies (Remove-RetiredSkills).
  foreach ($root in $SkillRoots) {
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
    foreach ($child in Get-ChildItem -LiteralPath $root -Force) {
      if ($child.LinkType -ne 'SymbolicLink') { continue }
      $t = Get-LinkTarget $child
      if ($t -and -not (Test-Path -LiteralPath $t)) {
        Write-Sync "  [remove] $($child.FullName) (dangling skill link)"
        $changed++
        if (-not $DryRun) { $child.Delete() }
      }
    }
  }
  if (-not $sourcesCurrent) { $changed += Remove-RetiredSkills $doneNames -DryRun:$DryRun }
  if ($script:SyncQuiet -and $changed -gt 0) { Write-Host "ai-sync: refreshed $changed global skill folder(s) ($SkillMode mode)" }
  if ((-not $DryRun) -and (-not $sourcesCurrent)) { Complete-FactorySkillsInstall }
}

# install-global wrote ~\.gemini\commands\bootstrap-ai.toml with this repo's pre-move skills
# path (vscode-global/skills/): point it at skills/.
function Repair-GeminiBootstrap {
  if (-not $HOME) { return }
  $toml = Join-Path (Join-Path (Join-Path $HOME '.gemini') 'commands') 'bootstrap-ai.toml'
  if (-not (Test-Path -LiteralPath $toml -PathType Leaf)) { return }
  $root = $TemplateDir.TrimEnd('\', '/') -replace '\\', '/'
  $text = [IO.File]::ReadAllText($toml)
  if (-not $text.Contains("$root/vscode-global/skills/")) { return }
  try { [IO.File]::WriteAllText($toml, $text.Replace("$root/vscode-global/skills/", "$root/skills/")) } catch { }
}

# Dev-context packs (see the header). One pack file is capped so a huge rules.md cannot fill
# the session. The marker is the first line of a CLAUDE.local.md this engine wrote.
$script:DevContextMax = 16384
$script:DevContextMark = '<!-- ai-templates: dev-context'

# The dev-context scope: the code root's .ai-root\environment.json "label", else its "kind", else
# work under a work root (Test-WorkPath), else personal inside a code root (Get-CodeRoot). $null
# (no scope) anywhere else.
function Get-DevContextScope([string]$Target) {
  $croot = Get-CodeRoot $Target
  $v = ''
  if ($croot) {
    $file = Join-Path (Join-Path $croot '.ai-root') 'environment.json'
    $v = Get-EnvJsonField $file 'label'
    if (-not $v) { $v = Get-EnvJsonField $file 'kind' }
  }
  if (-not $v -and (Test-WorkPath $Target)) { $v = 'work' }
  if (-not $v -and $croot) { $v = 'personal' }
  if (-not $v) { return $null }
  return $v
}

function Add-KeptFactorySection([string]$Build, [string]$Local) {
  if (-not (Test-Path -LiteralPath $Local -PathType Leaf)) { return }
  $existing = [IO.File]::ReadAllText($Local)
  $mark = '<!-- ai-templates: factory -->'
  $endMark = '<!-- ai-templates: factory-end -->'
  $start = $existing.IndexOf($mark)
  if ($start -lt 0) { return }
  $end = $existing.IndexOf($endMark, $start)
  if ($end -lt 0) { return }
  $section = $existing.Substring($start, $end + $endMark.Length - $start).TrimEnd()
  $utf8 = New-Object System.Text.UTF8Encoding $false
  $bytes = $utf8.GetBytes("`n$section`n")   # one blank line, as the bash twin and apply.py write it
  $fs = [IO.File]::Open($Build, 'Append', 'Write')
  try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }
}

function Test-DevContextOurs([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $first = Get-Content -LiteralPath $Path -TotalCount 1 -ErrorAction SilentlyContinue
  return ($first -like "$($script:DevContextMark)*")
}

# Append one pack file onto $Dest. A missing file is skipped. An unreadable one prints one
# ai-sync line and a placeholder. Past DevContextMax, keep the head and say so.
function Add-DevContextFile([string]$Dest, [string]$Label, [string]$Src) {
  if (-not (Test-Path -LiteralPath $Src -PathType Leaf)) { return }
  $bytes = $null
  try { $bytes = [IO.File]::ReadAllBytes($Src) } catch { $bytes = $null }
  $utf8 = New-Object System.Text.UTF8Encoding $false
  $fs = [IO.File]::Open($Dest, 'Append', 'Write')
  try {
    if ($null -eq $bytes) {
      Write-Host "ai-sync: dev-context: cannot read $Label"
      $note = [Text.Encoding]::UTF8.GetBytes("(could not be read)`n")
      $fs.Write($note, 0, $note.Length)
      return
    }
    if ($bytes.Length -gt $script:DevContextMax) {
      Write-Host "ai-sync: dev-context: $Label truncated to $($script:DevContextMax) bytes"
      $fs.Write($bytes, 0, $script:DevContextMax)
      $note = $utf8.GetBytes("`n`n(truncated)`n")
      $fs.Write($note, 0, $note.Length)
    } else {
      if ($bytes.Length -gt 0) { $fs.Write($bytes, 0, $bytes.Length) }
      $endsNl = ($bytes.Length -gt 0) -and ($bytes[$bytes.Length - 1] -eq 10 -or $bytes[$bytes.Length - 1] -eq 13)
      if (-not $endsNl) {
        $nl = $utf8.GetBytes("`n")
        $fs.Write($nl, 0, $nl.Length)
      }
    }
  } finally { $fs.Dispose() }
}

function Apply-DevContext([string]$Target, [bool]$DryRun) {
  $scope = Get-DevContextScope $Target
  $local = Join-Path $Target 'CLAUDE.local.md'
  $dir = $null
  $label = ''
  $source = ''
  $has = $false
  # The code root's .ai-root\dev-context\ (when it holds a pack file).
  if ($scope) {
    $croot = Get-CodeRoot $Target
    if ($croot) {
      $dir = Join-Path (Join-Path $croot '.ai-root') 'dev-context'
      $label = '.ai-root/dev-context'
      $source = "../.ai-root/dev-context/ (the code root's .ai-root repo) — not in this project's git."
    }
  }
  if ($dir) {
    $has = (Test-Path -LiteralPath (Join-Path $dir 'rules.md') -PathType Leaf) -or (Test-Path -LiteralPath (Join-Path $dir 'settings.json') -PathType Leaf)
  }
  if (-not $has) {
    if (Test-DevContextOurs $local) {
      if ($DryRun) { Write-Sync '  [remove] CLAUDE.local.md (dev-context)' }
      else { Remove-Item -LiteralPath $local -Force }
    }
    return
  }
  if ((Test-Path -LiteralPath $local -PathType Leaf) -and -not (Test-DevContextOurs $local)) {
    Write-Host "ai-sync: dev-context $scope — CLAUDE.local.md is not ours, left untouched"
    return
  }
  if ($DryRun) {
    Write-Sync "  [write]  CLAUDE.local.md (dev-context $scope)"
    return
  }
  # Built outside the work tree: a leftover (killed hook, failed move) must never get committed.
  Get-ChildItem -LiteralPath $Target -Filter '.dev-context.tmp.*' -Force -File -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue
  $build = Join-Path ([IO.Path]::GetTempPath()) ('ai-dev-context.' + [guid]::NewGuid().ToString('N'))
  $utf8 = New-Object System.Text.UTF8Encoding $false
  $header = @(
    "$($script:DevContextMark) $scope -->"
    "# Dev context — $scope"
    ''
    "Development rules for this code root (label from .ai-root/environment.json, else work or personal). Source: $source"
    'Edit rules.md there. No credentials in that folder; this file is rewritten on sync.'
    ''
  ) -join "`n"
  [IO.File]::WriteAllText($build, $header + "`n", $utf8)
  if (Test-Path -LiteralPath (Join-Path $dir 'settings.json') -PathType Leaf) {
    $h = $utf8.GetBytes("## Settings`n`n")
    $fs = [IO.File]::Open($build, 'Append', 'Write')
    try { $fs.Write($h, 0, $h.Length) } finally { $fs.Dispose() }
    Add-DevContextFile $build "$label/settings.json" (Join-Path $dir 'settings.json')
    $fs = [IO.File]::Open($build, 'Append', 'Write')
    try { $blank = $utf8.GetBytes("`n"); $fs.Write($blank, 0, $blank.Length) } finally { $fs.Dispose() }
  }
  if (Test-Path -LiteralPath (Join-Path $dir 'rules.md') -PathType Leaf) {
    $h = $utf8.GetBytes("## Rules`n`n")
    $fs = [IO.File]::Open($build, 'Append', 'Write')
    try { $fs.Write($h, 0, $h.Length) } finally { $fs.Dispose() }
    Add-DevContextFile $build "$label/rules.md" (Join-Path $dir 'rules.md')
  }
  Add-KeptFactorySection $build $local
  $same = (Test-Path -LiteralPath $local -PathType Leaf) -and ((Get-FileHash -LiteralPath $build).Hash -eq (Get-FileHash -LiteralPath $local).Hash)
  if ($same) { Remove-Item -LiteralPath $build -Force }
  else { Move-Item -LiteralPath $build -Destination $local -Force }
  if ($script:SyncQuiet) {
    Write-Host "ai-sync: dev-context $scope — read CLAUDE.local.md and follow it (development rules for this root; gitignored)."
  } else {
    Write-Sync "ai-sync: dev-context $scope"
  }
}
