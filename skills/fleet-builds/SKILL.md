---
name: fleet-builds
description: >-
  Heavy builds and cleanup on fleet machines: choosing the build machine by measurement, `zsh -lc` over ssh, Lenovo and `lenovo-run.sh`, park108 model measurement on the Mac mini, the pinned Rust toolchain, sweeping `target/`, Dell's `/data` layout, and cleaning up containers, worktrees and targets before reporting done. Use before a whole-workspace cargo build or test, on disk pressure, or when finishing a ticket that started containers or worktrees.
---

# Builds, disks and cleanup

> Moved from `~/.claude/CLAUDE.md` at `ee7b381` (slimming step 2). Text is unchanged except: translated into English
> (each owner quote keeps the commit that first added the original), and infra-state tables replaced by pointers to `FLEET.md`.
> Since step 4 (2026-10-19) this skill is the source of truth; `CLAUDE.md` keeps only a headline summary that points here. Edit the rule here, and the summary only if a headline changes.

## 🖥 Big builds — choose the machine by measurement, never by habit

Owner's order 2026-09-27 *"Send part of the work to Lenovo too"* (`d4e67d7`), amending the 2026-09-12 order that sent everything to Mac Studio.
⚠️ **Lenovo has been off since 2026-10-09**, so until the owner brings it back the choice is Studio or the MacBook — but still **measure first:**
```bash
ssh macstudio 'df -h /System/Volumes/Data | tail -1; uptime'
ssh macstudio 'ssh pos108-lenovo "bash -s"' <<< 'df -h /; uptime'
```

Which machine suits which build (cores, memory, what lives there): `FLEET.md` § Build machines.
**Dell is never a worker's local build or test machine** — Dell is the only Linux CI machine (Lenovo off), so a session's own `cargo` there takes CPU from every lane's CI · if a Linux-only build truly has to run there: `CARGO_BUILD_JOBS=8` and nothing else heavy at once.

🔴 **A session's own builds: run only what the work needs, on the right machine.** Owner's order 2026-10-18 (session claude/bb65c5d9), widening the xchange lane's 2026-10-17 rule to every lane: *"Put it in every lane"* (`e541b83`).
- **Why:** measured 2026-10-18T03:27Z: Dell at load **109 on 64 threads** with only 3 CI runners on. Three Dell `claude-N` sessions were building and testing all of `xchange` in their own worktrees (`w-da` · `lg6-r45` · `tw-1023`), and 6 Linux CI jobs of other lanes sat queued. The Mac Studio was at load 6.5 on 20 cores.
- **Reviewing or writing tests:** run **only the tests the ticket names or the PR adds**, by name (`cargo test -p <crate> --test <file> <name>`). Never the crate suite or the workspace: the PR's CI and `main` run the rest.
  - Mutation checks still apply: revert the fix and the named test must go red.
  - A ticket that names `cargo test -p <crate>` as a criterion: run what the ticket says.
- **A full build or test a session truly needs:** run it on the **Mac Studio**, not on Dell.

- 🔴 **Always `zsh -lc`** — a headless ssh has no `/opt/homebrew/bin` and no `~/.cargo/bin`:
  `ssh macstudio 'zsh -lc "cd ~/108-Ting-Ecosystem/Commerce-Platform/pos108/core && cargo test -p <crate>"'`
- 🔴 **Folder layouts differ; never copy a path between machines** — Studio has `~/108-Ting-Ecosystem/Commerce-Platform/pos108/{core,terminal}` · `JH-Platform/Api` · `parking/park108`, the MacBook has `pos/` `heros/` `parking/`
- 🔴 **`park108` model measurement runs on the Mac mini only** (`Mac-mini-khxng-ai-01` · 100.100.204.107) — the models and the 244-image plate set live there and that set's `README.md` forbids committing them to **any** repo (PDPA) ⇒
  never copy the images off the machine · work in a worktree under `~/park108-src/.worktrees/` and delete it when done
- Reaching Studio (Tailscale, LAN alias): `FLEET.md` § Build machines.
- 🔴 **Commands to Lenovo go as a script over stdin** — it is reachable from Mac Studio only, its ssh lands in cmd.exe so nested quotes break every way, and **there is no sftp ⇒ `scp` cannot get in**:
  `ssh macstudio 'ssh pos108-lenovo "bash -s"' < /path/to/script.sh` · 🔑 `sudo` inside WSL needs a password, but `wsl -u root` from cmd.exe does not ⇒ all root work goes that way
- 🟢 **For cargo on Lenovo use `scripts/lenovo-run.sh`** (in `108-Ting-Ecosystem` · `cb764edc`) — run it from that repo's worktree on Studio:
  `…/scripts/lenovo-run.sh -- cargo test -p <crate>` ⇒ output and exit code come straight back · **commit + push first** (pending edits or new untracked files ⇒ `rc=3`, because Lenovo cannot see them) ·
  it reuses a per-branch worktree `~/worktrees/lr-*` for incremental builds and locks out two colliding jobs itself

**Fleet toolchain = one pinned number, the same in every repo** — owner's order 2026-10-17 *"That is, pin it to a version but keep it working"* (`0f859df`) ·
*"Because a fixed version won't break"* (`0f859df`) · *"But it must be the same number everywhere"* (`0f859df`) ⇒ **`channel = "stable"` is not acceptable**: it moves every ~6 weeks and a new clippy lint turns CI red with no code change.

**The pinned number is `1.99.1`** (measured 2026-10-17: rustc/cargo 1.99.1 on the MacBook, Mac Studio and Dell).
```bash
rustup toolchain install 1.99.1 --profile minimal -c clippy -c rustfmt
```
- 🔴 **Every repo states it in `rust-toolchain.toml` as `channel = "1.99.1"`**, and every workflow pins `dtolnay/rust-toolchain@1.99.1` — never `@stable`, `@master` or a bare `rustup default`
- 🔴 **The one allowed exception is `heros/api`'s fmt step**: its `.rustfmt.toml` uses nightly-only options (`imports_granularity`, `group_imports`), so that **step** installs nightly and pins `RUSTFMT` to the nightly binary (`cargo +nightly fmt` alone does not work there — the wrapper resolves to the pinned toolchain and silently ignores the options). Build, test and clippy in that repo still use the pinned number.
- Moving the number is a fleet decision: bump it in every repo in one round, or the repos disagree and "green locally" stops meaning anything
- A repo's `rust-toolchain.toml` always wins over the machine default, which is why the pin has to live in the repos and not in `rustup default`

Which repos do not follow the pin yet: `FLEET.md` § Rust toolchain.

**Sweep `target/` periodically:**
```bash
ssh macstudio 'find ~/108-Ting-Ecosystem ~/IdeaProjects -maxdepth 6 -type d -name target -prune -print0 | xargs -0 rm -rf'
```
First check `pgrep -x cargo; pgrep -x rustc` — **not** `pgrep -f cargo`, which matches `.cargo/bin` in anyone's PATH · after a sweep the next run is one cold build

## 💽 On Dell: worktrees and everything heavy live in `/data`, not `/home`

Owner's order 2026-09-19 *"Move actions-runner to /data"* (`611d3cc`) then *"From now on, create worktrees in /data"* (`611d3cc`)

| Item | Correct location |
|---|---|
| worktree created on Dell | **`/data/yuth/worktrees/<slug>`** (already created, writable, no sudo needed) |
| `target/` intentionally kept across runs | `/data/yuth/target-<slug>` (existing ones already follow this form) |
| GitHub runner `_work` | `/data/actions-runners/<runner>` (moved with sudo + symlink back to `/home/yuth/<runner>`) |

**Why:** `/home` on Dell is nvme **1.8 TB** while `/data` is **6 TB (3.7 TB free)** · 2026-09-19 `/home` was 100% full (14 GB left)
and CI went red fleet-wide with `System.IO.IOException: No space left on device` — jobs died mid `cargo nextest run`
and died at the cleanup step of `actions/checkout` (the latter symptom showed as `mergeStateStatus = UNSTABLE` on PRs that had nothing wrong)
Measured that day: `target/` 148 folders totalling **709 GB** · `scratch/` 275 GB · `worktrees/` 168 GB · runner `_work` ~300 GB

```bash
ssh Dell-server 'df -h /home /data'        # always look first
git worktree add /data/yuth/worktrees/<slug> -b <branch> origin/main     # not ~/worktrees
```
🔴 **Never delete things on this machine yourself, even when free space is critical** — it is a fleet-wide shared resource · measure, then report to the owner with runnable commands
· `/home/koey` (260 GB) belongs to another user, not the fleet

## 🧹 Clean up what you created for a ticket before reporting it done

Owner's order 2026-09-27 *"Workers tend to leave things running, never clean up, and keep creating more"* (`a1f986c`) · *"Otherwise everything fills up"* (`a1f986c`) ·
widened 2026-10-19 *"ใคร ทำงาน เสร็จต้องทำความสะอาดฮาร์ทดิส"*: **every role, every machine used, every kind of work** (not only tickets). Reports end with `cleanup: removed <what> on <machine>; kept <what> because <why>`. Delete folders with `bash ~/.claude/rules-repo/bin/finish-cleanup <dir>...` (allowed in every machine's settings; it runs the safety checks in rule 2 below and prints that line), never into the Finder Trash. Never create folders directly under `~`.
Measured 2026-10-19 on Mac Studio: 9 GB free of 1.8 TB, `~/worktrees` 420 GB, `target/` in leftover worktrees ~520 GB; clearing old worktrees brought it to 512 GB free ·
Principle: **anything holding one ticket's data = use once and discard · anything expensive to recreate that holds nobody's data = reuse**

| Item | What to do |
|---|---|
| DB/Redis container started to test one ticket | `docker run --rm --label fleet.worker=<kind>/<id> --label fleet.ticket=<owner/repo>#<n> …` · never `--restart` · when the ticket is done, `docker stop` (`--rm` removes the container together with its unnamed volumes) |
| Test DB server | **use the repo's existing standing one on that machine** (e.g. `jh-postgres-test` :5433) — tests create/drop their own sub-databases · none available ⇒ the row above |
| testcontainers | cleans up itself on normal exit · **killing a test midway = leftover containers** ⇒ `docker ps -aq --filter label=org.testcontainers.managed-by=testcontainers` then `docker rm -fv` |
| worktree `target/` | delete together with the worktree at merge / ticket abandonment · 🔴 **never let two worktrees of the same package share `CARGO_TARGET_DIR`** — cargo's hash does not include the path ⇒ the second worktree runs the other's test binaries with no warning (tried and reverted 2026-09-03) |
| image | don't tag images to keep them yourself · need it again ⇒ `pull` again |

**Before reporting done, these must be empty:** `docker ps -a --filter label=fleet.worker=<kind>/<id>` · the ticket's worktree deleted together with `target/`

### 🧹 Merged or closed ⇒ whoever merges or closes it removes the worktrees

Owner's order 2026-10-19 *"สร้างกฏ ว่า ใครทำงาน merge แล้วต้อง ทำความสะอาด worktree ด้วย"* · *"ผมเคยทำกฏไว้แล้ว ทำไม มันไม่ทำงาน"*

**Why the rule above did not work:**
- A worker "finishes" at `pr_open`, but it must **keep** the worktree then, because a FAIL sends the PR back for rework.
- The merge happens later, in **another session** (reviewer or merger), and no merge step said to clean up. So nobody owned the worktree after merge.
- Dispatch messages never carried a cleanup step, and agy workers do not read this file.
- `git-gone` refuses to delete a branch that is checked out in a worktree, so the leftover worktrees also kept their merged branches alive.
- **Measured 2026-10-19 on Mac Studio:** the disk was at 100% (9 GB free of 1.8 TB). Leftover worktrees held ~520 GB of `target/`, and `~/worktrees` had 575 entries.

**The rule:**
1. **The session that runs `gh pr merge`, or closes a PR without merging, removes that PR's worktrees in the same turn**: on its own machine and, where it can reach it, on the worker's machine. Find the machine in `GET /v1/workers` (row of the PR's `> worker:`) or in the take-ticket comment.
   ```bash
   git -C <repo> worktree list --porcelain | awk '/^worktree /{w=$2} /^branch refs\/heads\/<branch>$/{print w}'
   bash ~/.claude/rules-repo/bin/finish-cleanup <path>...
   ```
   The script handles worktrees (`git worktree remove`) and full clones (`~/worktrees/<slug>` with its own `.git`) alike, and keeps any folder that fails rule 2.
2. **Never remove a folder in use:** a process has its cwd inside it (`lsof -a -d cwd | grep <path>`), or it has uncommitted changes or commits not on `origin`. Leave it, and write on the PR which folder was kept and why.
   **Nor one that holds a gitignored secret** (`git status` never shows ignored files, so such a worktree looks clean). `finish-cleanup` lists ignored files outside caches and keeps the worktree when one looks like a secret (`esp32s3-rs/src/config.rs`, `.secret.key`, `.env`, `.env.*`, `*.pem`, `*.key`, `credentials*`). 🔴 **A secret's only copy never lives inside a worktree**: keep it in `~/.config/<project>/` (mode 600) and copy it in. Pass `--allow-secret <file>` only for a throwaway secret (bank-bot's test `.secret.key` from `head -c 32 /dev/urandom`) or after `cmp <file> ~/.config/<project>/<file>` shows a byte-identical copy outside. Why: 2026-11-28 the only flashed ScreenLink board config was deleted with `~/worktrees/sl-flash-main`, and the Trash had been emptied. **The ScreenLink board config now lives at `~/.config/screenlink/config.rs` on the MacBook.**
3. **Reviewers remove their own review worktree** as soon as the verdict is posted (PASS or FAIL). A re-review makes a new one; it is cheap.
4. **Every dispatch order ends with:** *"When your PR is merged or closed, delete your worktree for it. Also delete any worktree of yours whose PR is already merged before you start the next ticket."*
5. **On Dell**, removing the worktree of a PR you merged is allowed (`/data/yuth/worktrees/<slug>`). It belongs to that ticket, not to the shared machine. Everything else there stays "measure and report".
6. **Backstop: the fleet-sweep worktree pass** (since `108-Ting-Ecosystem` PR 287, 2026-11-26; owner *"ตัวกำจัดที่ต้นตอ"* · *"เพิ่ม ทุกเครื่องเลยนะ"*). It catches what a dead session or a forgetful merger left. It is not a reason to skip step 1.
   - **Where:** every direct child of a worktree root: `~/worktrees`, any `.worktrees/` or `.claude/worktrees/` up to 3 levels under `~`, and `/data/yuth/worktrees`. Linked worktrees and scratch clones alike (owner *"มันเป็นปัญหาเดียวกัน"*).
   - **Removes one only when all hold:** no process is inside it (lsof; lsof gives nothing ⇒ nothing is removed) · nothing outside `.git/` changed in 24 h · `git status` clean · every commit is on `origin`, or its PR is MERGED/CLOSED and that PR's head contains the local commit (OPEN ⇒ kept) · not locked (`git worktree lock`) · not on `FLEET_SWEEP_KEEP_WORKTREES` · no gitignored file outside build caches looks like a secret, per the rules repo's `bin/ignored-secrets`, the list `finish-cleanup` also uses (scan missing or failing ⇒ kept; `108-Ting-Ecosystem` PR 289). A clone also needs no stash, no live linked worktree, and every local branch safe.
   - **Not removed:** unmerged work, however old. Branch refs are never deleted.
   - **Why a worktree is still on disk:** `grep 'worktree:' ~/Library/Logs/fleet-sweep.log` (Macs) or `~/.local/state/fleet-sweep.log` (Dell). Every kept folder logs `kept (<reason>)`.
   - **Keep one deliberately:** `git worktree lock <path>`, or add it to `FLEET_SWEEP_KEEP_WORKTREES` (colon-separated; read at install, so reinstall with `--scheduled` after changing it). Turn the pass off with `FLEET_SWEEP_WORKTREES=0`.
   - **Why it was needed:** step 1 alone did not hold. On 2026-11-26 Studio's `~/worktrees` had 913 folders again, and this line had promised a backstop that did not exist since 2026-10-19 (#246).

**Reviewers specifically** (owner's order 2026-09-28 — measured that day: one review session's targets totalled ~260 GB on Studio · a single one 144 GB = `incremental` 84 + `deps` 60):
- **base and head of the same PR use one worktree, one target** — `git checkout <base>` → test → `git checkout <head>` → test · never create separate `…-base` / `…-head` (previously 2–3 per PR)
- **builds for review set `CARGO_INCREMENTAL=0`** — the incremental cache is for edit-rebuild loops, not one build per commit · leaving it on = accumulates every reviewed commit
- **big repos (`pos108-core` · `rust-project-backend` · `jh-api`) build on Lenovo** with `scripts/lenovo-run.sh` (🖥 Big builds)
- review finished (verdict posted) ⇒ delete that PR's target immediately; don't wait for the sweeper

**The automatic sweeper** (`108-Ting-Ecosystem/scripts/fleet-sweep.sh`) runs on every machine installed with `--scheduled` (MacBook, Mac Studio, Mac mini, Warut, Dell; measured 2026-11-26) at 07:00 and 13:00 ICT, pulling itself from `origin/main` each round — it removes finished worktrees (rule 6 above) and deletes targets in which no file was modified within the time threshold and that no process has open ·
**a process left holding files open in a target = the sweeper never touches that target** ⇒ always shut down unused jobs/pg/redis (real incident 09-28: `find | head` hung 12 hrs holding a 144 GB target)
- 🔴 **It also removes running test containers that carry no label** (since `108-Ting-Ecosystem` PR 226, 2026-10-14). It removes one only when all of these hold:
  no label and no compose project · restart policy none · image postgres/redis/mysql/mariadb/mongo/nginx/python · up ≥ 48 h · name not in `FLEET_SWEEP_KEEP_CONTAINERS`.
  A test DB you mean to keep standing ⇒ give it a restart policy (`--restart unless-stopped`) or add its name to the keep list, or it goes after 48 h.
  Why: on 2026-10-11 Dell held 95 unlabelled test containers 2–17 days old, with swap full.

Measured 2026-09-27: Studio had 118 containers (5 actually running · the rest named after ticket numbers `pg1956` `revpg2117` `pg789` … some left for 23 days) ·
440 volumes, 63 GB dead · Dell had 991 images (57.7 GB unused) + 206 dead volumes (41 GB) — the owner ordered all of it deleted the same day

---

## 🖥 Builds, disks and cleanup — full rule

_Moved verbatim from the global rules `CLAUDE.md` on 2026-11-27 to cut the per-session load; the headline stays there._

→ skill **`fleet-builds`** (machine choice, `zsh -lc`, Lenovo `lenovo-run.sh`, park108 on the Mac mini, pinned Rust toolchain, sweeping `target/`, Dell `/data`, cleanup). Build machines: `FLEET.md` § Build machines. Headlines:
- **Choose the machine by measurement** (`uptime`, `df -h`) · 🔴 **Dell is never a session's own build/test machine** — it is the only Linux CI box · a full build a session truly needs runs on the **Mac Studio**
- 🔴 **Review or test-writing runs only the tests the ticket names or the PR adds, by name** — never the crate suite or the workspace (owner 2026-10-18 *"ใส่ ทุกเลน"*)
- 🔴 **On Dell, worktrees go to `/data/yuth/worktrees/<slug>`**, never `/home` · **never delete things on Dell yourself** — measure and report
- 🔴 **Fleet Rust toolchain is one pinned number** (`rust-toolchain.toml` + `dtolnay/rust-toolchain@<n>`, never `stable`) — the number is in `FLEET.md`
- 🔴 **Whoever finishes a piece of work cleans up, and cleans the disk it used, before reporting done — never leave junk behind** (owner 2026-10-19 *"ใคร ทำงาน เสร็จต้องทำความสะอาดฮาร์ทดิส"* · restated 2026-11-10 *"ทำงานจบต้อง ทำความสะอาด งาน เสมอ ห้าม ทิ้ง ขยะไว้รก"*). This applies to every role: implementer, reviewer, controller, ticket writer, a one-off investigation, and an owner-direct task.
  - "Finished" = your last action on it: `pr_open` (keep only the worktree, for rework), verdict posted, ticket returned or blocked, investigation reported, PR merged or closed.
  - Remove what **you** created on **every machine you used**: `target/` and build output · test containers and their volumes (`docker run --rm --label fleet.worker=<kind>/<id>`, never `--restart`) · scratch clones and copies · downloaded artifacts · temp dirs.
  - Delete folders with **`bash ~/.claude/rules-repo/bin/finish-cleanup <dir>...`** (owner 2026-10-21 *"เพราะ มันต้อง รัน ตอนปิด งาน"*). Every machine's `~/.claude/settings.json` allows exactly this command, so it runs without a prompt where a bare `rm` is blocked. It deletes only scratch folders (`~/worktrees/`, `/data/yuth/worktrees/`, a repo's `.worktrees/`, the session's `claude-<uid>` temp dir), refuses one a process is in or that holds uncommitted or unpushed work (a squash-merged PR's content on main counts as pushed), and prints the `cleanup:` line. Never widen the allow rule to `rm`; change the script's checks instead. **Never move anything to the Finder Trash**, which frees nothing and needs Full Disk Access to empty.
  - Never create folders directly under `~` (`~/review-*`, `~/wt*`, `~/tmp-*`). Work in `~/worktrees/<slug>` or the repo's `.worktrees/`, so a sweeper can find it.
  - **The report states it:** one line `cleanup: removed <what> on <machine>; kept <what> because <why>`. No line = not done.
  - Reviewers use one worktree per PR and `CARGO_INCREMENTAL=0`.
  - **Why:** 2026-10-19 Mac Studio reached 100% (9 GB free of 1.8 TB). Measured that day: `~/worktrees` held 420 GB and `target/` folders in leftover worktrees held ~520 GB. Clearing old worktrees brought free space to 512 GB. Details: skill `fleet-builds` § 🧹
- 🔴 **Whoever merges or closes a PR removes its worktrees in the same turn** (owner 2026-10-19 *"ใครทำงาน merge แล้วต้อง ทำความสะอาด worktree ด้วย"*). That covers the merger's own machine and, where reachable, the worker's machine. Leave a folder only if a process is in it or it holds unpushed work, and say so on the PR. Reviewers delete their review worktree once the verdict is posted. Every dispatch order ends with "delete your worktree once your PR is merged or closed". Why the old rule failed: the worker must keep its worktree at `pr_open` (rework), the merge happens later in another session, and no step owned cleanup ⇒ Studio hit 100% on 2026-10-19 with ~520 GB in leftover worktrees. Details: skill `fleet-builds` § 🧹 Merged or closed

## Merged branches

_Moved verbatim from the global rules `CLAUDE.md` on 2026-11-27 to cut the per-session load; the headline stays there._

**Merged = delete immediately, both local and remote, without asking** (not a destructive op)
- Our repos (`108-Plaza/*` · `yuthstyle88/*`) have `delete_branch_on_merge` enabled · new repo: `gh api -X PATCH repos/<slug> -F delete_branch_on_merge=true` ·
  `fetch.prune true` is set globally
- local: after every merge · the scripts live in rules-repo ⇒ present on every machine via autopull (previously in `~/bin` on Mac Studio only · measured 2026-10-04)
  - `~/.claude/rules-repo/bin/git-gone [--dry-run]` — **the main one** · catches squash merges (head of a merged PR at the same sha) · unsure whether deletable ⇒ prints `REVIEW`, doesn't delete
  - `~/.claude/rules-repo/bin/git-cleanup-merged.sh [--remote] [--dry-run] [REPO ...]` — also deletes on remote / across repos · checks only ancestry + `git cherry` per commit ⇒ **multi-commit squashes are not caught** (they stay behind; nothing is wrongly deleted)
- **Delete only what is proven to lose no commit:** tip is an ancestor of `origin/<default>` or `git cherry` leaves no `+` ·
  still has unique commits ⇒ never delete; report to the user
- **Never delete:** `main` `master` `develop` `dev` `gh-pages` `release/*` `deploy/*` (`deploy/staging` = trigger build) `auto/*` `backup/*` `archive/*` ·
  branches checked out in any worktree · branches with an open PR
- **Conditional:** `prod` `production` `staging` `sync/*` — deletable if no workflow references them (`git grep -n -A3 'branches:' origin/main -- .github/workflows`)
- Skip: archived repos (`Notification-Platform` · `Loyalty-Platform`) · other people's upstreams · beware redirect aliases — canonicalize with `gh api repos/<slug> -q .full_name` before counting/deleting
  · measured aliases: `108-Plaza/api-108jobs`→`jh-api` · `yuthstyle88/fast-work-new`→`jh-api-dev` ·
  `yuthstyle88/108jobs-clean`→`108jobs-web-dev` · `yuthstyle88/108jobs-flutter`→`108heros-flutter-dev`
