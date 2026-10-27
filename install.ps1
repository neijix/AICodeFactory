# AICodeFactory one-line install: clone (or update) the factory, then run `aicf setup`.
# PowerShell twin of install.sh; runs in Windows PowerShell 5.1 too (setup then needs pwsh 7).
#
#   irm https://raw.githubusercontent.com/neijix/AICodeFactory/HEAD/install.ps1 | iex
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/neijix/AICodeFactory/HEAD/install.ps1))) [options] [setup options]
#   pwsh -File install.ps1 [options] [setup options]
#
# Options: see the usage text below (or --help). Everything runs inside one script block: a
# download cut short runs nothing, and under `iex` it neither exits your shell nor changes its
# $ErrorActionPreference.

& {
  $ErrorActionPreference = 'Stop'
  $usage = @'
Usage: install.ps1 [options] [aicf setup options]

  --code-root DIR        folder holding your projects (default: $env:AI_CODE_ROOT, else ~/Code);
                         the factory goes to DIR/AICodeFactory
  --channel stable|main  stable (default; or $env:AICF_CHANNEL): the latest release, vX.Y.Z;
                         main: the development edge. A repo without a release gets main.
                         Recorded as `git config aicf.channel` in the checkout
  --repo URL             where to clone from (default: $env:AICF_REPO, else the GitHub repo)
  -h, --help             this help
Every other option goes to `aicf setup` (see `aicf setup --help`).

Run it again to update: an existing checkout is fast-forwarded to its channel, never reset;
one with uncommitted changes is refused. It never touches your projects; `aicf uninstall`
reverses the setup.
'@
  # git, stopping on failure (5.1 and 7 alike: no stderr redirection, so no NativeCommandError).
  function Invoke-G {
    & git @args
    if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed (exit $LASTEXITCODE)." }
  }
  function Get-G {
    $ErrorActionPreference = 'Continue'   # 5.1 turns redirected stderr into errors
    $out = & git @args 2>$null
    if ($LASTEXITCODE -ne 0) { return '' }
    return (@($out) | Select-Object -First 1) + ''
  }
  # Put <dest> on <branch> tracking <up>, fast-forward only: a diverged branch is refused, never reset.
  function Set-Ff([string]$Dest, [string]$Branch, [string]$Up) {
    if (Get-G -C $Dest rev-parse -q --verify "refs/heads/$Branch") {
      if ((Get-G -C $Dest symbolic-ref -q --short HEAD) -ne $Branch) { Invoke-G -C $Dest checkout -q $Branch }
      Invoke-G -C $Dest branch -q "--set-upstream-to=$Up" $Branch
      & git -C $Dest merge -q --ff-only $Up | Out-Null
      if ($LASTEXITCODE -ne 0) { throw "$Dest branch $Branch has commits that are not on $Up. Push or move them, then run this again." }
    } else {
      Invoke-G -C $Dest checkout -q -b $Branch --track $Up
    }
  }

  $repo = if ($env:AICF_REPO) { $env:AICF_REPO } else { 'https://github.com/neijix/AICodeFactory.git' }
  $root = if ($env:AI_CODE_ROOT) { $env:AI_CODE_ROOT } else { Join-Path $HOME 'Code' }
  $channel = if ($env:AICF_CHANNEL) { $env:AICF_CHANNEL } else { 'stable' }
  $setupArgs = @()
  $list = @($args)
  for ($i = 0; $i -lt $list.Count; $i++) {
    $a = [string]$list[$i]
    if ($a -cmatch '^--(repo|code-root|channel)=(.*)$') { $name = $Matches[1]; $val = $Matches[2] }
    elseif ($a -cin @('--repo', '--code-root', '--channel')) {
      if ($i + 1 -ge $list.Count) { throw "$a needs a value (see --help)." }
      $name = $a.Substring(2); $i++; $val = [string]$list[$i]
    }
    elseif ($a -cin @('-h', '--help')) { Write-Output $usage; return }
    else { $setupArgs += $a; continue }
    switch ($name) { 'repo' { $repo = $val } 'code-root' { $root = $val } 'channel' { $channel = $val } }
  }
  if ($channel -cnotin @('stable', 'main')) { throw "--channel is stable or main, not '$channel'." }
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git is required. Install it (winget install --id Git.Git -e), then run this again.' }

  New-Item -ItemType Directory -Force -Path $root | Out-Null
  $root = (Resolve-Path -LiteralPath $root).Path
  $dest = Join-Path $root 'AICodeFactory'
  if ((Test-Path -LiteralPath $dest) -and -not (Test-Path -LiteralPath (Join-Path $dest '.git'))) {
    throw "$dest exists and is not a git checkout. Move it away, or pick another --code-root."
  }
  if (Test-Path -LiteralPath $dest) {
    if (Get-G -C $dest status --porcelain --untracked-files=no) {
      throw "$dest has uncommitted changes. Commit or stash them (git -C `"$dest`" stash), then run this again."
    }
    Write-Output "Updating $dest"
    Invoke-G -C $dest fetch -q --tags origin
  } else {
    Write-Output "Cloning $repo into $dest"
    Invoke-G clone -q $repo $dest
  }

  $tag = ''
  if ($channel -eq 'stable') { $tag = Get-G -C $dest tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname }
  if ($channel -eq 'stable' -and -not $tag) {
    Write-Output 'No release yet: following main instead of stable.'
    $channel = 'main'
  }
  if ($channel -eq 'stable' -and (Get-G -C $dest rev-parse -q --verify refs/remotes/origin/stable)) {
    Set-Ff $dest 'stable' 'origin/stable'
    Write-Output "Channel: stable ($tag; the session-start pull follows each release)"
  } elseif ($channel -eq 'stable') {
    Invoke-G -C $dest -c advice.detachedHead=false checkout -q "refs/tags/$tag"
    Write-Output "Channel: stable (pinned at $tag; run this installer again to update)"
  } else {
    $main = Get-G -C $dest symbolic-ref -q --short refs/remotes/origin/HEAD
    if (-not $main) {
      $line = @(Get-G -C $dest ls-remote --symref origin HEAD) | Where-Object { $_ -match '^ref: refs/heads/(\S+)' } | Select-Object -First 1
      if ($line -and $line -match '^ref: refs/heads/(\S+)') { $main = "origin/$($Matches[1])" }
    }
    if (-not $main) { throw "cannot tell the default branch of $repo." }
    $branch = $main.Substring('origin/'.Length)
    Set-Ff $dest $branch $main
    Write-Output "Channel: main ($branch, the development edge)"
  }
  Invoke-G -C $dest config aicf.channel $channel

  Write-Output 'Running aicf setup'
  # A child process: under `iex` this session's execution policy may not allow running a file.
  $self = (Get-Process -Id $PID).Path
  $exe = if ($PSVersionTable.PSVersion.Major -ge 7) { $self } elseif (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { $self }
  & $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dest 'bin/aicf.ps1') setup @setupArgs
  if ($LASTEXITCODE -ne 0) { throw "aicf setup failed (exit $LASTEXITCODE)." }
} @args
