#!/usr/bin/env bash
# mr-has-updates.sh - fast boolean "does this MR have any updates?" check.
#
# usage: mr-has-updates.sh <project> <mr_iid> [--state <file>]
#
#   <project>    group/project path (omit when GITLAB_DEFAULT_PROJECT is set)
#   <mr_iid>     MR iid within the project
#   --state F    state marker file; default
#                <tools>/.state/has-updates/<project w/o slashes>__<iid>.json
#                (a bare filename resolves under GITLAB_TOOLS_STATE_DIR/has-updates;
#                the directory is created on demand)
#
# Exit codes:
#   0  updates present; stdout carries one human-readable line per changed
#      category (commits, notes, threads, MR state, title/description,
#      reviewers/approvals, merge status, CI pipeline) - attach it to the
#      timer wakeup
#   1  no updates (also the first run: it records a baseline and prints
#      "baseline recorded (...)" to stdout)
#   2  usage error
#   3  API/network failure (diagnostics on stderr; the state marker is NOT
#      rewritten, so the delta is not lost)
#
# Read-only: GET-only, nothing is ever posted; no git clone needed. The
# marker stores no secrets: no full 40-hex shas (short ids only), no MR or
# description text (length + sha256 prefix only). Written atomically
# (tmp + rename). Schema is additive ("schema": 3).
#
# Traps handled (see lib.sh / tools/README.md): glab api rc=0 on HTTP errors
# (failures detected from the stderr HTTP line and error-shaped bodies; a
# detected failure exits 3 before the marker is touched), 40-hex sha masking
# (the head marker uses the always-present commit short_id; the CI pipeline
# query prefers the unmasked commits-endpoint id and falls back to the MR
# head ref when the id arrives masked), list pagination (notes are walked
# fully - the max note id must be exact; commits/discussions/pipelines use
# per_page=100 single pages).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  cat >&2 <<'EOF'
usage: mr-has-updates.sh <project> <mr_iid> [--state <file>]
EOF
  exit 2
}

die_usage() { printf 'ERROR: %s\n' "$*" >&2; usage; }

proj="" iid="" state_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --state) [ $# -ge 2 ] || die_usage "--state needs a file path"; state_file="$2"; shift ;;
    -h|--help) usage ;;
    -*) die_usage "unknown option: $1" ;;
    *) if [ -z "$proj" ]; then proj="$1"
       elif [ -z "$iid" ]; then iid="$1"
       else die_usage "unexpected argument: $1"
       fi ;;
  esac
  shift
done
# <project> may be omitted when GITLAB_DEFAULT_PROJECT is configured
if [ -n "$proj" ] && [ -z "$iid" ] && [ -n "$GITLAB_DEFAULT_PROJECT" ]; then
  iid="$proj"; proj="$GITLAB_DEFAULT_PROJECT"
fi
[ -n "$proj" ] && [ -n "$iid" ] || usage
[[ "$iid" =~ ^[0-9]+$ ]] || die_usage "<mr_iid> must be numeric, got: $iid"

state_dir="$GITLAB_TOOLS_STATE_DIR/has-updates"
if [ -n "$state_file" ]; then
  case "$state_file" in
    /*|*/*) : ;;
    *) state_file="$state_dir/$state_file" ;;
  esac
else
  state_file="$state_dir/${proj//\//_}__${iid}.json"
fi

# ---------------------------------------------------------------------------
# GET wrappers: every failure exits 3 (API failure) with diagnostics on
# stderr, BEFORE the state marker is touched - the delta is never lost.
# ---------------------------------------------------------------------------

ghu_api_fail() {
  printf 'ERROR: GET %s failed (rc=%s, http=%s): %s %s\n' \
    "$1" "${GT_RC:-?}" "${GT_HTTP_CODE:-?}" \
    "$(tr -d '\n' <"$GT_ERR" | tail -c 200)" \
    "$(tr -d '\n' <"$GT_BODY" | tail -c 200)" >&2
  exit 3
}

# ghu_get ENDPOINT OUT [glab-args...] - single GET, canonical items to OUT.
ghu_get() {
  local endpoint="$1" out="$2"; shift 2
  gt_try_get "$endpoint" "$out" "$@" || ghu_api_fail "$endpoint"
}

# ghu_get_all ENDPOINT OUT - paginated GET (per_page=100 + --paginate).
ghu_get_all() {
  local endpoint="$1" out="$2" sep='?'
  if [[ "$endpoint" == *\?* ]]; then sep='&'; fi
  ghu_get "${endpoint}${sep}per_page=100" "$out" --paginate
}

# ---------------------------------------------------------------------------
# Snapshot fetch (all GET-only; ~6 requests: MR, commits, notes, discussions,
# approvals, pipelines)
# ---------------------------------------------------------------------------

enc="$(gt_urlencode "$proj")"
mr_ep="projects/$enc/merge_requests/$iid"

ghu_get "$mr_ep" "$GT_API_TMP/mr.jsonl"
ghu_get "$mr_ep/commits" "$GT_API_TMP/commits.jsonl"
ghu_get_all "$mr_ep/notes?sort=desc&order_by=created_at" "$GT_API_TMP/notes.jsonl"
# newest discussions first: new-thread detection needs the fresh tail, and
# resolve/unresolve of old threads is caught from system notes (category
# threads), so a single page is enough here
ghu_get "$mr_ep/discussions?order_by=created_at&sort=desc" "$GT_API_TMP/disc.jsonl"
ghu_get "$mr_ep/approvals" "$GT_API_TMP/appr.jsonl"

# CI: the contract query is pipelines?sha=<head_sha>; the sha filter needs
# the FULL 40-hex id (a short id returns an empty list on this instance).
# When the commits endpoint masks the id, fall back to the MR head ref and
# take the newest pipeline of that ref.
pipe_basis="sha"
pipe_sha="$(python3 -c '
import json, sys
try:
    c = json.loads(open(sys.argv[1]).readline())
    cid = c.get("id") or ""
except Exception:
    cid = ""
print(cid if len(cid) == 40 else "")
' "$GT_API_TMP/commits.jsonl")"
if [ -n "$pipe_sha" ]; then
  ghu_get "projects/$enc/pipelines?sha=$pipe_sha" "$GT_API_TMP/pipe.jsonl"
else
  pipe_basis="ref"
  gt_note "commits endpoint masked the head id; CI status via the MR head ref"
  ghu_get "projects/$enc/pipelines?ref=$(gt_urlencode "refs/merge-requests/$iid/head")" \
    "$GT_API_TMP/pipe.jsonl"
fi

# ---------------------------------------------------------------------------
# Compare against the marker, print the summary, update the marker
# ---------------------------------------------------------------------------

rc=0
python3 - "$GT_API_TMP/mr.jsonl" "$GT_API_TMP/commits.jsonl" "$GT_API_TMP/notes.jsonl" \
          "$GT_API_TMP/disc.jsonl" "$GT_API_TMP/appr.jsonl" "$GT_API_TMP/pipe.jsonl" \
          "$state_file" "$proj" "$iid" "$pipe_basis" <<'PY' || rc=$?
import hashlib, json, os, sys, datetime

(mr_path, commits_path, notes_path, disc_path, appr_path, pipe_path,
 state_path, proj, iid, pipe_basis) = sys.argv[1:11]

RESOLVE_ACTIONS = {"[resolved]", "[unresolved]", "resolved all threads"}
MAX_COMMITS_LISTED = 5  # new-commit shas printed in the summary line


def load_lines(path):
    out = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if line.strip():
                out.append(json.loads(line))
    return out


def h12(text):
    return hashlib.sha256(text.encode("utf-8", "replace")).hexdigest()[:12]


def eff_sha(commit):  # full id when unmasked, else the surviving short_id
    cid = commit.get("id") or ""
    return cid if len(cid) == 40 else (commit.get("short_id") or cid)


def die_api(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(3)


# ---- current snapshot ------------------------------------------------------

mr = load_lines(mr_path)
if len(mr) != 1 or not isinstance(mr[0], dict):
    die_api(f"unexpected merge request payload ({len(mr)} item(s))")
mr = mr[0]

commits = load_lines(commits_path)
notes = load_lines(notes_path)
discussions = load_lines(disc_path)
approvals = load_lines(appr_path)
pipelines = load_lines(pipe_path)

cur = {}
cur["mr_state"] = mr.get("state") or ""
cur["draft"] = bool(mr.get("draft") or mr.get("work_in_progress"))
title = mr.get("title") or ""
desc = mr.get("description") or ""
cur["title_len"], cur["title_hash"] = len(title), h12(title)
cur["desc_len"], cur["desc_hash"] = len(desc), h12(desc)
cur["reviewers"] = sorted(r.get("username") or "" for r in mr.get("reviewers") or [])
cur["approved_by"] = sorted(
    a.get("user", {}).get("username") or "" for a in approvals[0].get("approved_by") or []
) if approvals and isinstance(approvals[0], dict) else []
cur["merge_status"] = mr.get("merge_status") or ""
cur["detailed_merge_status"] = mr.get("detailed_merge_status") or ""

head = commits[0] if commits else {}
cur["head_short"] = head.get("short_id") or eff_sha(head)
cur["head_created"] = head.get("created_at") or ""

cur["max_note_id"] = max((n.get("id") or 0 for n in notes), default=0)
cur["max_note_created"] = ""
for n in notes:
    if n.get("id") == cur["max_note_id"]:
        cur["max_note_created"] = n.get("created_at") or ""
resolvable = [n for n in notes if n.get("resolvable")]
cur["unresolved_ids"] = sorted(n["id"] for n in resolvable if not n.get("resolved"))
cur["resolved_count"] = sum(1 for n in resolvable if n.get("resolved"))
cur["discussion_ids"] = [d.get("id") for d in discussions if d.get("id")]

cur["pipeline"] = None
if pipelines:
    newest = max(pipelines, key=lambda p: p.get("id") or 0)
    cur["pipeline"] = {"id": newest.get("id"), "status": newest.get("status") or ""}

# ---- the marker -----------------------------------------------------------

old = None
if os.path.exists(state_path):
    try:
        loaded = json.load(open(state_path, encoding="utf-8"))
    except Exception as exc:
        die_api(f"state marker {state_path} is unreadable ({exc}); "
                f"fix or remove it by hand - refusing to lose the delta")
    if isinstance(loaded, dict) and loaded.get("schema") == 3 \
            and str(loaded.get("iid")) == str(iid) \
            and loaded.get("project") == proj:
        old = loaded
    else:
        print(f"NOTE: {state_path} is not a schema-3 marker for {proj}!{iid}; "
              f"recording a fresh baseline", file=sys.stderr)

now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def build_state():
    return {
        "schema": 3,
        "project": proj,
        "iid": int(iid),
        "head_short_id": cur["head_short"],
        "head_created_at": cur["head_created"],
        "commit_count": len(commits),
        "max_note_id": cur["max_note_id"],
        "max_note_created_at": cur["max_note_created"],
        "resolved_count": cur["resolved_count"],
        "unresolved_note_ids": cur["unresolved_ids"],
        "discussion_ids": cur["discussion_ids"],
        "mr_state": cur["mr_state"],
        "draft": cur["draft"],
        "title_len": cur["title_len"], "title_hash": cur["title_hash"],
        "desc_len": cur["desc_len"], "desc_hash": cur["desc_hash"],
        "reviewers": cur["reviewers"],
        "approved_by": cur["approved_by"],
        "merge_status": cur["merge_status"],
        "detailed_merge_status": cur["detailed_merge_status"],
        "pipeline": cur["pipeline"],
        "saved_at": now,
    }


def write_state(st):
    directory = os.path.dirname(state_path)
    if directory:
        os.makedirs(directory, exist_ok=True)
    tmp = state_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(st, indent=2, ensure_ascii=False) + "\n")
    os.replace(tmp, state_path)


if old is None:
    write_state(build_state())
    pipe = cur["pipeline"]
    pipe_txt = "no pipeline" if pipe is None else f"pipeline {pipe['id']} {pipe['status']}"
    print(f"baseline recorded (head {cur['head_short'] or '?'}, "
          f"{len(commits)} commit(s) listed, max note id {cur['max_note_id']}, "
          f"{len(notes)} note(s), {len(discussions)} discussion(s) listed, "
          f"{pipe_txt})")
    sys.exit(1)

# ---- category deltas (one summary line each) --------------------------------

lines = []


def add(line):
    lines.append(line)


# 1. commits: head moved and/or new commits before the marker head
new_commits = []
cut_seen = False
for c in commits:
    if old.get("head_short_id") and eff_sha(c)[:8] == old["head_short_id"][:8]:
        cut_seen = True
        break
    new_commits.append(c)
if cur["head_short"] != old.get("head_short_id"):
    shas = ", ".join(eff_sha(c)[:8] for c in new_commits[:MAX_COMMITS_LISTED])
    if len(new_commits) > MAX_COMMITS_LISTED:
        shas += ", ..."
    detail = f"{len(new_commits)} new: {shas}" if shas else "no new commits listed"
    if new_commits and not cut_seen:
        detail += " (marker head not in the newest page; list may be truncated)"
    add(f"commits: head {old.get('head_short_id') or '?'} -> {cur['head_short']}"
        f" ({detail})")
elif new_commits:
    shas = ", ".join(eff_sha(c)[:8] for c in new_commits[:MAX_COMMITS_LISTED])
    if len(new_commits) > MAX_COMMITS_LISTED:
        shas += ", ..."
    add(f"commits: {len(new_commits)} new before the same head: {shas}")

# 2. notes: anything with a higher id (user AND system notes)
cut_id = old.get("max_note_id") or 0
new_notes = [n for n in notes if (n.get("id") or 0) > cut_id]
if new_notes:
    newest = max(new_notes, key=lambda n: n.get("id") or 0)
    who = (newest.get("author") or {}).get("username") or "?"
    body = (newest.get("body") or "").strip().splitlines()
    first = body[0][:60] if body else ""
    n_system = sum(1 for n in new_notes if n.get("system"))
    tail = f", latest @{who}: {first}" if first else ""
    if n_system == len(new_notes) and new_notes:
        tail += " (all system)"
    add(f"notes: {len(new_notes)} new (max note id {cut_id} -> "
        f"{cur['max_note_id']}{tail})")

# 3. threads: resolve/unresolve flips (system notes + set diff) and new
#    discussions
old_unres = set(old.get("unresolved_note_ids") or [])
now_unres = set(cur["unresolved_ids"])
became_resolved = sorted(old_unres - now_unres)
became_unresolved = sorted(now_unres - old_unres)
events = [n for n in new_notes if n.get("system")
          and (n.get("body") or "").strip().lower() in RESOLVE_ACTIONS]
new_disc = [d for d in cur["discussion_ids"] if d not in set(old.get("discussion_ids") or [])]
if events or became_resolved or became_unresolved or new_disc:
    parts = []
    if events:
        by_whom = {}
        for n in events:
            who = (n.get("author") or {}).get("username") or "?"
            action = (n.get("body") or "").strip().lower().strip("[]")
            by_whom.setdefault(f"{action}", []).append(who)
        for action in sorted(by_whom):
            parts.append(f"{len(by_whom[action])} {action} "
                         f"(by {', '.join(sorted(set(by_whom[action])))})")
    parts += [f"{len(became_resolved)} note(s) now resolved"] if became_resolved else []
    parts += [f"{len(became_unresolved)} note(s) now unresolved"] if became_unresolved else []
    parts += [f"{len(new_disc)} new discussion(s)"] if new_disc else []
    add("threads: " + ", ".join(parts))

# 4. MR state / draft
state_parts = []
if cur["mr_state"] != old.get("mr_state"):
    state_parts.append(f"state {old.get('mr_state')} -> {cur['mr_state']}")
if cur["draft"] != bool(old.get("draft")):
    state_parts.append(f"draft {'yes' if old.get('draft') else 'no'} -> "
                       f"{'yes' if cur['draft'] else 'no'}")
if state_parts:
    add("mr state: " + "; ".join(state_parts))

# 5. title / description (hashes only; no text is stored)
text_parts = []
if cur["title_hash"] != old.get("title_hash"):
    text_parts.append(f"title changed ({old.get('title_len')} -> {cur['title_len']} chars)")
if cur["desc_hash"] != old.get("desc_hash"):
    text_parts.append(f"description changed ({old.get('desc_len')} -> {cur['desc_len']} chars)")
if text_parts:
    add("title/description: " + "; ".join(text_parts))

# 6. reviewers / approvals
def set_diff(old_list, new_list, label, parts):
    old_set, new_set = set(old_list or []), set(new_list)
    added = sorted(new_set - old_set)
    removed = sorted(old_set - new_set)
    bits = []
    if added:
        bits.append("+" + ", +".join(added))
    if removed:
        bits.append("-" + ", -".join(removed))
    if bits:
        parts.append(f"{label} " + ", ".join(bits))


ra_parts = []
set_diff(old.get("reviewers"), cur["reviewers"], "reviewers", ra_parts)
set_diff(old.get("approved_by"), cur["approved_by"], "approvals", ra_parts)
if ra_parts:
    add("reviewers/approvals: " + "; ".join(ra_parts))

# 7. merge status
ms_parts = []
if cur["merge_status"] != old.get("merge_status"):
    ms_parts.append(f"{old.get('merge_status')} -> {cur['merge_status']}")
if cur["detailed_merge_status"] != old.get("detailed_merge_status"):
    ms_parts.append(f"detailed: {old.get('detailed_merge_status')} -> "
                    f"{cur['detailed_merge_status']}")
if ms_parts:
    add("merge status: " + "; ".join(ms_parts))

# 8. CI pipeline for the current head
old_pipe = old.get("pipeline") or None
if cur["pipeline"] != old_pipe:
    if cur["pipeline"] is None:
        add(f"CI: pipeline gone (was "
            f"{old_pipe['id']} {old_pipe['status'] if old_pipe else '?'})")
    elif old_pipe is None:
        p = cur["pipeline"]
        add(f"CI: new pipeline {p['id']} {p['status']} (head {cur['head_short']}, "
            f"by {pipe_basis})")
    else:
        p = cur["pipeline"]
        same = "same id" if p["id"] == old_pipe.get("id") else f"id {old_pipe.get('id')} -> {p['id']}"
        add(f"CI: pipeline {p['id']} {old_pipe.get('status')} -> {p['status']} "
            f"({same}, head {cur['head_short']})")

# ---- verdict ---------------------------------------------------------------

if lines:
    write_state(build_state())
    print("\n".join(lines))
    sys.exit(0)

print(f"no updates since {old.get('saved_at') or '?'}", file=sys.stderr)
sys.exit(1)
PY
case "$rc" in
  0) exit 0 ;;
  1) exit 1 ;;
  *) exit 3 ;;
esac
