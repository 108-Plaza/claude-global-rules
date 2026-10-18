# AGENTS.md — the global rules are not in this file

🔴 **All global rules live in `CLAUDE.md` in this same repo** (`108-Plaza/claude-global-rules`),
checked out at `~/.claude/rules-repo/` on every machine · autopull every 15 minutes.

**Agents that read `AGENTS.md` first: read that file before starting work:**

```
cat ~/.claude/rules-repo/CLAUDE.md
```

This file is short on purpose. **Never copy rules into it** — Claude Code loads both `CLAUDE.md`
and `AGENTS.md` into context ⇒ a copy here = paying the tokens twice every session.

## Procedures by role: read the skill file

Claude Code loads these as skills on demand; other agents (agy) do not, so read the file for your role before you start:

| Your work | Read |
|---|---|
| Holding a queue ticket (implementer) | `~/.claude/rules-repo/skills/tq-worker/SKILL.md` |
| Reviewing a PR, verdict format, merging | `~/.claude/rules-repo/skills/review-and-merge/SKILL.md` |
| Writing a ticket or a design doc | `~/.claude/rules-repo/skills/ticket-writing/SKILL.md` |
| Workflows, CI queue, deploy lanes | `~/.claude/rules-repo/skills/fleet-ci/SKILL.md` |
| Heavy builds, disk, cleanup | `~/.claude/rules-repo/skills/fleet-builds/SKILL.md` |
| Lane controller (dispatch, monitoring) | `~/.claude/rules-repo/skills/queue-controller/SKILL.md` |

Machines, sessions, lanes and runners as measured: `~/.claude/rules-repo/FLEET.md`.

## Never write rules into this file

New or changed rule ⇒ edit `~/.claude/rules-repo/CLAUDE.md` + commit + `claude-rules push`
· editing without committing = a split fleet (autopull skips the whole machine when the worktree is dirty).

## Why this file is this short (2026-09-27)

The old `~/AGENTS.md` was 711 lines / 77.6 KB, last edited 2026-09-06, and **not in git**
⇒ nothing kept it current · it went stale for 21 days and contradicted `CLAUDE.md` in 8 places. The most dangerous:
it ordered `[skip ci]` (the global rules forbid it — required checks never run · park108#943) and said merge
belongs to the owner alone (global rule 🟢 lets the reviewer merge when all three conditions hold) · the whole file
still described Codex as a main role, which the owner stopped using on 2026-09-22.

The 2 remaining non-duplicate pieces were moved into `CLAUDE.md` in commit `60065c3`.
