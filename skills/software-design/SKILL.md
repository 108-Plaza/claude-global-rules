---
name: software-design
description: >-
  How to design code so it is reused, not copied, and stays simple: survey what already exists, model the change in UML
  adapted to Rust (Mermaid class, sequence, state and component diagrams that match the real code), choose the right shape
  and a named design pattern for each set of variants, keep one shared core with one seam when flows behave alike, add a
  helper instead of a copy, and never abstract for a single case. Use when designing a class diagram or design doc, before
  writing or reviewing code that adds a function, a type, a query or a branch on a variant, and when something looks like
  code already written.
---

# Software design: model it, reuse it, keep it simple

Owner, 2026-11-25 (jh-api, JH-API session): *"งานได้ reuse object ไหม"* · *"มันแค่แยก หน้า ที่ แต่มัน reuse ได้ เพราะ พฤติกรรม คล้าย ๆ กัน"* ·
*"source code ต้องมีคุณภาพไม่ขยะ ไม่ซับซ้อน"* · *"ไม่ง้ันผมก็ต้องมานั่งบอก เสีย refactor"* · *"พวก design pattern มันต้องมี สิ"* ·
*"แต่ผม อยากให้ เช่น UML"* · *"UML อาจไม่เหมือน กับเราก็ได้"* · *"หรืออาจเหมาะ เพราะ ใช้ AI"*. The owner gave the direction and expects the designer to work out the rest:
*"คิดก่อน"* · *"ผมแค่ เกริ่น"*.

**Why this exists.** Code written without a design adds one more copy of something that already exists, and every copy is a refactor later.
The owner had to point this out by hand. Measured that day on jh-api `main` `3a0dc02`:
- 14 inline `FOR UPDATE` reads of the trip row, with no shared lock function;
- 9 inline copies of one status list ("not yet picked up");
- 88 branches on `ServiceType` (Ride vs Delivery) in 37 files, though both services run the same trip flow;
- a fix written that day would have added the 15th lock copy and put a decision inside a DB function.

**Who follows it:** every designer, every implementer (Claude, Gemini, MAI, Grok) and every reviewer, in every repo.
Agents without Claude skills read this file at `~/.claude/rules-repo/skills/software-design/SKILL.md`.
The repo's own architecture page (jh-api: `docs/design/architecture-rules.md`) says where each kind of code lives; this skill says how to design it. Where they differ on placement, the repo page wins.

## The process

```
1 Survey → 2 Model in UML → 3 Shape + pattern per variant set → 4 One core, one seam → 5 Keep it simple → 6 Hand off and review
```
A small change still runs steps 1, 5 and 6. Steps 2–4 are required for anything that adds a type or a seam, or that touches several variants.

## 1. Survey: what exists, counted

1. Name the concept, then search for it under **several names**: the noun, the verb, the status or column, the error.
   Search the code and the repo's design docs. "Not found" holds only as far as you searched, so write down the scope.
2. **Count the copies** and write them down: `N places already do X (file:line …)`.
3. Check work in flight (open PRs, worktrees, the queue) for the same helper.
4. Read the existing design docs for the area. A recorded decision is not re-decided; if its reason no longer holds, say what changed.

## 2. Model it in UML, adapted to Rust

The design is drawn as Mermaid inside the design doc (`docs/design/<area>.md`), so it renders on GitHub and diffs in review.
It is the contract tickets are cut from: the names, signatures and files in it are what implementers write.

**Why UML fits this fleet:** the code is written by several AI agents that cannot see each other's work
(owner: *"หรืออาจเหมาะ เพราะ ใช้ AI"*). Mermaid is plain text an agent reads exactly, so one diagram tells every agent the same names,
signatures and files. Without it each agent guesses, and guesses become duplicates and collisions.
AI agents are capable and do their best work when the task has a clear structure and a known pattern to follow
(owner: *"AI มีความสามารถ แล้วชอบงานที่มีโครงสร้าง มีแบบแผน"*): the diagram and the named pattern are that structure.

**UML was made for languages with classes and inheritance; Rust has neither.** Draw what the code really is, not textbook UML:

| Rust | Draw as | Note |
|---|---|---|
| `struct` with `impl` | a class | fields + the methods other tickets use |
| `trait` | `<<trait>>` | the interface; never draw inheritance between structs |
| `enum` | `<<enumeration>>` with its variants | per-variant methods listed on it |
| module of free fns (a rule module) | `<<module>>` or `<<rule>>` | functions marked static with `$` |
| `impl Trait for X` | realisation `Trait <\|.. X` | the only "is-a" in Rust |
| a field holding another type | composition `*--` (owned) / aggregation `o--` (`Arc`, reference) | ownership is real in Rust; show it |
| a call or a use | dependency `..>` with a label | e.g. `Handler ..> pickup_rule : asks` |
| the file it lives in | `note for X "crates/…/file.rs"` | required on every element |

| Diagram | Mermaid | Draw it when | It must show |
|---|---|---|---|
| **Class** | `classDiagram` | always | every struct, trait, enum and module touched or added, with the fields and methods that cross tickets; the file of each; the core, the seam and the seam's pattern |
| **Sequence** | `sequenceDiagram` | a flow crosses layers or services | who calls whom, in order; where the transaction opens and commits; what runs after commit |
| **State** | `stateDiagram-v2` | an entity has statuses | every state, every allowed transition, who may make it |
| **Component** | `flowchart` with subgraphs | a crate, service or dependency is added or moved | layers and the allowed dependency direction |

**The diagram must match the code.** A diagram that has drifted is worse than none, because people build against it.
- A design for existing code is drawn **from the code** (read the files), not from memory or older docs.
- Code that has to differ from the diagram changes the diagram first, in the same PR or before it.
- The reviewer checks that every element the PR adds or renames is in the diagram at the file shown.

Keep each diagram to what one reader can hold; split by area rather than drawing the whole system.

## 3. Shape and pattern for each set of variants

First pick the **shape** by what kind of set it is. Then name the **pattern** of the seam.

| The variants are… | Shape | Never |
|---|---|---|
| A closed set fixed by the domain, law or protocol (`ServiceType`, `TripStatus`, a legal vehicle kind) | **an enum**; each per-variant table written **once**, as methods on the enum or in its rule module, and callers ask it | `if x == Variant` scattered through callers |
| Interchangeable outside engines or vendors (payments, banks, maps, push, face match) | **a trait + one real impl each + a `Fake`**, as `Arc<dyn Trait>` (generic when fixed at compile time) | a copy of the flow per vendor |
| Things an admin adds (classes, options, zones, fares) | **rows + an API**; no code change | a `match` on a row's code |

`dyn` for a closed set, or an enum for vendors, is the wrong shape even when it compiles.
This refines the fleet ♻️ rule ("one shared core + a trait per variant"), which is about interchangeable implementations. A closed set is an enum.

| Situation | Pattern | Rust shape | Example on `main` |
|---|---|---|---|
| Several outside engines doing one job | **Strategy** (+ **Adapter** per vendor API) | trait + impl per vendor + `Fake` | jh-api `RoadRouter`, `logistics/src/routing/` |
| Pick the implementation by key at runtime | **Registry** / **Factory** | one loader mapping key → `Arc<dyn Trait>`; a new variant = one file + one line | bank-bot `load_bank` |
| One flow, a few steps differ per variant | **Template method** (core + hooks) | the core owns the step order and asks the seam for the steps that differ | none yet; the Ride/Delivery trip core will be the first |
| Per-variant values or yes/no answers on a closed set | **Table-driven enum** | methods returning constants, or one `match` returning a small policy struct | `TripStatus::is_terminal()`, `is_passenger_aboard()` |
| A decision: eligibility, price, transition | **Policy / Specification** | a pure fn taking values, no I/O, tested without a DB | jh-api `surcharge.rs` `quote_lines_with` |
| Allowed status changes | **State machine** | one transition table every write asks, under a row lock | `RideSession::can_transition_to` |
| Reading and writing one entity | **Repository** | the entity's queries in one DB module; callers never write SQL | jh-api `crates/db/src/impls/**` |
| A write spanning several statements | **Unit of work** | one fn, one transaction: lock, re-check with the rule, write | jh-api architecture rules §A |
| Side effects after a change (push, chat, webhook) | **Observer / domain event** | emitted after commit, never inside the transaction | jh-api: push after commit |
| One entry point over steps a caller must not sequence | **Facade** | one public fn; the steps stay private | jh-api `RideSessionWastedTripFee::refuse_parcel_at_pickup` |

Name the pattern in the diagram and in the PR, for example `Seam: Strategy — trait OfferSearch, impls RideOfferSearch, DeliveryOfferSearch`.

## 4. Flows that behave alike: one core, one seam

When variants differ only in role (a ride carries a person, a delivery carries a parcel), there is **one core** and **one seam**.
- List every difference in a table in the design, and mark each one as a **value**, a **yes/no**, or a **real algorithm**.
- Values and yes/no answers become methods on the seam that return constants (`has_bill_check()`, a config field, a copy key). They are not branches at call sites.
- A real difference in algorithm (two ways to search for offers) is one function per variant behind the same seam, called from the core.
- Adding a variant must be one entry in the seam, not an edit in every file that branches today.

## 5. Keep it simple

- **Reuse what exists.** If a function already does it, call it; don't wrap it.
- **A repeated piece with no shared function gets one helper**, placed where the repo's rules say and used in your new code.
  - Count the old copies and list them as a follow-up ticket, split by file.
  - Don't migrate them inside an unrelated fix, and never add copy N+1.
- **A pattern needs a reason that exists today:** two variants now, or an outside engine to fake. One case means a plain function.
- **One pattern per seam.** Don't put a factory on a strategy on a wrapper for a single vendor.
- **No layer whose only job is to forward.** Keep nothing "in case". Delete dead or duplicate code you touch.
- The bar is the owner's: *"ไม่ขยะ ไม่ซับซ้อน"* (not junk, not complicated). If a ten-line change needs the design doc to follow it, it is too clever.

## 6. Hand off and review

**Design doc** must contain:
- the survey (§1);
- the UML (§2);
- the variant table and the seam with its pattern (§3–4);
- what is reused, which helpers are added, and the follow-up for old copies.

A doc missing the UML, the files, or the seam's pattern is not ready.

**Tickets** cite the classes and files from the diagram (skill `ticket-writing` § 📐). **Every dispatch order names this skill's file**, so implementers without Claude skills read it.

**PR body:** one line `Reuse: <reused> · <helper added> · <N old copies left, follow-up #…>`, with the survey numbers.

**Reviewer: FAIL** when any of these hold, naming the `file:line`:
- a new copy of logic that already exists;
- a new branch on a variant outside its seam;
- a decision in a handler or DB function instead of the rule/policy layer;
- the wrong shape (§3), or a seam whose pattern is unnamed or does not fit;
- an element the PR adds or renames that is missing from the diagram, or sits in a different file;
- an abstraction or wrapper with only one user;
- no `Reuse:` line, or survey counts that re-running the search does not reproduce.
