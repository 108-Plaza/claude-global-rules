---
name: software-design
description: >-
  How to design code so it is reused, not copied: survey what exists, design the class diagram around one shared core and one
  seam per set of variants, pick the right shape (enum + one table for a closed set, a trait + Fake for an outside engine, rows
  for admin-added things), extract one helper instead of a new copy, and never abstract for a single case. Use when designing
  a class diagram or design doc, and before writing or reviewing code that adds a function, a type, a query, an `if`/`match`
  on a variant, or something that looks like code already written.
---

# Software design: reuse, not copies

Owner, 2026-11-25 (jh-api, JH-API session): *"งานได้ reuse object ไหม"* · *"มันแค่แยก หน้า ที่ แต่มัน reuse ได้ เพราะ พฤติกรรม คล้าย ๆ กัน"* ·
*"source code ต้องมีคุณภาพไม่ขยะ ไม่ซับซ้อน"* · *"ควร เอา skill reuse object มาใช้"* · *"ไม่ง้ันผมก็ต้องมานั่งบอก เสีย refactor"* · *"skill การออกแบบไง"* · *"พวก design pattern มันต้องมี สิ"*

**Why this exists:** code written without a survey adds the 15th copy of something, and every copy later costs a refactor.
The owner had to point this out by hand. Measured that day, on jh-api `main` `3a0dc02`:
- 14 inline `FOR UPDATE` reads of the trip row and 11 of its dispatch row, with no shared lock function;
- 9 inline copies of the "not yet picked up" status list;
- 88 decisions on `ServiceType` (Ride vs Delivery) in 37 files, though both services run the same trip flow;
- a fix I was writing would have added the 15th lock copy and put a decision inside a DB function.

This skill holds for **every writer and every reviewer**, in every repo. The ♻️ rule in `CLAUDE.md` and skill `ticket-writing` § ♻️ are the ticket author's side of the same idea.

## 0. Design first: the class diagram decides reuse

Reuse is a design decision, made in the class diagram (skill `ticket-writing` § 📐), not something a reviewer finds afterwards.
A design doc for code that has several variants, or that repeats something already in the repo, must contain:
1. **The survey** (§1): what already exists, with counts and `file:line`.
2. **The shared core**: the classes or functions every variant goes through, drawn once.
3. **The seam**: where each per-variant difference lives, in the shape §3 picks, with a table of every difference (value, yes/no, or real algorithm).
4. **What is reused** as is, and the **one helper** added for each repeated piece (§2), with the file it lives in.
5. **Migration of old copies**: which existing copies move onto the core or seam, split into tickets by file so they can run in parallel.

A diagram that draws a second copy of an existing flow, or leaves `if variant ==` checks in the callers, is not finished.

## 1. Survey before you write (every new function, type, query or variant check)

1. Name the concept, then grep for it under **several names** (the noun, the verb, the status names, the column, the error).
   `grep` finds code; the repo's design docs and rules page (e.g. `docs/design/architecture-rules.md`) say where things belong. Read both.
2. **Count the copies.** Write the number down: `N places already do X (file:line …)`. Zero is an answer too, but it must be measured.
3. Check work in flight (open PRs, worktrees) for the same helper, so two sessions don't add it twice.

## 2. Reuse, or extract one helper

| What the survey found | Do |
|---|---|
| A function that already does it | Call it. Don't wrap it in a function that only forwards. |
| Copies of the same few lines, no shared function | Add **one** helper where the rules page says that kind of code goes, use it in **your** new code, and list the old copies (count + `file:line`) as a follow-up ticket. Don't make your copy number N+1. Don't migrate every old copy inside an unrelated fix. |
| A predicate written inline in several places (`matches!(status, A \| B \| C)`) | One named method on the type (`TripStatus::is_before_pickup()`), beside its siblings, with a test that the variants still split cleanly. |
| A decision (price, eligibility, state, validation) | A pure function in the rule module the repo uses (`*_rule.rs` in jh-api). It takes values, does no I/O, and has a test that needs no database. Handlers and DB functions call it; they don't re-decide. |

## 3. Pick the right shape for a set of variants

| The variants are… | Shape | Not |
|---|---|---|
| A closed set fixed by the domain, law or protocol (`ServiceType`, `TripStatus`, a legal vehicle kind) | **an enum**. Each per-variant table is written **once**, in its rule module or as methods on the enum, and callers ask it | `if x == Variant` scattered through handlers |
| Interchangeable outside engines or vendors (payment providers, banks, maps, push, face match) | **a trait + one real impl + one `Fake`**, injected as `Arc<dyn Trait>` (generic when fixed at compile time) | a copy of the flow per vendor |
| Things an admin adds (classes, options, zones, fares) | **rows + an API**; no code change | a `match` on a row's code |

Choosing `dyn` for a closed set, or an enum for vendors, is the wrong shape even when it compiles.

## 3a. Design patterns: name the pattern in the design

Every seam in a class diagram names the pattern it uses, so the reader knows the shape before reading code.
Use the standard pattern that fits; don't invent a new mechanism when one of these covers the case.

| Situation | Pattern | Rust shape | Fleet example |
|---|---|---|---|
| Several outside engines or vendors doing one job | **Strategy** (+ **Adapter** wrapping each vendor's API to our trait) | `trait` + one impl per vendor + `Fake`, held as `Arc<dyn Trait>` | jh-api `RoadRouter` (`logistics/src/routing/`) · bank-bot steps, one file per bank app |
| Picking the implementation by key at runtime | **Registry** (or **Factory**) | one central loader that maps a key to an `Arc<dyn Trait>`; adding a variant = one file + one registry line | bank-bot `load_bank` · steps loader (owner 11-23 *"ต้องมี ตัวโหลด กลาง"*) |
| One flow, a few steps differ per variant | **Template method** (shared core + hooks) | the core fn owns the order of steps and calls the seam for the steps that differ | Ride and Delivery: one trip flow, the service seam answers the differing steps |
| A closed set with per-variant values or yes/no answers | **Enum with a table** (table-driven design) | methods on the enum, or one `match` in the rule module returning constants or a small policy struct | `TripStatus::is_terminal()`, `is_passenger_aboard()` |
| A rule that decides eligibility, price or a transition | **Policy / Specification** | a pure fn in `*_rule.rs` taking values, tested without a DB | jh-api `wasted_trip_fee_rule::refusable_at_pickup` |
| Allowed status changes | **State machine** | one transition table (`can_transition_to`) every write asks, under a row lock | `RideSession::can_transition_to` |
| Reading and writing one entity | **Repository** | the entity's DB functions live in one `impls` module; callers never write SQL | jh-api `crates/db/src/impls/**` |
| A write spanning several statements | **Unit of work** | one function, one transaction: lock, re-check with the rule, write | jh-api architecture rules §A (S3) |
| Side effects after a state change (push, chat, webhook) | **Observer / domain event** | emit after commit; listeners never run inside the transaction | jh-api handler rule: push after the commit |
| A simple entry point over several steps a caller shouldn't sequence | **Facade** | one public fn that runs the steps; the steps stay private | `refuse_parcel_at_pickup` (cancel, fee, free the rider) |

Rules for using them:
- **A pattern needs a reason that exists today**: at least two variants, or a real outside engine to fake in tests. One case ⇒ plain function (§5).
- **One pattern per seam.** Stacking a factory on a strategy on a wrapper for one vendor is the complexity the owner bans.
- **Name it in the diagram and the PR** (`Seam: Strategy, trait OfferSearch, impls RideOfferSearch / DeliveryOfferSearch`), so the reviewer can check the shape against this table.

## 4. Two flows that behave alike share one core

When two variants differ only in role (a ride carries a person, a delivery carries a parcel), the flow is **one core**.
The differences sit in **one seam**: an enum table, a small policy struct or a trait, chosen by §3.
- A per-variant difference that is a value or a yes/no (`has_bill_check`, a config field, a copy key, a licence column) is a method returning a constant, not a branch at each call site.
- A real difference in algorithm (two offer-search strategies) is one function per variant behind the same seam, called from the shared core.
- A new variant must then be one entry in the seam, not edits to every file that branches today.

## 5. No speculative abstraction, no wrapper layers

- Build a seam only when a **second user exists now**. One caller ⇒ call the concrete thing.
- No layer whose only job is to forward to one other thing. No "kept in case we need it".
- Delete dead or duplicate code you touch rather than carrying it forward.
- Short and direct beats clever: the owner's bar is *"ไม่ขยะ ไม่ซับซ้อน"* (not junk, not complicated).

## 6. Say it in the PR, check it in review

**Author:** the PR body has a line `Reuse: <what was reused> · <helper added, if any> · <N old copies left, follow-up #…>` with the survey numbers from §1.
A PR that adds a function or a variant check without that line is not finished.

**Reviewer:** FAIL the PR when any of these hold:
- a new copy of logic that already exists (name the existing `file:line`);
- a new `if`/`match` on a variant outside that variant's seam;
- a decision placed in a handler or DB function instead of the rule module;
- the wrong shape per §3, or a seam whose pattern is not named or does not fit §3a;
- a wrapper or abstraction with a single user;
- no `Reuse:` line, or survey numbers that a re-run of the grep does not reproduce.
