# Undoes `aicf setup` (engine\install-global.ps1) on this machine, for this checkout:
#   - the global skill folders it installed: links into this checkout's skills (or the overlay's),
#     and copies whose .ai-template-origin names them - in every tool's skills dir and in each
#     Claude profile's config dir. Skills another template repo installed, and copies without
#     the marker, are not ours and stay.
#   - in ~\.claude\settings.json and each Claude profile's settings.json: the global SessionStart
#     hook (the entry running --global-hook) and the env keys AI_TEMPLATE_DIR, AI_CODE_ROOT and
#     AI_TEMPLATE_OVERLAY_DIR. Every other key stays; a file left empty is removed.
#   - the Copilot CLI block in ~\.copilot\copilot-instructions.md (your own text above it stays),
#     the VS Code prompts file ai-autobootstrap.instructions.md, ~\.gemini\commands\bootstrap-ai.toml
#   - the managed `claude` profile block in the shell profiles (the PowerShell profiles, ~/.zshrc,
#     ~/.bashrc, or $env:AI_SHELL_PROFILES)
#   - ~\.ai-template-dir, ~\.ai-template-overlay-dir, ~\.ai-work-roots, ~\.claude-profiles and
#     ~\.ai-skills-stamp, then the folders setup created that are now empty.
#
# Never touched: any project, a code root's .ai-root and .ai-context-remote, ~\.apps-config-dir
# (your apps read it), the <file>.bak backups setup kept when it removed stale MCP entries, the
# "settings" a Claude profile merged into its config dir, and this checkout itself.
# When ~\.ai-template-dir names another checkout, that one owns the machine-wide files: only the
# skills and settings entries of this checkout go.
#
# Usage: aicf uninstall [--yes]
#   (no option)  preview: print what would be removed or edited; nothing changes
#   --yes        do it

[CmdletBinding(PositionalBinding = $false)]
param([switch]$Yes, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)

# Windows PowerShell 5.1 (all a fresh Windows has) cannot run this script: hand over to pwsh.
if ($PSVersionTable.PSVersion.Major -lt 7) {
  $fwd = @($Rest | Where-Object { $null -ne $_ })
  if ($Yes) { $fwd = @('--yes') + $fwd }
  if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) { Write-Host "Error: this script needs PowerShell 7 (this is Windows PowerShell $($PSVersionTable.PSVersion)). Install it with ``winget install --id Microsoft.PowerShell -e``, open a new terminal and run it again."; exit 1 }
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @fwd; exit $LASTEXITCODE
}

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $PSScriptRoot   # the template repo (this file is in engine\)
$codeRoot = Split-Path -Parent $scriptDir
$apply = [bool]$Yes
foreach ($a in @($Rest | Where-Object { $null -ne $_ })) {
  switch -Regex ($a) {
    '^(--yes|-y)$' { $apply = $true; break }
    '^(-h|--help)$' {
      foreach ($line in @(Get-Content -LiteralPath $PSCommandPath)) { if ($line -notmatch '^\W?#') { break }; $line -replace '^\W?# ?', '' }
      exit 0
    }
    default { $host.UI.WriteErrorLine("Unknown option: $a (usage: aicf uninstall [--yes])"); exit 2 }
  }
}

. (Join-Path $scriptDir 'sync-ai-templates.ps1')
$userHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$base = if ($env:APPDATA) { $env:APPDATA }
        elseif ($IsMacOS) { Join-Path $userHome 'Library/Application Support' }
        elseif ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $userHome '.config' }

# This checkout owns the machine-wide files unless ~/.ai-template-dir names another live one.
$owns = $true
$other = ''
$markerFile = Join-Path $userHome '.ai-template-dir'
if ((Test-Path -LiteralPath $markerFile -PathType Leaf) -and (Get-Item -LiteralPath $markerFile -Force).Length -gt 0) {
  $other = (@(Get-Content -LiteralPath $markerFile -TotalCount 1)[0] + '').Trim()
  if ((Test-Path -LiteralPath (Join-Path $other 'sync-ai-templates.sh')) -and -not (Test-SamePath $other $scriptDir)) { $owns = $false }
}
$script:found = 0

# One line; in -Yes mode a remove deletes the path (a link as a link).
function Write-Action([string]$Verb, [string]$Path, [string]$Why) {
  if ($Verb -ne 'keep') { $script:found++ }
  Write-Host ('  {0,-8} {1} ({2})' -f "[$Verb]", $Path, $Why)
  if ($apply -and $Verb -eq 'remove') { Remove-Any $Path }
}
function Remove-Any([string]$Path) {
  $i = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if ($null -eq $i) { return }
  if ($i.LinkType) { $i.Delete() } else { Remove-Item -LiteralPath $Path -Recurse -Force }
}
# A link into one of our skills sources, or a copy whose marker names one.
function Test-OurSkill($Item) {
  if (Test-SymLink $Item.FullName) {
    $t = Get-LinkTarget $Item
    if (-not $t) { return $false }
    $full = [IO.Path]::GetFullPath($t, (Split-Path -Parent $Item.FullName)).TrimEnd('\', '/')
    foreach ($src in $SkillSrcs) {
      foreach ($s in $src, (Get-LegacySkillSrc $src)) {
        $prefix = $s.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        $cmp = if ($OnWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
        if ($full.StartsWith($prefix, $cmp)) { return $true }
      }
    }
    return $false
  }
  $marker = Join-Path $Item.FullName $SkillOriginFile
  if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) { return $false }
  $origin = (@(Get-Content -LiteralPath $marker -TotalCount 1)[0] + '').Trim()
  foreach ($src in $SkillSrcs) {
    if ((Test-SameSkillSrc $origin $src) -or (Test-SameSkillSrc $origin (Get-LegacySkillSrc $src))) { return $true }
  }
  return $false
}
# Remove a folder and its parents while they are empty folders below the user's home.
function Remove-EmptyUp([string]$Dir) {
  $homeFull = [IO.Path]::GetFullPath($userHome).TrimEnd('\', '/')
  $d = $Dir
  while ($d) {
    $full = [IO.Path]::GetFullPath($d).TrimEnd('\', '/')
    if ($full -eq $homeFull -or -not $full.StartsWith($homeFull + [IO.Path]::DirectorySeparatorChar)) { return }
    $item = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
    if ($null -eq $item -or -not $item.PSIsContainer -or $item.LinkType -or @(Get-ChildItem -LiteralPath $full -Force).Count -gt 0) { return }
    Remove-Item -LiteralPath $full -Force
    $d = Split-Path -Parent $full
  }
}
# What precedes a managed block, minus the blank line setup added.
function Get-HeadText([string]$Head) {
  $h = $Head.TrimEnd("`n")
  if ($Head.Trim()) { return $h + "`n" }
  return ''
}
function Write-OrRemove([string]$Path, [string]$Text) {
  if (-not $apply) { return }
  if ($Text) { [IO.File]::WriteAllText($Path, $Text) } else { Remove-Item -LiteralPath $Path -Force }
}

# Claude settings: our SessionStart entry and env keys, unless another checkout's.
function Remove-SetupSettings([string]$File) {
  if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { return }
  $J = [System.Text.Json.Nodes.JsonNode]
  try {
    $raw = [IO.File]::ReadAllText($File)
    if ([string]::IsNullOrWhiteSpace($raw)) { $raw = '{}' }
    $node = $J::Parse($raw)   # assigned directly: an if-expression would unroll the JsonObject
  } catch { $node = $null }
  if ($node -isnot [System.Text.Json.Nodes.JsonObject]) { Write-Action keep $File 'not a JSON object: edit it by hand'; return }
  $envNode = $node['env']
  if ($envNode -isnot [System.Text.Json.Nodes.JsonObject]) { $envNode = $null }
  $named = $null
  if ($envNode -and $envNode.ContainsKey('AI_TEMPLATE_DIR')) { $named = "$($envNode['AI_TEMPLATE_DIR'])" }
  if (($null -ne $named -and -not (Test-SamePath $named $scriptDir)) -or ($null -eq $named -and -not $owns)) { return }
  $gone = @()
  $hooks = $node['hooks']
  if ($hooks -is [System.Text.Json.Nodes.JsonObject] -and $hooks['SessionStart'] -is [System.Text.Json.Nodes.JsonArray]) {
    $starts = $hooks['SessionStart']
    $n = $starts.Count
    for ($k = $n - 1; $k -ge 0; $k--) {
      if ($null -ne $starts[$k] -and $starts[$k].ToJsonString().Contains('--global-hook')) { $starts.RemoveAt($k) }
    }
    if ($starts.Count -ne $n) {
      $gone += 'global SessionStart hook'
      if ($starts.Count -eq 0) { [void]$hooks.Remove('SessionStart') }
      if ($hooks.Count -eq 0) { [void]$node.Remove('hooks') }
    }
  }
  if ($envNode) {
    foreach ($key in 'AI_TEMPLATE_DIR', 'AI_CODE_ROOT', 'AI_TEMPLATE_OVERLAY_DIR') {
      if (-not $envNode.ContainsKey($key)) { continue }
      if ($key -eq 'AI_CODE_ROOT' -and -not (Test-SamePath "$($envNode[$key])" $codeRoot)) { continue }
      [void]$envNode.Remove($key); $gone += $key
    }
    if ($envNode.Count -eq 0 -and $gone.Count -gt 0) { [void]$node.Remove('env') }
  }
  if ($gone.Count -eq 0) { return }
  $left = $node.Count -gt 0
  Write-Action $(if ($left) { 'edit' } else { 'remove' }) $File (($gone -join ', ') + $(if ($left) { '' } else { '; nothing else in it' }))
  if ($apply -and $left) {
    $opts = [System.Text.Json.JsonSerializerOptions]::new()
    $opts.WriteIndented = $true
    $opts.Encoder = [System.Text.Encodings.Web.JavaScriptEncoder]::UnsafeRelaxedJsonEscaping
    [IO.File]::WriteAllText($File, $node.ToJsonString($opts).Replace("`r`n", "`n") + "`n")
  }
}

if ($apply) { Write-Host "Removing what aicf setup installed for ${scriptDir}:" }
else { Write-Host "Preview — what aicf uninstall --yes would remove for $scriptDir (nothing changes now):" }
if (-not $owns) { Write-Action keep $markerFile "names another checkout, ${other}: its own aicf uninstall removes the machine-wide files" }

# 1. Skills (the profile dirs are in $SkillRoots while ~/.claude-profiles is still there).
Add-FactorySkillSources
$profileDirs = @()
$profilesFile = Join-Path $userHome '.claude-profiles'
if (Test-Path -LiteralPath $profilesFile -PathType Leaf) {
  foreach ($line in [IO.File]::ReadAllLines($profilesFile)) {
    $parts = $line -split "`t", 2
    if ($parts.Count -eq 2 -and $parts[1].Trim()) { $profileDirs += $parts[1].Trim() }
  }
}
foreach ($root in $SkillRoots) {
  if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
  $n = 0
  foreach ($item in @(Get-ChildItem -LiteralPath $root -Force)) {
    if (-not (Test-OurSkill $item)) { continue }
    $n++
    if ($apply) { Remove-Any $item.FullName }
  }
  if ($n -eq 0) { continue }
  $script:found += $n
  Write-Host ('  {0,-8} {1} skill folder(s) in {2} (from this checkout; the others stay)' -f '[remove]', $n, $root)
}

# 2. JSON and text edits: Claude settings, the Copilot CLI block, the shell-profile blocks.
Remove-SetupSettings (Join-Path $userHome '.claude/settings.json')
foreach ($d in $profileDirs) { Remove-SetupSettings (Join-Path $d 'settings.json') }
$copilot = Join-Path $userHome '.copilot/copilot-instructions.md'
$mark = 'Global AI Behavior — Auto-Bootstrap Every Project'
if ($owns -and (Test-Path -LiteralPath $copilot -PathType Leaf)) {
  $text = [IO.File]::ReadAllText($copilot)
  $i = $text.IndexOf($mark, [StringComparison]::Ordinal)
  if ($i -ge 0) {
    $new = Get-HeadText $text.Substring(0, $text.LastIndexOf("`n", [Math]::Max(0, $i - 1)) + 1)
    Write-Action $(if ($new) { 'edit' } else { 'remove' }) $copilot ('auto-bootstrap block' + $(if ($new) { '' } else { '; nothing else in it' }))
    if ($new) { Write-OrRemove $copilot $new }
  }
}
$rcs = @()
if ($env:AI_SHELL_PROFILES) { $rcs += @($env:AI_SHELL_PROFILES.Split([IO.Path]::PathSeparator) | Where-Object { $_ }) }
$xdg = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $userHome '.config' }
$rcs += @((Join-Path $userHome '.zshrc'), (Join-Path $userHome '.bashrc'), (Join-Path $xdg 'powershell/profile.ps1'),
  (Join-Path $userHome '.config/powershell/profile.ps1'), (Join-Path $userHome 'Documents/PowerShell/profile.ps1'),
  (Join-Path $userHome 'Documents/WindowsPowerShell/profile.ps1'))
$begin = '# >>> AICodeFactory claude-profiles >>>'; $end = '# <<< AICodeFactory claude-profiles <<<'
foreach ($rc in @($rcs | Select-Object -Unique)) {
  if (-not $owns -or -not (Test-Path -LiteralPath $rc -PathType Leaf)) { continue }
  $text = [IO.File]::ReadAllText($rc)
  $i = $text.IndexOf($begin, [StringComparison]::Ordinal); $j = $text.IndexOf($end, [StringComparison]::Ordinal)
  if ($i -lt 0 -or $j -lt $i) { continue }
  $j = $text.IndexOf("`n", $j); $j = if ($j -lt 0) { $text.Length } else { $j + 1 }
  $new = (Get-HeadText $text.Substring(0, $i)) + $text.Substring($j)
  if (-not $new.Trim()) { $new = '' }
  Write-Action $(if ($new) { 'edit' } else { 'remove' }) $rc ('claude profile function' + $(if ($new) { '' } else { '; nothing else in it' }))
  if ($new) { Write-OrRemove $rc $new }
}

# 3. Files setup wrote whole.
$toml = Join-Path $userHome '.gemini/commands/bootstrap-ai.toml'
if (Test-Path -LiteralPath $toml -PathType Leaf) {
  $body = [IO.File]::ReadAllText($toml).Replace('\', '/')
  $dir = $scriptDir.Replace('\', '/').TrimEnd('/')
  $cmp = if ($OnWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
  if ($body.IndexOf("$dir/skills/bootstrap-ai/SKILL.md", $cmp) -ge 0 -or $body.IndexOf("$dir/vscode-global/skills/bootstrap-ai/SKILL.md", $cmp) -ge 0) {
    Write-Action remove $toml 'Gemini CLI command'
  }
}
if ($owns) {
  foreach ($f in (Join-Path $base 'Code/User/prompts/ai-autobootstrap.instructions.md'), $markerFile,
      (Join-Path $userHome '.ai-template-overlay-dir'), (Join-Path $userHome '.ai-work-roots'), $profilesFile,
      (Join-Path $userHome '.ai-skills-stamp'), (Join-Path $userHome '.ai-skills-stamp.running')) {
    if (Test-Path -LiteralPath $f) { Write-Action remove $f 'written by aicf setup' }
  }
}
foreach ($f in (Join-Path $userHome '.apps-config-dir'), (Join-Path $codeRoot '.ai-context-remote'), (Join-Path $codeRoot '.ai-root')) {
  if (Test-Path -LiteralPath $f) { Write-Action keep $f "not removed: yours, or the code root's" }
}

# 4. The folders setup created, once empty.
if ($apply) {
  foreach ($d in @($SkillRoots) + $profileDirs + @((Join-Path $userHome '.gemini/commands'), (Join-Path $userHome '.copilot'),
      (Join-Path $userHome '.claude'), (Join-Path $base 'Code/User/prompts'), (Join-Path $xdg 'powershell'),
      (Join-Path $userHome '.config/powershell'), (Join-Path $userHome 'Documents/PowerShell'),
      (Join-Path $userHome 'Documents/WindowsPowerShell'))) {
    Remove-EmptyUp $d
  }
}

if ($script:found -eq 0) { Write-Host 'Nothing of aicf setup is installed for this checkout.' }
elseif ($apply) { Write-Host "Done. Projects keep their AI files; delete $scriptDir by hand if you no longer want it." }
else { Write-Host 'Nothing changed. Run aicf uninstall --yes to apply.' }
exit 0
