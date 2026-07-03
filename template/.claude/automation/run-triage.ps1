# run-triage.ps1 - wrapper run by Windows Task Scheduler (claude-issue-triage kit)
#
# What it does: cd to project root -> launch claude headless + dontAsk to run /issue-triage
#   -> append stdout/stderr with timestamps to cron.log
#   -> extract '@@LOG@@ <line>' summary lines from claude's output and append them to log.md.
#      (Headless claude CANNOT Write into .claude/ - it is a protected dir and dontAsk blocks all
#       Write - so this wrapper, being plain PowerShell with no tool-permission model, writes log.md.)
# Scheduled-run only. For manual checks, just type /issue-triage in an interactive session.
#
# IMPORTANT: keep this file ASCII-only. Windows PowerShell 5.1 reads BOM-less files as ANSI (CP949 etc.),
#   which corrupts non-ASCII string literals -> mojibake in cron.log. ASCII markers avoid that.
#   Non-ASCII text from claude's own stdout is preserved by the UTF-8 console encoding set below.

$ErrorActionPreference = 'Continue'

# ===== EDIT HERE: model used for scheduled (headless) runs ==================================
$TriageModel = 'claude-sonnet-5'
# ============================================================================================

# Decode native-command (claude) stdout as UTF-8 so non-ASCII output is captured without mojibake.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [System.Text.Encoding]::UTF8

# --- paths: project root derived from script location (<root>\.claude\automation) ---
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$LogFile     = Join-Path $PSScriptRoot 'cron.log'
$TriageLog   = Join-Path $PSScriptRoot 'log.md'

# --- prepend key tool paths to PATH (logon session PATH may miss them; dupes are harmless) ---
$extraPaths = @(
  "$env:USERPROFILE\.local\bin",     # claude.exe
  'C:\Program Files\GitHub CLI',     # gh
  'C:\Program Files\Git\cmd',        # git
  'C:\Program Files\nodejs'          # node (guard.js hook)
) | Where-Object { Test-Path $_ }
$env:PATH = ($extraPaths -join ';') + ';' + $env:PATH

# --- locate claude executable ---
$claude = (Get-Command claude -ErrorAction SilentlyContinue).Source
if (-not $claude) { $claude = "$env:USERPROFILE\.local\bin\claude.exe" }

$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
Set-Location $ProjectRoot

Add-Content -Path $LogFile -Value "" -Encoding utf8
Add-Content -Path $LogFile -Value "===== [$stamp] (scheduled) issue-triage START =====" -Encoding utf8

if (-not (Test-Path $claude)) {
  Add-Content -Path $LogFile -Value "[ERROR] claude executable not found: $claude" -Encoding utf8
  exit 1
}

# --- TLS: trust a corporate SSL-inspection CA if present ---
# Node uses its OWN CA store (not Windows'), so a TLS-intercepting proxy causes
# "UNABLE_TO_VERIFY_LEAF_SIGNATURE". Point NODE_EXTRA_CA_CERTS at a PEM bundle exported from the
# Windows root store. See docs/troubleshooting.md for the one-liner that builds the bundle.
# Only set if the environment did not already provide one, and only if the bundle exists.
if (-not $env:NODE_EXTRA_CA_CERTS) {
  $caBundle = Join-Path $env:USERPROFILE '.claude\corp-ca-bundle.pem'
  if (Test-Path $caBundle) { $env:NODE_EXTRA_CA_CERTS = $caBundle }
}

# --- auth: inject a long-lived token for the unattended run (claude setup-token) ---
# Interactive OAuth login creds (~/.claude/.credentials.json) expire roughly nightly and are NOT
# refreshed reliably in a headless -p run -> "401 Invalid authentication credentials" the next day.
# Store the token printed by 'claude setup-token' in the gitignored file below; we export it here
# so every scheduled run presents a valid, long-lived credential regardless of the login token.
$TokenFile = Join-Path $PSScriptRoot 'oauth-token.secret'
if (Test-Path $TokenFile) {
  $tok = (Get-Content -Path $TokenFile -Raw).Trim()
  if ($tok) { $env:CLAUDE_CODE_OAUTH_TOKEN = $tok }
}
if (-not $env:CLAUDE_CODE_OAUTH_TOKEN) {
  Add-Content -Path $LogFile -Value "[WARN] CLAUDE_CODE_OAUTH_TOKEN not set (missing $TokenFile). Falling back to interactive login creds, which expire nightly and may 401. Fix: run 'claude setup-token' and save its output into that file." -Encoding utf8
}

# Headless + dontAsk. 'headless' arg tells the command no human is present.
# dontAsk keeps the deny rules + guard.js hook AND blocks all Write (safe) - which is exactly
#   why the headless run cannot write log.md/decisions itself; this wrapper writes log.md below.
# Capture output to a var, then log -> $LASTEXITCODE reflects claude's real exit code.
$code = 1
try {
  $out = & $claude -p "/issue-triage headless" --permission-mode dontAsk --model $TriageModel 2>&1
  $code = $LASTEXITCODE
} catch {
  $out = "[ERROR] claude launch exception: $($_.Exception.Message)"
}
if ($out) { $out | Out-File -FilePath $LogFile -Append -Encoding utf8 }

# --- log.md: append the '@@LOG@@ <one-line>' summaries claude printed for each processed issue.
# claude cannot write .claude/ itself, so it emits markers to stdout (see issue-triage.md section 7)
# and this wrapper appends them. Only writes a header when at least one issue was processed
# (no marker on "no open issues" days -> no daily spam).
$logLines = @(
  $out | ForEach-Object { "$_" } |
    Where-Object { $_ -match '@@LOG@@' } |
    ForEach-Object { ($_ -replace '^.*@@LOG@@\s*', '').TrimEnd() } |
    Where-Object { $_ -ne '' }
)
if ($logLines.Count -gt 0) {
  if (-not (Test-Path $TriageLog)) {
    Add-Content -Path $TriageLog -Value "# issue-triage run log (local only, gitignored)" -Encoding utf8
  }
  Add-Content -Path $TriageLog -Value "" -Encoding utf8
  Add-Content -Path $TriageLog -Value "## $stamp (scheduled run - run-triage.ps1)" -Encoding utf8
  foreach ($line in $logLines) { Add-Content -Path $TriageLog -Value "- $line" -Encoding utf8 }
}

$stampEnd = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
Add-Content -Path $LogFile -Value "===== [$stampEnd] (scheduled) issue-triage END (exit $code) =====" -Encoding utf8
exit $code
