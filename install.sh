#!/usr/bin/env bash
# install.sh — claude-issue-triage installer (macOS / Linux / Git Bash)
#
# Run from YOUR PROJECT ROOT (the git repo you want triage to manage):
#   curl -fsSL https://raw.githubusercontent.com/kiminyeob/claude-issue-triage/main/install.sh | bash
# or from a local clone of this kit:
#   bash <kit>/install.sh
#
# What it does (safe by default — never overwrites your existing files):
#   1. copies template/.claude/{commands,automation} into ./.claude/
#   2. creates ./.claude/settings.json with your project path substituted
#      (if one already exists → writes settings.triage-suggested.json for manual merge)
#   3. appends triage-local entries to .gitignore (idempotent)
#   4. copies CLAUDE-md-snippet.md for you to paste into your CLAUDE.md
# Env overrides: TRIAGE_REPO_URL (source repo), TRIAGE_FORCE=1 (overwrite files)

set -eu

REPO_URL="${TRIAGE_REPO_URL:-https://github.com/kiminyeob/claude-issue-triage}"
FORCE="${TRIAGE_FORCE:-0}"
TARGET="$(pwd)"

echo ""
echo "claude-issue-triage installer"
echo "  target project: $TARGET"

if [ ! -e "$TARGET/.git" ]; then
  echo "[ABORT] current directory is not a git repository." >&2
  echo "        cd into your project root first, then re-run the installer." >&2
  exit 1
fi

# --- locate the template: local checkout first, otherwise clone to temp -------------------
SRC=""
TEMP_CLONE=""
SCRIPT_DIR=""
case "${BASH_SOURCE[0]:-}" in
  */*) SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)" ;;
esac
if [ -n "$SCRIPT_DIR" ] && [ -d "$SCRIPT_DIR/template" ]; then
  SRC="$SCRIPT_DIR/template"
  echo "  source: local checkout ($SCRIPT_DIR)"
else
  command -v git >/dev/null 2>&1 || { echo "[ABORT] git not found on PATH." >&2; exit 1; }
  TEMP_CLONE="$(mktemp -d "${TMPDIR:-/tmp}/claude-issue-triage.XXXXXX")"
  echo "  source: cloning $REPO_URL ..."
  git clone --depth 1 --quiet "$REPO_URL" "$TEMP_CLONE"
  SRC="$TEMP_CLONE/template"
fi
[ -d "$SRC" ] || { echo "[ABORT] template folder not found in source." >&2; exit 1; }

# --- project path in Claude Code permission syntax: /home/u/proj -> //home/u/proj ----------
PERM_PATH="/$TARGET"

COPIED=""
SKIPPED=""

copy_file() { # $1 = relative path
  rel="$1"
  from="$SRC/$rel"
  to="$TARGET/$rel"
  mkdir -p "$(dirname "$to")"
  if [ -e "$to" ] && [ "$FORCE" != "1" ]; then
    SKIPPED="$SKIPPED$rel\n"
    return 0
  fi
  cp "$from" "$to"
  COPIED="$COPIED$rel\n"
}

# --- 1) commands + automation --------------------------------------------------------------
for rel in \
  .claude/commands/issue-triage.md \
  .claude/commands/session-briefing.md \
  .claude/commands/resolve-issue.md \
  .claude/automation/run-triage.ps1 \
  .claude/automation/run-triage.sh \
  .claude/automation/register-task.ps1 \
  .claude/automation/register-cron.sh \
  .claude/automation/guard.js
do copy_file "$rel"; done
chmod +x "$TARGET/.claude/automation/run-triage.sh" "$TARGET/.claude/automation/register-cron.sh" 2>/dev/null || true

# --- 2) settings.json (substitute {{PROJECT_PATH}}; never clobber an existing one) ---------
SETTINGS_OUT="$(sed "s|{{PROJECT_PATH}}|$PERM_PATH|g" "$SRC/.claude/settings.json")"
if [ -e "$TARGET/.claude/settings.json" ]; then
  printf '%s\n' "$SETTINGS_OUT" > "$TARGET/.claude/settings.triage-suggested.json"
  echo "  [merge needed] .claude/settings.json already exists."
  echo "                 wrote .claude/settings.triage-suggested.json — merge its permissions.deny/allow"
  echo "                 and hooks into your settings.json (or ask Claude Code to merge them)."
else
  printf '%s\n' "$SETTINGS_OUT" > "$TARGET/.claude/settings.json"
  COPIED="$COPIED.claude/settings.json\n"
fi

# --- 3) .gitignore (idempotent block) ------------------------------------------------------
GI="$TARGET/.gitignore"
MARKER="# claude-issue-triage (local runtime files)"
if ! { [ -f "$GI" ] && grep -qF "$MARKER" "$GI"; }; then
  { [ -f "$GI" ] && [ -n "$(tail -c1 "$GI" 2>/dev/null)" ] && echo ""; true; } >> "$GI"
  {
    echo ""
    echo "$MARKER"
    echo ".claude/automation/log.md"
    echo ".claude/automation/decisions/"
    echo ".claude/automation/cron.log"
    echo ".claude/automation/*.tmp"
    echo ".claude/automation/*.tmp.md"
    echo ".claude/automation/*.secret"
    echo ".claude/settings.triage-suggested.json"
  } >> "$GI"
  echo "  .gitignore: triage entries appended"
else
  echo "  .gitignore: already contains triage entries (skipped)"
fi

# --- 4) CLAUDE.md snippet ------------------------------------------------------------------
cp "$SRC/CLAUDE-md-snippet.md" "$TARGET/.claude/CLAUDE-md-snippet.md"
COPIED="$COPIED.claude/CLAUDE-md-snippet.md\n"

# --- cleanup temp clone --------------------------------------------------------------------
[ -n "$TEMP_CLONE" ] && rm -rf "$TEMP_CLONE" 2>/dev/null || true

# --- summary + next steps ------------------------------------------------------------------
echo ""
echo "installed files:"
printf '%b' "$COPIED" | sed 's/^/  + /'
if [ -n "$SKIPPED" ]; then
  echo "kept existing (not overwritten — set TRIAGE_FORCE=1 to overwrite):"
  printf '%b' "$SKIPPED" | sed 's/^/  = /'
fi
echo ""
echo "NEXT STEPS"
echo "  1. edit .claude/commands/issue-triage.md — top block: verify commands + project rules"
echo "  2. paste .claude/CLAUDE-md-snippet.md into your project's CLAUDE.md"
echo "  3. gh auth login   (GitHub CLI must be authenticated for issues)"
echo "  4. claude setup-token → save the token into .claude/automation/oauth-token.secret"
echo "  5. register the daily schedule:"
echo "       bash .claude/automation/register-cron.sh          # daily 10:00 (or pass HH:MM)"
echo "  6. test now:  bash .claude/automation/run-triage.sh"
echo "     then check .claude/automation/cron.log"
echo ""
echo "docs: $REPO_URL/tree/main/docs"
