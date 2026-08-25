---
name: spec
description: Use when writing, updating, or reviewing project specifications (SPEC.md, specs/<component>.md, specs/index.md, specs/GLOSSARY.md, or colocated <library>/<component>/SPEC.md), when the user requests any change to functionality, behavior, or constraints (spec-first flow: spec before code), when checking related specs for collisions, or when implementing code against an existing spec. Use ONLY for specification documents and spec-driven changes, not for READMEs or general docs.
---

# Project specifications: authoring, layout, change flow

A specification fixes how algorithms, functions, components, and systems behave:
their interfaces, semantics, constraints, and error handling. The spec is the
source of truth: implementation code follows the spec and never contradicts it.
Behavior found in code but absent from the spec is either a spec gap (fix the spec)
or a bug (fix the code) — never silently tolerated.

## 1. Core rules (non-negotiable)

1. **Spec-first change flow.** A request to change functionality is a request to
   change the spec first. Order: locate the governing spec → update it → check
   related specs for collisions (section 5) → only then implement. Commits that
   change behavior must touch the spec in the same change (or reference the spec
   section that already prescribes it).
2. **No contradictions.** Code may not diverge from its spec. If implementation
   constraints force a deviation, stop and surface the conflict to the user:
   changing the spec is a decision, not a side effect of coding.
3. **One canonical spec per component.** Never keep two specs of the same thing;
   link from auxiliary documents to the canonical spec.
4. **Index is always current.** In any project that has an index per section 2,
   every create/update/move/delete of a spec file updates `specs/index.md` in the
   same commit.
5. **Conflicts between specs stop the work.** If a spec change contradicts another
   spec and the resolution is not obvious, report both statements to the user and
   pause; do not pick a winner silently.

## 1b. Workflow for spec authoring (when using the spec skill)

When authoring or updating a specification with the `spec` skill, follow this
two-step agent delegation workflow:

1. **Research with assistant_cheap.** Use the `assistant_cheap` researcher agent
    (on glm-4.6v) to read the relevant specs, sources, and documentation.
   The agent should save references to useful documents with exact line ranges
   in a temporary draft file (e.g. `specs/draft.md` or a working copy in the
   project root). The draft should contain:
   - Links to source files or URLs with line number ranges
   - Brief summaries of each document's relevance
   - Noted conflicts or ambiguities between documents
   - Gaps in documentation that need to be addressed in the new spec

   The draft file is created locally for the author to review; it is NOT part
   of the final commit and is not committed to the repository until explicitly
   approved.

2. **Generate with assistant_max.** Once the research draft is ready, use the
   `assistant_max` agent (on vk-zai-personal/flash with reasoningEffort max) to
   author or update the specification according to the templates and writing
   rules in sections 3-4. The draft file serves as the source of truth for
   references and gaps; the spec generation should cite specific requirement
   IDs, maintain bidirectional links (Dependencies/Used-by), and follow the
   layout and format rules.

3. **Cleanup.** After the spec is generated and all checks (section 5) are
   passed, remove or move the draft file out of the repository root and
   archive it (e.g. under a `specs/drafts/` directory with a timestamp or under
   `.gitignore`). The draft is not part of the final specification and should
   not be committed unless explicitly included as documentation of the authoring
   process (which is allowed only when the draft contains significant
   methodology or rationale that is valuable for future reference).

This workflow ensures that the authoring process leverages the research
capabilities of assistant_cheap (cheap, read-only, reasoning-heavy) before
moving to the high-effort spec writing with assistant_max, keeping the draft
ephemeral and easily deletable.

## 2. Layout by project size

| Project | Spec location | Index |
|---|---|---|
| Small (single component) | `SPEC.md` in the repo root | none |
| Larger (several components/features) | `specs/<component-or-feature>.md` | `specs/index.md` |
| Multi-library monorepos | colocated `<library>/<component>/SPEC.md` — allowed, but MUST be indexed in `specs/index.md` | `specs/index.md` |

The specs/ tree of any multi-component project carries two cross-cutting
files: `specs/index.md` (section 3) and `specs/GLOSSARY.md` (section 3a) —
both maintained in the same commits as the specs they describe.

Rules:
- Growing past "small": when a second component boundary appears or root SPEC.md
  exceeds ~300 lines, split into `specs/` with an index; the root SPEC.md content
  moves to `specs/<component>.md` files (do not keep duplicated content — a
  one-line pointer stub at the old path is allowed if the path is widely
  referenced).
- Colocation threshold: allowed once the repo hosts multiple independently
  versioned libraries (their components live far from a central specs/ tree);
  a single-library repo keeps everything under specs/.
- In mixed layouts (some colocated, some centralized) the index is the single
  discovery point: it must list every spec regardless of where the file lives.
- Never index a path that does not exist, and never leave an existing spec
  unindexed (colocated specs are the classic leak — audit them explicitly).

## 3. specs/index.md format

```markdown
# Specification Index

| Path | Reference | Status | Summary |
|---|---|---|---|
| specs/auth.md | auth | stable | Token issuance, refresh, validation |
| specs/queue.md | queue | draft | Persistent queue delivery guarantees |
| lib/storage/SPEC.md | lib-storage | stable | Disk layout and compaction contract |
```

- `Status`: `draft` (being designed; may change freely — code may follow it
  provisionally, but deviations are not yet bugs) | `stable` (implemented,
  binding — code/spec divergence is a finding).
- No `deprecated` status: superseded specs (or their obsolete parts) are
  DELETED or rewritten in place under the new requirements — never kept for
  reference. The index row is removed in the same commit; if a successor spec
  exists, the old path is not kept as a stub. History lives in git and in
  DEVIATIONS.md (section 6), not in living spec files.
- `Summary`: one line, nouns only — what is fixed, not how.
- `Reference` is the stable ID other specs cite instead of file paths (section
  4 writing rules) and the mandatory prefix of every term ID (section 3a). It
  must include the component or library name and may be composite
  (`library-component`, e.g. `yt-core-bus`); use the composite form whenever
  the bare component name is ambiguous across libraries. Reference IDs are
  unique, lowercase, and stable — renaming one means updating the index, every
  referencing spec's Dependencies, and every term ID carrying the prefix
  (GLOSSARY.md and spec texts) in the same commit.
- Optional extra columns (owner, last-updated) are fine if the team maintains
  them; a stale extra column is worse than no column.

## 3a. specs/GLOSSARY.md format

```markdown
# Specification Glossary

| Term | Definition | Defined in |
|---|---|---|
| auth/token | Opaque credential authenticating a request | auth (R2) |
| queue/ack | Positive delivery confirmation from a consumer | queue |
| queue/lease | Exclusive time-bounded ownership of a message | queue |
```

- Every term is a full ID `<reference>/<term>` (e.g. `yt-core-bus/connection`),
  strictly English, at every occurrence — glossary, Definitions sections,
  requirement text. The prefix must equal an existing reference from
  specs/index.md; the bare short form (`connection`) is never used.
- Alphabetical order by full term ID, always — a glossary is looked up, not
  read.
- One row per term ID. `Defined in` cites the owning reference — which must
  equal the term's prefix — optionally with requirement IDs; never a file path.
- The glossary is the canonical place where "which spec owns which term" is
  visible; a term introduced by a spec (its Definitions section) gets a row in
  the same commit. Terms reused from another spec (writing rules, section 4)
  do not get a second definition — their row keeps pointing at the owning spec.
- One meaning per term ID across the project. The prefix keeps references
  from colliding: `queue/lease` and `auth/lease` are distinct terms and may
  coexist. Within one reference a term ID is defined once; if two references
  define the same short name for the same concept, reuse the owner's full ID
  instead of duplicating it (shared-vocabulary check, section 5).
- Updated together with the index: spec create/delete/rename updates both files
  in the same commit. A glossary row citing a deleted reference — or a term
  prefix that no longer resolves — is a dangling reference; resolve or remove
  it immediately.
- Small single-SPEC.md projects: a short Definitions section inside SPEC.md
  suffices, using the same full-ID form (the reference is the component name
  declared in the spec header); introduce GLOSSARY.md when the specs/ tree
  appears.

## 4. Spec file template

```markdown
# <Component> Specification

Status: stable | draft
Spec source of truth for: <component / feature name>

## Overview
One paragraph: what this component does and why it exists.

## Scope
In: <explicit list of responsibilities>.
Out (non-goals): <what this component deliberately does not do>.

## Definitions
Terms used with precise meaning, each a full ID `<reference>/<term>` (e.g.
yt-core-bus/connection); English only.

## Interface
Signatures, endpoints, CLI verbs, message schemas, config keys — the
externally observable contract. Every element named and typed. Config-key
names and types live here; allowed values and effect live in Configuration.

## Configuration
Mandatory when the component has configurable parameters, named
constants, or magic numbers (writing rule below); omit the section only
if it has none of the three. One row per entry — allowed values and
effect. Three kinds of rows, always distinguishable: a parameter (keyed
by config key; type/bounds/enum/step, default, effect); a named
constant — a value baked into the code under an identifier
(`MAX_RETRIES`) — keyed by that identifier, its single value with units
marked `fixed`, no default; and a magic number — a bare literal in the
code with no identifier (`3`, `60000`) — keyed by the literal with
units plus the behavior it participates in (there is no name to cite),
its single value marked `magic`, no default:

| Name | Allowed values | Default | Effect |
|---|---|---|---|
| `batch_timeout` | integer, 0..60000 ms, step 100 | 100 ms | Coalescing window (R4); at 0 coalescing is disabled; above 10000 ms the window fills only when `max_batch_size` >= 2 |
| `mode` | enum: strict, lenient | strict | `strict` rejects unknown keys (R7); `lenient` logs and skips them |
| `MAX_RETRIES` | `fixed` 3 attempts | — | Delivery retries before dead-lettering (R3) |
| `60000` ms, `batch_timeout` upper bound | `magic` 60000 ms | — | Values above 60000 ms are rejected as out of range (R4) |

## Behavior
Numbered requirements, each testable, each with a stable ID:
- R1. On `put(k, v)` where k exists, the old value is replaced atomically.
- R2. A key expires after TTL seconds; reads of expired keys return NOT_FOUND.
Sequencing rules, ordering guarantees, algorithm semantics (steps or
invariants, not code).

## Constraints
Hard limits and invariants: capacity, latency budgets, compatibility
(versions, formats), security, environment assumptions.

## Error handling
Error classes, codes, retry semantics, partial-failure behavior.

## Dependencies
Specs whose terms, interfaces, or constraints this spec uses or constrains
(semantic links — see writing rules). Cite by reference ID from the index,
optionally citing specific requirement IDs:
- auth (R2, R5) — auth/token format reused in message authentication
- queue — queue/lease term adopted in Definitions

## Used by
The reverse side of Dependencies, maintained in the referenced specs: every
spec listed above must list this reference in its own Dependencies (with the
same meaning stated from its side). Populated by the referencing spec's
change, same commit:
- lib-storage (R4) — validates message authenticity via this spec's
  auth/token format

## Verification
One entry per verified algorithm (a spec may describe several — always name
the exact one). Recorded when the algorithm is checked with TLC/TLAPS; see
the tla-plus / tlaps skills for run rules.
- Algorithm: lease-based leader election (R3-R7)
  Tool: TLC 1.8.0; model TLA/consensus.tla + tlc.cfg (Nodes = 3, MaxTerm = 2)
  Level: L1 protocol — message loss/duplication and crash/recover modeled;
    node internals abstracted as atomic phases
  Checked: safety Inv1 (at most one leader), deadlock-freedom, liveness
    elected ~> leading under weak per-node fairness
  Not checked: Nodes > 3; Byzantine faults (crash only); no TLAPS proof
```

Writing rules:
- **Cross-spec references use reference IDs, never file paths.** The only
  valid way to cite another spec is its `Reference` value from specs/index.md
  (e.g. `auth`, `yt-core-bus`) — paths break when files move between root
  SPEC.md, specs/, and colocated layouts; reference IDs are the stable IDs.
  This rule holds everywhere: Dependencies sections, Definitions, requirement
  bodies.
- **Terms are full IDs, strictly English.** Every term is written as
  `<reference>/<term>` (e.g. `yt-core-bus/connection`) at every occurrence —
  Definitions, requirement bodies, constraints, GLOSSARY.md; the short form is
  never used. Term IDs are English whatever the spec's language is (language
  rule below). The prefix must resolve to an existing reference (from
  specs/index.md, or the component name declared in the spec header in small
  projects without an index).
- **Reusing terms from another spec is allowed** and preferred over
  redefining: use the owner's full ID verbatim (e.g. `queue/lease` — the
  prefix records the origin; never strip or rewire it) and make sure the
  source spec is listed in Dependencies.
- **Links are semantic, bidirectional, and exact.** A Dependencies entry
  exists only while this spec actually uses the other's terms, interfaces, or
  constraints in its normative content (requirements, definitions, interface)
  — not for historical or "related" mentions. Every link has two ends,
  written the same commit: A's `Dependencies` names B, and B's `Used by`
  names A. When the semantic use disappears (requirement dropped or
  rewritten, term replaced), the link is removed from BOTH sides in the same
  commit — never leave one-sided or stale "just in case" links.
- Statements are declarative and testable: "must", "never", "exactly once".
  If a requirement cannot be falsified by a test, it is a note, not a requirement.
- Stable IDs (R1, R2, ...) are referenced by code comments, tests, and commits;
  never renumber — retire IDs (drop the statement, note the retirement in
  DEVIATIONS.md) instead.
- Include concrete input→output examples for every nontrivial rule.
- Record algorithms as behavior (steps, invariants, complexity bounds), not as
  implementation (no source files, class names, or private helpers).
- **Configuration section is mandatory when configurable parameters,
  named constants, or magic numbers exist** (template section above).
  Whenever the component exposes at least one configurable parameter —
  config key, flag, env var, tuning knob, whatever the delivery
  mechanism — or bakes a fixed value into its behavior (timeout, limit,
  threshold, buffer size, retry count, and the like — fixed in code,
  not tunable at runtime), the spec has a Configuration section with
  one entry per parameter or fixed value; a spec without the section
  asserts the component has none of them — no parameters, no named
  constants, no magic numbers — and the small-spec section collapse
  does not waive it. Fixed values come in two kinds, distinguishable in
  the table: a named constant — the value lives in the code under an
  identifier (`MAX_RETRIES`) — keyed by that identifier, its single
  value with units marked `fixed`, no default; and a magic number — a
  bare literal with no identifier (`3`, `60000`) — keyed by the literal
  with units plus the behavior it participates in (there is no name to
  cite), its single value marked `magic`, no default. Each entry
  states: (a) allowed values — for a parameter: type, range bounds or
  enum members, discreteness (step), default, units where applicable;
  for a fixed value of either kind: its single value with units and its
  `fixed`/`magic` marker — no default, nothing to choose; (b) effect —
  for a parameter: what differs at different values, boundary cases at
  the extremes, interactions with other parameters when they exist; for
  a fixed value: what its value causes — what happens when the timeout
  elapses, the limit is hit, the count is exhausted. The behavior
  itself stays in Behavior requirements; the entry cites their IDs
  instead of restating them. A limit the component itself enforces
  through a baked-in value is a fixed value recorded here, not a
  Constraints entry — Constraints keeps externally imposed budgets and
  invariants.
- Sections may be collapsed in small specs; keep the header (Status, scope,
  IDs) and the section names stable across the project.
- Language: follow the project's existing spec language; for the first spec in
  a project, use the user's language. Do not mix languages within one file.
  Terms are the exception: term IDs are always English (full-ID rule above),
  whatever the spec's language is.
- The spec states the CURRENT requirements only: when requirements change,
  rewrite or delete the obsolete statements — no strikethrough archives inside
  spec files (behavior deltas belong in DEVIATIONS.md, section 6).
- **Verification entries (template section above)**: a spec section that
  describes algorithms gets a `Verification` section when any of them is
  checked with a formal tool. Rules:
  - Name the exact algorithm (never "the algorithm" when the spec defines
    several); cite its requirement IDs.
  - State the abstraction level of the CHECK (tla-plus levels L0/L1/L2 or a
    custom description) and what that level abstracts away — the level of the
    verification, not of the spec.
  - `Checked` claims exactly what the run established: TLC = bounded evidence
    (record model bounds); TLAPS = proof (record the proof module). Never
    write "verified" for what TLC only sampled within bounds.
  - `Not checked` is mandatory — the deliberate gaps (bounds not explored,
    fault classes not modeled, liveness skipped, no proof). An entry without
    a Not-checked list overstates the result.
  - A behavior change to a verified algorithm invalidates its entry: either
    re-run and update, or drop the entry (and say so in the DEVIATIONS.md
    record for that change). A stale entry claiming verification of behavior
    that no longer exists is worse than no entry.

## 5. Post-change consistency check (always, before implementing)

After editing any spec, run this pass over the *related* specs (found via the
index, Dependencies sections, and shared vocabulary):

1. **Shared identifiers**: names, term IDs, message fields, config keys, error
   codes, units (ms vs s), versions — same name must mean the same thing
   everywhere.
2. **Direct contradictions**: one spec requires what another forbids
   (ordering, defaults, error semantics, limits).
3. **Counterpart drift**: producer-side spec adds a field/state/flag the
   consumer-side spec does not mention; a spec starts depending on a
   constraint another spec dropped.
4. **Duplicate definitions**: the same rule now stated in two specs — reduce
   to one canonical statement and link from the other.
5. **Reference resolution**: every reference ID cited in Dependencies or
   Definitions, and every term prefix used by the changed spec, exists in
   specs/index.md; a renamed/deleted reference leaves no dangling citations or
   orphaned prefixes (paths in citations are themselves a finding). Same for
   specs/GLOSSARY.md: rows must cite existing references (matching the term's
   prefix), stay alphabetical by full ID, be strictly English, and cover every
   term the changed spec introduced or stopped using.
6. **Link symmetry and semantic validity**: every Dependencies entry in the
   changed spec has the matching Used-by entry in the referenced spec (and
   vice versa for specs whose Used by lists the changed reference); each
   surviving link still has a live semantic basis — trace it to the concrete
   requirement, definition, or interface element that uses it; a link whose
   basis was deleted or rewritten away is removed from BOTH specs.
7. **Verification staleness**: if the change touches requirements cited by a
   Verification entry (the algorithm's behavior), the entry no longer holds —
   re-run the check and update the entry, or remove it; note the verification
   impact in the DEVIATIONS.md record.
8. **Configuration coverage**: every parameter the change makes
   configurable (or re-tunes) and every fixed value it introduces or
   alters — named constant or magic number — has a Configuration entry
   with both allowed values (the `fixed`/`magic` single value) and
   effect (section 4); entries citing requirement IDs that changed or
   were retired are updated in the same commit.

Resolution: fix the related spec when the fix is mechanical (renames,
reference updates, counterpart mentions). Stop and ask the user when both
statements look intentional — that is a design conflict, not a typo.

## 6. DEVIATIONS.md: the change ledger

Every spec modification that changes BEHAVIOR (not typos, formatting, or pure
wording) is recorded in `DEVIATIONS.md` (root, small projects) or
`specs/DEVIATIONS.md` (projects with a specs/ tree). Purpose: after the spec
changes, this file answers "what code must be reworked, and what should a
reviewer of that code check". A behavior-changing spec edit without a
DEVIATIONS.md entry is incomplete — same commit.

Entry format (append at the end; newest last):

```markdown
## D-007 2026-08-25 specs/queue.md
Change: R3 delivery retries changed from fixed 3 attempts to exponential
  backoff, unbounded until ack or lease expiry.
Was: max 3 retries, then dead-letter.
Now: retry with 1s doubling backoff while message lease is held.
Code impact: retry loop in queue/worker.go must drop the attempt counter and
  respect lease deadline; dead-letter emission moves to lease-expiry path.
Tests: retry-count test (queue_test.go) invalidated — replace with
  backoff-timing and lease-deadline tests.
Review focus: unbounded retry cannot outlive the lease; dead-letter is emitted
  exactly once per message.
```

Rules:
- One entry per behavior change, stable ID (D-1, D-2, ...; never renumber).
  Cite the spec requirement IDs it touches (R3 above).
- `Code impact` names the places to rework — files/modules are allowed HERE
  (unlike the spec itself), because this ledger exists to drive code changes.
- `Was`/`Now` states observable behavior, not implementation.
- `Review focus` lists what a code reviewer must verify for compliance with
  the NEW spec — the checks that would not exist without this change.
- Entries are never edited after the fact; corrections get a new entry
  referencing the old one.
- **Entry lifecycle ends with conformance**: once the code matches the new spec
  (implementation landed, tests updated and green), the entry is DELETED from
  DEVIATIONS.md — in the same commit as the conforming code change, not later.
  DEVIATIONS.md contains only open code-vs-spec divergences; it is a live
  worklist, never an archive of applied changes (that history lives in git).
- Small projects may start with DEVIATIONS.md in the root even before any
  specs/ tree exists.

## 7. Code ↔ spec compliance

- Implementing from a spec: cite requirement IDs (commit message or PR text).
  A test per requirement ID is the default expectation.
- Implementing a DEVIATIONS.md entry: cite its D-ID; when the change makes the
  code conform to the new spec, remove the entry in that same commit
  (section 6 lifecycle).
- Encountering unspecified behavior while coding: do not improvise silently —
  either extend the spec (obvious gap, mechanical) or ask.
- Never edit a spec to retroactively match what the code already does without
  flagging it: that rewrite is the diff between "intended" and "actual" and
  must be visible to the user.
- Reviewing code against a spec: any behavior without a backing requirement is
  a finding (spec gap or bug), reported, not skipped.
- Reviewing code that implements a deviation: walk the entry's `Review focus`
  list explicitly before approving.

## 8. Anti-patterns

- Code change shipped with no spec change (drift; the spec stops binding).
- Two specs of one component (root SPEC.md + specs/copy, centralized + colocated)
  — one canonical, the other a pointer.
- Colocated `<library>/<component>/SPEC.md` missing from the index.
- Index rows for deleted/moved files; stale Status values.
- Keeping superseded/obsolete specs or spec parts "for reference" — delete or
  rewrite them (section 3); history lives in git and DEVIATIONS.md.
- Strikethrough archives or change logs inside spec files — the spec states
  current requirements only; behavior deltas go to DEVIATIONS.md.
- Behavior-changing spec edit without a DEVIATIONS.md entry.
- DEVIATIONS.md as an archive: entries surviving after the code conforms
  (section 6 lifecycle) defeat its purpose as a worklist.
- Renumbering requirements (breaks external references) — retire IDs instead.
- Citing another spec by file path instead of its index reference ID — the
  reference breaks on the first file move (section 4 writing rules).
- Bare or non-English terms: `connection` instead of `yt-core-bus/connection`,
  a translated term, or a prefix naming no reference in the index — the full
  English ID is mandatory at every occurrence (sections 3a, 4).
- Using a term from another spec without listing that spec in Dependencies.
- specs/GLOSSARY.md out of sync: missing rows for introduced terms, dangling
  rows for deleted references, `Defined in` disagreeing with the term prefix,
  broken alphabetical order, or two definitions of one term ID.
- One-sided links: A cites B in Dependencies but B's Used by lacks A (or the
  link was removed from one side only when the semantic use ended).
- Formal links without semantic basis — "related specs" entries kept for
  history or courtesy; the tie must trace to a live requirement, definition,
  or interface element or be deleted from both sides.
- "Verified"/"tested" claims about algorithms with no Verification entry, or
  entries that: name no specific algorithm (in a multi-algorithm spec), state
  no abstraction level, omit the Not-checked list, claim proof for bounded
  TLC evidence, or survive a behavior change to the algorithm.
- Spec as narrative prose with no testable statements or IDs.
- Spec detailing private implementation (locks refactoring into the contract).
- Mixing units/naming with sibling specs (the shared-vocabulary check exists
  for this).
- A configurable parameter, named constant, or magic number with no
  Configuration entry — or an entry missing allowed values (type,
  bounds or enum, default, units; the `fixed`/`magic` value for a fixed
  value) or the behavioral effect — is an undocumented knob or buried
  magic number and a spec gap (section 4).
- Conflating the two fixed-value kinds: a magic number recorded as
  `fixed` under a name the code does not have (or a named constant
  demoted to a nameless literal row). A `magic` row keyed by the
  literal records what the code actually carries — a nameless value;
  promoting it to a named constant is a code change, and only then does
  its row become `fixed` keyed by the identifier.
- Resolving a spec-vs-spec contradiction by editing one side quietly.
