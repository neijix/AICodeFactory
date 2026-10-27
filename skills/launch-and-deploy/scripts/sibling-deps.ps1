# Sibling-repo dependencies (launch-and-deploy skill; canonical copy in AICodeFactory, copy it
# unchanged into an app's scripts\). Twin of sibling-deps.sh: every repo listed in the app's
# sibling-deps.txt is cloned beside the app when missing, fast-forwarded when its tree is clean
# (at most once a day; every time with update), then its own idempotent install.ps1 -Start runs.
# Never fails the caller: a dependency that cannot be fetched or installed is a warning line.
#
# Usage: scripts\sibling-deps.ps1 [start|update]      (install and start scripts: start)
# sibling-deps.txt, one per line:  NAME  GIT_URL  [DIR_ENV_VAR]     (# starts a comment)
# Lookup: $DIR_ENV_VAR when set, else $AI_CODE_ROOT\NAME, ~\Code\NAME, ..\NAME; a clone goes to
# $DIR_ENV_VAR when set, else ..\NAME. Plain ASCII: Windows PowerShell 5.1 too.
param([string]$Mode = 'start')
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$parent = Split-Path -Parent $root
$list = Join-Path $root 'sibling-deps.txt'
if (-not (Test-Path -LiteralPath $list)) { exit 0 }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host '  ! git not found - sibling dependencies not checked'
    exit 0
}

function Get-DepDir([string]$Name, [string]$Var) {
    if ($Var) {
        $explicit = [Environment]::GetEnvironmentVariable($Var)
        if ($explicit) { return $explicit -replace '^~', $HOME }
    }
    foreach ($base in @($env:AI_CODE_ROOT, (Join-Path $HOME 'Code'), $parent)) {
        if ($base -and (Test-Path -LiteralPath (Join-Path (Join-Path $base $Name) '.git'))) {
            return (Join-Path $base $Name)
        }
    }
    return (Join-Path $parent $Name)
}

$shell = (Get-Process -Id $PID).Path
foreach ($line in Get-Content -LiteralPath $list) {
    $fields = @((($line -split '#', 2)[0]).Trim() -split '\s+' | Where-Object { $_ })
    if ($fields.Count -eq 0) { continue }
    $name = $fields[0]
    if ($fields.Count -lt 2) { Write-Host "  ! sibling-deps.txt: no URL for $name - skipped"; continue }
    $url = $fields[1]
    $var = if ($fields.Count -gt 2) { $fields[2] } else { '' }
    $dir = Get-DepDir $name $var
    if (-not (Test-Path -LiteralPath (Join-Path $dir '.git'))) {
        Write-Host "Fetching dependency $name into $dir..."
        git clone --quiet $url $dir 2>&1 | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  ! could not clone $name ($url) - clone it beside this app, then start again"
            continue
        }
    } else {
        $fetchHead = Join-Path $dir '.git\FETCH_HEAD'
        $stale = (-not (Test-Path -LiteralPath $fetchHead)) -or
                 ((Get-Item -LiteralPath $fetchHead).LastWriteTime -lt (Get-Date).AddDays(-1))
        if (($Mode -eq 'update' -or $stale) -and -not (git -C $dir status --porcelain 2>$null)) {
            $env:GIT_TERMINAL_PROMPT = '0'
            git -C $dir pull --ff-only --quiet 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Host "  ! ${name}: could not fast-forward (offline, or another branch) - using it as is"
            }
            Remove-Item Env:GIT_TERMINAL_PROMPT -ErrorAction SilentlyContinue
        }
    }
    $installer = Join-Path $dir 'install.ps1'
    if (Test-Path -LiteralPath $installer) {
        & $shell -NoProfile -ExecutionPolicy Bypass -File $installer -Start | Out-Host
        if ($LASTEXITCODE -ne 0) { Write-Host "  ! ${name}: install.ps1 failed - continuing without it" }
    }
}
exit 0
