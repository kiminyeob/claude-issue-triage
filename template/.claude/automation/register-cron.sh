#!/usr/bin/env bash
# register-cron.sh — register the daily issue-triage in the user's crontab (macOS/Linux)
#   (claude-issue-triage kit)
#
# Usage:
#     bash .claude/automation/register-cron.sh            # daily at 10:00
#     bash .claude/automation/register-cron.sh 09:30      # daily at 09:30
#
# Idempotent: re-running replaces this project's existing entry (matched by marker comment).
# Remove:  crontab -e  → delete the line ending with the marker below.
# Note (macOS): cron needs Full Disk Access in some setups; launchd is the Apple-blessed
#   alternative — see docs/setup.md.

set -eu

AT="${1:-10:00}"
HH="${AT%%:*}"
MM="${AT##*:}"
case "$HH$MM" in (*[!0-9]*) echo "invalid time: $AT (use HH:MM)"; exit 1;; esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_NAME="$(basename "$PROJECT_ROOT")"
MARKER="# claude-issue-triage:$PROJECT_NAME"
WRAPPER="$SCRIPT_DIR/run-triage.sh"

[ -f "$WRAPPER" ] || { echo "wrapper not found: $WRAPPER"; exit 1; }
chmod +x "$WRAPPER" || true

ENTRY="$MM $HH * * * /usr/bin/env bash '$WRAPPER' $MARKER"

# Replace any existing entry for this project, then append the new one.
TMP="$(mktemp)"
( crontab -l 2>/dev/null | grep -vF "$MARKER" || true ) > "$TMP"
printf '%s\n' "$ENTRY" >> "$TMP"
crontab "$TMP"
rm -f "$TMP"

echo "[OK] cron registered: daily $AT -> $WRAPPER"
echo "     check:   crontab -l | grep issue-triage"
echo "     run now: bash '$WRAPPER'"
echo "     remove:  crontab -e   (delete the line ending with '$MARKER')"
