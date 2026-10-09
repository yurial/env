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
| `GITLAB_DEFAULT_PROJECT` | (empty)                   | `<project>` positional may be omitted when set; the remaining positionals shift left (mr-updates/mr-threads/mr-verify-posted: 1 arg, mr-draft-review/mr-resolve/mr-verify-report: 2 args, mr-reply: 3 args, mr-comment: 4 args) |
| `GITLAB_REPO`            | (cwd)                     | git clone used for sha recovery / hunks            |
| `GITLAB_TOOLS_STATE_DIR` | `<tools>/.state` (next to `lib.sh`) | directory for `--state` marker files given as a bare filename (mr-updates.sh); created on demand |
| `GITLAB_TOKEN`           | glab config               | auth token, honored by glab itself                 |

All output is plain text, no ANSI colors (`NO_COLOR` needs no handling).
Exit codes: 0 success, 1 failure, 2 usage error.

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
8. **Every posted comment must start with the prefix `AI generated: `.**
   All write scripts refuse to post otherwise, unless `--no-prefix` is
   passed.

## lib.sh

Shared helpers sourced by every script (the single shared library file):
config loading, API wrapper + error detection, concatenated-JSON parsing,
pagination, sha recovery, hunk range building/summarization, GraphQL call
helper, prefix check, `@file` body loading.

## mr-updates.sh

```
mr-updates.sh <project> <mr_iid> [--since <iso8601|sha>] [--state <file>] [--fetch]
```

Prints MR state (head sha, updated_at, draft, state), new commits, all notes
newer than the marker, and thread status changes. `--since` accepts an
ISO8601 timestamp or a commit sha (walk stops right before it). With
`--state <file>` the head sha (+ its short_id) plus max note id/created_at
are stored after printing; the next run reports only the delta (no marker
file = full dump). A bare `--state` filename resolves under
`GITLAB_TOOLS_STATE_DIR`. The marker schema is additive (`"schema": 2`);
older markers load unchanged, and a masked sha (`__SECRET_N__`) in a marker
is ignored for the cutoff (the timestamp cutoff takes over). Commits come
from `git log origin/<source_branch> --not origin/<target>` when run inside
a clone (branch must exist locally; `--fetch` refreshes it), otherwise from
the API commits endpoint; inside a clone every new commit line carries a
diffstat suffix `(<n> files, +a/-b)` (merge/root commits without numstat get
none). Notes always come from the API (GET-only).

When the delta contains resolution events, a `== thread status changes ==`
section is printed (nothing when there are none). It lists system notes
`[resolved]` / `[unresolved]` and `resolved all threads` with the discussion
id (mapped by note id via a lazy discussions GET), the anchor path of the
thread, who flipped the state, and the first line of our original
`AI generated: ` note (or the thread's first note) for context. An
MR-timeline `resolved all threads` note that is not attached to any
discussion is reported as `(all threads; MR timeline note)`.

Example:

```
mr-updates.sh ai/streamflow/flowruntime 1887 --state mr1887.json
```

## mr-threads.sh

```
mr-threads.sh <project> <mr_iid> [--open|--all] [--ai-only] [--max-chars N] [--full]
```

Dumps discussions as readable text: discussion id, resolved state (resolved
iff every non-system note has `resolved:true`), anchor `path:line` (new
side; old side when there is no new line), authors, full note bodies
(truncated to 400 chars by default; `--max-chars N` / `--full`). `--open`
(default) keeps only unresolved threads; `--ai-only` keeps threads
containing a note that starts with `AI generated: `. GET-only.

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
to the body, keeping the `AI generated: ` prefix first), then POSTs via the
discussions API and verifies creation by GET. `--dry-run` prints the exact
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
```

Replies into an existing thread: tries REST
`discussions/<id>/notes` first, verifies the note landed **inside** the
discussion (GET); on 404 or the silent-orphan result it falls back to
GraphQL `createNote` with `gid://gitlab/Discussion/<discussion_id>` and
verifies again. `--dry-run` prints both payloads.

## mr-resolve.sh

```
mr-resolve.sh <project> <mr_iid> <discussion_id> [--unresolve] [--dry-run]
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
  note text (notes start with `AI generated: `); zero or several matching
  discussions is an error with the candidates listed - the plan is never
  built on a guess;
- `{"action": "new", "path": ..., "line": N, "old_side": optional,
  "text": ...}` - the anchor is validated like mr-comment.sh; out-of-diff /
  out-of-hunk items are refused with the valid ranges.

`text` is the body WITHOUT the `AI generated: ` prefix - the script adds it
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
                     [--max-chars N] [--full]
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
  `--ai-only` only notes starting with `AI generated: ` count.
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
  `--ai-only` narrows the candidate notes to `AI generated: ` ones.

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
expected with that final body. The reply item's discussion id is a
masked-value placeholder (`1ba268fb6712127820af0b181b3f2633e110aef4`)
captured from an API response - replace it with a real discussion id of
the target MR for a live run. `comments.example.json` contains no reply
item: the example pair covers the anchored and unanchored kinds only.

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
paths): one draft (`AI generated: Canary test of the toolkit, will be
deleted immediately.`, anchored on `pipeline_follower.cpp:102`) was created
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
