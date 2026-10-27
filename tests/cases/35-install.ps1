# Dot-sourced by tests/run-tests.ps1 after case 34 ($F30, With-Env): the one-line installer, run the
# way `& ([scriptblock]::Create((irm …))) <args>` does, from a local bare clone into a fresh code
# root. Twin: 35-install.sh.
Write-Host "--- 35. install.ps1: clone + setup, fast-forward on a rerun, channels, a dirty checkout refused"
$R35 = Join-Path $S 'r35'; $H35 = Join-Path $R35 'home'; $B35 = Join-Path $R35 'aicf.git'; $D35 = Join-Path $R35 'Code/AICodeFactory'
New-Item -ItemType Directory -Force -Path $H35 | Out-Null
git clone -q --bare $F30 $B35 2>$null
if ($LASTEXITCODE -ne 0) { Fail "setup: bare clone of the engine under test" }
$br35 = git -C $B35 symbolic-ref --short HEAD   # the default branch, whatever the engine's checkout calls it
$url35 = 'file:///' + $B35.Replace('\', '/').TrimStart('/')
# The script text through a script block, as irm's output would be.
[IO.File]::WriteAllText("$R35/irm35.ps1", '$rest = @($args | Select-Object -Skip 1); & ([scriptblock]::Create([IO.File]::ReadAllText($args[0]))) @rest')
# IN35 <install args…> — install.ps1 on the sandbox profile; sets $rc35.
function IN35 {
  $a = @("$F30/install.ps1", '--repo', $url35, '--code-root', "$R35/Code") + $args
  With-Env @{ USERPROFILE = $H35; HOME = $H35; APPDATA = "$H35/AppData"; XDG_CONFIG_HOME = "$H35/.config"; XDG_STATE_HOME = "$R35/state"
    PYTHONDONTWRITEBYTECODE = '1'; AI_SKILLS_MODE = 'copy'; AI_SHELL_PROFILES = "$H35/rc35"; AI_CODE_ROOT = $null; AICF_REPO = $null; AICF_CHANNEL = $null } {
    $o = Out-Text (& pwsh -NoProfile -File "$R35/irm35.ps1" @a 2>&1 | ForEach-Object { "$_" })
    $script:rc35 = $LASTEXITCODE
    $o
  }
}
git clone -q $B35 "$R35/dev" 2>$null
if ($LASTEXITCODE -ne 0) { Fail "setup: a dev clone" }
# PUSH35 <file> <tag-or-empty> — one more commit on the bare repo's default branch (and a tag on it).
function PUSH35([string]$Name, [string]$Tag) {
  [IO.File]::AppendAllText("$R35/dev/$Name", "$Name`n")
  git -C "$R35/dev" add -A; git -C "$R35/dev" commit -qm $Name | Out-Null
  if ($Tag) { git -C "$R35/dev" tag $Tag }
  git -C "$R35/dev" push -q --tags origin "HEAD:$br35" 2>$null
  if ($LASTEXITCODE -ne 0) { Fail "setup: push $Name" }
}
function Git35 { $o = @(git -C $D35 @args 2>$null); return (($o | Select-Object -First 1) + '').Trim() }
$out = IN35
if ($rc35 -ne 0 -or -not (Test-Path "$D35/sync-ai-templates.ps1") -or -not (Test-Path "$H35/.claude/skills/bootstrap-ai") -or
    ([IO.Path]::GetFullPath([IO.File]::ReadAllText("$H35/.ai-template-dir").Trim()).TrimEnd('\', '/') -ne [IO.Path]::GetFullPath($D35).TrimEnd('\', '/'))) {
  Fail "install.ps1 must clone into <code root>/AICodeFactory and run setup there (rc=$rc35): $out"
}
if ($out -notmatch '(?m)^No release yet: following main instead of stable\.\r?$' -or (Git35 config aicf.channel) -ne 'main' -or
    (Git35 symbolic-ref --short HEAD) -ne $br35) {
  Fail "no tag: the stable default falls back to main, recorded: $out"
}
# A rerun fast-forwards.
PUSH35 one35 ''
$out = IN35
if ($rc35 -ne 0 -or -not (Test-Path "$D35/one35") -or (Git35 rev-parse HEAD) -ne (git -C $B35 rev-parse $br35) -or $out -notmatch '(?m)^Updating ') {
  Fail "a rerun must fast-forward the checkout (rc=$rc35): $out"
}
# stable: the latest vX.Y.Z tag (pinned while origin has no stable branch), then the stable branch.
PUSH35 two35 v0.1.0; PUSH35 three35 v0.2.0; PUSH35 four35 ''
$out = IN35 --channel stable
if ($rc35 -ne 0 -or (Git35 rev-parse HEAD) -ne (git -C $B35 rev-parse 'v0.2.0^{commit}') -or (Git35 config aicf.channel) -ne 'stable' -or
    $out -notmatch '(?m)^Channel: stable \(pinned at v0\.2\.0; run this installer again to update\)\r?$') {
  Fail "stable without a stable branch is the latest tag, pinned (rc=$rc35): $out"
}
git -C "$R35/dev" push -q origin 'v0.2.0^{commit}:refs/heads/stable' 2>$null
if ($LASTEXITCODE -ne 0) { Fail "setup: push the stable branch" }
$out = IN35 --channel=stable
if ($rc35 -ne 0 -or (Git35 rev-parse --abbrev-ref --symbolic-full-name '@{u}') -ne 'origin/stable') { Fail "stable must track origin/stable (rc=$rc35): $out" }
$out = IN35 --channel main
if ($rc35 -ne 0 -or (Git35 symbolic-ref --short HEAD) -ne $br35 -or -not (Test-Path "$D35/four35") -or (Git35 config aicf.channel) -ne 'main') {
  Fail "--channel main returns to the default branch, up to date (rc=$rc35): $out"
}
# A dirty checkout is refused before anything moves.
PUSH35 five35 ''
[IO.File]::AppendAllText("$D35/README.md", "local edit`n")
$out = IN35
if ($rc35 -eq 0 -or $out -notmatch 'has uncommitted changes' -or (Test-Path "$D35/five35") -or
    -not (Select-String -LiteralPath "$D35/README.md" -SimpleMatch 'local edit' -Quiet)) {
  Fail "a dirty checkout must be refused, untouched (rc=$rc35): $out"
}
$out = IN35 --channel edge
if ($rc35 -eq 0 -or $out -notmatch 'stable or main') { Fail "an unknown channel is refused (rc=$rc35): $out" }
