---
name: docs
description: Use when writing, updating, or restructuring project documentation (docs/ directory, docs/index.md, component-level documents, architecture, configuration, principles, deployment, external-dependency docs), when a functionality change requires refreshing affected docs plus the index in the same change, or when the user asks to explain how a complex system works, its architecture, capabilities, limitations, or configuration as lasting documentation. Use ONLY for human-facing documentation; not for specification documents (spec skill), not for READMEs, not for TLA+ or other formal artifacts (tla-plus / tlaps / tlc-run skills).
---

# Project documentation: writing for human readers

Premise: this skill governs documentation for projects whose code is too complex
for a human to understand by direct reading. The documentation REPLACES code
reading, not duplicates it. After reading it, a human must understand:

- how the system works at a high level;
- how the architecture is structured;
- what capabilities and limitations the system has;
- how the system is configured.

Documentation may cover a single component or the whole system; a whole-system
documentation set may consist of several files (section 5).

## 1. Core rules (non-negotiable)

1. **The audience is a human.** Every document is written to be read: logical
   structure, coherent in meaning and in narrative flow — each section builds on
   the previous one, terms are introduced before use, nothing requires knowledge
   the document did not provide or point to.
2. **Docs replace code reading, never retell it.** No line-by-line or
   function-by-function walk-throughs of the code. The code is precisely the
   thing a human cannot profitably read directly; the document states behavior,
   structure, decisions, and rationale in its own words.
3. **Explain "why", not only "what".** Every nontrivial design carries its
   rationale: what constraint forces it, what alternative was rejected and why.
   A document that states facts without reasons forces the reader to reverse-
   engineer intent from the code — the exact thing the document exists to
   prevent.
4. **Annotation and References are mandatory** in every document (section 4) —
   no exceptions for "small" files.
5. **Docs and index are always current.** Any change to functionality updates
   the affected documents and `docs/index.md` in the same change (section 8).

## 2. When to use (workflow)

Use this skill when the user asks to: write or update project documentation;
create or refresh `docs/index.md`; document a component or the whole system;
capture an explanation (architecture, configuration, deployment) as a lasting
`docs/` file rather than a chat reply.

Workflow:

1. **Determine scope.** One component (colocated doc, section 3) or the whole
   system (multi-file set, section 5). Ask only if the request cannot be
   resolved from the project layout and the user's wording.
2. **Read before writing.** Read `docs/index.md` and the documents adjacent to
   the topic (via the index and their References sections); read the governing
   specs (spec skill layout) — documentation never contradicts a spec.
3. **Choose location and structure** (sections 3-5); create or update the
   document(s) with mandatory annotation and References.
4. **Update `docs/index.md`** in the same change (section 6).
5. **Run the freshness and consistency pass** (section 8) before finishing.

## 3. Location

- Whole-project and cross-component documents: `docs/` at the project root.
- A component's own document: `docs/` inside the component's directory — ONLY
  when explicitly specified (by the user, or by the project's already-existing
  colocated layout). Do not invent colocated docs proactively.
- **`docs/index.md` is always at the project root**, even when component
  documents live in component-local `docs/` directories: it is the single
  discovery point and lists every document regardless of where the file lives.

```
<project>/
  docs/
    index.md                  <- always, project root docs/
    principles.md
    architecture.md
    ...
  components/
    queue/
      docs/queue.md           <- only when explicitly requested
```

Rules: never index a path that does not exist; never leave an existing document
unindexed (colocated component docs are the classic leak — audit them
explicitly); do not scatter loose `*.md` documents outside `docs/`.

## 4. Document structure (mandatory elements)

Every document, any size, starts with two mandatory elements:

1. **Annotation** — at the very top, before the body: what the document covers
   and who it is written for (an integrating newcomer, an operator deploying
   the system, a developer extending the component). A document without a
   stated audience cannot be checked for serving it.
2. **References** — a separate section near the top listing the other documents
   and RFCs required to understand the text, each with a one-line note on what
   it contributes. The reader must not discover prerequisites by hitting an
   unexplained term midway.

Then the body sections. Suggested skeleton (sections collapse only for very
small documents; the two mandatory elements never collapse):

```markdown
# <Component / System> — <what it is>

**About this document:** covers <scope>; written for <audience>.

## References
- docs/principles.md — base principles assumed throughout
- RFC-7 — rationale for the lease protocol used here

## Overview
What this is and why it exists — the high-level picture first.

## How it works
The mental model: main flows, lifecycle, interaction between parts.

## Architecture
Parts and their responsibilities, boundaries, how they communicate.

## Capabilities and limitations
What the system can do; hard limits and what they follow from.

## Configuration
How the system is configured: sources, keys, defaults, effects.
```

Writing order: sections follow the reader's needs, not the source tree's file
order — the reader has not seen the source tree.

## 5. Whole-system documentation (multi-file)

A whole-system documentation set is split by concern when it does not fit one
document. Canonical split (indicative, not exhaustive — add files by concern,
not by module):

- `docs/principles.md` — base principles: the invariants and decisions that
  hold across the whole system;
- `docs/architecture.md` — architecture: components, boundaries, interactions;
- `docs/configuration.md` — configuration: sources, precedence, keys, effects;
- `docs/deployment.md` — deployment manual: environments, rollout, recovery;
- `docs/external-dependencies.md` — dependencies on external systems: what is
  relied on, what breaks when they degrade.

Each file is a complete document (section 4) with its own annotation and
References; cross-links between the files carry the coherence of the set. One
concern lives in one file — the same topic is not re-explained in a sibling
file; siblings link instead of duplicating.

## 6. docs/index.md

One row per document, with a short note on what the document is about:

```markdown
# Documentation Index

| Path | Summary |
|---|---|
| docs/principles.md | Base principles holding across the system |
| docs/architecture.md | Components, boundaries, interactions |
| docs/configuration.md | Configuration sources, keys, precedence, effects |
| docs/deployment.md | Deployment manual: environments and rollout |
| docs/external-dependencies.md | External systems relied upon |
| components/queue/docs/queue.md | Queue component: behavior, limits, tuning |
```

Rules:

- Every document is indexed, colocated ones included; `Summary` is one line —
  what the reader gets, not the file name restated.
- The index updates in the same change as any document create / update / move
  / delete. A stale index (missing row, row for a deleted path) is a finding.
- The index lists documents only — not specs, not README, not TLA+ artifacts
  (those have their own indices under their own skills).

## 7. Style rules

- **Write for a human.** Sentence-level clarity first: no unexplained jargon,
  no bullet lists where a connected explanation is needed, no walls of bullets
  where cause and effect matter. Prose carries reasoning; lists carry
  enumerations.
- **Coherence across the document and across the set.** Terms mean one thing
  everywhere; a term used here is defined here or in a Referenced document.
- **Explain why.** Rationale, constraints, rejected alternatives — a reader
  must be able to tell a deliberate decision from an accident.
- **No code retelling.** Do not walk the reader through files, classes, or
  functions; do not narrate control flow of the implementation. State the
  observable behavior, the structure, and the reasoning. Code excerpts appear
  only to pin down an interface or a configuration example — never as a
  substitute for explanation.
- **Behavior, not implementation detail.** Private helpers, file layout, and
  internal names appear only when the reader must know them (e.g. deployment),
  and then with the reason.
- **Current state only.** Documents describe the system as it is now; change
  logs and superseded text do not live in docs (history lives in git).
- **Language:** follow the project's existing documentation language; for the
  first document in a project, use the user's language. Do not mix languages
  within one file.

## 8. Freshness: docs and index always current

Whenever functionality changes (by the user's request or an agent-driven
change), before finishing:

1. **Find every affected document** — via `docs/index.md`, the References
   sections of nearby documents, and grep over `docs/` for the changed
   concepts. Colocated component docs are checked explicitly.
2. **Update content** of each affected document: behavior, architecture
   claims, capabilities/limitations, configuration entries — whichever the
   change touches. Obsolete statements are rewritten or deleted, never left
   "for reference".
3. **Update `docs/index.md`** in the same change: rows for created/deleted/
   moved files, refreshed summaries when a document's scope shifted.
4. **Consistency pass:** no document contradicts another document or a
   governing spec; every link and Referenced path resolves; every annotation
   still describes its document accurately.

A functionality change that ships without updating the affected docs and the
index is incomplete — same standard as code without tests.

## 9. Boundaries (do not use this skill)

- **Specification documents** — `SPEC.md`, `specs/`, requirement IDs, spec-first
  flow: use the `spec` skill. Documentation never duplicates spec content; it
  links to the spec. If a docs request collides with a spec, the spec is the
  source of truth — report the conflict, do not resolve it silently in docs.
- **README** — never create, edit, or restructure a README without an explicit
  user request, even when it seems to obviously belong to the task.
- **TLA+ and formal artifacts** — `.tla` / `.cfg` files, `TLA/index.md`, proofs,
  TLC models: use the `tla-plus` / `tlaps` / `tlc-run` skills.

## 10. Anti-patterns

- Line-by-line or file-by-file retelling of the code as "documentation".
- A document without an annotation or without a References section.
- Stale index: missing rows, rows for deleted/moved paths, summaries that no
  longer match the document.
- A document contradicting another document or the governing spec.
- Duplicating spec content in docs instead of linking — two sources of truth.
- Narrating implementation internals (private helpers, file layout) where
  behavior and rationale belong.
- Prerequisites discovered mid-text because the References section omitted
  them.
- Unexplained terms: a term used before it is defined or referenced.
- Editing or creating a README as a side effect of a docs task.
- Colocated component docs missing from the root `docs/index.md`.
- Scattered loose `*.md` documents outside `docs/` (without an explicit user
  request for that placement).
- Change logs, superseded sections, or strikethrough archives inside
  documents.
- Mixed languages within one file.
