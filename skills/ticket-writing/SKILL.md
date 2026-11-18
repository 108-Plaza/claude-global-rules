---
name: ticket-writing
description: >-
  How to write a ticket an implementer can finish without asking: the 10-part ticket, the class diagram that must exist first, the behaviour table and up-front failing tests, the `## File scope` block the queue locks, entering the queue, and fixing at the root cause. Use when writing, splitting, reviewing or releasing a ticket or a design doc, when a ticket is found unclear, or when found work must become a ticket.
---

# Writing tickets

> Moved from `~/.claude/CLAUDE.md` at `ee7b381` (slimming step 2). Text is unchanged except: translated into English
> (each owner quote keeps the commit that first added the original), and infra-state tables replaced by pointers to `FLEET.md`.
> Since step 4 (2026-10-19) this skill is the source of truth; `CLAUDE.md` keeps only a headline summary that points here. Edit the rule here, and the summary only if a headline changes.

## 📋 Found work = open a ticket · don't take it yourself · review after it closes

Owner's order 2026-09-01 / 2026-09-03 — the default destination of a ticket is an implementer (not a Claude subagent and not Claude itself).
This is a global rule: any session that finds work follows this immediately, without waiting to be told again.

1. **Found work/bug → search for duplicates first** (`gh issue list --state all --search "<keywords>"` — including closed tickets) →
   **open the ticket in the repo where the PR will merge**, using the format below (`Fixes #N` only closes tickets in the same repo)
2. **Then stop** and report which ticket you opened · you may fix it yourself only as allowed by "When Claude may write code"
3. 🔴 **Ticket closed = start reviewing**, not the end of the work — including tickets you neither filed nor worked on (tickets you did not open = read + add comments/open follow-up tickets, do not issue a `Verdict:` — see section 2. Review)

Exceptions: something you broke yourself on a branch that is not merged yet · a typo in code you are currently typing
· Applies to **every agent**, including an implementer who finds a bug while working a ticket — open a ticket into the queue; never fix it yourself outside the ticket you hold

## 📐 Class diagram before code, always — the blueprint is what makes parallel dispatch possible

Owner's order 2026-09-22 *"Make it a central rule that work must have a class diagram before the source code is implemented"* (`a68e734`) ·
*"Without a class diagram it is certainly slow, because each piece waits for the one before it to finish · with a class diagram nothing has to wait"* (`a68e734`)
(builds on 2026-09-18 *"Dispatch the design work first … but the document must be reviewed first"* (`a68e734`))

🔴 **Never add `ready` to a code-writing ticket until the part it touches has a merged class diagram in the repo** — the ticket must cite class/module names from that diagram

🔴 **The class diagram is designed by Claude (that lane's controller) from the owner's requirements** — owner's order 2026-09-22
*"Claude is the one who designs the class diagram, from the owner's requirements"* (`82dcf2f`) · implementers (Gemini, or a Claude holding a ticket)
**do not design diagrams** — they follow the diagram · requirements unclear ⇒ the designer asks the owner before drawing (🔬 Blocked on an owner decision), not guess and draw

```
1. class diagram (+ a contract doc if it binds to something outside)  → review → merge
2. the queue controller splits tickets by the classes in the diagram — one class set per ticket, no overlapping files
3. every child ticket goes `ready` at once → written in parallel → review → merge
```

**Why:** tickets split by symptom run into the same file, because nobody decided which piece lives in which file ⇒ the queue locks the file for one ticket at a time
⇒ **the later ticket must wait for the earlier one to merge** · if the diagram has already decided the seams (types · signatures · files), tickets for different classes do not wait for each other,
and implementers who cannot see each other's work do not have to guess names (*"Don't write duplicates; grep first"* is not enough — grep cannot find what nobody has written yet)

**The diagram must have** — `docs/design/<area>.md` in the repo where the PR will merge · mermaid `classDiagram`:
- every class/struct/trait/module the ticket will touch or create, with the fields and methods that cross tickets (name + type)
- 🔴 **the file each class lives in** — two classes that different tickets will touch **must not be in the same file**
- relationships: who creates/who calls/who owns (arrows) + a "who provides, who uses" table
- a fallback if the provider has not landed yet — the consuming ticket declares a stub matching the diagram's signature in its own file + a comment that it will move
  **never just wait, never touch another ticket's files**
- 🔴 **Touches the database (table · column · constraint · default · new status value) ⇒ must have a "data migration" section**
  — owner's order 2026-09-27 *"A doc about changing or adding to the database must include a data migration, because the data has to be migrated"* (`9b2e8de`)
  · applies to both design docs and tickets with a migration · answer all of:
  (1) what each kind of existing row looks like after the migration (gets the default? becomes NULL? violates the new rule?)
  (2) is a backfill needed — if not, say why (e.g. code handles it lazily) · if yes ⇒ the SQL used + a `count(*)` command measuring the affected rows before deploy
  (3) deploy order (migration before/after the new binary) and whether the old binary still works with the new schema
  (4) what `down` loses
  · a reviewer of a design/ticket that touches the database but **lacks this section = FAIL** · the backfill itself is still Data Risk and still needs the owner's approval

- **One file that many tickets must touch = the diagram is not finished** ⇒ the first ticket splits that file per the diagram (pure code move) —
  not adding workers and not ordering tickets one by one with `blocked by #N` (that is a stopgap per 🧩 Two pieces of work conflict)
- 🔴 An implementer who finds the diagram's shape unworkable ⇒ **comments on the ticket and stops; never changes it themselves**, because other tickets are written against that shape ·
  the queue controller fixes the diagram via PR (review → merge), then releases work again
- 🔴 **Review between every step** — an unreviewed diagram/doc is a guess that looks like a fact, and it flows into every child ticket with nobody re-checking ·
  a code reviewer can only confirm *"the code matches the ticket"*, not *"it matches the real thing outside"*
- **Exception (no new diagram needed):** a change within one file that **adds/changes no** types, public signatures or files · pure docs/config —
  but if the repo already has a diagram, the ticket must still cite the classes it touches

Evidence: 2026-09-22 `108-agent-queue` had 5 `ready` tickets that could not be dispatched while Gemini workers sat idle, because they collided on three files
(`src/lua/claim.lua` ×3 · `src/sync/run.rs` ×2 · `scripts/tq-autopilot.sh` ×2) · 2026-09-18 `park108` split three tickets by file but did not design the seams
⇒ the `BillFacts`/`Mode` contract had to be sent afterwards, and an unreviewed bank contract doc led the code to guess the response shape wrong (the bank answered 400)

## 🧪 A ticket for an implementer = diagram + behaviour table + failing tests the ticket author writes first

Owner's order 2026-10-03 *"Make it a rule too; it may help other agents as well"* (`17f69a1`) · applies to implementers of **every kind** (Gemini, or a Claude holding a ticket)

| Layer | What it says | What it prevents |
|---|---|---|
| **1. class diagram** (📐 Class diagram before code) | what to write, in which file, with which signature | wrong placement · guessed names · colliding with another ticket's files |
| **2. behaviour table in the ticket** | "existing behaviour that must be kept" + "case → required result" | silently changing meaning while the signatures are right |
| **3. failing tests the ticket author writes first** | locks item 2 in as code | implementer claiming "kept the existing behaviour" when it did not |

- 🔴 **A diagram alone is not enough** — the diagram makes code land **in the right place** · the behaviour table and tests make it **mean the right thing**
- **Procedure:** the ticket author branches from `origin/main` → commits failing tests (failing on wrong results, not on compile errors, where possible) → pushes →
  the ticket names the branch + test names, and 🔴 **carries the machine-read line `Test branch: test/<n>` on a line of its own** (108-agent-queue reads it since #1095 and writes "branch from test/<n>" into the dispatch order; without it the order says "branch from main" and contradicts the ticket — happened to #1105/#1107 on 2026-10-21) · the implementer makes them pass and may add tests, but 🔴 **must not edit/delete/weaken the provided tests**
- **Reviewer:** `git diff <test-commit>..<head> -- <test-file>` must not touch the provided tests · touched ⇒ **FAIL**
- Dependency not landed yet (tests cannot compile yet) ⇒ write the tests once the dependency merges, **before** dispatching the ticket · a ticket with no behaviour to lock (pure file move · docs) ⇒ write in the ticket "no tests up front — intentional, because …"
- ⚠️ **Cost:** the ticket author writes extra tests · wrongly written tests lead the implementer astray ⇒ up-front tests must pass review together with the ticket
- 🟢 **Small tickets are exempt from layer 3** (owner's order 2026-10-12, chosen to cut the up-front-test bottleneck: 95 xchange tickets waited on tests/deps while ~17 Gemini sat idle) —
  a `class:mechanical` ticket, or any ticket whose diff stays inside one file with no new public signature, may be dispatched **without up-front tests**.
  The behaviour table (layer 2) is still required · the implementer writes the tests for each row · the **reviewer** checks every row has a test that goes red when the fix is reverted (the 2. Review mutation check) — missing ⇒ FAIL.
  `class:logic` / `class:guarded` tickets keep layer 3 unchanged.

Evidence 2026-10-03 `rust-project-backend#659`: the ticket named the file and function clearly and the code landed in the right place, but the implementer changed
`AuthService::change_password` from `is_ok()` to `!= Verified::Yes` ⇒ a correct password with an old-style hash (`YesUpgrade`) could no longer be changed, while it reported
"match the original behavior precisely" · every existing test stayed green because none covered that case, and every signature was right ⇒ **the diagram could not catch it**

## Entering the queue

Add labels `ready` + `class:mechanical|logic|guarded` (+ `p0` if urgent · + `assign:<kind>` to name a specific worker)
⇒ the queue picks it up within ≤60 seconds · the ticket must have a `## File scope` heading the queue can parse (`108-agent-queue/src/sync/parse/scope.rs:27` accepts `file scope` · `file_scope` · and the legacy Thai heading) · without it, scope `**` collides with every ticket (🧱 … is the fleet-wide file lock)

## 1. The 10-part ticket — must be workable without this conversation

The implementer reads only the ticket — not this conversation, not other repos · first line `> dispatched-by: <kind>/<session-id>`

1. **Symptom** — what happens to the user/system, not a function name
2. **Evidence** — `file:line` + **sha of the `main` checked** + the command that produced it + the chain to the root cause
3. **Fix location** — files and approach, pointing at **the root-cause site**
4. 🔴 **Done criteria** — machine-decidable (command + required result) + the CI gates that must be green (see 1a item 4)
5. 🔴 **File scope** — in the format the queue can parse (🧱 … is the fleet-wide file lock)
6. 🔴 **Do not touch** — the 4 BLOCK groups + never delete/skip existing tests
7. **Function structure** — cite classes from the diagram `docs/design/…` (📐 Class diagram before code — none ⇒ the ticket is not ready) · type/function names · which file/module · where it fits existing code (`file:line`)
8. **Input / Output** — types accepted · returned · possible errors and what is returned for each
9. **Edge cases** — as a list, with the correct behaviour for each
10. **Step-by-step** — 5–8 steps, one testable commit per step, ending with a command whose result can be seen

**Also required:** the repo where the PR will merge (`owner/repo`) · how to verify (real command + expected result + toolchain/rustfmt if constrained) ·
**decided vs open** (what the owner has decided = decided, never ask again · not yet decided = write "must stop and ask")

**Rules for parts 7–10 (ordered 2026-09-04 — mandatory for every ticket):**
- Proposed names **must cite real code** with `file:line` — a wrongly guessed signature is worse than none, because the implementer follows it without asking
- Prefix with **`[required]`** (wrong = the ticket is wrong · contracts others see: JSON fields · HTTP routes · columns) or
  **`[proposed]`** (internal shape · may change, but the reason must be written in the PR)
- Every edge case must have a test in the done criteria, or say *"no test yet — intentional, because …"* (no test yet — intentional, because …)
- If unknown, write **"waiting on #N"** (waiting on #N) / **"must ask the owner — do not guess"** (must ask the owner — do not guess) · a six-part ticket that is all true beats ten parts with four guessed
- **One ticket = one outcome** reviewable in one sitting · split big work into sub-tickets ordered with `blocked by #N`
- ⚠️ **Cost of this rule:** tickets get longer and take longer to write · **guessing structure wrong = leading the implementer wrong too** ⇒ the first two rules
  (cite real `file:line` · separate `[required]`/`[proposed]`) are what keep that cost from happening — **never skip them**

## 1a. "Tight and clear"

| Never write | Write instead |
|---|---|
| "make it better" · "handle errors properly" · "refactor to be clean" | a command whose result shows the difference |
| "as discussed" · "like in the other repo" | write it out in full |
| a bare file reference "in `lane.rs`" | `file:line` + sha (shas change, line numbers drift) |
| criteria that need a human to judge | criteria a machine judges |
| one ticket, two topics | split the ticket |
| "fix location" pointing at where the symptom shows | point at where the wrong thing is created + the chain |

**Before submitting every ticket:**
1. Re-check the evidence on the current `origin/main` — yesterday's ticket cites a dead sha
2. When a ticket is split off, the parent ticket does not narrow by itself — remove the moved criteria by hand
3. `gh pr list --json files` — if it collides, write in the ticket which ticket it waits for · never resolve a conflict by taking one side wholesale
4. 🔴 **State which CI gates will measure it, especially ratchets** (counters that must not rise — ask whether the number rises, not whether the code is correct) ·
   look at `.github/workflows/` + the scripts it calls (e.g. `scripts/hygiene/`) + baseline files · write into the done criteria which gate, and which file holds the ceiling
   · ways out, in order (always first fix it so it does not rise · raising the ceiling needs a per-item reason in the PR) · **a ticket that orders writing a transpile harness + mock injection must always warn about `any`**
   (cause: store#212/#213/#215 all three went red on `any_types`)

## 🧱 `## File scope` is the fleet-wide file lock

The `tq` queue takes the lines under this heading and **actually reserves those files** — one bad line and the whole repo stops dispatching, while workers only see `empty`
(incident 2026-09-14: a bare `tests/` in `pos108-core#1843` reserved the whole subtree and collided with p0 ticket `#1855` ⇒ the whole repo could not dispatch all day · after changing it to file names, work flowed within 19 seconds)

| Written like this | Result |
|---|---|
| path mid-sentence · preceded by a `-` bullet | **the queue cannot find it** ⇒ scope `**` collides with every ticket |
| several paths on one line separated by `·` | only the first is found; the rest are not reserved |
| `tests/` · `src/` (directories that already have content) | reserves the whole subtree, blocking every ticket under it |
| path with brackets `src/app/[locale]/(dashboard)/x.tsx` | **silently dropped** (`looks_like_path` in aq `src/sync.rs`) ⇒ not reserved; you must guard it against rebase yourself |
| a **new directory this ticket owns entirely** + a note that it "intentionally reserves the whole subtree" | ✅ correct (example `pos108-admin#678`) |

**Correct form:** a code block, one path per line at the start of the line, no trailing description (put descriptions outside the block)
```
src/a.rs
tests/a_test.rs
```
After adding `ready`, confirm the queue read it correctly: `ssh Dell-server "redis-cli -p 6381 HGET 'tq:t:<owner>/<repo>#<n>' scope_prefixes"`
— got `**` or incomplete = fix before releasing · the queue posts a warning but **does not prevent** a bad ticket from being dispatched (aq#332 closed not planned)

## 🌱 Fix the root cause, not the symptom

Owner's order 2026-09-11 *"Fix the root cause of the problem, not the far end, because otherwise it never ends"* (`c2ddf92`)
**Symptom site** = where the symptom is *seen* · **root cause** = where the wrong thing is *created* · fix the symptom site and the symptom goes away this round, but the creator keeps running

Examples already dispatched: the `pos108-core` bridge collided for a month; the root cause was the queue watching the `-dev` mirror (removed one line from `config.toml`) ·
workers got `empty` 400 times while tickets sat `ready`; the root cause was the lane gate (aq#227) · three tickets went red at `any_types`; the root cause was the ticket not warning about the ratchet gate

**Before fixing, answer three questions:**
1. **Where is the wrong thing created** — trace to the point that *writes/sends/decides* the wrong value, not the point that *reads/displays/checks* it · write the causal chain into the ticket/PR
2. **After fixing here, can the symptom come back?** (elsewhere · new data rows · the next PR · the next cron run) — yes = still the symptom site
3. **Does this root cause have other symptom sites?** — fixing the root cause closes every site at once

**Signs you are fixing the symptom site:** fixing the same thing a second time · fixing one item at a time (row/ticket/PR/machine/label) · making the **reader** tolerate bad values
(fallback · default · `unwrap_or` · filtering out) instead of fixing the **writer** · raising a ceiling/threshold · adding retry/sleep/timeout · special cases ·
`#[ignore]`/skip · cleaning bad data by hand while the creator still runs · editing generated files / the `*-dev` mirror / `kubectl set image` ·
closing a ticket with an explanation and nothing that prevents recurrence

**Root cause out of your hands** (another repo/lane · BLOCK · Data Risk · waiting on the owner) ⇒ a **stopgap** is allowed if all three hold:
(1) the PR/commit contains the word `stopgap` + what the root cause is (2) **open a ticket at the root cause before merging**, linked both ways
(3) the symptom ticket must not be closed as "fixed" — close it as a duplicate pointing to the root-cause ticket, or wait for the root-cause ticket to merge · fixing the symptom site silently = hiding the root cause

**Bad data:** fix the creator first, then clean up (cleanup/backfill is still Data Risk and must be asked)

**By role:** ticket author ⇒ "fix the root cause" = **open a ticket at the root cause, not do it yourself** · the *evidence* part has the causal chain · the *fix* part points at the root cause ·
never send a symptom-fixing ticket worded to look like a fix · if you can't trace it, write *"root cause unknown — this ticket is the investigation"* (root cause unknown — this ticket is the investigation) ·
implementer ⇒ if the ticket orders a symptom-site fix, write that on the ticket and go `blocked` + reason; don't fix it silently and don't expand beyond the ticket's file scope
· reviewer ⇒ a symptom-site fix without `stopgap` + a root-cause ticket = **FAIL**

This rule does not ask you to go slower — many root causes are one-line fixes · tracing is paid once, symptom fixes are paid every round

## ♻️ Several variants of one job = one shared core + a `dyn Trait` or generic per variant — never a copy per variant

Owner's order 2026-10-06 *"Make it a rule: for this kind of work, use a dyn trait or generics"* (`9d573e4`) ·
*"It has to be reusable"* (`9d573e4`) · *"Not building new copies over and over"* (`9d573e4`) · *"Because the logic is much the same"* (`9d573e4`) ·
*"Payments have many providers"* (`9d573e4`) · *"We use a trait, loaded dynamically"* (`9d573e4`) · *"There will be shared central logic"* (`9d573e4`)

**"This kind of work"** = the same job done for several interchangeable things, where more will come:
payment providers · banks · notification channels · printers/hardware drivers · OCR/LPR engines · storage backends ·
the same admin screen needed by several apps

| Part | Where it lives | Written |
|---|---|---|
| What is the same for every variant (routes · auth · validation flow · masking · audit · storage · the screen) | **one central place** | once |
| What differs (field list · names · mapping · that variant's own rules) | behind a trait — `Arc<dyn Trait>` when the variant is chosen at runtime (per merchant · per config · per request), a generic `T: Trait` when it is fixed at compile time | one small file per variant |

- 🔴 **Adding a variant = adding one implementation file** — if it also needs a new route set, a new DTO pair, a new handler block
  or a new screen, the design is a copy, not a reuse ⇒ redesign before writing
- 🔴 **Before writing variant number two, look at variant number one** — if the new code would be the old code with the names changed,
  extract the shared core first (📐 Class diagram before code: the trait and the central type go in the diagram)
- **Safety-relevant logic goes in the core, never in the variant** (masking secrets · auth · money rounding · idempotency) —
  a variant that does not write it cannot get it wrong
- **UI too:** one component drawn from data the backend describes (field specs), embedded by every app that needs it —
  not one screen per app per variant
- Existing copies that others call (URLs · JSON shapes another repo depends on) keep their contract; re-point them at the shared core
  in a follow-up ticket rather than breaking the caller
- **Reviewer:** a PR that adds a per-variant copy where a shared core + trait was possible = **FAIL**, unless the PR says why
  the variants are not actually alike
- ⚠️ **Not a licence to abstract a single case** — one variant with no second in sight stays concrete; this rule fires when the
  second arrives or is already planned

Evidence 2026-10-06 `Payment-Platform`: credential storage and service were generic over the provider, but the HTTP layer was copied —
16 handlers + 4 DTOs + 2 mappers for SCB and KBank, nothing for 2C2P or Beam; a third copy for Beam was started and stopped
⇒ design `docs/design/provider-credential-specs.md` (`ProviderCredentialSpec` trait + one registry + one form)

## 🔍 Reuse only what keeps the same contract — "similar" is not "the same"

Owner, 2026-11-18: *"ผมตรวจพบว่า ai ได้ reuse object แต่ตัดสินใจผิดพลาดไป reuse object ที่ มีพฤติกรรม คล้ายกัน"* ·
*"ทำผิด มาตลอด เมื่อมีการเพิ่ม flow"* · *"transfer เราก็ทำถูก แต่ อย่าไป อิง ของเดิม"* · *"ใส่เป็นกฎใน ticket-writing กับ review-and-merge เลย"*

♻️ above says *build one shared core*. This rule says *what may go into it*. Agents decide to reuse from what looks alike
(name, field shape, most of the steps, tests pass) and never check what happens inside. The types match, so the compiler is silent.

**The test for reuse:** two callers may share an object only if **both would have to change together, for the same reason**.
If one could need a change the other must not get, they only look alike today. Sharing ties them together, so the next fix for one breaks the other.

**Before reusing an object, a flow, or a function for new work, fill this table:**

| Dimension | What the new work needs | What the candidate does |
|---|---|---|
| State it expects at the start (screen, session, lock, row status) | | |
| State it leaves at the end | | |
| Inputs and edge values (0, empty, negative, missing) | | |
| Output, rounding, units | | |
| Side effects (DB writes, events, outside calls, money moved) | | |
| Errors: raised, swallowed, defaulted | | |
| Idempotency and retry | | |
| Permissions and tenant | | |
| Who owns its rules, and why it would change | | |

- **Every row matches ⇒ reuse.**
- **Any row differs ⇒ do not reuse it as it is.** Either write a separate object, or move only the rows that are the same into ♻️'s core and put the differing rows behind a trait.
- 🔴 **Never add a flag, a parameter or an `if` to the candidate so it fits the new caller.** That is the plainest sign the wrong object was picked. Every existing caller now runs through the new branch.
- 🔴 **Adding a new flow ⇒ write it from what it needs, never by copying or trimming an existing flow.** Reuse the parts beneath it whose contract really is the same (recorded buttons, one screen-unlock step, a popups list). Flows differ in where they start and where they end, and a copy inherits both.
- **Make the code say it:** when two objects look alike, put a doc comment on each saying what it is for **and what it is not for, and why** (`/// Not for transfers: ends with the phone locked`).
  Name by meaning, not shape (`RefundAmount`, not `Amount`). Use newtypes (§ 🦀) so passing the wrong one does not compile.
- **The new caller has its own tests** for the rows of the table that matter to it, and they must be able to go red. Tests of the reused object only prove it does what it always did, not that this is what the new caller needs.

**The ticket author:**
- When the area already has a similar object, the ticket says which way to go: *"reuse `X`: the table matches"* or *"do not use `X`, because <row>"*. Never leave it for the implementer to guess.
- When the owner has rejected a reuse, write the decision and its reason in the design doc (🧭 in CLAUDE.md), so the next session does not propose it again.

**The implementer:** a PR that reuses something in a new place carries a section `Reuse:`. It names what is reused and gives the table, or one line per row that could differ.

Evidence 2026-11-18, bank-bot K BIZ:
- Each time a K BIZ flow was added, the agent derived it from `bank-901/login`. First it proposed cutting the login's `recents → close_all` rows so K BIZ would stay open for the transfer. Then it proposed a login copy for login-then-transfer.
- Both were wrong. The login job ends locked (`rig_program_build.rs`, `build_scan_jobs`, `lock_at_end: true`). A transfer never follows a login inside one order (bank-bot#728). Transfer rows 1–2 expect the home screen.
- So the start and end states differ, the two rows of the table nobody filled in. The owner's ruling, with these three reasons, is `docs/design/kbiz-transfer-approval.md` §4d (bank-bot PR 1051).
- What the two flows really share is a layer below the flows: the recorded buttons under `bank-901`, `bank-901/popups` and `main/unlock`.

## 🦀 Rust: let the compiler catch the mistake, not shorter code

Owner, 2026-11-16: *"เราควรปรับปรุงไหม เพื่อ ให้ โค้ดสั้นลง"* · *"ความผิดพลาดจะได้น้อย ลง"* (should we shorten the code, so there are fewer mistakes).
Shorter code is not the goal. The goal is a compiler error at the place a mistake would otherwise slip through.
These rules apply to **new code and code a ticket already touches**. They are not a reason to sweep existing code: a sweep with no failure seen is over-design (owner 2026-11-15).

| Write | Instead of | What the compiler then catches |
|---|---|---|
| `match` on our own enum with every variant named | a `_ =>` arm | a new variant forces every `match` to handle it |
| an enum for a closed set of states | `bool` flags or string states | impossible combinations and typos |
| newtypes for money and ids (`Satang(i64)`, `TenantId(Uuid)`) | bare `i64` / `Uuid` / `String` in a signature | arguments passed in the wrong order, units mixed up |
| `#[must_use]` on functions whose result must be checked | a result the caller can drop silently | a forgotten check |

- `_ =>` stays fine for foreign `#[non_exhaustive]` enums, integers and strings.
- **Choosing enum vs `dyn` vs generic:** a closed set that only we extend ⇒ enum + `match`. An open set of variants (providers, banks, channels, drivers) ⇒ ♻️ above, `Arc<dyn Trait>` or a generic, because an enum would make every new variant edit one central file that every ticket then reserves.
- **`#[async_trait]` stays on any trait used as `dyn`.** Native `async fn` and `-> impl Trait` in a trait (RPITIT, 1.75) make the trait not dyn compatible (E0038). Use them only on traits that are generic-only, and when the future must be `Send` write `-> impl Future<Output = T> + Send` (callers cannot add `Send` themselves: return type notation is still unstable as of rustc 1.99.1).
- Trait upcasting (1.86) means `trait X: Any` replaces a hand-written `fn as_any(&self) -> &dyn Any`.
  It also turns `&dyn Sub` into `&dyn Super` directly (`trait Sub: Super`), so a hand-written `fn as_super(&self) -> &dyn Super` is not needed either.
- **A closed enum with many trait methods:** `enum_dispatch` generates the forwarding `match` for every method, so you do not hand-write one `match` per method. It is still a closed set: a new variant edits the central enum. For an open set, use ♻️ (`Arc<dyn Trait>`).
- **An open set (`dyn`) whose methods return an iterator or a future, where the box is measured to cost something:** split it into a generic-only trait with RPITIT or native `async fn`, plus a dyn-safe "erased" trait with a blanket impl that boxes the result for `Arc<dyn …>` callers. With no measured cost, keep `#[async_trait]` / `Box<dyn Iterator>`; the split is two traits to keep in step.
- `derive_more` is fine for the boilerplate the newtypes row creates (`Display`, `From`, `Deref` on a newtype). Derive only what a caller uses: a derived `From` or `Deref` reopens the very mix-ups the newtype was there to stop.

Measured 2026-11-16 on `origin/main` of six Rust repos (pos108-core, 108-agent-queue, 108-platform-services, Media-Platform, Payment-Platform, park108): 66 of 78 `#[async_trait]` traits are used as `dyn`, there are 0 `fn as_any`, and there is 1 `-> Box<dyn Iterator`. Rewriting to newer syntax would save almost nothing.
