# Dot-sourced by tests/run-tests.ps1 after case 30 ($F30): aicf uninstall is the exact reverse of
# aicf setup on a home that already holds the user's own files. Twin: 34-uninstall.sh.
Write-Host "--- 34. aicf uninstall: a preview changes nothing, --yes gives the home back byte for byte"
# With-Env <hashtable> <scriptblock> — run with these environment variables ($null removes one), then restore them.
function With-Env([hashtable]$Vars, [scriptblock]$Do) {
  $saved = @{}; foreach ($k in $Vars.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k) }
  try {
    foreach ($k in $Vars.Keys) { if ($null -eq $Vars[$k]) { Remove-Item "Env:$k" -EA SilentlyContinue } else { Set-Item "Env:$k" $Vars[$k] } }
    & $Do
  } finally {
    foreach ($k in $saved.Keys) { if ($null -eq $saved[$k]) { Remove-Item "Env:$k" -EA SilentlyContinue } else { Set-Item "Env:$k" $saved[$k] } }
  }
}
# Snap <dir> — every path under <dir>: D, L (with its target) or F (with a hash). pwsh's own startup
# cache (AppData\Local\Microsoft\PowerShell, ~/.cache/powershell, ~/.local/share/powershell) is not ours.
function Snap([string]$Dir) {
  $base = (Resolve-Path -LiteralPath $Dir).Path.TrimEnd('\', '/')
  @(Get-ChildItem -LiteralPath $base -Recurse -Force | ForEach-Object {
    $rel = $_.FullName.Substring($base.Length + 1).Replace('\', '/')
    if ($rel -match '^(AppData/Local/Microsoft(/PowerShell(/|$)|$)|AppData/Local$|\.cache(/powershell(/|$)|$)|\.local(/share(/powershell(/|$)|$)|$))') { return }
    if ($_.LinkType) { "L $rel -> $($_.Target)" }
    elseif ($_.PSIsContainer) { "D $rel" }
    else { "F $rel $((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" }
  } | Sort-Object) -join "`n"
}
$R34 = Join-Path $S 'r34'; $C34 = Join-Path $R34 'Code'; $F34 = Join-Path $C34 'AICodeFactory'; $H34 = Join-Path $R34 'home'
New-Item -ItemType Directory -Force -Path "$C34/.ai-root", "$H34/.claude/skills/foreign", "$H34/.claude/skills/mine" | Out-Null
git clone -q $F30 $F34 2>$null
if ($LASTEXITCODE -ne 0) { Fail "setup: clone the engine under test" }
git -C $F34 remote remove origin
# The user's own things, which must survive: a settings file with other keys, a shell profile, a
# skill another template repo installed, an unmarked skill, and a Claude profile (more roots).
[IO.File]::WriteAllText("$C34/.ai-root/claude-profile.json", "{`"config_dir`": `"~/.claude-code`"}`n")
[IO.File]::WriteAllText("$H34/rc34", "export FOO=1`n")
[IO.File]::WriteAllText("$H34/.claude/skills/foreign/SKILL.md", "x`n")
[IO.File]::WriteAllText("$H34/.claude/skills/foreign/.ai-template-origin", "/elsewhere/skills`n")
[IO.File]::WriteAllText("$H34/.claude/skills/mine/SKILL.md", "y`n")
[IO.File]::WriteAllText("$H34/.claude/settings.json", "{`n  `"model`": `"opus`",`n  `"env`": {`n    `"FOO`": `"1`"`n  }`n}`n")
# AI34 <aicf args…> — bin/aicf.ps1 on the sandbox profile; sets $rc34.
function AI34 {
  $a = $args
  With-Env @{ USERPROFILE = $H34; HOME = $H34; APPDATA = "$H34/AppData"; XDG_CONFIG_HOME = "$H34/.config"; XDG_STATE_HOME = "$R34/state"
    PYTHONDONTWRITEBYTECODE = '1'; AI_SKILLS_MODE = 'copy'; AI_SHELL_PROFILES = "$H34/rc34" } {
    $o = Out-Text (& pwsh -NoProfile -File "$F34/bin/aicf.ps1" @a 2>&1 | ForEach-Object { "$_" })
    $script:rc34 = $LASTEXITCODE
    $o
  }
}
AI34 --version | Out-Null   # pwsh's first-run files (AppData\Local in the sandbox home) exist before the snapshot
$before34 = Snap $H34
$out = AI34 setup
if ($rc34 -ne 0 -or -not (Test-Path "$H34/.claude-code/skills/bootstrap-ai") -or -not (Test-Path "$H34/.ai-template-dir") -or
    -not (Select-String -LiteralPath "$H34/rc34" -SimpleMatch 'AICodeFactory claude-profiles' -Quiet)) {
  Fail "setup must install the profile's skills, the rc block and the marker (the case needs them; rc=$rc34): $out"
}
$setup34 = Snap $H34
$out = AI34 uninstall
if ($rc34 -ne 0) { Fail "the preview failed: $out" }
if ((Snap $H34) -ne $setup34) { Fail "the preview must change nothing: $out" }
if ($out -notmatch '(?m)^Preview' -or @($out -split "`n")[-1] -notmatch 'aicf uninstall --yes' -or
    -not $out.Contains("[remove] $(Join-Path $H34 '.ai-template-dir')") -or -not $out.Contains("[edit]   $(Join-Path $H34 '.claude/settings.json')")) {
  Fail "the preview must list what --yes removes and edits: $out"
}
$out = AI34 uninstall --yes
if ($rc34 -ne 0) { Fail "uninstall --yes failed: $out" }
$after34 = Snap $H34
if ($after34 -ne $before34) {
  Fail "uninstall --yes must give the home back exactly: $(Compare-Object ($before34 -split "`n") ($after34 -split "`n") | Select-Object -First 20 | Out-String)"
}
if (-not (Test-Path "$C34/.ai-root/claude-profile.json") -or (git -C $F34 status --porcelain)) { Fail "uninstall must leave .ai-root and the checkout alone" }
$out = AI34 uninstall
if ($rc34 -ne 0 -or $out -notmatch '(?m)^Nothing of aicf setup is installed for this checkout\.\r?$') { Fail "a second uninstall finds nothing: $out" }
$out = AI34 uninstall --bogus
if ($rc34 -ne 2) { Fail "an unknown option is exit 2 (rc=$rc34): $out" }
$out = AI34 uninstall --help
if ($rc34 -ne 0 -or $out -notmatch 'Usage: aicf uninstall') { Fail "--help prints the usage: $out" }
