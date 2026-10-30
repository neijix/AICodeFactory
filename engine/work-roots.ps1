# Work roots: code roots whose private AI docs must never reach a personal remote (the remote
# rules of Set-AiContextRemote, Resolve-RootRemote and Copy-AiRoot). Dot-sourced by
# sync-ai-templates.ps1; kept here so the engine script stays under the code-health line record.

# The first "<Key>": "<value>" of an environment.json (value of letters, digits, . _ -), or ''
# (no file, no such key).
function Get-EnvJsonField([string]$File, [string]$Key) {
  if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { return '' }
  try { $text = [IO.File]::ReadAllText($File) } catch { return '' }
  $m = [regex]::Match($text, '"' + [regex]::Escape($Key) + '"\s*:\s*"([A-Za-z0-9._-]*)"')
  if ($m.Success) { return $m.Groups[1].Value }
  return ''
}

# The work-roots list (lowercase, backslashes as /, trailing / dropped): $env:AI_WORK_ROOTS when
# set (';' or the platform path separator between entries; empty or none = no work roots, and the
# file is not read), else the lines of ~/.ai-work-roots (blank lines and # comments skipped, CR
# stripped, trimmed).
function Get-WorkRoots {
  if ($null -ne $env:AI_WORK_ROOTS) {
    if ($env:AI_WORK_ROOTS -eq '' -or $env:AI_WORK_ROOTS -ceq 'none') { return @() }
    $lines = $env:AI_WORK_ROOTS -split ('[;' + [regex]::Escape([string][IO.Path]::PathSeparator) + ']')
  } else {
    $file = Join-Path $HOME '.ai-work-roots'
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return @() }
    try { $lines = [IO.File]::ReadAllLines($file) } catch { return @() }
  }
  $out = @()
  foreach ($l in $lines) {
    $e = $l.Trim()
    if (-not $e -or $e.StartsWith('#')) { continue }
    $e = $e.Replace('\', '/').TrimEnd('/').ToLowerInvariant()
    if ($e) { $out += $e }
  }
  return $out
}

# True when the nearest folder at or above the path holding .ai-root\ or .ai-context-remote (a
# code root; the walk stops at $HOME and every folder above it, as in Get-AncestorRoot) has
# .ai-root\environment.json "label": "work" (any case; a file written before label replaced kind:
# "kind": "work").
function Test-WorkLabel([string]$Path) {
  try { $d = [IO.Path]::GetFullPath($Path) } catch { return $false }
  $sep = [IO.Path]::DirectorySeparatorChar
  $homeDir = ''
  if ($HOME) { try { $homeDir = [IO.Path]::GetFullPath($HOME).TrimEnd('\', '/') + $sep } catch { $homeDir = '' } }
  while ($d) {
    if ($homeDir -and $homeDir.StartsWith($d.TrimEnd('\', '/') + $sep, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    if ((Test-Path -LiteralPath (Join-Path $d '.ai-root') -PathType Container) -or
        (Test-Path -LiteralPath (Join-Path $d '.ai-context-remote'))) {
      $f = Join-Path (Join-Path $d '.ai-root') 'environment.json'
      if ((Get-EnvJsonField $f 'kind') -ceq 'work') { return $true }
      return ((Get-EnvJsonField $f 'label') -eq 'work')
    }
    $d = Split-Path -Parent $d
  }
  return $false
}

# True when the path lies under a work root: an entry of Get-WorkRoots matches it (a name without
# / = any path component, case-insensitive; a path = a prefix on whole components,
# case-insensitive), or its code root's label is work (Test-WorkLabel).
function Test-WorkPath([string]$Path) {
  if (-not $Path) { return $false }
  $p = $Path.Replace('\', '/').ToLowerInvariant().TrimEnd('/')
  foreach ($e in @(Get-WorkRoots)) {
    if ($e.Contains('/')) {
      if (($p + '/').StartsWith($e + '/', [StringComparison]::Ordinal)) { return $true }
    } elseif (@($p -split '/') -ccontains $e) { return $true }
  }
  return (Test-WorkLabel $Path)
}
