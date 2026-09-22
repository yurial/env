---
name: glab
description: Use when working with GitLab from the command line via glab (GitLab CLI): listing, viewing, creating, checking out, approving, and merging merge requests (MRs), filtering MRs by role (reviewer, assignee, author), draft/WIP MRs, and calling the GitLab REST API via `glab api`. Covers glab-specific traps: repository context, scope=all, iid vs id, pagination. Use ONLY for glab/GitLab CLI operations, not for plain git workflows or other forges.
---

# glab: GitLab CLI — typical workflows and traps

This skill is a practical guide to glab, the GitLab CLI: repository context,
authorization, role-based MR lists, drafts, typical operations, API pagination.
Every identifier in the examples is a placeholder: `<group/project>`,
`<username>`, `<iid>`.

## 1. Repository context

The `glab mr ...`, `glab issue ...`, `glab ci ...` commands must run inside a
git repository: the host and the project are derived from `git remote`
(usually `origin`). Outside a repository the command fails with
`fatal: not a git repository` and exit code 1 — that is a context error, not
"the project has no MRs".

- To work with a specific (including someone else's) project, use the `-R`
  flag: `glab mr list -R <group/project>` (format `<group>/<project>`, nested
  groups `<group>/<subgroup>/<project>`). The `-R` flag exists on all `glab mr`,
  `glab issue`, and `glab ci` commands.
- `glab api` and `glab auth status` work from anywhere: the host comes from the
  authentication config — inside a git repository the host of that repository
  is used, outside it the default host (overridable with the `--hostname` flag
  of `glab api`).

## 2. Authorization

`glab auth status` — check who you are logged in as and on which hosts; works
from any directory. Before working with a new host, make sure it has a valid
token (`✓ Logged in ... as <username>`); `x`/`!` lines in the output indicate
a token problem, and with one the API calls will return 401.

## 3. MR lists by role

Inside a repository — `glab mr list` with a role filter (`@me` is the current
user):

```bash
glab mr list --reviewer=@me    # where I am the reviewer
glab mr list --author=@me      # where I am the author
glab mr list --assignee=@me    # where I am the assignee
```

The list is limited to one project (or a group with `-g <group>`).

Across all accessible projects — the global REST endpoint `merge_requests`:

```bash
glab api "merge_requests?reviewer_username=<username>&state=opened&scope=all"
# likewise: author_username=<username>, assignee_username=<username>
```

The output is a JSON array; parse it with jq or python. Useful fields of each
MR: `iid`, `title`, `state`, `references.full` (full project path + iid),
`web_url`, `work_in_progress`, `author`.

## 4. The scope=all trap (critical)

Without `scope`, the global `merge_requests` endpoint returns only MRs created
by the user themself (the default scope is `created_by_me`). A "where am I a
reviewer" query without `&scope=all` silently returns an empty list — and it is
easy to draw the false conclusion "there are no MRs".

Rules:

- Any global MR search by `reviewer_username` / `author_username` /
  `assignee_username` — only with `&scope=all`.
- On an empty result, before reporting "no MRs", check in order: whether
  `scope=all` is present; whether `state` is right (`opened` excludes
  `merged`/`closed`); whether the right project/group is being searched.

## 5. iid vs the global number

- `iid` is the MR number within a single project; it is the number used in the
  URL and passed to `glab mr <subcommand> <iid>` commands. Only `id` is
  globally unique.
- The same `iid` in different projects means different MRs.
- `404 Not Found` from `glab mr view <N>` more often means "wrong project"
  than "the MR does not exist": the host and project were taken from the
  current repository.
- Therefore, when viewing an MR by number, always either work from that
  project's repository or specify the project explicitly: `glab mr view <iid>
  -R <group/project>`.

## 6. Drafts

- A draft MR has a `Draft:` / `WIP:` title prefix; in the API — the field
  `work_in_progress: true`.
- Filtering: in `glab mr list` — the `-d`/`--draft` flag (drafts only); in API
  queries — the `wip=yes` / `wip=no` parameter.
- Always show the draft status in reports to the user (e.g. from the
  `work_in_progress` field of the JSON response or the `Draft:` prefix in the
  title): a draft is usually not ready for review/merge.

## 7. Typical MR operations

An MR can be addressed by number (`<iid>`) or by its source branch name;
without an argument, the MR of the current branch is used.

```bash
glab mr view <iid>          # MR card: title, description, status
glab mr diff <iid>          # MR diff
glab mr checkout <iid>      # check out the MR branch locally
glab mr create --fill       # create an MR; --fill — title/description from commits
glab mr approve <iid>       # approve
glab mr merge <iid>         # merge (useful: -y, --squash, -d)
glab mr close <iid>         # close
glab mr reopen <iid>        # reopen
```

All commands accept `-R <group/project>`.

## 8. Leaving comments — mandatory `AI generated:` prefix

Every comment posted via glab — a note on an MR, a comment on an issue, or a
reply in a discussion — must begin with the prefix `AI generated:` followed
by a space and the comment text. The prefix marks the comment as
machine-generated: never post a comment without it.

```bash
glab mr note <iid> -m "AI generated: <comment text>"    # note on an MR (<iid> or branch)
glab issue note <iid> -m "AI generated: <comment text>" # comment on an issue
# reply in an existing MR discussion — via the API (:fullpath = current repository):
glab api -X POST "projects/:fullpath/merge_requests/<iid>/discussions/<discussion_id>/notes" \
  --raw-field body="AI generated: <comment text>"
```

Rules:

- The prefix is mandatory for every posted comment; in a multi-line comment
  the first line still begins with `AI generated:`.
- Repo context (section 1) applies: `glab mr note` and `glab issue note`
  accept `-R <group/project>`; in `glab api` use the `:fullpath` placeholder
  inside the repository, or write the project URL-encoded:
  `projects/<group>%2F<project>/...`.

## 9. API pagination

`glab api` returns a single page (20 records by default). For complete lists:

- add `&per_page=100` and walk the pages (`&page=2`, `&page=3`, ...);
- or use the `glab api --paginate` flag — it fetches all pages sequentially
  (useful combined with jq when you need one continuous stream).

A missing "tail" of a large list is a typical symptom of forgotten pagination:
check whether the result was cut off by the page limit.
