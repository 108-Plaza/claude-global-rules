---
name: fleet-ci
description: >-
  CI and deploy procedure for the fleet: self-hosted runners only, where load can move, collapsing queued runs, the `ci:go` merge-turn label, the doc-only fast path, and the personal-staging / org-prod deploy lanes with copied workflows. Use when editing a workflow, when CI is queued or jammed, when a doc PR runs builds, or when touching deploy lanes.
---

# CI and deploy lanes

> Moved from `~/.claude/CLAUDE.md` at `ee7b381` (slimming step 2). Text is unchanged except: translated into English
> (each owner quote keeps the commit that first added the original), and infra-state tables replaced by pointers to `FLEET.md`.
> Until step 4 removes these sections from `CLAUDE.md`, an edit to one must be made in both files.

## 🔴 Every job runs self-hosted — GitHub-hosted is a failure, not a fallback

Owner's order 2026-09-21 *"Actions must use self-hosted runners"* (`98f7593`) · applies to **every workflow on both sides**, not just new ones ·
the source of truth is `108-Plaza/108-Ting-Ecosystem` → **`docs/CI_RUNNER_STANDARD.md` §1** (including the `# hosted-ok:` format) ⇒ edit the details there, not here

- `runs-on: [self-hosted, Linux, X64]` (Linux) · `[self-hosted, macOS, ARM64]` (macOS) · `[self-hosted, Windows, X64]` (Windows) —
  **never `ubuntu-latest` · `windows-latest` · `macos-latest`**, and never pin extra specialised labels
- ⚠️ **hosted has died on billing before** — 2026-09-20 a `windows-latest` job ended in two seconds before its first step with
  `The job was not started because recent account payments have failed or your spending limit needs to be increased`, so the gate never ran and the PR read as broken.
  🔴 **That is no longer the state — re-measure before repeating it.** Measured 2026-10-17 from `gh api "/organizations/108-Plaza/settings/billing/usage?year=<y>&month=<m>"`:
  October used **108 hosted Linux minutes, net $0.00** (inside the included allowance), the last on 2026-10-14 ⇒ hosted jobs do run today. The reason to stay self-hosted is cost and capacity, not a hard block
- **The only acceptable exception** = an OS the fleet has no machine for · ⚠️ **Windows is not that exception** — the org has a Windows runner ⇒
  **check `gh api orgs/108-Plaza/actions/runners` before claiming there is no machine** · if the exception really holds, write `# hosted-ok: <why the fleet has no machine for this>` above that `runs-on`
  and know the job will not run until billing is unblocked · registering a runner for a new OS is the owner's job
- **An enforcing gate exists but is not rolled out** — `108-Ting-Ecosystem/.github/workflows/hosted-runner-gate.yml` is a reusable workflow running
  `scripts/check-hosted-runners.sh`, which requires every hosted job to carry the marker · it is installed in **one** repo (itself) ⇒ every other repo with workflows has nobody checking it
- **Re-measure before citing any count** — leftovers move every week:
  ```bash
  gh api search/code -f q='"runs-on: ubuntu-latest" user:<owner> path:.github/workflows'
  ```
  and read the actual files (`grep -n "runs-on:"`), because code search also matches the word inside comments

## ⚙️ CI runner

Details and the `# hosted-ok:` format live in `108-Plaza/108-Ting-Ecosystem` → **`docs/CI_RUNNER_STANDARD.md` §1** ⇒ edit them there, not here.
🔴 **Runner inventories go stale — `gh api orgs/108-Plaza/actions/runners --jq '.runners[]|"\(.name)\t\([.labels[].name]|join(","))"'` before citing one.**

Runner pools, labels and the repo-level runner: `FLEET.md` § CI runners.
Lenovo's runner service and Warut's runner PATH: `FLEET.md` § CI runners.
- 🔴 **Jobs pinned to `pos108-ci` cannot land on Lenovo** — that label exists only on Dell, so they still queue on one machine
  ⇒ **remove `pos108-ci` from `runs-on`, leaving `[self-hosted, Linux, X64]`** (a workflow change, not a runner-label change) · find them with
  `gh api "repos/<slug>/contents/.github/workflows/<file>" -H "Accept: application/vnd.github.raw" | grep -n "runs-on:"` — `grep -n "runs-on:"`, never `git grep -l <label>` (comments match too)
- New workflows and tickets use `runs-on: [self-hosted, Linux, X64]` — **never pin extra specialised labels**
- **The broadest `runs-on` means GitHub picks the machine** ⇒ load spreads in only two ways: **add machines to the pool**, or **remove specialised labels** from narrowly pinned jobs ·
  moving `runs-on` **within the same OS** moves nothing · 🔴 **moving to another OS really moves it** when the job is not tied to that OS — light gates (hash · clone · regex · text checks)
  on `[self-hosted, macOS, ARM64]` get a runner while Linux is saturated (`6719b7c`) · **condition:** no Linux-specific toolchain; real build/test jobs stay on Linux
- 🔴 **Never touch runner labels** — shared resource, owner only
- Faster CI is not permission to push guess-fixes — local verify must still be green first

## 🧹 More than 3 CI runs queued = collapse into one run

Owner's order 2026-09-24 *"If more than 3 CI jobs are stuck waiting, collapse them into a single run"* (`3e2edc5`) · applies to **every repo, every session that sees it**, no need to ask again

**Principle:** *"If the last one runs green, they all pass anyway"* (`396f746`) · *"There is no need to run them one at a time"* (`396f746`) (owner 2026-09-24) — the latest commit of a line
contains all earlier commits ⇒ green on the latest = the earlier ones pass too · running intermediate commits one by one *"It's a waste of time"* (`396f746`) because *"Basic tests were already run before pushing"* (`a119b0d`) (Lifecycle step 6 — verify locally to green before push) ⇒ CI is the final confirmation gate, not a per-commit test runner

**Count:** runs with `status=queued` in one repo · **more than 3 ⇒ cancel down to one**
- **Same line (main/master or the same PR)** ⇒ keep only the **latest commit**, cancel the older waiting commits — main included
  (replaces the old concern from `pos108-core#1733`) · if the latest goes red, then find which commit broke it (bisect) locally
- **Different PRs** ⇒ keep the PR that will merge next (already PASS / p0), otherwise the newest · the rest run when their merge turn comes
  (`strict=true` repos must update-branch before merge anyway ⇒ runs before that are wasted)
  · 🔴 if you don't know which PR merges next ⇒ **skip that repo and let the lane controller sweep it** (real incident 05:01Z: `jh-api#798`, which was the CI fix itself, got cancelled and had to be re-run)

🔴 **Never cancel:** runs that are `in_progress` · deploy/release/promote (`release-image` · `Promote to staging` · `deploy/*`) ·
`workflow_dispatch` the owner triggered · light gates `independent-review` / `Issue link` **may be cancelled only as duplicates within the same PR**
(keep the newest per PR) — every PR must have one, otherwise the gate hangs
```bash
gh api "repos/108-Plaza/<repo>/actions/runs?status=queued&per_page=100" \
  --jq '.workflow_runs[]|"\(.id) \(.name) \(.event) \(.head_branch) \(.created_at)"'
gh api -X POST repos/108-Plaza/<repo>/actions/runs/<id>/cancel
```
- The permanent fix is one `concurrency` group per repo for PR runs (`…-pr` + `cancel-in-progress: false` ⇒ 1 running + 1 waiting) —
  put in place 2026-09-24 at `pos108-core#2192` · `108-agent-queue#809` · `pos108-terminal#720` · `jh-api` following `#797`
  · this rule is the sweeper for what concurrency doesn't cover (other workflows · repos not yet fixed)
- Single-queue repos ⇒ **merge one PR at a time and re-run only when the group is free** — re-running several at once = they fight over the waiting slot
- 🔴 **The single waiting slot goes to the PR pushed most recently, not to the PR whose merge turn it is** (measured 2026-09-24 aq: the next PR got bumped ≥6 times in one day) ⇒
  the owner chose option B: **a PR's full CI runs only on PRs labelled `ci:go`** · PRs without the label ⇒ the required check fails fast (not skipped) and sits in its own group
  · in use at `108-agent-queue` (#831 · PR 832 `a544b54`) · `jh-api` (#815 `5ba573e`) · `pos108-core` (#2273 · PR 2274 `de8c8c2` · 2026-09-26)
  — in these repos, **org-side** PRs without the label ⇒ `cargo check + test` is red at the step `Wait for merge turn (ci:go)` **on purpose, not broken code** ·
  the check tests `github.repository` ⇒ PRs on the `yuthstyle88/*-dev` mirrors (outsiders can't add labels) get the full build/test as before ci:go (pos108-core #2277 · jh-api #946 · 108-agent-queue #893 · 2026-09-27 — all three ci:go repos covered) ·
  other repos don't have it yet (measured 2026-09-26 `grep -c ci:go .github/workflows/ci.yml`: `park108` · `pos108-admin` · `pos108-store` · `pos108-terminal` = 0)
  · **When its turn comes:** the lane controller/reviewer adds `ci:go` (one PR at a time) **before** push/update-branch
  ⇒ full run ⇒ verdict ⇒ merge ⇒ remove `ci:go` · FAIL ⇒ remove `ci:go` · the label must be in the payload when the event fires ⇒ adding it later and rerunning **does not see the label**
  · a PR that is not behind (update-branch unavailable) ⇒ the author pushes one empty commit after the label is added ·
  🔴 **update-branch = new head = new verdict + must win a slot again** ⇒ do not press it on a PR waiting for a slot without asking the lane controller (2026-09-26 PR 2268: two update-branches from an unidentified session ⇒ verdict re-bound 3 times)
- ⚠️ Light gates queue behind `cargo` because they use the same runners (measured 04:56Z: 46 waiting · 29 light gates · 7 real builds) — separate runners for light gates require adding a label = owner's job

## 📄 Doc-only changes run no build or test CI

Owner's order 2026-10-09 *"Doc work doesn't need CI; check that, and make it a central rule"* (`0440977`) · applies to **every repo, both PRs and pushes to main**

A change that touches only docs (`*.md` · `docs/**` · design docs · blueprint HTML · `.ai_context`/`HANDOFF.md`) **must not compile, test, lint or build anything**.
Every CI run on a doc-only change is a runner taken away from code PRs waiting on the same machines.

- 🔴 **Required checks must still report green.** Give each required workflow a doc-only fast path: an early step that diffs the change and makes every heavy step `if: skip_build != 'true'`.
  **Never `paths-ignore` a required workflow**: a required check that never reports blocks the PR forever.
- 🔴 **The fast path must not wait for a heavy runner or start services.**
  - Decide "doc-only?" in a light first job.
  - Put `services:` (postgres and the like) and heavy steps in a second job gated on that decision.
  - A light job may run on the macOS pool (🖥 Big builds / ⚙️ CI runner: light gates there do not queue behind builds).
- **Check:** on a doc-only PR, every workflow finishes with **no build/test step run** and **no `services:` container started**. Look at a doc PR's job steps (`gh api repos/<slug>/actions/runs/<id>/jobs`).
  A repo where a doc PR still runs build/test ⇒ open a ticket in that repo. That is part of every controller's bottleneck survey.
- **Evidence 2026-10-09 `xchange`:**
  - Doc PR 565's `web` job ran typecheck + test + build, because `web.yml` has no doc filter.
  - Its `api` job skipped correctly (37 s of work) but waited **5 min** for a Dell runner and still started a postgres container.
  - Meanwhile 6 code PRs with PASS sat waiting for the same runners.

## 🚀 Deploy lanes — personal ships staging · org ships prod

Owner's order 2026-09-21: *"Have the personal-side git deploy staging, and adjust its actions by copying them from the org"* (`a55bf22`) · *"Have the org deploy prod"* (`a55bf22`)

| Side | repo | Lane it may push | Who works there |
|---|---|---|---|
| **personal** `yuthstyle88/<repo>-dev` | mirror of org | **`deploy/staging` only** | developers not in the org (no access to org repos) + work not yet reviewed |
| **org** `108-Plaza/<repo>` | the real one | **`release/prod` only** | the agent fleet · all PRs/reviews/merges |

- 🔴 **Never push `release/prod` from the personal side and never push `deploy/staging` from the org side** — once lanes cross,
  nobody can say which commit the running thing came from
- 🔴 **org has no staging** — owner redefined 2026-09-25 *"The org deploys to prod; there is no staging"* (`2d1d59f`) ·
  do not rely on "never push" alone (measured 09-25: `deploy/staging` on the org side still used in 7 repos, most recently core the same day) ⇒
  workflows must decide the lane by the pair **(repository, branch)**, not by branch alone — one file for both sides
  (the bridge does **not** sync `.github/` · the mirror gets a manual copy from org per the section below ⇒ a guard in one file lets
  the same copy work on both sides · **after changing the org side, always open a PR copying it to the mirror too**, otherwise the mirror has no guard) · reference pattern `jh-api#830`:
  a lane guard step in the first job allows only `108-Plaza/<repo>:release/prod` and `yuthstyle88/<repo>-dev:deploy/staging`;
  everything else goes red before building + each deploy job checks `github.repository` · the org-side `deploy/staging` branch may be deleted
  once that repo has the guard (tag `backup/*` first if it has commits main doesn't have)
- 🔴 **`deploy` can still be ordered only by the owner** (old rule unchanged) — this rule says *where to push*, not *when to push*

**Why the personal side gets a staging lane** (owner 2026-09-21): *"So developers on the personal side can deploy to Dell (staging)"* (`a55bf22`)
— people outside the org cannot open PRs on the org side and cannot read org private repos (measured 2026-09-20: `koeylp` = `permission: none`
on `108-Plaza/108heros-flutter`) ⇒ if the mirror had no staging lane, their work would never reach a test machine ·
this lane's destination is **k3s on Dell (`ibrowe.com`) namespace `staging`**, the same machine where the whole fleet's runners live
⚠️ the staging lane from mirrors has had an infra-level blocker (GHCR pushes colliding when builds run concurrently) — **deploy one repo at a time, never fire in parallel**
- ⚠️ **The lane name `prod` does not mean there is real production** — actual status is in [`STATE.md`](STATE.md) (no app is in production yet)

## `.github/workflows/**` on the personal side = a copy from org

**This reverses the old rule that said workflows on the two sides are "intentionally not synced"** — that left the mirror with fewer
and older workflows (measured 2026-09-21: org `pos108-core` has 13 files · `pos108-core-dev` has 6 · missing `independent-review` ·
`promote-staging` · `issue-link` · the new `supply-chain`) ⇒ the side people outside the org actually use was the side with the fewest gates

**Correct method:** copy the whole file from org, then change **only two things**
1. **Lane trigger** — `branches: [release/prod]` ⇒ `branches: [deploy/staging]` (the mirror has no prod lane)
2. **`runs-on`** — make it `[self-hosted, Linux, X64]` per the standard (the mirror still has `[self-hosted, pos108-ci]` in several files
   — same pool but needlessly narrower)
