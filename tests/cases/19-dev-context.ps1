# Dot-sourced by tests/run-tests.ps1 (its helpers and sandbox): the dev-context packs (19) and the
# work roots that pick a pack's scope (19b).
Write-Host "--- 19. dev-context: personal in a code root, work under a work root, nowhere else"
# Each root's pack lives in its .ai-root/dev-context/ (the only source). The projects are
# registered tracked so the code roots add no conformance line.
$D19 = Join-Path $S 'dc19'; $NR = "$D19/Code/.ai-root"; $UR = "$D19/WorkCode/.ai-root"
New-Item -ItemType Directory -Force -Path "$NR/dev-context", "$NR/projects", "$UR/dev-context", "$UR/projects" | Out-Null
[IO.File]::WriteAllText("$NR/dev-context/rules.md", "PERSONAL-RULE`n")
[IO.File]::WriteAllText("$NR/dev-context/settings.json", '{"note":"personal-pref"}' + "`n")
[IO.File]::WriteAllText("$UR/dev-context/rules.md", "WORK-RULE`n")
[IO.File]::WriteAllText("$UR/dev-context/settings.json", '{"note":"work-pref"}' + "`n")
function New-Proj([string]$Dir) { New-Item -ItemType Directory -Force -Path $Dir | Out-Null; git -C $Dir init -q }
function New-Proj19([string]$Dir) {
  New-Proj $Dir
  [IO.File]::WriteAllText((Join-Path (Join-Path (Split-Path $Dir) '.ai-root/projects') (Split-Path $Dir -Leaf)), "mode=tracked`n")
}
New-Proj19 "$D19/Code/personal-proj"
$out = @(E "$D19/Code/personal-proj" --quiet --commit) -join "`n"
if ($out -notmatch 'ai-sync: dev-context personal') { Fail "personal pack not announced: $out" }
if ($out -match 'WORK-RULE') { Fail "personal run leaked the work pack: $out" }
$local = Get-Content -Raw "$D19/Code/personal-proj/CLAUDE.local.md"
if ($local -notmatch 'PERSONAL-RULE') { Fail "personal rules not in CLAUDE.local.md" }
if ($local -notmatch 'personal-pref') { Fail "personal settings not in CLAUDE.local.md" }
if ($local -match 'WORK-RULE') { Fail "work rules written into a personal project" }
if (-not $local.Contains('Source: ../.ai-root/dev-context/')) { Fail "the note must name the .ai-root source" }
git -C "$D19/Code/personal-proj" check-ignore -q CLAUDE.local.md
if ($LASTEXITCODE -ne 0) { Fail "CLAUDE.local.md is not gitignored" }
$st = git -C "$D19/Code/personal-proj" status --porcelain
if ($st -match 'CLAUDE.local.md') { Fail "CLAUDE.local.md shows up in git status" }
$out = @(E "$D19/Code/personal-proj" --quiet) -join "`n"
if ($out -notmatch 'ai-sync: dev-context personal') { Fail "a settled project must still announce the pack: $out" }
if (git -C "$D19/Code/personal-proj" status --porcelain) { Fail "announcing the pack dirtied the tree" }
$before = [IO.File]::ReadAllBytes("$D19/Code/personal-proj/CLAUDE.local.md")
E "$D19/Code/personal-proj" --dry-run | Out-Null
$after = [IO.File]::ReadAllBytes("$D19/Code/personal-proj/CLAUDE.local.md")
if ([Convert]::ToBase64String($before) -ne [Convert]::ToBase64String($after)) { Fail "dry-run rewrote CLAUDE.local.md" }
New-Proj19 "$D19/WorkCode/work-proj"
$out = @(E "$D19/WorkCode/work-proj" --quiet --commit) -join "`n"
if ($out -notmatch 'ai-sync: dev-context work') { Fail "work pack not announced: $out" }
$local = Get-Content -Raw "$D19/WorkCode/work-proj/CLAUDE.local.md"
if ($local -notmatch 'WORK-RULE' -or $local -notmatch 'work-pref') { Fail "work pack missing from CLAUDE.local.md: $local" }
if ($local -match 'PERSONAL-RULE') { Fail "personal rules written into a work project" }
$out = @(E "$D19/WorkCode/work-proj") -join "`n"
if ($out -notmatch 'ai-sync: dev-context work') { Fail "a normal run must name the pack: $out" }
New-Proj "$S/other/proj"
$out = @(E "$S/other/proj" --quiet --commit) -join "`n"
if ($out -match 'dev-context') { Fail "a project outside both roots got a pack: $out" }
if (Test-Path "$S/other/proj/CLAUDE.local.md") { Fail "unscoped project must not grow CLAUDE.local.md" }
[IO.File]::WriteAllText("$S/other/proj/CLAUDE.local.md", "<!-- ai-templates: dev-context personal -->`nstale`n")
$out = @(E "$S/other/proj" --quiet) -join "`n"
if ($out) { Fail "removing a stale pack must stay quiet: $out" }
if (Test-Path "$S/other/proj/CLAUDE.local.md") { Fail "a pack we wrote must go when the project has no scope" }
New-Proj "$S/CodeWork/dropped"
$out = @(E "$S/CodeWork/dropped" --quiet --commit) -join "`n"
if ($out -match 'dev-context') { Fail "CodeWork is not a scope: $out" }
New-Proj "$S/Code/nopack"
$out = @(E "$S/Code/nopack" --quiet --commit) -join "`n"
if ($out -match 'dev-context') { Fail "a Code project outside a code root has no pack: $out" }
New-Proj19 "$D19/Code/foreign"
[IO.File]::WriteAllText("$D19/Code/foreign/CLAUDE.local.md", "my notes`n")
$out = @(E "$D19/Code/foreign" --quiet --commit) -join "`n"
if ($out -notmatch 'not ours') { Fail "a hand-written CLAUDE.local.md must be reported: $out" }
if ((Get-Content -Raw "$D19/Code/foreign/CLAUDE.local.md") -notmatch 'my notes') { Fail "a hand-written CLAUDE.local.md was overwritten" }
Move-Item "$NR/dev-context" "$S/dc19-away"
$out = @(E "$D19/Code/personal-proj" --quiet) -join "`n"
if ($out) { Fail "no pack must be silent: $out" }
if (Test-Path "$D19/Code/personal-proj/CLAUDE.local.md") { Fail "no pack must remove a pack we wrote" }
[IO.File]::WriteAllText("$D19/Code/personal-proj/CLAUDE.local.md", "<!-- ai-templates: dev-context personal -->`nkeep`n")
E "$D19/Code/personal-proj" --dry-run | Out-Null
if ((Get-Content -Raw "$D19/Code/personal-proj/CLAUDE.local.md") -notmatch 'keep') { Fail "dry-run removed CLAUDE.local.md" }
Move-Item "$S/dc19-away" "$NR/dev-context"
if ($IsWindows) {
  Write-Host "    (unreadable-pack half skipped on Windows)"
} else {
  & chmod 000 "$NR/dev-context/rules.md"
  New-Proj19 "$D19/Code/unreadable"
  $out = @(E "$D19/Code/unreadable" --quiet --commit) -join "`n"
  & chmod 644 "$NR/dev-context/rules.md"
  if ($out -notmatch 'cannot read \.ai-root/dev-context/rules\.md') { Fail "unreadable rules.md must be reported: $out" }
  $copy = Get-Content -Raw "$D19/Code/unreadable/CLAUDE.local.md"
  if ($copy -notmatch 'could not be read') { Fail "the copy must say the rules could not be read" }
  if ($copy -notmatch 'personal-pref') { Fail "settings must still be copied when rules cannot be read" }
}
$big = [byte[]]::new(20000)
for ($i = 0; $i -lt $big.Length; $i++) { $big[$i] = 65 }
[IO.File]::WriteAllBytes("$UR/dev-context/rules.md", $big)
Add-Content -LiteralPath "$UR/dev-context/rules.md" -Value 'TAIL-MARKER' -Encoding utf8
New-Proj19 "$D19/WorkCode/big"
$out = @(E "$D19/WorkCode/big" --quiet --commit) -join "`n"
if ($out -notmatch 'truncated') { Fail "an oversized rules.md must be truncated: $out" }
$copy = [IO.File]::ReadAllText("$D19/WorkCode/big/CLAUDE.local.md")
if ($copy -match 'TAIL-MARKER') { Fail "the truncated copy kept the tail" }
if ($copy -notmatch '\(truncated\)') { Fail "the copy must say it was truncated" }

Write-Host "--- 19b. work roots: the ~/.ai-work-roots list, environment.json kind, AI_WORK_ROOTS=none"
# Office is a code root of no special name: personal until a list or its environment.json says work.
$OR19 = "$D19/Office/.ai-root"
New-Item -ItemType Directory -Force -Path "$OR19/dev-context", "$OR19/projects" | Out-Null
[IO.File]::WriteAllText("$OR19/dev-context/rules.md", "OFFICE-RULE`n")
New-Proj19 "$D19/Office/office-proj"
function EW($Roots) {   # untyped: [string] would turn $null into ""
  if ($null -eq $Roots) { Remove-Item Env:AI_WORK_ROOTS -EA SilentlyContinue } else { $env:AI_WORK_ROOTS = $Roots }
  try { return (@(E "$D19/Office/office-proj" --quiet) -join "`n") } finally { $env:AI_WORK_ROOTS = 'WorkCode' }
}
$out = EW 'WorkCode'
if ($out -notmatch 'ai-sync: dev-context personal') { Fail "a root on no list is personal: $out" }
[IO.File]::WriteAllText("$env:HOME/.ai-work-roots", "# work roots`n`n  office  `r`n")
$out = EW $null
if ($out -notmatch 'ai-sync: dev-context work') { Fail "a ~/.ai-work-roots entry must make the root work: $out" }
$out = EW 'none'
if ($out -notmatch 'ai-sync: dev-context personal') { Fail "AI_WORK_ROOTS=none must not read ~/.ai-work-roots: $out" }
Remove-Item -LiteralPath "$env:HOME/.ai-work-roots" -Force
[IO.File]::WriteAllText("$OR19/environment.json", "{`"kind`": `"work`"}`n")
$out = EW 'none'
if ($out -notmatch 'ai-sync: dev-context work') { Fail "environment.json kind work must make the root work: $out" }
Remove-Item -LiteralPath "$OR19/environment.json" -Force
# The helper itself: a name matches a whole component, a path a whole-component prefix (any case).
@'
param([string]$Eng, [string]$P)
. $Eng
if (Test-WorkPath $P) { exit 0 }
exit 1
'@ | Set-Content -LiteralPath "$S/w19.ps1" -Encoding utf8
function W19([string]$Roots, [string]$P) {
  $env:AI_WORK_ROOTS = $Roots
  try { & pwsh -NoProfile -File "$S/w19.ps1" -Eng (Join-Path $T 'sync-ai-templates.ps1') -P $P | Out-Null; return ($LASTEXITCODE -eq 0) }
  finally { $env:AI_WORK_ROOTS = 'WorkCode' }
}
if (-not (W19 'office' "$D19/Office/x")) { Fail "a name entry must match a path component" }
if (W19 'offi' "$D19/Office/x") { Fail "a name entry must match a whole component" }
if (-not (W19 "$D19/OFFICE/" "$D19/Office/x")) { Fail "a path entry must match a prefix, case-insensitively" }
if (W19 "$D19/Off" "$D19/Office/x") { Fail "a path entry must match whole components" }
if (W19 'none' "$D19/Office/x") { Fail "AI_WORK_ROOTS=none must give no work root" }
if (-not (W19 'nope;office' "$D19/Office/x")) { Fail "AI_WORK_ROOTS takes several entries" }
