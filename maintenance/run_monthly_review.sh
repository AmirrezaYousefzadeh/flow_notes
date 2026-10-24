#!/usr/bin/env bash
# Monthly maintenance run of the flow notes: upstream review, re-audit of the projects, issue files, housekeeping.
# Started by cron (see maintenance/README.md); runs Claude Code headless from /media/amir so the shared memory loads.
set -euo pipefail

NOTES=/media/amir/flow_notes
LOGDIR=$NOTES/maintenance/logs
mkdir -p "$LOGDIR"
LOG="$LOGDIR/$(date +%Y-%m-%d_%H%M).log"
exec 9>"$LOGDIR/.lock"
flock -n 9 || { echo "another review is running" >>"$LOG"; exit 0; }

export PATH="$HOME/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
# The CLI ships inside the VS Code extension; take the newest installed version.
CLAUDE=$(ls -d "$HOME"/.vscode-server/extensions/anthropic.claude-code-*/resources/native-binary/claude 2>/dev/null \
         | sort -V | tail -1)
if [[ -z "$CLAUDE" ]]; then
  echo "claude CLI not found" >>"$LOG"
  gh issue create --repo AmirrezaYousefzadeh/flow_notes --title "Monthly review $(date +%Y-%m) failed" \
     --body "run_monthly_review.sh could not find the Claude Code CLI." >>"$LOG" 2>&1 || true
  exit 1
fi

cd /media/amir
nice -n 19 "$CLAUDE" -p "$(cat "$NOTES/maintenance/monthly_review_prompt.md")" \
  --permission-mode auto \
  --add-dir /home/yousefzadeha/.claude/projects/-media-amir/memory \
  --disallowedTools "Bash(rm -rf:*)" "Bash(sudo:*)" "Bash(nix profile:*)" "Bash(pip install:*)" \
                    "Bash(volare:*)" "Bash(ciel:*)" "Bash(apt:*)" \
  >>"$LOG" 2>&1 || {
    echo "claude exited with $?" >>"$LOG"
    gh issue create --repo AmirrezaYousefzadeh/flow_notes --title "Monthly review $(date +%Y-%m) failed" \
       --body "The headless run ended with an error; see $LOG on the workstation." >>"$LOG" 2>&1 || true
  }
