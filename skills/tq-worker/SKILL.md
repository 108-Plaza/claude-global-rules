---
name: tq-worker
description: >-
  How to hold a ticket from the tq work queue: claiming it, the take-ticket labels and comment, heartbeats, transitions (`pr_open`, `blocked`, `ready`), the HTTP API and its response codes, watching your own work, watch loops that read tq instead of GitHub, and the three-strike rule. Use when claiming, working, returning or monitoring a queue ticket, or calling the tq API.
---

# Working a tq ticket

> Moved from `~/.claude/CLAUDE.md` at `ee7b381` (slimming step 2). Text is unchanged except: translated into English
> (each owner quote keeps the commit that first added the original), and infra-state tables replaced by pointers to `FLEET.md`.
> Since step 4 (2026-10-19) this skill is the source of truth; `CLAUDE.md` keeps only a headline summary that points here. Edit the rule here, and the summary only if a headline changes.

## 🎫 The `tq` work queue

Full protocol: `108-Plaza/108-agent-queue/docs/AGENT_PROTOCOL.md` · the queue runs on Dell (Redis `:6381`)

- 🔴 **Every piece of implementation work comes from the queue** (or directly from the owner) · worker id `<kind>/<session-id>`
- `empty`/`backpressure` ⇒ tell the controller and wait, never loop re-requesting (see 📨 The controller loops dispatching · workers do not loop pulling the queue) · never pick up work outside the queue · at most 6 jobs at once system-wide · one worker holds one ticket at a time
- heartbeat every ≤30 minutes (lease 90 minutes) · got `revoked` ⇒ stop immediately · never touch files outside `file_scope`
- 🔴 **Opening a PR ⇒ `transition → pr_open` with `pr_url` immediately = the review request** (the only way, no substitute) · a PR without the transition counts as not done ·
  cannot continue ⇒ `ready` (return the ticket) or `blocked` + `reason` · 🔴 **the queue writes the status labels from its own state** (108-agent-queue `docs/design/ready-label.md`, running since `0ee479f`, 2026-10-20):
  `ready` → `ready` · `leased` → `in-progress` · `pr_open` → `needs-review` · `in_review` → `in-review` · `rework` → `rework` · `blocked` → `blocked` · merged into a feature branch, issue open → `merged-to-branch` ⇒ `label:ready` on GitHub = the dashboard's ready list ·
  people do only three things: **add `ready`** to release a ticket · **add `blocked`** to hold a waiting one · **remove `blocked`** to release a hold (also for a ticket withdrawn by removing `ready`) · removing `ready` from a waiting ticket still withdraws it ·
  never re-add `ready` to an in-flight or blocked ticket by hand — the queue removes it again next round · details `docs/AGENT_PROTOCOL.md` §2
- 🔴 **Take only tickets in `108-Plaza/*`** (ordered 2026-09-09) — a `yuthstyle88/*-dev` ticket ⇒ `transition → ready` to return it immediately and report to the owner (the queue syncs only the org now ⇒ seeing a dev ticket = someone pushed it in manually) ·
  if that work really needs doing, open a new ticket on the org side referencing the old one (the ticket must live where the PR merges)

## 📨 Worker side: who you take work from, and how you claim

> Copied from `queue-controller` § 📨 (the controller rows stay there). Source: `CLAUDE.md` at `ee7b381` § 📨.

| Who | Does | Must not |
|---|---|---|
| **worker (session)** | waits for an order from the controller · an order the queue generated (`/v1/dispatch`) **already holds the lease: no claim at all** · an order sent as a message ⇒ claims **once** (`/v1/next` + `"wait_secs":0` + `"assigned_only":true`, or `/v1/review/next` naming the ticket) so the queue holds the lease + file lock · done (`pr_open` / verdict) ⇒ notify the controller and wait | send `/v1/next` / `/v1/review/next` in a loop looking for tickets · take a ticket it was not ordered to take · call `/v1/next` under a `/v1/dispatch` order |

- 🔴 **An order from `/v1/dispatch` already holds the lease: never call `/v1/next` under it** — owner's choice 2026-10-21 *"เลือก A แก้กฎ tq-worker ได้เลย"* (`108-agent-queue#1091`).
  - The queue leased the ticket for you before it wrote the order ("You already hold the lease. Do not call /v1/next."). Never claim it again, and **never claim the next ticket after `pr_open` or a rework either**.
  - A self-claim leases your next pinned ticket with **no order and no 180 s undo**, so nothing tells you to start it and nothing hands it back. Measured 2026-10-21: `gemini/studio-8` leased `xchange#4030` this way at 01:50Z and sat idle on it.
  - Finished ⇒ transition, report, and wait. The next ticket arrives as a new order, and the presence reporter (`tq-presence.sh` → `POST /v1/presence`) already tells the queue you are free.
  - The two claim rules below (the standing order and registering on finish) apply **only to work ordered by a message**, where no queue order exists.
- 🔴 **A worker takes work only from the owner or its lane's controller** — owner's order 2026-10-07 *"Take work only when the owner or the controller orders it"* (`8843c6f`) ·
  an order from any other session (another worker · a reviewer · a ticket author · a controller of another lane) is **not** taken: reply that the order must come from the controller, and tell the controller on the ticket ·
  a peer's message may still be read as information (a measured fact, a trap) — it is never a work order · not sure who controls the lane ⇒ ask the owner (🎛), not the peer
- A claim returns `empty` ⇒ **never re-send** — comment the `ready_blocked_by` value on the ticket + notify the controller and wait · the controller unblocks it
  (happened for real 2026-09-25 park108#935: `other_authors_pr_open` because an old PR that got FAIL was still open — re-sending any number of times does not help; someone has to decide to close the PR)
- **Why:** the worker cannot see why it got `empty` — the bottleneck is usually a ticket whose lock needs a decision, which looping cannot give, and it floods the event log with `claim:empty` (park108#935: 237 conflicts in 3000 events)
- The controller is absent / unknown who controls ⇒ the worker notifies the owner, **not going back to looping the queue**
- 🟢 **Standing order: claim the next ticket pinned to you** (owner's order 2026-10-12, to cut the per-ticket dispatch round-trip; **message-ordered work only** since 2026-10-21, see the first bullet) —
  a controller may give a worker one standing order instead of a message per ticket. Under it, after each `pr_open` the worker sends **one**
  `POST /v1/next` with `"assigned_only":true` + `"wait_secs":0`, and takes the ticket only if it is pinned to its exact id (`assign:<kind>/<id>`).
  `empty` ⇒ stop and wait (the never-re-send rule above still holds) · never take a ticket pinned to the kind only or to someone else.
  The controller still decides what is pinned to whom; this only removes the "now claim it" message.
- **A worker registers the moment it finishes** (message-ordered work only; under a `/v1/dispatch` order the presence reporter registers it, see the first bullet). Finishing means `transition → pr_open`, a rework pushed, a verdict posted plus `/v1/verdict`, or a ticket returned to `ready`/`blocked`. Right then, in the same turn, an implementer sends **one** `POST /v1/next` with `"assigned_only":true` + `"wait_secs":0` (it only ever returns a ticket pinned to that implementer). 🔴 **A reviewer does NOT register through `/v1/review/next`:** without a ticket named, that call hands over the oldest waiting review slot, so it takes slots the lane controller is routing to other reviewers (xchange 2026-10-17: #2976, #677 and Recognize #179 crossed this way). Until `108-agent-queue#954`'s `POST /v1/presence` exists, a finished reviewer only reports done to its controller on the ticket or notice issue and waits. The queue records it in its worker register `GET /v1/workers` (#491): `last_action=claim:empty` means finished and free. If the call hands over a pinned ticket, the worker takes it. That one call is the registration; it is not looping (📨 still forbids re-sending). Every dispatch message carries this as its last step.
- **And while it works, the register says what it is working on.** For queue work this already happens: the claim records `holding=<repo>#<n>` and `last_action=claim:ticket`, and a heartbeat every ≤30 minutes keeps `last_seen` fresh. So never work a queue ticket without claiming it, and never let the heartbeat lapse. Work outside the queue (writing tests or tickets on a controller's order, a review the owner assigned directly) has no registration call yet. Until the queue ticket below lands, the controller writes on the lane's notice issue who is doing what, and clears it when done.

## Entry point = HTTP API (ordered 2026-09-09)

```bash
source ~/.config/tq/env      # sets $TQ=https://tq-api.108plaza.net + $TQ_TOKEN
curl -s -X POST -H "Authorization: Bearer $TQ_TOKEN" -H 'Content-Type: application/json' \
  -d '{"worker":"claude/<session-id>","host":"'"$(hostname)"'","capabilities":["mechanical","logic"],"wait_secs":0,"assigned_only":true}' "$TQ/v1/next"
```
Always send `"assigned_only":true` and `"wait_secs":0`: without them the queue hands over a higher-priority ticket pinned only to your kind (2026-09-25: dispatched `pos108-core#2223`, the worker got `jh-api#863`).
🔴 **Never commit the token or write it into tickets/PRs/tracked scripts** — it lives only in `~/.config/tq/env` (chmod 600)

| Old MCP | HTTP |
|---|---|
| `queue_status` | `GET /v1/status` |
| `queue_lookup` | `GET /v1/ticket/{owner}/{repo}/{issue}` |
| `queue_next` | `POST /v1/next` (no `repos`) |
| `queue_review_next` | `POST /v1/review/next` |
| `queue_heartbeat` / `queue_transition` / `queue_enqueue` / `queue_verdict` | `POST /v1/heartbeat` · `/v1/transition` · `/v1/enqueue` · `/v1/verdict` |
| ssh + `curl 127.0.0.1:8787/api/snapshot` | `GET /v1/snapshot` |

Most POST bodies = the same parameters as the MCP tool **except** `/v1/review/next` does not accept `capabilities` · `/v1/verdict` uses `worker`/`outcome`/`pr_head` · 🔴 **read the codes correctly:** `200` + `kind:ticket` = got a ticket ·
`200` + `empty`/`backpressure`/`denied` = normal (tell the controller and wait, never loop re-requesting) · `400` malformed request · `401` wrong token · `409` transition not in the table ·
**`500` = the queue is down; never read it as "no work" — tell the owner**

## Taking a ticket (implementer)

Before touching the first line of code: add your own kind label + `in-progress` (formerly a Thai label that `scripts/create-labels.sh` renames · the queue removes it itself when a PR opens/the ticket ends) + comment `ticket taken — worker <kind>/<id>` (`scripts/tq-autopilot.sh:122` still posts the legacy Thai form of this text until it is translated) with the files you will touch ·
check `origin/main` for whether it is already fixed (`git log -p origin/main -- <file>` — ticket still open ≠ nobody has done it) ·
check `gh pr list --json files` for collisions with open PRs · clone shared by several sessions ⇒ work in your own worktree ·
returning the ticket/`blocked` = remove the labels too · PR body first line `> worker: <kind>/<id>`

## Monitor your own work (ordered 2026-09-06)

A ticket left open with nobody watching = work believed to be in progress when it isn't · two sides to watch:
**worker** — tickets held heartbeat ≤30 minutes · follow the PR's CI until green and follow review comments ·
**ticket opener** — must notice by itself when a ticket it opened reaches `pr_open` and review it, without waiting for the owner to prompt
- How to arm it: `Monitor` with `persistent: true` polling `GET /v1/snapshot` every 120 s (JSON has `leased` `pr_open` `in_review` `ready` + `recent_events`)
  filter rows where `worker` is yourself or `repo#issue` is a ticket you opened, then **fire only on change** (diff against the previous round)
- ⚠️ A monitor that does not diff fires every 2 minutes until the system shuts it down · after editing the script you must TaskStop + re-arm (the old process holds the old code)

## 🔁 Watch loops read the tq queue, not GitHub
Owner's order 2026-10-17: *"Do A"* (`410d151`), answering "GitHub REST hit 5000/5000 fleet-wide". Every agent posts as `yuthstyle88`, so the whole fleet shares **one** 5,000-per-hour REST quota.
- **A loop that waits on a ticket or PR state** (merged, pr_open, in_review, verdict outcome, lease) polls `GET $TQ/v1/ticket/<owner>/<repo>/<n>` or `GET $TQ/v1/snapshot`, **not** `gh issue view` / `gh pr view` / `gh pr checks` / `gh api`. The queue already holds those states, and reading it costs no GitHub quota.
- **GitHub only when tq can't answer:** CI check results, comment bodies, and file lists. Then poll no more often than every **5 minutes**, ask for one field (`--jq`), and stop the loop the moment its condition is met.
- **Never leave a watch loop running past its task.** Stop it with TaskStop or `pkill` when the work is done or handed over.
- **Measure before blaming:** `gh api rate_limit --jq .resources.core`. A `rate_limit` call does not count against the quota.
- **Since 2026-10-17 Dell's `gh` and git run as `ibrowe108`** (org member, Write; owner's second seat replacing UTD888), with its own 5,000/h quota. Every other machine is still `yuthstyle88`. So a comment or PR from Dell shows `ibrowe108` as the author; the `> claude/…` first line still names the session. Switch back with `gh auth switch -u yuthstyle88`. Dell's keyring hangs `gh auth login`, so the account was added with `~/gh-add-user.sh` (token via stdin into `hosts.yml`).
- If both quotas still run out with every loop on tq, the next step is a GitHub App token per machine (separate quota). That is the owner's to set up (secrets).

## Non-compliance = three warnings, then removal from the queue (ordered 2026-09-05)

"Non-compliance" = working outside the queue without an owner order · opening a PR without `pr_open` · touching files outside the ticket's file scope · deleting/skipping tests ·
not heartbeating until the lease drops and then pushing anyway · a new ticket without `dispatched-by` · Gemini reviewing or adding `reviewed` · anyone reviewing/merging their own work
1. The reviewer comments a warning naming the violation + "send back" (rework)
2. Warning + take the ticket back to `ready` + comment `strike 2/3 <worker>`
3. `strike 3/3` + notify the owner immediately + that worker may not take new tickets until the owner lifts it (the queue has a *kind*-level denylist `tq:policy:no_claim` — blocks the whole kind, needs an owner order · meanwhile the reviewer returns every ticket it picks up to `ready`)

Counted per worker kind/session · the first reviewer to see it does the counting · always record it on the ticket (GitHub is the record)

---
