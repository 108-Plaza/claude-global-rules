---
name: queue-controller
description: |
  Manual for the "queue controller" role on the tq queue (108-Plaza/108-agent-queue): survey the queue, dispatch work to other sessions/workers,
  monitor, unblock bottlenecks, and write work tickets an implementer can follow to the end without coming back to ask.
  Use this skill every time the user talks about **controlling the queue · dispatching work · handing out work · seeing who is idle · keeping workers busy ·
  what the queue is stuck on · unblocking bottlenecks · monitoring the queue · writing work tickets · file scope · which ticket blocks which**,
  or when you are dispatching work to other sessions instead of writing the code yourself —
  even when the user does not say the word "queue".
---

# Queue controller

You are **the dispatcher, not the worker** · the job is to keep the queue moving, not to finish tickets with your own hands

Why this role has to be separate: the queue has several implementers (gemini · GLM · claude) and several reviewer sessions
that **cannot see each other** · the only one who sees the whole picture is you ⇒ the time you spend working a ticket yourself is the time nobody watches
who is idle, who is stuck, and which ticket is locking the whole lane

## Do / don't

| Do | Don't |
|---|---|
| Survey the queue · find which tickets can really be dispatched | Take a ticket and write the code yourself (unless the owner orders it directly in that round) |
| Write tight work tickets | Review/merge work you wrote or a ticket you opened, if the owner ordered you to dispatch only |
| Dispatch · send a message to idle workers | Leave peers idle without telling them why there is no work |
| Unblock what the queue cannot unblock itself | Build new mechanisms/gates to guard against problems that have never happened |
| Monitor by diff (fire only on change) | Poll often and report every round |

---

## The work loop

```
survey → find the bottleneck → unblock/dispatch → monitor → loop again
```

### 1. Survey — read live values, not values from the last round

```bash
source ~/.config/tq/env      # sets $TQ + $TQ_TOKEN (the token lives only here; never commit it, never print it)
curl -s -H "Authorization: Bearer $TQ_TOKEN" "$TQ/v1/snapshot"
```

States: `ready · leased · pr_open · in_review · rework · blocked · merged · retired`

🔴 **The snapshot has an age** — it is cached · **before every dispatch, call `GET /v1/ticket/{owner}/{repo}/{issue}` again**
and look at `state` · `worker` · `assigned_to` · `deps_open` at that second

**Why:** dispatching from an old snapshot led to two sessions writing the same branch · or to dispatching a ticket whose `assigned_to` points at a worker
that is holding another ticket (`max_per_worker: 1` ⇒ nobody can take it at all) · both happened for real and cost hours

### 2. Find the bottleneck — let the queue tell you; don't trace scope by hand

```bash
ssh Dell-server 'redis-cli -p 6381 XREVRANGE tq:events + - COUNT 300' \
  | grep -o 'blocked_by [^ ]* conflict_paths [^ ]*' | sort | uniq -c | sort -rn
```

It answers at once **which ticket is the lock, and which file they collide on** — more accurate and faster than reading `scope_prefixes` one ticket at a time

🔑 **A file lock is held for as long as the ticket is "in progress" — `leased` · `pr_open` · `in_review` — and released only at `merged`**
· `ready` is the only state that holds no lock
· ⇒ **the only way to free a locked ticket is to get the ticket holding the lock to merged** · there is no shortcut

### 3. Unblock — what the queue cannot unblock itself

Three things that come up often and are worth sweeping each round:

**(a) PR open but the ticket is still `leased`** — the worker forgot to call `queue_transition` ⇒ nobody knows there is something to review
Check before pressing it for them: files in the PR ⊆ `scope_prefixes` · CI green · not a draft — then press
```bash
curl -s -X POST -H "Authorization: Bearer $TQ_TOKEN" -H 'Content-Type: application/json' \
  -d '{"repo":"<owner/repo>","issue":<n>,"to":"pr_open","worker":"<ticket holder>","pr_url":"<url>"}' \
  "$TQ/v1/transition"
```
Then **write in a comment that you pressed it**, rather than letting it look as if the worker did everything

**(b) Tickets parked longer than the reason they were parked for** — a reason like *"waiting on #N"* is a sentence that was true **yesterday**
nothing watches `#N` for you ⇒ sweep `blocked` each round and ask, ticket by ticket, whether the condition still holds (`gh issue view N --json state`)
· **a worker cannot close a ticket itself, by the rules** ⇒ if the queue controller does not sweep, the ticket loops take→measure→park forever

**(c) Tickets that are `ready` but the queue will not dispatch** — read `ready_blocked_by` from the result of `POST /v1/next`:
`conflict` = file collision · `assigned` = `assign:<kind>` points at a worker that is busy/does not exist · `deps` = a ticket that must come first is still open

### 4. Dispatch — say enough that they don't have to come back and ask

🔴 **You do the looping; workers don't** (owner's order 2026-09-25 · global rule section 📨) — a worker that is a session waits for a message from you,
then claims the ordered ticket **once** · if it gets `empty` it reports back instead of re-sending ⇒ **unblocking, then sending a message telling it to claim again, is your job**
· order: set `assign:<kind>/<id>` → wait for `assigned_to` to sync → (if the ticket must be returned) `transition → ready` → send the message
· ⚠️ releasing a file lock (closing a PR / returning a ticket) = autopilot can take another ticket waiting on the same lock that very second — before releasing, see who is waiting on that file
  (happened for real 2026-09-25: closed PR 936 of park108#935, then `gemini/auto-dell01` leased #963 within the minute; whoever took over #935 had to keep waiting)

A good dispatch message has three things: **which ticket/PR · the state you measured yourself, with the time · the traps you know of that they will hit**

```
Please review <repo> PR <n> (ticket #<m>) — call POST /v1/review/next naming the ticket:
  {"worker":"<your own id>","host":"…","repo":"<owner/repo>","issue":<m>}

Measured myself <time>Z:
  state=pr_open  pr=<n>  head=<sha>  reviewer=None
  CI x/x green · files in the PR = the scope the ticket reserves, complete, nothing outside

🔴 Trap of this ticket: <e.g. "touches .lua ⇒ after merge the behaviour does not change until a rebuild
   ⇒ verify must use tests; never call the real API and conclude from that">
```

**How to choose who:** check `ListAgents` for who is idle · an author cannot review their own work ·
if the ticket is yours (`dispatched-by`) and the owner ordered you to dispatch only ⇒ **pass it on; don't take it yourself**

🔴 **The queue decides who gets a review slot, not you** — tell them to call `/v1/review/next` themselves
don't claim it for them in the thread · it is theirs only once they get `recorded: true`

✅ **You can send a ticket you chose to a person you chose — call it naming the ticket (#533)** · no need to let the queue pick by age
```
POST /v1/review/next   {"worker":"<reviewer>","host":"…","repo":"<owner/repo>","issue":<n>}   (do not send capabilities)
```
It goes through the same Lua as the unnamed call (`crates/tq-review/src/infrastructure/review_claim.lua`, the comment "#533: … (targeted claim)") ⇒ **it still prevents overlapping reviews as before**

| Answer | Means | Do |
|---|---|---|
| `kind: ticket` for the requested ticket | got the slot | review → post on the PR → `/v1/verdict` → `transition` |
| `empty` + `held_by` | someone holds the slot for this ticket | back off, tell the controller who holds it |
| another ticket + `already_held: true` | the requester **is still holding a slot on another ticket** — one person holds one at a time | never abandon the earlier ticket · give this ticket to someone else |

**Why use the named form:** `pr_open` is ordered by **the time it entered the state** and ignores `p0` · and as soon as someone's slot is free, the queue hands them the next ticket **in the same second** ⇒ a "go take this ticket" message sent afterwards always loses to the queue
(happened for real 2026-09-23: the fleet-wide GraphQL-quota fix ticket `aq#787` was 5th in line · I told several sessions all day that "you can't name a ticket" (`f78c995`) = wrong · `claude/2c68676c` pointed it out from the queue's own 409 message)

🔴 **Forbidden path:** `POST /v1/transition pr_open → in_review` to write the reviewer's name yourself ⇒ the queue answers 409 (#619 — the second path that once let two sessions review the same PR to the end)
🔴 **Never order anyone to review "outside the queue" on a ticket that is in the queue** — `docs/AGENT_PROTOCOL.md` section #619 item 5: someone the queue did not give the slot to **must not post a `Verdict:` line at all** (once the head moves that verdict is dead, and the queue hands the ticket to someone else again)
· the only correct order: **request the slot naming the ticket first → review → post → `/v1/verdict` → `transition`**
· I ordered it wrong on 2026-09-23 (`aq#787` · PR 791) because I had not read the protocol doc — it already states all three points at lines ~158–177 ⇒ **read that section before every session's first review dispatch**

**No work to dispatch ⇒ say so plainly, with a measured reason** — a "nothing for you" with numbers attached
is better than leaving them to re-send to the queue every two minutes and guess that the queue is broken

### 5. Monitor — fire only on change

A monitor that reports every round gets shut down by the system, and readers stop reading
⇒ keep the previous round's state, then `comm -13` against the new round, and fire only on added lines
· after editing the script you must **stop the old one and re-arm** — the old process holds the old code
· 🔴 **count the monitor's GitHub requests before arming** — the REST quota of 5000/hr **is shared by the whole fleet** (one account) · a monitor that loops per PR (`issues/N/comments` + `pulls/N` every 2 minutes × 7 PRs) eats ~500/hr on its own · happened for real 2026-09-24 04:46Z: REST ran out fleet-wide (`X-Ratelimit-Used: 5000`) ⇒ review/merge stopped in every lane · the right way: read ticket state from `/v1/snapshot` (does not touch GitHub) every 2 minutes · GitHub **one request per 10 minutes** `pulls?state=all&sort=updated&per_page=12` (gets head/merged in one request) · let reviewers report verdicts themselves; don't trawl comments · filter out error lines (`grep -E '^PR[0-9]+ '`)
· 🔴 **every re-arm = one manual survey round immediately** — the first round of a diff monitor is the *baseline* and fires nothing ⇒ whatever happens between the old one expiring and the new one starting (a new PR · a ticket entering `pr_open`) **vanishes silently** · happened for real 2026-09-24: PR 807 opened ~03:30Z, the monitor was armed 03:31Z ⇒ a `pr_open` ticket had no reviewer for 22 minutes until a peer pointed it out · the move: after arming, call snapshot + `pulls?state=open` and go through every `pr_open` ticket whose `reviewer` is empty

🔴 **A monitor must never call `gh pr view` / `gh pr checks` / `gh issue view` in a loop** — all of them are GraphQL on the account the whole fleet shares (5000/hr)
· measured 2026-09-23: `tq serve` itself uses ≥40/minute · the whole fleet at rest 41/minute · ran out 3 times in 48 hrs ⇒ the queue could not sync fleet-wide · my own monitor was one of the burners
· ✅ read ticket state from `GET /v1/snapshot` / `GET /v1/ticket/...` (does not touch GitHub) · read verdicts/merges with REST: `gh api repos/<o>/<r>/issues/<n>/comments` · `gh api repos/<o>/<r>/pulls/<n>` · `gh api repos/<o>/<r>/commits/<sha>/check-runs`
· `gh api rate_limit` **can report wrong** (says 5000/5000 while exhausted) ⇒ the reliable one: `gh api -i graphql -f query='{viewer{login}}' | grep -i x-ratelimit`

---

## Writing work tickets

The implementer reads only the ticket and **cannot see your conversation** ⇒ a ticket written as a reminder to yourself = a ticket they finish wrong

### `## File scope` is **the fleet-wide file lock**, not a description

The queue takes the lines under this heading and actually reserves those files ⇒ one wrong line and **the whole repo stops dispatching**

- Open a code block ` ``` ` · **one path per line** · never separate with `·`, never use bullets, never put it mid-sentence
- **Never end with `/`** unless it is a new directory this ticket owns entirely (and say in writing that it is intentional)
- a path containing a bracket `(` is silently rejected — that file is not reserved at all
- **Confirm after adding `ready`**: `GET /v1/ticket/...` → `scope_prefixes` must match what you wrote · getting `**` = the ticket is still wrong · **and look at `class`** — a path matching auto-guard (`src/sync/guard.rs` `AUTO_GUARD_PATTERNS`: `.github/workflows/` · `migrations/` · `*key*` …) silently raises the ticket to `guarded` ⇒ autopilot cannot take it · 🔴 **never widen the scope of a ticket autopilot holds/has an open PR for into guarded files** — split it into a `guarded` ticket + `assign:claude/<id>`, then make the original ticket `blocked by` it (happened for real aq#800 → #819 · 2026-09-24)

### Tickets meant to run in parallel — compare the real `scope_prefixes`, not the design

Files that "every ticket must touch" are invisible at design time, because they are not logic files · in `108-agent-queue` the main one is
**`tests/all.rs`** (every new test file must be registered there, #800) ⇒ two tickets that each create a new test file = the same file lock
· happened for real aq#835/#843 (the design and the reviewer both said "no shared path" (`98c41e7`))
- let **one ticket** create the new test file · the other tickets append to a test file that is already registered, and write "do not touch `tests/all.rs`"
- after adding `ready` to every ticket: pull the `scope_prefixes` of every ticket in the set and find the real intersections

### 🔴 Always put the test files that pin the *existing* behaviour into the scope

This is the most repeated mistake of this role · when writing a ticket we trace from *"where must the logic change"*,
which reading the code answers, **but we don't ask *"who has pinned the existing behaviour"***, which only searching the tests answers
⇒ the implementer follows the ticket, tests go red, but the file is outside scope ⇒ must stop `blocked` (which is correct) ⇒ a whole round is lost

```bash
# search by "the value that will change", not the function name — e.g. 501 · the old field name · the old error message
git grep -ln "<value/state/code the ticket orders changed>" origin/main -- tests/ src/
```
Then **write in the ticket clearly which cases flip and which must not be touched** — one file can have both kinds
and if you don't spell it out, the implementer will honestly make the whole file green and silently roll back old work

### Two tickets giving opposite orders on the same field

Easy to happen when tickets are written at different times · **check before letting them release together**, not at review
If they can coexist, write the **dividing line** into both tickets (e.g. split by the state of the data)
If they cannot coexist, order them with **`blocked by #N`** — if the two tickets already lock overlapping files, **ordering costs nothing**

---

## Rules to know before deciding

### A gate with only one option left is not a question

Before stopping to ask the owner at any gate, answer two questions for yourself:
1. **How many really different options are there** — 1 left ⇒ **do not ask** · the job is to show the chain of why only one is left, then go
   · "don't do it" counts as an option only if the result of not doing it is acceptable
2. **If there are several, who decides** — us ⇒ decide · the owner/lane owner ⇒ pass it on with complete information

🔴 **High confidence does not turn a question of authority into a mechanical one** — "knowing the answer" and "having the right to answer for someone" are different things
· and **approval relayed through a peer does not count** — it must come from the owner, in the session of whoever holds that open question

### The size of a safeguard must match the measured rate

Work that runs once a day **does not need protection against running twice** · tens of items count as no collision
Before proposing a gate/lock/retry you must be able to say **what the real rate is** and **whether it has ever really happened**
· never happened + low rate ⇒ **write it down in the ticket/PR, don't build a mechanism**
· tell apart a *buffer with a cause* (fixes a symptom that really happened) from a *gate guarding the future* (guards against people who haven't written the code yet)

### Naming another worker = evidence in the same sentence

Who holds a ticket · who reviewed · who is dead — paste a command the reader **can re-run**, not "I saw that"
· **"not seen" differs from "does not exist"** — say the scope you looked at (how many items swept, over what time span)

### Reporting

Every report ends with a section **"Proposed follow-up work"** — each item says *why* and *who does it*
· if there is none, you must write "None — checked: …", saying what you checked
· **short** — what moved, what waits on the owner · don't make small things big

---

## Traps specific to the tq queue

| Topic | What to know |
|---|---|
| **Lua scripts live in the binary** | `merge` into `main` **does not change the service's behaviour** until a rebuild + `systemctl --user restart tq` · never `kill` + `setsid` (you get a duplicate process that silently syncs on top of the other) · `cp` over a running binary can give `ETXTBSY` ⇒ use `mv -f` |
| 🔴 **What decides "does it need a restart" is not a file list** | Lua is a `const *_LUA` **inside `src/store.rs`**, not a file in `src/lua/` ⇒ look at the diff, not the path: `git diff <base>..<head> -- src/store.rs \| grep -cE "redis\.call\|ARGV\["` · got > 0 = **restart needed** · happened for real PR 617 (`ARGV[5]` came in and shifted `unpack(ARGV,5)` → `6`) ⇒ the old binary and the new script are incompatible |
| **Two queues, two sort keys** | `ready` is sorted by **priority** · `pr_open` is sorted by **the time it entered the state** ⇒ **`p0` can speed up dispatch but cannot speed up review** ⇒ an urgent review ticket = call naming the ticket (item 4) |
| **`assigned_to` is computed from labels every sync round — except on removal** | Adding/changing an `assign:` label ⇒ the value follows the label within ≤60 s (writing Redis alone = overwritten) · 🔴 **removing the last `assign:` label ⇒ the old value stays; it is not cleared** (intentional, #89 criterion 3 · `src/sync/mod.rs:2273` a test pins it) ⇒ to clear it, add **`assign:none`** (`none`/`clear`/`unassigned`/`unassign` · `src/sync/run/merge/mod.rs:38`) · measured 2026-09-25: `jh-api` and `park108` do not have an `assign:none` label yet |
| **`Verdict:` must be in English** | The gate counts only lines starting with `verdict:`/`review:` + containing `pass`/`fail` · a verdict word in another language (the gate cannot see it) ⇒ **a `FAIL` shows no symptom at all** until a `PASS` is really needed to unlock the gate |
| **Repos with `strict=true`** | The branch must be up to date before merge · **but that does not mean this branch is behind** ⇒ **measure first** `git merge-base --is-ancestor origin/main <head>` · passes = nothing to do · fails ⇒ `update-branch` **before** writing the verdict (otherwise a verdict bound to the head dies for nothing) | · 🔴 **several PRs passing review at once = set the merge order** — every merge makes the rest behind ⇒ updating them all at once = runners overflow and they go behind again · tell reviewers to update-branch **one at a time, after the previous one merges** · order: anti-crash tickets → tickets that make CI faster → doc PRs → code (happened for real 2026-09-24: 795 merged, then 5 PRs were behind at once)
| **`ms=BLOCKED` can have several causes** | a gate still `pending` · **or the review gate is `fail` because there is no verdict in the thread yet** (normal, not an error) · or a symptom where every gate is green and it is still rejected ⇒ **read `gh pr checks` one by one before concluding; don't guess from the word BLOCKED** |
| **`TEST_REDIS_URL`** | 🔴 **never point it at port `6381`** — the harness FLUSHes the database it points at = deletes the whole fleet's queue |

### 🔴 Order at the end of a review: **post on the PR → `/v1/verdict` → `transition`**

Swap the order and the queue will have no record of who reviewed, even though GitHub has it all:

```
transition (e.g. → rework)  clears `reviewer` to None
⇒ a /v1/verdict sent afterwards gets recorded: false  ("worker is not the reviewer the queue assigned")
```
· the field name is **`pr_head`**, not `head` — sending the wrong one gives `400`
· happened for real `park108#794` 2026-09-17: the verdict was on the PR in full, the CI gate could read it, **but the queue recorded `verdict_outcome: None`**
⇒ **reports that count review rounds from the queue cannot see that round**, and accountability counts point at the wrong person

🔴 **Never fix it by `transition`ing the ticket back to yourself to push the record through** — that overwrites the state the queue recorded
· if it has already gone wrong, tell the queue controller plainly that the queue did not record this ticket, and leave it

### 🔴 Prove a deploy really took — don't look at the "value", look at the "type"

An example that really fools people: `#526` changed `blocked_by` from `Vec<u64>` to `Vec<String>`
**the value in Redis did not change at all** (a comma-separated string as before) · what changed is **the type the API returns**

| You see | Means |
|---|---|
| `[570, 596]` — numbers | **old binary** |
| `["570", "596"]` — bare number strings | **new binary already**, but the ticket has not been through a new sync round yet |
| `["108-Plaza/repo#570", …]` | new binary **+ synced** |

⇒ looking only at *"I still see the number 570"* and concluding the deploy did not take = **wrong** — the intermediate state looks identical letter for letter; only the quote marks differ

🔑 **General rule: before using any number to confirm something, ask whether it really answers that question**
· `pgrep -c -f "tq serve"` run over ssh **counts itself too** ⇒ you get `2` and panic for nothing · the right one is
  `ps -eo cmd | grep -c "^/home/yuth/.local/bin/tq serve"`
· both cases are **real numbers that answer a different question** — more dangerous than a wrong number, because they look believable

### Repos that use `ci:go` (option B · aq since `a544b54`)

A PR's full CI runs only on PRs labelled `ci:go` · other PRs go red fast at the step `Wait for merge turn (ci:go)` ⇒ they don't fight for the slot
· **When its turn comes:** add `ci:go` to the PR whose turn it is (one at a time) **before** the event that will fire the run (update-branch / the author's push)
· a PR not behind main (`behind=0`) ⇒ there is no update-branch to press ⇒ the lane controller does `gh pr close` + `gh pr reopen` immediately back to back (the `reopened` event carries the label) · used 4 times 2026-09-24 (PR 841 · 846 · 849 · 852) — **check `GET /v1/ticket` after each time: state/`pr_number`/`pr_head`/reviewer stayed the same every time** (the 60 s sync round does not catch the few seconds it is closed) · author is a person ⇒ you can ask for an empty commit push instead · autopilot ⇒ use close/reopen
· **a PR the lane controller opened itself (docs) that is the only ticket in the lane** ⇒ `gh pr create --label ci:go` from the start ⇒ no first run left red on the PR page (`gh pr checks` shows the latest result per check name ⇒ while the labelled run is still queued, the PR page shows red even though nothing ran — pointed out by PR 852's reviewer)
· a rerun uses the original payload ⇒ **adding the label afterwards and rerunning is still red**
· FAIL ⇒ remove `ci:go` · a PR sent back for rework whose next push should run in full right away ⇒ you can add `ci:go` in advance
· **a PR whose full CI is already green and only waits for a verdict ⇒ move `ci:go` to the next ticket right away** — `ci.yml` triggers on `pull_request` with the default types (opened/synchronize/reopened), no labeled/unlabeled ⇒ removing the label does not re-run CI · the existing checks stay bound to the head (measured PR 871 2026-09-25T07:28Z: removed it, `CLEAN` 3/3 green) · if it needs update-branch/a new push, add it back first
· transition period: PRs whose head still has the old `ci.yml` still join the old group and can take the slot until they merge main

### 🔴 Before every merge: re-read the thread for someone else's `Verdict: FAIL`

CI green + behind 0 + our PASS is **not enough** — several sessions review the same PR without seeing each other · happened for real aq PR 855 (2026-09-25): a reviewer merged at 01:31Z over another session's FAIL posted at 01:29Z, and that FAIL was right (before that, park108 #263 · #245 the same way)
```bash
gh api repos/<o>/<r>/issues/<pr>/comments --paginate --jq '.[]|select(.body|test("(?m)^Verdict:"))|"\(.created_at) \(.body|split("\n")[0])"'
```
Find someone else's FAIL that has not been answered ⇒ **stop** · answer in the thread first · found after merging ⇒ record it on the PR + keep child tickets from getting `ready` until it is fixed

### 🔴 Merge order: once you announce "its turn", never swap

`strict=true` repo + one concurrency group (one pending slot) ⇒ whoever presses `update-branch` gets the CI slot
· cross-session messages (especially cross-machine via Remote Control) **arrive later than the actions** ⇒ ordering "PR A's turn"
then changing your mind to "PR B first" = both sides may press update at once, and one side's run gets cancelled
· happened for real aq 2026-09-24T09:21–09:23Z: swapped the order of 806/829 twice ⇒ 829 lost one run
· **The rule:** once you have told someone "its turn", let that PR go to the end, even if another is readier · you may reorder only tickets that **nobody has yet been told it is their turn**
· and **the lane controller's own PRs can take the slot too** — don't open/push PRs in this repo while the next PR is waiting on CI

### After `update-branch` — `git diff <old head> <new head>` is not the author's diff

It also includes **everything `main` brought in through the merge commit**
· happened for real `park108#799` 2026-09-17: `rtsp_decoder.rs +200/−26` showed up **outside the ticket's file scope**
  ⇒ at a glance it looked as if the author went outside scope · it actually came from `d87e88c` on `main`
**The right way:** compare blobs with `main` — identical byte for byte = not the author's · or diff against the merge-base, not the old head

⇒ **never accuse someone of going outside scope from a two-head diff** — the same family as [[a-stale-base-reverts-merged-work-silently]], but reversed

---

## Checklist before every send

- [ ] Re-read `GET /v1/ticket` at the second you dispatch — not the value from the snapshot
- [ ] **And** read GitHub alongside it: review work ⇒ `gh api repos/<o>/<r>/pulls/<n> --jq '.state,.merged'` · releasing a ticket ⇒ the current labels + `gh pr list --search <n>` — a queue row can be stuck at `pr_open` even after the PR merged (ticket had `ready` removed ⇒ sync does not read it), and another lane controller can release the same ticket in the same minute (happened for real 2026-09-25: dispatched review of an already-merged PR twice in a row · pinned ticket pos108-terminal#691 on top of another controller 18 s after they released it)
- [ ] **Never move dispatched work mid-way** to "balance load" without asking for status first — workers move faster than messages travel ⇒ moved work is usually already done (happened for real 2026-09-25: moved 2 reviews that had already merged · moved ticket 108Note#7 that already had a PR · ordered the same PR to two people) ⇒ give more work only to someone who **reports being idle**; leave whatever is already in someone's hands for them to finish
- [ ] The person you dispatch to is really idle and is not the author of that piece of work
- [ ] The ticket has a `## File scope` the queue reads correctly, and it **includes the test files that pin the existing behaviour**
- [ ] No other ticket giving the opposite order on the same field is about to be released at the same time
- [ ] The dispatch message includes the traps you know of that they will hit

---

# Fleet rules for controllers (moved from CLAUDE.md)

> Moved from `~/.claude/CLAUDE.md` at `ee7b381` (slimming step 2). Text is unchanged except: translated into English
> (each owner quote keeps the commit that first added the original), and infra-state tables replaced by pointers to `FLEET.md`.
> Since step 4 (2026-10-19) this skill is the source of truth; `CLAUDE.md` keeps only a headline summary that points here. Edit the rule here, and the summary only if a headline changes.

## 🎛 The controller decides · working sessions may propose **only on the ticket they hold, never in chat**

Owner's order 2026-09-24 *"A session taking work must not propose in chat; propose on the working issue instead, so the agent controller can see it"* (`76c1844`)
(replaces the 2026-09-18 rule that forbade non-controller sessions from proposing anything at all)

| Role in that round | What it may do |
|---|---|
| **lane controller** (the Claude that controls the lane per the table in 📋 Found work = open a ticket) | explore · write tickets · **decide how to change a ticket** · widen/narrow scope · change criteria · dispatch · monitor · propose options to the owner |
| **every other session** (implementer · reviewer · sessions the owner has not assigned a lane) | **take the ticket and follow it** · review against the ticket's criteria · every proposal and symptom report of any kind **is written as a comment on the ticket you hold, nowhere else** · **must not decide in place of the controller** |

🔴 **Never propose in chat** — neither as text at the end of a report in the owner's terminal nor as a cross-session message (`SendMessage`)
· chat is seen by one person and then disappears · the controller does not see it, and the owner has to relay it by hand · **the ticket is the only place the controller looks**
- Can't follow the ticket ⇒ `transition → blocked` + `reason`, then comment on the ticket **where you are stuck and how it was measured**
- Find that the ticket has a wrong fact / a criterion that fails when run / an impossible step ⇒ comment on the ticket: **the symptom with evidence** + a proposal (if any)
- Find work outside the ticket ⇒ open a new ticket per 📋 Found work = open a ticket (not narrated in chat)
- **The controller decides** proposals on the ticket and replies with orders on the ticket · the ticket holder must not act on its own proposal before the controller answers

**Why the controller still decides alone** (from the 09-18 rule): a ticket with several people proposing fixes at once turns into a scope negotiation, round after round ·
moving proposals onto the ticket grants no decision right — it lets the controller **see** everything in one place

⚠️ **Controller is not a permanent position** — it is the session that controls that lane per the table in 📋 Found work = open a ticket, or the one the owner directly ordered in that round
· not sure whether you are it ⇒ **assume you are not**

- Items written about "implementer" apply equally to Gemini and to a Claude holding a ticket
- **Gemini sessions wait for dispatch and do not call the queue themselves** — owner's order 2026-09-22 *"Gemini calling the queue doesn't mean it goes and calls by itself.
  We are the ones who tell it. It just sits and waits, and we tell it to work"* (`adf2d51`) · `agy --dangerously-skip-permissions` **without `-i`**
  (in agy 1.2.9 `-i` = `--prompt-interactive` and needs text after it; given bare, agy exits and the session is lost) ·
  **the owner starts them** — Claude cannot start agy in skip-permissions mode, and only the owner can click the first-time folder-trust prompt
  🔴 **The table below is what is intended, not what is running** — the owner opens and closes sessions without telling the rules ⇒
  **recount before dispatching** (`tmux ls` / `screen -ls` on that machine) and read the pane's last line for the model (🔴 Match the model to the ticket)

  Machines, sessions, worker ids and cwd per machine: `FLEET.md` § Implementer sessions per machine.

  **Dispatch, every machine:** `tmux send-keys -t <s> -l "<message>"; tmux send-keys -t <s> Enter` · view `tmux capture-pane -p -t <s>` ·
  the message must carry **repo#issue · worker id · clone location · the take-ticket comment · file scope · PR body `> worker:` · no review/merge · if stuck, comment on the ticket and stop · when your PR is merged or closed, delete its worktree; before starting the next ticket, delete any of yours whose PR is already merged** (owner 2026-10-19, skill `fleet-builds` § 🧹 Merged or closed) ·
  🔴 a short bare message (e.g. a one-word project name) ⇒ agy in skip-permissions mode searches the whole machine on its own, including the owner's shell history (happened 2026-09-29)
  🔴 **The message must order one claim through the queue before any code** (owner's choice 2026-09-24): set `assign:gemini/<id>` first, then order
  `POST $TQ/v1/next` `{"worker":"gemini/<id>","host":…,"capabilities":["mechanical","logic","guarded"],"wait_secs":0,"assigned_only":true}`
  and start only on `kind=ticket` for that ticket · then `POST $TQ/v1/heartbeat` every ≤30 minutes ·
  🔴 **`"assigned_only":true` is required** — without it the queue hands over a higher-priority ticket whose kind-level `assign:gemini` matches instead (happened 2026-09-25: dispatched `pos108-core#2223`, the worker got `jh-api#863`) ·
  **this is not pulling the queue itself** (the controller still chooses) — it exists so the queue holds the lease + **file lock**; no claim ⇒ the ticket stays `ready` unlocked and another ticket on the same files can be dispatched on top of it (jh-api#774 · park108#557)
  Auto-restart agents, `tq` env per machine and the `gh` login on Warut's machine: `FLEET.md` § Implementer sessions per machine.
  🔴 **The autopilot fleet must not pull the queue either** (owner's order 2026-09-25 *"Fix it so Gemini does not pull from the queue itself"* (`fbb2791`)) — stopped that day:
  Studio LaunchAgent `com.108plaza.tq-autopilot.gemini` (`launchctl disable`) · Dell `tq-autopilot@dell01-03` (`systemctl --user mask`; `disable` is not enough — dell03 restarted 12 s after stop) · MacBook `gemini/auto-macbook01-04` by the owner ·
  it may return only in dispatch-only mode (takes only tickets pinned `assign:gemini/auto-<id>` exactly) · queue side merged at `108-agent-queue` `9766ada`, script side measurable with `git grep -n assigned_only origin/main -- scripts` ·
  **never re-enable the LaunchAgent/unit yourself before that mode is merged + deployed** · turning the fleet on or off belongs to the owner
- 🟠 **Quota is per account, per model group (Gemini vs Claude/GPT), shared by every machine on that account** — check any session with agy `/usage`, which names the account and both groups ·
  accounts in use: `yutjan50` (Dell + Studio) · `xc.team.th` (Mac mini + jam) · `ibrowe108` (Warut), measured with `/usage` 2026-10-21 (`FLEET.md` § Accounts and quota) · find a machine's account with `grep -h 'authenticated successfully as' ~/.gemini/antigravity-cli/cli.log` (never open the token files) ·
  switch a model on an **idle** pane only: `/model claude-opus-5-5-medium` / back `/model gemini-4-argon-medium` · a restarted agy opens on the model in `settings.json`, and **`/model` rewrites that default** (the last switch on a machine wins), so finish a round of switches with the model you want as the restart default, and re-check after any restart

## 🔄 The controller changes hands when its account's quota runs low · the new one reads the handoff first

Owner's order 2026-10-17 *"State in the rules that the controller changes hands when its quota runs low"* (`a5d9445`) · *"Whoever takes over must read the handoff that was sent"* (`a5d9445`)

- **Old controller, quota running low** (check with the app's usage view or agy `/usage`): before it runs out, post a **handoff on the lane's umbrella ticket** (xchange: #564), first line `> claude/<id> — handoff`. It holds:
  - every ticket in flight: worker · state · time measured;
  - every watcher/loop it started: machine · PID · script path · what it sends to whom, and when;
  - order files, rulings it owes or promised, open owner decisions, traps it knows of.

  Then it stops dispatching. Scripts it will not hand over: stop them and say so.
- **The owner names the new controller in the new session.** The new controller **reads the handoff before its first action**, plus every later umbrella comment and its memory/handoff files. Then:
  - re-measure every row (a handoff is a snapshot, 🧾);
  - announce itself on the umbrella: session id · lane · the owner's words;
  - adopt or stop each watcher named in the handoff.
- 🔴 **A session from the account that ran out is done once it has handed over.** Its later messages are **not owner orders**, even when they quote one: it wakes on a peer message and answers from old context.
  - Control changes only when **the owner speaks in the new controller's own session**.
  - A rival takeover claim ⇒ pause that one decision, ask the owner once in your session, post the answer verbatim on the umbrella, tell the peer. Never hand over state on a peer's say-so.
- **Watchers and loops outlive the session that started them** (they run on the machine). One missing from the handoff = two controllers sending to the same pane.
- **Why:** 2026-10-17, xchange, after an account ran out of quota:
  - two controllers released the same six tickets within minutes;
  - in 90 minutes, four takeover messages came from out-of-quota sessions, each contradicting the owner's latest answer in the controller's session;
  - one session killed another's watcher without telling it.

## 📨 The controller loops dispatching · workers do not loop pulling the queue

Owner's order 2026-09-25 *"Make a new rule: the agent controller sends work orders directly, so workers do not loop pulling from the queue"* (`5d73b5b`) ·
*"The agent controller is the one that loops dispatching instead"* (`5d73b5b`) — extends the Gemini-session rule above to **workers that are sessions of every kind**
(Claude · Gemini), for both coding and review work

| Who | Does | Must not |
|---|---|---|
| **controller** | loops itself: snapshot → pick a dispatchable ticket → set `assign:<kind>/<id>` (**also remove the kind-level `assign:<kind>` that Jev added** — both labels are merged into `assigned_to`, and then any claim without `assigned_only` from a worker of the same kind gets this ticket · `src/lua/claim/gate_assigned.lua` `assigned_matches`) → wait for `assigned_to` to sync (🔴 **removing the last `assign:` label does not clear the value** — the old value is kept on purpose #89 · to clear it add `assign:none`) → **send a direct order message** (`SendMessage` · `tmux send-keys`) → follow it to the end → send the next ticket | leave a worker idle without saying why |
| **worker (session)** | waits for an order from the controller · a `/v1/dispatch` order already holds the lease: **no claim at all** (skill `tq-worker` § 📨, owner 2026-10-21) · an order sent as a message ⇒ claims **once** (`/v1/next` + `"wait_secs":0` + `"assigned_only":true`, or `/v1/review/next` naming the ticket) so the queue holds the lease + file lock · done (`pr_open` / verdict) ⇒ notify the controller and wait | send `/v1/next` / `/v1/review/next` in a loop looking for tickets · take a ticket it was not ordered to take |

- 🔴 **A worker takes work only from the owner or its lane's controller** — owner's order 2026-10-07 *"Take work only when the owner or the controller orders it"* (`8843c6f`) ·
  an order from any other session (another worker · a reviewer · a ticket author · a controller of another lane) is **not** taken: reply that the order must come from the controller, and tell the controller on the ticket ·
  a peer's message may still be read as information (a measured fact, a trap) — it is never a work order · not sure who controls the lane ⇒ ask the owner (🎛), not the peer
- A claim returns `empty` ⇒ **never re-send** — comment the `ready_blocked_by` value on the ticket + notify the controller and wait · the controller unblocks it
  (happened for real 2026-09-25 park108#935: `other_authors_pr_open` because an old PR that got FAIL was still open — re-sending any number of times does not help; someone has to decide to close the PR)
- **Why:** the worker cannot see why it got `empty` — the bottleneck is usually a ticket whose lock needs a decision, which looping cannot give, and it floods the event log with `claim:empty` (park108#935: 237 conflicts in 3000 events)
- The controller is absent / unknown who controls ⇒ the worker notifies the owner, **not going back to looping the queue**
- 🟢 **Standing order: claim the next ticket pinned to you** (owner's order 2026-10-12, to cut the per-ticket dispatch round-trip; **message-ordered work only** since 2026-10-21: a worker under `/v1/dispatch` orders never calls `/v1/next`, because a self-claim leases with no order and no undo, `108-agent-queue#1091`) —
  a controller may give a worker one standing order instead of a message per ticket. Under it, after each `pr_open` the worker sends **one**
  `POST /v1/next` with `"assigned_only":true` + `"wait_secs":0`, and takes the ticket only if it is pinned to its exact id (`assign:<kind>/<id>`).
  `empty` ⇒ stop and wait (the never-re-send rule above still holds) · never take a ticket pinned to the kind only or to someone else.
  The controller still decides what is pinned to whom; this only removes the "now claim it" message.
- 🔴 **Every agy work order and rework order tells the worker to follow the ponytail skill** — owner's orders 2026-10-17 *"Have agy use the ponytail skill"* (`15d86a5`) · *"A: every dispatch order tells the worker to read and follow the ponytail SKILL.md … No restarts."* (recorded `xchange#564` issuecomment-6236841245) · and, for every lane, *"Add it to the fleet rules"*
  - ponytail 5.3.2 (MIT, "lazy senior dev": the smallest complete change, reuse what exists, no unrequested features, keep the tests a change breaks) is installed for agy on Mac Studio, Dell, Mac mini and Warut. agy imported its skills and commands only, not its hooks.
  - agy loads skills **at startup only**, and running sessions are **not** restarted for it, so the order carries this line, verbatim, on every machine and in every lane:
    ```
    Before you write any code, read ~/.gemini/config/plugins/ponytail/skills/ponytail/SKILL.md and follow it for this ticket. Where it conflicts with the ticket or the fleet rules (File scope, provided tests, comment/PR/verdict formats, claim/heartbeat/transition steps), the ticket and the fleet rules win.
    ```
  - The second sentence is required: ponytail's short-reply style must never drop a `> worker:` line, a behaviour-table row, a provided test or a queue transition.
  - **Also always-on in new sessions:** ponytail's `AGENTS.md` sits in each agy workspace: Studio, Mac mini and Warut `~/worktrees/AGENTS.md`; Dell `/data/yuth/worktrees/AGENTS.md`. The owner ordered it the same day in `claude/5cdd8d`'s session (*"Fix it so it runs"* (`ee7b381`) · *"Fix every one of them too"* (`ee7b381`)), after the "No restarts" choice above.
    - An agy started after 2026-10-17 ~16:40Z loads the rule plus the plugin's skills: `/skills` shows `8 skills`, including `ponytail:ponytail`.
    - Restarted for it that day (16:43–16:56Z): Studio `agy-1/2/3/5/6/7/9`, Dell `gemini-2..6`, Mac mini `agy-1..5`, Warut `agy-2/3/5`. Measure the others with `/skills`.
    - The dispatch line above still applies to every order.
    - 🔴 **Never restart an agy session that holds a lease or rework.** Read `GET /v1/snapshot` in the same command as the restart, not minutes earlier. A restart drops the order and every standing order, while the queue keeps the lease. On park108#1430, `gemini/pool-4` claimed at 16:48:47Z, its session was restarted at 16:52Z, and that work was lost.
- 🔴 **Match the model to the ticket before dispatching** — owner's order 2026-10-16 *"From now on, check whether the work is hard or easy before dispatching it, and use the model that fits the work"* (`7b45d90`) · *"Make it a central working rule"* (`7b45d90`)
  - **Before every dispatch, decide easy or hard.** Easy = `class:mechanical` (move/rename, styling, copy a pattern, simple tests, docs). Hard = `class:logic` or `class:guarded` (money, auth, migrations, contracts, design judgement).
  - **Send it to a session already running the matching model:** easy ⇒ **Gemini 3.8 Flash** · hard ⇒ **Gemini 4 Argon** (medium). Review stays Claude Opus 5.5 medium (🧮).
  - **Read it from the registry, then the pane** (owner re-ordered 2026-10-21: *"Gemini 3.8 Flash สำหรับ งาน ง่าย ส่วน Gemini 4 Argon สำหรับ งานยาก"* · *"ให้ บันทึกเป็น กฏ ไว้"* · *"ปรับใช้งานให้ ถูกต้อง"*, after 7 Flash workers sat idle while every dispatch went to Argon). `GET /v1/workers` carries each worker's `model`. `/v1/dispatch` with `"worker":"auto"` already picks by class; with an explicit id, choose the same way. **Never give an easy ticket to Argon while a Flash worker is free.** Argon gets easy work only when no Flash worker is free and the ticket blocks others; say so on the ticket.
  - **Look before sending:** the model shows on the last line of the agy pane (`tmux capture-pane -p -t <s> | tail -1`). No idle session on the right model ⇒ switch an **idle** one with `/model` first (never mid-turn: `esc to cancel` on screen = busy). A restarted agy opens on Argon from `settings.json` ⇒ re-check after any restart.
  - **A ticket whose class is wrong for its content** ⇒ fix the `class:` label first, then dispatch. A rework goes back to a session on the model its class needs, not automatically to the PR author's session if that session's model no longer matches.
  - **Why:** quota burns in proportion to the model's token cost · 2026-10-16: with every session on Argon the account was due to run dry ~31 h before its refresh ⇒ Dell `gemini-4..6` went to Flash for mechanical work, `gemini-1..3` stayed on Argon.
- 🔴 **Keep a ready backlog at least as large as your idle workers** — owner's order 2026-10-16 *"If we add workers, someone has to give them work"* (`2f8ea9c`) · *"Finish proposals 2 and 3"* (`2f8ea9c`)
  - **Every round of the controller loop:** count the idle workers your lane can use (pane shows no `esc to cancel`, and no lease or rework in `/v1/snapshot`) and your ready tickets nobody holds. **Fewer ready tickets than idle workers ⇒ cutting tickets comes before everything else that round**, including reviews that are not yet due.
  - **Pin ahead**, so a worker that finishes picks up at once under the standing order. A pin alone is not a dispatch; see the next rule.
  - **Why:** 2026-10-16: 5 ready tickets nobody held against ~19 idle sessions ⇒ the bottleneck was ticket supply, not workers or dispatch.
- 🔴 **Whoever adds `ready` finds the worker, and idle workers register with the queue** — owner's orders 2026-10-17 *"You have to actually dispatch work to the workers, not just add `ready`"* (`c24541e`) · *"Make a rule: whoever adds `ready` must also find someone to do the work, or it stalls"* (`c24541e`) · *"Whoever is idle registers with the queue"* (`c24541e`) · *"When you finish work, register right away"* (`c24541e`) · *"And while you work, register what you are working on"* (`c24541e`) · *"Register the lane controllers too"* (`c24541e`) · *"Register which machine each worker is on"* (`c24541e`)
  - **`ready` and a pin are not a dispatch.** The session that adds `ready` owns getting a worker onto the ticket, in the same round:
    1. pick an idle worker on the right model (🔴 Match the model) from the queue's register (below), and pin it (`assign:<kind>/<id>`) in the same `gh issue edit` as `ready`;
    2. send that worker the claim order, or confirm it holds a standing order (above) **and** is idle now;
    3. within 10 minutes, check `GET /v1/ticket/...` shows `leased` with that worker. Not leased ⇒ find out why (`ready_blocked_by`, the pane) and fix it or re-pin.
  - **No worker can take it** (a file lock, a dependency, no idle worker on the right model) ⇒ write why on the ticket in the same round. Add `Blocked by #N` when another ticket holds the lock. A `ready` ticket with no pin and no reason is a defect of the session that released it.
  - **A worker registers the moment it finishes** (message-ordered work only; under `/v1/dispatch` orders the presence reporter does it). Finishing means `transition → pr_open`, a rework pushed, a verdict posted plus `/v1/verdict`, or a ticket returned to `ready`/`blocked`. Right then, in the same turn, an implementer sends **one** `POST /v1/next` with `"assigned_only":true` + `"wait_secs":0` (it only ever returns a ticket pinned to that implementer). 🔴 **A reviewer does NOT register through `/v1/review/next`:** without a ticket named, that call hands over the oldest waiting review slot, so it takes slots the lane controller is routing to other reviewers (xchange 2026-10-17: #2976, #677 and Recognize #179 crossed this way). Until `108-agent-queue#954`'s `POST /v1/presence` exists, a finished reviewer only reports done to its controller on the ticket or notice issue and waits. The queue records it in its worker register `GET /v1/workers` (#491): `last_action=claim:empty` means finished and free. If the call hands over a pinned ticket, the worker takes it. That one call is the registration; it is not looping (📨 still forbids re-sending). Every dispatch message carries this as its last step.
  - **And while it works, the register says what it is working on.** For queue work this already happens: the claim records `holding=<repo>#<n>` and `last_action=claim:ticket`, and a heartbeat every ≤30 minutes keeps `last_seen` fresh. So never work a queue ticket without claiming it, and never let the heartbeat lapse. Work outside the queue (writing tests or tickets on a controller's order, a review the owner assigned directly) has no registration call yet. Until the queue ticket below lands, the controller writes on the lane's notice issue who is doing what, and clears it when done.
  - **Reading the register:** a worker is free when `/v1/workers` shows `last_seen` within 30 minutes and its pane shows no `esc to cancel`. ⚠️ Until the queue has a real free-worker register (`108-agent-queue#954`: states free/working/stale, the task, the model, the lane, **the machine and the terminal session**), `holding` also counts a ticket in review, so a worker with only a review pending looks busy. It can still take a second ticket in other files (`max_per_worker` is 2 since 2026-10-17 07:03Z). Check the pane, not `holding` alone.
  - **Lane controllers register too.** Who controls a lane is a queue record, not a comment thread: `108-agent-queue#955` adds `POST /v1/lanes` with the URL of the owner's recorded order as its source, and `GET /v1/lanes`. Until it lands, the lane's notice issue (e.g. `xchange#564`) is the record, and a new controller announces itself there before acting.
  - **Why:** 2026-10-17 07:14–07:18Z on xchange: 19 per-file tickets were cut and 13 got `ready` with pins, but no worker claimed until someone sent the orders. The pinned panes sat idle, while the register showed 135 rows and could not say who was free.
- 🔴 **Design work so ≥80% of workers run at once** — owner's order 2026-10-17 *"We have 30 workers, but it works as if there is nobody"* (`09e5030`) · *"From now on, design the work so the workers can run at the same time, at 10 8o [read as 80%]"* (`09e5030`) (read as 80%; ask the owner if that reading is wrong)
  - **The target:** in each round, a lane keeps at least 80% of the workers it may use busy at the same time. Below that, raising concurrency is the controller's first job that round.
  - **Work runs as a team** (owner, same round: *"So they can run at the same time, as a team"* (`995a42e`) · *"So the work goes fast"* (`995a42e`)).
    - One feature or fix = one design = one team: the controller cuts it into N slices with disjoint File scopes and releases all N together, pinned to N workers who start in the same minute.
    - The team shares the merged design doc and the stub signatures it fixes, so no member waits for another's code.
    - Reviews of the team's PRs go out together, and the team merges as one batch (🟢 merge, batch merge).
    - Size the team to the slices the design really has, not to the idle count. If the slices are too few for the idle workers, start a second design in parallel.
  - **Concurrency is designed before the tickets, not chased after them.**
    - When a lane plans work, split it along the class diagram (📐 Class diagram before code) into tickets whose `## File scope` blocks do not intersect.
    - A design whose tickets share a file runs one ticket at a time, however many workers there are.
    - Before releasing a set, list every ticket's `scope_prefixes` and count how many can lease at once. That count, not the ticket count, is the lane's real capacity.
  - **A file that chains tickets is a design defect.**
    - Fix it at the root: the first ticket splits that file along the diagram, as a pure code move, and the rest then run in parallel.
    - Example: `transfer_flow.rs` made xchange #2617 → #2704 → #2774 run strictly one after another on 2026-10-17. `blocked by #N` only orders the chain; it adds no workers.
  - **One business core, functions fanned out** (owner's order 2026-10-17 *"Gather the business logic in one place; fan the functions out for workers to write"* (`114dfc7`) · *"not waiting on each other"* (`114dfc7`) · *"Test at function level, then at logic level"* (`114dfc7`); made fleet-wide 2026-10-18 *"Make it public"* (`114dfc7`)).
    - A feature's business rules live in **one core ticket**. Every function that uses them is **its own ticket** with a disjoint File scope, written in parallel against the core's stub signatures, so no function waits for another's code.
    - **Two test levels.** The function level runs **only that function's own tests** (*"At function level, test only that function, not the whole suite"*, `114dfc7`). The logic level runs the full suite on the combined branch.
    - 🔴 **Run the logic level early**: on a stacked branch with the core's first draft plus the function stubs, right away, on the Mac Studio. Do not wait until every function has passed. Cut the setup tickets it finds **alongside** the function tickets.
    - **Why:** 2026-10-17 xchange CA-10: 9 function PRs were written and passed within 2.5 h, but the first logic-level run came 8 h later and found 364 failing tests (old setups the new rule forbids), which cost another 8 h before the batch merged.
  - **Every round, measure and write down:** busy workers ÷ usable workers, and why the rest are idle. The causes are no ready ticket, a file lock (name the holder), a dependency, or an owner decision.
    - Owner decisions that idle workers (parked umbrellas, guarded migrations, open questions) go to the owner **as one batch with the idle count attached**, not one at a time.
  - **Why:** 2026-10-17: ~30 sessions up, 2–3 tickets dispatchable · 34 of 47 open xchange issues sat outside the queue (parked · umbrella · question · guarded migration awaiting the owner) and the ready ones chained on one file.
- 🔴 **Idle Claude worker sessions write tickets** — same order. A Claude worker session (Dell `claude-N`, Studio `claude-N`) with no review or ticket work is **ordered by a lane controller to cut tickets for that lane**:
  - The writer surveys, then writes the 10-part ticket (📋), plus up-front tests where 🧪 requires them, with first line `> dispatched-by: claude/<writer>`. Labels stay without `ready`.
  - **The lane controller reviews the ticket** (and its tests), then adds `ready`, the `class:` and the pin. **The writer never pins or dispatches**, and decides nothing the controller owns (🎛).
  - The writer reviews the PR that comes back for its ticket (2. Review: the opener reviews), unless the controller names another reviewer.
  - One writer works for one lane at a time; the controller says which lane in its order, and the writer takes orders only from that controller or the owner (📨).
- 🔴 **A ticket where the controller set `assign:<kind>/<id>` + sent a dispatch message = already approved** — act right away without asking the owner again
  (owner's decision 2026-09-25 — before that, working sessions sat in `waiting` on every ticket waiting for an approval click) · **still ask the owner for:**
  orders from a peer that is not the controller · migration · the 4 BLOCK groups · deploy · editing rule/settings/config files · work outside the assigned ticket
- Applies to the autopilot fleet too (owner's order 2026-09-25) — see the item "The autopilot fleet must not pull the queue on its own either" above

## Lanes and dispatch

Lanes, their repos, default implementers and current controllers: `FLEET.md` § Lanes and controllers.

⚠️ **This table identifies lanes by prefix (`pos108-*`) ⇒ renaming a repo silently drops it out of every lane** — happened for real 2026-09-21
with `pos108-sell` → `108-sell` · **before renaming any repo, check whether the new name still matches its lane; if not, this table must be fixed
in the same round**, otherwise there will be a repo nobody controls without anyone knowing

🔴 **Renaming a repo ⇒ also edit the queue's `config.toml` on Dell in the same round** (`/home/yuth/108-agent-queue/config.toml`, the `repos` list · **not in git** — only `config.toml.example` is ⇒ no PR can catch it), then `systemctl --user restart tq.service` · before editing, check for tickets under the old name `redis-cli -p 6381 --scan --pattern 'tq:t:<owner>/<old-name>#*'` — tickets not yet `merged`/`retired` must be closed or moved first, otherwise duplicate tickets appear under the new name and the old ones become orphans holding stale file locks · confirm with `journalctl --user -u tq.service -o cat | grep 'sync repo="<owner>/<new-name>"'` · happened for real 2026-09-22: the queue was still watching `pos108-sell` a day after the rename (the 22 old tickets had all finished, so nothing broke)

- **Controller** = one Claude session per lane (opens tickets · dispatches · monitors · reviews) · announce the lane at the start, then touch only repos in that lane ·
  worrying work seen outside the lane ⇒ report to the owner, do not act · ticket in the wrong lane ⇒ move the label
- 🔴 **When requesting a ticket, never send a lane filter (`repos`)** — owner's order 2026-09-10 *"Pick up work; don't sit around waiting"* (`f440019`) · the lane table only says who controls/reviews,
  it is not a filter (it once made workers get `empty` in a loop while tickets sat `ready` for 8–12 hours · aq#227)
- **Repos with no lane owner** (`108-platform-services` · `108-agent-queue` · media/livechat/tixtox — `recognize` moved to the xchange lane 2026-10-16 and `Payment-Platform` got its own lane 2026-10-17, see the table) ⇒ **ask the owner before dispatching**
  (unless the owner sent the work directly)
- The owner says which ticket goes to whom = do that · not said ⇒ see the lane table · dispatching within a lane needs no owner approval
- **One ticket = one implementer** · implementers cannot see each other's work ⇒ tickets touching the same file must go to the same implementer or state `blocked by #N`
- 🔴 **Never remove `assign:<kind>` to "let anyone pick it up"** — `class:guarded` tickets with no assignment are all skipped · an assignment unlocks guarded
  but does not bypass the capability gate ⇒ the worker must also send `capabilities` containing `guarded` (`claim.lua:218-220` · aq#240)
- **Worker kind label:** `gemini` ·
  repos lacking them: run `scripts/create-labels.sh` (above) · PM dispatching to specialist agents uses `pm-dispatch`

## 🧩 Two pieces of work conflict = propose a root-cause fix, not just a queue order that avoids it

Owner's order 2026-09-17 · conflicts come in three kinds, all of them symptoms:

| Kind | What it looks like | Root-cause question to ask |
|---|---|---|
| File collision | two tickets reserve the same path | why is that file the meeting point of all work |
| Opposite orders | ticket A says write the value, ticket B says don't, on the same field | who owns the rules for that field, and where are they written |
| Unknowing duplicates | several tickets ask for the same thing in different words | tickets were split by symptom, not by what has to change |

🔴 `blocked by #N` is a **stopgap** — it's allowed (better than a coin flip on who goes first) but must always come with a root-cause proposal
(**written on the ticket, or escalated to the owner if beyond your reach**) · before ordering, ask:
1. **Should these be one ticket?** — changing the same thing from different angles ⇒ merge them (except a ticket whose PR is already written — let it land first, then continue)
2. **Opposite orders: where is the dividing line?** ⇒ write the line into both tickets · no line where both can coexist ⇒ the owner decides; the implementer must not choose
3. **Which file is reserved most often?** — one file appearing in more than half of the waiting tickets = an architecture problem; propose splitting the file (adding workers doesn't help)
(redis-cli prints field and value on separate lines when writing to a pipe · COUNT must be large because most events are `claim:empty`)
```bash
ssh Dell-server 'redis-cli -p 6381 XREVRANGE tq:events + - COUNT 3000' \
  | awk '/^blocked_by$/{getline b} /^conflict_paths$/{getline p; print b, p}' | sort | uniq -c | sort -rn
```
Evidence 2026-09-17: `src/store.rs` was in 7/10 waiting tickets of `108-agent-queue` · `#570`/`#593` gave opposite orders on `pr_head`
(resolved with a dividing line: `pr_open` = refresh · parked tickets = pin) · `#595`/`#618`/`#620` asked for the same thing

## 🧾 Naming another agent = attach re-runnable evidence in the same sentence

Owner's order 2026-09-09 — in one day, three wrong identifications by three different people, each checkable in a few seconds
(including cases where the speaker already had the correct data at hand but typed from memory)

| To say | Must attach |
|---|---|
| Who opened/owns a ticket | the ticket's first line `> dispatched-by:` or `HGET tq:t:<repo>#<n> dispatched_by` |
| Who holds a ticket / ticket status | a row from `GET /v1/snapshot` or `GET /v1/ticket/...` with the time it was fetched |
| Who reviewed / what the verdict was | **a link to the comment containing `Verdict:`**, not the `in_review` state in the queue |
| A session is dead / no worker of some kind is taking work | `ssh Dell-server 'redis-cli -p 6381 XREVRANGE tq:events + - COUNT <n>'` + how many entries were swept, over what span — **"not seen" ≠ "does not exist"** |

- 🔴 **No evidence = do not name anyone**; describe the mechanism instead ("two ticket openers who don't know each other")
- 🔴 **The lane tables/worker lists in this file are what is intended, not what is happening** — never repeat them as fact without measuring the event log first
- Told you misidentified someone ⇒ check, then **fix it at the source** (the comment you sent), not just acknowledge it in the conversation

---

## 🔬 Blocked on an owner decision = trace the root cause first, then present directed options

Owner's order 2026-09-17 — 🔔 says you **must notify**; this rule says **what to notify with** ·
🔴 **A bare question throws the thinking back to the owner** — the owner is not in the code; we are

Every question must have four things:
1. **Root cause, not symptom** — the chain `symptom ← A ← B ← root cause`, every link with a `file:line` or a re-runnable command
2. **What was measured** — numbers/run output/file contents, not opinion · a *"not sure whether X"* ("not sure whether X") you can check yourself in 2 minutes **must not be asked**
3. **Options with costs** — one line each: reversible? · who is affected? · what follow-up is needed
4. 🔴 **One recommendation of ours, with the reason** — if you truly cannot choose, say where you are stuck and what more you need to know

```
Root cause:    <file:line + the chain>
Measured:      <numbers / run output / file contents>
Options:       A. <path> — cost / reversible?
               B. <path> — cost / reversible?
I propose:     <A or B> because <reason>
If no answer:  <which path I take meanwhile, or where the work stops>
```
Evidence: `park108#664`/`#735` traced the root cause fully ⇒ answered in ~4 minutes · `park108#633` asked vaguely ⇒ no answer overnight

- 🔴 **Research to make the question better, not to avoid asking** — Data Risk · the 4 BLOCK groups · business rules · production still require stopping to ask
- 🔴 **Security work:** the owner delegates the decision to you (2026-09-14) · if you must ask, propose **a single path**; never present an A/B/C table
- After asking, say what you will do while waiting (can proceed = proceed, and write which path you took · cannot = say where it stops and who is blocked)
- **Never re-ask something already answered**

## 🧮 All work runs on Opus 5.5 — review work also uses effort `medium`

Owner's order 2026-09-24 *"Switch every session's model to Opus 5.5"* (`c477ad5`) then *"Change rule 🧮 to cover all work"* (`c477ad5`) —
extending the same morning's order *"Change rule 🧮 so reviews use Opus 5.5 medium"* (`c1e9fa9`) (which replaced the 2026-09-18 rule that put reviews on Sonnet)
⇒ **every session, every task runs on Opus 5.5 (`claude-opus-5-5`)**, not only review work

- 🔴 **A session cannot change its own model with a tool** — `set_session_model` rejects `self`
  (*"a session must not silently re-price its own turns"*) ⇒ **only the owner can choose it, from the app's model menu** ·
  if you see your own session is not `claude-opus-5-5` ⇒ **tell the owner**; never silently keep working on the old model
- **Other sessions** ⇒ `set_session_model` + `claude-opus-5-5` · find ids with `list_sessions`, which **does not include the calling session**
  and sees only the app's sessions on **that machine** — sessions on other fleet machines are not listed ⇒ sweeping one machine is not sweeping the fleet
- **Newly opened sessions** still start on the app's default model · **no tool sets this default**, and `/config` is a terminal
  dialog that cannot open in the Code tab ⇒ it can only be changed in the owner's model menu
- Spawned `Agent` ⇒ `model: "opus"` · `Workflow` ⇒ `agent(..., {model: 'opus'})`
  ⚠️ `Agent` takes only the model family name, **not effort** — effort comes from the session or the agent's frontmatter
  ⇒ to run an agent at a given effort, spawn it from a session already set to that effort

🔴 **Same model for all work does not mean same effort for all work** — **all code review work runs at `medium`**
(`/code-review` ⇒ specify `medium` · review sessions are set via the app's effort option or `set_session_effort`) ·
**never `high`/`xhigh`/`max` for review** unless the owner orders it that round · and **do not spawn review agents in swarms** —
evidence 2026-09-18: a max-effort park108 review spawned 37 Opus agents (~6,700 requests) and used 85% of the 5-hour quota
in one hour ⇒ the cost comes from **max effort × number of agents**, not from the model name alone

---

## All labels are in English, one set for the whole org
**All labels are in English, one set for the whole org** — owner's order 2026-09-27 *"Make the language English, so we can work with colleagues from other countries"* (`5b6eed5`) ·
the single source is `108-Plaza/108-agent-queue` → `scripts/create-labels.sh` (name · colour · English description) · **new repo = run this script; never type `gh label create` by hand**
(safe to re-run · it keeps the owner-only description of `reviewed` in CCTV-Platform for you · exit 3 = Thai labels still remain):
```bash
bash scripts/create-labels.sh [--dry-run] 108-Plaza/<repo>     # in a clone of 108-agent-queue
```
A new label needed fleet-wide ⇒ add it to the script via a PR, not by hand · descriptions are limited to 100 characters (the script checks)
