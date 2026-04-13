---
name: team-agents
description: Spin up coordinated agent teams for any task. Reusable framework for TeamCreate/SendMessage/TaskList patterns. Use when user says "team-agents", "spin up a team", "use teammates", "parallel agents", "coordinate agents", "fan out", or wants multiple agents working together with coordination. Do NOT trigger for simple subagent work (use Agent tool directly) or inter-Oracle messaging (use /talk-to).
argument-hint: "<task-description> [--roles N] [--model sonnet|opus|haiku] [--plan]"
---

# /team-agents — Coordinated Agent Teams

> "Many hands, one mind."

Spin up a coordinated team of agents for any task. Generalizes the TeamCreate/SendMessage/TaskList pattern into a reusable framework that any skill or workflow can leverage.

## Prerequisites

Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in `~/.claude/settings.json`:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

Without this flag, TeamCreate/SendMessage/TaskList tools don't exist. Fall back to parallel subagents (fire-and-forget) if unavailable.

## Usage

```
/team-agents "review this PR for security, perf, and tests"
/team-agents "refactor auth module" --roles 3
/team-agents "research X" --model haiku
/team-agents "implement feature Y" --plan
/team-agents --manual "build feature Z"    # spawn agents, user controls
/team-agents status                    # show running team
/team-agents --panes                   # peek at tmux panes
/team-agents shutdown                  # graceful shutdown (SendMessage per agent)
/team-agents cleanup                   # kill idle orphan panes (safe)
/team-agents killshot                  # kill ALL non-lead panes (nuclear)
/team-agents doctor [--fix]            # detect ghosts + orphans + stale tasks
```

### Flags

| Flag | Effect |
|------|--------|
| `--manual` | Human controls agents via lead relay |
| `--panes` | Peek at tmux panes |
| `--plan` | Show team design, wait for approval |
| `--roles N` | Override default agent count |
| `--model X` | Override default model (sonnet/opus/haiku) |
| `--isolated` | Each agent gets its own git worktree (#224) |

---

## How It Works

### 3 Tiers — Choose the Right One

| Tier | When | Tools | Coordination |
|------|------|-------|-------------|
| **Subagents** | Simple parallel work, < 3 agents | Agent tool only | None — fire-and-forget |
| **Team Agents** | Coordinated work, 3-5 agents | TeamCreate + SendMessage + TaskList | Full — named roles, shared tasks, reports |
| **Cross-Oracle** | Inter-session, multi-repo | /talk-to + contacts | Persistent — maw/thread/inbox |

**Rule**: If the task can be done with 2 independent subagents, DON'T use team-agents. Use this for tasks that need coordination — where Agent B's work depends on Agent A's findings, or where a lead needs to compile structured reports.

---

## Step 0: Parse Task + Auto-Design Team

From the user's task description, the lead (you) designs the team:

### Role Archetypes

Pick 2-5 roles that cover the task. Common patterns:

| Pattern | Roles | Best For |
|---------|-------|----------|
| **Review** | security, performance, testing | Code review, PR review |
| **Research** | codebase, docs, community | Investigation, trace-like work |
| **Analysis** | timeline, patterns, memory | Retrospectives, audits |
| **Build** | architect, implementer, tester | Feature development |
| **Explore** | deep-dig, cross-repo, history | Discovery, /dream-like work |

### Auto-Design Logic

1. Parse the task description
2. Identify 2-5 dimensions of work
3. Assign each dimension a named role
4. Show the user the proposed team:

```
Team: pr-review (3 agents)

  Role         Focus                          Model
  ────────── ──────────────────────────────── ────────
  security     Auth flows, injection, OWASP    sonnet
  performance  N+1 queries, memory, latency    sonnet
  testing      Coverage gaps, edge cases       sonnet

  Lead: you (compile + write final report)

Spin up? [Y/n]
```

If `--plan` flag: show plan, wait for approval.
If no flag: show plan briefly, proceed immediately.

---

## Step 1: Create Team

```
TeamCreate("team-name")
```

Team name: slugified from task (e.g., "review this PR" → `pr-review`).

---

## Step 2: Register Tasks

Create one task per role:

```
TaskCreate({
  subject: "Security review",
  description: "Review auth flows, check for injection, OWASP top 10"
})

TaskCreate({
  subject: "Performance review",
  description: "Check N+1 queries, memory leaks, latency bottlenecks"
})

TaskCreate({
  subject: "Test coverage review",
  description: "Find coverage gaps, missing edge cases, flaky tests"
})
```

---

## Step 3: Spawn Teammates

Spawn all teammates in parallel. Each gets:

```
Agent({
  name: "security",
  team_name: "pr-review",
  model: "sonnet",
  prompt: `You are the SECURITY reviewer on team "pr-review".

REPO: [ABSOLUTE_PATH]
TASK: Review auth flows, check for injection vulnerabilities, OWASP top 10.

Instructions:
1. Read the relevant files
2. Do your analysis
3. Update your task: TaskUpdate({ taskId: [ID], status: "completed" })
4. Report to lead: SendMessage({
     to: "team-lead@pr-review",
     summary: "Security review complete — [findings count] issues",
     message: "[structured findings, max 500 words]"
   })

Rules:
- ONLY report via SendMessage — do NOT write files
- Max 500 words in your report
- Include severity (critical/high/medium/low) for each finding
- Be specific — file paths, line numbers, code snippets`
})
```

### Prompt Template (every teammate gets this)

```
You are the [ROLE] specialist on team "[TEAM_NAME]".

REPO: [ABSOLUTE_PATH_TO_REPO]
TASK: [TASK_DESCRIPTION]

Instructions:
1. Do your work (read files, run commands, analyze)
2. Mark task done: TaskUpdate({ taskId: [ID], status: "completed" })
3. Report to lead: SendMessage({
     to: "team-lead@[TEAM_NAME]",
     summary: "[5-10 word summary]",
     message: "[findings, max 500 words]"
   })

Rules:
- Report via SendMessage ONLY — do NOT write files
- Max 500 words in report
- Be specific — paths, lines, evidence
- If you need info from another agent, ask lead via SendMessage
```

**Critical**: Always include:
- `REPO:` with literal absolute path (never shell variables)
- `team-lead@[TEAM_NAME]` for SendMessage addressing
- 500-word limit to prevent context waste
- "do NOT write files" — only lead writes

---

## Step 4: Wait for Reports

Lead waits for SendMessage reports from all teammates. Expected time: 60-120 seconds.

**While waiting**:
- Idle notifications are normal — teammates are working
- Real content arrives via SendMessage with summary field
- Check TaskList periodically if reports seem slow

**If a teammate crashes**:
1. Check TaskList — is their task still `in_progress`?
2. SendMessage to the agent: "status check — are you still working?"
3. If no response after 30s: lead does the work manually
4. Note in final output: "Agent [role] crashed — lead completed manually"

---

## Step 5: Compile Results

Lead receives all SendMessage reports and compiles into a single output.

### Compilation Template

```markdown
# [Task Title] — Team Report

**Team**: [team-name] | **Agents**: [N] | **Duration**: ~[N]min
**Date**: [timestamp]

## [Role 1]: [Summary]
[Compiled findings from agent 1]

## [Role 2]: [Summary]
[Compiled findings from agent 2]

## [Role 3]: [Summary]
[Compiled findings from agent 3]

## Synthesis
[Lead's cross-cutting observations — patterns across agents' findings]

## Action Items
- [ ] [Specific action from findings]
- [ ] [Specific action from findings]
```

### Where to Write

- If task is review/analysis → display to user (don't write file)
- If task is retrospective → write to `ψ/memory/retrospectives/`
- If task is research → write to `ψ/memory/traces/`
- If task is implementation → agents write code (lead reviews)

---

## Step 6: Shutdown

Graceful shutdown sequence:

**IMPORTANT**: Structured messages (JSON with `type` field) CANNOT be broadcast via `to: "*"`.
You MUST send shutdown requests individually to each agent. Attempting `to: "*"` with a structured message will error: `structured messages cannot be broadcast`.

```
# 1. Send shutdown request to EACH teammate (no broadcast — #212)
SendMessage({ to: "security", message: { type: "shutdown_request" } })
SendMessage({ to: "performance", message: { type: "shutdown_request" } })
SendMessage({ to: "testing", message: { type: "shutdown_request" } })

# 2. Wait for shutdown_response from each (~5-10s)

# 3. Clean up
TeamDelete()
```

**After shutdown, archive agent findings to persistent mailbox + skills to /tmp:**

```bash
# 1. Archive each agent's findings to persistent mailbox (ψ/memory/mailbox/)
for agent in security performance testing; do
  bash ~/.claude/skills/mailbox/scripts/mailbox.sh archive $agent pr-review
done

# 2. Archive ephemeral skills to /tmp (Nothing is Deleted)
bash ~/.claude/skills/team-agents/scripts/shutdown-skills.sh pr-review security performance testing
```

Next time you spawn the same agent name, their mailbox context is auto-loaded into the prompt.

**Then clean up panes:**

```bash
bash ~/.claude/skills/team-agents/scripts/cleanup.sh    # safe — idle only
bash ~/.claude/skills/team-agents/scripts/killshot.sh    # nuclear — all panes
```

**Never skip shutdown** — TeamDelete fails if agents are still active.
**Never broadcast shutdown** — use sequential sends, one per agent.

---

## /team-agents status

Show current team state:

```
Team: pr-review (active)

  Agent        Status       Task                     Last Report
  ──────────── ──────────── ──────────────────────── ────────────
  security     completed    Security review           2 issues found
  performance  in_progress  Performance review        —
  testing      completed    Test coverage review      3 gaps found

  Duration: 45s | Tasks: 2/3 complete
```

Uses TaskList to get current state.

---

## /team-agents --panes

> See the machines breathing.

Peek at tmux panes to see team agent processes running alongside the lead. Maps panes to agent names.

### Quick Run (helper script)

One command — runs the full pane scan:

```bash
bash ~/.claude/skills/team-agents/scripts/panes.sh [team-name]
```

Pass the team name to map panes to agents. Without it, all non-lead panes show as `(other)`.

### Display

```
🖥 Team Panes — [session-name] ([PANE_COUNT] panes)

  Pane  Size      Model        Ctx    Agent        Status
  ───── ───────── ──────────── ────── ──────────── ──────────
  0     74x55     Opus 4.6     45%    team-lead    ← YOU
  1     78x8      Opus 4.6     12%    (other)      idle
  2     78x8      Opus 4.6     13%    (other)      idle
  3     78x8      Sonnet 4.6    9%    scout        idle
  4     78x8      Sonnet 4.6   11%    builder      idle
  5     78x8      Sonnet 4.6   11%    auditor      idle
  6     78x10     Opus 4.6     12%    (other)      idle

  Team: [team-name] | Agents: 3/6 panes | Non-team: 3

  💡 "tell scout to ..." — direct an agent
  💡 "/team-agents status" — task progress
```

### Pane Mapping Rules

1. **Pane 0** is always the lead (largest pane, main claude process)
2. **Team agents** are identified by reading `~/.claude/teams/[team-name]/config.json` and matching agent count to newest panes (agents spawn after lead, so they're higher pane numbers)
3. **Non-team panes** (pre-existing before team spawn) shown as `(other)` — they're separate claude instances, not part of this team
4. **Model extraction**: parse from the status bar line containing model name (e.g., `👁 Mawui Sonnet 4.6`)
5. **Context extraction**: parse `ctx XX%` or `XX%` from status bar
6. If **not in tmux**: show message and suggest running inside tmux

### Integration with status

When running `/team-agents status`, also show pane info if in tmux:

```
Team: whetstone-ops (active)

  Agent        Status       Task                     Pane
  ──────────── ──────────── ──────────────────────── ────
  scout        idle         —                         3
  builder      in_progress  Fix installer             4
  auditor      idle         —                         5
```

---

## /team-agents cleanup

> Sweep the floor after the fight.

Kill **idle** orphan panes left behind after team shutdown. Safe — only kills panes showing the `❯` prompt (idle claude processes). Active panes are skipped.

### Quick Run

```bash
# Dry run — see what would die
bash ~/.claude/skills/team-agents/scripts/cleanup.sh --dry-run

# Execute — kill idle panes
bash ~/.claude/skills/team-agents/scripts/cleanup.sh
```

### What it does

1. Scans all non-lead panes (pane 1+) in current tmux session
2. Captures last 3 lines of each pane
3. If pane shows `❯` prompt → **idle** → kills it
4. If pane is active (output streaming) → **skips** it
5. Works backwards (highest pane first) to avoid index shifting

### Output

```
🧹 Cleanup — skills-cli-view (4 panes)

  Pane 3   78x10      Sonnet 4.6   idle    → killed
  Pane 2   78x8       Sonnet 4.6   idle    → killed
  Pane 1   78x8       Opus 4.6     active  → skipped (still active)

  Killed: 2 | Skipped: 1 active
  Panes remaining: 2
```

### When to use

- After `/team-agents shutdown` — agent processes exited but tmux panes remain
- Stale panes from crashed agents
- Quick cleanup without killing active work

---

## /team-agents killshot

> "Kill them all. Let tmux sort them out."

Kill **ALL** non-lead panes — idle or active. The nuclear option. Use when you want a clean slate.

### Quick Run

```bash
bash ~/.claude/skills/team-agents/scripts/killshot.sh
```

### What it does

1. Kills every pane except pane 0 (the lead)
2. No mercy — active, idle, team, non-team, all die
3. Shows what was killed

### Output

```
💀 Killshot — skills-cli-view

  Pane 3   78x10      Opus 4.6     → killed
  Pane 2   78x8       Sonnet 4.6   → killed
  Pane 1   78x8       Sonnet 4.6   → killed

  Eliminated: 3 panes
  Remaining: 1 (lead only)
```

### When to use

- Total cleanup — don't care what's running
- Too many orphans to sort through
- Fresh start needed

**WARNING**: This kills ALL non-lead panes including pre-existing sessions. If you have other work running in side panes, use `cleanup` (safe) instead.

---

## /team-agents --manual Mode (#219)

> "You name them. You control them. They execute."

Manual mode spawns named agents but does NOT auto-orchestrate. The human directs each agent via the lead. The lead relays commands and compiles results.

### Why Manual?

| Auto Mode | Manual Mode |
|-----------|-------------|
| Lead designs roles + tasks | Human designs roles + tasks |
| Lead dispatches all agents | Human says "tell security to check auth" |
| Lead compiles automatically | Human reviews each report, gives next order |
| Fast, parallel, fire-and-forget | Deliberate, sequential, human-in-the-loop |

**Use manual when**: you want to name specific agents, control what they investigate, direct them step-by-step, or use team agents as persistent workers you can message throughout the session.

### Step 1: Parse + Show Team

```
/team-agents --manual "build the auth feature"
```

Lead proposes team (same as auto mode):

```
🤖 Manual team: auth-build (3 agents)

  Name         Role                            Model
  ──────────── ──────────────────────────────── ────────
  architect    Design auth flow + data model    sonnet
  builder      Implement code changes           sonnet
  tester       Write tests + verify             sonnet

  Manual mode: agents wait for YOUR commands.
  
  Commands:
    "tell architect to design the auth flow"
    "ask builder to implement login endpoint"
    "send tester the code to review"
    "/team-agents status" — check who's done
    "/team-agents shutdown" — end team

Spawn team? [Y/n]
```

### Step 2: Spawn Agents + Create Live Skills

```
TeamCreate("auth-build")
```

**After spawning agents, create live skills so user can talk directly:**

```bash
bash ~/.claude/skills/team-agents/scripts/spawn-skills.sh auth-build architect builder tester
```

This creates ephemeral skills at `.claude/skills/{agent}/SKILL.md`:
- `/architect` — direct channel to architect agent
- `/builder` — direct channel to builder agent
- `/tester` — direct channel to tester agent

Each skill wraps `SendMessage` — user says `/scout explore X`, lead relays to scout.

**Pre-load mailbox context (if agent has previous findings):**

```bash
MAILBOX_CONTEXT=$(bash ~/.claude/skills/mailbox/scripts/mailbox.sh load [agent-name] 2>/dev/null)
```

If mailbox has content, inject it into the spawn prompt so the agent starts with memory of previous sessions.

Spawn each agent with a standby prompt:

```
Agent({
  name: "[role-name]",
  team_name: "[team-name]",
  model: "sonnet",
  prompt: `You are [ROLE] on team "[TEAM_NAME]" in MANUAL mode.

REPO: [ABSOLUTE_PATH]
ROLE: [ROLE_DESCRIPTION]

You are in standby. Wait for instructions from the lead.
When you receive a message via SendMessage:
1. Read the instruction
2. Execute the work
3. Report back: SendMessage({
     to: "team-lead@[TEAM_NAME]",
     summary: "[5-10 word summary]",
     message: "[findings, max 500 words]"
   })
4. Return to standby — wait for next instruction

Rules:
- Do NOT start working until instructed
- Report via SendMessage ONLY — do NOT write files
- Max 500 words per report
- Be specific — paths, lines, evidence`
})
```

### Step 3: Human Directs

The human talks to the lead. The lead relays instructions to specific agents:

**Human says**: "tell architect to design the login flow"

**Lead does**:
```
SendMessage({
  to: "architect",
  summary: "New instruction: design login flow",
  message: "Design the login flow for our auth system. Include: data model, API endpoints, session handling. Report back when done."
})
```

**Lead reports**: "Sent to architect. Waiting for response..."

When architect reports back via SendMessage, lead shows the human:

```
📨 Report from architect:

  [architect's findings]

  💡 Next? "tell builder to implement this" / "ask architect for more detail"
```

### Step 4: Human Reviews + Directs Next

The human can:
- **Direct another agent**: "tell builder to implement the login endpoint based on architect's design"
- **Ask for more detail**: "ask architect about session storage"
- **Check status**: `/team-agents status`
- **Shut down**: `/team-agents shutdown`

### Step 5: Compile (on demand)

When human says "compile" or "report":

```
Lead compiles all SendMessage reports received so far into a structured summary.
Same format as auto mode Step 5.
```

### Key Differences from Auto

| Aspect | Auto | Manual |
|--------|------|--------|
| Who designs tasks? | Lead | Human |
| When do agents start? | Immediately after spawn | When human says "tell X to..." |
| Who compiles? | Lead (automatically) | Lead (when human says "compile") |
| Can human redirect? | No — fire-and-forget | Yes — at every step |
| Token efficiency | Higher (one shot) | Lower (more round-trips) |
| Control | Less | Full |

---

## /team-agents shutdown

Force graceful shutdown of current team:

```
SendMessage shutdown_request → all agents
Wait for responses (10s timeout)
TeamDelete()
```

---

## /team-agents --panes

Peek at tmux panes to see team agent processes running alongside the lead.

### How it works

```bash
# 1. Get current tmux session
SESSION=$(tmux display-message -p '#S' 2>/dev/null)

# 2. List all panes in this session
tmux list-panes -t "$SESSION" -F "#{pane_index} #{pane_width}x#{pane_height} #{pane_current_command}" 2>/dev/null

# 3. Peek at each non-lead pane (capture last 3 lines for status)
for i in $(tmux list-panes -t "$SESSION" -F "#{pane_index}" | tail -n +2); do
  tmux capture-pane -t "$SESSION:0.$i" -p | tail -3
done
```

### Display format

```
🖥 Team Panes — [session-name]

  Pane  Model        Ctx    Status         Agent
  ───── ──────────── ────── ────────────── ──────────
  0     Opus 4.6     45%    ← LEAD (you)   team-lead
  1     Sonnet 4.6    9%    idle           scout
  2     Sonnet 4.6   11%    idle           builder
  3     Sonnet 4.6   11%    idle           auditor

  💡 Pane mapping is best-effort — matches by model + spawn order
```

### Rules

1. Pane 0 is always the lead
2. Agent panes are matched by model (Sonnet = team agents) and spawn order
3. If not in tmux, show: "Not in a tmux session — pane view unavailable"
4. Non-team panes (pre-existing) shown as "other" with their model info

---

## Fallback: No Agent Teams Available

If `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is not set, the TeamCreate tool won't exist.

**Fallback to Tier 1 (subagents)**:

```
Team tools not available. Falling back to parallel subagents.
  (Enable with: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 in settings.json)

Spawning 3 independent agents...
```

Spawn agents via the regular Agent tool without team_name. Results come back as tool results instead of SendMessage. Lead still compiles.

**Differences in fallback mode**:
- No SendMessage — agents return text directly
- No TaskList — no shared task tracking
- No named addressing — agents can't message each other
- Still works for most parallel tasks — just less coordinated

---

## Gotchas

1. **Context is isolated** — teammates don't see lead's conversation history
2. **One team per session** — no nested teams
3. **~3-7x token usage** vs single agent — use wisely
4. **Two agents editing same file = overwrites** — only lead should write
5. **Task status can lag** — agents sometimes forget TaskUpdate
6. **No session resumption** — /resume doesn't restore teammates
7. **Teammates inherit lead's permissions** — can't restrict per-agent
8. **Recommended**: 3-5 agents, 5-6 tasks per agent max
9. **Don't use for small tasks** — if it takes < 5 minutes solo, don't team it

## Broadcast Limitation (#212)

**Known issue**: `SendMessage` can only target ONE agent at a time. There is no native broadcast/multicast.

### Workaround: Sequential Send

To send the same message to all teammates:

```
# Must send individually — no broadcast primitive
SendMessage({ to: "agent-1", message: "..." })
SendMessage({ to: "agent-2", message: "..." })
SendMessage({ to: "agent-3", message: "..." })
```

### Workaround: Lead as Relay

For structured broadcasts (e.g., shutdown), the lead iterates over the known agent list:

```
for agent in team_agents:
    SendMessage({ to: agent, message: { type: "shutdown_request" } })
```

### Why This Matters

Shutdown is the most common broadcast case. Without it, you must manually send shutdown to each agent. The current skill handles this by listing all agents in Step 6, but it's verbose.

**Upstream fix needed**: A `SendMessage({ to: "all@team-name", ... })` or `BroadcastMessage` tool would eliminate this friction. Tracked as #212.

---

## Integration with Other Skills

| Skill | How /team-agents helps |
|-------|----------------------|
| `/rrr --deep --teammate` | Already uses this pattern (TEAMMATE.md) |
| `/dream` | Could upgrade from subagents to coordinated team |
| `/trace --deep` | Wave 2 agents could coordinate findings |
| `/learn --deep` | Doc agents could build on each other's output |
| Any new skill | Import the pattern instead of reinventing |

---

## Worktree Isolation (`--isolated`) (#224)

When multiple agents edit code simultaneously, last-write-wins. `--isolated` gives each agent its own git worktree:

```
/team-agents --manual --isolated "build feature"
```

Each agent spawns with `isolation: "worktree"` in the Agent tool:

```
Agent({
  name: "builder",
  isolation: "worktree",
  ...
})
```

Claude Code creates the worktree at `.claude/worktrees/agent-<id>` and cleans up if no changes were made. If changes exist, the worktree path + branch are returned for the lead to merge.

**Note**: Worktree cleanup is NOT automatic if the agent crashes. `team-ops doctor` detects orphaned worktrees and `--fix` removes them.

---

## TMux Internals (#222)

From Claude Code source (`PaneBackendExecutor.ts`):

### Pane Creation

```
First agent:  tmux split-window -t <leaderPane> -h -l 70%
Additional:   alternating v/h splits from existing teammate panes
Rebalance:    select-layout main-vertical + resize-pane -t <leader> -x 30%
Border:       select-pane -P bg=default,fg=<color>
Title:        select-pane -T <name>
```

### Sequential Lock

`acquirePaneCreationLock()` prevents race conditions when spawning multiple agents in parallel. 200ms delay after each pane creation for shell init.

### Pane Tagging

Our `spawn-skills.sh` tags panes with tmux user options for reliable identity:

```bash
tmux set-option -p -t <paneId> @agent-name "scout"
tmux set-option -p -t <paneId> @team-name "myteam"
tmux select-pane -t <paneId> -T "scout@myteam"
```

Readable anytime: `tmux display-message -t <paneId> -p '#{@agent-name}'`

---

## Philosophy

> Subagents are arrows. Team agents are a squad.

Arrows fly independently — you aim them and hope they hit. A squad communicates, coordinates, adapts. Use arrows for quick shots. Use a squad when the mission is complex.

The cost is real (~3-7x tokens). The benefit is real (structured coordination, named roles, shared tasks, crash resilience). Choose based on the task, not the novelty.

---

ARGUMENTS: $ARGUMENTS
