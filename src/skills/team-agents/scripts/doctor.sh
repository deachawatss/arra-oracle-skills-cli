#!/usr/bin/env bash
# team-ops doctor — detect ghost agents by cross-referencing team config with live processes
# Usage: doctor.sh [--fix]

FIX=false
[ "$1" = "--fix" ] && FIX=true

echo ""
echo "🩺 Team Ops Doctor"
echo ""

GHOSTS=0
ALIVE=0
ISSUES=0

# 1. Check active teams
if ls -d "$HOME/.claude/teams"/*/ &>/dev/null; then
  for team_dir in "$HOME/.claude/teams"/*/; do
    TEAM=$(basename "$team_dir")
    CONFIG="$team_dir/config.json"
    [ -f "$CONFIG" ] || continue

    echo "  Team: $TEAM"

    # Read members from config
    MEMBERS=$(python3 -c "
import json
config = json.load(open('$CONFIG'))
for m in config.get('members', []):
    print(f\"{m['name']}|{m.get('agentId', '')}\")
" 2>/dev/null)

    while IFS='|' read -r NAME AGENT_ID; do
      [ -z "$NAME" ] && continue

      # Check if agent process is alive via /proc
      FOUND_PID=""
      for pid in $(pgrep -f "claude" 2>/dev/null); do
        CMD=$(cat /proc/$pid/cmdline 2>/dev/null | tr '\0' '\n' | grep -A1 '^--agent-name$' | tail -1)
        if [ "$CMD" = "$NAME" ]; then
          FOUND_PID=$pid
          break
        fi
      done

      # Check tmux pane
      SESSION=$(tmux display-message -p '#S' 2>/dev/null)
      PANE_ALIVE=false
      if [ -n "$SESSION" ]; then
        PANE_COUNT=$(tmux list-panes -t "$SESSION" 2>/dev/null | wc -l)
        for i in $(seq 1 $((PANE_COUNT - 1))); do
          CAPTURE=$(tmux capture-pane -t "$SESSION:0.$i" -p 2>/dev/null | tail -3)
          if echo "$CAPTURE" | grep -qi "$NAME"; then
            PANE_ALIVE=true
            break
          fi
        done
      fi

      if [ -n "$FOUND_PID" ]; then
        echo "    ✅ $NAME — alive (pid $FOUND_PID)"
        ALIVE=$((ALIVE + 1))
      else
        echo "    👻 $NAME — GHOST (no process found)"
        GHOSTS=$((GHOSTS + 1))

        if [ "$FIX" = true ]; then
          echo "       → Marking inactive in team config"
        fi
      fi
    done <<< "$MEMBERS"
    echo ""
  done
else
  echo "  No active teams found."
  echo ""
fi

# 2. Check orphaned worktrees
echo "  Worktrees:"
ORPHAN_WTS=0
for repo in ~/Code/github.com/Soul-Brews-Studio/*/; do
  WT_DIR="$repo/.claude/worktrees"
  if [ -d "$WT_DIR" ]; then
    for wt in "$WT_DIR"/*/; do
      [ -d "$wt" ] || continue
      name=$(basename "$wt")
      echo "    ⚠️ Orphaned: $(basename "$repo")/.claude/worktrees/$name"
      ORPHAN_WTS=$((ORPHAN_WTS + 1))

      if [ "$FIX" = true ]; then
        ARCHIVE="/tmp/worktree-$name-$(date +%Y%m%d_%H%M%S)"
        cd "$repo" && git worktree remove "$wt" --force 2>/dev/null
        echo "       → Removed worktree"
      fi
    done
  fi
done
[ "$ORPHAN_WTS" -eq 0 ] && echo "    ✅ No orphaned worktrees"

echo ""

# 3. Check stale task dirs
echo "  Task directories:"
STALE_TASKS=0
for task_dir in "$HOME/.claude/tasks"/*/; do
  [ -d "$task_dir" ] || continue
  name=$(basename "$task_dir")
  # Check if corresponding team exists
  if [ ! -d "$HOME/.claude/teams/$name" ]; then
    echo "    ⚠️ Stale: ~/.claude/tasks/$name/ (no matching team)"
    STALE_TASKS=$((STALE_TASKS + 1))

    if [ "$FIX" = true ]; then
      ARCHIVE="/tmp/tasks-$name-$(date +%Y%m%d_%H%M%S)"
      mv "$task_dir" "$ARCHIVE"
      echo "       → Archived to $ARCHIVE"
    fi
  fi
done
[ "$STALE_TASKS" -eq 0 ] && echo "    ✅ No stale task directories"

echo ""

# 4. Check ghost panes (tmux panes with dead claude processes)
echo "  Tmux panes:"
GHOST_PANES=0
SESSION=$(tmux display-message -p '#S' 2>/dev/null)
if [ -n "$SESSION" ]; then
  PANE_COUNT=$(tmux list-panes -t "$SESSION" 2>/dev/null | wc -l)
  for i in $(seq 1 $((PANE_COUNT - 1))); do
    PANE_PID=$(tmux list-panes -t "$SESSION" -F "#{pane_index} #{pane_pid}" 2>/dev/null | awk -v idx="$i" '$1==idx {print $2}')
    CLAUDE_PID=$(pstree -p "$PANE_PID" 2>/dev/null | grep -oP 'claude\((\d+)\)' | grep -oP '\d+' | head -1)

    if [ -z "$CLAUDE_PID" ]; then
      # Pane exists but no claude process
      CAPTURE=$(tmux capture-pane -t "$SESSION:0.$i" -p 2>/dev/null | tail -1)
      if echo "$CAPTURE" | grep -q '^❯'; then
        echo "    👻 Pane $i — idle shell (no claude)"
        GHOST_PANES=$((GHOST_PANES + 1))
      fi
    fi
  done
  [ "$GHOST_PANES" -eq 0 ] && echo "    ✅ No ghost panes"
else
  echo "    (not in tmux)"
fi

# Summary
echo ""
echo "  ────────────────────────────"
echo "  Agents alive:     $ALIVE"
echo "  Ghost agents:     $GHOSTS"
echo "  Orphan worktrees: $ORPHAN_WTS"
echo "  Stale tasks:      $STALE_TASKS"
echo "  Ghost panes:      $GHOST_PANES"
TOTAL=$((GHOSTS + ORPHAN_WTS + STALE_TASKS + GHOST_PANES))
if [ "$TOTAL" -eq 0 ]; then
  echo ""
  echo "  ✅ All clear — system healthy"
else
  echo "  ⚠️ $TOTAL issues found"
  if [ "$FIX" = false ]; then
    echo ""
    echo "  💡 Run: team-ops doctor --fix"
  fi
fi
echo ""
