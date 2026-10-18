---
name: lane-controllers
description: |
  Playbook for running a lane as a controller of controllers: a top controller opens one sub-controller session per
  feature branch, each sub-controller fans the work out as one-function tickets to workers, and the merger lands one
  PR per feature on main. Use it when you are a lane or sub-controller, when the owner says "open a controller for X",
  "dispatch by function", "how many controllers / workers", or when planning, staffing, reviewing or closing a feature branch.
---

# Lane controllers: one controller per branch, one function per worker

Owner's orders, 2026-10-18, xchange (BE controller session claude/c81c8986):
- *"การจ่ายงานเป็น ฟั่งชั่น"* (dispatch by function; design `108-agent-queue/docs/design/function-dispatch.md`);
- *"คุณต้อง มี agent controller มารับงาน"* · *"คุณคือคนคุม agent controller อีกที่"* (you supervise agent controllers);
- *"คุณต้องแยก คนคุมงาน แต่ละสาขา เพื่อคุม การจ่ายฟั่งชั่น"* (one controller per branch);
- *"มันจะทำงาน จนจบ"* · *"แล้วปิดมันไป"* (each runs to the end, then is closed);
- *"ต่อไป คุณต้องเสนองาน แบบ นี้ มี controller กี่ คน ใข้ worker กี่คน"* (every proposal states controllers × workers);
- *"เพื่อให้ งาน สำเร็จ อย่างมีประสิทธิภาพ"* · *"ทำคุ่มือ การทำงานไว้ ด้วย"* · *"เพื่อให้ คนอื่น ทำตาม"* (write this down so others follow it).

## 1. Roles

| Role | Who | Does | Does not |
|---|---|---|---|
| Owner | — | business rules, migration approvals, deploy | — |
| Lane controller | one Claude session per lane | picks the next feature; opens a sub-controller session per feature branch; gives it orders; rules on cross-branch conflicts; brings owner decisions in one batch; checks main after each merge; closes finished sub-controllers | dispatch, review or merge inside a sub-controller's branch |
| Sub-controller ("AG controller &lt;X&gt;") | one session per feature branch | skeleton, function tickets, dispatch, review, merge into `feat/<x>`, early full suite, the `feat/<x>` → main PR | merge into main; touch another branch's files without agreeing the order |
| Merger | one session per repo | merges into main (single PRs and `feat/*` PRs), one CI run each, merge commit | review its own work |
| Worker | **Gemini** session (owner 2026-10-18: *"งาน ระดับ ฟั่งชั่นต้องให้ Gemini รับงานไปนะ"*) | one function, its own test only, PR into `feat/<x>`. Setup-fix tickets from the early full suite count as function tickets too | build on Dell; take an unpinned ticket; edit provided tests |

The lane controller hands work over with a handoff on the lane's notice issue (first line `> claude/<id> — handoff (<X>)`), then stops acting on it.

🔴 **Function tickets go to Gemini, never to a Claude session or a Claude subagent.** Claude sessions do control, the skeleton, the up-front tests and review. That keeps Claude quota for judgement and puts the volume work on Gemini.

## 2. A sub-controller's life

1. **Created by the lane controller** (`start_session`, fresh): its brief names the tickets, the rulings in force, its done line,
   the owner-approval points, and the other sub-controllers whose workers and files it must not take.
2. **Announces itself** on the notice issue and re-measures every row of its brief (a brief is a snapshot).
3. **Skeleton commit on `feat/<x>`** from `origin/main`: every new type and signature, `todo!()` bodies, every `mod` / registry line,
   the up-front tests. It must compile; the provided tests must fail at the `todo!()`; today's tests must still pass.
4. **Function tickets, all released at once**: one function per ticket, or one file when the queue's whole-file lock forces it.
   Base and PR target `feat/<x>`. Done line = that function's provided test green.
5. **Review each function** with only its tests; a must-fix of ≤30 lines is fixed by the reviewer (rules `f629c7a`).
   Merge into `feat/<x>` with a merge commit; close the ticket by hand (aq#960: no `pr_head` for non-main bases).
6. **Full suite on `feat/<x>` early** (Mac Studio), as soon as the core lands — not at the end. Every setup red becomes a ticket in the next wave.
7. **`feat/<x>` → main**: one PR, one CI run, runners switched on first, merged by the merger. The lane controller watches main's CI.
8. **Final report** on the notice issue; the lane controller archives the session.

## 3. Dispatching a function ticket (until `POST /v1/dispatch` exists)

1. Pick a worker: idle pane (no `esc to cancel`), right model (Flash = mechanical, Argon = logic/guarded), **never Dell for builds**
   (rules `e541b83`), not held by another sub-controller (`GET /v1/snapshot`).
2. One `gh issue edit`: `ready` + `class:` + `assign:<kind>/<id>`.
3. Send the order: ponytail line · **wait ~90 s for the pin to sync, then claim once** with `"assigned_only":true` · heartbeat loop ·
   new folder · branch from `origin/feat/<x>` · only the ticket's file · only the item-1 command · PR `--base feat/<x>` · `pr_open` ·
   one standing claim for the next pinned ticket.
4. Within 10 minutes check `GET /v1/ticket/...` shows `leased`. Not leased ⇒ read the pane; a claim sent before the pin synced
   returns `not_pinned` and the worker stops — tell it to claim once more.

## 4. Proposing and reporting work

Every plan to the owner is a table:

| Lane | Controller | Workers (count, machine, model) | Done when |
|---|---|---|---|

plus the totals against the workers really free now (count the panes), and the owner decisions in one batch.
Report each round: busy ÷ usable workers, what merged, what is stuck and why, what the owner must decide.

## 5. Traps seen on 2026-10-18

- A ticket cut "file-sized" grew to 20+ files once a worker measured it (BK-11, OR-7): when a worker's stop report lists many
  out-of-scope files, that is a feature, not a ticket — give it a sub-controller.
- Two sub-controllers can need the same file (OR-7 `domain/account/` vs RBAC): the later one waits, agreed on the notice issue; the lane controller rules if they can't agree.
- A provided test written before an owner decision may pin the old decision (the C1b test listed import rows after "no import"): the
  controller restates the test on `feat/<x>`, the reviewer fixes the code, both cite the owner's words.
- A red batch: fix and re-run only the failed tests; never push to re-run the whole suite (owner: *"ไม่ใช่ รันใหม่หมด"*).
- Migrations: write and merge only with the owner's approval; deploy is a separate order. Renumber with `scripts/migration-slot.sh next` right before `pr_open`.
