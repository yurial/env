---
name: tlc-run
description: Use when asked to run TLC, model-check a TLA+ spec, execute a tlc.cfg/tlc.live.cfg model, or interpret TLC output (violations, deadlocks, parse errors, coverage). Also the execution backend for tla-plus workflow steps that say "run TLC". Covers commands, flags, result classification, and the delegation protocol for running TLC via a cheap background subagent. Use ONLY for running TLC, not for writing specs (tla-plus) or proofs (tlaps).
---

# Running TLC: commands, result classification, delegation

This skill is the execution companion to `tla-plus` (spec authoring, models,
workflow) and `tlaps` (proofs). It assumes the spec module, the cfg file, and
the decision of WHAT to check already exist; this skill covers HOW to run the
check and HOW to read the result.

## 1. Inputs and commands

The run takes a spec module (.tla) and a cfg file placed next to it
(naming: `tlc.cfg`, `<module>.tlc.cfg`, variants `tlc.live.cfg` /
`tlc.impl.cfg` — see the tla-plus skill, section 6.1).

Component model pairs (tla-plus section 2b) mean more runs per component,
each still an ordinary module+cfg pair: the external module's
`<module>.tlc.cfg` and `<module>.tlc.live.cfg` (the contract standalone),
the internal module's `<module>.tlc.cfg`, `<module>.tlc.live.cfg` (local
liveness), and `<module>.tlc.impl.cfg` (`PROPERTY Refines` onto the
external contract), plus every importer's own `tlc.cfg` (composition;
imported guarantees are plain INVARIANT lines there). The pair's two
modules normally share one directory, so the `<module>.` prefix is the
normal form there — a bare `tlc.cfg` fits only a module alone in its
directory.

TLC is invoked with an explicit `-config` path — never rely on the
built-in `<ModuleName>.cfg` lookup.

```bash
# Safety run (default checks deadlock + INVARIANTs):
java -Xmx8g -jar tla2tools.jar -coverage 1 -workers auto \
     -metadir /tmp/tlc-states -cleanup -config tlc.cfg ModuleName 2>&1 | tee tlc.log

# Liveness run (after safety is clean; cfg has SPECIFICATION FairSpec + PROPERTY):
java -Xmx8g -jar tla2tools.jar -deadlock -workers auto \
     -metadir /tmp/tlc-states -cleanup -config tlc.live.cfg ModuleName 2>&1 | tee tlc.log

# Collect multiple violations instead of stopping at the first:
java -jar tla2tools.jar -continue -config tlc.cfg ModuleName

# Simulation (deep behaviors, not exhaustive):
java -jar tla2tools.jar -simulate num=100000 -depth 300 -coverage 1 \
     -config tlc.cfg ModuleName

# Bounded-depth exhaustive (no liveness):
java -jar tla2tools.jar -dfid 25 -config tlc.cfg ModuleName

# Specs spread over directories: classpath carries the module search path:
java -cp tla2tools.jar:TLA tlc2.TLC -config TLA/queue.tlc.cfg queue
```

Working rules:
- Run from the directory holding the .tla unless the cfg path is absolute or
  correctly relative; `-config` accepts relative paths (validated on TLC 1.8.0).
- Always `tee` full output to a log file; always `-metadir <dir> -cleanup` so
  state dirs never pollute the repo (add `states/`, `*.log`, `*_TTrace_*.tla`
  to .gitignore).
- Useful flags (TLC 1.8.0): `-coverage 1` (per-action counts), `-difftrace`,
  `-gzip`, `-fpmem 0.8`, `-maxSetSize N`, `-checkpoint <min>` + `-recover <id>`,
  `-tool`, `-continue`. Do not use `-nowarning` — warnings are load-bearing.
- Interruption: if `Progress:` lines show distinct states growing fast past
  several million, interrupt (Ctrl-C / kill) and report — the model needs
  shrinking (tla-plus section 5), not patience.

## 2. Result classification (what to report)

Green — ALL must hold:
- exit code 0, and
- a line `Model checking completed. No error has been found.`, and
- no `[ERROR]`/`Error:` lines.
Report: model file, `states generated / distinct states / depth` lines,
wall time, and the per-action coverage counts (from `-coverage 1`).

Violations (exit non-zero; observed exit 12 on TLC 1.8.0) — identify the
class and report the error line + the full counterexample trace (States 1..N,
`Back to state` for liveness):

| Output contains | Class | Report extra |
|---|---|---|
| `Invariant X is violated` | safety (X = TypeOK → type error) | trace states |
| `Deadlock reached` | deadlock | trace states |
| `Temporal properties were violated` | liveness | lasso (`Back to state`) |
| `Parsing error` / `Unknown operator` / `Multiply-defined symbol` | syntax | line number |
| `Attempted to enumerate a set of size` | state explosion | the set/size named |
| `Attempted to compute CHOOSE ... when no` | bad guard | line number |
| `Successor state is not completely specified` | incomplete action | line number |
| `is not defined in the specification` | cfg names a missing operator | the name |
| `TLC cannot handle the temporal formula` | fairness over variable set / bad PROPERTY form | line number |
| OutOfMemory / disk full | resource exhaustion | heap/disk facts |

Full diagnosis and fixes live in the tla-plus skill (sections 5 and 7
there); the runner classifies and reports, the caller decides the fix.
Coverage gate note: when reporting a green safety run, include the coverage
counts — an action with zero fires is itself a finding (tla-plus 6.3).

## 3. Delegation protocol (run TLC via a cheap background agent)

TLC runs are minutes-long, mechanical, and independent — delegate them to the
most cost-efficient agent available (the cheapest, least capable agent that
can still run a given bash command and copy output verbatim; pick by the
agents' cost/capability descriptions, not by habit) and continue other work
while it runs. The qualification bar is low: bash execution + verbatim
copying, nothing else.

The instruction to the runner agent MUST be self-contained (the dumb agent
knows nothing about the project) and include, verbatim:

1. **Workdir** — absolute path of the directory holding the .tla.
2. **Command** — the exact java line from section 1 (already includes cfg
   path, flags, tee target). The agent must not invent or alter flags; the
   only allowed change is the timeout.
3. **What is being checked** — one sentence: model kind (safety / liveness /
   refinement / simulation) and the property name(s) from the cfg; for safety
   runs with `-coverage 1`, also the list of action names the caller expects
   in the coverage statistics (e.g. Send, Recv, Terminal) so the runner can
   report missing ones.
4. **Expected output** — green form (section 2) or "a violation may occur,
   that is a valid result, do not treat as your failure".
5. **Report format** — exactly:
   - RESULT: green | violation:<class> | syntax | resource | timeout
   - EVIDENCE: the `Model checking completed` line OR the error line(s),
     verbatim, plus `states generated / distinct / depth` lines
   - TRACE: full counterexample states if a violation (verbatim)
   - COVERAGE: per-action count lines verbatim; for each caller-listed
     action absent from the statistics, one line `<action>: absent`
6. **Boundaries** — timeout (e.g. 20 min; on timeout kill java and report
   RESULT: timeout with the last `Progress:` line); do not edit any file;
   do not retry with changed flags; do not summarize the trace in your own
   words — copy it.

While the runner works, the caller proceeds with unrelated tasks; treat the
result as arriving asynchronously. Never let the runner agent "fix" a
violation it finds — classification and verbatim reporting is its whole job.

## 4. Runner-side quick reference (for the delegated agent)

If you are the runner agent: cd to the given workdir, run the given command
with stdout captured (tee), wait for completion or timeout, then produce the
report from section 3 item 5 by copying lines from the log — no analysis, no
fixes, no edits. If the command fails to start (java/jar missing), report
RESULT: resource with the error line.
