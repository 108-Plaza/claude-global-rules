# FLEET — what is where today

Infra state for the agent fleet: machines, sessions, accounts, lanes, runners, toolchain and disk layout.
`STATE.md` answers a different question (is any app in production? no). This file answers "what is where today".
It syncs to every machine through `108-Plaza/claude-global-rules`, the same way as `CLAUDE.md` and `STATE.md`.

**Everything here is a measurement, not a rule.** Each table carries a `measured:` line (date and source)
and the command that re-measures it. Older than you can trust ⇒ re-measure before you act on it, and update the table.

> **Migration status (steps 1 and 4 of the plan in `108-Ting-Ecosystem/docs/proposals/global-claude-md-slimming.md`):**
> these tables are a pure move from `CLAUDE.md` at `ee7b381`, translated to English. `CLAUDE.md` still carries
> pointers to these tables since step 4 (2026-10-19), so **this file is the only copy: edit it here.** (The repo-name
> aliases still appear in one line of `CLAUDE.md` § Merged Branch Auto-Cleanup; change both if they move.)

Owner quotes are translated into English. The commit ref after each one is where the original first appears in
`CLAUDE.md` (`git log -p <sha> -- CLAUDE.md`).

---

## Machines that carry the rules

measured: as recorded in `CLAUDE.md` § ✏️ How to edit this file (last changed in `ee7b381`, 2026-10-17); Lenovo off since 2026-10-09.
Re-measure: on each machine, `git -C ~/.claude/rules-repo log -1 --format=%h` and `tail -3 ~/.claude/rules-sync.log`; compare with `git ls-remote https://github.com/108-Plaza/claude-global-rules HEAD`.

| Machine | ssh | Pulls updates itself |
|---|---|---|
| MacBook · Mac Studio · Mac mini | `macstudio` · `macmini` (user `yuth`) | LaunchAgent `com.108ting.claude-rules-autopull` |
| Dell (`ibrowe.com`) | `Dell-server` | cron `*/15` |
| **Lenovo — WSL2 on `DESKTOP-ENCHS4F`** (user `worker`) | `pos108-lenovo`, **reachable only from Mac Studio** | cron `*/15` (read-only deploy key id `164563018`) |

- **Lenovo uses its own deploy key** (`~/.ssh/id_ed25519_rules`; the repo's `core.sshCommand` points to that key), so the remote is `git@github.com:`, not https.
- Lenovo's ssh lands in **cmd.exe**, not WSL: call through `bash -s` or `bash -c "…"` (single quotes don't work; cmd doesn't strip them). There is **no sftp**, so `scp` cannot get in; send over stdin only.
- `legion-utd-1` (100.98.93.83) is a different machine: port 22 closed, **no rules yet**.

## Implementer sessions per machine

measured: as recorded in `CLAUDE.md` § 🎛 (last changed 2026-10-17). The table there is marked *what is intended, not what is running*.
Re-measure: `tmux ls` (or `screen -ls` on Warut's MacBook) on each machine, and the pane's last line for the model: `tmux capture-pane -p -t <s> | tail -1`.

| Machine | Reach · sessions · worker id | Must know |
|---|---|---|
| **Dell** | `ssh Dell-server` · tmux `gemini-1..6` · `gemini/pool-N` · cwd `/data/yuth/worktrees` | The big Linux machine: k3s, CI and the DBs live here too. |
| **Mac Studio** | `ssh macstudio 'zsh -lc "…"'` · tmux `agy-1..10` · `gemini/studio-N` · cwd `~/worktrees` | ⚠️ `~/worktrees` holds other sessions' worktrees ⇒ the message must order the worker to create its own folder and touch no existing one. `agy-14..16` are gone (2026-10-16 reboot) ⇒ tickets still pinned to them must be re-pinned by the lane controller. Not the autopilot `auto-studio01..04` (plists renamed `*.off-20261010-owner`). |
| **Mac Studio (Claude)** | tmux `claude-1..5` · `claude --dangerously-skip-permissions --model claude-opus-5-5` · cwd `~/108-Ting-Ecosystem` | Same `tmux send-keys` / `capture-pane` as agy. |
| **Warut's MacBook** | `ssh warut-mbp "screen -S agy-N -p 0 -X stuff \$'<message>\r'"` · `screen`, not tmux · `agy-1..6` · `gemini/warut-N` · cwd `~/worktrees` | **Not the fleet's machine.** 10 cores ⇒ light work; heavy Rust goes to Dell/Studio. Reach it from the Mac mini or the MacBook, **not from Studio** (the alias does not resolve there; go `ssh macmini 'ssh warut-mbp "…"'`). Read output with `screen … -X hardcopy /tmp/a.txt`, then `tr -cd "\11\12\40-\176" < /tmp/a.txt \| tail -30`. Cancel a turn with `stuff $'\e'`. |
| **Mac mini** | `ssh macmini 'zsh -lc "…"'` (its Tailscale route drops; from the home LAN use `macmini-lan` → `192.168.1.68`) · tmux `agy-1..5` · `gemini/mini-N` · cwd `~/worktrees` | M1 · 8 cores · 16 GB ⇒ **light work only**, no whole-workspace Rust. Runs **Flash** ⇒ `class:mechanical` only. node defaults to Homebrew v26, which breaks jsdom ⇒ the message must order `source ~/.nvm/nvm.sh && nvm use 24` before any `npm`. No auto-restart yet. |
| **Lenovo** (WSL2) | ⚠️ **off since 2026-10-09** · when back: `ssh macstudio 'ssh pos108-lenovo "bash -s"'`, then `tmux send-keys …` on stdin · `agy-1..2` · `gemini/lenovo-N` | Reachable only from Mac Studio. ssh lands in cmd.exe ⇒ send scripts over stdin; no sftp, so `scp` cannot get in. For the owner to watch: `ssh -t macstudio 'ssh -t pos108-lenovo "wsl -e tmux attach -t agy-N"'`, exit with `Ctrl-B D`, **never Ctrl-C**. Does not recover after a WSL/Windows restart. ⚠️ The agy on Lenovo's **Windows** side is not a worker (toolchain does not match the fleet; dies when ssh drops). |

Auto-restart and machine notes (same source, same date):

- Studio and Warut have LaunchAgent `com.108plaza.agy-sessions` → `~/.local/bin/agy-sessions-up.sh` (at login and every 5 minutes; starts only missing sessions; log `~/Library/Logs/agy-sessions.log`).
- **Order delivery (`/v1/dispatch`):** every worker machine runs the delivery agent, installed 2026-10-21 on the owner's order: Studio, Dell, the Mac mini, Warut and jam. Each runs `~/.local/share/tq-deliver/tq-deliver.sh` (copied from `108-agent-queue` `635d017`) in a session named `tq-deliver`, and keeps its cursor in `~/.cache/tq-deliver/cursor`. `~/.local/bin/tq-deliver-up.sh` starts the session when it is missing.

  | Machine | Session | Kept alive by | Log |
  |---|---|---|---|
  | Studio | tmux | `agy-sessions-up.sh` (LaunchAgent `com.108plaza.agy-sessions`) | `~/Library/Logs/tq-deliver.log` |
  | Dell, Mac mini | tmux | cron `@reboot` + `*/5` (crontab backup `~/.cache/tq-deliver/crontab.bak-20261021`) | `~/.cache/tq-deliver/deliver.log` |
  | Warut | screen | `agy-sessions-up.sh` (LaunchAgent `com.108plaza.agy-sessions`) | `~/.cache/tq-deliver/deliver.log` |
  | jam | screen | LaunchAgent `com.108plaza.tq-deliver` | `~/.cache/tq-deliver/deliver.log` |

  **Stopgap:** a `shim/hostname` printing the canonical host (`studio` · `dell` · `mac-mini` · `warut` · `jam`) comes first on the agent's `PATH`, because `GET /v1/orders` does not canonicalise the host (108-agent-queue#1079). Remove the shims once that fix is deployed.
- **jam** (`ssh jam`, user `Direwolves`) has 5 Gemini 4 Argon sessions in screen, `agy-1..5`, worker ids `gemini/jam-1..5`, cwd `~/worktrees`, ponytail installed. Its presence reporter `~/.local/bin/tq-presence.sh` (a copy of Warut's) runs from LaunchAgent `com.108plaza.tq-presence`, and its map `~/.config/tq/presence.map` was added 2026-10-21. LaunchAgent `com.108plaza.agy-sessions` → `~/.local/bin/agy-sessions-up.sh` restarts a missing session (at login and every 5 minutes). agy trusts `~/worktrees` (the owner answered the folder-trust prompt on 2026-10-21; recorded in `~/.gemini/antigravity-cli/settings.json`). Without that trust, a new session stops at the prompt while presence still reports it `free`.
- **Who can reach do-sgp1** (xc-v3 host, `152.42.247.83`, as root): the owner's MacBook (alias `do-sgp1`, `~/.ssh/id_rsa`) and, since 2026-10-21, the Mac Studio (`~/.ssh/id_ed25519`, added by the owner; no alias, so use `root@152.42.247.83`). Dell cannot reach it. xc-v3 deploys run by hand per `xchange/deploy/README.md` §3, because the §3a `release/prod` lane has no secrets set.
- Studio also has `com.108plaza.claude-sessions` for `claude-1..5`. Since 2026-10-16 Studio comes back by itself after a reboot (FileVault off + auto-login).
- **A reboot kills every running turn** ⇒ re-check the panes before assuming a dispatched ticket is still being worked.
- The agents run only while that user is logged in ⇒ to drain a session for good, lower the script first, or it returns within 5 minutes.
- **tq env:** Warut, Lenovo, Studio and the Mac mini all have `~/.config/tq/env` (`TQ` + `TQ_TOKEN`), so they can claim and heartbeat. **Never put an autopilot token (`TQ_AUTOPILOT_*`) on Warut's machine**; the owner removed the one that arrived with it.
- **gh on Warut's machine is logged in as `yuthstyle88`**, although the machine is not the fleet's, and git uses that token (can clone and push private repos). To remove: `gh auth logout -h github.com -u yuthstyle88` and `git config --global --unset-all credential.https://github.com.helper`.
- **ponytail** (5.3.2) is installed for agy on Mac Studio, Dell, the Mac mini and Warut. Its `AGENTS.md` sits in each agy workspace: Studio, Mac mini and Warut `~/worktrees/AGENTS.md`; Dell `/data/yuth/worktrees/AGENTS.md`. Sessions restarted for it on 2026-10-17 (16:43–16:56Z): Studio `agy-1/2/3/5/6/7/9`, Dell `gemini-2..6`, Mac mini `agy-1..5`, Warut `agy-2/3/5`. Measure the others with `/skills` (expect `8 skills`, including `ponytail:ponytail`).

## Autopilot fleet

measured: as recorded in `CLAUDE.md` § 🎛 (stopped 2026-09-25, owner: *"Fix it so Gemini does not pull from the queue itself"* (`fbb2791`)).
Re-measure: Studio `launchctl print gui/$(id -u)/com.108plaza.tq-autopilot.gemini`; Dell `systemctl --user list-units 'tq-autopilot@*'`; `git grep -n assigned_only origin/main -- scripts` in `108-agent-queue`.

| Where | Unit | State |
|---|---|---|
| Studio | LaunchAgent `com.108plaza.tq-autopilot.gemini` | `launchctl disable` |
| Dell | `tq-autopilot@dell01-03` | `systemctl --user mask` (`disable` is not enough: dell03 restarted 12 s after stop) |
| MacBook | `gemini/auto-macbook01-04` | stopped by the owner |

It may return only in dispatch-only mode (takes only tickets pinned `assign:gemini/auto-<id>` exactly). Queue side merged at `108-agent-queue` `9766ada`. Turning the fleet on or off belongs to the owner.

## Accounts and quota

measured: as recorded in `CLAUDE.md` § 🎛 and § 🔁 Watch loops (2026-10-17).
Re-measure: agy `/usage` in any session (names the account and both model groups); `grep -h 'authenticated successfully as' ~/.gemini/antigravity-cli/cli.log` on a machine (never open the token files); `gh auth status` and `gh api rate_limit --jq .resources.core` for GitHub.

| Account | Used by | Notes |
|---|---|---|
| agy `yutjan50` | Dell | Quota is per account, per model group (Gemini vs Claude/GPT), shared by every machine on that account. |
| agy `xc.team.th` | Mac Studio + Mac mini | same |
| agy `ibrowe108` | Warut's MacBook | same |
| GitHub `ibrowe108` | Dell's `gh` and git (since 2026-10-17) | Org member, Write; owner's second seat replacing UTD888. Own 5,000/h REST quota. Switch back with `gh auth switch -u yuthstyle88`. Added with `~/gh-add-user.sh` because Dell's keyring hangs `gh auth login`. |
| GitHub `yuthstyle88` | every other machine | One 5,000/h REST quota shared by the whole fleet. |

Model per session: a restarted agy opens on the model in `settings.json`, and `/model` rewrites that default (the last switch on a machine wins). On 2026-10-16 Dell `gemini-4..6` went to Flash for mechanical work and `gemini-1..3` stayed on Argon; on 2026-10-17 both model tables were found stale (Dell `gemini-4..6` and Mac mini `agy-3..4` were not on the model recorded). Always read the pane.

## Lanes and controllers

measured: as recorded in `CLAUDE.md` § Lanes and dispatch (last changed 2026-10-17, `dc24675`). This table is to be replaced by the queue's own register when `108-agent-queue#955` (`POST/GET /v1/lanes`) lands.
Re-measure: the lane's notice issue (e.g. `xchange#564`) for the latest controller announcement; `GET $TQ/v1/lanes` once it exists.

| Lane | Default implementer | Controller (Claude) handles only |
|---|---|---|
| **pos** | Claude + Gemini | all `pos108-*` |
| **heros** | first come, first served (ordered 2026-09-09) | `jh-api` · `108heros-web` · `108heros-flutter` · legacy 108jobs-line repos |
| **park** | **Gemini** | `park108` · `esp32-io-node` (door board firmware for park108#813; owner 2026-10-01: *"Put it in the park lane"* (`9cc19f1`)) |
| **sell** | first come, first served | `108-sell` (formerly `pos108-sell`; owner renamed it 2026-09-21: *"Because it sells every product we have"* (`c1e8151`)). **Its own lane, not pos's**, because the storefront sells every product, not just POS. Controller not yet assigned; the owner orders per round. |
| **broker** | **Gemini** (owner 2026-10-07: *"Switch dispatch to Gemini, and tell every session"* (`53b7e73`)) · review: the controller `claude/4a6b8284` and the Claude sessions it dispatches (the MacBook sessions titled "Broker coding" and "Broker system review" (`3480dfb`), plus its fork) | `Broker-Platform`: central broker/referral system for every 108 product (owner 2026-10-07: *"You are this lane's controller"* (`3480dfb`)). Controller `claude/4a6b8284` (MacBook session titled "AG broker system"; owner 2026-10-15: *"Come back and control the broker lane again"* (`9b9efc8`), approved for the rules the same day; took back over from `claude/eb72d565`, which held it 2026-10-09 → 10-15). Design `docs/design/broker-platform.md`. |
| **xchange** | **Gemini** (owner 2026-10-07: new implementation work goes to Gemini) | `xchange`: currency-exchange desk v3. Controller `claude/5edf7bb5` (MacBook session continuing "AG xchange" after the account switch; owner 2026-10-10: *"Continue AG xchange"*, approved for the rules the same day: *"Go with what you proposed"* (`7b24540`); took over from `claude/608dff`). |
| **recognize** (under xchange) | **Gemini** (same as xchange) | `Recognize-Platform`: the AI document-reader service (passport MRZ first; design `docs/design/ai-reader.md`, ticket #150 and its child tickets A0–A13). Controller = **the xchange BE controller, `claude/1656900d`** (owner 2026-10-16: *"Do what you proposed"*, on the proposal that the only consumer is `xchange#542`; approved for the rules the same day: *"You can add it"* (`cbdeb0e`)). Deploy on do-sgp1, secrets and the public name stay with the owner. The queue syncs only repos listed in `config.toml` on Dell; check that `Recognize-Platform` is there before releasing a ticket. |
| **bank** | **Gemini** on Mac Studio (Dell is usually overloaded) | `bank-bot` · `ScreenLink` (ESP32 finger firmware + config page; its engine now lives in bank-bot). Controller `claude/20daac6e` (MacBook session titled "Survey and continue the Screen Link work"; owner 2026-10-14: *"You look after the Bank Bot + Screen Link work"*, approved for the rules the same day: *"Go ahead and add the bank lane to the rules table"* (`2244396`)). `ScreenLink` is not in the tq queue ⇒ dispatch directly, no claim. Real transfers, DB migrations, deploy and secrets stay with the owner. |
| **payment** | **Gemini**: `class:mechanical` to a Flash session (Mac mini `agy-1..5`), `class:logic`/`guarded` to Argon (Dell `gemini-1..6`, Studio `agy-1..10`). **Measure the pane before dispatching**: both model tables were stale on 2026-10-17. | `Payment-Platform`: the payment gateway service (SCB · KBank · 2C2P · Beam; Beam payment links are design `docs/design/beam-payment-link.md`). Controller `claude/35b9e3f8` (owner 2026-10-17: *"Go ahead and control the Payment-Platform lane"*, approved for the rules the same day: *"Add the payment lane to the rules table"* (`dc24675`)). **The only repo in the fleet with `cargo audit (dependency CVEs)` as a required context** ⇒ a new advisory turns every PR here `BLOCKED` with no PR at fault (2026-10-17: 9 vulnerabilities, fixed by #170/PR 171; the fleet-wide picture is `108-Ting-Ecosystem#236`). `strict = false` ⇒ the merge-base check is the only guard. Real money moves through this service: migrations, provider keys and deploy stay with the owner. |
| **168pay** | **Gemini**: `class:mechanical` to Flash, `class:logic`/`guarded` to Argon. Pick workers by name, not `"worker":"auto"` (on 2026-10-21 `auto` picked `gemini/jam-1`, whose pane sat at agy's first-run folder-trust prompt). | `108-Plaza/168pay` (moved from `yuthstyle88/168pay` 2026-10-21): merchant payment gateway, Next.js dashboard + Rust/Axum/Postgres API. Controller `claude/68bb0e3f` (owner 2026-10-21: *"https://github.com/yuthstyle88/168pay คุณคุมงานเลนนี้"*; decisions on `168pay#1`: real gateway, the Rust API is the only backend, migration `0002` hashed keys approved). Registered in `GET /v1/lanes` as lane `168pay`. Real money is the goal: provider keys and deploy stay with the owner. |

Repos with no lane owner (ask the owner before dispatching, unless the owner sent the work directly): `108-platform-services` · `108-agent-queue` · media/livechat/tixtox.

Queue config: the repos the queue syncs are listed in `/home/yuth/108-agent-queue/config.toml` on Dell (**not in git**; only `config.toml.example` is).
Re-measure: `ssh Dell-server 'grep -A40 "^repos" /home/yuth/108-agent-queue/config.toml'`.

## Branch protection: `strict` per repo

measured: 2026-09-24T01:33Z (`claude-global-rules#3`), as recorded in `CLAUDE.md` § 🟢 merge.
Re-measure: `gh api repos/<slug>/branches/main/protection --jq .required_status_checks.strict`.

| `strict` | Repos |
|---|---|
| `true` | `park108` · `jh-api` · `108-agent-queue` |
| `false` | `pos108-core` · `pos108-store` · `pos108-admin` · `pos108-orders` · `108-sell` · `Payment-Platform` (from the lanes table, 2026-10-17) |

## Repos with the independent-review gate

measured: 2026-09-18, as recorded in `CLAUDE.md` § 3. Verdict format.
Re-measure: `gh api repos/108-Plaza/<repo>/contents/.github/workflows/independent-review.yml --jq .name` per repo.

| Has `.github/workflows/independent-review.yml` | Does not |
|---|---|
| `pos108-core` · `pos108-store` · `pos108-admin` · `pos108-orders` · `108-sell` (named `pos108-sell` when measured) · `pos108-terminal` · `park108` · `jh-api` | `108-agent-queue` · `108-platform-services` |

## Repos with the `ci:go` merge-turn label

measured: 2026-09-26/27, as recorded in `CLAUDE.md` § 🧹 More than 3 CI runs queued.
Re-measure: `gh api repos/108-Plaza/<repo>/contents/.github/workflows/ci.yml -H "Accept: application/vnd.github.raw" | grep -c ci:go`.

| Repo | `ci:go` | Where it landed |
|---|---|---|
| `108-agent-queue` | yes | #831 · PR 832 `a544b54`; mirror exemption #893 |
| `jh-api` | yes | #815 `5ba573e`; mirror exemption #946 |
| `pos108-core` | yes | #2273 · PR 2274 `de8c8c2` (2026-09-26); mirror exemption #2277 |
| `park108` · `pos108-admin` · `pos108-store` · `pos108-terminal` | no (count = 0) | — |

PR-run `concurrency` groups were put in place 2026-09-24 at `pos108-core#2192` · `108-agent-queue#809` · `pos108-terminal#720` · `jh-api` following `#797`.

## CI runners

measured: as recorded in `CLAUDE.md` § ⚙️ CI runner (Lenovo runners added 2026-09-27, owner: *"Add the Lenovo runners too"* (`d4e67d7`); Lenovo off since 2026-10-09).
Re-measure: `gh api orgs/108-Plaza/actions/runners --jq '.runners[]|"\(.name)\t\([.labels[].name]|join(","))"'`; repo-level runners with `gh api repos/<slug>/actions/runners`.

| Pool | Runners | Labels |
|---|---|---|
| Linux — Dell `ibrowe.com` | `dell-org-108plaza` · `dell-org-ci-1..4` | `self-hosted,Linux,X64,pos108-ci` (+`dell-org-ci`) |
| Linux — Lenovo | `lenovo-org-ci-1..2` | `self-hosted,Linux,X64` |
| macOS/ARM64 | `studio-org-1..6` · `mbp-org-1..2` · `macmini-org-1..2` · `108-Ting-Ecosystem-R2` | `self-hosted,macOS,ARM64` |
| macOS/ARM64 — Warut's MacBook | `warut-org-1..2` | `+ fast-mac`, `warut-mbp`; `warut-org-1` also `heavy-build` (owner added 2026-10-21, so it takes xchange `api` tests) |
| Windows | `lenovo-org-win-1` | `self-hosted,X64,Windows` |

- `ibrowe-pos108-2` is a **repo-level** runner of `pos108-core`; it does not appear in the org list.
- Lenovo's two Linux runners are a systemd service (`actions.runner.108-Plaza.lenovo-org-ci-{1,2}.service`, enabled + active) and recover when WSL comes up. ⚠️ Not resilient to a Windows reboot: Windows does not start WSL by itself, and the Task Scheduler entry (`wsl.exe -d Ubuntu-24.04 -e true` at logon) has not been made. Manage from cmd.exe: `wsl -u root -e bash -c "systemctl restart actions.runner.108-Plaza.lenovo-org-ci-1"`.
- Warut's runners read their PATH from `~/actions-runner-warut-org-N/.path`, not a shell profile; a new tool means editing that file plus `launchctl kickstart -k gui/$(id -u)/actions.runner.108-Plaza.warut-org-N`. Its `cargo-nextest`/`cargo-deny` are **newer than Studio's** ⇒ a job red only on `warut-org-*` ⇒ suspect the version first. It is a LaunchAgent (`svc.sh`), so it takes jobs only while Warut is logged in and the machine is awake. `~/actions-runner` there is a runner for a personal repo; do not touch it.
- The `pos108-ci` label exists only on Dell.
- `macmini-org-2` was added 2026-10-20 (owner: *"ทำตามที่เสนอ"* (do as proposed), on the proposal of a second runner for the Mac mini's spare room). It is a copy of `macmini-org-1`: `~/actions-runner-org-macmini-2`, runner 2.337.0, the same labels (`+ fast-mac`), group `108-Ting-Ecosystem`, the same `.env`/`.path`. Verified on a real job: xchange `changes` Succeeded 08:03–08:04:57Z. Off by default like every runner.
- **Linux has only Dell** (4 runners, cap 4) while the Lenovo is off: on 2026-10-20 `ssh pos108-lenovo` timed out and `lenovo-org-win-1` was offline. Every Mac is ARM64, so none can take `Linux, X64` jobs.

Hosted-runner billing: measured 2026-10-17 from `gh api "/organizations/108-Plaza/settings/billing/usage?year=<y>&month=<m>"`: October used **108 hosted Linux minutes, net $0.00** (inside the included allowance), the last on 2026-10-14. On 2026-09-20 a `windows-latest` job had died on a billing block.

## Build machines

measured: as recorded in `CLAUDE.md` § 🖥 Big builds (owner 2026-09-27: *"Send part of the work to Lenovo too"*; Lenovo off since 2026-10-09).
Re-measure: `ssh macstudio 'df -h /System/Volumes/Data | tail -1; uptime'` and `ssh macstudio 'ssh pos108-lenovo "bash -s"' <<< 'df -h /; uptime'`.

| Machine | Suited for |
|---|---|
| **Mac Studio** (20 cores · 128 GB) | Whole-workspace `cargo build/test/clippy` for `pos108-*`, `jh-api`, `park108`, `108-platform-services`; anything needing macOS/arm64 (Xcode, bundle, Apple-bound code). Tailscale `macstudio` (100.84.133.23); `macstudio-lan` works only on the same LAN. |
| **Lenovo** (WSL2 · i9 16 threads · 62 GB · 1 TB) | The idle-disk choice for heavy Rust **when it is on**. Has the Rust toolchain, node 24, cmake, docker, psql, systemd; re-measure versions when it comes back. |
| **MacBook** | A few crates at a time. |
| **Mac mini** (`Mac-mini-khxng-ai-01` · 100.100.204.107) | `park108` model measurement only: the models and the 244-image plate set live there and must never leave it (PDPA). Worktrees under `~/park108-src/.worktrees/`. |
| **Warut's MacBook** (`warut-mbp`) | Not a fleet machine: no build work without the owner's order. |
| **Dell** | Never a worker's local build or test: it is the only Linux CI machine while Lenovo is off. A Linux-only build that truly must run there: `CARGO_BUILD_JOBS=8`, nothing else heavy at once (`e541b83`). |

Folder layouts differ; never copy a path between machines. Studio: `~/108-Ting-Ecosystem/Commerce-Platform/pos108/{core,terminal}`, `JH-Platform/Api`, `parking/park108`. MacBook: `pos/`, `heros/`, `parking/`.

## Rust toolchain

measured: 2026-10-17, as recorded in `CLAUDE.md` § 🖥 Big builds (owner 2026-10-17: *"That is, pin it to a version but keep it working"* · *"Because a fixed version won't break"* · *"But it must be the same number everywhere"* (`0f859df`)).
Re-measure: `rustc --version` on each machine; in each repo `cat rust-toolchain.toml` and `grep -rn "rust-toolchain@" .github/workflows`.

| Item | Value |
|---|---|
| Fleet pin | **`1.99.1`** (rustc/cargo 1.99.1 on the MacBook, Mac Studio and Dell) |
| Install | `rustup toolchain install 1.99.1 --profile minimal -c clippy -c rustfmt` |
| Exception | `heros/api`'s fmt **step** uses nightly (`.rustfmt.toml` uses `imports_granularity`, `group_imports`) with `RUSTFMT` pinned to the nightly binary |

Not yet following the pin (measured 2026-10-17):

| Repo | State |
|---|---|
| `pos/core` · `pos/terminal` · `heros/api` · `platform/services` · `platform/media` · `pos/livechat` | `channel = "stable"` |
| `parking` | pinned to a **different** number, `1.98.0` (install `1.98.0` as well until fixed) |
| `pos/agent-queue` | no toolchain file |
| CI | `@stable` in core/terminal/media; `@master` in `heros/api` |

## Dell disk layout

measured: 2026-09-19, as recorded in `CLAUDE.md` § 💽 (owner 2026-09-19: *"Move actions-runner to /data"* · *"From now on, create worktrees in /data"* (`611d3cc`)).
Re-measure: `ssh Dell-server 'df -h /home /data'`.

| Item | Location |
|---|---|
| Worktree created on Dell | **`/data/yuth/worktrees/<slug>`** (exists, writable, no sudo needed) |
| `target/` kept across runs on purpose | `/data/yuth/target-<slug>` |
| GitHub runner `_work` | `/data/actions-runners/<runner>` (moved with sudo, symlinked back to `/home/yuth/<runner>`) |
| Old `tq train` crontab backup | `~/108mon/crontab.backup.20260915-tqtrain.txt` |

Sizes on 2026-09-19: `/home` nvme **1.8 TB** (100% full that day, 14 GB left); `/data` **6 TB** (3.7 TB free). `target/` 148 folders, **709 GB**; `scratch/` 275 GB; `worktrees/` 168 GB; runner `_work` ~300 GB. `/home/koey` (260 GB) belongs to another user, not the fleet.

## Sweeper and leftovers

measured: 2026-09-27/28 and 2026-10-11/14, as recorded in `CLAUDE.md` § 🧹 Clean up.
Re-measure: `docker ps -a --format '{{.Names}}\t{{.Status}}' | wc -l` and `docker system df` per machine.

| Item | State |
|---|---|
| `108-Ting-Ecosystem/scripts/fleet-sweep.sh` | Runs every 6 h on Mac Studio (LaunchAgent) and Lenovo (cron). Since PR 226 (2026-10-14) it also removes unlabelled running test containers up ≥48 h (see the rule for the full condition). |
| 2026-09-27 | Studio: 118 containers (5 running), 440 volumes, 63 GB dead. Dell: 991 images (57.7 GB unused), 206 dead volumes (41 GB). Deleted the same day on the owner's order. |
| 2026-09-28 | One review session's targets on Studio ~260 GB; one target 144 GB (`incremental` 84 + `deps` 60). |
| 2026-10-11 | Dell held 95 unlabelled test containers 2–17 days old, swap full. |

## Repo name aliases (redirects)

measured: as recorded in `CLAUDE.md` § Merged Branch Auto-Cleanup and § 🏷.
Re-measure: `gh api repos/<slug> --jq .full_name`.

| Old name | Resolves to |
|---|---|
| `108-Plaza/api-108jobs` | `jh-api` |
| `yuthstyle88/fast-work-new` | `jh-api-dev` |
| `yuthstyle88/108jobs-clean` | `108jobs-web-dev` |
| `yuthstyle88/108jobs-flutter` | `108heros-flutter-dev` |

Archived repos skipped by branch cleanup: `Notification-Platform` · `Loyalty-Platform`.
