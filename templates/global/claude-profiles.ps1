# Claude Code profiles (AICodeFactory install-global; edit templates\global\claude-profiles.ps1 there):
# `claude` started inside a code root listed in ~\.claude-profiles runs with that root's
# CLAUDE_CONFIG_DIR (its own login, settings, memory and history). An explicit CLAUDE_CONFIG_DIR wins.
function claude {
  $cfg = $null
  $rec = Join-Path $HOME '.claude-profiles'
  if (-not $env:CLAUDE_CONFIG_DIR -and (Test-Path -LiteralPath $rec)) {
    $here = (Get-Location).ProviderPath.Replace('\', '/').TrimEnd('/') + '/'
    foreach ($line in Get-Content -LiteralPath $rec) {
      $root, $dir = $line -split "`t", 2
      if ($root -and $dir -and $here.StartsWith($root.Replace('\', '/').TrimEnd('/') + '/', [StringComparison]::OrdinalIgnoreCase)) { $cfg = $dir.Trim(); break }
    }
  }
  $exe = Get-Command claude -CommandType Application, ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $exe) { Write-Error 'claude: not found on PATH'; return }
  if (-not $cfg) { & $exe @args; return }
  $env:CLAUDE_CONFIG_DIR = $cfg
  try { & $exe @args } finally { Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue }
}
