# Dot-sourced by tests/run-tests.ps1 after case 9c (its helpers, sandbox $env:HOME and $S/proj).
# Skills moved from <repo>/vscode-global/skills to <repo>/skills: what machines installed from the
# old path is re-pointed by the next --skills pass, never left stale or taken for another repo's.
Write-Host "--- 9d. installs from a moved skills source (vscode-global/skills -> skills) follow it"
$K = "$env:HOME/.claude/skills"
function First-Line($f) { @(Get-Content -LiteralPath $f -TotalCount 1)[0].Trim() }
$env:AI_SKILLS_MODE = 'copy'
# This repo: a copy stamped with its pre-move origin is ours, so it is re-copied and re-stamped.
Remove-Any "$K/bootstrap-ai"
New-Item -ItemType Directory -Force -Path "$K/bootstrap-ai" | Out-Null
'stale' | Set-Content "$K/bootstrap-ai/SKILL.md"
(Join-Path (Join-Path $T 'vscode-global') 'skills') | Set-Content "$K/bootstrap-ai/.ai-template-origin"
E "$S/proj" --skills --quiet | Out-Null
$o9d = First-Line "$K/bootstrap-ai/.ai-template-origin"
if ($o9d -ne (Join-Path $T 'skills')) { Fail "a pre-move copy was not re-stamped: $o9d" }
if (-not (Same "$T/skills/bootstrap-ai/SKILL.md" "$K/bootstrap-ai/SKILL.md")) { Fail "a pre-move copy was not refreshed" }
# An overlay installed from vscode-global/skills, then moved to skills/: the copy follows.
$OD = "$S/ov9d"
New-Item -ItemType Directory -Force -Path "$OD/vscode-global/skills/ov-moved" | Out-Null
[IO.File]::WriteAllText("$OD/vscode-global/skills/ov-moved/SKILL.md", "---`nname: ov-moved`n---`n")
$OD = (Resolve-Path $OD).Path
$env:AI_TEMPLATE_OVERLAY_DIR = $OD
try {
  E "$S/proj" --skills --quiet | Out-Null
  $o9d = if (Test-Path "$K/ov-moved/.ai-template-origin") { First-Line "$K/ov-moved/.ai-template-origin" } else { '' }
  if ($o9d -ne (Join-Path (Join-Path $OD 'vscode-global') 'skills')) { Fail "an old-layout overlay skill was not installed from vscode-global/skills: $o9d" }
  Move-Item -LiteralPath (Join-Path (Join-Path $OD 'vscode-global') 'skills') -Destination (Join-Path $OD 'skills')
  Remove-Item -LiteralPath (Join-Path $OD 'vscode-global') -Force
  E "$S/proj" --skills --quiet | Out-Null
  $o9d = First-Line "$K/ov-moved/.ai-template-origin"
  if ($o9d -ne (Join-Path $OD 'skills')) { Fail "the copy did not follow its moved source: $o9d" }
  if ($Symlinks) {
    # Links: one dangling (this repo's old path is gone), one into a leftover old folder (a stale
    # __pycache__ keeps vscode-global/skills/<name> alive): both are ours, both are re-linked.
    New-Item -ItemType Directory -Force -Path "$OD/vscode-global/skills/ov-moved/__pycache__" | Out-Null
    Remove-Any "$K/ov-moved"; Remove-Any "$K/bootstrap-ai"
    New-Item -ItemType SymbolicLink -Path "$K/ov-moved" -Target "$OD/vscode-global/skills/ov-moved" | Out-Null
    New-Item -ItemType SymbolicLink -Path "$K/bootstrap-ai" -Target "$T/vscode-global/skills/bootstrap-ai" | Out-Null
    $env:AI_SKILLS_MODE = 'link'
    E "$S/proj" --skills --quiet | Out-Null
    $l9d = (Get-Item "$K/ov-moved").LinkTarget
    if ([IO.Path]::GetFullPath($l9d) -ne [IO.Path]::GetFullPath((Join-Path (Join-Path $OD 'skills') 'ov-moved'))) { Fail "a link into the old folder was not re-linked: $l9d" }
    if ([IO.Path]::GetFullPath((Get-Item "$K/bootstrap-ai").LinkTarget) -ne [IO.Path]::GetFullPath((Join-Path (Join-Path $T 'skills') 'bootstrap-ai'))) { Fail "a dangling pre-move link was not re-linked" }
  }
} finally { $env:AI_TEMPLATE_OVERLAY_DIR = 'none' }
Remove-Any "$K/ov-moved"; Remove-Any $OD
Remove-Item Env:AI_SKILLS_MODE
