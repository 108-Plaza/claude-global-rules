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
   git -C <repo> worktree remove --force <path> && git -C <repo> worktree prune
   ```
   A worker folder that is a full clone rather than a worktree (`~/worktrees/<slug>` with its own `.git` directory): `rm -rf` it once `git -C <path> status --porcelain` is empty and its branch tip is on `origin`.
2. **Never remove a folder in use:** a process has its cwd inside it (`lsof -a -d cwd | grep <path>`), or it has uncommitted changes or commits not on `origin`. Leave it, and write on the PR which folder was kept and why.
3. **Reviewers remove their own review worktree** as soon as the verdict is posted (PASS or FAIL). A re-review makes a new one; it is cheap.
4. **Every dispatch order ends with:** *"When your PR is merged or closed, delete your worktree for it. Also delete any worktree of yours whose PR is already merged before you start the next ticket."*
5. **On Dell**, removing the worktree of a PR you merged is allowed (`/data/yuth/worktrees/<slug>`). It belongs to that ticket, not to the shared machine. Everything else there stays "measure and report".
6. **Backstop:** the fleet-sweep **worktree pass** removes worktrees that are idle and whose work is pushed or merged. It catches what a dead session left. It is not a reason to skip step 1.

**Reviewers specifically** (owner's order 2026-09-28 — measured that day: one review session's targets totalled ~260 GB on Studio · a single one 144 GB = `incremental` 84 + `deps` 60):
- **base and head of the same PR use one worktree, one target** — `git checkout <base>` → test → `git checkout <head>` → test · never create separate `…-base` / `…-head` (previously 2–3 per PR)
- **builds for review set `CARGO_INCREMENTAL=0`** — the incremental cache is for edit-rebuild loops, not one build per commit · leaving it on = accumulates every reviewed commit
- **big repos (`pos108-core` · `rust-project-backend` · `jh-api`) build on Lenovo** with `scripts/lenovo-run.sh` (🖥 Big builds)
- review finished (verdict posted) ⇒ delete that PR's target immediately; don't wait for the sweeper

**The automatic sweeper** (`108-Ting-Ecosystem/scripts/fleet-sweep.sh`) already runs on Mac Studio (LaunchAgent) and Lenovo (cron) every 6 hrs — deletes targets in which no file was modified within the time threshold and that no process has open ·
**a process left holding files open in a target = the sweeper never touches that target** ⇒ always shut down unused jobs/pg/redis (real incident 09-28: `find | head` hung 12 hrs holding a 144 GB target)
- 🔴 **It also removes running test containers that carry no label** (since `108-Ting-Ecosystem` PR 226, 2026-10-14). It removes one only when all of these hold:
  no label and no compose project · restart policy none · image postgres/redis/mysql/mariadb/mongo/nginx/python · up ≥ 48 h · name not in `FLEET_SWEEP_KEEP_CONTAINERS`.
  A test DB you mean to keep standing ⇒ give it a restart policy (`--restart unless-stopped`) or add its name to the keep list, or it goes after 48 h.
  Why: on 2026-10-11 Dell held 95 unlabelled test containers 2–17 days old, with swap full.

Measured 2026-09-27: Studio had 118 containers (5 actually running · the rest named after ticket numbers `pg1956` `revpg2117` `pg789` … some left for 23 days) ·
440 volumes, 63 GB dead · Dell had 991 images (57.7 GB unused) + 206 dead volumes (41 GB) — the owner ordered all of it deleted the same day

---
