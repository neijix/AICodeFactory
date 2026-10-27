# Dot-sourced by tests/run-tests.ps1 (its helpers and sandbox). The template repo syncing itself
# takes no overlay (no fragment, no override, no overlay-manifest entry): its pointer copies stay
# the base ones, while a project synced by the same engine gets the overlay.
Write-Host "--- 15b. the template repo syncing itself takes no overlay; its projects still do"
$ST = "$S/selftpl"
New-Item -ItemType Directory -Force -Path $ST, "$S/proj-st", "$S/ov-st/templates" | Out-Null
Get-ChildItem -LiteralPath $T -Force | Where-Object { $_.Name -ne '.git' } | Copy-Item -Destination $ST -Recurse -Force
[IO.File]::WriteAllText("$S/ov-st/templates/CLAUDE.md.template.append", "ST-FRAGMENT`n")
[IO.File]::WriteAllText("$S/ov-st/overlay-manifest.txt", "[POINTERS]`ntemplates/CLAUDE.md.template|st-extra.md`n")
git -C $ST init -q; git -C "$S/proj-st" init -q
$env:AI_TEMPLATE_OVERLAY_DIR = "$S/ov-st"
function EST { $o = & pwsh -NoProfile -File "$ST/sync-ai-templates.ps1" @args; if ($LASTEXITCODE -ne 0) { Fail "engine exited $LASTEXITCODE" }; return $o }
EST "$S/proj-st" | Out-Null
if ((Get-Content "$S/proj-st/CLAUDE.md")[-1] -cne 'ST-FRAGMENT') { Fail "a project must get the overlay fragment" }
if (-not (Test-Path "$S/proj-st/st-extra.md")) { Fail "a project must get the overlay-manifest pointer" }
EST $ST | Out-Null
if (-not (Same "$ST/templates/CLAUDE.md.template" "$ST/CLAUDE.md")) { Fail "the template repo must not take the overlay fragment: $((Get-Content "$ST/CLAUDE.md")[-1])" }
if (Test-Path "$ST/st-extra.md") { Fail "the template repo must not take overlay-manifest entries" }
$out = EST "$S/proj-st" --quiet; if ($out) { Fail "a project after the template repo must still settle: $out" }
$env:AI_TEMPLATE_OVERLAY_DIR = 'none'
