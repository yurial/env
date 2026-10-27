---
name: spec
description: Create, review, and maintain project specifications; enforce spec-first behavior changes; align related contracts; and verify implementation against approved requirements.
---

# Spec skill

## Purpose

Use this skill to author and review project specifications, align related contracts, check code against specifications, and implement approved requirements. `speclint` checks mechanical properties; semantic properties require a separate semantic pass and review.

## When to use

Use this skill when creating, changing, or reviewing `SPEC.md`, `specs/<component>.md`, `specs/index.md`, `specs/GLOSSARY.md`, or a colocated library `SPEC.md`; when a behavior change requires a spec-first flow; when checking related specifications for conflicts or contract drift; or when implementing code against an existing specification.

Do not use it for README files, general project documentation, formal TLA+ specifications, TLC models, or proofs. A spec review does not authorize code changes or changes to the user's normative decisions.

## Classify the request first

Before editing files, classify the request as one of:

- behavior, interface, or constraint change;
- specification review;
- implementation against an existing specification;
- small, unambiguous change;
- new initiative with several independently verifiable capabilities.

Do not present an unconfirmed assumption as fact. Pause the affected decision when an unknown affects the public interface, security, compatibility, data integrity, or architectural boundaries. Pause affected work and ask the user to decide when normative requirements in related specifications substantively conflict. Confirm that the existing spec covers a requested implementation task; if it has a gap, update the spec or ask for a decision instead of silently improvising.

## Spec placement and lifecycle

- Use a root `SPEC.md` for a small project.
- For a project with multiple components, use `specs/<component-or-feature>.md` and one `specs/index.md`.
- If a second component boundary appears or the root spec grows to approximately `root-spec-growth-guide` (about 300 lines), suggest moving to a `specs/` tree without duplicating content.
- An independently versioned library may keep a colocated `SPEC.md`; register it in the shared index.
- With mixed placement, the index remains the single discovery point, and each component has one canonical spec.
- A project with a `specs/` tree contains both `specs/index.md` and `specs/GLOSSARY.md`.
- Include every spec in the index. Keep index paths current and unique, and store the index as a Markdown table with columns `Path`, `Reference`, `Status`, `Summary` in that order, one data row per document.
- A `Reference` is unique and uses lowercase ASCII letters and digits separated by single hyphens. In a small project without `specs/index.md`, use the component name in the spec heading as the `Reference` for cross-spec terminology and relationships.
- Spec status is `draft` or `stable` and must match the index. `stable` is a mandatory active contract; code that deviates from it is a finding.
- Remove or rewrite obsolete requirements in the current spec. Do not use archived copies, struck-through rules, a `deprecated` status, or changelogs inside specs.
- When creating, changing, moving, or deleting a spec, synchronize the index and glossary wherever their data is affected.

## Required spec structure

Every spec starts with a heading naming the component, `Status: draft` or `Status: stable`, and `Spec source of truth for: <component/feature>`.

Use only these section headings:

- `Overview`
- `Scope`
- `Definitions`
- `Interface`
- `Configuration`
- `Requirements`
- `Implementation`
- `Examples`
- `Tests`
- `Usage constraints`
- `Justification`
- `Error handling`
- `Dependencies`
- `Used by`
- `Verification`

Small specs may omit optional sections. `Tests` is required if at least one leaf `R-ID` has `verification=automated` or `verification=scenario`; if no such requirements exist, `Tests` may be omitted. Keep section names stable within a project. `Scope` defines `In` and `Out (non-goals)`. `Interface` documents external signatures, names, types, valid inputs and outputs, and the complete list of error codes. Include `Configuration` when parameters, named constants, or magic numbers exist.

`Requirements` is the only section that serves as an independent source of obligations. It contains mandatory behavior and component properties observable by consumers through the public interface. Do not put internal decisions that do not affect observable behavior in `Requirements`.

For bug fixes, add an `I-ID` to `Implementation` when it records an internal decision, constraint, or invariant needed to prevent recurrence. An `I-ID` must not introduce an independent mandatory rule or replace fixing the root cause or adding the corresponding `R-ID` when public behavior was affected.

`Examples` explain existing requirements and reference their `R-ID`; they do not create new rules. `Tests` contains only concrete automated checks and deterministic multi-step scenarios. It references only leaf requirements marked `verification=automated` or `verification=scenario`, never `I-ID`s. Repeating a requirement without an independent procedure is not a test method.

`Usage constraints` explains budgets, applicability boundaries, compatibility, security, and environment assumptions; record mandatory constraints in `Requirements` as well. `Justification` contains stable `J-ID`s that reference active requirements or `Configuration` entries. `Error handling` explains error semantics already defined in `Requirements` and listed in `Interface`; it introduces no new codes or rules. `Verification` records the algorithm properties checked, abstraction level, actual results, and a `Not checked` list.

Describe algorithm contracts with steps, invariants, and complexity estimates at the contract level. Do not expose private source files, classes, or helper-function names as part of the external contract.

## Requirement writing and identifiers

- Give every requirement a stable, unique `R-ID`. Do not renumber existing IDs unless an explicitly approved migration updates all references. Gaps are allowed; do not fill them without confirmed content and approval.
- Group requirements by semantic area using hierarchical IDs. A group ID has children, ends with a colon, and asserts no behavior. A leaf ID states one testable requirement and ends with a period.
- Each leaf requirement must be declarative, unambiguous, and testable, and describe one behavioral capability without independent obligations, justifications, examples, or explanations.
- Every leaf requirement contains exactly one `verification=<value>` marker immediately after its R-ID. Allowed values are `automated`, `scenario`, `manual`, and `analysis`.
- `automated` means an automated test checks the requirement; `scenario` means a deterministic multi-step verification scenario exists; `manual` means a person checks it against criteria; `analysis` means analytical reasoning or proof checks the property.
- Every leaf requirement describes behavior observable through the public interface. Move internal-only decisions to an appropriate non-normative section.
- Refer to names defined in `Interface` or `Configuration`, not raw parameter values, constant values, or magic numbers.
- Define local terms exactly in `Definitions` or `GLOSSARY.md`; use common or defined terms in normative wording.
- Every non-trivial example mirrors the ID of the requirement it explains.

Prefixed entry families belong only in their corresponding sections: `R` in `Requirements`, `I` in `Implementation`, `E` in `Examples`, `T` in `Tests`, `J` in `Justification`, and `V` in `Verification`. Every non-empty content line in these sections begins in column zero with `- ` followed by its corresponding ID. Each prefixed entry occupies exactly one line; do not use Markdown nesting to express hierarchy. Each leaf `T-ID` names the checked `R-ID` or IDs, a concrete procedure, conditions or inputs, and expected-result criteria.

Every leaf `R-ID` marked `automated` or `scenario` must be covered by at least one `T-ID`. A separate `T-ID` is not required for `manual` or `analysis`. Missing required test coverage is a blocking finding. Each `Verification` entry applies to a precisely named algorithm and must not claim complete correctness based only on a limited TLC run.

## Interface and configuration

Define every public name, signature, type, allowed domain, and error code in `Interface`. State mandatory behavior associated with an interface domain in `Requirements` too.

Each `Configuration` entry is keyed by name and specifies its type and effect. For parameters, specify allowed values and the default. For named constants, specify the identifier, single value, units where applicable, and `fixed`, without `default`. For an unnamed literal that acts as a magic number, define a semantic name and label it `magic`, without `default`. Link every mandatory behavioral consequence of configuration to an active `R-ID`. Requirements use parameter and constant names, not their numeric values.

## Terms and relationships between specs

- Use full project term IDs in the form `<reference>/<term>`; both parts contain only lowercase ASCII letters, digits, and hyphens.
- When a project uses a `specs/` tree, add each new term to `GLOSSARY.md` in the same change as the spec.
- Give each full term ID exactly one definition. Store `GLOSSARY.md` as a Markdown table with columns `Term ID`, `Definition`, `Defined in` in that order, one data row per term; sort rows strictly alphabetically by full term ID.
- Each glossary entry includes `Defined in`, equal to the term's `Reference` prefix and, where necessary, requirement IDs.
- Reuse an owned term by citing its full ID without changing the prefix or defining it again. List its owner spec in `Dependencies`.
- Refer to another spec by its `Reference`, not its file path.
- Every `Dependencies` relationship must have a semantic basis and a mirrored `Used by` entry. Update both sides together and remove both sides when the relationship no longer applies.
- Write spec prose in the project's language. The first spec uses the user's language; do not mix languages within one file. In non-English prose, avoid undocumented anglicisms except full term IDs, identifiers and code literals, CLI verbs, and configuration keys.

## Mechanical and semantic checks

After every spec change:

1. Run `speclint` first on the changed spec or relevant directory.
2. Perform a separate semantic pass on the changed spec and related specs.
3. Report mechanical-check results and semantic-review results separately.
4. After changing a requirement, verify that the associated `Verification` entry is still current; update or remove stale entries.

The semantic pass checks requirement clarity, testability and atomicity; cross-spec contradictions and contract drift; duplication of normative rules; consistency of public names, message fields, term IDs, configuration keys, error codes, units and versions; `Reference` resolution; glossary completeness, ordering and duplicate definitions; dangling references; mirrored `Dependencies`/`Used by` relationships; configuration completeness; language and terminology; and the substance of `Verification`.

Do not claim that mechanical lint proves semantic correctness. Report checks not performed separately and do not claim full conformance while required checks have not been performed or known discrepancies remain open.

## `speclint` contract

Use `speclint <path>...` to check one or more Markdown files or directories. At least one path is required. A missing argument, nonexistent path, or existing file whose extension is not `.md` produces a diagnostic on `stderr` and returns `speclint-error-exit-code`.

When checking a directory, process all `index.md` files recursively in sorted order first, then all `GLOSSARY.md` files, then the remaining `.md` files in sorted order. Determine file type by basename: `index.md` is an index, `GLOSSARY.md` is a glossary, and every other `.md` file is a spec. In directory mode, every `.md` file is a candidate. Apply checks to recognized prefixed entries and to numeric literals outside excluded areas.

The mechanical checks include all of the following:

- Check syntax and per-file uniqueness of `R`, `E`, `I`, `V`, `T`, and `J` IDs; required ancestors; valid group and leaf entries; and absence of groups without children.
- Check that `E-ID`s mirror existing `R-ID`s; `Tests` references only existing leaf `R-ID`s marked `verification=automated` or `verification=scenario`; and prefixed entries occupy one line.
- In `Requirements`, `Examples`, `Implementation`, `Verification`, `Tests`, and `Justification`, every non-empty content line must begin in column zero with `- ` immediately followed by an ID of that section's corresponding family, for both group and leaf entries. Report missing markers, missing IDs, and section-inappropriate prefixes.
- Report a prefixed entry that begins with indentation or continues on a following indented line.
- Prohibit bare numeric literals outside `Configuration`, `Examples`, backticks, and recognized fenced code blocks. Recognize integers and decimals, decimal separators using a dot or comma, and numeric tokens with alphabetic suffixes when the token begins with a number. Do not treat digits inside identifiers, versions, TLS-like tokens, or tokens beginning with a letter as bare numeric literals.
- Recognize fenced code blocks only when the fence marker begins in column zero. Skip their lines. The closing marker does not need to match the opening marker's character or length. If no closing marker occurs, treat all following lines through end of file as part of the block for numeric scanning and section switching. Headings inside a recognized block do not change the scanner's section; a heading outside a block determines the section by the first alphabetic word in the heading.
- For indexes, validate compliance with the document-format and content requirements in the source specification (especially R2.7–R2.10): check the required table header and column order, required cells, `Status`, `Reference`, and path existence. These are document-authoring rules defined by the source specification; `speclint` only checks compliance with them. Resolve index paths relative to the Git repository root, or, if that root cannot be determined, relative to the parent directory of `specs/` or the index directory itself.
- For glossaries, validate compliance with the document-format and content requirements in the source specification (especially R6.3–R6.5): check the required table header and column order, required cells, term-ID format, use of the English alphabet, alphabetical sorting, and the `Defined in` field format. These are document-authoring rules defined by the source specification; `speclint` only checks compliance with them. Resolve term-ID prefixes against `Reference` IDs collected from indexes. If no `Reference` IDs were collected, skip only prefix-resolution checking and emit a warning.
- Check that every leaf `R-ID` has exactly one `verification` marker and that its value is one of `automated`, `scenario`, `manual`, or `analysis`.
- Check that every leaf `R-ID` marked `automated` or `scenario` is referenced by at least one leaf entry in `Tests`. `manual` and `analysis` requirements do not need a `T-ID`. Missing required coverage is an error. A present reference does not prove that the test procedure is semantically sufficient.

Write findings to `stderr` in the format `<file>:<line>: <message>`. Warnings must have the prefix `speclint: warning:`. Return `speclint-clean-exit-code` when there are no findings, `speclint-warning-exit-code` when warnings occur without errors, and `speclint-error-exit-code` when errors occur. These are fixed configuration entries: `speclint-clean-exit-code` is `0`, `speclint-warning-exit-code` is `1`, and `speclint-error-exit-code` is `2`.

Do not describe semantic checks as capabilities of `speclint` unless the script mechanically performs them. Document and account for line-by-line scanner limitations during review, including its inability to detect unindented continuations and its fenced-code-block recognition behavior. Mechanical checking does not establish requirement clarity, atomicity, semantic completeness of configuration, truth of `Verification`, semantic justification of relationships, or language quality. Prefix-resolution warnings skip only that resolution check, not the rest of linting.

## Open deviations

`DEVIATIONS.md` contains only confirmed, unresolved discrepancies between the active spec and code; it is not a changelog or archive.

- If the spec changes without a conforming code change in the same change, add one entry for each confirmed discrepancy.
- If the spec and conforming code change together, do not create an entry for a discrepancy that does not exist.
- Each entry describes one discrepancy, has a stable `D-ID`, and includes the date, spec identifier, `Spec edit`, `Was`, `Now`, `Code impact`, `Tests`, and `Review focus`.
- `Was` describes observable code behavior; `Now` describes the mandatory behavior of the updated spec.
- Append new entries to the end and never renumber IDs.
- Document a correction in a new entry that references the old one, and remove the superseded entry in the same change.
- Remove a deviation only in the change where code, tests, and review confirm conformance with the updated spec.
- Implementations, tasks, tests, commits, and PRs reference normative `R-ID`s. An `I-ID` does not replace an `R-ID` as the basis for conformance.
- Report behavior without a normative basis as a spec gap or bug. Review every item in `Review focus` before approving a deviation fix.

## Planning and implementation

For a new initiative with several independently verifiable capabilities, agree on the Scope Check before writing component specs. Record each module's `Reference`, responsibilities and boundaries, dependencies, build order, and boundary interfaces. The Scope Check does not replace `specs/index.md` or create another spec catalog. If mandatory contracts create a cyclic module dependency, propose revised boundaries or ask the user to decide.

Before approving a spec, check boundaries and exclusions, interfaces, configuration, dependencies, terms, normal and edge scenarios, errors, success criteria, and required-check results.

For significant changes, complete checkpoints in this order: `Scope` (if applicable), `Spec`, `Plan`, `Tasks`, `Implementation review`. Advance automatically when readiness criteria are met unless another requirement calls for explicit approval; feedback returns the current checkpoint for revision. A small, unambiguous task may use a shortened process with a brief list of affected requirements and acceptance criteria.

Do not begin implementation of a significant change until the spec, plan, and tasks are approved unless the user explicitly authorizes another mode. Autonomous mode does not waive blocking risks or conflicts. The plan records components, dependencies, order, critical path, risks, unknowns, checks, permitted parallelism, and checkpoints. Each task records acceptance criteria, a verification step, expected files, and approved `R-ID`s. By default, use `plan.md` and `issues.md` unless the project uses a compatible system or another format is specified. If a task affects approximately `task-file-count-decomposition-guide` files or more (about five files), consider further decomposition.

For significant implementation work, maintain the traceability chain `Requirement ID → Task → Test ID / verification evidence → Implementation`. After implementation, run prescribed checks, compare each affected requirement with actual behavior, check test quality, and update `Tests` and `Verification`.

When changing these skill instructions, check consistency across affected requirements, section structure, `Interface`, `Configuration`, `speclint`, its tests, and the documented limits of mechanical checking.

## Review and final report

Review should report:

- behavior-changing commits without an up-to-date spec;
- spec changes without corresponding code and without an open deviation;
- deviations that remain after they are closed;
- duplicate specs, missing or extra index rows, stale status, or invalid `Reference` values;
- file-path references used instead of `Reference` IDs, one-sided or semantically empty relationships, and use of another spec's term without a dependency;
- incomplete term IDs, an unsynchronized glossary, duplicate definitions, and inappropriate anglicisms;
- compound or untestable requirements, unstable IDs, incorrect grouping, multi-line prefixed entries, Markdown-nested entries, and dangling references;
- undocumented `Interface` values, missing `Configuration` entries, incorrect use of `fixed` and `magic`, raw numeric values where names are required, and private implementation details presented as external requirements;
- incomplete or stale `Verification`, including overclaims based on limited TLC runs.

The final report lists changed specs and affected IDs, related artifacts, results of `speclint`, semantic review and tests, plus unchecked requirements, assumptions, risks, and open deviations. State explicitly which checks were not performed.

## Mandatory specification-compliance gate

Before declaring a specification complete, walk through every applicable leaf requirement in this skill's source specification, `SPEC.md`, and record its disposition in the review notes. Do not treat a section-level summary as evidence that every leaf rule was applied. For each requirement, confirm the artifact or decision that satisfies it, or record it as not applicable with a reason, blocked by an unresolved decision, or not checked. Never silently omit a requirement.

Use this order for every specification change:

1. **Classify and scope.** Apply R1 and R2: classify the request; establish whether it is a behavior change; identify canonical specs; preserve stable IDs; resolve unknowns and conflicts by the stated pause/decision rules; update the index and glossary when affected.
2. **Structure and normative content.** Apply R3 and R4: validate the heading, status and source-of-truth line; use only permitted sections; put independent obligations only in `Requirements`; define public behavior observably; keep internal implementation notes non-normative; follow the ID, one-line entry, verification-marker, example, and test rules.
3. **Interfaces and configuration.** Apply R5: document every public name, signature, type, domain, output and error code; repeat mandatory interface behavior in `Requirements`; define every parameter, constant and magic number with the correct fields and labels; link behavioral consequences to active `R-ID`s and use names instead of numeric values in requirements.
4. **Terms and relationships.** Apply R6: validate the glossary table header and rows, full term IDs, definitions, sorting and `Defined in`; add new terms to the glossary in the same change where applicable; reuse owner IDs without redefining terms; use `Reference` rather than paths; synchronize both sides of each dependency; check language and anglicisms.
5. **Mechanical check, then semantic check.** Apply R7 and R8: run `speclint` first, then separately review the changed spec and related specs. Use the complete `speclint` contract above. Re-check the associated `Verification` whenever a requirement changes. Report the two check types separately and never equate lint success with semantic correctness.
6. **Deviation accounting.** Apply R7.5–R7.15: record only confirmed open discrepancies; use one stable `D-ID` per discrepancy and all required fields; append without renumbering; supersede corrected entries correctly; close only when code, tests and review establish conformance; keep implementation artifacts tied to normative `R-ID`s.
7. **Planning and implementation.** Apply R9: perform Scope Check for multi-capability initiatives; inspect boundaries, interfaces, dependencies, terms, normal and edge scenarios, errors and success criteria; follow the checkpoint order and approval gate; record plan and task details; preserve requirement-to-task-to-test-to-implementation traceability; run prescribed checks and update `Tests` and `Verification` after implementation.
8. **Review and report.** Apply R10: check cross-spec contradictions, contract drift, duplicate normative rules, identifiers and configuration consistency, glossary and relationship integrity, requirement quality, interface/configuration completeness, and `Verification` claims. Report changed specs and affected IDs, related artifacts, mechanical results, semantic results, tests, unchecked requirements, assumptions, risks and open deviations.

A specification is not reported as fully conforming while any applicable requirement is unchecked, any required check is missing, any blocking coverage finding exists, or any known discrepancy remains open. If the source `SPEC.md` changes, first compare this skill against the new source and update the skill before relying on it for further specification work.

## Configuration values governed by the source spec

Treat these as fixed configuration entries rather than independent informal defaults:

- `root-spec-growth-guide`: integer, approximately 300 lines; a guideline for suggesting a move from a root `SPEC.md` to a `specs/` tree; related to R2.3.
- `speclint-clean-exit-code`: integer `0`; exit code when there are no findings; related to R6.5.
- `speclint-warning-exit-code`: integer `1`; exit code for warnings without errors; related to R6.5.
- `speclint-error-exit-code`: integer `2`; exit code for lint errors or invalid invocation; related to R6.1 and R6.5.
- `task-file-count-decomposition-guide`: integer, approximately five files; a guideline for considering task decomposition; related to R8.7.

Use these names when referring to the values in normative instructions. Requirements must not substitute raw numeric values for parameter or constant names.

## Source requirement coverage index

Use this index as a final coverage sweep against the current source `SPEC.md`. It supplements, and does not replace, reading and applying each leaf requirement.

- `R1.1–R1.12`: use cases, classification, uncertainty, conflicts, authorization boundaries, confirming scope, and honest reporting — `When to use`, `Classify the request first`, `Mechanical and semantic checks`.
- `R2.1–R2.13`: file placement, index, Reference, status, stable contracts, obsolete rules, synchronized index/glossary — `Spec placement and lifecycle`.
- `R3.1–R3.19`: header, allowed sections, conditional `Tests`, section responsibilities, family placement, line format, verification markers — `Required spec structure`, `Requirement writing and identifiers`.
- `R4.1–R4.14`: stable hierarchical IDs, atomic/testable/observable requirements, terms, examples, verification and test procedures — `Requirement writing and identifiers`, `Interface and configuration`, `Mechanical and semantic checks`.
- `R5.1–R5.8`: complete interface and configuration contracts, correct parameter/constant/magic-number fields, links to active requirements — `Interface and configuration`.
- `R6.1–R6.13`: term IDs, glossary, owner terms, dependencies, mirrored relationships, language — `Terms and relationships between specs`.
- `R7.1–R7.15`: lint-first order, semantic pass, current Verification, deviation lifecycle and traceability — `Mechanical and semantic checks`, `Open deviations`.
- `R8.1–R8.27`: complete CLI, ordering, scanner, index/glossary checks, diagnostics, exit codes, limitations and test coverage — `speclint contract`.
- `R9.1–R9.20`: Scope Check, approval checkpoints, plan/tasks, decomposition, traceability and implementation verification — `Planning and implementation`.
- `R10.1–R10.13`: semantic review and final-report findings — `Review and final report`.

If any item in the index is not fully covered by the operative instructions, update those instructions; the presence of an index entry alone is not compliance.
