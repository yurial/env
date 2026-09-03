---
name: tla-plus
description: Use when writing, reviewing, or model-checking TLA+ specs (.tla) or TLC models (.cfg) at any abstraction level, and when the user asks to find bugs TLA+ catches (races, deadlocks, starvation, protocol violations) — check for an existing spec and propose writing one if absent. Covers safety/liveness properties, refinement, component contract (external) and implementation (internal) model pairs, the Heavy full-detail composition variant, TLC invocation, and state-space control; routes mathematical-proof requests to the tlaps skill. Prefer for formal verification work; not for purely aesthetic code design questions.
---

# TLA+ specification authoring and TLC model checking

Goal: specs of components of a large system, at multiple abstraction levels, that
catch real bugs (type, safety, deadlock, liveness) without combinatorial explosion.

Non-negotiable: a spec is done only after a green TLC run of its model. Never claim a
spec is verified without executing TLC and seeing `Model checking completed`. TLC is
also the parser: run it after every edit; do not hand-verify TLA+ syntax.

All patterns below were validated against TLC 1.8.0 (rev 9787e65). If a run rejects a
pattern from this skill, the TLC version changed — re-derive, do not patch blindly.
Proof patterns (section 9) live in the `tlaps` skill, validated against TLAPS 1.5.0.

**Bug-hunt trigger.** When the user asks to *find a bug* of a class TLA+ catches —
races/interleavings, safety violations (lost update, double-apply, mutual exclusion),
deadlock, starvation/liveness, message loss/duplication/reordering, crash recovery,
abstraction mismatch between design levels:
1. Check whether a spec already exists: the TLA/ layout (section 8), or search the
   repo for `*.tla` / `*.cfg` covering the component in question.
2. If none exists — do not jump to fixing code on a hunch; *propose writing a spec*:
   state the level (L0/L1/L2, section 2), the property in one sentence (section 1
   step 1), the smallest model bounds (section 6.1 here; commands in the tlc-run skill), and what TLC will hunt there.
   Wait for the user's go-ahead before writing it.
3. If a spec exists — extend it or add a new cfg model for the property; never fork a
   duplicate spec of the same component.

## 1. Workflow (follow in order)

Tool choice first: steps 1–9 are the TLC loop — bounded-model evidence, the default.
If the user explicitly asks for a *mathematical proof* ("prove", "proof", "for all N"),
or the property is inherently unbounded (arbitrary node count, unbounded log), go to
section 9 (TLAPS) instead of, or before, this loop.

1. **Property first.** Write down, in one sentence, what error class you are hunting,
   then as a temporal formula (invariant `Inv` or liveness `Live`). If you cannot state
   the property, you are not ready to write the spec.
2. **Pick the abstraction level** (section 2): the *highest* level at which the property
   is still observable. Fewest variables that can exhibit the bug.
3. **Write the spec module** from the template (section 3). For a component,
   this means the model pair of section 2b: the external contract module
   first (check it standalone), then the internal module.
4. **Create a model with the smallest sensible bounds** (typically 2–3 nodes,
   1–2 in-flight messages; constants are assigned in the cfg, section 6.1). Run TLC
   (execution via the tlc-run skill — direct or delegated) checking *safety only*
   (TypeOK + invariants + deadlock). Fix until clean.
5. **Coverage gate (hard stop).** Rerun the safety model with `-coverage 1` and
   verify every action fired. A never-fired action is a bug, an over-small model,
   or dead code — resolve it before moving on. This gate blocks every later
   stage (section 6.3 here). Grow bounds one step at a time and re-pass the gate after
   each growth; stop when the state budget (section 5) is hit.
6. **Only after safety is clean AND the coverage gate has passed**, enable
   liveness: switch the cfg to the fair spec and add `PROPERTY`, rerun on the
   *minimal* model. Liveness costs several times more.
7. **Simulation pass**: `-simulate` with a long `-depth` to reach deep behaviors that
   BFS truncates (long queues, rare interleavings). Coverage statistics accumulate
   over generated behaviors (works with `-coverage 1`) — check them too: an action
   cold even in simulation is genuinely hard to reach.
8. **Refinement** (section 2.4) if an upper-level spec exists: `PROPERTY Refines`.
   The refinement cfg is a separate model — it must pass its own green run and
   coverage gate. This is what catches abstraction bugs between levels. For a
   component model pair (2b) the refinement onto the component's own external
   contract is mandatory, not conditional.
9. **Record** in the spec header comment: model name, states found, diameter, wall time,
   date. Anyone re-running the model needs the baseline. If the verified algorithm is
   governed by a project spec (spec skill), ALSO mirror the result into that spec's
   `Verification` section: the exact algorithm name + requirement IDs, the abstraction
   level of this spec (section 2) and what it abstracts away, what was checked
   (invariants/liveness, bounds), and the explicit Not-checked list.

## 1b. Agent-based workflow (assistant_cheap → assistant_max)

When authoring a TLA+ spec with the `tla-plus` skill, follow this two-agent delegation workflow:

1. **Research with assistant_cheap.** Use the `assistant_cheap` researcher agent to read
   the relevant spec files, examples, and documentation. The agent should save
   references to useful spec files with exact line ranges in a temporary draft file
   (e.g. `TLA/draft.md` or a working copy in the project root). The draft should
   contain:
   - Links to source `.tla` and `.cfg` files with line number ranges
   - Brief summaries of each document's relevance
   - Noted conflicts or ambiguities between documents
   - Gaps in documentation that need to be addressed in the new spec
   - Copy of relevant template snippets with explanations

   The draft file is created locally for the author to review; it is NOT part of
   the final commit and is not committed to the repository until explicitly
   approved.

2. **Generate with assistant_cheap, iterate with TLC.** Once the research draft is
   ready, use `assistant_cheap` to author or update the TLA+ spec module according
   to the template (section 3) and writing rules (sections 4-7). After each
   iteration:
   - Run TLC on the safety model (via tlc-run skill) checking TypeOK, invariants,
     and deadlock.
   - Review the TLC output for errors, counterexamples, or coverage gaps.
   - Fix errors in the spec based on TLC findings.
   - Repeat until the safety model is green and the coverage gate passes
     (section 6.3).

This cycle (spec generation → TLC run → fix) should be repeated up to **3
iterations** of `assistant_cheap` before escalating.

3. **Escalate to assistant_max if necessary.** If after 3 complete TLC runs
   (i.e., after 3 spec iterations) the same or similar errors persist, or the
   spec requires high-effort reasoning (complex liveness, tricky refinements,
   intricate invariant design), switch to using `assistant_max` (on
   vk-zai-personal/flash with reasoningEffort max) to fix the PLA file.
   Assistant_max should:
   - Review the current spec and TLC output
   - Apply targeted fixes based on deep reasoning about the error class
   - Re-run TLC to verify the fix
   - Document the fix in the spec header; if it changes behavior, the change
     goes into the governing project spec immediately, with only the resulting
     code-vs-spec divergence recorded in DEVIATIONS.md (spec skill, section 6)

4. **Cleanup.** After the spec is green and verified, remove or archive the draft
   file (see spec skill section 1b for archive strategy). The draft is not part of
   the final commit and should be cleaned up to keep the repository clean.

This workflow ensures that simple and mechanical spec authoring tasks leverage the
cheap, fast assistant_cheap, while complex or recalcitrant bugs escalate to the
high-effort assistant_max, keeping iterations efficient and the draft ephemeral.

## 2. Abstraction levels for a large system

Never one giant spec. Decompose into levels; each level is its own module(s) with its
own models; variables of one level never contain data structures of another.
Components are specified as model pairs: an external contract plus an internal
implementation (section 2b).

| Level | Models | Typical properties |
|---|---|---|
| L0 system | components as black boxes with a handful of abstract states each | global invariants: at-most-one-leader, no lost update, monotonicity of committed data, no double-apply |
| L1 protocol | messages between components, ordering, retries, timeouts-as-events, loss/duplication, crash/recover | protocol invariants (message well-formedness, state-machine constraints) and end-to-end liveness `sent ~> processed` |
| L2 component | internal algorithm of one component; environment is nondeterministic (unbounded `\E` inputs) | internal invariants, local liveness, deadlocks |

Rules:

- 2.1 Formulate each property at the highest level where it is observable; then, if the
  bug lives lower, re-express the same property at L1/L2 by projecting variables.
- 2.2 Cross-check levels: when an L2 spec makes variables observable that also exist in
  an L1 invariant, include that invariant in the L2 model too (cheap sanity check).
- 2.3 Model crashes as a nondeterministic `Crash(n)` / `Recover(n)` pair resetting the
  volatile subset of `n`'s variables. Model the network as a set of in-flight messages
  with lossy/duplicating delivery actions. Do not model time: no global clock ticks —
  a timeout is just another enabled action.
- 2.4 Refinement: the lower level implements the upper level. Canonical pattern
  (validated on TLC):
  ```tla
  \* in the lower-level module:
  busyMap == \E n \in Nodes : phase[n] = "wait"     \* mapping: expression over lower vars

  Upper == INSTANCE UpperModule WITH busy <- busyMap \* substitute every upper variable
                                                     \* by a function of lower variables;
                                                     \* a parenthesized expression inline
                                                     \* also parses, an operator is cleaner
  Refines == Upper!Spec                              \* temporal property to check

  THEOREM Spec => Refines                            \* documentation only; TLC never
                                                      \* resolves THEOREM names in cfg;
                                                      \* prove with TLAPS (section 9)
                                                      \* if a proof is requested
  ```
  Model cfg: `SPECIFICATION Spec` + `PROPERTY Refines`. TLC then checks that every
  behavior of the lower spec satisfies the upper spec under the mapping. Do NOT write
  `PROPERTY Spec => Upper!Spec` — TLC rejects action-containing temporal formulas not
  of the form `<>[]A` / `[]<>A`; the `SPECIFICATION` clause already restricts behaviors.
  A refinement failure means the concrete mechanism does not implement the abstraction
  — exactly the bug class per-level checking misses.
- 2.5 If no direct mapping exists, add **history/witness variables** to the lower spec:
  variables that only record what happened (never read by actions), making the mapping
  expressible. This is the standard fix before giving up. If refinement is still out of
  reach, fall back to 2.2 (shared invariants) and note the gap in the specs TODO.md —
  loud stub, not silence.

## 2b. Component model pairs: internal and external

Every component that gets a TLA+ spec gets TWO modules, not one:

- `<component>External.tla` — the component as a **black box**: interface and
  contract only. Written to be INSTANCEd into other components' internal
  models as a reusable, pre-checked environment.
- `<component>Internal.tla` — the component's **own logic**: the real
  algorithm, internal variables, internal invariants (the L2 spec of
  section 2).

The pair is the formal version of the L0 row "components as black boxes":
the external model IS the black box other components reason about, the
internal model is what implements it, and refinement (2.4) ties them
together. A component breaking its own contract surfaces as a refinement
failure; a component misusing another component surfaces in the importer's
composition model.

Order: write the external contract FIRST (it is the interface decision),
check it standalone, then write the internal model and check the refinement.
Importers INSTANCE only external modules — an internal module is never
INSTANCEd from outside.

### External model: what goes in

- CONSTANTS for interface parameters (participants, request-id space,
  flow-control bounds) plus an `ASSUME` stating the assumptions the contract
  makes about its instantiation.
- Interface event histories as VARIABLES — sequences (or sets) of what
  crossed the interface, in 2.5 witness style: they record what happened;
  no action reads them for control flow. These histories ARE the observable
  behavior; there is nothing else.
- Interface actions as self-contained reusable operators: guard + primed
  effects on the interface variables only. An importer conjoins them to its
  own steps (joint actions).
- A standalone autonomous model for checking the contract itself: `EnvNext`
  (a nondeterministic environment drives the interface) + guarded
  `Terminal` + `Spec`, and `FairSpec` containing ONLY the component's own
  obligations (weak fairness on its output actions) — never fairness on
  the environment.
- Guarantees as NAMED operators (safety invariants and liveness
  properties), so importers can check them by name.

**Infinite-state trap (standalone contract runs).** The histories only
grow and `EnvNext` is nondeterministic, so an unbounded standalone run of
the external model has an infinite state space — TLC never terminates.
Bound the environment explicitly: a finite, non-repeating request space
(`EnvNext` issues each (worker, request) pair at most once), so the
histories saturate and the model closes. Measured on a review run:
without the bound the run did not finish within 120 s; with it the same
model closed at 18 states. Record the bound in the cfg header as a
modeling assumption (section 5).

### External model: what is forbidden (each poisons every importer)

- Internal variables — buffers, slots, pointers, worker phases, caches.
  Importers inherit them in every state: state-space bloat plus a leaky
  abstraction.
- Internal invariants — they talk about variables that must not exist here;
  they belong in the internal model.
- Fairness on environment actions — the importer decides when it calls the
  interface; a contract that assumes a live caller lies to its importers.

### Internal model: the implementation side

- The real algorithm (section 3 applies in full): internal variables,
  `TypeOK`, internal invariants, deadlock policy, local liveness. These
  checks exist ONLY here — that is the point of the split.
- Witness copies of the interface histories, updated by the component's own
  steps and never read by them — the identity mapping onto the external
  module's variables (2.5 in its purest form).
- The mandatory refinement link onto the component's own external module:

  ```tla
  \* in queueInternal.tla:
  Ext == INSTANCE queueExternal
           WITH enq <- enqH, deq <- deqH, Cap <- BufCap
  Refines == Ext!Spec
  ```

  cfg: `PROPERTY Refines` in `queueInternal.tlc.impl.cfg`. A failure means
  the implementation breaks the published contract — the bug class neither
  model alone catches.

### Composition: importing a contract into another internal model

The importer (a Scheduler over the Queue) treats `queueExternal` as its
environment with zero visibility into the queue's implementation:

```tla
\* in schedulerInternal.tla:
CONSTANTS
  Workers,   \* importer's participants — substitutes queueExternal's Nodes
  ReqIds,    \* importer's request space (quantified in Next below)
  Cap        \* like-named constant of queueExternal: auto-resolved, no WITH

VARIABLES
  phase,     \* importer's own state
  enq, deq   \* contract-owned interface variables: declared here under the
             \* same names as in the imported module

Q == INSTANCE queueExternal WITH Nodes <- Workers

Terminal == Q!Terminal  \* re-export the imported termination guard under
                        \* its own name (Next references it below)

QFifo == Q!Fifo    \* root-alias: cfg resolves root-module names only —
                   \* a cfg line `INVARIANT Q!Fifo` does not work

Init == /\ phase = [w \in Workers |-> "idle"]
        /\ Q!Init

\* Importer steps CONJOIN interface actions (joint actions): the effect on
\* enq/deq is the contract's, the effect on phase is the importer's.
Submit(w, r) == /\ phase[w] = "idle"
                 /\ Q!Enq(w, r)
                 /\ phase' = [phase EXCEPT ![w] = "submitted"]

Collect(w) == /\ phase[w] = "submitted"
              /\ enq[Len(deq) + 1][1] = w    \* guards read only the interface
              /\ Q!Deq(w)
              /\ phase' = [phase EXCEPT ![w] = "collected"]

vars == <<phase, enq, deq>>
Next == (\E w \in Workers, r \in ReqIds : Submit(w, r))
      \/ (\E w \in Workers : Collect(w))
      \/ Terminal      \* guarded Terminal, as in section 3
Spec == Init /\ [][Next]_vars
```

Composition rules (validated on TLC 1.8.0 rev 9787e65):

- The imported module's variables must be DECLARED in the importer under
  the same names — `INSTANCE` without `WITH v <- ...` for a variable
  requires the name to exist in the root module. Constants substitute
  freely (`WITH Nodes <- Workers`); like-named constants resolve
  automatically.
- The every-action-defines-all-variables convention (section 3) is what
  makes joint actions sound: the conjoined interface action already pins
  the interface variables, the importer's conjuncts pin its own.
- Every imported contract's guarantees are checked as INVARIANTs of the
  composition, via root aliases. A violation means either the importer
  breaks the contract's assumptions or the component does not implement
  its contract — both are real bugs.
- Contract liveness is NOT inherited: the importer never takes `Q!FairSpec`.
  Progress across the interface is expressed as the importer's own liveness
  — weak fairness on the importer actions that conjoin interface actions.
- The imported `EnvNext` is normally NOT part of the importer's `Next`: in
  the contract, `EnvNext` IS the caller side of the interface — and the
  importer is that caller. Include it only to model interface events not
  caused by the importer (the component acting on its own as seen from
  the interface: timeouts, background flush).

Naming and file placement for the pair: section 6.1; repository layout:
section 8. Both modules of the pair pass the full workflow of section 1 and
the coverage gate of 6.3 independently, each with its own cfg models.

### Heavy model: full-detail composition

A third module per component, on demand only (trigger below):
`<component>Heavy.tla`, sitting in the same TLA/ directory as the pair.

- Definition: an Internal model whose composition replaces the External
  contracts of imported components with their Internal (implementation)
  modules — the composition is built with full internal detail of every
  inner component. Where an imported component already has its own Heavy
  model, prefer that (the most detailed variant of the same component).
  The substitution applies recursively, transitively down the dependency
  tree: every component inside the composition is represented at full
  detail; no External black boxes remain anywhere in the composition.
- Keeps everything an Internal model has (above): the real algorithm,
  `TypeOK`, internal invariants, deadlock policy, local liveness — and the
  mandatory refinement link `PROPERTY Refines` onto the component's own
  External contract (`<component>Heavy.tlc.impl.cfg`), same as Internal.
- This is the ONE sanctioned exception to the "never INSTANCE another
  component's internal module" rule (section 7).
- Generation trigger (hard rule): a Heavy model is generated ONLY in one of
  two cases — (1) the user explicitly requests it (e.g. "generate a Heavy
  model", "full-detail composition"), or (2) Heavy models already exist in
  the same TLA/ directory for other components: the project has already
  committed to the Heavy tier for this directory, and a new component's
  Heavy is generated along with its pair. Otherwise do NOT generate Heavy
  proactively; the External/Internal pair is the default.
- State-space warning: a full-detail composition multiplies the state
  spaces of the inner components multiplicatively — the state budgets and
  the shrink ladder of section 5 apply with extra force: smallest sensible
  bounds, safety before liveness, and expect a much smaller N than Internal
  models tolerate. If exhaustive checking is impossible even after the
  ladder, follow the existing rule — loud header + TODO.md note, with the
  bounded/simulation checks run instead labeled as such.

## 3. Module template

```tla
------------------------- MODULE ProtocolName -------------------------
EXTENDS Naturals, FiniteSets, TLC      \* TLC module: Permutations, Assert, ...

CONSTANTS
  Nodes,        \* set of node ids; assigned small values in cfg (section 6.1)
  MaxQ          \* small bound; never leave unbounded in a model

VARIABLES
  phase,        \* abstract phase per node
  msgs          \* in-flight messages

vars == <<phase, msgs>>

\* Domains of variables are computed from CONSTANTS only, never from variables.
Msgs == [from: Nodes, kind: {"req"}]

TypeOK == /\ phase \in [Nodes -> {"idle", "wait", "done"}]
          /\ msgs \in SUBSET Msgs

Init == /\ phase = [n \in Nodes |-> "idle"]
        /\ msgs = {}

Send(n) == /\ phase[n] = "idle"
           /\ Cardinality(msgs) < MaxQ     \* backpressure: constants bound the model
           /\ msgs' = msgs \union {[from |-> n, kind |-> "req"]}
           /\ phase' = [phase EXCEPT ![n] = "wait"]

Recv(n, m) == /\ m \in msgs
              /\ m.from = n
              /\ msgs' = msgs \ {m}
              /\ phase' = [phase EXCEPT ![n] = "done"]

Terminal == /\ \A n \in Nodes : phase[n] = "done"   \* guarded self-loop: marks
            /\ UNCHANGED vars                        \* legitimate termination

\* Parenthesize each disjunct: an unparenthesized `\E n : A \/ B` parses as
\* `\E n : (A \/ B)` — B silently lands inside the quantifier and is disabled
\* whenever the quantified set is empty.
Next == (\E n \in Nodes : Send(n))
      \/ (\E q \in Nodes, m \in msgs : Recv(q, m))   \* binder names must differ
                                                     \* within one expression
      \/ Terminal

Spec == Init /\ [][Next]_vars

\* Fairness: quantifiers over CONSTANT domains only (TLC rejects quantified
\* fairness over variable-dependent sets with "cannot handle the temporal formula").
\* Binders must not repeat names used elsewhere in the same formula.
FairSpec == Spec
          /\ \A n \in Nodes : WF_vars(Send(n))
          /\ \A q \in Nodes, m \in Msgs : WF_vars(Recv(q, m))

\* Safety: the actual bug you are hunting
Inv == Cardinality(msgs) <= MaxQ

\* Liveness: progress under FairSpec. The <>Term conjunct is only needed under
\* the alternative deadlock policy (see conventions below); with the guarded
\* Terminal action above, checking Live alone is enough.
Term == \A n \in Nodes : phase[n] = "done"
Live == \A n \in Nodes : (phase[n] = "wait") ~> (phase[n] = "done")
LiveAll == Live /\ <>Term

\* SYMMETRY support: the library Permutations operator (hence EXTENDS TLC);
\* hand-written permutation sets can make TLC reject the model
Sym == Permutations(Nodes)

\* For cfg CONSTRAINT / ACTION_CONSTRAINT / VIEW — safety models only (section 5):
Cons == Cardinality(msgs) <= MaxQ
ActCons == Cardinality(msgs') <= MaxQ
View == phase
=======================================================================
```

Conventions:

- Every action defines *all* variables (`x' = ...` or `UNCHANGED`); missing primed
  variables cause TLC errors or silently wrong specs.
- Values are strings (`"idle"`), numbers, booleans, records — never bare identifiers:
  `{idle, wait}` is a set of *undefined operators*, SANY rejects it ("Unknown
  operator"). Interchangeable ids come from cfg model values (section 6.1).
- The stuttering-step `[Next]_vars` is intentional: it lets the environment interleave.
  To catch a race between two logically-consecutive steps of one component, split them
  into two actions — interleaving of others between them then becomes reachable.
- **Deadlock policy** (all statements verified on TLC 1.8.0). TLC reports a
  deadlock for a state where NO action of `Next` is enabled; an enabled action
  that keeps all variables unchanged (a self-loop) counts as a successor and
  suppresses the report for that state. Consequences:
  - *Reactive spec* (environment can always act: clients may always send): keep
    the default check. A reachable stuck state is a design bug; TLC prints the
    trace. This is the preferred shape — model the environment as non-terminating.
  - *Terminating spec*: add the guarded `Terminal` action as a top-level disjunct
    of `Next` (template above). Legitimate final states stop being deadlocks;
    illegitimate stuck states are still reported, because the guard is false
    there. Do not attach fairness to `Terminal`.
  - NEVER use an unguarded self-loop (`/\ TRUE /\ UNCHANGED vars`): it silently
    disables deadlock checking for every reachable state and hides real hangs.
  - Alternative for terminating specs: run with `-deadlock` (disables the check)
    and add `<>Term` to the liveness property — a stuck state then surfaces as a
    liveness violation with a single-state stuttering lasso.
- Fairness rules: `WF_vars` on *minimal instantiated* actions
  (`\A n \in Nodes : WF_vars(Send(n))`), never on `\E`-existential actions — that
  asserts "someone eventually acts" and hides per-node starvation. Do not make
  failure/loss actions fair; make delivery fair only if the system guarantees it.
  `SF_vars` only when an action can repeatedly lose and regain enabledness without
  firing; continuous enabledness is already covered by `WF_vars`. Extra SF is a
  stronger assumption than the real system makes — it can mask starvation bugs.

## 4. Error classes to catch (checklist for every spec)

- **Type errors** — `TypeOK` invariant, always first. Catches ill-typed state, missing
  EXCEPT branches, bad DOMAIN.
- **Safety bugs** — the functional `Inv`: mutual exclusion, at-most-once, no-loss,
  monotonicity, unique leader, no phantom reads.
- **Deadlock / stuck states** — default check for reactive specs; guarded
  `Terminal` marks legitimate termination in terminating specs (section 3);
  an unguarded self-loop hides everything — never use one.
- **Liveness / starvation** — `Live` under per-agent weak fairness: `sent ~> processed`,
  eventual termination, eventual cleanup. A liveness counterexample always ends with
  `Back to state N` (a lasso); a lasso that stutters in one state = missing/too-weak
  fairness; a nontrivial cycle = a real cyclic starvation scenario.
- **Abstraction bugs between levels** — refinement property (2.4).
- **Contract violations between components** — the importer relies on a
  behavior the component does not provide. Caught in two places: the
  component's internal⇒external refinement (`PROPERTY Refines`, 2b) and the
  importer's composition model (imported guarantees as invariants, 2b).
- **Stuttering-caused non-progress** — same signature: single-state lasso.

## 5. State-space control (apply top-down at the first sign of explosion)

Budget heuristics (8-core dev box, rough): <10^6 distinct states — trivial;
10^7 — minutes, fine; 10^8 — hours and heavy disk, needs justification; >10^8 —
do not launch exhaustive checking, shrink the model first. Track growth via the
`Progress:` lines in TLC output; if distinct states grow fast past several million
without slowing, interrupt and shrink.

Ladder (try in this order, one at a time, rerun after each):

1. **Shrink constant domains.** 3 nodes find almost all interleaving bugs; 4 rarely
   add any. 2 request ids catch uniqueness bugs, 3 catches ordering bugs. Cap terms,
   lengths, retries at 2. Every `\E i \in 0..N` doubles/triples branching.
2. **Abstract the data, keep the structure.** Payload -> sender+type; log ->
   length + set of entries; amount -> 0..3; timer -> boolean; history ->
   digest (e.g. `Len`, `Cardinality`, min/max, membership flag). The property dictates
   how much data must survive the abstraction — abstract less if the property talks
   about it, more if it does not.
3. **Sets instead of sequences when order is irrelevant** — factorial reduction. But:
   a set cannot model duplicates; if duplication is part of the bug class, use a
   multiset (function `msg -> count`) or a small sequence. Do not sort what TLC could
   interleave.
4. **SYMMETRY — safety models only.** If and only if the spec, invariants, and
   properties are invariant under permuting `Nodes` (no `n1 < n2`, no fixed leader
   constant, no CHOOSE-min). Use `Sym == Permutations(Nodes)` (requires `EXTENDS TLC`)
   and `SYMMETRY Sym` in the safety cfg. Verify the reduction by comparing distinct
   states with/without the line. TLC warns that symmetry with liveness "might cause
   TLC to miss violations" — treat it as a hard rule: no SYMMETRY in any model with a
   `PROPERTY` line.
5. **CONSTRAINT (state) / ACTION_CONSTRAINT (transition) — safety models only.**
   Semantics: states violating a constraint are discarded *unchecked* (successors not
   generated, invariants not tested on them); an action constraint discards
   transitions (write it over primed variables, e.g. `Cardinality(msgs') <= 1`, and
   name it as an operator in the .tla — the cfg line takes the operator name, not an
   expression). With liveness TLC does *not* even warn — never put constraints in a
   model with a `PROPERTY` line. Uses: bound the environment (cap in-flight messages,
   cap issued requests) as a *documented modeling assumption* recorded in the model
   header — it is a smaller model, not a sound check of the unbounded one. Never use
   constraints to silence a violation: that hides the bug.
6. **VIEW — safety models only, and only if every checked invariant is a function of
   the view expression** (states equal under the view are checked as one). Example:
   `View == phase` with only phase-dependent invariants. With liveness, TLC accepts
   a VIEW silently and results are unreliable — no VIEW in models with `PROPERTY`.
7. **Check subsystems in isolation.** Stub the rest of the system as one nondeterministic
   environment action — but if the rest already has an external contract (section 2b),
   import that contract instead of hand-stubbing; stub only what has no spec yet.
   This is the L2/L1 decomposition paying off.
8. **Simulation instead of exhaustive**: `-simulate num=... -depth ...` explores long
   behaviors without the full graph. Not exhaustive — report it as simulation, not
   verification. For bounded-depth exhaustive search there is `-dfid N`
   (depth-first iterative deepening; no liveness support) — also a partial check,
   label it as such.
9. **Merge confluent actions**: if two orderings of independent local steps lead to the
   same abstract state, one atomic action is enough (only skip interleaving when the
   interleaving itself is the suspected bug).

## 6. Running TLC → tlc-run skill

Invocation mechanics live in the `tlc-run` skill: exact commands and flags,
cfg naming recap (tlc.cfg / <component>.tlc.cfg / variant names are defined
in section 6.1 there), result classification table (green vs violation
classes), exit codes, and the delegation protocol for launching runs via a
cheap background subagent (instruction template: workdir, command, what is
checked, expected output, report format, boundaries).

Still governed here (methodology): the workflow (section 1) — safety before
liveness, the coverage gate before stage transitions (section 6.3 below),
state budgets (section 5), and cfg authoring semantics (SPECIFICATION /
INVARIANT / PROPERTY / SYMMETRY rules, sections 3 and 5).

### 6.1 cfg models (naming and placement)

The cfg lives next to its .tla; names: `tlc.cfg` (single spec per dir),
`<module>.tlc.cfg` (shared dir), variants append the model kind before
`.cfg` (`tlc.live.cfg`, `tlc.impl.cfg`; shared-dir form:
`<module>.tlc.live.cfg`, `<module>.tlc.impl.cfg`). Component model pairs
(section 2b) name the modules `<component>External.tla` /
`<component>Internal.tla`. The pair's two modules normally sit in ONE
directory (section 8), where two bare `tlc.cfg` would collide — in that
case the cfgs take the `<module>.tlc.cfg` form (`queueExternal.tlc.cfg`,
`queueInternal.tlc.cfg`), exactly as in the section 8 layouts; the bare
`tlc.cfg` is legal only for a module alone in its directory. The variant
rule applies to BOTH modules of the pair — each runs the full section 1
workflow, liveness step included: each gets a `tlc.cfg` and a
`tlc.live.cfg` (the contract's guarantees for the external module, local
liveness for the internal one), and the internal module additionally gets
`tlc.impl.cfg` holding `PROPERTY Refines` onto the external contract. An
importer's composition model is just the importer's own `tlc.cfg` — the
imported contract's guarantees appear there as ordinary INVARIANT lines
(root aliases, 2b). The Heavy model (2b) uses the same variant scheme —
`<component>Heavy.tlc.cfg` (safety), `<component>Heavy.tlc.live.cfg`
(liveness), `<component>Heavy.tlc.impl.cfg` (refinement onto the
component's own External contract) — in the shared-dir form, since it
sits next to the pair. Constants are assigned in the cfg — never
by redefining inherited names in a wrapper module; `n1..n3` become model
values. Operator overrides use `<-` with a fresh name defined in the root
module. Keep variant cfgs per spec (N2/N3, lossy/faithful); bounds are
hypotheses — document every deliberate bound in a cfg comment.

### 6.3 Coverage gate (methodology)

A model is done only when the run is green AND every action fired (counts
come from `-coverage 1`; command lives in tlc-run). The gate blocks: safety
→ liveness, → refinement (separate cfg, separate gate), bound growth
(re-pass after each growth), simulation (cold in simulation = hard to
reach). Never proceed to the next stage with cold actions.
One expected exception (observed on TLC 1.8.0): a guarded `Terminal`
self-loop always shows zero fires — it generates no new distinct state —
while its second coverage number (times enabled) is non-zero; that is its
pass condition. Every other action must actually fire.

## 7. Pitfalls and anti-patterns

- `\E i \in Nat` / `Int` — infinite enumeration: error or explosion. Always `0..MaxX`.
- Bare identifiers as values (`{idle, wait}`, `kind: {req}`) — undefined operators;
  use strings or cfg model values.
- Reusing a quantifier binder name inside one formula — multiply-defined symbol.
- Fairness quantified over a variable-dependent set (`\A m \in msgs : WF_vars(...)`) —
  TLC rejects; use the constant domain (`Msgs`).
- An unguarded self-loop action (`/\ TRUE /\ UNCHANGED vars`) in `Next` to "fix"
  deadlock — silently disables deadlock checking everywhere; only a guarded
  `Terminal` is legitimate (section 3).
- Unparenthesized disjuncts in `Next`: `\E n \in S : A \/ B` parses as
  `\E n \in S : (A \/ B)`; the `B` branch is silently disabled whenever `S` is
  empty in that state (a terminal action hidden there never fires).
- Global clock/tick action — doubles every state, hides nothing. Use event timeouts.
- Modeling payloads, real data, real ids. Section 5.2.
- Sequence where a set suffices, when order is not part of the property (and the reverse:
  set where duplicates matter).
- `CHOOSE` for nondeterminism — deterministic in TLC, silently prunes behaviors. Use `\E`.
- Fairness of an `\E`-existential action instead of per-instance fairness (section 3).
- Gratuitous `SF_vars` — stronger than real systems; masks starvation.
- `UNCHANGED <<x>>` forgotten in one action — either a TLC error or an intended update
  silently dropped.
- SYMMETRY / CONSTRAINT / VIEW in any model with a `PROPERTY` line — silent or
  warning-only unsoundness. Safety cfg only (section 5).
- SYMMETRY on non-symmetric specs (fixed roles, comparisons, CHOOSE-min).
- CONSTRAINT to make a violation disappear — hiding a bug, not fixing it.
- Running the big model first. Always N2/N3 safety first, grow one parameter at a time.
- Checking liveness before safety is clean — wastes hours, hard to interpret.
- One spec per everything — levels exist precisely to prevent this.
- Internal variables (buffers, slots, pointers, worker phases) inside an
  external contract module (2b) — every importer inherits them in every
  state: state-space bloat plus a leaky abstraction. External modules carry
  interface observables only.
- Hand-writing another component's behavior inside an internal model instead
  of INSTANCEing its external contract (2b) — the copy silently diverges from
  the real contract, and that divergence is exactly the integration bug the
  model pair exists to catch.
- `INVARIANT Q!Fifo` as a cfg line — cfg resolves root-module operator names
  only; TLC stops with `The invariant Q specified in the configuration file
  is not defined in the specification`. Define a root alias
  (`QFifo == Q!Fifo`) and check the alias (2b).
- INSTANCEing another component's internal module — importers see the
  contract, never the implementation (2b). One exception — the Heavy model
  (2b), whose entire purpose is full-detail composition and which exists
  only under its generation trigger.
- Believing `-simulate` or `-dfid` coverage is verification. They are bug-hunting /
  bounded checks — label results accordingly.
- If exhaustive checking is impossible even after the full ladder, state it explicitly
  in the spec header and TODO.md (loud), and record which bounded/simulation checks
  were run instead — never present them as full model checking.

## 8. Repository layout (mirrors the spec-skill conventions)

```
Small project (single spec):
  <library>.tla         \* the spec module, named after the library
  tlc.cfg               \* default (safety) model, next to the spec
  (+ tlc.live.cfg, ... variants)

Medium project (several specs):
  specs/queue.md        \* spec in specs/ directory
  specs/TLA/            \* TLA directory co-located with the spec
    queueExternal.tla           \* contract model of the queue (2b)
    queueExternal.tlc.cfg       \* standalone contract safety
    queueExternal.tlc.live.cfg  \* contract liveness
    queueInternal.tla           \* buffer implementation (2b)
    queueInternal.tlc.cfg       \* internal safety
    queueInternal.tlc.live.cfg  \* internal local liveness
    queueInternal.tlc.impl.cfg  \* PROPERTY Refines onto queueExternal
    queueHeavy.tla              \* full-detail composition (2b): only on
                                \* request / if Heavy exists for other components
    queueHeavy.tlc.cfg          \* heavy safety
    queueHeavy.tlc.live.cfg     \* heavy local liveness
    queueHeavy.tlc.impl.cfg     \* PROPERTY Refines onto queueExternal
  specs/storage.md
  specs/TLA/
    storageExternal.tla
    storageExternal.tlc.cfg
    storageInternal.tla
    storageInternal.tlc.cfg
    (+ the pair's variant cfgs, as for queue above)

Large project / multi-library monorepo (colocated specs):
  lib/<component>/<component>External.tla   \* contract lives with its component
  lib/<component>/<component>External.tlc.cfg
  lib/<component>/<component>External.tlc.live.cfg
  lib/<component>/<component>Internal.tla   \* implementation, same directory
  lib/<component>/<component>Internal.tlc.cfg
  lib/<component>/<component>Internal.tlc.live.cfg
  lib/<component>/<component>Internal.tlc.impl.cfg
  lib/<component>/<component>Heavy.tla     \* full-detail composition (2b),
                                            \* only on its generation trigger
  lib/<other-component>/...                \* importers INSTANCE only the
                                            \* External modules of others
                                            \* (classpath, see below)
```

**TLA directory placement:** the `TLA/` directory is created at the **same level as the spec** being modeled. For a spec at `specs/queue.md`, the TLA directory is at `specs/TLA/`. For a spec at `SPEC.md` (root), the TLA directory is at root level (`TLA/`). This co-location keeps TLA files tightly coupled to the spec they model and matches the single-spec-per-level decomposition rule.

- Shared helpers (`Utils.tla`) sit in the TLA/ directory of each spec or in a shared `TLA/Utils.tla` at the spec's level if multiple specs share them. For colocated layouts, put the directories on the classpath (command in the tlc-run skill) so INSTANCE resolves.
- `tla2tools.jar`: pinned version at the repo root or at the TLA/ level (or a documented download); a Makefile with `check` / `live` / `sim` targets is recommended for medium+.
- `.gitignore`: `states/`, `*.log`, `*_TTrace_*.tla`.
- Baselines: README (or per-spec header comments) lists property -> model ->
  last run (states, diameter, time, verdict). When a counterexample is found,
  record model, property, and the shape of the trace.

`TLA/index.md` — minimal list, one line per spec, no statuses:

```markdown
# TLA Specification Index

- specs/TLA/queueExternal.tla — queue contract: FIFO/no-loss interface guarantees (external, L0 view)
- specs/TLA/queueInternal.tla — queue ring-buffer implementation (internal, L2; refines queueExternal)
- specs/TLA/queueHeavy.tla — queue full-detail composition (heavy, L2; refines queueExternal)
- lib/storage/tla/storageExternal.tla — storage contract (external)
```

Index rules (as in the spec skill): every spec is indexed — colocated ones
are the classic leak, audit them explicitly; the index updates in the same
commit as any spec create/move/delete; never index a nonexistent path.
Abstraction levels (section 2) map onto entries: e.g. `specs/TLA/system.tla`
(L0), `specs/TLA/consensus.tla` (L1), `specs/TLA/worker.tla` (L2) — mention the
level in the index line; for component model pairs (2b) also mark the role
(external/internal), naming what the internal entry refines; Heavy entries
are marked (`heavy`) like the external/internal roles. INSTANCE
references between specs use module names natively, no extra link
bookkeeping is required.

## 9. Mathematical proofs → TLAPS skill

Default tool is TLC: finite-model evidence, not proof. When the user explicitly asks
for a *mathematical proof* ("prove", "proof", "for all N") or the property is
inherently unbounded (arbitrary node count, unbounded data), switch to the `tlaps`
skill (tlapm + z3): proof language, backend selection, refinement proofs, failure
triage. Keep TLC as the bounded first pass even when a proof is the goal — a quick
counterexample beats a failing proof.
