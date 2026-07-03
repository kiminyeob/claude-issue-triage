#!/usr/bin/env bash
# run-triage.sh — cron/launchd wrapper for the daily issue-triage (claude-issue-triage kit)
#
# What it does: cd to project root → launch claude headless + dontAsk to run /issue-triage
#   → append stdout/stderr with timestamps to cron.log
#   → extract '@@LOG@@ <line>' summary lines from claude's output and append them to log.md.
#     (Headless claude CANNOT Write into .claude/ — dontAsk blocks all Write — so this wrapper,
#      being a plain shell script with no tool-permission model, writes log.md.)
# Scheduled-run only. For manual checks, just type /issue-triage in an interactive session.

set -u

# ===== EDIT HERE: model used for scheduled (headless) runs ==================================
TRIAGE_MODEL="${TRIAGE_MODEL:-claude-sonnet-5}"
# ============================================================================================

# cron runs with a minimal environment — fix locale (UTF-8 output) and PATH.
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export PATH="$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_FILE="$SCRIPT_DIR/cron.log"
TRIAGE_LOG="$SCRIPT_DIR/log.md"

cd "$PROJECT_ROOT" || exit 1

stamp() { date '+%Y-%m-%d %H:%M:%S'; }

{
  echo ""
  echo "===== [$(stamp)] (scheduled) issue-triage START ====="
} >> "$LOG_FILE"

CLAUDE_BIN="$(command -v claude || true)"
if [ -z "$CLAUDE_BIN" ]; then
  echo "[ERROR] claude executable not found on PATH" >> "$LOG_FILE"
  exit 1
fi

# --- TLS: trust a corporate SSL-inspection CA if present ---
# Node uses its own CA store, so a TLS-intercepting proxy causes UNABLE_TO_VERIFY_LEAF_SIGNATURE.
# See docs/troubleshooting.md for how to build the PEM bundle. Only set if not already provided.
if [ -z "${NODE_EXTRA_CA_CERTS:-}" ] && [ -f "$HOME/.claude/corp-ca-bundle.pem" ]; then
  export NODE_EXTRA_CA_CERTS="$HOME/.claude/corp-ca-bundle.pem"
fi

# --- auth: inject a long-lived token for the unattended run (claude setup-token) ---
# Interactive OAuth login creds expire roughly nightly and are NOT refreshed reliably in a
# headless -p run → "401 Invalid authentication credentials" the next day. Store the token
# printed by 'claude setup-token' in the gitignored file below.
TOKEN_FILE="$SCRIPT_DIR/oauth-token.secret"
if [ -f "$TOKEN_FILE" ]; then
  TOK="$(tr -d '[:space:]' < "$TOKEN_FILE")"
  [ -n "$TOK" ] && export CLAUDE_CODE_OAUTH_TOKEN="$TOK"
fi
if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  echo "[WARN] CLAUDE_CODE_OAUTH_TOKEN not set (missing $TOKEN_FILE). Falling back to interactive login creds, which expire nightly and may 401. Fix: run 'claude setup-token' and save its output into that file." >> "$LOG_FILE"
fi

# Headless + dontAsk. 'headless' arg tells the command no human is present.
OUT="$("$CLAUDE_BIN" -p "/issue-triage headless" --permission-mode dontAsk --model "$TRIAGE_MODEL" 2>&1)"
CODE=$?
[ -n "$OUT" ] && printf '%s\n' "$OUT" >> "$LOG_FILE"

# --- log.md: append the '@@LOG@@ <one-line>' summaries claude printed for each processed issue.
# Only writes a header when at least one issue was processed (no marker on "no open issues" days).
LOG_LINES="$(printf '%s\n' "$OUT" | grep '@@LOG@@' | sed 's/^.*@@LOG@@[[:space:]]*//' | sed 's/[[:space:]]*$//' | grep -v '^$' || true)"
if [ -n "$LOG_LINES" ]; then
  [ -f "$TRIAGE_LOG" ] || echo "# issue-triage run log (local only, gitignored)" > "$TRIAGE_LOG"
  {
    echo ""
    echo "## $(stamp) (scheduled run - run-triage.sh)"
    printf '%s\n' "$LOG_LINES" | while IFS= read -r line; do echo "- $line"; done
  } >> "$TRIAGE_LOG"
fi

echo "===== [$(stamp)] (scheduled) issue-triage END (exit $CODE) =====" >> "$LOG_FILE"
exit $CODE
