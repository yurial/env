# Skill `glab-autoreview`

Status: draft
Spec source of truth for: the `glab-autoreview` skill — the SKILL.md guide «glab-autoreview: continuous automated MR review — supervisor, watchers, restart safety» (standing automated review of GitLab merge requests where the user is the reviewer) and the watcher prompt template (`references/watcher-prompt.md`)
Reference: glab-autoreview

## Overview

The `glab-autoreview` skill governs a standing automated review service for GitLab merge requests on which the user is the reviewer. It is a two-level orchestration over the `glab` skill: a supervisor on the main agent — an hourly scheduler whose gate command is the fresh reviewer listing (`mr-list.sh --role reviewer --state opened`), a registry comparison, watcher launches under a slot limit with a pending-launch queue, and completion control for closed or merged MRs — and per-MR watcher subagents, each with its own short-interval scheduler, a dedicated worktree, and full ownership of one MR's review: comments, replies, thread resolution, and the approve state. The skill's normative core is restart safety: every watcher run resumes by reading the full discussion state from GitLab, open own threads are never re-posted or duplicated, and a restart is indistinguishable from a regular round. The behavioral contracts fix the `[ai] ` comment prefix (via `GITLAB_COMMENT_PREFIX`) as authorship marker and own-thread filter, line-anchored posting only after anchor validation against diff hunks with the unpositioned fallback, the approve invariant in both directions, the own-thread lifecycle (confirm and resolve fixed, agree and resolve justified, contest wrong), watcher completion on closed or merged MRs, the anti-blocking discipline (publish validated findings immediately, publish subagent findings as a follow-up, return a result after each completed step), the watcher prompt contract (task and requirements only, no recipes), the three-part stop, and the registry contract (states, sections, single-writer). The skill inherits every GitLab mechanic from the `glab` skill by section reference and does not restate it (R1.1).

The skill activates when the user asks for continuous, standing review of GitLab merge requests where they are the reviewer: watching all MRs awaiting their review in a project, resuming review state across restarts and session changes, maintaining the approve state according to the invariant, processing author replies in the watcher's own threads, and stopping the whole service on demand (R14.4). The canonical trigger text is the frontmatter `description` (Interface). The skill does not activate for one-off reviews without monitoring, for other GitLab work, or for other forges (Scope, Out).

## Scope

In:
- the relationship to the `glab` skill: build on it by section reference, no duplication, mechanics-versus-orchestration ownership (R1.1);
- the prefix fixation `[ai] ` via `GITLAB_COMMENT_PREFIX` as authorship marker and own-thread filter (R1.2);
- the supervisor: hourly scheduler, gate command over `mr-list.sh`, registry comparison, watcher launches, slot limit with pending-launch queue, completion control, restart tolerance, the no-direct-MR-writes rule (R2.1..R2.7);
- the registry: location, entry format, states, sections, single writer, arbitration role against legal duplicate sessions (R3.1..R3.3);
- restart safety: resumption instead of a fresh start, mandatory first read of all discussions, no re-posting or duplication of open own threads, fixed-check before new findings, GitLab as the source of truth, session-change tolerance (R4.1..R4.6);
- the watcher round: the short-interval scheduler with the has-updates gate, the round order (R5.1, R5.2);
- prefix and ownership: the prefix on every posted body, the mechanical own-thread selection, the prohibition on touching others' threads including bots (R6.1..R6.3);
- anchors: client-side hunk validation before any positioned post, the unpositioned fallback with `<path>:<line>` in the text (R7.1, R7.2);
- the approve invariant in both directions, the blocking classification of findings, the local merge-tree check over the API merge status (R8.1..R8.4);
- the own-thread lifecycle: confirm-and-resolve, agree-and-resolve, contest, resolve discipline (R9.1..R9.3);
- watcher completion on closed or merged MRs and the supervisor's done marking (R10.1, R10.2);
- the anti-blocking discipline: immediate publication, follow-up batches, per-step results, the no-recipes prompt rule (R11.1..R11.3);
- the watcher prompt contract and the template in `references/watcher-prompt.md` (R12.1, R12.2);
- the three-part stop and the registry marking after a user stop (R13.1, R13.2);
- document structure, placeholders, instance-dependent markers, and the canonical frontmatter (R14.1..R14.4).

Out (non-goals):
- one-off MR reviews without continuous monitoring — the `glab` skill's reviewer workflows cover them; this skill must not be loaded for them;
- GitLab mechanics itself — glab calls, toolkit contracts, comment protocols, anchor mechanics, the draft review flow, pagination, HTTP-error discipline: owned by the `glab` skill and referenced, never restated here;
- merging, closing, or renaming the reviewed MRs — merge decisions stay with the user;
- other forges (GitHub, Bitbucket) and their CLIs;
- CI/CD debugging and pipeline authoring — the watcher may consume CI status as an update signal, nothing more;
- secret management — no token handling beyond what the `glab` skill already prescribes.

## Definitions

- `glab-autoreview/supervisor` — the standing role of the main agent: the hourly scheduler, the gate listing, the registry comparison, watcher launches, and completion control; it writes only the registry and its own schedulers, never MR objects (R2.1..R2.7).
- `glab-autoreview/watcher` — one subagent of subagent type `watcher-subagent-type` per watched MR, owning that MR's review: comments, replies, thread resolution, and the approve state (R2.4, R6, R8, R9).
- `glab-autoreview/round` — one pass of a watcher: resume read, state refresh, open-thread triage, delta review, publication, approve update, summary (R5.2).
- `glab-autoreview/registry` — the file at `registry-path`: the single bookkeeping artifact of the service, written by the supervisor alone and read by watchers for orientation (R3.1, R3.2).
- `glab-autoreview/own-thread` — a discussion of the watched MR whose first non-system note starts with `watcher-comment-prefix`; the write scope of the watcher is its own threads, the approve state, and nothing else (R6.2, R6.3).
- `glab-autoreview/open-issue` — an own thread of the watcher that is not resolved; the set of open issues is rebuilt from GitLab on every run (R4.2).
- `glab-autoreview/blocking-problem` — a problem that must be fixed before merge; every published finding states its blocking classification explicitly, which keeps the approve invariant decidable from the published threads (R8.1, R8.3).
- `glab-autoreview/restart-safety` — the property that any launch of a watcher — first, scheduled, or restarted — resumes from the GitLab discussion state and is indistinguishable from a regular round (R4.1).
- `glab-autoreview/pending-launch` — the registry state of an MR whose watcher is planned but not yet launched because the slot limit is reached (R2.3).
- `glab-autoreview/three-part-stop` — the complete stop of the service: abort the running watcher sessions, remove the supervisor scheduler, and message the finished watchers to remove their schedulers and finish (R13.1).
- `glab-autoreview/zombie-round` — a scheduler fire of a watcher session that no longer works: aborting sessions does not remove schedulers created inside them (R13.1).

## Interface

The skill's public artifacts: the frontmatter of SKILL.md, the document structure of SKILL.md, the watcher prompt template at `references/watcher-prompt.md`, and the named rule components.

Frontmatter (canonical, verbatim):

```yaml
---
name: glab-autoreview
description: "Use when the user asks for continuous automated review of GitLab merge requests where the user is the reviewer: a standing hourly supervisor on the main agent (gate command mr-list.sh --role reviewer --state opened --project <group/project>, registry comparison in ~/tmp/mr-watch/registry.md, watcher launches under a slot limit with a pending-launch queue, completion control for closed/merged MRs), one watcher subagent (assistant_high) per MR with its own 15-minute scheduler and dedicated worktree (~/wt/<repo>/mr-<iid>, branch mr-<iid> from origin/main, passed as the first Worktree: line), restart-safe review rounds (every run resumes by reading all MR discussions from GitLab with pagination; open [ai] threads are never re-posted or duplicated — matching is by file and topic), the `[ai] ` comment prefix set via GITLAB_COMMENT_PREFIX as both authorship marker and own-thread filter, line-anchored comments only after anchor validation against diff hunks with the unpositioned <path>:<line> fallback, the approve invariant (approve present iff no unresolved blocking problems; unapprove when new blockers appear; non-blocking remarks never cancel an approve), own-thread lifecycle (confirm and resolve fixed threads, agree and resolve justified author replies verified in code, contest wrong replies with facts, never touch others' threads including bots), watcher completion on closed/merged MRs (scheduler removed, approve settled, final summary), anti-blocking discipline (publish validated findings immediately, publish subagent findings as a follow-up, return a result after each completed step), the three-part stop (abort sessions, remove the supervisor scheduler, tell watchers to remove theirs), and traps: stale merge_status vs the local merge-tree check, legal duplicate watcher sessions arbitrated by the registry, project-path 404 resolved via search?scope=projects, glab api exiting 0 on HTTP errors. Builds on the glab skill (gitlab-tools, comment protocols, scope=all, draft review flow) for all underlying mechanics. Use ONLY for continuous GitLab MR review with monitoring, not for one-off reviews without monitoring, other GitLab work, or other forges."
---
```

Norms of form:

- The frontmatter contains `name` and `description`; their values are canonical verbatim as in the block above.
- The `description` enumerates the trigger scope and ends with the boundary sentence «Use ONLY for continuous GitLab MR review with monitoring, not for one-off reviews without monitoring, other GitLab work, or other forges.»
- The document title of the skill: «glab-autoreview: continuous automated MR review — supervisor, watchers, restart safety».

SKILL.md document structure (mapping to requirements):

```
# glab-autoreview: continuous automated MR review — supervisor, watchers, restart safety
<intro: purpose, two levels, relation to glab, instance-observation caveat, placeholder notice>
## 1. Relationship to the glab skill                     — R1.1, R1.2
## 2. Architecture: supervisor and per-MR watchers       — R2.1..R2.7
## 3. The registry                                       — R3.1..R3.3
## 4. Restart safety: every run resumes (critical)       — R4.1..R4.6
## 5. The watcher round                                  — R5.1, R5.2
## 6. Comment prefix `[ai] ` and thread ownership        — R6.1..R6.3
## 7. Anchors: validate before posting                   — R7.1, R7.2
## 8. The approve invariant                              — R8.1..R8.4
## 9. Own-thread lifecycle: fixed, justified, contested  — R9.1..R9.3
## 10. Completion: closed or merged                      — R10.1, R10.2
## 11. Anti-blocking: publish early, return per step     — R11.1..R11.3
## 12. The watcher prompt                                — R12.1, R12.2
## 13. Stopping the system: the three-part stop          — R13.1, R13.2
## 14. Traps (consolidated)                              — R14.3 (trap highlighting)
```

The section order is canonical: the glab relationship comes first; the architecture precedes its artifacts; restart safety — the normative core — precedes the round it governs; the behavioral contracts (prefix, anchors, approve, lifecycle) follow the round; completion and anti-blocking discipline follow the contracts; the prompt contract and the stop procedure close the operational part; the consolidated traps close the document.

Named components:

- The restart-safety protocol — the resumption rules of R4.1..R4.6 (invariants R15.2, R15.3).
- The approve invariant — `approve present ⇔ no unresolved blocking problems`, both directions (R8.1, R8.2; invariant R15.1).
- The registry contract — location, format, states, sections, single writer, arbitration role (R3.1..R3.3).
- The three-part stop — abort sessions, remove the supervisor scheduler, message the finished watchers (R13.1; invariant R15.4).
- The watcher-prompt template — `references/watcher-prompt.md`, the current authoritative prompt text with its mandatory elements (R12.1, R12.2).

## Configuration

- `supervisor-tick-interval`: duration; `1h`; fixed; the cadence of the supervisor scheduler — each tick runs the gate listing and the registry comparison.
- `watcher-tick-interval`: duration; `15m`; fixed; the cadence of each watcher's own scheduler — each fire runs one round.
- `watcher-slot-limit`: integer; `4`; fixed; the maximum number of concurrently running watchers; MRs beyond the limit wait in pending-launch.
- `watcher-subagent-type`: string; `assistant_high`; fixed; the subagent type every watcher is launched as.
- `registry-path`: string; `~/tmp/mr-watch/registry.md`; fixed; the location of the registry file.
- `watcher-worktree-pattern`: string; `~/wt/<repo>/mr-<iid>`; fixed; the worktree of a watcher, on branch `mr-<iid>` created from `origin/main`.
- `watcher-comment-prefix`: string; `[ai] `; fixed; the owner-prescribed value of `GITLAB_COMMENT_PREFIX` for this review context (environment or glab `tools/config.sh`, precedence per the glab skill); the authorship marker and own-thread filter of every watcher write and selection.

## Requirements

- R1. Relationship to the glab skill:
- R1.1. verification=manual; Build on glab, reference, never duplicate. The skill performs every GitLab mechanic through the `glab` skill — its rules and its gitlab-tools toolkit — and cites the concrete glab sections (comment prefix, anchors and batch posting, draft review, pagination, reading discussions, replies and resolve, the toolkit and timer/watcher recipe) instead of restating their text; on any conflict the glab skill owns the mechanics while this skill owns only the orchestration policy above them.
- R1.2. verification=manual; Prefix fixation. The review context runs with `watcher-comment-prefix` as the owner-prescribed value of `GITLAB_COMMENT_PREFIX` (environment or glab `tools/config.sh`, precedence per the glab skill): every body a watcher posts and every own-thread selection under this skill uses this prefix; the glab skill's built-in default stays in force for contexts without an owner prescription.
- R2. The supervisor:
- R2.1. verification=manual; Hourly gate listing. The supervisor holds a scheduler at `supervisor-tick-interval` whose gate command prints the fresh list of MRs awaiting the user's review in the project — `mr-list.sh --role reviewer --state opened --project <group/project>` (scope=all and pagination built into the tool); a gate exit `0` fires the tick, a nonzero gate skips the fire and retries on the next tick, and every fire compares the fresh listing against the registry before anything is launched.
- R2.2. verification=manual; New-MR intake. An MR found by the gate and absent from the registry gets a worktree per `watcher-worktree-pattern` (branch `mr-<iid>` from `origin/main`), a registry entry in state pending-launch, and a watcher launch as soon as a slot is free.
- R2.3. verification=manual; Slot limit and queue. At most `watcher-slot-limit` watchers run concurrently; MRs beyond the limit stay in pending-launch and are launched as slots free on later ticks.
- R2.4. verification=manual; One watcher per MR. Exactly one watcher of subagent type `watcher-subagent-type` is launched per watched MR, with the prompt built from the watcher-prompt template (R12.1) whose first line is `Worktree: <path>`.
- R2.5. verification=manual; Completion control. On a tick, a registry entry in state watching whose MR left the opened state is verified terminal (closed or merged) by an MR card check, its watcher is instructed to complete (R10.1), and the entry becomes done.
- R2.6. verification=manual; No direct MR writes. The supervisor never posts comments, replies, resolves threads, or changes approve on the watched MRs — all MR writes belong to watchers; the supervisor writes only the registry and the schedulers it owns.
- R2.7. verification=manual; Supervisor restart tolerance. Any supervisor instance reconstructs its duty from the registry alone — the registry, not session or task history, decides which MRs are watched and which watchers are due.
- R3. The registry:
- R3.1. verification=manual; Registry format. The registry lives at `registry-path`; its entry format is `- !<iid> - <state> (worktree <path>)`; its states are pending-launch, watching, stopped by user, and done; its sections are watching (pending-launch and watching entries), closed (done entries), and archived (records rotated out of closed as hygiene, changing nothing semantically).
- R3.2. verification=manual; Single writer. The registry is written by the supervisor alone; watchers read it for orientation and never write it.
- R3.3. verification=manual; Registry as arbiter. The registry is the single arbiter of watcher duty: duplicate watcher sessions on one MR are legal (a cancelled wave and a relaunched session may coexist), and the decision whether an MR needs a watcher is made from the registry state alone, never from task-list history.
- R4. Restart safety:
- R4.1. verification=manual; Resumption, not fresh start. A watcher always resumes and never starts from scratch: any launch — first, scheduled, or restarted — behaves as one more round, and a restart is indistinguishable from a regular round.
- R4.2. verification=manual; Mandatory first read. The first action of every watcher run is reading from GitLab all discussions of the MR with full pagination, selecting the own threads by `watcher-comment-prefix`, and rebuilding the open-issue list from them — before any other step of the round.
- R4.3. verification=manual; No re-posting, no duplication. Open own threads are never re-posted and never duplicated: a candidate finding is matched against the open own threads by file and topic, never by byte equality of the text.
- R4.4. verification=manual; Fixed-check before new findings. Each open own thread is checked against the current diff of the MR for being fixed before new findings are gathered.
- R4.5. verification=manual; GitLab as the source of truth. GitLab is the source of truth of the review context: the registry and local state markers are auxiliary, and their loss is recoverable by re-reading GitLab.
- R4.6. verification=manual; Session-change tolerance. A session change is not an obstacle: a fresh agent instance takes the MR from the registry and continues under the same rules.
- R5. The watcher round:
- R5.1. verification=manual; Watcher scheduler. The watcher keeps its own scheduler at `watcher-tick-interval` with the boolean has-updates gate of the glab skill's timer/watcher recipe (the marker file and the clone pinning belong to the watcher, the clone being its worktree); every fire runs exactly one round.
- R5.2. verification=manual; Round order. A round runs in this order: the resume read (R4.2..R4.4) → fresh MR state (the card; the true local diff from the merge base) → triage of open own threads (R9) → review of new commits since the previous round → publication of new findings (R6, R7) → approve update (R8) → the round summary.
- R6. Prefix and ownership:
- R6.1. verification=manual; Prefix on every body. Every body the watcher posts — findings, replies, confirmations, agreements, objections — starts with `watcher-comment-prefix`.
- R6.2. verification=manual; Mechanical own-thread selection. A discussion counts as an own thread exactly when its first non-system note starts with `watcher-comment-prefix`; the selection is mechanical, through the toolkit's own-thread filter.
- R6.3. verification=manual; Others' threads untouched. The watcher never answers, resolves, or otherwise modifies threads started by others, including bot threads; its write scope is its own threads, the approve state, and nothing else.
- R7. Anchors:
- R7.1. verification=manual; Validate before positioning. A line-anchored comment is posted only after its anchor passes client-side validation against the diff hunk ranges (the glab skill's anchor rules; the toolkit refuses outside-hunk anchors).
- R7.2. verification=manual; Unpositioned fallback. When an anchor cannot be validated, the comment is posted unpositioned with `<path>:<line>` written into the text; a blind positioned post is forbidden.
- R8. The approve invariant:
- R8.1. verification=manual; The invariant, both directions. The approve state of a watcher on an MR satisfies: approve present exactly when the watcher sees no unresolved blocking problems.
- R8.2. verification=manual; Approve and unapprove actions. When the watcher sees no unresolved blocking problems, it approves the MR; when a new blocking problem appears, it withdraws its approve; non-blocking remarks never cancel an approve.
- R8.3. verification=manual; Blocking classification is explicit. A blocking problem is one that must be fixed before merge, and every published finding states its blocking classification explicitly, keeping the invariant decidable from the published threads.
- R8.4. verification=manual; Local merge verdict over API status (trap, instance-dependent). A merge-conflict verdict is taken from the local merge simulation (merge-tree semantics, the toolkit's conflicts mode), not from the API merge status alone: `cannot_be_merged` may be stale, and the local check decides.
- R9. Own-thread lifecycle:
- R9.1. verification=manual; Fixed: confirm and resolve. A thread whose problem is fixed in the current diff is answered with a short confirmation referencing what fixed it, and only then resolved.
- R9.2. verification=manual; Justified: agree or contest. An author's justification in an own thread is verified in the code: when correct, the watcher posts agreement citing the verified facts as `<path>:<line>` references and resolves the thread; when wrong, it posts an objection with the contradicting facts and leaves the thread open.
- R9.3. verification=manual; Resolve discipline. A thread is resolved only after the watcher's verdict for it is posted inside the thread, one thread per resolve call, never as a batch.
- R10. Completion:
- R10.1. verification=manual; Watcher completion. When the MR is closed or merged, the watcher removes its own scheduler, settles the approve state (withdrawing the approve on an MR closed with unresolved blocking problems; a merged MR keeps its recorded state), and returns a final summary of the whole review.
- R10.2. verification=manual; Supervisor done marking. The supervisor marks the registry entry of a completed watcher done and moves it to the closed section.
- R11. Anti-blocking discipline:
- R11.1. verification=manual; Publish immediately, follow up later. The watcher publishes its validated findings immediately and never waits for its subagents indefinitely; findings arriving from subagents are published later as a separate follow-up batch.
- R11.2. verification=manual; Result per completed step. The watcher returns a result after each completed step of a round and never parks in a waiting state; a round ends with its summary.
- R11.3. verification=manual; Task and requirements only. The watcher prompt carries the task and the requirements only — no how-to recipes; the choice of methods stays with the watcher, with the glab skill as its mechanical reference.
- R12. The watcher prompt:
- R12.1. verification=manual; Mandatory elements. The watcher prompt is built from the template in `references/watcher-prompt.md` and always contains: the `Worktree: <path>` first line; a reference to the glab skill; the explicit prefix norm (`watcher-comment-prefix` on every posted body); the resume section (the R4 rules); and the hard constraints — no merging, closing, or renaming of the MR, no answering others' threads, no posting without anchor validation.
- R12.2. verification=manual; Template currency. The template in `references/watcher-prompt.md` is the current authoritative prompt text and is updated in the same change as any skill rule that affects it.
- R13. The stop:
- R13.1. verification=manual; Three-part stop. A complete stop of the service consists of three parts, all mandatory: aborting the running watcher sessions; removing the supervisor's own scheduler; and messaging the finished watchers to remove their schedulers and finish — aborting sessions does not remove schedulers created inside them, and omitting the third part leaves zombie rounds.
- R13.2. verification=manual; Registry marking after a stop. After a user stop, the supervisor marks the affected registry entries stopped by user.
- R14. Structure, accuracy, and style:
- R14.1. verification=manual; Canonical skeleton. SKILL.md follows the canonical skeleton of the Interface section: numbered sections in the canonical order, with an intro stating purpose, the two levels, the relation to the glab skill, the instance-observation caveat, and the placeholder notice.
- R14.2. verification=manual; Placeholders only. Identifiers in the skill documents are placeholders only — `<group/project>`, `<iid>`, `<repo>`, `<path>`, `<worktree-path>`; no real hosts, users, projects, or numeric MR ids appear.
- R14.3. verification=manual; Traps and instance-dependence. Observations resting on a specific instance are marked instance-dependent, and every trap is highlighted with its failure mode and the false conclusion it invites.
- R14.4. verification=manual; Frontmatter currency. The frontmatter carries `name` and `description` exactly as the canonical block of the Interface section; the `description` enumerates the trigger scope and ends with the boundary sentence.
- R15. Revision invariants:
- R15.1. verification=manual; The approve invariant (R8.1, R8.2) is inviolable: no revision may weaken, scope-limit, or drop either direction.
- R15.2. verification=manual; The no-duplication rule for open own threads (R4.3) is inviolable.
- R15.3. verification=manual; The mandatory first read of the full GitLab discussion state on every watcher run (R4.2) is inviolable.
- R15.4. verification=manual; The three-part stop (R13.1) is inviolable: no stop procedure may drop any of its parts.
- R15.5. verification=manual; The prefix rule (R1.2, R6.1) is inviolable while this skill governs the context: every posted body starts with `watcher-comment-prefix`; changing the prefix value is an owner decision recorded in Configuration, not a revision side effect.
- R15.6. verification=manual; Revision monotonicity: a revision may extend or refine existing rules but must not silently weaken or remove any rule present in the previous version.

## Examples

- E1. Relationship to the glab skill:
- E1.2. R1.2 subtree (observed pattern): the repository owner required `[ai] ` as the machine-comment marker on their MRs; the review context runs with `GITLAB_COMMENT_PREFIX='[ai] '` so the toolkit's write checks and own-thread filters all operate on `[ai] ` while contexts without an owner prescription keep the glab built-in default.
- E3. The registry:
- E3.3. R3.3 subtree (incident pattern): after a cancelled launch wave, two watcher sessions existed for one MR — the cancelled one and the relaunched one; the registry (one entry in state watching) correctly showed one watcher duty, and the two-session task history was irrelevant to the decision.
- E4. Restart safety:
- E4.3. R4.3 subtree (observed pattern): a round rephrased a previously posted finding about error handling in `<path>`; the resume read matched the candidate to the open thread on the same file and topic, and the rephrased text was not posted as a second thread.
- E8. The approve invariant:
- E8.4. R8.4 subtree (incident pattern, instance-dependent): the API reported `merge_status: cannot_be_merged` on an MR whose local merge simulation came out clean; the local check decided, and the conflict report was treated as stale.
- E13. The stop:
- E13.1. R13.1 subtree (incident pattern): after aborting watcher sessions, their schedulers kept firing rounds with no working session behind them; the complete stop — abort the sessions, remove the supervisor scheduler, message the finished watchers to remove theirs — cleared the service.

## Usage constraints

- The skill governs only continuous review with monitoring: a one-off review without monitoring belongs to the `glab` skill's reviewer workflows, and this skill must not be loaded for it.
- The service never merges, closes, or renames the MRs it reviews; merge decisions stay with the user.
- The registry and local markers hold no secrets and no review text; losing them is recoverable from GitLab (R4.5).
- Instance-dependent observations were made on the reference instance; re-check them on a new instance before relying on them.
- The slot limit is honored by the launching agent, not by the scheduler: exceeding `watcher-slot-limit` is a launch-discipline violation even if the runtime permits it.

## Error handling

- A divergence between SKILL.md, the watcher-prompt template, and this specification is either a spec gap (fix the spec) or a skill bug (fix the skill document); silent tolerance is forbidden.
- An unverifiable or instance-specific claim is removed or explicitly marked instance-dependent (R14.3); removal of content carrying an invariant is forbidden — re-verify instead (R15.6).
- Scheduler gate failures follow the glab timer/watcher discipline: a failed gate skips the fire without an alert and retries on the next tick; a delta is never lost to a skipped fire.
- A watcher that cannot complete a step returns with the failure stated in the round summary; the next round re-enters through the resume read (R4.1..R4.6), so a failed round never corrupts the review state.

## Dependencies

- The `glab` skill — the mechanical foundation: glab rules and the gitlab-tools toolkit (comment protocols, anchor validation, the draft review flow, the timer/watcher recipe); this skill references its sections and does not restate them (R1.1).
- The runtime's scheduler and task tooling — gate-command schedulers, subagent launches, session aborts; the three-part stop (R13.1) relies on their observed behavior, including schedulers surviving a session abort.
- A bash environment with glab, python3, and git; each watcher needs its worktree clone per `watcher-worktree-pattern` for diff and anchor work.

## Used by

None.
