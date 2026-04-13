#!/usr/bin/env bash
# /team-agents --panes helper v2 — peek at tmux panes and map to agents
# Usage: bash ~/.claude/skills/team-agents/scripts/panes.sh [team-name]
#
# v2: Uses tmux @agent-name pane option for reliable mapping (scout research)
#     Falls back to model+spawn-order if @agent-name not set

TEAM_NAME="${1:-}"
SESSION=$(tmux display-message -p '#S' 2>/dev/null)

if [ -z "$SESSION" ]; then
  echo "Not in a tmux session — pane view unavailable"
  exit 0
fi

# Get all pane IDs and count
PANE_IDS=$(tmux list-panes -t "$SESSION" -F "#{pane_index}|#{pane_id}|#{pane_width}x#{pane_height}" 2>/dev/null)
PANE_COUNT=$(echo "$PANE_IDS" | wc -l)

# Load team members if team name given
MEMBERS=""
if [ -n "$TEAM_NAME" ]; then
  TEAM_CONFIG="$HOME/.claude/teams/$TEAM_NAME/config.json"
  if [ -f "$TEAM_CONFIG" ]; then
    MEMBERS=$(python3 -c "
import json
config = json.load(open('$TEAM_CONFIG'))
for m in config.get('members', []):
    print(m['name'])
" 2>/dev/null)
  fi
fi

MEMBER_COUNT=$(echo "$MEMBERS" | grep -c . 2>/dev/null || echo 0)
TEAM_FOUND=0

echo ""
echo "🖥 Team Panes — $SESSION ($PANE_COUNT panes)"
echo ""
echo "  Pane  Size      Model        Ctx    Agent        Status   Title"
echo "  ───── ───────── ──────────── ────── ──────────── ──────── ─────────────────────────"

while IFS='|' read -r IDX PANE_ID SIZE; do
  # Capture last 3 lines for status bar
  CAPTURE=$(tmux capture-pane -t "$SESSION:0.$IDX" -p 2>/dev/null | tail -3)

  # Extract model from status bar
  MODEL=$(echo "$CAPTURE" | grep -oP '(Opus|Sonnet|Haiku) [0-9.]+' | head -1)
  [ -z "$MODEL" ] && MODEL="unknown"

  # Extract context percentage
  CTX=$(echo "$CAPTURE" | grep -oP 'ctx \d+%' | head -1 | sed 's/ctx //')
  [ -z "$CTX" ] && CTX=$(echo "$CAPTURE" | grep -oP '\d+%' | tail -1)
  [ -z "$CTX" ] && CTX="?"

  # Determine status (idle if prompt visible, working otherwise)
  if echo "$CAPTURE" | grep -q '^❯'; then
    STATUS="idle"
  else
    STATUS="working"
  fi

  # Get pane title (shows current agent task)
  TITLE=$(tmux display-message -t "$PANE_ID" -p '#{pane_title}' 2>/dev/null | head -c 25)

  # --- Agent name mapping (3-tier fallback) ---

  # Tier 1: @agent-name tmux option (most reliable — set at spawn time)
  AGENT=$(tmux display-message -t "$PANE_ID" -p '#{@agent-name}' 2>/dev/null)

  # Tier 2: Match from pane title (contains agent name sometimes)
  if [ -z "$AGENT" ] && [ -n "$MEMBERS" ]; then
    while IFS= read -r member; do
      if echo "$TITLE" | grep -qi "$member"; then
        AGENT="$member"
        break
      fi
    done <<< "$MEMBERS"
  fi

  # Tier 3: Spawn-order heuristic (team agents are newest panes)
  if [ -z "$AGENT" ] && [ -n "$MEMBERS" ]; then
    FIRST_TEAM_PANE=$((PANE_COUNT - MEMBER_COUNT))
    if [ "$IDX" -ge "$FIRST_TEAM_PANE" ]; then
      AGENT_IDX=$((IDX - FIRST_TEAM_PANE))
      AGENT=$(echo "$MEMBERS" | sed -n "$((AGENT_IDX + 1))p")
    fi
  fi

  # Lead pane
  if [ "$IDX" -eq 0 ]; then
    AGENT="team-lead"
    STATUS="← YOU"
  fi

  # Default
  [ -z "$AGENT" ] && AGENT="(other)"

  # Count team agents found
  if [ "$AGENT" != "(other)" ] && [ "$AGENT" != "team-lead" ]; then
    TEAM_FOUND=$((TEAM_FOUND + 1))
  fi

  printf "  %-5s %-9s %-12s %-6s %-12s %-8s %s\n" "$IDX" "$SIZE" "$MODEL" "$CTX" "$AGENT" "$STATUS" "$TITLE"

done <<< "$PANE_IDS"

echo ""
if [ -n "$TEAM_NAME" ]; then
  OTHER_PANES=$((PANE_COUNT - 1 - TEAM_FOUND))
  echo "  Team: $TEAM_NAME | Agents: $TEAM_FOUND/$((PANE_COUNT-1)) panes | Non-team: $OTHER_PANES"
  echo ""
  echo "  💡 Tag panes for reliable mapping:"
  echo "     tmux set-option -p -t %ID @agent-name \"scout\""
else
  echo "  💡 Pass team name: bash panes.sh <team-name>"
fi
echo ""
