# Skill `spec`

Status: stable
Spec source of truth for: the `spec` skill — authoring project specifications, the spec-first flow, and mechanical spec checks

## Overview

The `spec` skill defines the process for creating and reviewing project specifications, aligning related contracts, checking code against specifications, and implementing approved requirements. `speclint.py` performs mechanical format checks; substantive properties are checked through a semantic pass and review.

## Scope

**In:** authoring and reviewing project specifications; spec-first behavior changes; checking related specs; mechanical and semantic checks; planning, implementing, and verifying changes against an approved spec.

**Out (non-goals):** README files and general project documentation; formal TLA+ specs, TLC models, and proofs; independently resolving substantive conflicts between specs.

## Definitions

- `spec/spec-first` — a process in which the controlling spec is updated and checked before implementation of a behavior change begins.
- `spec/reference-id` — a stable spec identifier from `specs/index.md`, or the component name in the heading of a small project's spec when there is no index.
- `spec/open-deviation` — a confirmed discrepancy between the active spec and the code that has not yet been resolved.

## Interface

- `speclint.py <path>...` — runs mechanical checks on one or more Markdown files or directories; the script's full mechanical-check contract is defined by SPECLINT.md, which is the single source of truth for the linter's rules.
- Allowed spec and index statuses: `draft`, `stable`.
- Allowed prefixed-entry families: `R`, `E`, `I`, `V`, `T`, `J`; deviation entries use `D-ID`.

## Configuration

- `root-spec-growth-guide`: integer; approximately 300 lines; fixed; a guideline for suggesting that the root `SPEC.md` be moved into a `specs/` tree; related to R2.3.
- `task-file-count-decomposition-guide`: integer; approximately 5 files; fixed; a guideline for considering further task decomposition; related to R9.15.

## Requirements

- R1. General rules for applying the skill and managing changes:
- R1.1. verification=manual; The skill is used when creating, changing, or reviewing `SPEC.md`, `specs/<component>.md`, `specs/index.md`, `specs/GLOSSARY.md`, and a colocated library `SPEC.md`.
- R1.2. verification=scenario; A request to change functionality, behavior, the interface, or constraints triggers the spec-first flow before implementation.
- R1.3. verification=manual; The skill is used to check related specs for conflicts and contract drift, and to implement code against an existing spec.
- R1.4. verification=manual; The agent does not use the skill for README files, general documentation, formal TLA+ specs, TLC models, or proofs.
- R1.5. verification=manual; Before editing files, the agent classifies the request as a behavior change, spec review, implementation against an existing spec, a small unambiguous change, or a new initiative with several independently verifiable capabilities.
- R1.6. verification=manual; The agent does not present an unconfirmed assumption as fact.
- R1.7. verification=manual; The agent pauses the affected decision if an unknown affects the public interface, security, compatibility, data integrity, or architectural boundaries.
- R1.8. verification=manual; A substantive conflict between normative requirements in related specs pauses the affected work until the user decides.
- R1.9. verification=manual; A spec review does not change code or rewrite the user's normative decisions without a separate request.
- R1.10. verification=manual; Implementation against an existing spec begins only after confirming that the spec covers the task.
- R1.11. verification=manual; If the contract has a gap, the agent updates the spec or asks the user to decide and does not silently improvise.
- R1.12. verification=manual; The agent reports checks that were not performed separately and does not claim full conformance if required checks have not been performed or known discrepancies remain open.

- R2. Spec placement and lifecycle:
- R2.1. verification=manual; A small project uses a root `SPEC.md`.
- R2.2. verification=manual; A project with multiple components uses `specs/<component-or-feature>.md` and a single `specs/index.md`.
- R2.3. verification=manual; When a second component boundary appears or the root spec grows to approximately `root-spec-growth-guide`, the agent suggests moving to a `specs/` tree without duplicating content.
- R2.4. verification=manual; An independently versioned library may keep a colocated `SPEC.md`, which is registered in the shared index.
- R2.5. verification=manual; With mixed placement, the index remains the single discovery point, and each component has only one canonical spec.
- R2.6. verification=manual; A project with a `specs/` tree contains `specs/index.md` and `specs/GLOSSARY.md`.
- R2.7. verification=manual; Every spec is included in the index, and the index contains no missing or stale paths.
- R2.8. verification=manual; `specs/index.md` is a Markdown table with the columns `Path`, `Reference`, `Status`, and `Summary`, in that order; each document has exactly one data row.
- R2.9. verification=manual; `Reference` is unique and consists of lowercase ASCII letters and digits separated by single hyphens.
- R2.10. verification=manual; A spec's status is `draft` or `stable` and matches the status in the index.
- R2.11. verification=manual; `stable` denotes a mandatory active contract, and code that deviates from it is a finding.
- R2.12. verification=manual; Obsolete requirements are removed or rewritten in the current spec; archived copies, struck-through rules, the `deprecated` status, and changelogs inside specs are not used.
- R2.13. verification=manual; Creating, changing, moving, or deleting a spec is accompanied by a synchronized update to the index and glossary when their data is affected.

- R3. Spec structure and content:
- R3.1. verification=manual; Every spec has a heading with the component name, `Status: draft` or `Status: stable`, and the line `Spec source of truth for: <component/feature>`.
- R3.2. verification=manual; Allowed section headings are `Overview`, `Scope`, `Definitions`, `Interface`, `Configuration`, `Requirements`, `Implementation`, `Examples`, `Tests`, `Usage constraints`, `Justification`, `Error handling`, `Dependencies`, `Used by`, and `Verification`.
- R3.3. verification=manual; A small spec may omit optional sections; `Tests` is required if at least one leaf R-ID has `verification=automated` or `verification=scenario`; if no such requirements exist, the section may be omitted; section names remain stable within a project.
- R3.4. verification=manual; `Scope` defines the `In` and `Out (non-goals)` areas.
- R3.5. verification=manual; `Interface` defines external signatures, interface elements, names, types, valid inputs and outputs, and the complete list of error codes.
- R3.6. verification=manual; `Configuration` is present when parameters, named constants, or magic numbers exist.
- R3.7. verification=manual; `Requirements` contains mandatory requirements for behavior and component properties observable by its consumer through the public interface; internal decisions that do not affect observable behavior are not included in `Requirements`.
- R3.8. verification=manual; When fixing a bug, the agent adds an `I-ID` entry to `Implementation` if it records an internal decision, constraint, or invariant needed to prevent recurrence of the same bug; the entry does not introduce independent mandatory rules and does not replace fixing the root cause or adding the corresponding `R-ID` when the bug affected public behavior.
- R3.9. verification=manual; `Examples` explains existing requirements and references the corresponding R-IDs without creating new rules.
- R3.10. verification=manual; `Tests` is generated from `Requirements`, never recovered or reverse-engineered from existing test code, and contains only concrete automated checks and deterministic multi-step scenarios; each leaf requirement with `verification=automated` or `verification=scenario` generates one or more T-IDs, whose `R-ID` points back to that requirement; each `procedure=` is a reproducible step-by-step recipe for the test body, derived from the behavior stated by the requirement and specifying setup, actions, checks, and their order; existing test code does not determine the contents of `Tests`, and tests are written from the generated recipes after the requirements are approved; repeating a requirement without an independent procedure does not constitute a test method.
- R3.11. verification=manual; `Usage constraints` explains budgets, applicability boundaries, compatibility, security, and environment assumptions; mandatory constraints are also recorded in `Requirements`.
- R3.12. verification=manual; `Justification` contains stable J-IDs and references to active requirements or `Configuration` entries.
- R3.13. verification=manual; `Error handling` explains error semantics defined in `Requirements` and listed in `Interface`, and introduces no new codes or rules.
- R3.14. verification=manual; `Verification` records the algorithm properties checked, the abstraction level, actual results, and a `Not checked` list.
- R3.15. verification=manual; No section other than `Requirements` serves as an independent source of obligations.
- R3.16. verification=manual; An algorithm's contract is described using steps, invariants, and complexity estimates at the contract level, without private source-code file, class, or helper-function names.
- R3.17. verification=automated; Each prefixed-entry family appears only in its corresponding section: `R` in `Requirements`, `I` in `Implementation`, `E` in `Examples`, `T` in `Tests`, `J` in `Justification`, and `V` in `Verification`; placing a family in any other section is prohibited.
- R3.18. verification=automated; The prefixes `R`, `E`, `I`, `V`, `T`, and `J` are used to form entry IDs; every non-empty content line in `Requirements`, `Examples`, `Implementation`, `Verification`, `Tests`, and `Justification` must begin with the list marker `- ` followed by an ID with the corresponding prefix; this applies to both group and leaf entries.
- R3.19. verification=automated; Every leaf entry in `Requirements` contains exactly one `verification=<value>` marker immediately after the R-ID; allowed values are `automated`, `scenario`, `manual`, and `analysis`. `automated` means the requirement is checked by an automated test; `scenario` means a deterministic verification scenario with more than one step exists; `manual` means a person checks it against the requirement's criteria; `analysis` means the property is checked through analytical reasoning or proof.

- R4. Requirements and identifiers:
- R4.1. verification=manual; Every requirement has a stable, unique R-ID; existing IDs are not renumbered without an explicitly approved migration that updates references at the same time. Gaps in the ID sequence are allowed; a missing number is not restored or filled with a new requirement without confirmed content and approval.
- R4.2. verification=manual; Requirements are grouped by semantic area using hierarchical R-IDs.
- R4.3. verification=manual; An R-ID with children is a group, ends with a colon, and does not assert behavior.
- R4.4. verification=manual; A leaf R-ID states a testable requirement and ends with a period.
- R4.5. verification=automated; Every prefixed entry in the `R`, `E`, `I`, `V`, `T`, and `J` families occupies exactly one line, begins with the list marker `- ` in column zero, is immediately followed by the ID, and does not use Markdown nesting to express hierarchy.
- R4.6. verification=analysis; Every leaf requirement entry is declarative, unambiguous, and testable.
- R4.7. verification=analysis; One requirement line describes one behavioral capability and contains no independent obligations, justifications, examples, or explanations.
- R4.8. verification=manual; Requirements refer to names from `Interface` or `Configuration`, not raw parameter, constant, argument, or magic-number values.
- R4.9. verification=analysis; A local term has an exact definition in `Definitions` or `GLOSSARY.md`; normative wording uses common or defined terms.
- R4.10. verification=manual; Every non-trivial example mirrors the ID of the requirement it explains and creates no new obligations.
- R4.11. verification=manual; Every `Verification` entry applies to a precisely named algorithm and does not claim proof of complete correctness based on a limited TLC run.
- R4.12. verification=analysis; Every leaf R-ID describes a property or behavior observable by the component's consumer through the public interface; a requirement that does not affect such observable behavior is removed from `Requirements` or moved to an appropriate non-normative section.
- R4.13. verification=automated; Every leaf R-ID with `verification=automated` or `verification=scenario` is covered by at least one T-ID entry describing the corresponding check; a separate T-ID is not required for `verification=manual` or `verification=analysis`.
- R4.14. verification=automated; Every leaf T-ID entry specifies one or more R-IDs being checked, a concrete `procedure=` field that gives the ordered setup, actions, and checks performed by the test body, derived from the behavior stated by the referenced requirement rather than from existing test code or a test invocation, conditions or inputs, and an expected-result criterion; restating a requirement, naming a test, or reverse-engineering a procedure from existing test code does not count as a test method.

- R5. Interface and configuration:
- R5.1. verification=manual; Every public name, signature, type, allowed domain, and error code is defined in `Interface`.
- R5.2. verification=manual; Every mandatory behavior associated with an interface domain is additionally stated in `Requirements`.
- R5.3. verification=manual; Each `Configuration` entry is keyed by name and specifies the value type and its effect.
- R5.4. verification=manual; For a parameter, `Configuration` specifies allowed values and the default value.
- R5.5. verification=manual; For a named constant, `Configuration` specifies the identifier, single value, units when applicable, and the `fixed` label, without `default`.
- R5.6. verification=manual; For an unnamed literal that is a magic number, `Configuration` defines a semantic name and the `magic` label, without `default`.
- R5.7. verification=manual; Every mandatory behavioral consequence of configuration is linked to an active R-ID.
- R5.8. verification=manual; Requirements use parameter and constant names instead of their numeric values.

- R6. Terms and cross-spec relationships:
- R6.1. verification=manual; Every project term uses the full ID `<reference>/<term>`.
- R6.2. verification=manual; Both parts of a term ID consist only of lowercase ASCII letters, digits, and hyphens.
- R6.3. verification=manual; Each new term is added to `GLOSSARY.md` in the same change as the spec, if the project uses a `specs/` tree.
- R6.4. verification=manual; Each full term ID has exactly one definition.
- R6.5. verification=manual; `GLOSSARY.md` is a Markdown table with the columns `Term ID`, `Definition`, and `Defined in`, in that order; each term has exactly one data row, and rows are sorted in strict alphabetical order by full term ID.
- R6.6. verification=manual; Each glossary row's `Defined in` cell starts with the term's Reference prefix and may include related requirement IDs when necessary.
- R6.7. verification=manual; A reused term is cited with the owner's full ID, without changing the prefix, and is not defined again.
- R6.8. verification=manual; The owner spec for a reused term is listed in `Dependencies`.
- R6.9. verification=manual; A reference to another spec uses its `Reference`, not its file path.
- R6.10. verification=manual; Every `Dependencies` relationship has a semantic basis and a mirrored `Used by` entry.
- R6.11. verification=manual; Both sides of a relationship are updated consistently and removed on both sides when the basis no longer exists.
- R6.12. verification=manual; Spec prose is written in the project's language; the first spec uses the user's language, and languages are not mixed within one file.
- R6.13. verification=manual; Non-English prose does not use undocumented anglicisms, except full term IDs, identifiers and code literals, CLI verbs, and configuration keys.

- R7. Checks and deviations:
- R7.1. verification=scenario; After every spec change, the agent first runs `speclint.py` and then performs a semantic pass on the changed spec and related specs.
- R7.2. verification=scenario; Mechanical checks and the semantic pass are reported separately.
- R7.3. verification=analysis; The semantic pass checks requirement clarity and testability, behavioral atomicity, relationship correctness, `Configuration` completeness, language and terminology, and the substance of `Verification`.
- R7.4. verification=scenario; After changing a requirement, the agent checks whether the associated `Verification` is still current and updates or removes a stale entry.
- R7.5. verification=manual; `DEVIATIONS.md` contains only open discrepancies between the active spec and code and is not used as a changelog or archive.
- R7.6. verification=manual; If the spec is changed without a conforming code change in the same change, a `DEVIATIONS.md` entry is created for every confirmed discrepancy.
- R7.7. verification=manual; If the spec and conforming code are changed together, no entry is created for a nonexistent open discrepancy.
- R7.8. verification=manual; Each `DEVIATIONS.md` entry describes one discrepancy, has a stable D-ID, and contains the date, spec identifier, `Spec edit`, `Was`, `Now`, `Code impact`, `Tests`, and `Review focus`.
- R7.9. verification=manual; `Was` describes the code's observable behavior, while `Now` describes the mandatory behavior of the updated spec.
- R7.10. verification=manual; New deviation entries are appended to the end of the file; IDs are not renumbered.
- R7.11. verification=manual; Correcting a deviation entry is documented in a new entry that references the old one, and the superseded entry is removed in the same change.
- R7.12. verification=manual; A deviation entry is removed only in the change where code, tests, and review confirm conformance with the updated spec.
- R7.13. verification=manual; Implementations, tasks, tests, commits, and PRs reference normative rule R-IDs; an I-ID does not replace an R-ID as the basis for conformance.
- R7.14. verification=manual; When behavior without a normative basis is found, review reports it as a spec gap or a bug.
- R7.15. verification=manual; A deviation review checks every item in `Review focus` before approval.

- R9. Planning and implementation:
- R9.1. verification=manual; For a new initiative with several independently verifiable capabilities, the Scope Check is agreed upon before component specs are written.
- R9.2. verification=manual; The Scope Check includes each module's Reference, responsibilities and boundaries, dependencies, build order, and boundary interfaces.
- R9.3. verification=manual; The Scope Check does not replace `specs/index.md` or create a second spec catalog.
- R9.4. verification=manual; A cyclic dependency between modules at the level of mandatory contracts leads to a proposal to revise boundaries or ask the user to decide.
- R9.5. verification=manual; Before a spec is approved, the agent checks boundaries, exclusions, interfaces, configuration, dependencies, terms, normal and edge scenarios, errors, success criteria, and results of required checks.
- R9.6. verification=scenario; For a significant change, checkpoints are completed in this order: `Scope` (if applicable), `Spec`, `Plan`, `Tasks`, `Implementation review`.
- R9.7. verification=manual; The process advances to the next checkpoint automatically once the current checkpoint's readiness criteria are met, unless another specification requirement calls for explicit approval.
- R9.8. verification=manual; Feedback returns the current checkpoint for revision.
- R9.9. verification=manual; A shortened process with a brief list of affected requirements and acceptance criteria is allowed for a small, unambiguous task.
- R9.10. verification=scenario; Implementation of a significant change does not begin until the spec, plan, and tasks are approved, unless the user explicitly authorizes another mode.
- R9.11. verification=manual; Autonomous mode does not waive handling of blocking risks and conflicts.
- R9.12. verification=manual; The implementation plan records components, dependencies, order, critical path, risks, unknowns, checks, permitted parallelism, and checkpoints.
- R9.13. verification=manual; Each task contains acceptance criteria, a verification step, expected files, and references to approved R-IDs.
- R9.15. verification=manual; If a task affects approximately `task-file-count-decomposition-guide` files or more, the agent considers further decomposition.
- R9.16. verification=manual; By default, the plan and tasks are placed in `plan.md` and `issues.md`, unless the project uses a compatible system or another format is specified.
- R9.17. verification=manual; For significant implementation work, a verifiable chain is maintained: `Requirement ID → Task → Test ID / verification evidence → Implementation`.
- R9.18. verification=scenario; After implementation, the agent runs the prescribed checks, compares each affected requirement with the behavior, checks test quality, and updates `Tests` and `Verification`.
- R9.19. verification=manual; Every requirement has an explicit verification method in its R-ID; no separate T-ID is needed for `verification=manual` or `verification=analysis`, while missing required coverage for `verification=automated` or `verification=scenario` is explicitly reported as a blocking finding.
- R9.20. verification=manual; When changing the skill instructions, the agent checks consistency across affected requirements, section structure, `Interface`, `Configuration`, `speclint.py`, its tests, and the description of mechanical-check limitations.

- R10. Reporting and review:
- R10.1. verification=analysis; The semantic pass identifies direct contradictions between requirements in related specs and contract drift between an interface provider and consumer.
- R10.2. verification=analysis; The semantic pass identifies duplication of a normative rule across multiple specs and retains one canonical formulation.
- R10.3. verification=analysis; The semantic pass checks consistency of public names, message fields, term IDs, configuration keys, error codes, units of measurement, and versions across all affected specs.
- R10.4. verification=analysis; The semantic pass checks Reference ID resolution, glossary completeness and ordering, dangling references, and mirrored `Dependencies`/`Used by` relationships.
- R10.5. verification=manual; Review reports a commit that changes behavior without an up-to-date spec.
- R10.6. verification=manual; Review reports a spec change without corresponding code and without an open deviation, as well as deviations that remain after they have been closed.
- R10.7. verification=manual; Review reports duplicate specs, missing or extra index rows, stale status, or an invalid Reference.
- R10.8. verification=analysis; Review reports file-path references used instead of Reference IDs, one-sided or semantically empty relationships, and use of another spec's term without a dependency.
- R10.9. verification=analysis; Review reports incomplete term IDs, an unsynchronized glossary, duplicate definitions, and inappropriate anglicisms.
- R10.10. verification=analysis; Review reports compound or untestable requirements, unstable IDs, incorrect grouping, multi-line prefixed entries, Markdown-nested entries, and dangling references.
- R10.11. verification=analysis; Review reports undocumented `Interface` values, missing `Configuration` entries, incorrect mixing of `fixed` and `magic`, citing numbers instead of names, and describing private implementation as an external requirement.
- R10.12. verification=analysis; Review reports incomplete or stale `Verification`, including overclaims based on a limited TLC run.
- R10.13. verification=manual; The final report lists changed specs and affected IDs, related artifacts, results of `speclint.py`, semantic review and tests, and unchecked requirements, assumptions, risks, and open deviations.

## Tests

- T11. Automated checks and deterministic multi-step scenarios:
- T11.3. R-ID=R3.17,R3.18,R3.19,R4.5,R4.13,R4.14; procedure=generate one valid fixture from a requirement set containing automated and scenario leaves, and separate invalid fixtures with malformed IDs, missing or repeated `verification`, invalid section markers, continued prefixed lines, missing generated T-IDs, and extra T-IDs for `manual`; run the linter on each fixture; compare each result with its expected diagnostic; conditions=each fixture is isolated and has a known expected result; expected=the valid fixture passes, each invalid fixture reports its corresponding violation, T-IDs are required only for `automated` and `scenario`, and the check does not claim semantic test sufficiency.
- T11.8. R-ID=R1.2,R9.6,R9.10,R9.18; procedure=submit a significant behavior-change request; write the applicable Requirements first; derive a T-ID and its step-by-step procedure from every automated or scenario leaf; approve Scope when applicable, Plan, and Tasks; write test bodies from the generated procedures; implement the change; run prescribed checks; compare every requirement with behavior; update Tests and Verification; conditions=the initial spec does not cover the requested behavior, explicit permission to skip approval is absent, and required checks are available; expected=Requirements precede generated Tests, test bodies follow the generated recipes, implementation starts only after required approval, and post-implementation evidence updates Tests and Verification.
- T11.9. R-ID=R7.1,R7.2,R7.4; procedure=change a requirement; regenerate the T-IDs and step-by-step procedures derived from the changed automated or scenario leaves; run `speclint.py`; perform the semantic pass separately; inspect whether the Verification still matches the changed requirement; update or remove the stale Verification entry; conditions=both the mechanical check and semantic pass are available; expected=the mechanical result is reported first and separately, generated Tests reflect the changed Requirements, and the stale Verification entry is updated or removed.

## Implementation

- I1. The skill is implemented by the `SKILL.md` instructions and the `speclint.py` script. The instructions describe the spec-first process, formatting rules for specs, the index and glossary, change verification, tracking open discrepancies, and implementation against an approved contract. Mechanical checking is limited to properties the script can recognize; other properties are established through the semantic pass and review.
