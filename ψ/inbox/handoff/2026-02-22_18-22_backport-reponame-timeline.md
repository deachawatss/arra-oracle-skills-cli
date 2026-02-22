# Handoff: Backport repoName + Timeline Mode

**Date**: 2026-02-22 18:22
**Version**: v1.5.85
**Plan**: `~/.claude/plans/curious-imagining-treasure.md`

## What We Did (This Session)

- Shipped v1.5.85: dig.py timeline format — end times + gap rows (#45)
- Tested `/trace --dig` — new format works (gap rows, chronological order)
- Discovered source/install drift: installed dig.py has `repoName` feature, source doesn't
- Read issues #45 (done) + #46 (next)
- Wrote and approved plan for next session

## Critical: Source/Install Drift

The **installed** `~/.claude/skills/trace/scripts/dig.py` has `repoName` attribution:
- `build_repo_map()` — calls `ghq list -p`, maps paths to repo names
- `get_repo_name()` — strips `-wt-N` suffix, falls back to last segment
- `seen` dict stores `(filepath, source_dir)` tuples
- Each session includes `'repoName'` field

The **source** `src/skills/trace/scripts/dig.py` is MISSING all of this.

**Fix**: Copy from installed → source (not the other way around).

## Next Session Tasks

1. [ ] **Backport repoName** — copy `build_repo_map()`/`get_repo_name()` from installed dig.py → source
2. [ ] **Close #45** — `gh issue close 45 --comment "Shipped in v1.5.85"`
3. [ ] **Add `--timeline` to `/trace --dig`** — group-by-date view in SKILL.md
   - Day headers: `## Feb 22 (Sun) — [vibe]`
   - Sessions: `HH:MM–HH:MM Nm REPO Summary`
   - Gaps: `· · · [label]`
   - Sidechains: `(bg)` prefix
   - Current day: `← current` marker
   - Sort: days newest-first, sessions within day oldest-first
4. [ ] **Ship v1.5.86** — `bun run version && git tag && git push`

## Key Files

- `src/skills/trace/scripts/dig.py` — backport target
- `~/.claude/skills/trace/scripts/dig.py` — backport source (has repoName)
- `src/skills/trace/SKILL.md` — add --timeline section
- Issue #45: close it
- Issue #46: /pulse timeline (implement as --timeline flag on trace)
