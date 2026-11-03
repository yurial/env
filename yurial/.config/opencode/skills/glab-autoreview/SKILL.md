---
name: glab-autoreview
description: "Use when the user asks for continuous automated review of GitLab merge requests where the user is the reviewer: a standing hourly supervisor on the main agent (gate command mr-list.sh --role reviewer --state opened --project <group/project>, registry comparison in ~/tmp/mr-watch/registry.md, watcher launches under a slot limit with a pending-launch queue, completion control for closed/merged MRs), one watcher subagent (assistant_high) per MR with its own 15-minute scheduler and dedicated worktree (~/wt/<repo>/mr-<iid>, branch mr-<iid> from origin/main, passed as the first Worktree: line), restart-safe review rounds (every run resumes by reading all MR discussions from GitLab with pagination; open own threads are never re-posted or duplicated — matching is by file and topic), line-anchored comments only after anchor validation against diff hunks with the unpositioned <path>:<line> fallback, the approve invariant (approve present iff no unresolved blocking problems; unapprove when new blockers appear; non-blocking remarks never cancel an approve), own-thread lifecycle (confirm and resolve fixed threads, agree and resolve justified author replies verified in code, contest wrong replies with facts, never touch others' threads including bots), watcher completion on closed/merged MRs (scheduler removed, approve settled, final summary), anti-blocking discipline (publish validated findings immediately, publish subagent findings as a follow-up, return a result after each completed step), the three-part stop (abort sessions, remove the supervisor scheduler, tell watchers to remove theirs), and traps: stale merge_status vs the local merge-tree check, legal duplicate watcher sessions arbitrated by the registry, project-path 404 resolved via search?scope=projects, glab api exiting 0 on HTTP errors. Builds on the glab skill (gitlab-tools, comment protocols, scope=all, draft review flow) for all underlying mechanics. Use ONLY for continuous GitLab MR review with monitoring, not for one-off reviews without monitoring, other GitLab work, or other forges."
---

# glab-autoreview: continuous automated MR review — supervisor, watchers, restart safety

This skill turns the user's reviewer duty on a GitLab project into a standing
automated review service. It has two levels: a supervisor on the main agent —
an hourly scheduler that discovers MRs awaiting the user's review, keeps the
registry, and launches one watcher per MR — and per-MR watcher subagents, each
running its own short-interval scheduler and owning the review of exactly one
MR: comments, replies, thread resolution, and the approve state. The user stays
the reviewer of record; the watchers are their standing review agents.

Everything mechanical — glab calls, the gitlab-tools toolkit, comment
protocols, anchor validation, the draft review flow, pagination, HTTP-error
discipline — belongs to the glab skill; this document only adds the
orchestration, continuity, and safety policy on top and cites the concrete
glab sections instead of restating them. Observations marked
instance-dependent were made live on a self-managed reference instance (the
one configured as `GITLAB_HOST` in glab `tools/config.sh`) and are not
guaranteed on other instances. Every identifier in examples is a placeholder:
`<group/project>`, `<iid>`, `<repo>`, `<path>`, `<worktree-path>`.

## 1. Relationship to the glab skill

- The skill builds on glab, it does not replace it. Before working under this
  skill, load the glab skill: the watcher's every GitLab operation goes
  through its rules and its toolkit.
- Reference, never duplicate: this document cites glab sections (§9 comments,
  §10 anchors and batch posting, §11 draft review, §13 pagination, §17
  reading discussions, §19 replies and resolve, §22 toolkit and the
  timer/watcher recipe). On any conflict glab owns the mechanics; this skill
  owns only the orchestration policy above them.
- Comment identity: comments are posted through the glab skill's comment
  rules and its toolkit (§9, §22); the same convention doubles as the
  authorship marker by which the toolkit's own-thread filter (`--ai-only`)
  recognizes the watcher's threads — the foundation the resume protocol
  (section 4) rests on. The prefix value and its configuration belong to
  the glab skill alone; this skill fixes none.

## 2. Architecture: supervisor and per-MR watchers

Supervisor (the main agent):

- Holds an hourly scheduler. Its gate command prints the fresh list of MRs
  awaiting the user's review in the project:
  `mr-list.sh --role reviewer --state opened --project <group/project>`
  (scope=all and pagination are built into the tool — glab §5, §22). Gate
  exit `0` → the fire happens; a nonzero gate skips the fire and retries on
  the next tick (the timer/watcher discipline of glab §22 — an API failure
  never loses the delta).
- On every fire, compare the fresh list against the registry (section 3):
  - An MR absent from the registry: prepare the watcher worktree
    `~/wt/<repo>/mr-<iid>` (branch `mr-<iid>` from `origin/main`), add a
    registry entry in state `pending-launch`, and launch the watcher as soon
    as a slot is free.
  - A registry entry in state `watching` whose MR is no longer opened:
    confirm the terminal state (closed or merged) with an MR card check
    (`mr-card.sh`), instruct its watcher to complete (section 10), mark the
    entry `done`.
- Slot limit: at most four watchers run concurrently (`watcher-slot-limit`,
  the delegation limit of the runtime); the rest wait in `pending-launch` and
  are launched as slots free on later fires.
- The supervisor writes only the registry and its own schedulers. It never
  posts comments, replies, resolves threads, or touches approve on the MRs —
  all MR writes belong to watchers.
- Restart tolerance: any supervisor instance reconstructs its duty from the
  registry alone (section 3).

Watcher (exactly one per watched MR):

- Subagent type `assistant_high`, launched with the prompt built from the
  template in `references/watcher-prompt.md` (section 12); the first line of
  the prompt is `Worktree: <path>` — the delegation contract of the runtime.
- Keeps its own 15-minute scheduler: the timer/watcher recipe of glab §22
  with `mr-has-updates.sh <group/project> <iid> --state <marker>` as the gate
  (`--no-ci` when CI events do not matter); the marker file and the
  `GITLAB_REPO` clone pinning belong to the watcher, the clone being its
  worktree.
- Every fire runs exactly one round (section 5). Rounds are restart-safe
  (section 4): an interrupted or relaunched watcher loses nothing.

## 3. The registry

- Location: `~/tmp/mr-watch/registry.md`.
- Entry format: `- !<iid> - <state> (worktree <path>)`.
- States: `pending-launch` / `watching` / `stopped by user` /
  `done (closed/merged)`.
- Sections: `watching` (entries in `pending-launch` and `watching`),
  `closed` (entries `done`), `archived` (old records rotated out of `closed`
  as hygiene — the move changes nothing semantically).
- The main agent is the only writer; watchers read the registry for
  orientation and never write it.
- The registry — never the task list — is the arbiter of watcher duty.
  Duplicate sessions on one MR are legal (a cancelled launch wave and the
  relaunched session may coexist in the task history): whether an MR needs a
  watcher is decided from the registry state alone, not from the history of
  sessions (trap, observed).

## 4. Restart safety: every run resumes (critical)

This section is the normative core of the skill. A watcher always resumes; it
never starts from scratch, and a restart is indistinguishable from a regular
round.

- The first action of every run — first launch, scheduled fire, or restart,
  no exceptions — is to read from GitLab all discussions of the MR, with full
  pagination (glab §13, §17; mechanically `mr-threads.sh --ai-only`), select
  the own threads (section 6), and rebuild the list of open review issues
  from them.
- Open own threads are never re-posted and never duplicated. Before
  posting a finding, match it against the open threads by file and topic —
  wording changes between rounds are expected; byte equality of the text is
  not the criterion (trap: a rephrased finding posted as a new thread is a
  duplicate).
- For each open thread, check the current diff: if the problem is already
  fixed, handle it per the lifecycle (section 9) — confirmation plus resolve.
- Only after this resume read does the regular cycle (section 5) run.
- GitLab is the source of truth of the review context. The registry and local
  state markers are auxiliary bookkeeping: losing them loses nothing that a
  re-read of GitLab cannot restore.
- A session change is not an obstacle: a fresh agent instance takes the MR
  from the registry and continues under the same rules.

## 5. The watcher round

One fire of the watcher scheduler is one round, in this order (each step is
self-contained; return after completed steps — section 11):

1. Resume read (section 4): discussions, own threads, open issues.
2. Fresh MR state: the card (`mr-card.sh`), the true local diff from the
   merge base (`mr-diff.sh` — never `diff_refs.start_sha`, glab §22),
   mergeability (section 8).
3. Triage open own threads (section 9): fixed → confirm and resolve; the
   author replied → verify the justification → agree and resolve, or contest.
4. Review new commits since the previous round for new findings.
5. Publish new findings: anchors validated (section 7), a batch via the
   draft review flow (`mr-draft-review.sh`, publish, then
   `mr-verify-posted.sh` — glab §11, §22).
6. Update the approve state per the invariant (section 8).
7. Return the round summary: findings posted, threads opened/closed/resolved,
   approve action taken, open blockers remaining.

The step → tool map of the round's mechanical operations is the
watcher-round recipe of glab §22; this section fixes the round order and
policy, and the map in that section assigns a tool to every step.

## 6. Thread ownership

- Every body the watcher posts — findings, replies, confirmations,
  agreements, objections — is published through the glab skill's comment
  rules and its toolkit; the toolkit enforces glab's comment conventions on
  every write (glab §9, §22). This skill keeps no comment convention of its
  own.
- An own thread is a discussion whose first non-system note the toolkit's
  own-thread filter recognizes as a watcher comment under the glab skill's
  comment rule. The selection is mechanical: `mr-threads.sh --ai-only` (and
  `mr-verify-posted.sh --ai-only` after publishing).
- Others' threads — human or bot — are never answered, resolved, or modified
  by the watcher. The watcher's write scope is its own threads, the approve
  state, and nothing else. A user request to answer someone else's thread is
  outside the standing loop and goes through the glab skill directly.

## 7. Anchors: validate before posting

- A line-anchored comment is posted only after its anchor passes client-side
  validation against the diff hunk ranges (glab §10; `mr-comment.sh` and
  `mr-draft-review.sh` enforce it and refuse outside-hunk anchors with the
  valid ranges).
- When an anchor cannot be validated, post unpositioned with `<path>:<line>`
  written into the text — never a blind positioned POST.
- Notes going outdated on diff rotation is expected, not an error (glab
  §10/§11) — the resume read (section 4) re-anchors the discussion topic, not
  the byte text.

## 8. The approve invariant

The invariant, both directions:

```
approve present  ⇔  no unresolved blocking problems
```

- No unresolved blocking problems → `glab mr approve <iid>`.
- A new blocking problem appears → `glab mr unapprove <iid>`.
- Non-blocking remarks never cancel an approve.
- Both commands verified live on the reference instance.
- A blocking problem is one that must be fixed before merge; every published
  finding states its blocking classification explicitly, so the invariant is
  decidable from the published threads.
- Trap (instance-dependent, observed): `merge_status: cannot_be_merged` can
  be stale. The local merge simulation decides — `mr-diff.sh --conflicts`
  (`git merge-tree` semantics, glab §22) — not the API field alone.

## 9. Own-thread lifecycle: fixed, justified, contested

For every open own thread, exactly one of three outcomes per round:

- Fixed in the current diff → post a short confirmation naming what fixed it
  (`<path>:<line>`), then resolve the thread.
- The author replied with a justification → verify it in the code. Correct →
  post agreement citing the verified facts (`<path>:<line>`), then resolve
  the thread. Wrong → post an objection with the contradicting facts
  (`<path>:<line>`), keep the thread open.
- Not yet addressed → the thread stays open; re-check on the next round.

Push gate for the fixed outcome: the confirmation and the resolve happen
only after the author has pushed the fix into the MR branch — a new
commit/head sha has appeared since the thread was opened (the round's MR
card names the head). An author's "fixed" claim without the push does not
verify: keep the thread open, at most marking it with a short "waiting
for the push" reply, and re-check on the next round (the same gate is
stated with the watcher-round recipe in glab §22).

Resolve only after the verdict is posted inside the thread, one thread per
resolve call (`mr-resolve.sh`; no batch resolve — glab §22). Never discuss
code you have not read at the referenced lines (glab §10).

## 10. Completion: closed or merged

When the MR turns out closed or merged — noticed by the watcher on a round or
instructed by the supervisor:

- The watcher removes its own scheduler.
- It settles the approve state: withdraw the approve on an MR closed with
  unresolved blocking findings; a merged MR keeps its recorded state.
- It returns the final summary of the whole review to the supervisor:
  findings total, resolved versus still open, the final verdict.
- The supervisor marks the registry entry `done (closed/merged)` and moves it
  to the `closed` section.

## 11. Anti-blocking: publish early, return per step

- Never wait for subagents indefinitely. Validated own findings are published
  immediately; findings arriving from subagents are published later as a
  separate follow-up batch.
- Return a result after each completed step of a round, never park in a
  waiting state — a round ends with its summary, not with a hang.
- Interruption is cheap: the resume protocol (section 4) makes every round
  idempotent, so an aborted round loses nothing but time.

## 12. The watcher prompt

- The current authoritative template lives in
  `references/watcher-prompt.md`; the supervisor copies it, fills the
  placeholders (`<group/project>`, `<iid>`, `<worktree-path>`,
  `<registry-path>`), and sends it as the launch prompt. Any rule change that
  affects the prompt updates the template in the same change.
- The prompt states the task and the requirements only — never a recipe for
  how to perform them; the watcher chooses its methods, with the glab skill
  as the mechanical reference.
- Mandatory elements, checked before every launch:
  1. the first line `Worktree: <worktree-path>`;
  2. a reference to the glab skill;
  3. the resume section (the section 4 rules);
  4. the hard constraints: no merging, closing, or renaming of the MR; no
     answering others' threads; no posting without anchor validation.

## 13. Stopping the system: the three-part stop

A user «stop» is three parts; omitting any leaves live artifacts (observed):

1. `task_abort` the running watcher sessions.
2. Remove the supervisor's own hourly scheduler.
3. Message the finished watchers — sessions that already returned their
   result — to remove their schedulers and finish: `task_abort` does NOT
   kill schedulers created inside those sessions, and skipping this part
   leaves zombie rounds — fires that wake nobody useful (trap, observed).

Then the supervisor marks the affected registry entries `stopped by user`.

## 14. Traps (consolidated)

Each trap below is stated in its subject section; collected here with the
false conclusion it invites:

- Stale `merge_status: cannot_be_merged` (section 8, instance-dependent) —
  the local merge-tree check decides; the false conclusion is «the MR is
  conflicted».
- Zombie watcher schedulers (section 13) — aborting sessions does not remove
  their schedulers; the false conclusion is «abort = stop».
- Legal duplicate sessions on one MR (section 3) — a cancelled wave plus the
  relaunched session coexist; arbitrate by the registry, never by task-list
  history; the false conclusion is «two sessions = two watchers needed».
- The full project path may differ from the expected one — on a `404` for a
  project that should exist, find it via `search?scope=projects` before
  concluding it does not exist.
- `glab api` exits `0` on HTTP errors — read the body and the stderr line,
  never the exit code (inherited from glab §3/§14; the toolkit neutralizes
  it centrally).
- Approve mechanics: `glab mr approve <iid>` / `glab mr unapprove <iid>` —
  both verified live on the reference instance.
