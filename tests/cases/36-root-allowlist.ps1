# Dot-sourced by tests/run-tests.ps1 ($T): the public root stays the product's. Twin: 36-root-allowlist.sh.
Write-Host "--- 36. the repo root holds only the product's entries"
# The target root of the public layout, the dev tooling beside it, and the dogfood copies: the first
# path component of every [POINTERS] and [LIVING_DOCS] destination of the manifest.
$allowed36 = @('README.md', 'LICENSE', 'CHANGELOG.md', 'CONTRIBUTING.md', 'SECURITY.md', '.editorconfig', '.gitignore', '.gitattributes',
  'install.sh', 'install.ps1', 'sync-ai-templates.sh', 'sync-ai-templates.ps1', 'templates-manifest.txt',
  'bin', 'engine', 'templates', 'skills', 'examples', 'docs', 'tests', '.github', '.githooks', '.code-health.json')
$section36 = ''
foreach ($line in [IO.File]::ReadAllLines((Join-Path $T 'templates-manifest.txt'))) {
  if ($line -match '^\[(\w+)\]') { $section36 = $Matches[1]; continue }
  if ($section36 -in 'POINTERS', 'LIVING_DOCS' -and $line.Contains('|')) { $allowed36 += ($line.Split('|')[1].Trim() -split '/')[0] }
}
$bad36 = @(git -C $T ls-files | ForEach-Object { ($_ -split '/')[0] } | Sort-Object -Unique | Where-Object { $_ -cnotin $allowed36 })
if ($bad36.Count -gt 0) { Fail "unexpected tracked entries at the repo root (move them, or extend the public layout): $($bad36 -join ' ')" }
