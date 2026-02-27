---
name: schedule
description: Query schedule via Oracle API (Drizzle DB). Use when user says "schedule", "upcoming events", "what's on today", "calendar".
---

# /schedule - Query Schedule

Query the Oracle schedule database via HTTP API. Backed by Drizzle DB with proper date indexing.

## Usage

- `/schedule` → Upcoming events (next 30 days)
- `/schedule week` → Next 7 days
- `/schedule today` → Today's events
- `/schedule tomorrow` → Tomorrow's events
- `/schedule month` → This month
- `/schedule march` → March events
- `/schedule standup` → Search by keyword
- `/schedule all` → Everything (all statuses)

## Implementation

Run the query script:

```bash
bun .claude/skills/schedule/scripts/query.ts [filter]
```

The script queries `GET /api/schedule` on the Oracle HTTP server (port 47778) and formats the response as a markdown table.

## API Reference

```
GET /api/schedule                         → next 14 days (pending)
GET /api/schedule?date=2026-03-05         → specific day
GET /api/schedule?date=today              → today
GET /api/schedule?from=2026-03-01&to=2026-03-31  → range
GET /api/schedule?filter=keyword          → search
GET /api/schedule?status=all              → include done/cancelled
```

## See Also

- `scripts/query.ts` - Query script (hits Oracle API)
- Oracle DB: `~/.oracle/oracle.db` → `schedule` table
- Auto-export: `~/.oracle/ψ/inbox/schedule.md` (generated on write)
