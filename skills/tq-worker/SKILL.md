---
name: tq-worker
description: >-
  How to hold a ticket from the tq work queue: claiming it, the take-ticket labels and comment, heartbeats, transitions (`pr_open`, `blocked`, `ready`), the HTTP API and its response codes, watching your own work, watch loops that read tq instead of GitHub, and the three-strike rule. Use when claiming, working, returning or monitoring a queue ticket, or calling the tq API.
---

# Working a tq ticket

> Moved from `~/.claude/CLAUDE.md` at `ee7b381` (slimming step 2). Text is unchanged except: translated into English
> (each owner quote keeps the commit that first added the original), and infra-state tables replaced by pointers to `FLEET.md`.
> Until step 4 removes these sections from `CLAUDE.md`, an edit to one must be made in both files.

## 🎫 The `tq` work queue

Full protocol: `108-Plaza/108-agent-queue/docs/AGENT_PROTOCOL.md` · the queue runs on Dell (Redis `:6381`)

- 🔴 **Every piece of implementation work comes from the queue** (or directly from the owner) · worker id `<kind>/<session-id>`
- `empty`/`backpressure` ⇒ tell the controller and wait, never loop re-requesting (see 📨 The controller loops dispatching · workers do not loop pulling the queue) · never pick up work outside the queue · at most 6 jobs at once system-wide · one worker holds one ticket at a time
- heartbeat every ≤30 minutes (lease 90 minutes) · got `revoked` ⇒ stop immediately · never touch files outside `file_scope`
- 🔴 **Opening a PR ⇒ `transition → pr_open` with `pr_url` immediately = the review request** (the only way, no substitute) · a PR without the transition counts as not done ·
  cannot continue ⇒ `ready` (return the ticket) or `blocked` + `reason` · 🔴 **a `blocked` ticket must keep the `ready` label** — the queue adds `blocked` itself and deliberately does not remove `ready` (108-agent-queue #300) ·
  removing `ready` ⇒ sync never reads that ticket again (`gh issue list --label ready`), edits to the ticket body/scope do not reach the queue, and removing `blocked` later does not unblock it ·
  **unblock a ticket = remove `blocked`** (on a ticket that still has `ready`) · for a ticket blocked because someone removed `ready` (reason `label ready removed`) the queue **also adds `blocked`** (#523) ⇒ unblock = **add `ready` back first, then remove `blocked`** · details 108-agent-queue #713
- 🔴 **Take only tickets in `108-Plaza/*`** (ordered 2026-09-09) — a `yuthstyle88/*-dev` ticket ⇒ `transition → ready` to return it immediately and report to the owner (the queue syncs only the org now ⇒ seeing a dev ticket = someone pushed it in manually) ·
  if that work really needs doing, open a new ticket on the org side referencing the old one (the ticket must live where the PR merges)

## Entry point = HTTP API (ordered 2026-09-09)

```bash
source ~/.config/tq/env      # sets $TQ=https://tq-api.108plaza.net + $TQ_TOKEN
curl -s -X POST -H "Authorization: Bearer $TQ_TOKEN" -H 'Content-Type: application/json' \
  -d '{"worker":"claude/<session-id>","host":"'"$(hostname)"'","capabilities":["mechanical","logic"]}' "$TQ/v1/next"
```
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
