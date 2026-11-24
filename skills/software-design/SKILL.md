---
name: software-design
description: >-
  How Claude designs code so workers build it reused, not copied, and simple: pick the process by work type (hotfix, bug fix,
  feature, new variant, refactor, UI, migration, spike), survey and count what exists, model the change in UML adapted to the
  language (Rust, Dart, TypeScript) that matches the real code, choose the shape and a named design pattern for each set of
  variants, keep one core with one seam when flows behave alike, design errors, tests and invalid states, and review in two
  stages. Use when designing a class diagram or design doc, writing a ticket, or writing or reviewing code that adds a
  function, a type, a query or a branch on a variant — including hotfixes.
---

# Software design: model it, reuse it, keep it simple

Owner, 2026-11-25 (JH-API session): *"งานได้ reuse object ไหม"* · *"มันแค่แยก หน้า ที่ แต่มัน reuse ได้ เพราะ พฤติกรรม คล้าย ๆ กัน"* ·
*"source code ต้องมีคุณภาพไม่ขยะ ไม่ซับซ้อน"* · *"ไม่ง้ันผมก็ต้องมานั่งบอก เสีย refactor"* · *"พวก design pattern มันต้องมี สิ"* ·
*"แต่ผม อยากให้ เช่น UML"* · *"UML อาจไม่เหมือน กับเราก็ได้"* · *"หรืออาจเหมาะ เพราะ ใช้ AI"* · *"AI มีความสามารถ แล้วชอบงานที่มีโครงสร้าง มีแบบแผน"* ·
*"เราต้องมี แบบแผน ไม่ง้้น worker จะเขียนไร้ หลักการ"* · *"Claude เป็นแม่งาน"* · *"worker แค่ทำตาม ที่ Claude ออกแบบ"* · *"เรามี หลายแบบดิ เช่น งาน Hotfix"* · *"jh-api คืองานใหญ่"* · *"แต่เรา ใช้ ai เลยไม่ใช่ปัญหา"* · *"อย่าคิดแบบใช้ คนทำงานดิ"* · *"หลักการ มันยังไม่อัพเดท"* · *"มันเลยเป็นเอกสารเก่า"*.
The owner gives direction and expects the designer to work out the rest (*"คิดก่อน"* · *"ผมแค่ เกริ่น"*).

**Why this exists.** Code written without a design adds one more copy of something that already exists, and each copy is a refactor later.
Evidence, jh-api `main` `3a0dc02` (re-run the command to check):
- 77 decisions on `ServiceType` (Ride vs Delivery) in 37 non-test files, though both services run one trip flow:
  `git grep -nE '(==|!=) *(crate::enums::)?ServiceType::|ServiceType::(Ride|Delivery) *(=>|\|)|matches!\(.*ServiceType' 3a0dc02 -- crates src ':!*_test.rs' ':!*_tests.rs' ':!*test_fixtures*' ':!*test_support*' ':!tests/'`
- two transition tables for one trip that already disagree: `RideSession::can_transition_to` (`crates/db/src/impls/ride_session/escrow.rs:490`) and `DeliveryDetails::can_transition_to` (`crates/db/src/impls/delivery_details/escrow.rs:23`, which allows `Pending→Assigned` and re-spells `is_terminal()`);
- the trip row is locked by an inline `FOR UPDATE` query repeated across `crates/db/src/impls/` with no shared lock function, and a one-line fix that day nearly added another copy.

## Who does what

- **Claude designs** (the lane's controller, as skill `ticket-writing` § 📐 says): the survey, the UML, every seam and its pattern, every helper and where it lives. All of it goes into the design doc or the ticket before the ticket is released.
- **Ticket authors** (Grok or Claude) copy the design's seam, pattern, helpers and reuse decision into each ticket (§7).
- **Workers build exactly that.** They don't invent a seam, a pattern, a helper or a new copy. If the design doesn't fit the code, or a helper it needs is missing, they comment on the ticket and stop.
  - At the function level, every worker writes the ponytail way: reuse existing code, then the standard library, then an installed dependency, and only then new code; no wrappers, options or code "for later"; finish callers and tests.
  - agy workers also load the ponytail skill itself (skill `queue-controller` § ponytail).
  - Where function-level habits and the ticket's design differ, the design wins.
- **Claude reviews against the design** (§8).

**Placement** (which file or layer each kind of code goes in) follows the repo's own architecture page when it has one (jh-api: `docs/design/architecture-rules.md`). Otherwise it follows the repo's `CLAUDE.md`/`AGENTS.md`, and failing that, its existing layout.
This skill builds on, and does not repeat, skill `ticket-writing` § 📐 (diagram first, single-file exception), § 🧪 (behaviour table and up-front tests), § ♻️ (one core for interchangeable implementations), § 🔍 (reuse only what keeps the same contract) and § 🦀 (let the compiler catch mistakes).

**Size is not a reason to skip design or refactoring.** jh-api and pos108-core are large, and AI agents write code far faster than people
(owner: *"jh-api คืองานใหญ่"* · *"pos108-core ก็ใหญ่"* · *"แต่เรา ใช้ ai เลยไม่ใช่ปัญหา เพราะ ai ทำงานได้ไว กว่า คนมาก"* · *"100เท่า"*).
The cost is not in typing the change; it is in designing it right and reviewing it, and a wrong design is copied just as fast.
So spend the effort on the design and the review. Plan a big refactor as parallel waves split by file (skill `lane-controllers`), not as something to avoid.

**Don't plan as if people did the work** (owner: *"อย่าคิดแบบใช้ คนทำงานดิ"*). "Later", "when someone has time" and "a follow-up for some day" are human-capacity habits.
Here, cleaning up is a wave of parallel tickets that starts **now**: the old copies are migrated in the same round as the helper lands, not left as a backlog.
What still limits us is review and merge (one design, one reviewer, CI turns), so work is still split into small reviewable PRs, and those PRs run at the same time.

### Classic principles, re-read for AI workers

Most design advice was written when people wrote the code, and part of it exists only to save scarce human hours
(owner: *"หลักการ มันยังไม่อัพเดท"* · *"มันเลยเป็นเอกสารเก่า"*). Keep the part that is about the code itself; drop the part that was about the labour.

| Classic advice | Why it existed | What holds here |
|---|---|---|
| "Refactor later, leave a TODO" | refactoring cost people days | **Migrate now** as a parallel wave of per-file tickets |
| "Rule of three: don't extract until the third copy" | each extraction cost a person time | **Extract at the second copy.** The cost that remains is the extra concept a reader carries, so still no abstraction for a single case |
| "Keep diagrams small and few; they rot" | people would not keep them in sync | **Diagram every design.** Agents redraw it from the code on every change, and review checks it matches |
| "Test the important paths" | writing tests took people time | **One test per behaviour-table row**, each able to go red, plus the failure and edge cases |
| "Big refactors are risky, avoid them" | people make slips across many files | **Do them**, split by file into small PRs that run in parallel; the compiler and the tests catch the slips |
| "Write docs once the code settles" | writing docs took people time | **Write the design first.** It is what every agent reads before writing |
| "Small PRs so reviewers don't tire" | human attention | **Still small PRs**, now because review and merge are the shared limit (one reviewer, CI turns, merge order), and a small PR is cheap to revert |
| YAGNI | building unused things cost time | **Still holds**, because unused code is something every agent reads and must keep right |
| Single responsibility, clear names, invalid states unrepresentable | about the code itself | **Unchanged.** AI agents need these more, not less: they have only the code and the design to go on |

## 1. Pick the process by work type

The ticket's first line names its type, and the reviewer checks the row for that type.

| Work type | Survey (§2) | UML (§3) | Seam and pattern (§4–5) | Special rule |
|---|---|---|---|---|
| **Hotfix** (something broken, urgent) | short: is there a helper to call? | no | none new | Smallest root-cause fix, plus a test that fails before it. **The hotfix PR stays minimal** (fast review, fast merge). The cleanup is not deferred: right after it merges, Claude designs and dispatches the migration wave for every copy counted |
| **Bug fix** | yes | only if it adds a type shared across tickets | use the existing seam; no new variant branch | One helper is allowed when the fix would otherwise add copy N+1, named in the ticket |
| **Feature** | yes | class diagram, plus a sequence diagram if the flow crosses layers | yes | Design doc reviewed before tickets are released |
| **New variant** (service, bank, vendor) | yes | update the existing diagram | must be an entry in the existing seam | If it needs edits across many files, the seam is missing: design the seam first |
| **Refactor** | yes, every copy counted | before and after | yes | No behaviour change. Existing tests stay green untouched. Split by file |
| **UI / screen** | yes, existing components | component diagram for a new shared component | one component driven by data | No screen per app per variant |
| **Migration / DB** | yes | state diagram if a status is added | — | Data-migration section (§ 📐), and owner approval |
| **Spike** | no | no | no | Never merged to main. Real work is redone under its real type |

The single-file exception from § 📐 holds for every type: a change inside one file that adds no public type, signature or file needs no new diagram.

## 2. Survey: what exists, counted, reproducible

1. Name the concept, then search for it under **several names**: noun, verb, status or column, error.
   Search the code and the design docs. "Not found" holds only as far as you searched.
2. Record every count with **its command and the sha**: `N places do X — <command> @ <sha> (file:line …)`. A count nobody can re-run is not evidence.
3. Check work in flight (open PRs, worktrees, the queue) for the same thing.
4. Read the area's design docs. A recorded decision is not re-decided; if its reason no longer holds, say what changed.

## 3. Model it in UML, adapted to the language

Draw the design as Mermaid in the design doc (`docs/design/<area>.md`), so it renders on GitHub and diffs in review.
The diagram is the contract tickets are cut from.

**Why UML fits this fleet:** several AI agents write the code and cannot see each other's work. Mermaid is plain text every agent reads exactly, so one diagram gives all of them the same names, signatures and files. Agents work best with a clear structure and a known pattern, and the diagram plus the named pattern provide both.

**Draw what the code really is, not textbook UML.** UML assumes classes and inheritance; our languages differ:

| Concept | Rust | Dart / Flutter | TypeScript | Mermaid |
|---|---|---|---|---|
| Data with behaviour | `struct` + `impl` | `class` | `class` or a plain object + functions | a class |
| Interface | `trait` | `abstract interface class` | `interface` | `<<trait>>` / `<<interface>>` |
| Closed set | `enum` (+ methods) | `enum` with members, or `sealed class` | discriminated union + exhaustive `switch` | `<<enumeration>>` |
| Pure rules | rule module of free fns | top-level functions in a rule file | module of pure functions | `<<module>>`; static fn = `name()$` (the `$` goes after the call) |
| Implements | `impl Trait for X` | `implements` | `implements` / structural match | write `Trait <\|.. X` in Mermaid (the backslash below is only table escaping) |
| Owns / refers to | field (owned) / `Arc`, `&` | field / injected dependency | field / injected dependency | `*--` owned · `o--` shared |
| Calls | call | call | call | `..>` with a label |
| Never draw | inheritance between structs | deep `extends` chains | class hierarchies for data | — |

Raw Mermaid, as you type it:
```
classDiagram
  class OfferSearch { <<trait>> +search(ctx) Offers }
  OfferSearch <|.. RideOfferSearch
```

| Diagram | Mermaid | When | Must show |
|---|---|---|---|
| **Class** | `classDiagram` | every design | the **public, cross-ticket** types and methods, the core, the seam and its pattern; private helpers only if a ticket must create them |
| **Sequence** | `sequenceDiagram` | a flow crosses layers or services | call order; where the transaction opens and commits; what runs after commit |
| **State** | `stateDiagram-v2` | an entity has statuses | every state and allowed transition, and who may make it |
| **Component** | `flowchart` with subgraphs | a crate, package or service is added or moved | layers and allowed dependency direction |

**Files:** every public element's file is shown, either in a "who provides, who uses" table under the diagram or in a `note for X "path"`.

**The diagram must match the code.** Draw existing code from the code (read the files), never from memory. Code that has to differ changes the diagram first. Each Mermaid block must render: preview it on GitHub, or run `npx -y @mermaid-js/mermaid-cli -i doc.md -o /tmp/out.md`, before review.

Split a large design into diagrams by area, so each ticket points at the part it builds and a reviewer checks one area at a time.

## 4. Pick the shape for each set of variants

| The variants are… | Shape | Never |
|---|---|---|
| A **closed set** fixed by the domain, law or protocol (service kind, trip status, legal vehicle kind) | **an enum** whose per-variant answers are written once: methods on it, or one `match` returning a small policy struct. A variant with a long algorithm of its own gets a private function, called from that one `match` | `if x == Variant` across callers; a `dyn` trait over the enum |
| **Interchangeable outside engines or vendors** (payments, banks, maps, push, face match) | a **trait + real impl(s) + a `Fake`**, injected (`Arc<dyn Trait>`, or a generic when fixed at compile time) | a copy of the flow per vendor |
| **Things an admin adds** (classes, options, zones, fares) | **rows + an API**, no code change | a `match` on a row's code |

Adding a variant costs: **closed set** = one enum variant, and the compiler lists every `match` that must answer for it (§ 🦀). That's intended, not a defect. **Engine** = one new file + one registry line.

**Make invalid states unrepresentable:** newtypes for IDs, money and units (`RideSessionId`, satang amounts); an enum instead of a set of bool flags; constructors that refuse bad input. Mark newtypes `<<newtype>>` in the diagram.

## 5. Name the pattern of every seam

| Situation | Pattern | Shape | Example (verified on `main`) |
|---|---|---|---|
| Several outside engines doing one job | **Strategy** (+ **Adapter** per vendor) | trait + impl per vendor + `Fake` | jh-api `RoadRouter`: `crates/logistics/src/routing/` (`google.rs`, `fake.rs`) |
| Choose an implementation by key | **Registry** (a loader) | one map key → `Arc<dyn Trait>` | bank-bot `load_bank` (other repo) |
| One flow, a few steps differ per variant | **Template method** | the core owns the steps and asks the seam for the differing ones | none yet; the Ride/Delivery trip core is the first |
| Per-variant values or yes/no on a closed set | **Table-driven enum** | methods returning constants | `TripStatus::is_terminal()`, `is_passenger_aboard()` (`crates/db/src/enums.rs`) |
| A decision (eligibility, price, transition) | **Policy** | pure function, values in, no I/O | jh-api `quote_lines_with` (`crates/logistics/src/surcharge.rs`) |
| Allowed status changes | **State machine** | one transition table, asked under a row lock | `RideSession::can_transition_to`, which still has a diverging twin (see Why) that the trip core must merge |
| Reading and writing one entity | **Repository** | its queries in one DB module | jh-api `crates/db/src/impls/**` |
| A multi-statement write | **Unit of work** | one fn, one transaction: lock, re-check, write | jh-api architecture rules §A |
| One entry point over steps a caller must not sequence | **Facade** | one public fn, private steps | jh-api `refuse_parcel_at_pickup` (`crates/db/src/impls/wasted_trip_fee.rs`) |
| Effects after a change (push, chat) | **After-commit effects** | the handler sends them after commit, never inside the transaction | jh-api architecture rules C6 |

Name it in the design and the PR. For a closed set, write it like this: `Seam: table-driven enum — ServiceType::offer_search() returns RideOfferSearch | DeliveryOfferSearch via one match`. For an engine: `Seam: Strategy — trait RoadRouter, impls GoogleRouter, FakeRouter`.

## 6. Design the rest of the contract, then keep it simple

**In the design doc, besides the UML:**
- **Alternatives considered.** At least one rejected option, with the reason it was rejected. That reason is what stops the next session from re-proposing it.
- **Errors at the seam.** Each seam or public function names its error type: an enum of the crate or package's errors, mapped where a foreign error enters. No stringly errors. In Rust, `anyhow` stays at the application edge and never crosses a trait.
- **Test seams.** Which pure functions are tested without I/O, which `Fake`s the tests use, and the up-front failing tests (§ 🧪).

**Keep it simple:**
- Reuse only what keeps the same contract (§ 🔍): the matching rows go in the core, the differing rows in the seam. Never add a flag or an `if` to an old object to make it fit.
- A pattern needs a reason that exists today: two variants now, or an outside engine to fake. Otherwise use a plain function. A Factory or Registry with one implementation is the smell.
- Application code uses concrete types. Generics and traits belong only at a real seam.
- One pattern per seam. No layer whose only job is to forward. Nothing kept "in case".
- A deliberately simple choice with a known limit carries a comment: `shortcut: <limit>, upgrade when <condition>`. Then nobody rediscovers it as a defect.
- One PR does one ticket: a worker deletes or changes code only inside its ticket's File scope, so every PR stays small to review and safe to merge in parallel.
- **Old copies are migrated now, as a wave.** When a helper or seam lands, Claude cuts one ticket per file for every counted copy and releases them together (skill `lane-controllers`), in the same round. In a repo at the 20-issue cap the wave is one ticket with a per-file checklist, or feature-branch function tickets (exempt from the cap).
- The bar is the owner's: *"ไม่ขยะ ไม่ซับซ้อน"* (not junk, not complicated).

## 7. Hand-off: the design doc, the ticket, the PR

**Design doc:** the work type, the survey with commands (§2), the UML (§3), the variant table and shape (§4), each seam's pattern (§5), alternatives, errors and test seams (§6), the helpers and where they live, and the migration wave for the old copies (tickets per file, released together).

**Ticket:** the work type on the first line. It names the classes and files from the diagram (§ 📐), the seam and its pattern, the helpers to create and in which file, and the reuse decision (*"reuse `X`: the table matches"* or *"do not use `X`, because <row>"*, § 🔍). The dispatch order names this file.

**PR body:** a `Reuse:` section in **one** form (and when a helper was added, the migration wave's tickets):
- something reused in a new place ⇒ the § 🔍 form: what is reused, plus its contract table or one line per row that could differ;
- nothing reused ⇒ `Reuse: none — searched <terms> in <paths> @ <sha>`.

## 8. Review in two stages

**Stage 1, does it match the design** (read the ticket and the design doc first):
- The work type's row from §1 is followed. A hotfix that refactors fails; a feature with no design doc fails.
- The public, cross-ticket elements the PR adds or renames appear in the diagram, at the file shown. Private helpers don't need to.
- Each Mermaid block in a changed doc renders.
- The `Reuse:` section is present in one of its two forms, and its counts reproduce when the command is re-run.

**Stage 2, quality.** FAIL, naming the `file:line`, when:
- the PR adds a new copy of logic that already exists;
- a new branch on a variant sits outside its seam, or a `dyn` trait is placed over a closed set;
- a decision sits in a handler or DB function instead of the rule or policy layer;
- the seam's pattern is unnamed, or doesn't fit §4–5;
- there is a reuse whose contract row differs, or a flag or `if` was added to an old object to make it fit;
- there is a wrapper that only forwards, or an abstraction with one implementation and no `Fake` or test need;
- an error crosses a seam as a string or as `anyhow`.

## 9. Keeping this skill honest

When an agent's design goes wrong in a way this skill should have caught, add the case to this file (what happened, the commit) and fix the rule. Keep 2–3 past cases as checks:
- the jh-api trip-lock fix: reuse the lock helper, no 15th copy;
- Ride/Delivery: one core, an enum seam, no `dyn`.

Before changing the skill, re-read it against them.
