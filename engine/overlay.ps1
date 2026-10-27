# The overlay: its layout, its effective templates, and the overlay per sync target. Dot-sourced
# by sync-ai-templates.ps1 once $OverlayDir is known; kept here so the engine script stays under
# its code-health record.
#
# Layout: templates\<src> (+ .append) and skills\, like this repo. The old layout - <src> at the
# overlay's root, vscode-global\<file> and vscode-global\skills\ - is still read, after the new
# paths, with one note per run (Write-OverlayLayoutNote).

$OverlayManifestFile = ''
$OverlaySkillsSrc = ''
if ($OverlayDir) {
  $OverlayManifestFile = Join-Path $OverlayDir 'overlay-manifest.txt'
  $OverlaySkillsSrc = Join-Path $OverlayDir 'skills'
  $ovOldSkills = Join-Path (Join-Path $OverlayDir 'vscode-global') 'skills'
  if (-not (Test-Path -LiteralPath $OverlaySkillsSrc -PathType Container) -and (Test-Path -LiteralPath $ovOldSkills -PathType Container)) {
    $OverlaySkillsSrc = $ovOldSkills
  }
}
# Where skills come from, first source wins on a name clash.
$SkillSrcs = @()
if ($OverlaySkillsSrc -and (Test-Path -LiteralPath $OverlaySkillsSrc -PathType Container)) { $SkillSrcs += $OverlaySkillsSrc }
$SkillSrcs += $SkillsSrc

# Old-layout paths of the overlay, relative with / (vscode-global itself, and every *.template /
# *.template.append outside templates\, skills\ and .git).
function Find-OverlayOldPaths([string]$Dir, [string]$Rel) {
  foreach ($c in @(Get-ChildItem -LiteralPath $Dir -Force -ErrorAction SilentlyContinue)) {
    $r = if ($Rel) { "$Rel/$($c.Name)" } else { $c.Name }
    if ($c.PSIsContainer) {
      if (-not $Rel -and $c.Name -cin @('templates', 'skills', '.git')) { continue }
      if (-not $Rel -and $c.Name -ceq 'vscode-global') { $r; continue }
      Find-OverlayOldPaths $c.FullName $r
    } elseif ($c.Name -clike '*.template' -or $c.Name -clike '*.template.append') { $r }
  }
}

# Once per run, one line when the overlay still holds old-layout paths.
$script:OverlayLayoutNoted = $false
function Write-OverlayLayoutNote {
  if (-not $OverlayDir -or $script:OverlayLayoutNoted) { return }
  $script:OverlayLayoutNoted = $true
  [string[]]$old = @(Find-OverlayOldPaths $OverlayDir '')
  if ($old.Count -eq 0) { return }
  [Array]::Sort($old, [StringComparer]::Ordinal)
  $what = ($old | Select-Object -First 3) -join ', '
  if ($old.Count -gt 3) { $what += ', …' }
  Write-Host "ai-sync: overlay uses the old layout ($what) — move it to templates/ and skills/"
}

# The old overlay layout's spelling of a template path.
function Get-TemplateOldRel([string]$Rel) {
  if ($Rel.StartsWith('templates/global/')) { return 'vscode-global/' + $Rel.Substring(17) }
  if ($Rel.StartsWith('templates/')) { return $Rel.Substring(10) }
  return $Rel
}

# Effective template path: the overlay's file when it has one (new layout, then old), else the
# base's. An old overlay-manifest entry naming a base template without its templates/ prefix
# still finds it.
function Get-TemplatePath([string]$Rel) {
  if ($script:TplOverlay) {
    foreach ($r in @($Rel, (Get-TemplateOldRel $Rel))) {
      $ov = Join-Path $script:TplOverlay $r
      if (Test-Path -LiteralPath $ov -PathType Leaf) { return $ov }
    }
  }
  $base = Join-Path $TemplateDir $Rel
  $moved = Join-Path (Join-Path $TemplateDir 'templates') $Rel
  if (-not (Test-Path -LiteralPath $base -PathType Leaf) -and (Test-Path -LiteralPath $moved -PathType Leaf)) { return $moved }
  return $base
}

# The effective template's bytes, followed by the overlay's <Rel>.append fragment when there is
# one (a newline is inserted if the base lacks one). Byte-exact, like the bash twin's `cat`: no
# BOM stripping, no re-encoding, line endings left as they are.
function Get-RenderedBytes([string]$Rel) {
  [byte[]]$bytes = [IO.File]::ReadAllBytes((Get-TemplatePath $Rel))
  if ($script:TplOverlay) {
    $frag = Join-Path $script:TplOverlay "$Rel.append"
    if (-not (Test-Path -LiteralPath $frag -PathType Leaf)) { $frag = Join-Path $script:TplOverlay "$(Get-TemplateOldRel $Rel).append" }
    if (Test-Path -LiteralPath $frag -PathType Leaf) {
      $ms = New-Object IO.MemoryStream
      $ms.Write($bytes, 0, $bytes.Length)
      if ($bytes.Length -gt 0 -and $bytes[$bytes.Length - 1] -ne 10) { $ms.WriteByte(10) }
      [byte[]]$fb = [IO.File]::ReadAllBytes($frag)
      $ms.Write($fb, 0, $fb.Length)
      $bytes = $ms.ToArray()
    }
  }
  return ,$bytes
}

# Same, as text - for living docs, which need the [PROJECT_NAME] substitution.
function Get-RenderedTemplate([string]$Rel) {
  return [Text.Encoding]::UTF8.GetString((Get-RenderedBytes $Rel))
}

# The overlay that renders this target ($script:TplOverlay): none for the template repo itself
# (same folder), whose committed copies must never carry overlay content - no overlay file,
# .append fragment or overlay-manifest entry. Skills keep the overlay.
$script:TplOverlay = $OverlayDir
function Set-OverlayFor([string]$Target) {
  $want = $OverlayDir
  $cmp = if ($IsWindows -or $env:OS -eq 'Windows_NT') { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
  try {
    $t = (Resolve-Path -LiteralPath $Target -ErrorAction Stop).Path.TrimEnd('\', '/')
    if ([string]::Equals($t, $TemplateDir.TrimEnd('\', '/'), $cmp)) { $want = '' }
  } catch { }
  if ($want) { Write-OverlayLayoutNote }
  if ($want -eq $script:TplOverlay) { return }
  $script:TplOverlay = $want
  $script:PointerMap = @(); $script:LivingDocsMap = @(); $script:ObsoleteMap = @(); $script:SharedHookMap = @()
  Read-Manifest $ManifestFile
  if ($want -and $OverlayManifestFile -and (Test-Path -LiteralPath $OverlayManifestFile -PathType Leaf)) { Read-Manifest $OverlayManifestFile }
}
