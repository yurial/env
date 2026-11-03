# gitlab-tools

Small bash+python3 toolkit for reviewing GitLab merge requests through
`glab api`. Built and smoke-tested against the self-managed instance
`gitlab.corp.mail.ru` (GitLab 18.x-ee) and MR
`ai/streamflow/flowruntime!1887`.

Location-independent: the scripts resolve `lib.sh`, `config.sh`, and the
default state directory relative to their own location, so the toolkit
works from any checkout/deployment path.

Requirements: `glab` (authenticated for the host), `python3`, `git`.
No `jq` dependency.

## Configuration

Optional `config.sh` next to `lib.sh` is sourced by `lib.sh` when present.
Every assignment only fills an unset/empty variable, so the precedence is:

    environment > config.sh > built-in defaults

| variable                 | default                   | meaning                                            |
|--------------------------|---------------------------|----------------------------------------------------|
| `GITLAB_HOST`            | `gitlab.corp.mail.ru`     | instance host for every API call                   |
| `GITLAB_DEFAULT_PROJECT` | (empty)                   | `<project>` positional may be omitted when set; the remaining positionals shift left (mr-card/mr-diff/mr-updates/mr-threads/mr-verify-posted: 1 arg, mr-draft-review/mr-resolve/mr-verify-report: 2 args, mr-reply: 3 args, mr-comment: 4 args) |
| `GITLAB_REPO`            | (cwd)                     | git clone used for sha recovery / hunks / diffstat / the local MR diff |
| `GITLAB_COMMENT_PREFIX`  | `[ai] `                   | prefix every machine-generated comment must start with: write scripts refuse bodies without it, `--no-prefix` is the only opt-out, and the `--ai-only` filters select by it; prescribed per host/repository by its owner |
| `GITLAB_TOOLS_STATE_DIR` | `<tools>/.state` (next to `lib.sh`) | directory for `--state` marker files given as a bare filename (mr-updates.sh; mr-has-updates.sh resolves bare names under its `has-updates/` subdir) |
| `GITLAB_TOKEN`           | glab config               | auth token, honored by glab itself                 |

Every script also accepts the optional `--repo <dir>` flag with identical
semantics: it overrides `GITLAB_REPO` for the invocation (precedence flag >
environment > `config.sh` > built-in default), a nonexistent directory is a
usage error (exit 2), and scripts that make no clone use of the value
accept it for interface uniformity (validated the same way). The usage text
printed on a usage error by every script accepting `--repo` carries the
hint `clone is configured via GITLAB_REPO env or config.sh`.

All output is plain text, no ANSI colors (`NO_COLOR` needs no handling).
Exit codes: 0 success, 1 failure, 2 usage error — except `mr-has-updates.sh`,
whose boolean contract redefines the pair: 0 updates present, 1 no updates
(and the baseline first run), plus 3 for an API/network failure; and except
the `--conflicts` mode of `mr-diff.sh`, which owns its 0/1 pair as the
verdict (0 clean, 1 conflicts) and exits 3 when the check could not be
performed at all.

## Instance traps these scripts encode

1. **`glab api` exits 0 even on HTTP errors.** Failure is detected from the
   stderr line `glab: ... (HTTP <code>)` and/or from a response body whose
   only keys are `message`/`error` (see `gt_api`/`gt_get` in `lib.sh`).
2. **40-hex shas are masked** in API responses (REST *and* GraphQL) as
   `__SECRET_N__` placeholders - and the masking is flaky, it comes and goes
   between identical requests. Two things always survive: the commit
   `short_id` (8 hex chars, the masker only rewrites 40-hex strings) and the
   plain git protocol. Real shas are therefore recovered through a ladder
   (`gt_resolve_shas`):
   commits-endpoint `id` when unmasked -> `short_id` resolved locally with
   `git rev-parse` -> `git ls-remote origin <source_branch>` (fresh, never
   masked, writes nothing to the clone) -> local `origin/<branch>` /
   `<branch>` refs. The merge-base comes from
   `git merge-base origin/<target> <head>` (fallback `origin/main`,
   `origin/master`); `start_sha` is sent equal to the merge-base. Overrides:
   `GT_BASE_SHA` / `GT_START_SHA` / `GT_HEAD_SHA`, `GT_LSREMOTE=0` disables
   the network step. Without a clone the scripts fail with a clear message.
3. **The `/diffs` endpoint returns most files with `collapsed: true` and an
   empty diff** (449 of 571 files on !1887). Hunk ranges are therefore built
   locally with `git diff --unified=0 <merge-base>..<head> -- <path>`.
   Note: the true MR diff runs from the **merge-base**, not from
   `diff_refs.start_sha` - on this instance `start_sha` is the target-branch
   tip, and diffing from it drags in ~600 unrelated target-side changes.
   If the clone lacks the true MR head (stale fetch), hunk validation falls
   back to the local source-branch tip and says so loudly; refresh the clone
   (`git fetch origin main <branch>`) for exact validation.
4. **Anchors are accepted only on lines inside diff hunks** (HTTP 400 on a
   bad `line_code`). Anchors are validated locally first; invalid ones are
   refused with the list of valid ranges unless `--force` is given.
5. **The REST reply route is unreliable**: `POST .../discussions/<id>/notes`
   may 404, and `POST .../notes?in_reply_to_discussion_id=...` is silently
   ignored (orphan note outside the discussion). The working fallback is
   GraphQL `createNote` with `gid://gitlab/Discussion/<discussion_id>`
   (noteable id via `project(fullPath).mergeRequest(iid).id`).
6. **`glab api --paginate` concatenates JSON arrays** on stdout. Everything
   paginated is parsed by repeated `json.JSONDecoder().raw_decode`
   (`gt_json_items`). Pagination itself always runs with `per_page=100` in
   the URL (list endpoints default to 20/30 records; glab 1.36 has no
   `--per-page` flag). Writers of pipelines that may be cut short by an
   early-exiting filter swallow `BrokenPipeError` so `set -o pipefail`
   survives a deliberate cutoff.
7. **A raw-body POST may return rc=0 with
   `{"message":"500 Internal Server Error"}` while the object WAS created.**
   Write scripts never trust the POST/PUT response: they verify by follow-up
   GET (`mr-comment.sh`, `mr-draft-review.sh`, `mr-resolve.sh`, and
   `mr-reply.sh`), and GraphQL results are re-verified through REST as well.
   The read-only after-the-fact re-check of what actually landed is
   `mr-verify-posted.sh`.
8. **Every posted comment must start with the configured prefix**
   (`GITLAB_COMMENT_PREFIX`, default `[ai] `; environment >
   `config.sh` > built-in default). All write scripts refuse to post
   otherwise, unless `--no-prefix` is passed; the `--ai-only` filters of
   `mr-verify-posted.sh` and `mr-threads.sh` select notes by the same
   configured text.

## lib.sh

Shared helpers sourced by every script (the single shared library file):
config loading (including `GITLAB_COMMENT_PREFIX` and the `--repo`
validation/resolution helpers `gt_repo_arg_ok`/`gt_repo_pick`), API wrapper
+ error detection, concatenated-JSON parsing, pagination, sha recovery,
hunk range building/summarization (the single hunk construction shared by
the anchor validators and `mr-diff.sh --hunks`), GraphQL call helper,
prefix check (against the configured prefix), `@file` body loading.

## mr-auth-probe.sh

```
mr-auth-probe.sh [host]
```

Live token-health probe — the mechanical form of the live-probe rule
(`glab auth status` output is a hint, never a verdict; only a live call
decides). Performs exactly ONE API call — GET `user` — through the gt_api
machinery of lib.sh, so the `glab api` rc=0-on-HTTP-error trap is
neutralized centrally.

- the optional `[host]` positional selects the target host for this
  invocation; when omitted, the host resolves per the shared runtime
  contract (environment > `config.sh` > built-in default);
- exit `0` — the call answered 200 and stdout carries exactly
  `ok <username>`;
- exit `1` — the probe failed (an HTTP error, 401 first of all, or a
  network failure); a stderr diagnostic line names the host and the HTTP
  code (or the network error);
- exit `2` — usage error.

GET-only: no writes, no clone, no state files; token values are never
read, echoed, or stored.

## mr-list.sh

```
mr-list.sh [--role reviewer|author|assignee] [--state opened|closed|merged|all]
           [--draft|--no-draft] [--json] [--project <group/proj>] [--max N]
           [--repo <dir>]
```

Global MR listing by role — the "which MRs await my review" scenario (the
default `--role reviewer --state opened`). Queries the global
`merge_requests` endpoint for the CURRENT user (the username comes from a
live `glab api user` call) with the mandatory `scope=all`: without it the
endpoint silently defaults to `created_by_me` and returns only the caller's
own MRs (SKILL.md section 5) — the tool encapsulates that trap.
Pagination: `per_page=100` + `--paginate` via `lib.sh`.

- text output: one block per MR — `references.full` and a `[DRAFT]` mark,
  `updated_at` date, `author.username` on the header line, then `title`,
  `web_url`, and the branch line `source_branch -> target_branch`; sorted
  by `updated_at` descending; a trailing count line
  summarizes the query;
- `--draft` / `--no-draft` filter drafts (`work_in_progress` or a
  `Draft:`/`WIP:` title prefix);
- `--project <group/proj>` narrows to one project (exact match on the
  project path of `references.full` — the global endpoint returns no
  `project` object; default: all accessible projects);
- `--max N` caps the list after sorting (newest updates first);
- `--json` prints the same normalized set as a JSON array of the
  endpoint's MR objects — `source_branch` and `target_branch` included —
  sorted identically, deduplicated by MR id (the count line goes to
  stderr).

GET-only: no writes, no clone needed. Exit codes: 0 success (an empty
result is a success printed as an informational line), 1 failure (API
error, unparsable response), 2 usage error (bad `--role`/`--state`/`--max`
value, unknown option).

Example:

```
mr-list.sh                            # open MRs awaiting my review, all projects
mr-list.sh --role author --json       # my own MRs as a JSON array
mr-list.sh --state all --project ai/streamflow/flowruntime --max 20
```

## mr-card.sh

```
mr-card.sh <project> <mr_iid> [--json] [--full] [--repo <dir>]
```

The MR card — the mechanical "view one MR" step of the watcher loop (raw
`glab mr view` remains the interactive project-scoped path). Fields, from
the single-MR endpoint plus the approvals endpoint: title with a `[DRAFT]`
mark, state, `work_in_progress`, author, reviewers, `approved_by`
(usernames, the approvals endpoint), `approved` (boolean) and
`approvals_required` (number or null; `?` in the text card when absent) —
both from the approvals endpoint too — `blocking_discussions_resolved`,
`detailed_merge_status` and the legacy `merge_status`, source and target
branches, the recovered head sha with its provenance (the masked-sha
ladder: commits-endpoint id -> `short_id` resolved locally -> git
ls-remote -> local refs), `changes_count`, and the description truncated to
400 chars (`--full` prints it whole, the truncation convention of
`mr-threads.sh`). Plus the local diffstat of `<merge-base>..<head>`.

- text output: one labeled block modeled on the mr-list.sh block style;
- `--json`: one normalized JSON object with the same fields — `diffstat` as
  an object of `files`/`insertions`/`deletions`, the description under the
  same truncation flags; the no-clone NOTE goes to stderr so stdout stays
  parseable;
- without a clone the card is still printed, without the diffstat, with an
  explicit NOTE saying so (the degrade-and-say-so pattern); a stale clone
  (no MR head) degrades the diffstat to the local source-branch tip with a
  loud warning.

GET-only plus read-only clone use — nothing is fetched or written. Exit
codes per the shared contract; a missing project/MR exits 1 with the HTTP
diagnostics on stderr.

Example:

```
mr-card.sh ai/streamflow/flowruntime 2108 --repo ~/streamflow/flowruntime
```

## mr-updates.sh

```
mr-updates.sh <project> <mr_iid> [--since <iso8601|sha>] [--state <file>] [--fetch]
              [--repo <dir>]
```

Prints MR state (head sha, updated_at, draft, state), new commits, all notes
newer than the marker, thread status changes, and — only when the delta
changes them — a `== merge status ==` section. `--since` accepts an
ISO8601 timestamp or a commit sha (walk stops right before it). With
`--state <file>` the head sha (+ its short_id), the max note id/created_at,
plus the merge-status snapshot (merge_status, detailed_merge_status,
blocking_discussions_resolved) and the approvals set (usernames only, no
secrets) are stored after printing; the next run reports only the delta (no
marker file = full dump). The marker schema is additive (`"schema": 3`):
older markers (schema 2) load unchanged, a field absent from an older
marker counts as "not changed" — the merge-status category never reports a
false change merely because an old marker lacks the field — and a masked
sha (`__SECRET_N__`) in a marker is ignored for the cutoff (the timestamp
cutoff takes over). A bare `--state` filename resolves under
`GITLAB_TOOLS_STATE_DIR`. Commits come from
`git log origin/<source_branch> --not origin/<target>` when run inside
a clone (branch must exist locally; `--fetch` refreshes it), otherwise from
the API commits endpoint; inside a clone every new commit line carries a
diffstat suffix `(<n> files, +a/-b)` (merge/root commits without numstat get
none). Notes always come from the API (GET-only).

When the delta contains resolution events, a `== thread status changes ==`
section is printed (nothing when there are none). It lists system notes
`[resolved]` / `[unresolved]` and `resolved all threads` with the discussion
id (mapped by note id via a lazy discussions GET), the anchor path of the
thread, who flipped the state, and the first line of our original prefixed
note (or the thread's first note) for context. An
MR-timeline `resolved all threads` note that is not attached to any
discussion is reported as `(all threads; MR timeline note)`.

When the delta changes the merge-status aspects, a `== merge status ==`
section is printed — one line per changed aspect:

- `merge_status: <old> -> <new>` and
  `detailed_merge_status: <old> -> <new>` transitions;
- `blocking_discussions_resolved: <old> -> <new>` flips;
- `approvals: +<username>, -<username>` diffs (the approvals endpoint,
  usernames only).

Example:

```
mr-updates.sh ai/streamflow/flowruntime 1887 --state mr1887.json
```

## mr-has-updates.sh

```
mr-has-updates.sh <project> <mr_iid> [--state <file>] [--no-ci] [--repo <dir>]
```

Fast boolean "does this MR have any updates?" check — the tool for timers
(wake the agent only when something changed; see the timer/watcher recipe
in SKILL.md section 22). Read-only: GET-only, nothing is posted, no git
clone needed. Compares the current MR snapshot against the has-updates
marker and reports the categories that moved, one line per category:

- `commits` — a new head (the commit walk stops at the marker head; only
  short ids are ever stored — masked 40-hex shas never enter the marker);
- `notes` — any note with a higher id, system notes included (the notes
  listing is walked with full pagination — the max note id must be exact);
- `threads` — resolve/unresolve flips (system notes plus the unresolved-id
  set diff) and new discussions;
- `mr state` — state (opened/locked/merged/closed) and draft/WIP;
- `title/description` — hashes only (length + sha256 prefix; no text is
  stored);
- `reviewers/approvals` — username set diffs (`approved_by` via the
  approvals endpoint, usernames only);
- `merge status` — `merge_status` / `detailed_merge_status` and
  `blocking_discussions_resolved` flips;
- `CI` — the newest pipeline for the current head sha
  (`pipelines?sha=<head>`; the sha filter needs the FULL 40-hex id — a
  short id returns an empty list on this instance — and when the commits
  endpoint masks the id the fallback is the newest pipeline of the
  `refs/merge-requests/<iid>/head` ref), its id/status change.

Exit codes (a boolean contract — note it redefines the toolkit's usual
0/1): **0** updates present (stdout carries the summary lines — attach
them to the timer wakeup); **1** no updates; **2** usage error; **3**
API/network failure (diagnostics on stderr; the marker is NOT rewritten,
so the delta is not lost).

State: `--state` is optional; the default is
`<tools>/.state/has-updates/<project without slashes>__<iid>.json` (a bare
filename resolves under `GITLAB_TOOLS_STATE_DIR/has-updates/`; the
directory is created on demand). The first run writes a baseline, prints
`baseline recorded (...)`, and exits 1; a rerun with no changes exits 1
with empty stdout (a single quiet stderr line names the last-check time).
The marker schema is additive (`"schema": 4`; older schema-3 markers load
unchanged — a field absent from an older marker counts as "not changed"),
holds no secrets (no full shas, no MR text — short ids, length+hash pairs,
and usernames only), and is written atomically (tmp + rename); an unchanged
run never touches it. API budget: ~6 GETs (MR, commits, notes, discussions,
approvals, pipelines); only the notes listing is paginated through
(max-note-id exactness), the rest use `per_page=100` pages (discussions
newest-first — new-thread detection needs the fresh tail, resolve flips of
old threads come from system notes).

`--no-ci` excludes the CI category entirely: the CI pipeline for the
current head is not requested (the sha-filter pipelines GET and its
ref-pipeline fallback are both skipped; one GET saved from the ~six API
budget), is not compared against the marker, and no CI line appears in the
stdout summary. The marker structure does not change: the stored pipeline
fields are not refreshed and keep their last saved values (a first-run
baseline under `--no-ci` stores no pipeline fields). A CI change that
happened during a `--no-ci` window is therefore detected by the next run
without `--no-ci`, so the CI delta is not lost. Exit codes and the
first-run baseline semantics are unchanged.

Examples:

```
# timer: wake the agent only when something changed
mr-has-updates.sh ai/streamflow/flowruntime 2067 && <run the agent>

# default per-MR marker under <tools>/.state/has-updates/
mr-has-updates.sh ai/streamflow/flowruntime 2067

# a watcher that does not care about CI events
mr-has-updates.sh ai/streamflow/flowruntime 2067 --state watch.json --no-ci
```

## mr-diff.sh

```
mr-diff.sh <project> <mr_iid> [--files|--stat|--hunks|--conflicts] [--repo <dir>]
```

The true local MR diff as a first-class command — the collapsed `/diffs`
endpoint and the merge-base rule made operational. A usable clone is
required; without one the script exits 1 with a clear message. Shas are
recovered through the lib.sh ladder, and the diff always runs
`<merge-base>..<head>` with the merge-base from `git merge-base` against
the target branch (fallback `origin/main` / `origin/master`) — never from
`diff_refs.start_sha` (on this instance it is the target-branch tip) and
never as a two-dot `origin/<target>..<head>` (a target that moved ahead
unfolds other authors' commits).

Clone-freshness guard: when the clone lacks the true MR head, every mode
prints a loud warning naming the expected head and the fallback tip and
degrades to the local source-branch tip; a `--conflicts` verdict computed
from the fallback head is labeled as such.

Modes:

- default — the full unified diff `<merge-base>..<head>`;
- `--files` — one line per changed path with its status:
  `new <path>`, `deleted <path>`, `renamed <old> -> <new>`,
  `modified <path>`;
- `--stat` — the diffstat: `<files> files, +<insertions>/-<deletions>`;
- `--hunks` — the machine-readable new-side hunk ranges per changed file,
  one line per file, `<path>\t<start>-<end> <start>-<end> ...` (a path
  with no new side carries `-` in place of ranges) — the
  anchor-validation source of truth; the ranges come from the SAME shared
  construction (lib.sh `gt_hunks`) `mr-comment.sh` and
  `mr-draft-review.sh` validate anchors against;
- `--conflicts` — a write-free local merge simulation
  (`git merge-tree --write-tree`) between the target-branch tip and the MR
  head: exit `0` — the merge is clean, exit `1` — conflicts, with the
  list of conflicting paths on stdout; a check that could not be performed
  at all (no usable clone or head, a git failure) exits `3` with stderr
  diagnostics.

Exit codes: standard `0`/`1`/`2` for all modes except `--conflicts`, which
owns the `0`/`1` pair as its verdict and adds `3` for
could-not-be-performed; usage errors exit `2` in every mode. GET-only plus
read-only clone use; nothing is fetched or written.

Example:

```
mr-diff.sh ai/streamflow/flowruntime 2108 --hunks --repo ~/streamflow/flowruntime
```

## mr-threads.sh

```
mr-threads.sh <project> <mr_iid> [--open|--all] [--ai-only] [--no-system]
              [--max-chars N] [--full] [--repo <dir>]
```

Dumps discussions as readable text: discussion id, resolved state (resolved
iff every non-system note has `resolved:true`), anchor `path:line` (new
side; old side when there is no new line), authors, full note bodies
(truncated to 400 chars by default; `--max-chars N` / `--full`). `--open`
(default) keeps only unresolved threads; `--ai-only` keeps threads
containing a note that starts with the configured prefix
(`GITLAB_COMMENT_PREFIX`, default `[ai] `); `--no-system` drops
notes with `system: true` from the dump — CI-bot progress comments bury
the human review threads otherwise — and a thread consisting only of
system notes is not printed at all; the trailing count line keeps its
meaning (under `--no-system` the system-only threads drop out of the shown
count), and the resolved state of a printed thread is still computed over
its non-system notes. GET-only; no clone needed (`--repo` is accepted for
interface uniformity).

## mr-comment.sh

```
mr-comment.sh <project> <mr_iid> <path> <line> <body-or-@file>
              [--old-side] [--no-prefix] [--force] [--dry-run] [--repo <dir>]
```

Posts one line-anchored comment. Reads `diff_refs` from the single-MR
endpoint, recovers real shas locally (fails with a clear message if shas are
masked and no clone is available), validates `<line>` against locally built
hunk ranges for `<path>`, refuses with the list of valid ranges if the line
is outside a hunk (`--force` posts unpositioned with `path:line` prepended
to the body, keeping the configured comment prefix first), then POSTs via
the discussions API and verifies creation by GET. `--dry-run` prints the exact
payload (including `position`) without POSTing.

Example:

```
mr-comment.sh ai/streamflow/flowruntime 1887 \
  flow/runtime/ytflow/pipeline_follower.cpp 102 @note.txt --dry-run
```

## mr-draft-review.sh

```
mr-draft-review.sh <project> <mr_iid> <comments.json>
                   [--publish] [--dry-run] [--no-prefix] [--repo <dir>]
                   [--ignore-stray]
```

Batch flow. `comments.json` is an array of
`{"path":..., "line":N, "body":..., "old_side":optional}` draft items and/or
`{"reply_to_discussion_id":..., "body":...}` reply items.

Draft items: every anchor is validated locally, a table
(`ok` / `will-post-unpositioned`) is printed, and drafts are created on the
`draft_notes` endpoint (Content-Type: application/json, top-level `note` +
`position`), then verified via GET (a POST may answer rc=0 with a fake 500
error body while the draft was created).

Reply items: posted immediately through `mr-reply.sh` (REST with the
GraphQL `createNote` fallback) - they cannot wait in the draft box, so they
are real posts even without `--publish`; the script says so loudly and
`--dry-run` previews them.

Stray-draft guard: before creating anything the pending `draft_notes` of
your user are listed; if any already exist the run refuses (mixing runs
makes publish steps dangerous) unless `--ignore-stray` is passed. A dry run
only warns.

With `--publish` ONLY the drafts created by this run are published, one by
one, via `PUT .../draft_notes/<id>/publish`, each verified by GET (draft
gone from `draft_notes` + a thread with the same body found in
`discussions`); the PUT answer itself is never trusted. If the
single-publish route answers 404/400, the script prints an explicit warning
that `bulk_publish` publishes ALL pending drafts of the user and only then
falls back to it. Without `--publish` the draft ids are printed (each
deletable: `glab api --hostname "$GITLAB_HOST" -X DELETE .../draft_notes/<id>`).
`--dry-run` validates and prints payloads without any write.

## mr-reply.sh

```
mr-reply.sh <project> <mr_iid> <discussion_id> <body-or-@file> [--no-prefix] [--dry-run]
            [--repo <dir>]
```

Replies into an existing thread: tries REST
`discussions/<id>/notes` first, verifies the note landed **inside** the
discussion (GET; the body match ignores trailing newlines — GitLab
stores note bodies with them trimmed while `@file` bodies end with
one); on 404 or the silent-orphan result it falls back to
GraphQL `createNote` with `gid://gitlab/Discussion/<discussion_id>` and
verifies again. `--dry-run` prints both payloads.

## mr-resolve.sh

```
mr-resolve.sh <project> <mr_iid> <discussion_id> [--unresolve] [--dry-run] [--repo <dir>]
```

Resolves (or with `--unresolve` unresolves) ONE thread via
`PUT .../discussions/<discussion_id>?resolved=true|false`. Guards, all
decided by GET before any write: the discussion must exist; the thread must
contain resolvable notes; already being in the requested state is an
idempotent OK message with nothing sent. `--dry-run` prints the current
state (anchor, first note line, resolvable count) and the exact request.
After the PUT the new state is verified by GET (the fake 500-in-body trap
applies to PUT as well). No batch mode by design: one call resolves one
thread, so a mistake cannot scale.

## mr-verify-report.sh

```
mr-verify-report.sh <project> <mr_iid> <verdicts.json>
                    [--emit <out.json>] [--post] [--yes] [--repo <dir>]
```

Turns a reviewer verdict list into replies and drafts. `verdicts.json` is a
JSON array of:

- `{"action": "acknowledge"|"contest", "thread_hint": ..., "text": ...}` -
  the target thread is located by `thread_hint`, a substring of our original
  note text (notes start with the configured prefix,
  `GITLAB_COMMENT_PREFIX`); zero or several matching
  discussions is an error with the candidates listed - the plan is never
  built on a guess;
- `{"action": "new", "path": ..., "line": N, "old_side": optional,
  "text": ...}` - the anchor is validated like mr-comment.sh; out-of-diff /
  out-of-hunk items are refused with the valid ranges.

`text` is the body WITHOUT the comment prefix - the script adds the
configured one (`GITLAB_COMMENT_PREFIX`)
(a text already carrying it is not doubled). The full plan (target
discussion, matched note, final body per item) is always printed before any
write.

- `--emit <out.json>` writes a batch file for `mr-draft-review.sh` (replies
  encoded as `{"reply_to_discussion_id": ..., "body": ...}`); no MR writes.
- otherwise (or with `--post`) the verdicts are posted: replies via
  `mr-reply.sh`, `new` items via the `draft_notes` flow of
  `mr-draft-review.sh` (they stay private; this tool never publishes).
  Posting requires `--yes`; without it only the plan is printed.

Example:

```
mr-verify-report.sh ai/streamflow/flowruntime 1887 verdicts.json --emit batch.json
mr-draft-review.sh ai/streamflow/flowruntime 1887 batch.json
```

A sample verdict list is in `examples/verdicts.example.json`.

## mr-verify-posted.sh

```
mr-verify-posted.sh <project> <mr_iid> [--expect <expected.json>]
                     [--drafts] [--max-note-id] [--ai-only]
                     [--max-chars N] [--full] [--repo <dir>]
```

Read-only post-publish verifier: GET-only, no POST/PUT/DELETE is ever sent
(the write tools verify their own writes; this one re-checks afterwards,
e.g. after a `mr-draft-review.sh --publish` run plus raw timeline notes —
use it instead of ad-hoc inline verification scripts). Three checks:

- `--drafts` - the pending `draft_notes` of your user on the MR: count + ids
  (the pre-existing-draft check before a batch run).
- `--max-note-id` - the highest note id on the MR (marker/baseline for
  follow-up posts, same basis as the `mr-updates.sh --state` marker).
  Fetched as a single `sort=desc` page - the newest notes are on page 1 -
  with the max taken over every note of that page, so the within-page
  ordering never matters; this diverges from the mr-updates.sh full-list
  basis only if more than 100 notes share one `created_at`. With
  `--ai-only` only notes starting with the configured prefix count.
- `--expect <expected.json>` - verifies expected comment bodies against the
  discussions listing. The file uses the `mr-draft-review.sh`
  comments.json schema: `{"path":..., "line":N, "body":..., "old_side":
  optional}` anchored items (match = body byte-equality AND position
  `new_path`/`new_line`, or `old_path`/`old_line` with `old_side`),
  `{"body":...}` unanchored items (body byte-equality anywhere on the MR),
  and `{"reply_to_discussion_id":..., "body":...}` reply items (body
  byte-equality inside that discussion). A body starting with `@` names a
  file read verbatim, the trailing newline included (the same @file
  convention as `mr-comment.sh` / `mr-reply.sh`; `@-` stdin is not
  supported here). No prefix is forced: expected bodies are the FINAL
  posted bodies, compared byte-exactly as given - an out-of-hunk batch
  item posts unpositioned with `path:line` prepended after the prefix
  (`mr-draft-review.sh`), so expect that prepended body for such items.
  `--ai-only` narrows the candidate notes to ones with the configured
  prefix (`GITLAB_COMMENT_PREFIX`).

Verdicts per expected item (each verdict line carries the discussion id,
note id, anchor, and resolved flag):

- `ok` - byte-equal body at the required place;
- `anchor-mismatch` - the exact body exists but is anchored differently;
- `body-mismatch` - the expected place exists (an anchor is occupied, the
  discussion exists, or the body exists elsewhere on the MR) but body and
  place never coincide - this catches the orphan-reply trap (a reply that
  landed outside its thread);
- `not-found` - neither the body nor the expected place found.

Exit codes: 0 all expected items `ok` (or informational-only runs); 1
failure (a mismatched expected item, unparsable input, an HTTP error;
unknown option / bad flag value also exit 1); 2 usage error (missing
arguments or nothing to do, an empty expect array included). Traps
handled: pagination, concatenated page arrays, error detection by
body/stderr (never the glab exit code). The resolved flag in a verdict
line is the matched note's own flag (resolvable notes); the script never
aggregates thread state (no discussion-level flag on this instance).

Example:

```
mr-verify-posted.sh ai/streamflow/flowruntime 1903 \
  --expect comments.json --drafts --max-note-id
```

A sample expectations file is in `examples/expect.example.json`; it pairs
with `examples/comments.example.json` — run mr-verify-posted.sh from
`tools/` for that pairing: `@file` bodies resolve against the CWD, so the
sample `@examples/comments.example.body.txt` only lines up from there.
The first and third batch items verify byte-exactly (the third via that
`@file` body, byte-identical to the batch body), while the second (line
99999) posts unpositioned with `path:line` prepended and would have to be
expected with that final body. The reply item's discussion id is the
placeholder `__SECRET_0__`: it mimics the masked form the API returns for
40-hex ids on this instance (an API-captured value would itself be masked
this way) and must be replaced with a real discussion id of the target MR
for a live run. `comments.example.json` contains no reply item: the
example pair covers the anchored and unanchored kinds only.

## Testing notes

Read-only scripts (`mr-updates.sh`, `mr-threads.sh`) were exercised against
the real MR !1887 (full dump, `--since`, `--state` delta twice, open/all/
ai-only/truncation, 404 handling); write paths were exercised only with
`--dry-run` (valid anchor `flow/runtime/ytflow/pipeline_follower.cpp:102`
inside the hunk `new 1-181` of that new file, an out-of-hunk line, `--force`,
`--old-side` on `.gitlab-ci.yml:722`, `@file` bodies, batch table +
prefix refusal, reply dry-run on a real discussion id). No comment, draft,
or reply was posted while developing this toolkit, and nothing was written
into the test worktree (only read-only git commands were run there; state
files live under `GITLAB_TOOLS_STATE_DIR`).

Canary protocol (the only real MR write performed while building the write
paths): one draft (a canary note — `Canary test of the toolkit, will be
deleted immediately.` behind the then-current comment prefix — anchored on
`pipeline_follower.cpp:102`) was created
with `mr-draft-review.sh` (no `--publish`), verified via GET
(`draft_notes/830102`), deleted by id with the documented
`DELETE .../draft_notes/830102` (rc=0, empty body), and the follow-up GET
answered HTTP 404; the draft list was `[]` afterwards. The stray-draft
guard was exercised against that live draft (refusal without
`--ignore-stray`, warning on `--dry-run`). `mr-resolve.sh` was exercised
only with `--dry-run` and its guards (missing discussion, idempotent
already-resolved, non-resolvable thread); nothing was resolved or
unresolved. `mr-verify-report.sh` ran plan generation and `--emit` on real
data without `--yes`. `bulk_publish` and the single-draft publish route
were never executed against a real draft.

`mr-verify-posted.sh` was exercised live against MR !1903 after a real
review session: three anchored items (byte-exact bodies from the posted
comments.json) plus one unanchored timeline note all matched with the
expected note ids, anchors, and resolved flags; draft count 0; max note id
reported; a deliberately bogus expected body answered `not-found` with
exit 1; `@file` bodies and `--ai-only` re-verified the same set.

`mr-has-updates.sh` was exercised live against MR !2067 (read-only, all
markers in a temp directory): the first run recorded a baseline and exited
1; the immediate rerun exited 1 with empty stdout (no false positives); a
tampered copy of the marker (older max note id, older head short id,
changed title/description hashes, a different pipeline id/status, changed
reviewer/approval sets, a merged+draft MR state) exited 0 with one summary
line per category; a nonexistent project exited 3 with the HTTP 404
diagnostics on stderr and no marker written; usage errors exited 2.

The 2026-11-03 round (MR !2108, read-only + dry-run; the clone was stale on
purpose, exercising the clone-freshness guard): `mr-auth-probe.sh` answered
`ok <username>` (exit 0) on the working token whose `auth status` block
still shows `! Invalid token provided`, and exit 1 with the host + HTTP 401
diagnostic on a broken host; `mr-card.sh` (text and `--json`, with a clone,
with a stale clone, and without one) printed the full card — approvals via
the approvals endpoint, `blocking_discussions_resolved`, both merge
statuses, the recovered head, `changes_count`, the diffstat (or the
explicit no-clone NOTE; the first cut of the no-clone path died on an
unset variable with exit 1 and no card — fixed and re-verified: the card
prints, the NOTE goes to stderr, exit 0); `mr-diff.sh` ran all five modes — the stale clone
degraded every mode to the local source-branch tip with the expected-head
warning, and `--conflicts` labeled the fallback verdict and listed the
conflicting paths (exit 1); `mr-has-updates.sh` recorded schema-4 baselines
(with and without `--no-ci` — the `--no-ci` baseline stores no pipeline
fields), kept the saved pipeline value across a `--no-ci` window, detected
the CI delta on the switch-back run (exit 0), loaded a schema-3 marker
without the new field as "not changed", and reported
`merge status: blocking_discussions_resolved: false -> true` plus the
approvals diff on a tampered marker; `mr-updates.sh` stored the schema-3
marker (merge-status snapshot + approvals), printed nothing on an unchanged
rerun, printed the `== merge status ==` section (one line per changed
aspect) on a tampered marker, and re-upgraded a schema-2 marker without a
false change; `mr-threads.sh --all` showed 11 system notes that
`--no-system` dropped, with the system-only threads leaving the shown count
(18 -> 7); `GITLAB_COMMENT_PREFIX='[ai] '` (the prefix the repository owner
actually uses on that MR; it became the toolkit's built-in default
afterwards) drove the write-path prefix refusals and the
`--ai-only` selections in `mr-comment.sh`, `mr-draft-review.sh`,
`mr-threads.sh`, and `mr-verify-posted.sh`; `--repo <dir>` was validated
(exit 2 on a nonexistent directory) in all twelve scripts that accept it.
No comment, draft, reply, resolve, or publish was posted.

The 2026-11-03 card/list round (MR !2039, read-only): `mr-card.sh` (text
and `--json`, with a clone) printed the new approvals-endpoint fields —
`approved: false (approvals_required: 1)` in the text card,
`"approved": false` / `"approvals_required": 1` in the JSON — alongside
the existing `approved_by`, both branches, and the recovered head
172675b1e9bc5549597b5c12c4fc34a59a9cdd64 with provenance `commits
endpoint` (the sha masking is flaky per request: in the same session some
`/commits` and single-MR responses arrived fully masked with
`__SECRET_N__` placeholders — the ladder recovered the head anyway);
`mr-list.sh --role reviewer --state opened` printed the new
`source_branch -> target_branch` line in every block (12 MRs, !2039
among them), and `--json` carried both branch fields in every item (the
normalized array keeps the endpoint objects as returned); `mr-diff.sh`
ran the default diff and `--conflicts` (clean verdict, exit 0, consistent
with the card's `merge_status: can_be_merged`).
