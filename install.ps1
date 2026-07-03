# install.ps1 - claude-issue-triage installer (Windows PowerShell 5.1+)
#
# Run from YOUR PROJECT ROOT (the git repo you want triage to manage):
#   irm https://raw.githubusercontent.com/kiminyeob/claude-issue-triage/main/install.ps1 | iex
# or from a local clone of this kit:
#   powershell -NoProfile -ExecutionPolicy Bypass -File <kit>\install.ps1
#
# What it does (safe by default - never overwrites your existing files):
#   1. copies template\.claude\{commands,automation} into .\.claude\
#   2. creates .\.claude\settings.json with your project path substituted
#      (if one already exists -> writes settings.triage-suggested.json for manual merge)
#   3. appends triage-local entries to .gitignore (idempotent)
#   4. copies CLAUDE-md-snippet.md for you to paste into your CLAUDE.md
# Env overrides: $env:TRIAGE_REPO_URL (source repo), $env:TRIAGE_FORCE=1 (overwrite files)

$ErrorActionPreference = 'Stop'

$RepoUrl = $env:TRIAGE_REPO_URL
if (-not $RepoUrl) { $RepoUrl = 'https://github.com/kiminyeob/claude-issue-triage' }
$Force = ($env:TRIAGE_FORCE -eq '1')

$Target = (Get-Location).Path
Write-Host ""
Write-Host "claude-issue-triage installer" -ForegroundColor Cyan
Write-Host "  target project: $Target"

if (-not (Test-Path (Join-Path $Target '.git'))) {
  Write-Host "[ABORT] current directory is not a git repository." -ForegroundColor Red
  Write-Host "        cd into your project root first, then re-run the installer."
  exit 1
}

# --- locate the template: local checkout first, otherwise clone to temp -------------------
$src = $null
$tempClone = $null
if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'template'))) {
  $src = Join-Path $PSScriptRoot 'template'
  Write-Host "  source: local checkout ($PSScriptRoot)"
} else {
  $git = (Get-Command git -ErrorAction SilentlyContinue)
  if (-not $git) { Write-Host "[ABORT] git not found on PATH." -ForegroundColor Red; exit 1 }
  $tempClone = Join-Path $env:TEMP ("claude-issue-triage-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
  Write-Host "  source: cloning $RepoUrl ..."
  git clone --depth 1 --quiet $RepoUrl $tempClone
  if ($LASTEXITCODE -ne 0) { Write-Host "[ABORT] git clone failed." -ForegroundColor Red; exit 1 }
  $src = Join-Path $tempClone 'template'
}
if (-not (Test-Path $src)) { Write-Host "[ABORT] template folder not found in source." -ForegroundColor Red; exit 1 }

# --- project path in Claude Code permission syntax: C:\Users\x\proj -> //c/Users/x/proj ----
$permPath = $Target -replace '\\', '/'
if ($permPath -match '^([A-Za-z]):(.*)$') {
  $permPath = '/' + $Matches[1].ToLower() + $Matches[2]
}
$permPath = '/' + $permPath   # leading double-slash form

$copied = @(); $skipped = @()

function Copy-TemplateFile([string]$rel) {
  $from = Join-Path $src $rel
  $to = Join-Path $Target $rel
  $dir = Split-Path $to -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  if ((Test-Path $to) -and -not $script:Force) { $script:skipped += $rel; return }
  Copy-Item -Path $from -Destination $to -Force
  $script:copied += $rel
}

# --- 1) commands + automation --------------------------------------------------------------
$relFiles = @(
  '.claude\commands\issue-triage.md',
  '.claude\commands\session-briefing.md',
  '.claude\commands\resolve-issue.md',
  '.claude\automation\run-triage.ps1',
  '.claude\automation\run-triage.sh',
  '.claude\automation\register-task.ps1',
  '.claude\automation\register-cron.sh',
  '.claude\automation\guard.js'
)
foreach ($rel in $relFiles) { Copy-TemplateFile $rel }

# --- 2) settings.json (substitute {{PROJECT_PATH}}; never clobber an existing one) ---------
$settingsSrc = Get-Content -Path (Join-Path $src '.claude\settings.json') -Raw
$settingsOut = $settingsSrc -replace '\{\{PROJECT_PATH\}\}', $permPath
$settingsPath = Join-Path $Target '.claude\settings.json'
if (Test-Path $settingsPath) {
  $suggested = Join-Path $Target '.claude\settings.triage-suggested.json'
  [System.IO.File]::WriteAllText($suggested, $settingsOut, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host "  [merge needed] .claude\settings.json already exists." -ForegroundColor Yellow
  Write-Host "                 wrote .claude\settings.triage-suggested.json - merge its permissions.deny/allow"
  Write-Host "                 and hooks into your settings.json (or ask Claude Code to merge them)."
} else {
  [System.IO.File]::WriteAllText($settingsPath, $settingsOut, (New-Object System.Text.UTF8Encoding($false)))
  $copied += '.claude\settings.json'
}

# --- 3) .gitignore (idempotent block) ------------------------------------------------------
$giPath = Join-Path $Target '.gitignore'
$marker = '# claude-issue-triage (local runtime files)'
$block = @(
  $marker,
  '.claude/automation/log.md',
  '.claude/automation/decisions/',
  '.claude/automation/cron.log',
  '.claude/automation/*.tmp',
  '.claude/automation/*.tmp.md',
  '.claude/automation/*.secret',
  '.claude/settings.triage-suggested.json'
) -join "`n"
$gi = ''
if (Test-Path $giPath) { $gi = Get-Content -Path $giPath -Raw }
if ($gi -notmatch [regex]::Escape($marker)) {
  $sep = ''
  if ($gi -and -not $gi.EndsWith("`n")) { $sep = "`n" }
  [System.IO.File]::AppendAllText($giPath, "$sep`n$block`n", (New-Object System.Text.UTF8Encoding($false)))
  Write-Host "  .gitignore: triage entries appended"
} else {
  Write-Host "  .gitignore: already contains triage entries (skipped)"
}

# --- 4) CLAUDE.md snippet (lives at template root, lands under .claude\) -------------------
Copy-Item -Path (Join-Path $src 'CLAUDE-md-snippet.md') -Destination (Join-Path $Target '.claude\CLAUDE-md-snippet.md') -Force
$copied += '.claude\CLAUDE-md-snippet.md'

# --- cleanup temp clone --------------------------------------------------------------------
if ($tempClone -and (Test-Path $tempClone)) {
  try { Remove-Item -Path $tempClone -Recurse -Force -ErrorAction Stop } catch {}
}

# --- summary + next steps ------------------------------------------------------------------
Write-Host ""
Write-Host "installed files:" -ForegroundColor Green
foreach ($f in $copied) { Write-Host "  + $f" }
if ($skipped.Count -gt 0) {
  Write-Host "kept existing (not overwritten - set TRIAGE_FORCE=1 to overwrite):" -ForegroundColor Yellow
  foreach ($f in $skipped) { Write-Host "  = $f" }
}
Write-Host ""
Write-Host "NEXT STEPS" -ForegroundColor Cyan
Write-Host "  1. edit .claude\commands\issue-triage.md - top block: verify commands + project rules"
Write-Host "  2. paste .claude\CLAUDE-md-snippet.md into your project's CLAUDE.md"
Write-Host "  3. gh auth login   (GitHub CLI must be authenticated for issues)"
Write-Host "  4. claude setup-token -> save the token into .claude\automation\oauth-token.secret"
Write-Host "  5. register the daily schedule:"
Write-Host "       powershell -NoProfile -ExecutionPolicy Bypass -File .\.claude\automation\register-task.ps1"
Write-Host "  6. test now:  Start-ScheduledTask -TaskName ('IssueTriage-' + (Split-Path (Get-Location) -Leaf))"
Write-Host "     then check .claude\automation\cron.log"
Write-Host ""
Write-Host "docs: $RepoUrl/tree/main/docs"
