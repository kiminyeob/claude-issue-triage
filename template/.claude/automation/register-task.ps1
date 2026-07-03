# register-task.ps1 - register the daily issue-triage schedule in Windows Task Scheduler
#   (claude-issue-triage kit)
#
# Usage (regular PowerShell, no admin rights needed):
#     powershell -NoProfile -ExecutionPolicy Bypass -File .\.claude\automation\register-task.ps1
#     powershell -NoProfile -ExecutionPolicy Bypass -File .\.claude\automation\register-task.ps1 -At '09:30'
#
# Unregister:  Unregister-ScheduledTask -TaskName '<TaskName printed below>' -Confirm:$false
# Run now:     Start-ScheduledTask -TaskName '<TaskName printed below>'

param(
  # Daily trigger time (local timezone), 24h 'HH:mm'.
  [string]$At = '10:00'
)

$ErrorActionPreference = 'Stop'

# Task name is derived from the project folder name so multiple projects can coexist.
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ProjectName = Split-Path $ProjectRoot -Leaf
$TaskName = "IssueTriage-$ProjectName"
$Wrapper  = Join-Path $PSScriptRoot 'run-triage.ps1'

if (-not (Test-Path $Wrapper)) {
  throw "wrapper script not found: $Wrapper"
}

# Run the wrapper with powershell.exe, no profile, policy bypass.
$action = New-ScheduledTaskAction `
  -Execute 'powershell.exe' `
  -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $Wrapper)

# Daily at $At (local timezone). Single trigger.
$trigger = New-ScheduledTaskTrigger -Daily -At ([datetime]$At)

# Settings: catch-up (missed-run backfill) OFF - StartWhenAvailable=$false.
#   Allow on battery, 1h execution limit, ignore new instance while one is running.
$settings = New-ScheduledTaskSettingsSet `
  -StartWhenAvailable:$false `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
  -MultipleInstances IgnoreNew

$desc = "claude-issue-triage: daily $At headless /issue-triage for $ProjectName. If the machine is off/logged-out, that day is skipped (no catch-up)."

# Explicit principal: current user + interactive logon (runs only while logged on, no password
# stored) + limited run level (never elevates even when registered from an admin shell).
$principal = New-ScheduledTaskPrincipal `
  -UserId "$env:USERDOMAIN\$env:USERNAME" `
  -LogonType Interactive `
  -RunLevel Limited

# -Force: overwrite an existing task of the same name (re-registration allowed).
Register-ScheduledTask `
  -TaskName $TaskName `
  -Action $action `
  -Trigger $trigger `
  -Settings $settings `
  -Principal $principal `
  -Description $desc `
  -Force | Out-Null

Write-Host "[OK] task registered: $TaskName (daily $At, no catch-up, limited privileges)"
Write-Host "     wrapper:   $Wrapper"
Write-Host "     run now:   Start-ScheduledTask -TaskName '$TaskName'"
Write-Host "     status:    Get-ScheduledTask -TaskName '$TaskName' | Get-ScheduledTaskInfo"
Write-Host "     remove:    Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false"
