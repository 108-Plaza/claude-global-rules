---
name: foreman-workflow
description: >-
  How Claude runs work as the foreman: think before designing (read the code, offer options), write plans that workers can't
  misread (file map, interfaces, test-first steps, self-review), execute through fresh workers with a review after every task and
  a whole-branch review at the end, debug by root cause in four phases, and claim nothing without fresh evidence. Adapted from
  the strongest parts of obra/superpowers and bound to this fleet's rules. Use when planning a feature or refactor, cutting and
  dispatching tickets, debugging any failure, or about to say work is done.
---

# Foreman workflow

Owner, 2026-11-25: *"superpowers+software-design"* · *"เอาจุดแข็งมาใข้งาน"*. This skill takes the strongest parts of
[obra/superpowers](https://github.com/obra/superpowers) (MIT, © Jesse Vincent; read at `22f0b46`, v7.0.2, 2026-11-25) and rewrites them for this fleet.

Not taken:
- its session-start hook, which injects "must use a skill at 1% chance" into every session;
- `finishing-a-development-branch`, which merges into main locally and pushes;
- `using-git-worktrees`, which picks its own worktree places;
- the brainstorming web server.

**What wins when rules disagree:** fleet rules (`CLAUDE.md`, skills `tq-worker`, `review-and-merge`, `fleet-builds`) first, then skill `software-design` for the shape of the code, then this skill for how the work moves.

`software-design` decides **what** to build. This skill is **how Claude moves the work**: think → plan → execute → verify, with debugging whenever something fails.

## 1. Think before designing

- **Read the code first, and never ask the owner what the code can answer.** Survey per `software-design` § 2.
- **Lay out 2–3 approaches with costs and one recommendation**, in a message of their own, before writing the design doc. The rejected ones go in the doc's "Alternatives considered".
- Bring only **owner decisions** to the owner: business rules, migrations, the BLOCK groups, deploy, contracts with apps outside the repo. Use the 🔬 format from `CLAUDE.md`. Everything else, decide yourself.
- Ask "why" when a request has no reason, and check the reason you infer against the code (`CLAUDE.md` 🧭).

## 2. Write a plan a worker can't misread

The plan becomes the tickets (skill `ticket-writing`), so write it as decisions, not prose.

**File map first.** List every file to create or change and the one responsibility of each, before any task.
Files that change together live together. A file that is already too large gets a split task of its own.

**One task = the smallest unit with its own test cycle that a reviewer could reject on its own.** Fold setup and docs into the task that needs them.

Every task has:
- **Files:** create / modify (`path:line-range`) / test.
- **Interfaces:**
  - *Consumes:* the exact signatures it uses from earlier tasks;
  - *Produces:* the exact names and types later tasks rely on.

  A worker sees only its own ticket, so this block is how it learns its neighbours' names.
- **Steps**, each one action with a checkable result:
  1. write the failing test (its name and assertions, with exact values);
  2. run it, expect FAIL (with the expected message);
  3. implement `signature` in `file`;
  4. run it, expect PASS;
  5. commit.
- A step is done when the worker can write **exactly one reasonable thing** from it.
  - A step that decides nothing ("handle edge cases", "add validation", "TBD") is a gap.
  - A function body the signature and the tests already determine is a transcript. Remove it.

**Plan header:**
- goal (one sentence);
- architecture (2–3 sentences);
- the design doc it implements;
- **Global constraints**, copied verbatim (toolchain, sqlx 0.9, money in satang, naming);
- **Review focus**: the inputs or failure modes the spec implies but no task tests, most likely first. Each line gets its test added to the task that owns the code.

**Self-review before release:**
1. Coverage: every requirement maps to a task.
2. Step scan: no gaps, no transcripts.
3. Type consistency: one name across all tasks (not `clearLayers` in one task and `clearFullLayers` in another).
4. Review focus: covered by tests.
5. Proportion: a plan longer than the code it describes has written the code. Cut it back to signatures and tests.

## 3. Execute: a fresh worker per task, a review after each, a broad review at the end

- **Each task goes to a fresh worker** through the queue (skills `queue-controller`, `lane-controllers`). The worker gets only the ticket, never this session's history.
  - Independent tasks are released together as a wave.
- **Pick the cheapest model that fits the role** (fleet table in `CLAUDE.md` 📨):
  - mechanical tasks ⇒ the implementer models;
  - judgement and integration ⇒ Claude;
  - review ⇒ Claude Opus at medium effort;
  - the **final whole-branch review** ⇒ the most capable model.
- **Review after every task, in two stages** (`software-design` § 8): first does it match the ticket and design, then quality. A failed review goes back to the same worker with the findings.
- **After every task in a feature is merged, one whole-branch review** runs before the `feat/*` → main PR. It catches the seams between tasks that per-task reviews can't see.
- **Keep a ledger that survives compaction.** Write it on the lane's umbrella ticket or in `.ai_context`: each task, its PR, state and merge sha.
  - After compaction, trust the ledger and `git log` over memory.
  - The costliest failure seen upstream is re-dispatching tasks that were already done.
- **Rulings:** decide the small ambiguities yourself and record each one where the next session reads it:
  `Ruling: <what> — <why> — <cost if wrong>` (on the ticket or in the design doc).
  - Unlike upstream, this fleet **stops and asks** for: migrations, the BLOCK groups, deploy, money paths, outward contracts, and anything `CLAUDE.md` § Must Stop And Ask lists.

## 4. Debug by root cause, in four phases

**No fix without a root cause first** (same rule as `CLAUDE.md` 🌱).

1. **Investigate.**
   - Read the whole error.
   - Reproduce it reliably.
   - Check recent changes.
   - In a multi-part system (CI → build → deploy, API → service → DB), log what enters and leaves each boundary once, to find **where** it breaks before guessing why.
   - Trace the bad value back to where it is created.
2. **Compare.** Find similar code that works, read it completely, and list every difference, however small.
3. **One hypothesis at a time.** Write "X is the cause because Y", then make the smallest change that tests it. Never stack fixes. "I don't understand X" is an allowed answer.
4. **Fix.**
   - Write a failing test that reproduces it.
   - Make one change at the root.
   - Verify (§5).
   - **After three failed fixes, stop:** the design is likely wrong. Bring the evidence to the owner (🔬) before a fourth.

Stop and go back to phase 1 if you catch yourself thinking: "quick fix for now", "let me just try X", several changes at once, "probably X", or "one more attempt".

## 5. No claim without fresh evidence

Before saying done, fixed, passing or merged:

1. **Identify** the command that proves it.
2. **Run** it fresh and in full.
3. **Read** the output and the exit code, never a piped tail (`CLAUDE.md` local facts).
4. **Only then** claim it, with the evidence beside the claim.

| Claim | Needs | Not enough |
|---|---|---|
| Tests pass | the test command, 0 failed, exit 0 | an earlier run; "should pass" |
| Build passes | the build, exit 0 | lint green |
| Bug fixed | the original symptom re-run and gone | code changed |
| Regression test works | red → green → **revert the fix, red again** → restore | it passes once |
| Worker finished | the PR diff and CI at its head | the worker's own report |
| Requirements met | the ticket's criteria checked one by one | tests green |

"Should", "probably", "looks right", "Done!" before running the command: each means you haven't verified yet.
