# `speclint.py`

Status: stable
Spec source of truth for: `speclint.py` — mechanical checking of Markdown specifications, indexes, and glossaries

## Overview

`speclint.py` performs deterministic mechanical checks of specification formatting, prefixed-entry structure, numeric literals, indexes, and glossaries. Checks for semantic completeness of requirements and correctness of their meaning are outside the script's scope.

## Scope

**In:** checking Markdown files and directory trees; recognizing file types; checking prefixed entries and references; scanning numeric literals; checking `index.md` and `GLOSSARY.md`; emitting diagnostics and exit codes.

**Out (non-goals):** semantic assessment of requirement clarity and atomicity; proving the truth of statements in `Verification`; assessing the semantic sufficiency of test procedures; evaluating language quality; analyzing source-code conformance to requirements.

## Definitions

- `speclint/path` — a path to a Markdown file or directory passed to the CLI.
- `prefixed entry` — an entry with an identifier from the `R`, `E`, `I`, `V`, `T`, or `J` family in the section designated for that family.
- `group entry` — an entry with child IDs; `leaf entry` — an entry without child IDs.
- `finding` — an issue detected by a check that affects the final exit code.
- `warning` — a diagnostic warning that is not an error.
- `section` — a Markdown section identified by its heading outside a recognized fenced code block.

## Interface

- `speclint.py <path>...` — checks one or more paths; each path must refer to an existing Markdown file or directory.
- `path` — a path to a file with the `.md` extension or to a directory processed recursively.
- Exit codes: `speclint-clean-exit-code` — no errors or warnings; `speclint-warning-exit-code` — warnings but no errors; `speclint-error-exit-code` — errors or an invalid invocation.
- Diagnostics are written to `stderr` in the format `<file>:<line>: <message>`; a warning begins with `speclint: warning:`.
- Markdown file type is determined by basename: `index.md` is an index, `GLOSSARY.md` is a glossary, and any other `.md` file is a spec.

## Configuration

- `speclint-clean-exit-code`: integer; `0`; fixed; exit code when there are no findings.
- `speclint-warning-exit-code`: integer; `1`; fixed; exit code when warnings are present and there are no errors.
- `speclint-error-exit-code`: integer; `2`; fixed; exit code for errors or an invalid invocation.

## Requirements

- R1. CLI and input-file selection:
- R1.1. verification=automated; The script accepts one or more positional paths to Markdown files or directories.
- R1.2. verification=automated; No arguments, a nonexistent path, or a path to a file whose extension is not `.md` produces a diagnostic on `stderr` and the `speclint-error-exit-code`.
- R1.3. verification=automated; When given a directory, the script recursively considers all files with the `.md` extension as candidates for checking.
- R1.4. verification=automated; When processing a directory, the script processes all `index.md` files in sorted order first, then `GLOSSARY.md`, then the remaining `.md` files in sorted order.
- R1.5. verification=automated; File type is determined by basename: `index.md` is an index, `GLOSSARY.md` is a glossary, and other Markdown files are specs.

- R2. Markdown structure and sections:
- R2.1. verification=automated; The script recognizes sections by the first alphabetic word of a Markdown heading outside a recognized fenced code block.
- R2.2. verification=automated; The script checks that entry families appear only in their corresponding sections: `R` in `Requirements`, `I` in `Implementation`, `E` in `Examples`, `T` in `Tests`, `J` in `Justification`, and `V` in `Verification`.
- R2.3. verification=automated; Every non-empty content line in `Requirements`, `Examples`, `Implementation`, `Verification`, `Tests`, and `Justification` begins in column zero with `- ` followed by an ID from the corresponding family.
- R2.4. verification=automated; Every prefixed entry occupies one physical line, begins in column zero with `- `, and has its ID immediately after the marker, without Markdown nesting to express hierarchy.
- R2.5. verification=automated; The script reports a prefixed entry that begins with indentation or continues on the next indented line.
- R2.6. verification=automated; The script does not treat headings inside a recognized fenced code block as section changes.

- R3. Identifiers and references:
- R3.1. verification=automated; The script checks the syntax and uniqueness of R-, E-, I-, V-, T-, and J-IDs within a file.
- R3.2. verification=automated; For hierarchical IDs, the script checks that all ancestors exist, group and leaf entries are valid, and no group is empty.
- R3.3. verification=automated; The script checks that every E-ID mirrors an existing R-ID.
- R3.4. verification=automated; In `Tests`, the script checks references only to existing leaf R-IDs with `verification=automated` or `verification=scenario`.
- R3.5. verification=automated; The script checks that every leaf R-ID contains exactly one `verification` marker with the value `automated`, `scenario`, `manual`, or `analysis`.
- R3.6. verification=automated; The script checks that every leaf R-ID with `verification=automated` or `verification=scenario` is mentioned in at least one leaf T-ID entry.
- R3.7. verification=automated; The script does not require T-IDs for leaf R-IDs with `verification=manual` or `verification=analysis`.
- R3.8. verification=automated; Missing required T-ID references are reported as errors; the presence of a reference alone is not treated as proof of semantic sufficiency of the procedure.

- R4. Numeric literals:
- R4.1. verification=automated; The script reports bare numeric literals outside `Configuration` and `Examples`, inline code in backticks, and recognized fenced code blocks.
- R4.2. verification=automated; The numeric scanner recognizes integers and decimals, decimal separators using a dot or comma, and numeric tokens with alphabetic suffixes when the token begins with a number.
- R4.3. verification=automated; The numeric scanner does not treat digits inside identifiers, versions, TLS-like tokens, or tokens beginning with a letter as bare numeric literals.
- R4.4. verification=automated; A fenced code block is recognized only when its marker is in column zero; lines in a recognized block are excluded from numeric scanning.
- R4.5. verification=automated; A fenced code block's closing marker does not have to match the opening marker's character or length.
- R4.6. verification=automated; If a fenced code block is not closed, all subsequent lines through end of file are treated as part of the block for numeric scanning and section switching.

- R5. Indexes:
- R5.1. verification=automated; For `index.md`, the script checks compliance with the index-formatting requirements defined by the specification-authoring rules (SPEC R2.8), including the required header, column order, and non-empty data cells. This rule defines the checks performed by the script; it does not independently define the document format.
- R5.2. verification=automated; The script accepts only `draft` or `stable` for `Status` and checks that `Reference` consists of lowercase ASCII letters and digits separated by single hyphens.
- R5.3. verification=automated; The script checks that every path listed in the index exists.
- R5.4. verification=automated; An index path is resolved relative to the Git repository root when it can be determined; otherwise it is resolved relative to the parent directory of `specs/` or the index directory itself.

- R6. Glossary:
- R6.1. verification=automated; For `GLOSSARY.md`, the script checks compliance with the glossary-formatting requirements defined by the specification-authoring rules (SPEC R6.5), including the required header, column order, row cells, term ID format, English alphabet, alphabetical ordering, and `Defined in` format. This rule defines the checks performed by the script; it does not independently define the document format.
- R6.2. verification=automated; Term ID prefixes are resolved against Reference IDs collected from indexes.
- R6.3. verification=automated; If Reference IDs cannot be collected, the script skips prefix-resolution checking and emits a warning.

- R7. Diagnostics and termination:
- R7.1. verification=automated; Every finding is written to `stderr` in the format `<file>:<line>: <message>`.
- R7.2. verification=automated; Every warning has the prefix `speclint: warning:`.
- R7.3. verification=automated; When there are no findings, the script returns `speclint-clean-exit-code`.
- R7.4. verification=automated; When warnings are present and there are no errors, the script returns `speclint-warning-exit-code`.
- R7.5. verification=automated; When errors are present, the script returns `speclint-error-exit-code`.

- R8. Limits of mechanical checking:
- R8.1. verification=analysis; The script does not claim that mechanical checking establishes requirement clarity, atomicity, or semantic completeness.
- R8.2. verification=analysis; The script does not claim that checking confirms the truth of statements in `Verification`, semantic justification of relationships, or language quality.
- R8.3. verification=analysis; Limitations of the line-by-line scanner, including its inability to detect unindented continuations and its fenced-code-block recognition behavior, are documented and considered during review.

## Tests

- T1. CLI and directory traversal:
- T1.1. R-ID=R1.1,R1.2; procedure=run the CLI without arguments, with a nonexistent path, and with an existing file whose extension is not `.md`; conditions=run each case separately and record `stderr` and the exit code; expected=each invalid invocation produces a diagnostic and returns `speclint-error-exit-code`.
- T1.2. R-ID=R1.3,R1.4,R1.5; procedure=create a temporary tree with several `index.md`, `GLOSSARY.md`, and ordinary Markdown files in different subdirectories, then run the script on the root directory; conditions=paths and file contents are predefined; expected=all `.md` files are processed recursively, type is determined by basename, and processing order follows the specified rule.

- T2. Sections and entry formatting:
- T2.1. R-ID=R2.1,R2.2,R2.3,R2.4,R2.5,R2.6; procedure=run the script on fixtures with valid and invalid section headings, prefixes, indentation, multi-line entries, and headings inside fenced code blocks; conditions=each fixture has an expected result; expected=each formatting violation is reported, and headings inside a recognized block do not change the section.

- T3. Identifiers and test references:
- T3.1. R-ID=R3.1,R3.2,R3.3,R3.4,R3.5,R3.6,R3.7,R3.8; procedure=run the script on fixtures with duplicate and malformed IDs, missing ancestors, empty groups, invalid E-references, invalid or repeated verification markers, and missing or extra T-references; conditions=check a valid fixture and each violation class separately; expected=the valid fixture passes, violations are reported, T-references are required only for `automated` and `scenario`, and the presence of a reference is not treated as semantic assessment.

- T4. Numeric scanner:
- T4.1. R-ID=R4.1,R4.2,R4.3,R4.4,R4.5,R4.6; procedure=run the scanner on paired fixtures containing bare numbers, numbers in excluded sections and code blocks, digits in IDs and versions, tokens with alphabetic suffixes, and closed and unclosed fenced code blocks; conditions=variants differ only in the context being checked; expected=bare numeric literals outside exclusions are reported, excluded tokens are not reported, and section switching follows the block rules.

- T5. Index and glossary:
- T5.1. R-ID=R5.1,R5.2,R5.3,R5.4; procedure=check table-formatted indexes with valid and invalid headers, row cell counts, fields, statuses, Reference IDs, and paths, both when the Git root can be determined and when it cannot; conditions=paths are checked under both resolution schemes; expected=invalid fields and nonexistent paths are reported, and path resolution follows the specified rule.
- T5.2. R-ID=R6.1,R6.2,R6.3; procedure=check table-formatted glossaries with valid and invalid headers, row cell counts, full term IDs, sorting, `Defined in` cells, and resolvable/unresolvable prefixes; conditions=run a separate case without collected Reference IDs; expected=format violations are reported, and when Reference IDs are unavailable a warning is emitted and only prefix-resolution checking is skipped.

- T6. Diagnostics and exit codes:
- T6.1. R-ID=R7.1,R7.2,R7.3,R7.4,R7.5; procedure=run the script on fixtures with no findings, warnings only, and errors; conditions=each fixture is designed for one result class; expected=diagnostic formatting and warning prefix are correct, and exit codes match the corresponding configured values.

## Implementation

- I1. The implementation is in `speclint.py`. The algorithm must remain mechanical and reproducible: recognition rules and their limitations are defined by this specification; semantic analysis of requirements and checking source-code conformance are outside the script's responsibility.
