---
name: review-and-merge
description: >-
  How to review a PR and merge it: who reviews, the review checklist, the machine-read verdict format the independent-review gate parses, the three merge conditions, the four merge-base relaxations, batch merge, and when to stop and ask the owner. Use when reviewing a PR, posting or fixing a verdict, adding `reviewed`, or merging.
---

# Reviewing and merging

> Moved from `~/.claude/CLAUDE.md` at `ee7b381` (slimming step 2). Text is unchanged except: translated into English
> (each owner quote keeps the commit that first added the original), and infra-state tables replaced by pointers to `FLEET.md`.
> Until step 4 removes these sections from `CLAUDE.md`, an edit to one must be made in both files.

## 🟢 merge — the reviewer adds `reviewed` and merges

Owner's order 2026-09-10 *"Normally I have you review, then merge once CI is green"* (`f440019`) (permanent rule, every repo)

**All three met = merge immediately, no approval needed, do not stop to ask:**
1. A `PASS` / `PASS + follow-up` verdict from **a session that did not write the PR** has been posted on the PR
   (`> reviewer:` + `> head:` matching the current head · acceptance criteria checked one by one · verify run by the reviewer)
2. All required checks are green at the current head (`gh pr checks --required`) and `mergeStateStatus = CLEAN`
   — **or `UNSTABLE` caused purely by non-required (advisory) jobs** that are still pending/red: merge right away, no need to ask
   (owner's order 2026-09-27 *"Yes, make it a permanent rule"* (`ec0025c`) · reason: the advisory Windows tests of `pos108-terminal` have a single machine and sit queued for hours ·
   non-required `lenovo-org-ci-*` jobs go red because of the machine) · you must first prove that **every required check is green** and that the pending/red ones are **not in the required list**:
   `gh api repos/<slug>/branches/<default>/protection --jq '.required_status_checks.contexts'` · `BLOCKED` still must not be merged, as before
3. `git merge-base --is-ancestor origin/main <head>` passes — **`strict` differs per repo; never guess, check first:**
   `gh api repos/<slug>/branches/main/protection --jq .required_status_checks.strict`
   - `false` ⇒ GitHub **allows merging a PR that was green on an old base**, and main can go red ⇒ this check is the only guard
   - `true` ⇒ GitHub **enforces it already** (old base = `BEHIND`, cannot merge) ⇒ `update-branch` creates a new head ⇒ **a new verdict is required at that head**
     ⇒ PRs in these repos may need the verdict re-bound several times when main moves often (real incident `jh-api#747`: 3 rounds) · merge quickly after PASS
   - Measured 2026-09-24T01:33Z: `true` = `park108` · `jh-api` · `108-agent-queue` · `false` = `pos108-core` · `pos108-store` · `pos108-admin` · `pos108-orders` · `108-sell` (`claude-global-rules#3`)
   - **The four relaxations below share these terms** — they let a PASSed PR merge without `update-branch`, and nothing else:
     **Still required:** conditions 1 and 2 — a PASS bound to the current head and the required checks green at that head ·
     **Only where GitHub lets it through:** a `strict = true` repo still blocks a `BEHIND` PR, so they apply only where it allows the merge ·
     **Shared file** = anything more than one CI job reads: root and workspace manifests and lockfiles (`Cargo.toml`, `Cargo.lock`, `package.json`, lockfiles), `.github/**`,
     `migrations/**`, shared crates or packages the PR's area depends on, generated files either side commits, `build.rs` and build scripts · **not sure ⇒ treat it as shared** ·
     **After merging:** watch main's CI on that merge commit; red because two PRs disagree ⇒ **revert at once** and send that PR back for update-branch — never leave main red while you debug ·
     **Why all four exist:** on `xchange` every merge moved main and forced every other open PR through update-branch, a 10–60-minute run and a fresh verdict — PR 963 needed it 3 times, PR 2268's verdict was re-bound 3 times
   - 🟢 **Exception: main moved only by docs.** Owner's choice 2026-10-09 *"Except when the only difference is docs"* (`edb64e8`) ·
     **Condition:** every file changed on main since the PR's merge-base is a doc no build or check reads (`*.md`, `docs/**`, design docs) ·
     **Proof:** paste `git diff --name-only $(git merge-base origin/main <head>) origin/main` in a PR comment · one non-doc path ⇒ the exception is off
   - 🟢 **Exception: main moved only outside the PR's area.** Owner's order 2026-10-10 *"A: merge now. C: make it a permanent rule"* (`266585e`) (permanent) ·
     **Condition:** every file main changed is in a different top-level area from every file the PR changes (PR in `api/`, main moved `web/` and `app/`), and none of them is shared ·
     **Proof:** the same `git diff --name-only` output, plus which area the PR is in · one path in the PR's area, or one shared path ⇒ off
   - 🟢 **Exception: main moved only in files the PR does not touch (same area allowed).** Owner's order 2026-10-14 *"Take B and make it a permanent rule"* (`a64f321`) (permanent) ·
     **Condition, all of:** no file main changed is a file the PR changes · none of main's changed files is shared, where a module registry (`mod.rs` / `lib.rs` / `main.rs`) counts as shared **only if its diff removes or changes a line**
     (owner's order 2026-10-16 — additions only, a new `mod` or `pub use`, do not count; check with `git diff $(git merge-base origin/main <head>) origin/main -- <file> | grep -E '^-[^-]'`, which must print nothing, and paste that) ·
     and `git merge-tree --write-tree origin/main <head>` merges with no conflict ·
     **Proof:** a PR comment with `comm -12 <(git diff --name-only $(git merge-base origin/main <head>) origin/main | sort) <(git diff --name-only $(git merge-base origin/main <head>) <head> | sort)`, which must be **empty**,
     plus main's changed-file list showing no shared file, plus the `merge-tree` result · any overlap or any shared file ⇒ off
   - 🟢 **Batch merge: one CI run on the combined head decides for every PR in it.** Owner's order 2026-10-16 *"Can you gather them and run CI once together? It's incremental work running over and over; let the last CI run decide"* (`5a71961`) · *"No need to wait"* (`5a71961`)
     **Who:** the lane controller or a merger it names · one batch per repo at a time, so two batches never race on main ·
     **Build:** branch `batch/merge-<UTC>` from `origin/main` → `git merge --no-ff` each PR head in stack order (a base PR before the PRs stacked on it) → a PR that conflicts leaves this batch → push and open a PR, so the required checks run **once** on the batch head ·
     **Entry per PR:** condition 1 holds — a PASS from a session that did not write it, with nothing under "Must fix before merge"; that PASS binds to the head that went into the batch ·
     **What it allows:** green required checks on the batch head stand in for conditions 2 and 3 for **every** PR in it — no per-PR update-branch, run or re-bind ·
     🔴 **merge the batch PR with a merge commit, never squash**, so each PR head becomes an ancestor of main and GitHub marks every PR merged and closes its `Fixes #` ·
     **Red batch:** bisect by halves, then quarters, to find the PR that breaks it; send that one to rework and re-batch the rest · **never merge a red batch** ·
     **Why:** ten PRs cost 30–50 runs one at a time and 1–4 as a batch — the latest commit already contains the earlier ones (🧹 More than 3 CI runs queued)
🔴 **Still stop and ask the owner for:**
- verdict `FAIL`, or `PASS` with a "Must fix before merge" list
- migration · schema change · data backfill · destructive op
- touching the 4 BLOCK groups (section 🏷 The brand is 108heros — not 108jobs)
- going to production (`deploy/*`, `release/prod`) or changing a business rule the owner has not yet decided
- **`108-Plaza/CCTV-Platform`** — only the owner may add `reviewed`: never add it, never merge yourself, even with PASS + green CI
  (ordered 2026-09-11 · there were fake verdicts + `reviewed` on PR #16/#17)

**`reviewed` = a label saying the review passed, not a merge button** — the owner removed the `tq train` pipeline on 2026-09-15
(`108-agent-queue` `989396a` · PR #466) ⇒ nothing merges automatically · after adding the label you **must run `gh pr merge` yourself**,
otherwise the PR sits · `tq report` is a read-only report (the `--apply` text in `--help` is stale) ·
the old cron on Dell is backed up at `~/108mon/crontab.backup.20260915-tqtrain.txt`

## 2. Review — ticket closed / `pr_open` = start reviewing

"The implementer closed the ticket" and "CI is green" **are not evidence of quality** · no permission needed before reviewing

**Who reviews:** Claude reviews every ticket · **which session = the session that opened the ticket** (`> dispatched-by:`) — other sessions may add comments but **must not issue their own `Verdict:`**
(incident `pos108-store#256`: two sessions issued FAIL → PASS → FAIL within 3 minutes)
- Ticket opener is dead / silent more than 60 minutes after `pr_open` / ticket has no `dispatched-by` / the ticket opener wrote the PR itself (cannot review its own work) ⇒ another session may take over, but must **first post a claim comment on the PR**
  (`reviewing as <worker> — ticket opener silent N minutes`) and wait ≥1 minute · someone already claimed = add comments instead
- Tickets that Gemini put into the queue ⇒ `dispatched-by` = the Claude that told them to open it · none = the first Claude session that sees it takes it
- 🔴 Conflicting verdicts must not be left hanging — the ticket opener summarises in the thread which one stands and why
- The owner directly assigns a session to review a ticket = do as told
- 🔴 **The owner says "review work is idle, nobody is reviewing" = hand it to a peer session to review immediately, no 60-minute wait**
  (owner's order 2026-09-22 *"If I say review work is idle and nobody is reviewing, send it to a peer to review at once"* (`78af04d`)) —
  `ListAgents` to find an idle peer session (`idle`) → `SendMessage` one message with full context (the peer cannot see this conversation):
  PR link · related tickets · why review now (direct owner order, not the 60-minute silence rule) ·
  short root cause/fix summary · reminder of the normal review steps (read the ticket before the diff · run verify yourself · post the verdict in the standard format ·
  may add `reviewed` + merge yourself if PASS + CI green + merge-base passes) · **does not replace the 60-minute silence rule above** —
  only applies when the owner orders it directly like this, in that round; normally still wait 60 minutes as before

**Steps:** read the issue before the diff (the criteria are the issue, not preference) · go through the acceptance criteria one by one with `file:line` ·
**run verify yourself** in your own worktree · verdict `PASS` / `PASS+follow-up` / `FAIL` + list of required fixes ordered by importance, each with `file:line`
("not good yet" without a location does not count) · never close a round with "looks probably OK" · **found something missed *outside the ticket* → open a new ticket and send it back, don't fix it yourself** · a small fix *inside* the ticket ⇒ the reviewer fixes it (below)

🟢 **Small fix = the reviewer fixes it, no send-back.** Owner's order 2026-10-18 *"ถ้างานนิดเดียวไม่ต้องส่งต่อ ให้ คนรีวิว แก้ได้เลย"* · *"เช่นแก้ ไม่เกิน 30 บรรทัดให้แก้เองเลย"* · *"นี้คือสาเหตุให้กิน โควต้า และงานออกช้า"*
- **When:** every "must fix" the reviewer finds adds up to **≤30 changed lines**, inside the ticket's File scope, and the fix is clear (no design choice left open).
- **Do:** commit the fix on the PR branch yourself (message `fix(review): <what>`), re-run verify, then post the verdict at the new head. List the fix commit in the verdict under `Reviewer fix:` with what it changed and why.
- **Why:** a send-back costs a rework round: a message, the worker re-reading the ticket and PR, a push, a fresh CI run and a second review, for a few lines. That is where the quota and the time go.
- **Still send back (FAIL):** more than 30 lines · a fix outside the File scope · a design or business-rule question · anything that would edit, delete or weaken the tests the ticket author provided (🧪) · migrations, the 4 BLOCK groups and other must-ask items, which still go to the owner.
- **Merge:** a PASS that contains a reviewer fix of ≤30 lines satisfies condition 1 of 🟢 merge. Anything larger is the reviewer's own work and needs another session's PASS.

| Check | What happens if it slips |
|---|---|
| All **done criteria** met | Half done then closed ⇒ leftover work with no ticket |
| **Tests really catch regressions** — revert the fix and the tests must go red | A test that cannot go red = no test |
| Any test `#[ignore]`d/skipped/deleted? | skip=pass hides real bugs |
| Touches the DB ⇒ has the "data migration" section with all 4 items (see 📐 Class diagram before code, always) | Existing rows break at deploy with nobody having thought of them |
| Touches files outside the **file scope**? | Silently regresses other streams' work |
| Really wired up, or just the pieces written? | mutation test on the wiring, not just on the pieces |
| `git merge-base --is-ancestor origin/main <head>` | Green on an old base, merged, then main goes red |
| Fixed at the **root cause**? | No `stopgap` + root-cause ticket = **FAIL** |

🔴 PRs claiming "swept every place" usually fix the places programmers read and forget the places on-site people read (README ```bash blocks) ⇒
**always re-run the sweep command yourself** (incident park#204 → had to open park#213)

**Sending the verdict:** queued ticket ⇒ post on the PR by default · PASS with all conditions met ⇒ add `reviewed` + merge yourself (see section 🟢 merge) ·
after posting, `transition → in_review` (otherwise the queue hands this ticket to another reviewer again) ·
FAIL ⇒ end with "send back" + `in_review → rework` (`pr_open → rework` directly gives 409) + open a follow-up ticket if what slipped is out of scope · non-queue work ⇒ post only when the owner orders it

## 3. Verdict format — machine-read; a malformed one is invisible to the gate

```
> reviewer: <kind>/<session-id>
> head: <sha of the head reviewed — at least 7 chars>

Verdict: PASS | PASS+follow-up | FAIL   (PR <url> for issue #N)
Acceptance criteria: n/m met
  1. <criterion> — met (evidence: path:line)
  2. <criterion> — not met (wrong at: path:line, expected: …)
Verify I ran myself: <command> → <result>
Out of scope found: <none | issue #M just opened>
Must fix before merge: <list, or "none">
```

- 🔴 **Line 1 `> reviewer:`** is mandatory — identity in prose does not count
- 🔴 **Line 2 `> head:`** is mandatory — the gate counts only a `PASS` whose head matches the current head · `FAIL` does not count as a review ·
  **a new push (including `Merge branch 'main'`) = a new verdict is required**
- 🔴 **The verdict line must start with the English `Verdict:`** — the reader `decide.mjs` → `isVerdictComment()` counts only lines that
  (leading `#` stripped · case-insensitive) start with `verdict:` or `review:` **and** contain `pass`/`fail` on the same line ·
  a verdict word in another language (the Thai for "Verdict: PASS" or "Summary: passed") = invisible to the gate ⇒ log `Awaiting an independent review (no attributable review)`
  (unlike `no PASS on head <sha>` = seen but bound to the wrong head) · a FAIL written in another language shows no symptom until a PASS is needed to unlock the gate
  (incident `park108#763`: changing only the Thai verdict word → `Verdict:` turned the gate green in one round) ·
  **never wrap the whole line in `**`** — `**Verdict: PASS**` = malformed, gate red (`Verdict: **PASS**` is fine)
- 🔴 **Lines that are not the verdict must not start with the word `verdict` or `review`** — the gate reads every comment in the thread (skipping only content inside code blocks)
  strictness differs per repo (`park108` flags every line that starts with verdict and contains pass/fail) ⇒ it is read as a malformed verdict and then `setFailed`
  `unparseable verdict line` (incident `pos108-core#1936`) · put another word in front (`· verdict for …`) or fold it into the middle of a sentence ·
  rules got stricter 2026-09-15 ⇒ old comments can become the problem as soon as the branch rebases onto a new main (PR red without any code change)
- **Repos with this gate** = those with `.github/workflows/independent-review.yml` (measured 2026-09-18: `pos108-core` · `store` · `admin` · `orders` · `sell` ·
  `terminal` · `park108` · `jh-api` — not present: `108-agent-queue` · `108-platform-services`)
- **Gate red because of wording ⇒ fix the comment, not the code** — the gate re-runs as soon as the comment is edited:
  ```bash
  gh api repos/<o>/<r>/issues/<pr>/comments --jq '.[] | "\(.id)\t\(.body|split("\n")|map(select(test("^\\s*(verdict|review)";"i")))|join(" ⏎ "))"' | awk -F'\t' '$2!=""'
  gh api -X PATCH repos/<o>/<r>/issues/comments/<id> -f body="$(cat fixed.md)"
  ```
  🔴 **Never edit another session's comment yourself** — raise it in the thread or report to the owner
- ⚠️ Before concluding the gate rejected the format, compare times first — check run `started_at` older than the comment = nobody has judged yet, wait:
  ```bash
  gh api repos/<o>/<r>/commits/<head>/check-runs --jq '.check_runs[] | select(.name|test("independent")) | "\(.conclusion) started=\(.started_at)"'
  gh api repos/<o>/<r>/issues/<pr>/comments --jq '.[-1].created_at'
  ```

---
