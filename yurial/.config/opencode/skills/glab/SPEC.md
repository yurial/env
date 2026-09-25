# glab Skill Specification

Status: stable
Spec source of truth for: the `glab` skill — the SKILL.md guide «glab: GitLab CLI — typical workflows and traps» (working with GitLab from the command line via glab, the GitLab CLI)
A divergence between the skill and this specification is either a spec gap (the spec is fixed) or a skill bug (SKILL.md is fixed); it must not be tolerated silently.
Reference: glab

## Overview

The `glab` skill governs how an agent works with GitLab from the command line via glab, the GitLab CLI. The skill is instructions to the agent: practical rules for repository context, authorization, non-interactive usage, role-based MR lists, drafts, typical MR operations, machine-generated comments, MR descriptions and review comments (the description/commit-message language pair, reading line-anchored discussions, posting line-level comments, batch posting with line-anchor validation against diff hunks and diff_refs freshness), replying in discussions with the GraphQL fallback and thread resolution state, the REST API via `glab api` (fields, request bodies, URL-encoded paths, pagination) and GraphQL via `glab api graphql`, HTTP error disambiguation, multi-host auth diagnostics, git-over-HTTP(S) authentication independent from API tokens, reading review comments via the discussions endpoint, issues, and CI/CD pipelines and jobs. The skill carries no scripts or mechanical checks: glab itself is the tool being operated. Every command, flag, and behavioral claim in the skill must be verified against the help output of the installed glab version — `glab help`, `glab <command> --help` — or against live behavior on an authenticated host; the skill states the version it was verified against (GLAB-S-17, GLAB-S-18). Behavior observed only on a specific instance is marked instance-dependent in the skill (GLAB-S-20). Traps — conditions that fail silently or mislead (scope=all, iid vs id, flag collisions, HTTP error shapes, exit code 0 on HTTP errors, line anchors on context lines, silently dropped discussion replies) — are highlighted as critical in the skill (GLAB-S-22).

## Activation triggers

The skill activates when working with GitLab from the command line via glab: listing, viewing, creating, checking out, approving, and merging merge requests; writing MR descriptions and reading and posting MR review comments; batch posting of review comments (line-anchor validation against diff hunks, diff_refs freshness, canary-first protocol); discussion replies via the GraphQL fallback; thread resolution state (`blocking_discussions_resolved`); filtering MRs by role (reviewer, assignee, author); draft/WIP MRs; managing issues; checking CI/CD pipelines and jobs; calling the GitLab REST API via `glab api`; non-interactive glab usage and interpreting glab errors; diagnosing multi-host authentication (stale stored tokens, `--hostname` scoping); git-over-HTTP(S) push/fetch authentication as distinct from API-token authentication; reading MR review comments via the discussions endpoint. The canonical trigger text is the frontmatter `description` (Interface); the activation scope grows together with Topic coverage (GLAB-S-23). The skill does not apply to plain git workflows, other forges, or GitLab web UI operations (Scope, Out).

## Scope

In:
- repository context rules and the `-R` flag (GLAB-S-01);
- authorization: `glab auth status`, token login, token/host environment variables (GLAB-S-02);
- non-interactive usage and machine-readable output (GLAB-S-12, GLAB-S-13);
- role-based MR lists, project- and group-scoped and global (GLAB-S-03);
- the scope=all trap (GLAB-S-04);
- iid vs global id (GLAB-S-05);
- drafts/WIP MRs (GLAB-S-06);
- typical MR operations (GLAB-S-07);
- deleting the source branch on merge — the flag is set at MR creation, with the merge-time equivalent as a fallback (GLAB-S-34);
- multi-host auth diagnostics and the stale-token trap (GLAB-S-35);
- git-over-HTTP(S) authentication being independent of the API token, with SSH as the reliable path (GLAB-S-36);
- reading MR review comments via the discussions endpoint rather than the flat notes list (GLAB-S-37);
- machine-generated comments with the mandatory `AI generated:` prefix (GLAB-S-08);
- MR descriptions and review comments: description/commit-message languages, reading discussions with line context, line-anchored comments (GLAB-S-31, GLAB-S-32, GLAB-S-33);
- batch posting of line-anchored review comments: anchor validation against diff hunks, diff_refs freshness, canary-first protocol, failure detection in the response body (GLAB-S-38, GLAB-S-39, GLAB-S-40);
- post-write verification after mass writes and the mass-posting rate caution (GLAB-S-45, GLAB-S-46);
- `glab api` scoping: no `-R` flag — the project rides in the URL, the host via `--hostname` (GLAB-S-41);
- discussion replies via the GraphQL `createNote` fallback and thread resolution state (GLAB-S-42, GLAB-S-43);
- pagination of the discussions listing (GLAB-S-44);
- `glab api` request construction: fields, bodies, URL-encoded paths (GLAB-S-10, GLAB-S-11);
- API pagination (GLAB-S-09);
- HTTP error disambiguation 401/403/404 (GLAB-S-14);
- issues coverage (GLAB-S-15);
- CI/CD pipelines and jobs coverage (GLAB-S-16).

Out (non-goals):
- plain git workflows (branches, commits, pushing) — git, not glab;
- other forges (GitHub, Bitbucket) and their CLIs;
- GitLab web UI operations;
- authoring `.gitlab-ci.yml` — the skill observes and retries pipelines via glab, it does not write CI configs;
- the full GitLab API surface — endpoints appear only as needed by the covered workflows; the skill teaches operating glab, not the entire API;
- installation and updating of glab itself;
- secret management — the skill never stores token values; tokens arrive via stdin or environment variables and appear in examples only as placeholders.

## Definitions

| Term | Definition |
|---|---|
| repository context | the git repository of the current working directory; `glab mr`, `glab issue`, `glab ci` commands derive host and project from its `git remote` (usually `origin`) (GLAB-S-01). |
| global endpoint | a top-level REST endpoint (`merge_requests`, `issues`) queried via `glab api` across all accessible projects; contrasted with project-scoped commands (GLAB-S-03, GLAB-S-04). |
| iid | the per-project number of an MR or issue, used in URLs and glab arguments; distinct from the globally unique `id` (GLAB-S-05). |
| draft MR | an MR marked not ready: `Draft:`/`WIP:` title prefix, API field `work_in_progress: true` (GLAB-S-06). |
| URL-encoded project path | the `<group>%2F<project>` form of a project path in REST URLs; a raw `/` splits URL segments and breaks route resolution (GLAB-S-11). |
| placeholder | an angle-bracket identifier (`<group/project>`, `<username>`, `<iid>`, ...) standing for a real value; real identifiers must not appear in the skill (GLAB-S-19). |
| machine-readable output | output intended for programmatic parsing: raw JSON from `glab api`, the `ids`/`urls` formats of `glab issue list` (GLAB-S-13). |
| line-anchored comment | a discussion note attached to specific diff lines via a `position` object (`position_type` `"text"`; `new_line`/`new_path` for the new side, `old_line`/`old_path` for the old side; `line_range` spans a block of lines); contrasted with a top-level MR note, which has no `position` (GLAB-S-32, GLAB-S-33). |
| trap | a condition that fails silently or returns misleading data (scope=all, iid vs id, flag collisions, HTTP 404 shapes, exit code 0 on HTTP errors); traps are highlighted in the skill (GLAB-S-22). |
| discussion thread | a `discussions`-endpoint object grouping the notes of one review conversation; its notes carry `position` for diff-anchored comments and `system: true` marks service notes (GLAB-S-37). |
| hunk range | the new-side line span of one diff hunk of a file (the `@@ +<start>,<count> @@` header); a line-anchored position is accepted only on lines inside hunk ranges — context lines are rejected with HTTP 400 (GLAB-S-38). |
| outdated note | a diff-anchored note created against a superseded diff version; GitLab marks it outdated when `diff_refs` move after the note was created (GLAB-S-39). |

## Interface (skill components)

### Frontmatter (canonical, verbatim)

```yaml
---
name: glab
description: Use when working with GitLab from the command line via glab (GitLab CLI): listing, viewing, creating, checking out, approving, and merging merge requests (MRs), writing MR descriptions (Russian description, English commit message), reading and posting MR comments (line-anchored comments), batch posting of review comments, line-anchor validation against diff hunks, discussion replies via GraphQL fallback, thread resolution state, filtering MRs by role (reviewer, assignee, author), draft/WIP MRs, managing issues, checking CI/CD pipelines and jobs, and calling the GitLab REST API via `glab api` (fields, bodies, pagination, URL-encoded paths). Covers glab-specific traps: repository context, scope=all, iid vs id, pagination, flag collisions, HTTP 401/403/404 disambiguation, non-interactive usage. Use ONLY for glab/GitLab CLI operations, not for plain git workflows or other forges.
---
```

Norms of form:
- The frontmatter contains `name` and `description`; their values are canonical verbatim as in the block above.
- The `description` enumerates the trigger scope and must grow with the skill's scope: any Topic-coverage requirement naming a new user-facing activity (issues, CI, error disambiguation, non-interactive usage, ...) is reflected in `description` (GLAB-S-23).
- The `description` ends with the boundary sentence «Use ONLY for glab/GitLab CLI operations, not for plain git workflows or other forges.»
- The document title of the skill: «glab: GitLab CLI — typical workflows and traps».

### SKILL.md document structure (mapping to requirements)

```
# glab: GitLab CLI — typical workflows and traps
<intro: purpose, coverage, verified glab version, placeholder notice>
## 1. Repository context                                   — GLAB-S-01
## 2. Authorization                                        — GLAB-S-02
## 3. Non-interactive usage and machine-readable output    — GLAB-S-12, GLAB-S-13
## 4. MR lists by role                                     — GLAB-S-03
## 5. The scope=all trap (critical)                        — GLAB-S-04
## 6. iid vs the global number                             — GLAB-S-05
## 7. Drafts                                               — GLAB-S-06
## 8. Typical MR operations                                — GLAB-S-07, GLAB-S-34
## 9. Leaving comments — mandatory `AI generated:` prefix  — GLAB-S-08
## 10. MR descriptions and review comments                 — GLAB-S-31, GLAB-S-32, GLAB-S-33, GLAB-S-38..GLAB-S-40, GLAB-S-45, GLAB-S-46
## 11. glab api: fields, bodies, and URL-encoded paths     — GLAB-S-10, GLAB-S-11, GLAB-S-41
## 12. API pagination                                      — GLAB-S-09
## 13. HTTP errors: 401 vs 403 vs 404                      — GLAB-S-14
## 14. Multi-host auth: auth status can mislead (trap)     — GLAB-S-35
## 15. Git-over-HTTP(S) auth: tokens do not always work    — GLAB-S-36
## 16. Reading MR review comments: discussions endpoint    — GLAB-S-37, GLAB-S-44
## 17. Replying in discussions and thread state (trap)     — GLAB-S-42, GLAB-S-43
## 18. Issues                                              — GLAB-S-15
## 19. CI/CD pipelines and jobs                            — GLAB-S-16
```

The section order is canonical: context and authorization come before workflows; traps follow their subject matter; the MR description/review-comment workflow follows the comment-prefix rule; API mechanics precede error interpretation; issues and CI close the document.

### Named components

- The `AI generated:` prefix rule — the mandatory marker on every comment posted via glab (GLAB-S-08; invariant GLAB-S-26).
- The scope=all rule — the mandatory `&scope=all` on global role-filtered MR/issue queries plus the empty-result checklist (GLAB-S-04; invariant GLAB-S-27).
- The iid≠id rule — per-project numbers, context/`-R` discipline for numeric references, the 404-wrong-project heuristic (GLAB-S-05; invariant GLAB-S-28).
- The MR language and line-anchoring rules — the MR description in Russian (problem + solution) with the MR commit message in English semantically mirroring it; reading comments at their anchored lines; line-level comments preferred over top-level notes (GLAB-S-31..GLAB-S-33).
- The batch posting protocol — anchors validated against hunk ranges, fresh `diff_refs`, a canary comment first, failures detected in the response body, with the no-position retry fallback (GLAB-S-38..GLAB-S-40).
- The accuracy gate — no flag or command example reaches the skill without verification against the installed glab (GLAB-S-17..GLAB-S-20; invariants GLAB-S-29, GLAB-S-30).

## Requirements

### Topic coverage

- GLAB-S-01. Repository context. The skill documents: `glab mr`, `glab issue`, `glab ci` commands require a git repository — host and project derive from `git remote` (usually `origin`); outside a repository they fail with `fatal: not a git repository ...` and exit code 1 — a context error, not an empty result; the `-R <group/project>` flag selects another project (formats `<group>/<project>`, nested `<group>/<subgroup>/<project>`, per glab help also a full URL or git URL) and exists on all `glab mr`, `glab issue`, `glab ci` commands; `glab api` and `glab auth status` work outside repositories — inside a repository its authenticated host is used, otherwise the default host (`--hostname` overrides, for `glab api`).
- GLAB-S-02. Authorization. The skill documents: `glab auth status` (works from any directory) as the pre-flight check; `✓ Logged in ... as <username>` marks a valid token, `x`/`!` lines mark token problems, and with a bad token API calls return 401; non-interactive login `glab auth login --hostname <host> --stdin` (token on standard input; `-t/--token` exists but puts the secret in the command line); minimum token scopes `api`, `write_repository`; environment variables `GITLAB_TOKEN` (token for API requests, overrides stored credentials) and `GITLAB_HOST`/`GL_HOST` (self-managed host URL).
- GLAB-S-03. MR lists by role. The skill documents both levels. Inside a repository/group: `glab mr list --reviewer=@me|--author=@me|--assignee=@me` (`@me` is the current user; also `-g <group>`); default page of 30 records, `-P`/`-p` control per-page/page. Across all accessible projects: the global endpoint `merge_requests?reviewer_username=<username>&state=opened&scope=all` (likewise `author_username`, `assignee_username`); the response is a JSON array parsed with jq or python; useful fields: `iid`, `title`, `state`, `references.full`, `web_url`, `work_in_progress`, `author`.
- GLAB-S-04. The scope=all trap (critical). The skill documents: without `scope`, the global `merge_requests` endpoint defaults to `created_by_me` — a role-filtered query silently returns only MRs created by the caller (often an empty list) instead of all matching MRs; any global MR search by `reviewer_username`/`author_username`/`assignee_username` must carry `&scope=all`; the global `issues` endpoint carries the same documented default scope and needs `&scope=all` as well; on an empty result, before reporting "no MRs", check in order: `scope=all` present; `state` correct (`opened` excludes `merged`/`closed`); the right project/group searched.
- GLAB-S-05. iid vs the global number. The skill documents: `iid` is the per-project MR number used in the URL and in `glab mr <subcommand> <iid>`; only `id` is globally unique; the same `iid` in different projects means different MRs; `404 Not Found` from `glab mr view <N>` more often means "wrong project" (host/project taken from the current repository) than "the MR does not exist"; numeric references require working from that project's repository or `-R <group/project>`.
- GLAB-S-06. Drafts. The skill documents: a draft MR has a `Draft:`/`WIP:` title prefix and the API field `work_in_progress: true`; filtering via `glab mr list -d/--draft` or the API parameter `wip=yes`/`wip=no`; the draft status is always shown in reports to the user (a draft is usually not ready for review/merge).
- GLAB-S-07. Typical MR operations. The skill documents the working set — `view`, `diff`, `checkout`, `create --fill`, `approve`, `merge` (useful flags `-y`, `--squash`, `-d`), `close`, `reopen` — and that an MR is addressed by `<iid>`, by its source branch name, or (without an argument) by the MR of the current branch; all commands accept `-R`.
- GLAB-S-08. Comments — mandatory `AI generated:` prefix. The skill documents: every comment posted via glab — a note on an MR, a comment on an issue, a reply in a discussion — must begin with the prefix `AI generated:` followed by a space and the comment text; in a multi-line comment the first line still begins with the prefix; commands: `glab mr note <iid> -m "AI generated: <comment text>"`, `glab issue note <iid> -m "AI generated: <comment text>"`, and a discussion reply via the API with a `body` field carrying the prefix.
- GLAB-S-09. API pagination. The skill documents: `glab api` returns a single page (20 records by default); complete lists require `&per_page=100` plus walking `&page=2`, `&page=3`, ... — or the `--paginate` flag, which fetches all pages sequentially; a missing "tail" of a large list is the typical symptom of forgotten pagination.
- GLAB-S-10. API fields and bodies. The skill documents, per glab help: `-f/--raw-field key=value` adds a string parameter (no type conversion); `-F/--field key=value` adds a typed parameter — literal `true`/`false`/`null` and integers convert to JSON types, a value starting with `@` is read from that file and `-` from standard input (the standard way to pass multiline text); any field switches the default method from GET to POST, `-X/--method` overrides; a raw request body is passed via `--input <file>` (`-` = standard input), and in this mode `--field`/`--raw-field` flags are serialized into URL query parameters; `-H/--header` adds HTTP headers.
- GLAB-S-11. URL-encoded project paths. The skill documents: inside a repository the `:fullpath` placeholder is replaced with the current project; outside it (or for another project) the project path in REST URLs must be URL-encoded — `projects/<group>%2F<project>/...`; a raw `/` splits the path and yields a generic `{"error":"404 Not Found"}` even when the project exists, while the encoded form for a missing project answers `{"message":"404 Project Not Found"}` — the two 404 body shapes distinguish a broken path from a missing project.
- GLAB-S-12. Non-interactive usage. The skill documents: `NO_PROMPT=1` disables interactive prompts; mutating commands support `-y/--yes` to skip the submission confirmation (verified for `mr create`, `mr merge`, `issue create`); explicit flags are preferred over prompts (`--no-editor` avoids opening an editor); in scripts and agent runs long flag names are mandatory because short flags collide across subcommands — `-F` is `--field` in `glab api` but `--output-format` in `glab issue list`, `-f` is `--raw-field` in `glab api` but `--fill` in `glab mr create`; `NO_COLOR` removes ANSI escape sequences from parsed output; `GITLAB_TOKEN`/`GITLAB_HOST` (GLAB-S-02) supply token and host non-interactively.
- GLAB-S-13. Machine-readable output. The skill documents: `glab api` is the reliable JSON source (raw JSON to standard output); `glab mr list` has no JSON output format in glab 1.36.0 — for JSON, query the API instead; `glab issue list -F ids`/`-F urls` print one identifier/one web URL per line; `glab api` exits 0 even on HTTP errors — 401/404, and 400 on POST requests (GLAB-S-40) — the error is visible in the stderr line `glab: <message> (HTTP <code>)` and in the response body, so parsing must check those, not the exit code; `glab mr`/`glab issue`/`glab ci` commands exit 1 on context errors (GLAB-S-01).
- GLAB-S-14. HTTP error disambiguation. The skill documents: 401 — token missing, invalid, or expired for that host → check `glab auth status`, re-login; 403 — the token is valid but the account lacks permission for the action (GitLab REST semantics); 404 — most often a wrong project (repository context, missing `-R`, unencoded path per GLAB-S-11), only then a nonexistent resource — consistent with the iid≠id rule (GLAB-S-05); and that `glab api` exits 0 on all of these (GLAB-S-13).
- GLAB-S-15. Issues. The skill documents the verified subset: `glab issue list` — filters `--assignee=@me`, `--author=<username>`, `-A`, `-g <group>`, labels, search; machine-friendly formats `-F ids`/`-F urls`; `glab issue view <iid>` (also accepts a full issue URL); non-interactive creation `glab issue create -t "<title>" -d "<description>" -y`; `glab issue note` with the mandatory prefix (GLAB-S-08); `glab issue close`/`glab issue reopen`. iid semantics and the repository-context rules apply to issues exactly as to MRs (GLAB-S-01, GLAB-S-05); the global `issues` endpoint requires `scope=all` (GLAB-S-04).
- GLAB-S-16. CI/CD pipelines and jobs. The skill documents the verified subset: `glab ci status` — pipeline of the current branch, flags `-b <branch>`, `-c` (compact), `-l` (live); `glab ci list` — `--status=<status>` filter (running|pending|success|failed|canceled|skipped|...); `glab ci trace <job-id>|<job-name>` — live job log, flags `-b`, `-p <pipeline-id>`; `glab ci retry <job-id>|<job-name>` — retry operates at the job level, not the pipeline level; the aliases `glab pipe`/`glab pipeline`; that without an argument `trace`/`retry` prompt interactively to select a job; repository context and `-R` apply (GLAB-S-01).
- GLAB-S-31. MR description and commit-message languages. The skill documents: the MR description is written in Russian and describes both the problem being solved and the way this problem is solved; the MR commit message is written in English and semantically mirrors the Russian description. The description is passed explicitly — `glab mr create -t "<title>" -d "<description>"` — and corrected later with `glab mr update <iid> -d "<description>"`; the `--fill` caveat: `--fill` takes the title/description from commit info (English commit messages), which does not satisfy the required language split, so it is not used to produce the description; the English commit message is set at merge time — `glab mr merge <iid> -m "<message>"` (with `-s/--squash` — `--squash-message "<message>"`).
- GLAB-S-32. Reading MR comments with line context. The skill documents: when reading MR discussions/comments, always resolve the line numbers a comment is anchored to and read the code at those lines (`glab mr diff <iid>` or the checked-out MR branch) before replying or acting on the comment; the quick view is `glab mr view <iid> --comments`, the machine-readable form is `glab api "projects/:fullpath/merge_requests/<iid>/discussions"` (pagination per GLAB-S-09); a diff-anchored note carries a `position` object — `position_type` `"text"`, `new_line`/`new_path` for the new side, `old_line`/`old_path` for the old side, `line_range` when the note spans a block of lines — while a note without `position` is a top-level MR note.
- GLAB-S-33. Line-level comments preferred. The skill documents: a comment about specific code is posted as a note anchored to that line/block — a line-anchored comment (Definitions) — not as a top-level note; `glab mr note` posts only top-level notes (in glab 1.36.0 it has no line anchoring), so a line-anchored comment is created via the REST API: `POST projects/:id/merge_requests/<iid>/discussions` with a `body` and a `position` — `base_sha`/`start_sha`/`head_sha` taken from the single-MR endpoint's `diff_refs` (the list endpoint returns `diff_refs: null`), `position_type` `"text"`, `new_path`+`new_line` (or `old_path`+`old_line`) — passed as a JSON body via `--input` (GLAB-S-10); the mandatory `AI generated:` prefix (GLAB-S-08, GLAB-S-26) applies to these comments as to every other.
- GLAB-S-34. Delete source branch on merge. The skill documents: an MR is created with the «delete source branch on merge» setting — `glab mr create --remove-source-branch`; the flag is set at creation so that the branch deletion is carried by the MR and happens however the MR is later merged; short-flag collision (GLAB-S-12): in `mr create` `-d` is `--description`, so only the long form sets the branch flag, while in `mr merge` `-d` is `--remove-source-branch`; the merge-time equivalent — `glab mr merge <iid> -d`/`--remove-source-branch` — is documented as the fallback for an MR created without the flag; both flags verified against glab 1.36.0 help.
- GLAB-S-35. Multi-host auth diagnostics (trap). The skill documents: on a machine with several configured hosts `glab auth status` prints a block per host, and a stored token may be present yet stale — a per-host block showing both `Token: ****` and `! Invalid token provided` means API calls to that host return 401; `glab auth status` without `--hostname` may check a different host than the one the API calls use, so diagnosis of a specific host passes `--hostname <host>`; recovery is re-login or a fresh `GITLAB_TOKEN` (GLAB-S-02), and `glab api` still exits 0 on the 401 (GLAB-S-13).
- GLAB-S-36. Git-over-HTTP(S) auth is independent of the API token (trap). The skill documents: `glab` covers the API, while `git push`/`git fetch` over HTTPS authenticate separately and a working API token may be rejected for git-over-HTTP on a self-managed instance (`remote: HTTP Basic: Access denied`); the symptom pair "API works (200), HTTPS push denied" and "SSH push fails with Permission denied (publickey)" is documented; the recovery order is SSH remotes with a loaded agent key (`ssh -T git@<host>` as the check), then a token-as-password HTTPS URL (`https://oauth2:<token>@<host>/...`) only after verifying the instance accepts it, and restoring the remote URL afterwards; a token must not remain embedded in a remote URL (`.git/config` plain text).
- GLAB-S-37. Review comments are read via the discussions endpoint (trap). The skill documents: `GET .../merge_requests/<iid>/notes` returns a flat mixed list of system and user notes without file/line context — the right endpoint for review comments is `GET .../merge_requests/<iid>/discussions`, where each discussion is a thread whose notes carry the text plus, for diff-anchored notes, the `position` object (GLAB-S-32); system notes (`system: true`) are skipped; a note with `position` is line-anchored, without — top-level; replies go into the same thread via `POST .../discussions/<discussion_id>/notes` (GLAB-S-08, GLAB-S-33); the documented workflow is fetch discussions, list non-system notes with their anchored `new_path:new_line`, read the code at those lines (GLAB-S-32), reply per discussion with the mandatory prefix (GLAB-S-26).
- GLAB-S-38. Line-anchor validation against diff hunks (trap). The skill documents: a `position` is accepted only on lines inside diff hunks (added or changed lines); `new_line` on a context (unchanged) line is rejected with HTTP 400 and a body naming an invalid line_code; grep finding the marker in the file does not make the line a valid anchor — before posting, collect the new-side line ranges from the hunk headers (`@@ +<start>,<count> @@`) of `GET .../merge_requests/<iid>/diffs` (paginated per GLAB-S-09) and check every anchor against them; on a position-rejecting 400 the fallback is the same body without `position` — a top-level note with `<path>:<line>` written into the text so the reference is not lost.
- GLAB-S-39. diff_refs freshness. The skill documents: `diff_refs` (`base_sha`/`start_sha`/`head_sha`) change when the author pushes to the source branch or the target branch moves; they are taken from the single-MR endpoint (GLAB-S-33) immediately before posting a batch and are never cached across sessions; a long batch can have its shas rotated mid-run; notes created against a superseded diff version are marked outdated by GitLab (Definitions) — expected behavior, not an error.
- GLAB-S-40. Batch posting protocol. The skill documents, for posting tens of line-anchored comments in one run: post the first comment alone (a canary) and verify the response schema — discussion id, note id, position — before posting the rest; detect failures by the response body (fields `message`/`error`) and the stderr line, never by the exit code — `glab api` exits 0 on HTTP 400 for POST as well (GLAB-S-13); on a 400 naming position/line_code, retry the same body without `position` (GLAB-S-38); save `discussion_id`/`note_id` from every POST response so that the final verification is the set of saved ids, not a full re-fetch of all discussions.
- GLAB-S-41. `glab api` scoping: no `-R` flag. The skill documents: `glab api` has no `-R/--repo` flag (verified against glab 1.36.0 help); the project is always part of the URL — `:fullpath` inside the repository or the URL-encoded path outside it (GLAB-S-11) — and the host is selected with `--hostname <host>`; `-R` exists on `glab mr`, `glab issue`, `glab ci` commands, not on `glab api`.
- GLAB-S-42. Discussion replies via the GraphQL fallback (trap, instance-dependent). The skill documents: the documented REST reply path is `POST .../discussions/<discussion_id>/notes` (GLAB-S-08, GLAB-S-37), but on some instances (observed on GitLab 18.7.7-ee) it answers 404 while the `in_reply_to_discussion_id` parameter of `POST .../notes` is silently ignored — the reply lands as a separate orphan discussion; the working path on such an instance is the GraphQL mutation `createNote` with a `discussionId` of the form `gid://gitlab/Discussion/<discussion_id>`, sent via `glab api graphql` (the `graphql` endpoint is documented in `glab api --help`; fields other than `query`/`operationName` are passed as GraphQL variables, so the object `input` is passed via a raw `--input` body per GLAB-S-10); the mandatory prefix (GLAB-S-08, GLAB-S-26) applies to GraphQL replies; the REST-404 behavior is marked instance-dependent (GLAB-S-20).
- GLAB-S-43. Thread resolution state (instance-dependent). The skill documents: in the discussions listing a discussion-level `resolved` field may be absent (observed on GitLab 18.7.7-ee); a thread counts as resolved exactly when every non-system note in it has `resolved: true`; the MR-level merge-readiness signal for open threads is `blocking_discussions_resolved` of the single-MR endpoint, not a discussion-level flag.
- GLAB-S-44. Discussions listing pagination. The skill documents: `GET .../discussions` is paginated like any list (GLAB-S-09): `per_page` up to 100, and an MR with more than 100 discussions requires walking pages; a comment set silently cut at a round page boundary is forgotten pagination, not the whole review.
- GLAB-S-45. Mass-posting rate caution (instance-dependent). The skill documents: posting tens of comments in rapid succession under one account has — once, cause unconfirmed — transiently affected that account's web UI; the rule is to work in batches, verify via the API, and warn the user before large insertions.
- GLAB-S-46. Post-write verification (instance-dependent). The skill documents: a raw-body POST (`--input`) was once observed answering rc=0 with `{"message":"500 Internal Server Error"}` in the body while the resource had in fact been created; after mass writes, creation is verified by the response id or a targeted GET — trusting neither the exit code (GLAB-S-13) nor the message in the body alone.

### Accuracy

- GLAB-S-17. Every command, flag, and example in SKILL.md must be verified against the help output of the installed glab (`glab help`, `glab <command> --help`) or against live behavior on an authenticated host before being added or kept.
- GLAB-S-18. The skill states the glab version it was verified against (currently 1.36.0) and instructs re-checking flags with `glab <command> --help` when running another version.
- GLAB-S-19. Identifiers in examples are placeholders only — `<group/project>`, `<username>`, `<iid>`, `<discussion_id>`, `<job-id>`, `<job-name>`, `<branch>`, `<host>`, `<title>`, `<description>`, `<message>`, `<comment text>`, `<file>`, `<sha>`, `<path>`, `<n>`; no real hosts, users, projects, or numeric IDs appear in the skill.
- GLAB-S-20. Behavioral claims not verifiable via help or a live check are excluded, or explicitly marked as version/instance-dependent; help output and live checks always take precedence over recollection.

### Structure

- GLAB-S-21. The SKILL.md document follows the canonical skeleton (Interface): numbered top-level sections in the canonical order; the intro states purpose, coverage, the verified glab version, and the placeholder notice.
- GLAB-S-22. Traps are highlighted: the highest-severity traps carry `(critical)` in the section heading; trap rules are imperative and explain both the failure mode and the false conclusion it invites.
- GLAB-S-23. The frontmatter carries `name` + `description` exactly as the canonical block; the `description` enumerates the actual trigger scope, ends with the boundary sentence, and is updated whenever Topic coverage grows.
- GLAB-S-24. Commands are shown in bash code blocks with outcomes as inline comments or adjacent prose; placeholders per GLAB-S-19; one block per workflow, not per flag.

### Style

- GLAB-S-25. The skill is a concise practical guide written in English: imperative rules, minimal prose, each rule immediately actionable; it teaches operating glab, not the GitLab API surface at large.

### Revision invariants

- GLAB-S-26. The `AI generated:` prefix rule (GLAB-S-08) is inviolable: no revision may weaken, scope-limit, or drop it; there are no exceptions for short or one-line comments.
- GLAB-S-27. The scope=all rule (GLAB-S-04) with its empty-result checklist is inviolable.
- GLAB-S-28. The iid≠id rule (GLAB-S-05) with the 404-wrong-project heuristic is inviolable.
- GLAB-S-29. Revision monotonicity: a revision may extend or refine existing content but must not silently weaken or remove any rule present in the previous version; a refinement that corrects a verified inaccuracy (for example, sharpening the scope=all effect from "empty list" to "only the caller's own MRs") is allowed when the correction itself passes the accuracy gate.
- GLAB-S-30. The accuracy gate (GLAB-S-17..GLAB-S-20) and the placeholder rule (GLAB-S-19) apply to every revision, including inherited examples and invariants: content may not be kept on recollection alone.

## Examples

- GLAB-S-04 subtree (live-verified pattern): `glab api "merge_requests?reviewer_username=<username>&per_page=100"` returns only MRs authored by the caller; the same query with `&scope=all` returns MRs from all authors — the difference is the silent default scope `created_by_me`.
- GLAB-S-10/GLAB-S-11 subtree: a discussion reply with the mandatory prefix and encoded path — `glab api -X POST "projects/<group>%2F<project>/merge_requests/<iid>/discussions/<discussion_id>/notes" --raw-field body="AI generated: <comment text>"`; inside the repository the same call uses `projects/:fullpath/...`.
- GLAB-S-13 subtree: `glab api "<endpoint>"` for a missing project prints `{"message":"404 Project Not Found"}` to stdout and `glab: 404 Project Not Found (HTTP 404)` to stderr while exiting 0 — parse stderr or the body, never the exit code.
- GLAB-S-32/GLAB-S-33 subtree (live-verified response shape): a diff-anchored note in `glab api "projects/:fullpath/merge_requests/<iid>/discussions?per_page=100"` carries `position` with `position_type: "text"`, `new_path`/`old_path`, `new_line` (or `old_line`), and a `line_range` block for multi-line anchors; the SHAs for creating such a note come from the single-MR endpoint's `diff_refs` (`base_sha`, `head_sha`, `start_sha`) — the list endpoint returns `diff_refs: null`.

- GLAB-S-35 subtree (live-verified pattern): `glab auth status --hostname <host>` prints `Token: ****` together with `! Invalid token provided` for a stale stored token while another host's block shows `✓ Logged in`; the subsequent `glab api` call returns 401 with exit code 0.
- GLAB-S-36 subtree (live-verified pattern): `glab api` returns 200 for the same host where `git push https://oauth2:<token>@<host>/...` answers `remote: HTTP Basic: Access denied`, and `ssh -T git@<host>` answers `Welcome to GitLab, @<username>!` — the API token and git-over-HTTP/SSH credentials are three separate paths.
- GLAB-S-37 subtree (live-verified pattern): on MR !1913 the review comment "all defaults: /tmp/port_manager/" was visible only via `GET .../discussions` as a DiffNote with `position` (`new_path: flow/ft/lib/ports.py`, `new_line: 40`), while the flat `GET .../notes` returned it among 14 mixed notes without context.
- GLAB-S-38/GLAB-S-40 subtree (live-verified pattern): in a batch post on MR !1887, a position with `new_line` on a context line answered HTTP 400 with a body naming an invalid line_code at rc=0; the same body without `position` landed as a top-level note — anchors must be validated against hunk ranges from `GET .../diffs`, and POST failures are detected in the response body, never by the exit code.
- GLAB-S-39 subtree (live-verified pattern): `diff_refs` fetched from the single-MR endpoint before a ~90-comment batch on MR !1887 rotated mid-batch after a push; notes posted with the older shas were created and shown as outdated — fetch `diff_refs` immediately before each batch and expect rotation on long runs.
- GLAB-S-42 subtree (live-verified pattern, instance-dependent): on GitLab 18.7.7-ee, `POST .../discussions/<discussion_id>/notes` answered 404 and `in_reply_to_discussion_id` on `POST .../notes` was silently ignored (the reply opened a new discussion); `glab api graphql` with `createNote(input: {discussionId: "gid://gitlab/Discussion/<discussion_id>", ...})` posted the reply into the existing thread.
- GLAB-S-43 subtree (live-verified pattern, instance-dependent): on GitLab 18.7.7-ee the discussions listing carries no discussion-level `resolved`; a thread showed resolved exactly when all its non-system notes had `resolved: true`, and the single-MR endpoint's `blocking_discussions_resolved: false` was the merge-blocking signal.
- GLAB-S-46 subtree (live-verified pattern, instance-dependent): on GitLab 18.7.7-ee a `--input` POST answered rc=0 with a body `{"message":"500 Internal Server Error"}` while the note had in fact been created — creation was confirmed by a targeted GET on the saved note id.

## Usage constraints

- The skill is instructions for operating glab; it is not a GitLab API reference: endpoints appear only as far as the covered workflows need them.
- The skill does not handle secrets: token values never appear in the skill or in command lines in examples; login reads the token from standard input or the environment.
- The `AI generated:` prefix is an honesty marker for machine-generated comments, not a style preference; it applies to every posted comment without exception (GLAB-S-26).
- glab flags are version-dependent: on any version other than the one recorded in the skill, re-verify via `--help` before relying on a flag or default (GLAB-S-18).

## Error handling

- A divergence between the skill and this specification is either a spec gap (fix the spec) or a skill bug (fix SKILL.md); silent tolerance is forbidden (header rule).
- An unverifiable flag or claim discovered in the skill is removed or explicitly marked version/instance-dependent (GLAB-S-20); removal of content carrying an invariant is forbidden — re-verify instead (GLAB-S-26..GLAB-S-28, GLAB-S-30).
- A glab version change triggers a re-verification pass over all flags, defaults, and behavioral claims (GLAB-S-18, GLAB-S-30); the version stamp in the skill intro is updated accordingly.

## Dependencies

- None on other skills. Assumes a bash environment with glab installed and at least one authenticated host.

## Used by

None.
