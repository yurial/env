---
name: tlaps
description: Use when the user asks for a mathematical proof of a TLA+ theorem ("prove", "proof", "theorem holds for all N"), when writing or checking hierarchical TLA+ proofs (proof steps like <1>1, BY/QED/SUFFICES/CASE/WITNESS), when running or debugging tlapm, or when a property is inherently unbounded so TLC model checking cannot cover it. Covers tlapm invocation, z3/SMT backends, proof structure, and obligation-failure triage. For model checking with TLC use the tla-plus skill instead.
---

# TLAPS: writing and checking TLA+ proofs

Goal: machine-checked *mathematical* proofs of TLA+ theorems — statements that hold
for ALL behaviors and ALL parameter values, not just small models.

Tool choice (hard rule): TLC model checking is the default (see the `tla-plus` skill).
Switch to TLAPS only when (a) the user explicitly asks for a proof, or (b) the
property is inherently unbounded (arbitrary node count, unbounded data) so no TLC
model can cover it. Even then: run the same property through TLC on small bounds
FIRST — a 30-second counterexample beats hours of failing proof steps on a false
theorem.

Non-negotiable: a proof is done only after `tlapm` exits 0 with
`All N obligations proved` (no ERROR lines). Never claim "proved" from reading the
proof text — only from tlapm output.

All patterns below were validated against TLAPS 1.5.0 (tlapm 1.5.0, bundled zenon
0.8.4 + Isabelle 2011-1, system z3 4.8.12 auto-detected). `.tlacache` note: tlapm
caches verdicts by fingerprints; when re-running to see *which backend* proves what,
delete `.tlacache` first or you get stale "All 0 obligations proved" lines.

## 1. Environment

Install (prebuilt, Linux x86_64):
```bash
curl -sL -o tlapm-inst.bin \
  https://github.com/tlaplus/tlapm/releases/download/202210041448/tlaps-1.5.0-x86_64-linux-gnu-inst.bin
chmod +x tlapm-inst.bin && ./tlapm-inst.bin -d <DIR>   # DIR/bin/tlapm
export PATH=<DIR>/bin:$PATH
```
`tlapm --version` must print 1.5.0. `tlapm --config` shows detected backends: it
auto-uses the system `z3` (invoked as `z3 -smt2 ...`); zenon and Isabelle ship in the
bundle; cvc4/yices/veriT/SPASS are absent unless installed separately. No opam/OCaml
toolchain is needed for the prebuilt.

## 2. Where proofs live

Put proofs in a separate module `FooProofs.tla` that EXTENDS `Foo` (convention from
tlaplus/examples); TLC does not load it (it is outside the root spec module's
dependency graph), so proof text never interferes with model checking. Simple
theorems may also live inline in the spec module. Spec modules stay free of `TLAPS`
dependencies where possible.

Placement follows the tla-plus layout (proof module sits NEXT TO its spec —
tlapm resolves both from the working directory without flags):

```
Small:    <library>.tla + <library>Proofs.tla            (repo root)
Medium:   TLA/<component>.tla + TLA/<component>Proofs.tla
Colocated: <component path>/<component>.tla
         + <component path>/<component>Proofs.tla
```

- One proof module per spec module — never a shared Proofs file for several
  specs; a proof module without its spec next to it is misplaced.
- `.tlacache/` is created by tlapm next to the proof files — keep it out of
  version control (gitignore), wherever the layout puts it.
- In `TLA/index.md`, proved specs may carry a marker so machine-checked
  theorems are visible at a glance: `- TLA/queue.tla — delivery guarantees
  (proved: queueProofs.tla)`. The marker names the proof module and updates
  in the same commit as the proof module's create/delete.

## 3. Proof language (validated forms)

```tla
THEOREM Spec => []Inv
<1>1. Init => Inv                       \* numbered step, formula
  BY DEF Init, Inv                      \* leaf: facts and/or definitions
<1>2. Inv /\ [Next]_vars => Inv'        \* step-lemma (pointwise!)
  <2>1. CASE Next                       \* CASE = separate step; prove via ITSELF
    BY <2>1 DEF Next, Inv               \* <2>1 as fact brings Next = TRUE
  <2>2. CASE UNCHANGED vars
    BY <2>2 DEF vars, Inv
  <2> QED BY <2>1, <2>2 DEF Next
<1> QED BY <1>1, <1>2, PTL DEF Spec     \* PTL = temporal inference (invariant rule)
```

Syntax rules (each was violated-and-fixed during validation; all produce confusing
errors otherwise):

- Every proof sentence sits on its own `<n>` line; a numbered subproof (`<1>1.`,
  `<2>3.`) ends with a `<n> QED` step at the same level. Unnumbered sentences
  (`<2> TAKE ...`, `<2> WITNESS ...`, `<2> DEFINE ...`, `<2> USE ...`, `<1> HAVE ...`)
  are followed by `<n> QED` or subsequent numbered steps.
- `CASE X` is a step whose proof *references the case step itself* (`BY <2>1`) to get
  hypothesis X = TRUE. Never write `CASE X => ...` inline.
- Leaf forms: `OBVIOUS`, `BY <facts> [DEF <defs>]`. `BY DEF` with an empty name list
  is a parse error. Facts can be step refs (`<1>2`), hypotheses, or theorem names.
- Definitions are NOT unfolded automatically: a leaf proving something about `Inv`
  must say `DEF Inv`. INSTANCE-substituted operators need the qualified name:
  `DEF U!NextU` (plain `DEF NextU` leaves the goal unexpanded — common failure).
- `WITNESS expr \in Set` — the `\in` part is what supplies set membership; a bare
  `WITNESS expr` loses the membership fact and the QED fails.
- `TAKE x \in S` introduces x for the following steps.
- `SUFFICES ASSUME NEW CONSTANT S, hyp PROVE goal` — splits goal into hypotheses;
  end with `OBVIOUS`-provable trivial remainder. `NEW CONSTANT`/`NEW VARIABLE`/plain
  `ASSUME op` forms all parse; prefer explicit `NEW`.
- PTL steps: `BY <steps>, PTL` performs temporal inference. It handles ONE pattern at
  a time (init + step-lemma => invariant; []TypeOK + step => []goal). A final QED
  chaining three facts through PTL at once fails — split into an intermediate
  `<1>4. SpecC => [][U!NextU]_varsC BY <1>2, <1>3, PTL DEF SpecC` step.

## 4. Backends (tlapm 1.5.0 semantics — measured, not documented)

- **Automatic**: by default tlapm tries backends per obligation (zenon, then SMT,
  then Isabelle). `-v` shows lines like `(* ... using SMT(v3) *)`. The SMT backend
  runs the configured solver — z3 by default.
- **`BY Z3` does NOT select the z3 backend** in 1.5.0: `Z3` resolves to the constant
  `TRUE` from the TLAPS module, enters the obligation as a useless hypothesis, and
  adds one extra trivial obligation. Same for `SMT`, `Isa` names in BY clauses.
  (Upstream examples carry `BY ..., Z3`; on 1.5.0 it is harmless but inert.)
- **Force/limit backends with CLI options**, not BY clauses: `--method smt`
  (only SMT), `--method zenon` (no arithmetic theories — nonlinear goals like
  `(x*y=0) => x=0 \/ y=0` FAIL under zenon-only and pass under default/SMT),
  `--method auto|blast|force` (Isabelle tactics), `--solver z3`, `--smt-logic AUFLIA`.
- **Timeouts**: `--stretch 2` multiplies all backend timeouts by 2. Default zenon
  timeout ~10s, SMT ~5s, Isabelle ~30s.
- **Isabelle cross-check**: `-C` re-checks proofs in Isabelle/TLA+ (slowest,
  highest assurance; bundle ships Isabelle2011-1).
- Missing external solvers (cvc4, yices, veriT) are reported by `tlapm --config`
  and simply never tried.

## 5. Commands

```bash
tlapm FooProofs.tla                 # check all proofs; exit 0 = all proved
tlapm -v FooProofs.tla              # verbose: which backend proved what
tlapm --timing FooProofs.tla        # per-phase runtime table
tlapm --threads 8 FooProofs.tla     # parallel obligations
tlapm -k FooProofs.tla              # keep going after failures (see all errors)
tlapm --method smt FooProofs.tla    # limit to SMT(z3)
tlapm --method zenon FooProofs.tla  # limit to zenon (no set/arith theories)
tlapm -C FooProofs.tla              # re-verify with Isabelle
tlapm --line 42 FooProofs.tla       # prove only the theorem at line 42
```
Exit codes: 0 = all obligations proved; 3 = parse error, unproved obligations, or
backend failure. Output to trust: lines `[INFO]: All N obligations proved.` and
absence of `[ERROR]`.

`.tlacache/` (created next to the file) stores fingerprints; unchanged obligations
are skipped on re-runs (fast iteration). Add `.tlacache/` to `.gitignore`. Delete it
when you need honest "which backend" data.

## 6. Reading failures

Output shape on failure:
```
File "./Foo.tla", line L, characters A-B:
[ERROR]: Could not prove or check:
           ASSUME NEW VARIABLE ..., <hyp definitions and facts>
           PROVE  <goal>
```
The printed obligation is exactly what the backends failed on. Triage:

| Symptom in obligation | Cause | Fix |
|---|---|---|
| Goal mentions operator names unexpanded; hypotheses show `Op == ...` | `DEF` missing that operator | add to BY DEF list |
| Goal like `U!NextU` with `U!NextU == c' > c` shown but still failed | arithmetic/int theory beyond zenon | keep default methods (SMT picks it up) or `--method smt` |
| Hypothesis needed (e.g. `c \in Nat`) absent from ASSUME list | type invariant not in scope | add TypeOK fact: prove `Spec => []TypeOK` first, pass as step fact |
| `PROVE Z3` (or SMT/Isa) as the goal itself | backend name written in BY clause — parsed as fact `TRUE`, inert | remove it from BY; use `--method` |
| Temporal goal (contains `[]`/`~>`) left to zenon | PTL missing from QED step | add `PTL` to the BY clause; if still failing, split into intermediate single-pattern PTL steps (section 3) |
| `Zenon error: exhausted search space` | zenon tried and failed (goal needs SMT/Isa or more facts) | usually fine if another backend proves it; check for `[ERROR]` |
| Parse error `Unexpected keyword THEOREM/TAKE` | proof sentence placed after a finished QED / wrong level | every sentence on its own `<n>` line before QED |
| `extra step(s) after finished proof` | numbered step after the `<1> QED` of the same level | move it before QED or into a new level |

## 7. Workflow

1. State the theorem informally; run TLC on the equivalent bounded property first
   (tla-plus skill). Counterexample => fix spec; only then prove.
2. Write the proof skeleton top-down: `<1>` steps as an informal proof outline
   (init, step-lemma, conclusion), each leaf `OBVIOUS` — run tlapm, see which
   obligations fail (`-k` to see all).
3. For each failed leaf: read the printed obligation; usually add `DEF`, a TypeOK
   fact, split the step, or restructure CASE-wise (section 6 table).
4. Strengthen with helper lemmas (THEOREM ... proved separately, referenced as facts)
   instead of monster leaves. Library: `FiniteSetTheorems` (FS_Subset, ...),
   `NaturalsInduction` (NatInduction, ...) — EXTENDS them to use theorem names as facts.
5. Full run green (`exit 0`, `All N obligations proved`) => optionally `-C` for
   Isabelle re-verification of high-assurance theorems.
6. Record in the module header: tlapm version, date, obligation count, `-C` status.
   If the proved theorem concerns an algorithm governed by a project spec (spec
   skill), mirror into that spec's `Verification` section: algorithm name +
   requirement IDs, tool = TLAPS (proof, not bounded evidence), proof module
   name, and what the theorem does NOT cover (proofs check the stated theorem
   only — list the unproven properties separately).

## 8. Refinement proofs between abstraction levels

Validated pattern (lower module L implements upper module U via
`U == INSTANCE Upper WITH u <- c`):

```tla
TypeOK == c \in Nat

THEOREM SpecC => U!InitU /\ [][U!NextU]_varsC
<1>1. InitC => U!InitU
  BY DEF InitC, U!InitU
<1>2. SpecC => []TypeOK                       \* type invariant first
  <2>1. InitC => TypeOK
    BY DEF InitC, TypeOK
  <2>2. TypeOK /\ [NextC]_varsC => TypeOK'    \* pointwise step-lemma
    <3>1. CASE NextC
      BY <3>1 DEF NextC, TypeOK
    <3>2. CASE UNCHANGED varsC
      BY <3>2 DEF varsC, TypeOK
    <3> QED BY <3>1, <3>2 DEF NextC
  <2> QED BY <2>1, <2>2, PTL DEF SpecC
<1>3. TypeOK /\ [NextC]_varsC => [U!NextU]_varsC     \* pointwise impl-map step
  <2>1. CASE NextC
    BY <2>1 DEF NextC, TypeOK, U!NextU
  <2>2. CASE UNCHANGED varsC
    BY <2>2 DEF varsC
  <2> QED BY <2>1, <2>2 DEF NextC
<1>4. SpecC => [][U!NextU]_varsC
  BY <1>2, <1>3, PTL DEF SpecC
<1> QED BY <1>1, <1>4, PTL DEF SpecC
```

Critical details (each cost a failed run):
- Prove the CONJUNCTION `U!InitU /\ [][U!NextU]_varsC`, not `U!SpecU`: the latter
  unfolds to `[][NextU]_varsU` whose frame `_varsU` does not syntactically match
  `_varsC` after substitution, and the final PTL step fails on the mismatch.
- `DEF U!NextU` (qualified) — required to unfold the INSTANCE-substituted definition.
- The type invariant is not optional: `c' = c + 1 => c' > c` needs `c \in Nat` in
  scope, supplied by `<1>2` + pointwise `<1>3` hypothesis.
- `ASSUME TypeOK, NextC PROVE ...` as a step loses the hypotheses' truth after
  DEF-unfolding (they print as bare definitions in the obligation) — use CASE steps
  with self-reference instead (section 3).
- One PTL pattern per step: `<1>4` exists because the three-way `<1> QED` chaining
  fails.

## 9. Anti-patterns

- Proving before TLC-checking the bounded version — proving false theorems wastes hours.
- `BY Z3` / `BY SMT` expecting backend selection — inert on 1.5.0 (section 4).
- Giant single leaves — split; tlapm error messages are per-obligation.
- Forgetting `DEF` (definitions never auto-unfold) or using unqualified `DEF NextU`
  for INSTANCE operators.
- `WITNESS e` without `\in Set`.
- Trusting `.tlacache`-fed re-runs during backend debugging.
- Claiming "proved" from exit code alone without checking for `[ERROR]` lines under
  `-k` runs (exit 3 with partial progress still prints some INFO lines).
- Writing proofs for liveness properties without checking current TLAPS temporal
  support first — keep liveness on TLC by default.
