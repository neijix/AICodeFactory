# Dot-sourced by tests/run-tests.ps1 after case 15b (its helpers and sandbox). An overlay still in
# the old layout (<x>.template and .append at its root, vscode-global/skills) keeps working, read
# after the new paths, with one note per run; once moved to templates/ and skills/ the note is gone.
Write-Host "--- 15c. an overlay in the old layout still renders, with one note per run, until it moves"
$OO = "$S/ov-old"; $PO = "$S/proj-oo"
New-Item -ItemType Directory -Force -Path "$OO/templates", "$OO/.claude/commands", "$OO/vscode-global/skills/old-sk", $PO | Out-Null
$OO = (Resolve-Path $OO).Path
[IO.File]::WriteAllText("$OO/CLAUDE.md.template", "OLD-OVERRIDE`n")
[IO.File]::WriteAllText("$OO/templates/CLAUDE.md.template", "NEW-OVERRIDE`n")   # either layout: the base wins
[IO.File]::WriteAllText("$OO/copilot-instructions.md.template.append", "OLD-FRAG`n")
[IO.File]::WriteAllText("$OO/.claude/commands/mine.md.template", "OLD-MINE`n")
[IO.File]::WriteAllText("$OO/overlay-manifest.txt", "[POINTERS]`n.claude/commands/mine.md.template|.claude/commands/mine.md`nAGENTS.md.template|extra-agents.md`n")
[IO.File]::WriteAllText("$OO/vscode-global/skills/old-sk/SKILL.md", "---`nname: old-sk`n---`n")
git -C $PO init -q
function Check-OO($when) {   # the rendering both layouts must give
  if (-not (Same "$T/templates/CLAUDE.md.template" "$PO/CLAUDE.md")) { Fail "${when}: an overlay CLAUDE.md.template replaced the base" }
  $want = [IO.File]::ReadAllText("$T/templates/copilot-instructions.md.template") + "OLD-FRAG`n"
  if ([IO.File]::ReadAllText("$PO/.github/copilot-instructions.md") -cne $want) { Fail "${when}: the .append fragment was not rendered" }
  if ([IO.File]::ReadAllText("$PO/.claude/commands/mine.md") -cne "OLD-MINE`n") { Fail "${when}: the overlay's own pointer was not rendered" }
  if (-not (Same "$T/templates/AGENTS.md.template" "$PO/extra-agents.md")) { Fail "${when}: a manifest entry without templates/ lost the base file" }
}
function EOO { $env:AI_TEMPLATE_OVERLAY_DIR = $OO; $env:AI_SKILLS_MODE = 'copy'; try { @(E @args) -join "`n" } finally { $env:AI_TEMPLATE_OVERLAY_DIR = 'none'; Remove-Item Env:AI_SKILLS_MODE -EA SilentlyContinue } }
$out = EOO $PO --skills
if (@(($out -split "`n") | Where-Object { $_ -cmatch 'overlay uses the old layout' }).Count -ne 1) { Fail "the old-layout note must print once per run: $out" }
if (@($out -split "`n") -cnotcontains 'ai-sync: overlay uses the old layout (.claude/commands/mine.md.template, CLAUDE.md.template, copilot-instructions.md.template.append, …) — move it to templates/ and skills/') {
  Fail "the old-layout note must name what to move: $out"
}
Check-OO 'old layout'
$oo15 = "$env:HOME/.claude/skills/old-sk/.ai-template-origin"
$got = if (Test-Path $oo15) { @(Get-Content -LiteralPath $oo15 -TotalCount 1)[0].Trim() } else { '' }
if ($got -ne (Join-Path (Join-Path $OO 'vscode-global') 'skills')) { Fail "a skill under the old vscode-global/skills was not installed: $got" }
# Move it to the new layout: same rendering, no note, the skill copy follows its source.
Remove-Item -LiteralPath "$OO/CLAUDE.md.template"
Move-Item -LiteralPath "$OO/copilot-instructions.md.template.append" -Destination "$OO/templates/"
Move-Item -LiteralPath "$OO/.claude" -Destination "$OO/templates/.claude"
Move-Item -LiteralPath "$OO/vscode-global/skills" -Destination "$OO/skills"; Remove-Item -LiteralPath "$OO/vscode-global"
[IO.File]::WriteAllText("$OO/overlay-manifest.txt", "[POINTERS]`ntemplates/.claude/commands/mine.md.template|.claude/commands/mine.md`ntemplates/AGENTS.md.template|extra-agents.md`n")
$out = EOO $PO --skills
if ($out -match 'old layout') { Fail "a new-layout overlay must not get the note: $out" }
Check-OO 'new layout'
$got = @(Get-Content -LiteralPath $oo15 -TotalCount 1)[0].Trim()
if ($got -ne (Join-Path $OO 'skills')) { Fail "the skill copy did not follow the move: $got" }
Remove-Any "$env:HOME/.claude/skills/old-sk"; Remove-Any $OO
