# Skill `spec`

Status: stable
Spec source of truth for: OpenCode `spec` skill — authoring project specifications, the spec-first flow, and mechanical spec checks

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

- `speclint.py <path>...` — runs mechanical checks on one or more Markdown files or directories.
- `path` — a path to a Markdown file or directory.
- Allowed spec and index statuses: `draft`, `stable`.
- Allowed prefixed-entry families: `R`, `E`, `I`, `V`, `T`, `J`; deviation entries use `D-ID`.

## Configuration

- `root-spec-growth-guide`: integer; approximately 300 lines; fixed; a guideline for suggesting that the root `SPEC.md` be moved into a `specs/` tree; related to R2.3.
- `speclint-clean-exit-code`: integer; 0; fixed; exit code when there are no findings; related to R6.5.
- `speclint-warning-exit-code`: integer; 1; fixed; exit code for warnings without errors; related to R6.5.
- `speclint-error-exit-code`: integer; 2; fixed; exit code for lint errors or an invalid invocation; related to R6.1 and R6.5.
- `task-file-count-decomposition-guide`: integer; approximately 5 files; fixed; a guideline for considering further task decomposition; related to R8.7.

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
- R3.10. verification=manual; `Tests` contains only concrete automated checks and deterministic multi-step scenarios, references only leaf R-IDs with `verification=automated` or `verification=scenario`, and does not reference I-IDs; repeating a requirement without an independent procedure does not constitute a test method.
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
- R4.14. verification=automated; Every leaf T-ID entry specifies one or more R-IDs being checked, a concrete verification procedure, conditions or inputs, and an expected-result criterion; restating a requirement without a reproducible procedure does not count as a test.

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

- R8. Mechanical-check contract for `speclint.py`:
- R8.1. verification=automated; `speclint.py` accepts at least one path to a Markdown file or directory.
- R8.2. verification=automated; A missing path, nonexistent path, or path to a non-`.md` file produces a message on `stderr` and `speclint-error-exit-code`.
- R8.3. verification=automated; When linting a directory, `speclint.py` recursively processes all `index.md` files in sorted order first, then `GLOSSARY.md`, then the remaining `.md` files in sorted order.
- R8.4. verification=automated; File type is determined by basename: `index.md` is checked as an index, `GLOSSARY.md` as a glossary, and any other `.md` file as a spec.
- R8.5. verification=automated; In directory mode, all `.md` files are candidates for checking; checks apply to recognized prefixed entries and numeric literals outside excluded areas.
- R8.6. verification=automated; `speclint.py` checks syntax and uniqueness of R-, E-, I-, V-, T-, and J-IDs within a file, the presence of ancestors, valid group and leaf entries, and the absence of groups without children.
- R8.7. verification=automated; `speclint.py` checks that E-IDs mirror existing R-IDs, that `Tests` entries reference only existing leaf R-IDs with `verification=automated` or `verification=scenario`, and that prefixed entries occupy one line.
- R8.8. verification=automated; `speclint.py` checks that every non-empty content line in `Requirements`, `Examples`, `Implementation`, `Verification`, `Tests`, and `Justification` begins in column zero with `- ` immediately followed by an ID with the section's corresponding prefix, for both group and leaf entries; a missing marker, missing ID, or section-inappropriate prefix is reported.
- R8.9. verification=automated; `speclint.py` reports a prefixed entry that begins with indentation or continues on the next indented line.
- R8.10. verification=automated; `speclint.py` prohibits bare numeric literals outside `Configuration`, `Examples`, backticks, and recognized fenced code blocks.
- R8.11. verification=automated; The numeric scanner recognizes integers and decimals, decimal separators using a dot or comma, and numeric tokens with alphabetic suffixes when the token begins with a number.
- R8.12. verification=automated; The numeric scanner does not treat digits inside identifiers, versions, TLS-like tokens, or tokens beginning with a letter as bare numeric literals.
- R8.13. verification=automated; Fenced code blocks are recognized from a marker in column zero and their lines are skipped; the closing marker is not required to match the opening marker's character or length.
- R8.14. verification=automated; If a fenced code block is not closed, all following lines through end of file are treated as part of the block for numeric scanning and section switching.
- R8.15. verification=automated; A heading inside a recognized fenced code block does not change the scanner's section; a heading outside a block determines the section by the first alphabetic word in the heading.
- R8.16. verification=automated; For an index, `speclint.py` mechanically validates compliance with the index-formatting and content requirements in R2.7–R2.10: table structure and required cells, valid `Status` and `Reference` values, and the existence of every path. R2.8 is the normative source for the table format; this rule specifies only the checks performed by the tool.
- R8.17. verification=automated; An index path is resolved relative to the Git repository root, or, if that root cannot be determined, relative to the parent directory of `specs/` or the index directory itself.
- R8.18. verification=automated; For a glossary, `speclint.py` mechanically validates compliance with the glossary requirements in R6.3–R6.5: required cells, full term IDs, the `Defined in` value, and alphabetical sorting by full term ID. R6.5 is the normative source for the table format; this rule specifies only the checks performed by the tool.
- R8.19. verification=automated; Glossary term ID prefixes are resolved against Reference IDs collected from indexes.
- R8.20. verification=automated; If Reference IDs have not been collected, prefix-resolution checking is skipped with a warning.
- R8.21. verification=automated; Findings are printed to `stderr` in the format `<file>:<line>: <message>`; warnings have the `speclint:` prefix and `warning:` label.
- R8.22. verification=automated; The exit code is `speclint-clean-exit-code` when there are no findings, `speclint-warning-exit-code` for warnings without errors, and `speclint-error-exit-code` when errors occur.
- R8.23. verification=analysis; `speclint.py` documentation does not attribute semantic checks to the tool that the script does not mechanically perform.
- R8.24. verification=analysis; Limitations of the line-by-line scanner, including its inability to detect unindented continuations and its fenced-code-block recognition behavior, are documented and considered during review.
- R8.25. verification=analysis; Mechanical checking does not establish requirement clarity, atomicity, semantic completeness of configuration, truth of `Verification`, semantic justification of relationships, or language quality.
- R8.26. verification=automated; `speclint.py` checks that every leaf R-ID has exactly one `verification` marker with an allowed value of `automated`, `scenario`, `manual`, or `analysis`.
- R8.27. verification=automated; `speclint.py` checks that every leaf R-ID with `verification=automated` or `verification=scenario` is referenced by at least one leaf entry in `Tests`, while R-IDs with `verification=manual` or `verification=analysis` do not require a T-ID; missing mandatory coverage is reported as an error. The presence of a reference does not establish the semantic sufficiency of the procedure.

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
- T11.1. R-ID=R8.1,R8.2; procedure=run `speclint.py` without arguments, then with a path to a nonexistent object and a path to an existing file whose extension is not `.md`; conditions=run each invocation separately and record `stderr` and the exit code; expected=each invalid invocation prints a diagnostic to `stderr` and returns `speclint-error-exit-code`, while a valid Markdown path is accepted.
- T11.2. R-ID=R8.3,R8.4,R8.5; procedure=create a temporary tree containing several `index.md`, `GLOSSARY.md`, and ordinary Markdown files in different subdirectories, then run `speclint.py` on the root directory; conditions=names and sortable paths are predefined, and some files contain recognizable violations; expected=files are processed recursively in the specified order, type is determined by basename, and all eligible Markdown files are checked.
- T11.3. R-ID=R3.17,R3.18,R3.19,R4.5,R4.13,R4.14,R8.6,R8.7,R8.8,R8.9,R8.26,R8.27; procedure=prepare specs with valid and invalid IDs, missing/repeated `verification`, invalid markers, incorrect section prefixes, multi-line entries, missing required T-IDs, and extra T-IDs for `manual`; conditions=run each case as a separate fixture with a known expected result; expected=valid fixtures pass, each invalid fixture reports the corresponding violation, T-IDs are required only for `automated` and `scenario`, and reference checking does not claim semantic test sufficiency.
- T11.4. R-ID=R8.10,R8.11,R8.12; procedure=run the numeric scanner on paired fixtures containing bare numbers and the same numbers inside allowed exceptions, identifiers, versions, and letter-starting tokens; conditions=fixtures differ only in the numeric token's context; expected=bare numeric literals outside allowed areas are reported, while excluded tokens are not reported as bare numbers.
- T11.5. R-ID=R8.13,R8.14,R8.15; procedure=check fixtures with closed and unclosed fenced code blocks, headings inside and outside blocks, and closing markers of different lengths; conditions=each fixture has a predefined expected section and numeric-scanner exclusion area; expected=scanner behavior matches the rules for recognizing blocks and switching sections.
- T11.6. R-ID=R8.16,R8.17,R8.18,R8.19,R8.20; procedure=run `speclint.py` on table-formatted indexes and glossaries with valid and invalid headers, rows, paths, statuses, Reference IDs, term IDs, sorting, and `Defined in`; conditions=test resolvable references separately from the case where Reference IDs cannot be collected; expected=invalid fields and references are reported, valid ones are accepted, and failure to resolve prefixes without collected Reference IDs produces a warning and skips only that check.
- T11.7. R-ID=R8.21,R8.22; procedure=run lint on fixtures producing no findings, warnings only, and errors; conditions=fixtures are prepared in advance to produce each of the three result classes; expected=diagnostics use the specified `stderr` format, warnings have the `speclint:` prefix, and the exit code matches the clean, warning, or error result.
- T11.8. R-ID=R1.2,R9.6,R9.10,R9.18; procedure=submit a request for a significant behavior change and track the agent's actions from specification through implementation verification; conditions=the spec initially does not cover the requested behavior, there is no explicit permission to skip approval, and checks are available; expected=the agent first updates and checks the spec, then completes Plan and Tasks before implementation, does not begin implementation before required approval, and after implementation runs checks, compares affected requirements, and updates `Tests`/`Verification`.
- T11.9. R-ID=R7.1,R7.2,R7.4; procedure=change an existing requirement while leaving its associated `Verification` entry stale; conditions=both `speclint.py` and the semantic pass are available in the project; expected=the agent runs `speclint.py` first, reports the semantic-pass result separately, and updates or removes the `Verification` entry if it no longer matches the requirement.

## Implementation

- I1. The skill is implemented by the `SKILL.md` instructions and the `speclint.py` script. The instructions describe the spec-first process, formatting rules for specs, the index and glossary, change verification, tracking open discrepancies, and implementation against an approved contract. Mechanical checking is limited to properties the script can recognize; other properties are established through the semantic pass and review.
