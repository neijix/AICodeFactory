# Project and code-root name spelling: the registry's and the root repo's, so every clone of a
# project on every machine (any folder case) shares one hidden branch. Dot-sourced by
# sync-ai-templates.ps1; kept here so the engine script stays under the code-health line record.

# The registry entry's own spelling of the folder name: the exact entry, else the one differing
# only by case (a d3skhand clone of D3SKHAND), else the folder name. The hidden repo's branch uses
# it, so every clone shares one branch.
function Get-RegistryName([string]$Dir, [string]$Name) {
  $ci = ''
  # The files a bash glob sees: no dot-file.
  foreach ($f in @(Get-ChildItem -LiteralPath $Dir -File -Force | Where-Object { -not $_.Name.StartsWith('.') } | Sort-Object Name)) {
    if ($f.Name -ceq $Name) { return $f.Name }
    if (-not $ci -and $f.Name -ieq $Name) { $ci = $f.Name }
  }
  if ($ci) { return $ci }
  return $Name
}

# The root folder's name as the root repo's branches spell it: the exact <name>/… branch, else one
# differing only by case (a Linux CODE checkout of a Code root), else the folder name. Read from
# .ai-root's remote-tracking refs (local, no network), so every machine's clone of a project
# shares one hidden branch.
function Get-RootSpelling([string]$Root) {
  $base = Split-Path -Leaf $Root
  $ci = ''
  $air = Join-Path $Root '.ai-root'
  if (Test-Path -LiteralPath (Join-Path $air '.git')) {
    $refs = Invoke-Git @('-C', $air, 'for-each-ref', '--format=%(refname)', 'refs/remotes/origin/')
    if ($script:GitExit -ne 0) { $refs = @() }
    foreach ($r in $refs) {
      $seg = ([string]$r).Trim() -replace '^refs/remotes/origin/', ''
      if ($seg -notmatch '/') { continue }
      $seg = $seg.Substring(0, $seg.IndexOf('/'))
      if ($seg -ceq $base) { return $seg }
      if (-not $ci -and $seg -ieq $base) { $ci = $seg }
    }
  }
  if ($ci) { return $ci }
  return $base
}
