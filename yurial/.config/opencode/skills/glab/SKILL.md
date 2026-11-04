---
name: glab
description: "Use when working with GitLab from the command line via glab. The bundled `tools/` scripts (gitlab-tools, next to this skill) are the REQUIRED mechanical path — use them first for MR update polling with state markers (merge status included), the fast boolean has-updates timer check and the timer/watcher gate scenario over it, a live token-health probe, global role-based MR listing (reviewer/assignee/author across all projects), the MR card, the true local MR diff (file/stat/hunk/conflict modes), thread dumps, single line-anchored comments, batch draft review with safe publish, discussion replies, single-thread resolve, and read-only post-publish verification of posted comments (draft count, max note id, body/anchor verification); reach for `glab api` directly ONLY for operations outside that set (fields, bodies, pagination, URL-encoded paths). Beyond the tools, the skill covers listing, viewing, creating, checking out, approving, and merging merge requests (MRs), writing MR descriptions (Russian description, English commit message), reading and posting MR comments (line-anchored comments), batch posting of review comments, line-anchor validation against diff hunks, review comments via draft review (draft notes, publish all at once), discussion replies via GraphQL fallback, thread resolution state, processing incoming review comments as the MR author (individual comment workflow, resolve discipline), filtering MRs by role (reviewer, assignee, author), draft/WIP MRs, managing issues, checking CI/CD pipelines and jobs. Covers glab-specific traps: repository context, scope=all, iid vs id, pagination, flag collisions, HTTP 401/403/404 disambiguation, non-interactive usage. Use ONLY for glab/GitLab CLI operations, not for plain git workflows or other forges."
---

## Tool-first rule (mechanical path)

The bundled `tools/` scripts are the REQUIRED mechanical path for every
operation they cover. Before writing ANY `glab api` call, pipeline, or
ad-hoc script for an MR/GitLab operation, check the mapping below — the
tools already encode the instance traps (pagination, sha masking,
rc=0-on-error, comment prefix, anchor validation).

| operation | script |
|---|---|
| has anything changed (commits/notes/threads/state/CI) | `mr-has-updates.sh` |
| state + delta of commits/notes/threads since a marker | `mr-updates.sh --state` |
| thread dump: open/resolved, authors, bodies, ids | `mr-threads.sh --open\|--all` |
| true local MR diff / files / hunks / conflicts | `mr-diff.sh` |
| MR card (state, approvals, head sha) | `mr-card.sh` |
| line-anchored comment | `mr-comment.sh` |
| reply into an existing thread | `mr-reply.sh` |
| resolve / unresolve one thread | `mr-resolve.sh` |
| batch review / verdict plan / post-publish verification | `mr-draft-review.sh` / `mr-verify-report.sh` / `mr-verify-posted.sh` |
| global role-based MR listing (reviewer/author/assignee) | `mr-list.sh` |
| token health | `mr-auth-probe.sh` |

Full contracts (arguments, exit codes, guards) are in `tools/README.md`;
one line per script is in section 22.

Hand-built `glab api` calls are allowed ONLY for operations this table
does not cover. A "my need is just a simple GET" is not an exception —
the first ad-hoc script is how the hand-rolled pipeline starts.

# glab: GitLab CLI — typical workflows and traps

This skill is a practical guide to glab, the GitLab CLI: repository context,
authorization, non-interactive usage, role-based MR lists, drafts, typical
operations, MR descriptions and review comments (single and batch posting of
line-anchored comments, anchor validation against diff hunks), the draft
review flow (draft notes created first, then published all at once with a
single call), replying in discussions (GraphQL fallback) and thread
resolution state, processing incoming review comments as the author
(one comment at a time, resolve discipline), the REST API via
`glab api` (fields, bodies, URL-encoded
paths, pagination) and GraphQL via `glab api graphql`, reading HTTP errors,
issues, and CI/CD pipelines and jobs. Alongside these manual protocols the
skill carries the gitlab-tools toolkit (section 22) — bash+python3 scripts
in `tools/` next to this file that implement the review workflows
mechanically — including the read-only post-publish verifier
`mr-verify-posted.sh` — and are the required path for their operations
(the Tool-first rule above).
Verified against glab 1.36.0; behavior marked instance-dependent was
observed live on a self-managed GitLab (18.7.7-ee at first, 18.8.11-ee by
2026-10) and is not guaranteed on other instances. On another glab version
re-check flags with `glab <command> --help` before relying on them. Every
identifier in the examples is a placeholder: `<group/project>`, `<username>`,
`<iid>`, `<job-id>`.

## 1. Repository context

The `glab mr ...`, `glab issue ...`, `glab ci ...` commands must run inside a
git repository: the host and the project are derived from `git remote`
(usually `origin`). Outside a repository the command fails with
`fatal: not a git repository (or any of the parent directories): .git` and
exit code 1 — that is a context error, not "the project has no MRs".

- To work with a specific (including someone else's) project, use the `-R`
  flag: `glab mr list -R <group/project>` (format `<group>/<project>`, nested
  groups `<group>/<subgroup>/<project>`; a full project URL or git URL also
  works). The `-R` flag exists on all `glab mr`, `glab issue`, and `glab ci`
  commands.
- `glab api` and `glab auth status` work from anywhere: the host comes from the
  authentication config — inside a git repository the host of that repository
  is used, outside it the default host (overridable with the `--hostname` flag
  of `glab api`).

## 2. Authorization

`glab auth status` — check who you are logged in as and on which hosts; works
from any directory. Before working with a new host, make sure it has a valid
token (`✓ Logged in ... as <username>`); `x`/`!` lines in the output
(`x No token provided`, `! Invalid token provided`) are indicators of a token
problem to check — not a verdict: they can coexist with a working token, so
the token's health is decided by a live API call (section 15). The preferred
mechanical form of that live probe is the bundled `mr-auth-probe.sh`
(section 22): one GET `user`, exit `0` with exactly `ok <username>` on
stdout, exit `1` with a stderr diagnostic naming the host and the HTTP code.

- Non-interactive login: `glab auth login --hostname <host> --stdin` reads the
  token from standard input (minimum token scopes: `api`, `write_repository`).
- Environment variables: `GITLAB_TOKEN` — token for API requests (overrides
  stored credentials); `GITLAB_HOST` — the GitLab host for self-managed
  instances.

## 3. Non-interactive usage and machine-readable output

Agents run non-interactively: an unexpected prompt hangs the whole run.

- `NO_PROMPT=1` disables glab's interactive prompts.
- Mutating commands take `-y`/`--yes` to skip the submission confirmation
  prompt: `glab mr create --fill -y`, `glab mr merge <iid> -y`,
  `glab issue create -t "<title>" -y`.
- Prefer explicit flags over prompts (`glab mr create -t <title> -d
  <description>`, `--no-editor` to avoid opening an editor).
- `NO_COLOR` strips ANSI escape sequences from output you are going to parse.
- In scripts use long flag names: short flags collide across subcommands —
  `-F` is `--field` in `glab api` but `--output-format` in `glab issue list`;
  `-f` is `--raw-field` in `glab api` but `--fill` in `glab mr create`.

Machine-readable output:

- `glab api` is the reliable JSON source: it prints raw JSON to stdout.
- `glab mr list` has no JSON output format in glab 1.36.0 — when you need
  JSON, query the API instead:
  `glab api "projects/:fullpath/merge_requests?state=opened"`.
- `glab issue list -F ids` (and `-F urls`) prints one iid (one web URL) per
  line — machine-friendly without full JSON.
- `glab api` exits 0 even on HTTP errors (400, 401, 404): check the stderr
  line `glab: <message> (HTTP <code>)` or the response body, never the exit
  code (see section 14).

## 4. MR lists by role

Inside a repository — `glab mr list` with a role filter (`@me` is the current
user):

```bash
glab mr list --reviewer=@me    # where I am the reviewer
glab mr list --author=@me      # where I am the author
glab mr list --assignee=@me    # where I am the assignee
```

The list is limited to one project (or a group with `-g <group>`); by default
one page of 30 records — use `-P <n>` (per page) and `-p <n>` (page number)
when listing.

Across all accessible projects — the global REST endpoint `merge_requests`:

```bash
glab api "merge_requests?reviewer_username=<username>&state=opened&scope=all"
# likewise: author_username=<username>, assignee_username=<username>
```

The output is a JSON array; parse it with jq or python. Useful fields of each
MR: `iid`, `title`, `state`, `references.full` (full project path + iid),
`web_url`, `work_in_progress`, `author`.

The mechanical path for the global listing is the bundled `mr-list.sh`
(section 22): it carries the mandatory `scope=all` (section 5), full
pagination, and role/state/draft filters, so the traps below cannot be
forgotten.

## 5. The scope=all trap (critical)

Without `scope`, the global `merge_requests` endpoint returns only MRs created
by the user themself (the default scope is `created_by_me`). A "where am I a
reviewer" query without `&scope=all` silently returns a wrong list — only the
caller's own MRs among those matching the filter, often an empty one — and it
is easy to draw the false conclusion "there are no MRs".

Rules:

- Any global MR search by `reviewer_username` / `author_username` /
  `assignee_username` — only with `&scope=all`.
- The global `issues` endpoint has the same documented default scope — add
  `&scope=all` there too.
- On an empty result, before reporting "no MRs", check in order: whether
  `scope=all` is present; whether `state` is right (`opened` excludes
  `merged`/`closed`); whether the right project/group is being searched.

## 6. iid vs the global number

- `iid` is the MR number within a single project; it is the number used in the
  URL and passed to `glab mr <subcommand> <iid>` commands. Only `id` is
  globally unique.
- The same `iid` in different projects means different MRs.
- `404 Not Found` from `glab mr view <N>` more often means "wrong project"
  than "the MR does not exist": the host and project were taken from the
  current repository (see also section 14).
- Therefore, when viewing an MR by number, always either work from that
  project's repository or specify the project explicitly: `glab mr view <iid>
  -R <group/project>`.

## 7. Drafts

- A draft MR has a `Draft:` / `WIP:` title prefix; in the API — the field
  `work_in_progress: true`.
- Filtering: in `glab mr list` — the `-d`/`--draft` flag (drafts only); in API
  queries — the `wip=yes` / `wip=no` parameter.
- Always show the draft status in reports to the user (e.g. from the
  `work_in_progress` field of the JSON response or the `Draft:` prefix in the
  title): a draft is usually not ready for review/merge.

## 8. Typical MR operations

An MR can be addressed by number (`<iid>`) or by its source branch name;
without an argument, the MR of the current branch is used.

```bash
glab mr view <iid>          # MR card: title, description, status
glab mr diff <iid>          # MR diff
glab mr checkout <iid>      # check out the MR branch locally
glab mr create --fill       # create an MR; --fill — title/description from commits
glab mr approve <iid>       # approve
glab mr merge <iid>         # merge (useful: -y, --squash, -d/--remove-source-branch)
glab mr close <iid>         # close
glab mr reopen <iid>        # reopen
```

All commands accept `-R <group/project>`.

When creating an MR, set the "delete source branch on merge" flag:
`glab mr create --remove-source-branch` — the branch deletion is then carried
by the MR and happens however the MR is later merged. Mind the short-flag
collision (section 3): in `mr create` `-d` is `--description`, so only the
long form sets the branch flag; in `mr merge` `-d` is
`--remove-source-branch` — the fallback for an MR created without the flag:
`glab mr merge <iid> -d`.

## 9. Leaving comments — mandatory `[ai]` prefix

Every comment posted via glab — a note on an MR, a comment on an issue, or a
reply in a discussion — must begin with the prefix `[ai] ` (brackets plus a
trailing space) followed by the comment text. The prefix marks the comment as
machine-generated: never post a comment without it.

```bash
glab mr note <iid> -m "[ai] <comment text>"             # note on an MR (<iid> or branch)
glab issue note <iid> -m "[ai] <comment text>"          # comment on an issue
# reply in an existing MR discussion — via the API (:fullpath = current repository):
glab api -X POST "projects/:fullpath/merge_requests/<iid>/discussions/<discussion_id>/notes" \
  --raw-field body="[ai] <comment text>"
```

Rules:

- The prefix is mandatory for every posted comment, without exceptions for
  short one-line comments; in a multi-line comment the first line still
  begins with `[ai] `.
- The marker TEXT is configurable per host/repository: the MR/repository
  owner may prescribe a different prefix, set through
  `GITLAB_COMMENT_PREFIX` (environment > `tools/config.sh` > the built-in
  default `[ai] ` — a value first observed as an owner-prescribed marker on
  a repository whose owner required it). The bundled tools check and filter
  by the configured text; the rule itself does not change — every
  machine-generated comment carries the configured marker, without
  exceptions.

```bash
GITLAB_COMMENT_PREFIX='<prefix> ' mr-comment.sh <group/project> <iid> <path> <line> "<prefix> <comment text>"
# the env var sets the prefix for this one command (precedence: environment > config.sh > default - see above)
```

- Repo context (section 1) applies: `glab mr note` and `glab issue note`
  accept `-R <group/project>`; in `glab api` use the `:fullpath` placeholder
  inside the repository, or the URL-encoded project path (section 12).

## 10. MR descriptions and review comments

Languages of an MR: the description is written in Russian and describes both
the problem and the way this problem is solved; the MR commit message is
written in English and semantically mirrors the Russian description.

- Pass the description explicitly:
  `glab mr create -t "<title>" -d "<description in Russian>"`; correct it
  later with `glab mr update <iid> -d "<description>"`.
- Do not rely on `--fill` (section 8): it fills the title/description from
  commit info — English text, the wrong language for the description.
- The English commit message is set at merge time: `glab mr merge <iid> -m
  "<message>"` (with `-s/--squash` — `--squash-message "<message>"`).

Reading review comments: always resolve the line numbers a comment refers
to and read the code at those lines before replying or acting on it.

```bash
glab mr view <iid> --comments  # quick view: comments and activities
glab api "projects/:fullpath/merge_requests/<iid>/discussions?per_page=100"
# machine-readable form (pagination — section 13); a diff-anchored note
# carries "position": new_line/new_path (new side) or old_line/old_path
# (old side), position_type "text", line_range when it spans a block of
# lines; a note without "position" is a top-level MR note
```

Read the anchored lines in `glab mr diff <iid>` or in the checked-out MR
branch (section 8) — never discuss code you have not read at the anchored
lines.

Writing review comments about specific code: leave a line-level comment
anchored to that line/block, not a top-level note. `glab mr note` posts
only top-level notes (no line anchoring in 1.36.0); a line-anchored
comment is created via the discussions API — `body` plus a `position` built
from the MR's `diff_refs` (`base_sha`, `head_sha`, `start_sha`; the
single-MR endpoint provides them, the list endpoint returns
`diff_refs: null`):

```bash
glab api -X POST "projects/:fullpath/merge_requests/<iid>/discussions" --input <file>
# <file> — JSON body passed verbatim (--input, section 12):
# {"body":"[ai] <comment text>",
#  "position":{"base_sha":"<sha>","start_sha":"<sha>","head_sha":"<sha>",
#              "position_type":"text","new_path":"<path>","new_line":<n>}}
```

- For a comment on the old side of the diff use `old_path` + `old_line`
  instead of `new_path` + `new_line`.
- The mandatory `[ai] ` prefix (shown with the default prefix; the
  configured one per section 9) applies to line-anchored comments as to
  every other.

Batch posting of tens of line-anchored comments in one run follows a fixed
protocol:

- Validate every anchor against the diff before posting. A position is
  accepted only on lines inside diff hunks (added or changed lines);
  `new_line` on a context (unchanged) line fails with HTTP 400 and a body
  naming an invalid line_code. grep finding the marker in the file is not
  enough — the line must be part of a hunk. Collect the new-side line
  ranges from the hunk headers
  (`@@ -<old> +<start>,<count> @@`) of the diffs endpoint
  `glab api "projects/:fullpath/merge_requests/<iid>/diffs?per_page=100"`
  (paginated like any list — section 13) and check each anchor against
  them.
- Take `diff_refs` from the single-MR endpoint immediately before posting
  the batch and never cache them across sessions: they change when the
  author pushes to the source branch or the target branch moves, and a long
  batch can have its shas rotated mid-run. Notes created against a
  superseded diff version are marked outdated by GitLab — that is expected,
  not an error.
- Post the first comment alone (a canary) and verify the response schema —
  discussion id, note id, position — before posting the rest.
- Detect failures by the response body (fields `message`/`error`) and the
  stderr line, never by the exit code: `glab api` exits 0 on HTTP 400 for
  POST as well (section 3). On a 400 naming position/line_code, retry the
  same body without `position` — the note lands as a top-level note; keep
  the reference by writing `<path>:<line>` into the text.
- Save `discussion_id`/`note_id` from every POST response: the final
  verification is then the set of saved ids, not a full re-fetch of all
  discussions. The read-only after-the-fact check that the expected bodies
  are really posted (byte-exact, with anchors) is mechanized by
  `mr-verify-posted.sh --expect` (section 22).
- Instance-dependent (observed once on GitLab 18.7.7-ee): a raw-body POST
  (`--input`) returned rc=0 with `{"message":"500 Internal Server Error"}`
  in the body while the note had in fact been created — after mass writes
  verify creation by the response id or a targeted GET, trusting neither
  the exit code nor the message in the body alone.
- Instance-dependent (observed once, cause unconfirmed): posting tens of
  comments in rapid succession under one account transiently affected that
  account's web UI. Work in batches, verify via the API, and warn the user
  before large insertions.

## 11. Review flow: draft notes, publish all at once (preferred)

For a review with multiple line-anchored comments, do not POST every
comment straight into discussions: build the review as draft notes and
publish them all with one call. A draft note is a pending, unpublished
comment on an MR — before publishing it is visible only to its author
(per GitLab docs) — so creating, inspecting, and deleting drafts is
private and recoverable; publishing is the single public step. glab
1.36.0 has no high-level draft-note commands (verified against help):
the flow rides entirely on `glab api`.

```bash
# availability probe: the draft list answers 200 with an array
# (empty when no drafts) if the API is on; 404 — see the fallback below
glab api "projects/:fullpath/merge_requests/<iid>/draft_notes"

# draft body: TOP-LEVEL "note" STRING + optional top-level "position"
# (diff_refs from the single-MR endpoint, section 10)
cat > <file> <<'EOF'
{"note":"[ai] <comment text>",
 "position":{"base_sha":"<sha>","start_sha":"<sha>","head_sha":"<sha>",
             "position_type":"text","new_path":"<path>","new_line":<n>}}
EOF

# create the drafts, one POST per comment of the review
glab api -X POST -H "Content-Type: application/json" \
  "projects/:fullpath/merge_requests/<iid>/draft_notes" --input <file>
# success body: {"id":<draft_note_id>,"note":"...","line_code":"...",
#                "position":{...},"resolve_discussion":false,
#                "discussion_id":null,"commit_id":null,"author_id":<n>}

# verify the whole set before publishing (paginated — section 13)
glab api "projects/:fullpath/merge_requests/<iid>/draft_notes?per_page=100"

# publish ALL pending drafts of the current user in ONE call
glab api -X POST "projects/:fullpath/merge_requests/<iid>/draft_notes/bulk_publish"

# a wrong draft: delete and recreate (creation is private, failures are recoverable)
glab api -X DELETE "projects/:fullpath/merge_requests/<iid>/draft_notes/<draft_note_id>"
# empty body on success; the next GET of the draft answers 404

# publish a single draft (per GitLab docs, not live-verified)
glab api -X PUT "projects/:fullpath/merge_requests/<iid>/draft_notes/<draft_note_id>/publish"
```

Contract traps (live-verified on GitLab 18.7.7-ee):

- `note` is a top-level string. A nested object
  `{"note":{"body":...,"position":...}}` answers HTTP 400
  `{"error":"note is invalid"}`; `position` is a top-level sibling of
  `note` (as are `resolve_discussion` and `in_reply_to_discussion_id`
  per GitLab docs).
- A raw-body POST (`--input`) without a Content-Type header answers HTTP
  415 `{"error":"The provided content-type '' is not supported."}` —
  always pass `-H "Content-Type: application/json"` (request construction,
  section 12).
- The server does NOT validate a draft's anchor: a position with
  `new_line` beyond the end of the file was accepted at creation, and
  `old_path` is optional in practice. Validate every anchor against hunk
  ranges client-side BEFORE creating the drafts (section 10) — an invalid
  anchor surfaces only at publish time, after the batch has gone public.
- Detect failures by the response body, never the exit code (section 14):
  `glab api` exits 0 on HTTP 400/415 here as everywhere.
- `bulk_publish` publishes all pending drafts of the current user in one
  call; the drafts become real notes/discussions, and the draft list
  empties (per GitLab docs). Optional body fields per GitLab docs, not
  live-verified: `note` — a summary note added to the MR, `internal`,
  `reviewer_state` (`requested_changes`|`reviewed`). On 18.7.7-ee both
  publish routes exist (verified without publishing: `bulk_publish` on an
  empty draft set is a no-op answering an empty body; the single-publish
  route answers 400 `{"error":"draft_note_id is invalid"}` on a
  non-integer id); the publish actions themselves are per GitLab docs,
  not live-verified — version/instance-dependent.

Order of operations for a review: fetch `diff_refs` from the single-MR
endpoint → validate every anchor against hunk ranges (section 10) →
create N drafts (failures by response body) → verify the draft list via
GET → one `bulk_publish` → optionally verify the published notes via the
discussions endpoint (section 17) — mechanized by `mr-verify-posted.sh`
(section 22), which also reports the pending-draft count and the max note
id baseline.

- The mandatory `[ai] ` prefix (shown with the default prefix; the
  configured one per section 9) applies to every draft note as to every
  other comment.
- `diff_refs` freshness (section 10) applies to draft positions the same
  way: if the shas rotate between draft creation and publishing, the
  published notes are marked outdated — expected, not an error.
- Fallback: if the availability probe answers 404, the instance does not
  offer the draft-notes API (instance-dependent) — post the review by the
  direct batch protocol of section 10. A direct `POST .../discussions`
  also remains the right tool for a single comment outside a review;
  replies into existing threads go per section 19 (draft notes accept
  `in_reply_to_discussion_id` for replies per GitLab docs, not
  live-verified).

## 12. glab api: fields, bodies, and URL-encoded paths

Passing parameters. The default method is GET; adding any field switches it
to POST; `-X`/`--method` overrides explicitly:

- `-f`/`--raw-field key=value` — a string parameter, no type conversion:
  `--raw-field body="<text>"`.
- `-F`/`--field key=value` — a typed parameter: the literals `true`/`false`/
  `null` and integers are converted to JSON types; a value starting with `@`
  is read from that file, `-` from standard input — the standard way to pass
  multiline text: `--field description=@<file>`.
- A raw request body (e.g. a ready JSON document) is passed with
  `--input <file>` (`-` = stdin); in this mode the `-F`/`-f` flags are
  serialized into URL query parameters instead of the body.
- `-H`/`--header "Key: Value"` adds HTTP headers.

Project paths in API URLs:

- Inside a repository use the `:fullpath` placeholder — it is replaced with
  the current project: `glab api projects/:fullpath/merge_requests`.
- Outside a repository (or for another project) the path must be URL-encoded:
  `projects/<group>%2F<project>/merge_requests` — a raw `/` splits the URL
  into segments and the route does not resolve.
- The two 404 shapes tell them apart: an unencoded path answers a generic
  `{"error":"404 Not Found"}` even when the project exists; the encoded path
  for a missing project answers `{"message":"404 Project Not Found"}`.
- `glab api` has no `-R/--repo` flag (verified against 1.36.0 help): the
  project is always part of the URL — `:fullpath` inside the repository or
  the URL-encoded path outside it — and the host is selected with
  `--hostname <host>`. The `-R` flag exists on `glab mr`, `glab issue`,
  `glab ci` commands, not on `glab api`.

## 13. API pagination

`glab api` returns a single page (20 records by default). For complete lists:

- add `&per_page=100` and walk the pages (`&page=2`, `&page=3`, ...);
- or use the `glab api --paginate` flag — it fetches all pages sequentially
  (useful combined with jq when you need one continuous stream).

A missing "tail" of a large list is a typical symptom of forgotten pagination:
check whether the result was cut off by the page limit.

## 14. HTTP errors: 401 vs 403 vs 404

`glab api` prints the response body to stdout and `glab: <message> (HTTP
<code>)` to stderr — and exits 0 (section 3): read the code, not the exit
status. Disambiguation:

- `401 Unauthorized` — token problem for that host: missing, invalid, or
  expired. Check `glab auth status` (section 2) — a hint, not a verdict
  (section 15) — and re-login.
- `403 Forbidden` — the token is valid, but the account lacks permission for
  this action (e.g. admin-only endpoints, merging without access).
- `404 Not Found` — most often a wrong project: the host/project were taken
  from the repository context or the path was not URL-encoded (section 12);
  only then "the resource does not exist" (see also iid vs id, section 6).

## 15. Multi-host auth: `auth status` can mislead (trap)

On a machine with several configured hosts, `glab auth status` prints a block
per host. Three pitfalls observed in practice:

- A `✓` on one host does not validate another: a per-host block may show
  `Token: ****` (a token is stored) together with `! Invalid token provided`
  — the stored token may be stale/expired, and an API call against that host
  then returns 401 even though `auth status` "shows a token".
- `glab auth status` without `--hostname` may check a different host than the
  one your API calls use. Always pass `--hostname <host>` when diagnosing a
  specific host: `glab auth status --hostname <host>`.
- Instance-dependent (observed 2026-10-26 on GitLab 18.8.11-ee): within ONE
  host block the lines `✓ Logged in to <host> as <username>` and `! Invalid
  token provided` may coexist while the token is in fact working — the very
  next live API call against that host returned 200. The `✓ Logged in ...
  as <username>` line is itself derived from a successful `/user` call, so
  it already proves the token usable; the `!` line alone is not a verdict.

Rule: `auth status` output is a hint to check, never a verdict. The health
of a token is decided only by a live API call — a cheap one suffices:
`glab api user --hostname <host>` (200 — the token works, ignore the `!`
line; 401 — the token is broken). The preferred mechanical form of that
probe is the bundled `mr-auth-probe.sh <host>` (section 22): the same single
GET `user` with the verdict on stdout (`ok <username>`) and the host + HTTP
code in the diagnostic on failure. Re-login is performed only after a real
401 from a live call (section 14), never on an `!` line alone.

Recovery: first a live probe — `mr-auth-probe.sh <host>` (raw form:
`glab api user --hostname <host>`); only on a real 401 re-login
`glab auth login --hostname <host> --stdin`, or supply a fresh token via
`GITLAB_TOKEN` (section 2). `glab api` still returns 401 with exit code 0
(section 3/13).

## 16. Git-over-HTTP(S) auth: tokens do not always work for push (trap)

`glab` covers the API. `git push`/`git fetch` over HTTPS authenticate
separately, and on self-managed instances an API token — even a working one —
may be rejected for git-over-HTTP (`remote: HTTP Basic: Access denied`) when
its scope or the instance policy disallows git HTTP access. Symptoms:

- `glab api ...` works (200), `git push` over HTTPS fails with
  `HTTP Basic: Access denied`;
- `git push` over SSH fails with `Permission denied (publickey)` when no SSH
  key is loaded.

Reliable options, in order:

1. Prefer SSH remotes with a loaded agent key
   (`ssh -T git@<host>` prints `Welcome to GitLab, @<username>!` on success).
2. If only HTTPS is available, use the token as the password with the
   `oauth2` username only after verifying it is accepted for git HTTP on this
   instance: `git push https://oauth2:<token>@<host>/<group>/<project>.git`.
3. After switching a remote URL back and forth, restore it:
   `git remote set-url origin git@<host>:<group>/<project>.git`.

Never leave a token embedded in a remote URL (it lands in `.git/config` in
plain text).

## 17. Reading MR review comments: use the discussions endpoint (trap)

`GET .../merge_requests/<iid>/notes` returns a flat list of all notes
(system + user) with no file/line context and mixed ordering — easy to miss a
line-anchored comment or mistake it for a top-level note. The right endpoint
for review comments is **discussions**:

```bash
glab api "projects/:fullpath/merge_requests/<iid>/discussions?per_page=100"
```

- Each discussion is a thread: its `notes` carry the comment text, author,
  and — for diff-anchored notes — `position` with `new_path`/`new_line`
  (or `old_path`/`old_line`) and `position_type` (section 10).
- Filter to actual comments: skip notes with `system: true`; a note with a
  `position` is line-anchored, without — a top-level note.
- The listing itself is paginated (section 13): `per_page` up to 100, and
  an MR with more than 100 discussions requires walking pages — a comment
  set silently cut at a round boundary is forgotten pagination, not the
  whole review.
- Reply into the same thread via
  `POST .../discussions/<discussion_id>/notes` (section 9) — this keeps the
  answer attached to the reviewer's comment instead of opening a new thread.

Workflow for "check the review comments on MR <iid>": fetch discussions,
list non-system notes with their anchored `new_path:new_line`, read the code
at those lines (section 10), then reply per discussion with the mandatory
prefix.

## 18. Processing review comments as the author (workflow)

When you are the MR author working through incoming review comments —
often over several rounds against the same MR — follow this workflow;
each rule below exists because skipping it caused a real failure.

- Fetch ALL discussions (section 17) each round. Never filter "new"
  comments by a remembered time threshold alone: an approximate
  `created_at` cutoff silently skips a note created shortly after the
  main batch. If you use a `created_at` threshold at all, take it as
  the maximum id and `created_at` of every note you have already
  processed — recorded from fetched data, not from memory — and
  re-fetch the full list anyway (paginated — section 13). A thread
  counts as handled only when it already contains your own reply.
- Process comments ONE BY ONE, keyed by note id: read the anchored
  lines (section 10) and the full comment text before deciding
  anything. Two comments about the same topic are two work items
  unless they state the same requirement — never merge them; when in
  doubt, treat them as separate, and ask the comment author or the
  user rather than guess.
- For each comment decide: a code/spec change, or a reasoned reply. A
  "no change needed" reply must cite verified facts from the code or
  documentation as `<path>:<line>` references. If your check proves
  your earlier interpretation of the comment wrong — fix the code, do
  not argue.
- Resolve a discussion ONLY after the fix is pushed or the reasoned
  reply is posted in the thread. A comment phrased as a question is
  not resolved without the author's confirmation or an explicit user
  decision. Never batch-resolve discussions — a loop of
  `PUT ...?resolved=true` over discussion ids without reading each
  text is forbidden (the route follows the GitLab docs; the
  batch-resolve failure mode was observed live):

```bash
# resolve ONE thread you have read and answered (not in a loop):
glab api -X PUT "projects/:fullpath/merge_requests/<iid>/discussions/<discussion_id>?resolved=true"
```

- After replying, re-verify the remaining unresolved set individually,
  per discussion (thread-state rules — section 19), never by counting
  discussions or replies.

## 19. Replying in discussions and thread state (trap)

The documented REST reply path is
`POST .../discussions/<discussion_id>/notes` (section 9). On some instances
(observed on GitLab 18.7.7-ee — instance-dependent) it answers 404, while
the `in_reply_to_discussion_id` parameter of `POST .../notes` is silently
ignored: the reply lands as a separate orphan discussion. The working path
on such an instance is the GraphQL mutation `createNote` with a
`discussionId` of the form `gid://gitlab/Discussion/<discussion_id>`, sent
via `glab api graphql` (the `graphql` endpoint is documented in
`glab api --help`; fields other than `query`/`operationName` are passed as
GraphQL variables, so the object `input` goes via a raw `--input` body):

```bash
glab api graphql --input <file>
# <file> — the GraphQL request as raw JSON (--input, section 12):
# {"query":"mutation($input: CreateNoteInput!){createNote(input:$input){note{id}errors}}",
#  "variables":{"input":{"discussionId":"gid://gitlab/Discussion/<discussion_id>",
#                        "body":"[ai] <comment text>"}}}
```

The mandatory `[ai] ` prefix (shown with the default prefix; the
configured one per section 9) applies to GraphQL replies as to every other
comment.

Thread state: in the discussions listing a discussion-level `resolved` field
may be absent (observed on 18.7.7-ee — instance-dependent); a thread counts
as resolved exactly when every non-system note in it has `resolved: true`.
The MR-level merge-readiness signal for open threads is
`blocking_discussions_resolved` of the single-MR endpoint (section 10), not
a discussion-level flag.

## 20. Issues


Brief working set. The repository-context and iid rules (sections 1 and 6)
apply to issues exactly as to MRs.

```bash
glab issue list --assignee=@me      # my assigned issues; likewise --author=<username>
glab issue list -F ids              # machine-friendly: one iid per line (also: -F urls)
glab issue view <iid>               # issue card (--comments); a full issue URL also works
glab issue create -t "<title>" -d "<description>" -y   # non-interactive create
glab issue note <iid> -m "[ai] <comment text>"           # comment — prefix mandatory (section 9)
glab issue close <iid>              # also: glab issue reopen <iid>
```

The global `issues` endpoint needs `&scope=all` for role-filtered queries,
same as `merge_requests` (section 5).

## 21. CI/CD pipelines and jobs

All commands take the repository context (`-R`, section 1). `glab ci` has the
aliases `glab pipe` / `glab pipeline`.

```bash
glab ci status                  # pipeline of the current branch (-b <branch>; -c compact; -l live)
glab ci list --status=failed    # pipelines; statuses: running|pending|success|failed|canceled|...
glab ci trace <job-id>          # live log of a job — by numeric job id or job name
glab ci retry <job-id>          # retry a job — by numeric job id or job name
```

Note: `trace` and `retry` address jobs, not pipelines; without an argument
they prompt to select a job interactively — pass the job id or name
explicitly in non-interactive runs (section 3).

## 22. gitlab-tools: the bundled mechanical toolkit

The skill ships a bash+python3 toolkit in `tools/` next to this SKILL.md.
The scripts wrap `glab api` and mechanically enforce the protocols and
traps of sections 5, 10, 11, 17, 18, and 19 — the scope=all rule, local
anchor validation, the configured comment prefix, verification by follow-up
GET, the GraphQL reply fallback, pagination. Full contracts (arguments,
exit codes, guards, stdout sections) are documented in `tools/README.md`;
the gitlab-tools topic of SPEC.md is normative for this section. Exit codes:
0 success, 1 failure, 2 usage error; output is plain text.

One line per script:

- `mr-auth-probe.sh [host]` — live token-health probe (the mechanical form of the section 15 rule): exactly one GET `user` through the shared error-detection machinery; exit 0 prints exactly `ok <username>`, exit 1 reports the host + HTTP code (or network error) on stderr, exit 2 usage. GET-only, no clone, no state, no token values read or echoed.
- `mr-list.sh [--role reviewer|author|assignee] [--state opened|closed|merged|all] [--draft|--no-draft] [--json] [--project <group/proj>] [--max N] [--repo <dir>]` — global MR list by role for the current user across all accessible projects (default `--role reviewer --state opened`, the "what awaits my review" scenario); the mandatory `scope=all` (section 5) and full pagination are built in; one block per MR (`references.full`, DRAFT mark, title, author, updated_at date, web_url, source/target branches), newest update first; `--json` prints the normalized array; GET-only, an empty result is a success.
- `mr-updates.sh <project> <iid> [--since <iso8601|sha>] [--state <file>] [--fetch] [--repo <dir>]` — MR state, new commits (diffstat inside a clone), new notes, thread status changes, and a `== merge status ==` section (detailed/legacy status transitions, the `blocking_discussions_resolved` flip, approvals +username/-username diffs) printed only when the delta changes them; with `--state` only the delta since the marker (additive schema, a masked sha is never stored as a cutoff).
- `mr-has-updates.sh <project> <iid> [--state <file>] [--no-ci] [--repo <dir>]` — fast boolean "any updates on this MR?" check for timers (read-only, GET-only, no clone needed): compares commits, notes (system ones included), thread resolve flips and new discussions, MR state/draft, title/description hashes, reviewers/approvals, merge status (incl. `blocking_discussions_resolved`), and the head-sha CI pipeline against a has-updates marker; `--no-ci` excludes the CI category (no pipelines GET, no CI line, the marker keeps its saved pipeline values — the delta is not lost); exit 0 — updates present (one summary line per category on stdout), 1 — none (the first run records a baseline and prints `baseline recorded (...)`), 2 — usage error, 3 — API failure (the marker is left untouched so the delta is not lost).
- `mr-card.sh <project> <iid> [--json] [--full] [--repo <dir>]` — the MR card: title + DRAFT mark, state, branches, author/reviewers/approvals (`approved_by` usernames, `approved`, `approvals_required` — the approvals endpoint), `blocking_discussions_resolved`, merge statuses, the recovered head sha with its provenance, `changes_count`, the truncated description, and the local diffstat `<merge-base>..<head>`; `--json` prints one normalized object; without a clone the card still prints, without the diffstat, with a NOTE on stderr.
- `mr-diff.sh <project> <iid> [--files|--stat|--hunks|--conflicts] [--repo <dir>]` — the true local MR diff, always `<merge-base>..<head>` (never `diff_refs.start_sha`, never a two-dot against the moved target); `--files`/`--stat`/`--hunks` (the shared hunk-range construction the anchor validators use), `--conflicts` — a write-free local merge simulation: exit 0 clean / 1 conflicts (paths on stdout) / 3 could not be performed; requires a clone; degrades loudly to the local source-branch tip when the clone lacks the MR head.
- `mr-threads.sh <project> <iid> [--open|--all] [--ai-only] [--no-system] [--max-chars N] [--full] [--repo <dir>]` — readable thread dump: discussion id, resolved state, anchor, authors, bodies; `--no-system` drops CI-bot system notes (system-only threads are not printed); GET-only.
- `mr-comment.sh <project> <iid> <path> <line> <body-or-@file> [--old-side] [--no-prefix] [--force] [--dry-run] [--repo <dir>]` — one line-anchored comment: sha recovery, local hunk validation (refuses outside hunks with the valid ranges; `--force` posts unpositioned with `path:line` prepended), POST verified by GET.
- `mr-draft-review.sh <project> <iid> <comments.json> [--publish] [--dry-run] [--no-prefix] [--repo <dir>] [--ignore-stray]` — batch review via draft notes: validation table, stray-draft refusal (pre-existing pending drafts abort the run), drafts verified by GET; `--publish` publishes only this run's drafts one by one, with `bulk_publish` as an explicitly warned fallback; reply items post immediately via `mr-reply.sh`.
- `mr-reply.sh <project> <iid> <discussion_id> <body-or-@file> [--no-prefix] [--dry-run] [--repo <dir>]` — reply into an existing thread: REST first, verified to sit inside the discussion by GET, GraphQL `createNote` fallback on 404 or the silent orphan, verified again.
- `mr-resolve.sh <project> <iid> <discussion_id> [--unresolve] [--dry-run] [--repo <dir>]` — resolve/unresolve exactly ONE thread: guards decided by GET (existence, resolvable notes, idempotent state), state verified by GET after the PUT; no batch mode by design.
- `mr-verify-report.sh <project> <iid> <verdicts.json> [--emit <out.json>] [--post] [--yes] [--repo <dir>]` — verdict plan (acknowledge/contest located by a thread hint, `new` anchored items): the full plan is printed before any write; `--emit` writes a batch for `mr-draft-review.sh`; posting requires `--yes`; it never publishes.
- `mr-verify-posted.sh <project> <iid> [--expect <expected.json>] [--drafts] [--max-note-id] [--ai-only] [--max-chars N] [--full] [--repo <dir>]` — READ-ONLY post-publish verification (use it instead of ad-hoc inline scripts): pending-draft count (`--drafts`), highest note id on the MR (`--max-note-id`, the follow-up baseline), and `--expect` matching of posted bodies (the comments.json schema of `mr-draft-review.sh`; byte-exact FINAL bodies; anchored items also require `new_path`/`new_line` — or `old_path`/`old_line` — equality; reply items require the body inside the given discussion; `@file` bodies; `--ai-only` narrows to notes with the configured comment prefix); verdicts `ok`/`anchor-mismatch`/`body-mismatch`/`not-found` with discussion id, note id, anchor, and resolved flag; exit 1 when any expected item is not ok, 2 usage error.

When to prefer the tools: always — the Tool-first table at the top of
this skill (before section 1) is the routing rule. Any operation in that
table goes through the bundled script, never through a hand-built glab
call; raw glab stays the path only for operations outside the table
(MR/issue/CI operations, project-scoped lists, descriptions, merges) and
for understanding the underlying API semantics: the tools automate the
protocols above, they do not replace the knowledge behind them. The
open-thread picture — the counter and the list of open (unresolved)
threads, each with its resolved state computed over its resolvable notes,
not just a dump of bodies — is `mr-threads.sh --open`: the trailing count
line is the open-thread counter, and `--ai-only` narrows the dump to
threads carrying the configured comment prefix.

Configuration: optional `tools/config.sh` fills site defaults only when the
environment has not set the variable — precedence
`environment > config.sh > built-in defaults`: `GITLAB_HOST` (instance host
of every call), `GITLAB_DEFAULT_PROJECT` (the `<project>` positional may be
omitted), `GITLAB_REPO` (clone for sha recovery, hunk building, the MR card
diffstat, and the local MR diff; default: the clone containing the current
directory), `GITLAB_COMMENT_PREFIX` (the configured comment prefix checked
on every write and used by the `--ai-only` filters; default
`[ai] ` — the marker text may be prescribed per host/repository by
its owner), `GITLAB_TOOLS_STATE_DIR` (default `<tools>/.state`, created on
demand). Every script accepts the optional `--repo <dir>` flag with
identical semantics — it overrides `GITLAB_REPO` for the invocation
(flag > environment > `config.sh` > built-in default), a nonexistent
directory is a usage error (exit 2), and scripts that make no clone use of
the value accept it for interface uniformity; the usage text of every
script taking `--repo` carries the hint
`clone is configured via GITLAB_REPO env or config.sh`. The toolkit is
location-independent — it resolves its library, config, and state directory
relative to its own location. Anchored writes need a git clone of the
project (masked shas and collapsed `/diffs` are worked around locally);
without one, `mr-comment.sh` degrades to an unpositioned post and says so;
`mr-diff.sh` requires a clone outright.

Instance-dependent (observed live on GitLab 18.8.x-ee): `diff_refs` may
arrive masked (`__SECRET_N__` placeholders) while the top-level `sha`
field of the single-MR response and the `/commits` endpoint still return
real shas (the masking is flaky per request — the same endpoint answers
masked and unmasked on different calls). Trust the head-sha recovery
ladder of `mr-card.sh` — its provenance line names the source that won
(e.g. "commits endpoint") — and take conflict verdicts from
`mr-diff.sh --conflicts` or a local `git merge-tree --write-tree`, not
from the masked fields.

Timer/watcher recipe (the has-updates gate). To watch an MR on a schedule,
make `mr-has-updates.sh` the gate command of any scheduler that fires when
its gate command exits `0`:

```bash
# the watcher owns its marker file and pins the clone for the woken agent
# (the gate command itself is clone-free and GET-only)
GITLAB_REPO=<clone-dir> mr-has-updates.sh <group/project> <iid> \
  --state <marker-file> [--no-ci]
# exit 0: updates present - the fire happens; the stdout summary lines are
#         the wakeup message payload
# exit 1: no updates - the fire is skipped (the first tick records the
#         baseline, prints "baseline recorded (...)", and exits 1 - the
#         arming step, not an error)
# exit 3: API/network failure - the fire is skipped WITHOUT an alert; the
#         marker is untouched, so the delta is never lost; retry next tick
```

Full lifecycle: the first tick arms the watcher (baseline recorded, exit 1,
no fire); every later tick fires only on a real delta, and the summary
lines (commits, notes, threads, MR state, title/description,
reviewers/approvals, merge status, CI) are attached to the wakeup so the
woken agent knows what changed. Set `GITLAB_REPO` in the gate command to
the clone the woken agent will use for diff/anchor work. A watcher that
does not care about CI events passes `--no-ci`: the CI pipeline is not
requested, no CI line appears, and the marker keeps its saved pipeline
values so a CI change during the window is caught by the next full check.

Watcher-round recipe (the step → tool map). One fire of the gate above is
one review round; each step of the round maps to exactly one tool
(contracts in `tools/README.md`; the comment prefix of section 9 applies
to every posted body):

- gate/wakeup — `mr-has-updates.sh` (the recipe above; its stdout summary
  lines name the changed categories);
- the MR card and the approve-state inputs (state, draft, reviewers,
  approvals, merge statuses, the head) — `mr-card.sh`;
- threads — `mr-threads.sh --all --no-system` (the resume read; own
  threads via `--ai-only`);
- conflicts — `mr-diff.sh --conflicts` (the local `git merge-tree`
  verdict, never the API merge status alone);
- new findings — `mr-draft-review.sh` (a batch, anchors pre-validated) or
  `mr-comment.sh` (single);
- replies into threads (confirmations, agreements, objections) —
  `mr-reply.sh`;
- resolve — `mr-resolve.sh`, exactly one thread per call, only after the
  verdict is posted inside the thread;
- post-verification of what actually landed — `mr-verify-posted.sh`
  (`--expect` / `--drafts` / `--max-note-id`).

Raw glab stays the path for the round operations outside the map —
`glab mr approve`/`glab mr unapprove` (the approve policy itself is the
caller's, e.g. the approve invariant of the glab-autoreview skill), CI
status and retries (section 21), and everything else the toolkit does not
cover.

Push gate for confirming outgoing review threads (reviewer-side triage,
the mirror of the author-side resolve discipline of section 18): the
confirming comment and the resolve of one of your own threads are posted
only after the author has pushed the fix into the MR branch — a new
commit/head sha has appeared since the thread was opened (the card's head
with its provenance; the gate's `commits:` line). Until the push lands
the thread stays open; a short "waiting for the push" reply may mark it,
without resolving — without a push there is no code change to verify,
only the comment being marked fixed.

End-to-end walkthrough: reviewing an MR with the toolkit — the typical
reviewer loop as one sequence (contracts live in `tools/README.md` and the
sections referenced below; the bodies of all posted comments carry the
configured prefix, section 9):

```bash
mr-auth-probe.sh <host>                                     # 1. token health: ok <username> or a host+code diagnostic
mr-card.sh <group/project> <iid> --repo <clone-dir>         # 2. the MR card: state, approvals, merge statuses, head, diffstat
mr-diff.sh <group/project> <iid> --files --repo <clone-dir> # 3. survey the change (likewise --stat / the default full diff)
mr-threads.sh <group/project> <iid> --all --no-system       # 4. read the review threads without the CI-bot noise
mr-draft-review.sh <group/project> <iid> <comments.json> --repo <clone-dir> \
                                                            # 5. create the drafts + verify by GET (private; rerun with
                                                            #    --publish to publish ONLY this run's drafts, one by one)
mr-verify-posted.sh <group/project> <iid> --expect <expected.json> --drafts --max-note-id \
                                                            # 6. read-only verification of what actually landed
mr-reply.sh <group/project> <iid> <discussion_id> "<comment text>" && \
  mr-resolve.sh <group/project> <iid> <discussion_id>       # 7. answer the author's pushback, resolve only after it
mr-has-updates.sh <group/project> <iid> --state <marker-file> [--no-ci] \
                                                            # 8. poll for the author's next push (the watcher gate above)
```
