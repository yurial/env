#!/usr/bin/env bash
# mr-updates.sh - MR state plus the delta of commits and notes since a marker.
#
# usage: mr-updates.sh <project> <mr_iid> [--since <iso8601|sha>] [--state <file>] [--fetch]
#
#   --since      only show commits/notes newer than an ISO8601 timestamp or a
#                commit sha (newest-first walk stops right before the sha)
#   --state      marker file: after printing, stores the MR head sha (+ its
#                short_id) and the max note id/created_at; the next run
#                reports only the delta (no marker file = full dump)
#   --fetch      inside a git clone, refresh origin/<source_branch> first
#
# Traps handled: 40-hex shas masked as __SECRET_N__ (flaky per response;
# short_id always survives - head comes from the commits endpoint id, the
# short_id resolved locally, git ls-remote, or local refs), 20/30-record
# pagination (per_page=100 + --paginate), concatenated page arrays parsed
# with repeated raw_decode, `glab api` rc=0-on-error (gt_get dies on
# detected HTTP failures), early-exiting pipeline readers (SIGPIPE-safe).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  cat >&2 <<'EOF'
usage: mr-updates.sh <project> <mr_iid> [--since <iso8601|sha>] [--state <file>] [--fetch]
EOF
  exit 2
}

proj="" iid="" since="" state_file="" opt_fetch=0
while [ $# -gt 0 ]; do
  case "$1" in
    --since) [ $# -ge 2 ] || usage; since="$2"; shift ;;
    --state) [ $# -ge 2 ] || usage; state_file="$2"; shift ;;
    --fetch) opt_fetch=1 ;;
    -h|--help) usage ;;
    -*) gt_die "unknown option: $1" ;;
    *) if [ -z "$proj" ]; then proj="$1"
       elif [ -z "$iid" ]; then iid="$1"
       else gt_die "unexpected argument: $1"
       fi ;;
  esac
  shift
done
# <project> may be omitted when GITLAB_DEFAULT_PROJECT is configured
if [ -n "$proj" ] && [ -z "$iid" ] && [ -n "$GITLAB_DEFAULT_PROJECT" ]; then
  iid="$proj"; proj="$GITLAB_DEFAULT_PROJECT"
fi
[ -n "$proj" ] && [ -n "$iid" ] || usage
if [ -n "$since" ] && [ -n "$state_file" ] && [ -f "$state_file" ]; then
  gt_note "--state marker exists; --since is ignored for the delta"
fi
# a bare --state filename lives in GITLAB_TOOLS_STATE_DIR (created on demand)
if [ -n "$state_file" ]; then
  case "$state_file" in
    /*|*/*) : ;;
    *) state_file="$GITLAB_TOOLS_STATE_DIR/$state_file" ;;
  esac
  mkdir -p "$(dirname "$state_file")"
fi

enc="$(gt_urlencode "$proj")"
mr_ep="projects/$enc/merge_requests/$iid"

# ---- MR state ----------------------------------------------------------
gt_get "$mr_ep" > "$GT_API_TMP/mr.json"
python3 - "$GT_API_TMP/mr.json" > "$GT_API_TMP/mr.fields" <<'PY'
import json, sys
mr = json.loads(open(sys.argv[1]).readline())
dr = mr.get("diff_refs") or {}
vals = [
    mr.get("title") or "",
    mr.get("state") or "",
    "yes" if mr.get("draft") else "no",
    mr.get("updated_at") or "",
    mr.get("source_branch") or "",
    mr.get("target_branch") or "",
    dr.get("head_sha") or "",
]
print("\n".join(vals))
PY
mapfile -t f < "$GT_API_TMP/mr.fields"
mr_title="${f[0]}"; mr_state="${f[1]}"; mr_draft="${f[2]}"; mr_updated="${f[3]}"
src_branch="${f[4]}"; tgt_branch="${f[5]}"; api_head="${f[6]}"

# real head sha; the API masks 40-hex values per response, short_id survives
head_sha=""; head_short=""; head_src=""
head_fields="$GT_API_TMP/head.fields"
if gt_try_get "$mr_ep/commits?per_page=1" "$GT_API_TMP/commits1.jsonlines"; then
  python3 - "$GT_API_TMP/commits1.jsonlines" > "$head_fields" <<'PY'
import json, sys
try:
    c = json.loads(open(sys.argv[1]).readline())
except Exception:
    c = {}
print(c.get("id", ""))
print(c.get("short_id", ""))
print(c.get("created_at", ""))
PY
  mapfile -t hf < "$head_fields"
  if gt_is_sha "${hf[0]:-}"; then
    head_sha="${hf[0]}"; head_src="commits endpoint"
  fi
  head_short="${hf[1]:-}"; head_created="${hf[2]:-}"
fi
repo="$(gt_git_dir)"
if ! gt_is_sha "$head_sha" && [ -n "$head_short" ] && [ -n "$repo" ]; then
  s="$(gt_git_sha "$repo" "$head_short")"
  if [ -n "$s" ]; then head_sha="$s"; head_src="commits endpoint short_id resolved locally"; fi
fi
if ! gt_is_sha "$head_sha" && [ -n "$repo" ]; then
  s="$(gt_lsremote_head "$repo" "$src_branch")"
  if [ -n "$s" ]; then head_sha="$s"; head_src="git ls-remote origin/$src_branch"; fi
fi
if ! gt_is_sha "$head_sha" && [ -n "$repo" ]; then
  s="$(gt_git_sha "$repo" "origin/$src_branch")"
  if [ -n "$s" ]; then head_sha="$s"; head_src="local git (origin/$src_branch, may be stale)"; fi
fi
if ! gt_is_sha "$head_sha" && [ -n "$repo" ]; then
  s="$(gt_git_sha "$repo" "refs/heads/$src_branch")"
  if [ -n "$s" ]; then head_sha="$s"; head_src="local git ($src_branch, may be stale)"; fi
fi
[ -n "$head_created" ] || head_created=""

echo "== MR state =="
echo "project:      $proj"
echo "iid:          $iid"
echo "title:        $mr_title"
echo "state:        $mr_state"
echo "draft:        $mr_draft"
echo "updated_at:   $mr_updated"
echo "source:       $src_branch -> $tgt_branch"
if gt_is_sha "$head_sha"; then
  echo "head_sha:     $head_sha  (from $head_src; API diff_refs.sha reported: ${api_head:-<none>})"
else
  head_sha="$api_head"
  head_src="API diff_refs (masked)"
  gt_warn "head sha could not be recovered locally; commit delta by sha will be unreliable - run inside a clone"
  echo "head_sha:     $head_sha  (masked)"
fi

# ---- delta basis -------------------------------------------------------
c_cut_sha=""; c_cut_iso=""; n_cut_id="0"; n_cut_iso=""
basis="full dump (no marker)"
if [ -n "$state_file" ] && [ -f "$state_file" ]; then
  python3 - "$state_file" > "$GT_API_TMP/state.fields" <<'PY'
import json, re, sys
try:
    st = json.load(open(sys.argv[1]))
except Exception:
    st = {}
for k in ("head_sha", "head_created_at", "max_note_id", "max_note_created_at"):
    v = st.get(k, "")
    v = "" if v is None else str(v)
    # a masked sha (__SECRET_N__) stored by an older run is not a cutoff
    if k == "head_sha" and not re.fullmatch(r"[0-9a-f]{40}", v):
        v = ""
    print(v)
PY
  mapfile -t sf < "$GT_API_TMP/state.fields"
  c_cut_sha="${sf[0]}"; c_cut_iso="${sf[1]}"; n_cut_id="${sf[2]:-0}"; n_cut_iso="${sf[3]}"
  basis="state marker: head=${c_cut_sha:-<none>}, note>${n_cut_id}"
elif [ -n "$since" ]; then
  if gt_is_sha "$since"; then
    c_cut_sha="$since"
  else
    gt_is_iso "$since" || gt_die "--since expects an ISO8601 timestamp or a commit sha, got: $since"
    c_cut_iso="$since"; n_cut_iso="$since"
  fi
  basis="--since $since"
fi
echo "basis:        $basis"

# ---- commits -----------------------------------------------------------
echo
echo "== commits (new since) =="

use_local=0
if [ -n "$repo" ] && [ -n "$(gt_git_sha "$repo" "origin/$src_branch")" ]; then
  use_local=1
  if [ "$opt_fetch" = 1 ]; then
    gt_note "fetching origin/$src_branch in $repo"
    git -C "$repo" fetch --quiet origin "$src_branch" || gt_warn "git fetch failed; using local refs as-is"
  fi
fi

# cutoff walk: stop right before the commit matching the marker sha
# (full id or, when the response masked the id, its always-present short_id);
# fall back to the created_at cutoff when the marker never shows up
commits_out="$GT_API_TMP/commits.delta"
if [ "$use_local" = 1 ]; then
  # branch-only commits (skip target ancestry), newest first
  git -C "$repo" log --format='%H%x09%cI%x09%an%x09%s' "origin/$src_branch" --not "origin/$tgt_branch" 2>/dev/null \
    | python3 -c '
import sys
cut_sha, cut_iso = sys.argv[1], sys.argv[2]
items = []
for line in sys.stdin:
    parts = line.rstrip("\n").split("\t", 3)
    while len(parts) < 4:
        parts.append("")
    items.append(parts)
idx = None
if cut_sha:
    idx = next((i for i, it in enumerate(items) if it[0] == cut_sha), None)
if idx is not None:
    for it in items[:idx]:
        print(f"{it[0]} {it[1]} {it[2]}  {it[3]}")
else:
    if cut_sha:
        print("NOTE: cutoff sha not found in local log (stale clone?); used the time cutoff instead", file=sys.stderr)
    for it in items:
        if not cut_iso or it[1] > cut_iso:
            print(f"{it[0]} {it[1]} {it[2]}  {it[3]}")
' "$c_cut_sha" "$c_cut_iso" > "$commits_out" || true
else
  gt_get_all "$mr_ep/commits" > "$GT_API_TMP/commits.jsonlines"
  python3 - "$GT_API_TMP/commits.jsonlines" "$c_cut_sha" "$c_cut_iso" > "$commits_out" <<'PY'
import json, sys
items = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
cut_sha, cut_iso = sys.argv[2], sys.argv[3]

def eff(c):
    cid = c.get("id", "")
    if len(cid) == 40 and all(ch in "0123456789abcdef" for ch in cid):
        return cid
    return c.get("short_id", "")  # masked response: short_id always survives

# stop right before the marker commit (match by id or short-id prefix)
cut_at = None
if cut_sha:
    for i, c in enumerate(items):
        e = eff(c)
        if e == cut_sha or (len(e) == 8 and cut_sha.startswith(e)):
            cut_at = i
            break
shown = 0
if cut_at is not None:
    for c in items[:cut_at]:
        print(f"{eff(c)} {c.get('created_at','')} {c.get('author_name','')}  {c.get('title','')}")
        shown += 1
else:
    if cut_sha:
        print("NOTE: cutoff sha not found in the MR commit list (force-push?); used the time cutoff", file=sys.stderr)
    for c in items:
        if not cut_iso or c.get("created_at", "") > cut_iso:
            print(f"{eff(c)} {c.get('created_at','')} {c.get('author_name','')}  {c.get('title','')}")
            shown += 1
PY
fi
# per-commit diffstat (files changed, +/-) - only inside a clone; the API
# path has no numstat (masked shas, no local objects), so those lines stay
# without the suffix. Merge/root commits with no numstat output get none.
if [ -s "$commits_out" ]; then
  if [ "$use_local" = 1 ]; then
    python3 - "$commits_out" "$repo" > "$commits_out.stat" <<'PY'
import subprocess, sys
out, repo = sys.argv[1], sys.argv[2]
for line in open(out):
    line = line.rstrip("\n")
    sha = line.split(" ", 1)[0]
    files = adds = dels = 0
    try:
        r = subprocess.run(
            ["git", "-C", repo, "diff-tree", "--no-commit-id", "-r", "--numstat", sha],
            capture_output=True, text=True, check=True)
        for st in r.stdout.splitlines():
            p = st.split("\t")
            if len(p) == 3:
                files += 1
                if p[0] != "-":
                    adds += int(p[0])
                if p[1] != "-":
                    dels += int(p[1])
    except Exception:
        pass
    suffix = f"  ({files} files, +{adds}/-{dels})" if files else ""
    print(line + suffix)
PY
    cat "$commits_out.stat"
  else
    cat "$commits_out"
  fi
else
  echo "(no new commits)"
fi

# ---- notes -------------------------------------------------------------
echo
echo "== notes (new since) =="
gt_get_all "$mr_ep/notes?sort=desc&order_by=created_at" > "$GT_API_TMP/notes.jsonlines"
python3 - "$GT_API_TMP/notes.jsonlines" "$n_cut_id" "$n_cut_iso" <<'PY'
import json, sys
lines = [l for l in open(sys.argv[1]) if l.strip()]
cut_id = int(sys.argv[2] or 0)
cut_iso = sys.argv[3] or ""
items = [json.loads(l) for l in lines]
newest_first = sorted(items, key=lambda n: n.get("id", 0), reverse=True)
shown = 0
for n in newest_first:
    nid = n.get("id", 0)
    created = n.get("created_at", "")
    if cut_id and nid <= cut_id:
        continue
    if cut_iso and created <= cut_iso:
        continue
    who = (n.get("author") or {}).get("username", "?")
    body = n.get("body") or ""
    flags = []
    if n.get("system"):
        flags.append("system")
    if n.get("resolvable"):
        flags.append("resolved" if n.get("resolved") else "unresolved")
    fl = (" [" + ",".join(flags) + "]") if flags else ""
    print(f"#{nid} {created} {who}{fl}")
    for bl in body.splitlines() or [""]:
        print(f"    {bl}")
    print()
    shown += 1
if shown == 0:
    print("(no new notes)")
PY

# ---- thread status changes ----------------------------------------------
# Resolution events are system notes: "[resolved]"/"[unresolved]" inside a
# thread and "resolved all threads" on the MR timeline (on this instance the
# latter also lands as a note inside the last active discussion, so it maps
# to a discussion id by note id). The section is printed only when the delta
# contains at least one such event; the discussion listing is fetched lazily
# (GET-only) to map event note ids -> discussion id + anchor + original note.
res_events="$GT_API_TMP/res.events"
python3 - "$GT_API_TMP/notes.jsonlines" "$n_cut_id" "$n_cut_iso" > "$res_events" <<'PY'
import json, sys
lines = [l for l in open(sys.argv[1]) if l.strip()]
cut_id = int(sys.argv[2] or 0)
cut_iso = sys.argv[3] or ""
items = sorted((json.loads(l) for l in lines), key=lambda n: n.get("id", 0), reverse=True)
actions = {"[resolved]": "resolved", "[unresolved]": "unresolved",
           "resolved all threads": "resolved all threads"}
for n in items:
    if not n.get("system"):
        continue
    nid = n.get("id", 0)
    created = n.get("created_at", "")
    if cut_id and nid <= cut_id:
        continue
    if cut_iso and created <= cut_iso:
        continue
    action = actions.get((n.get("body") or "").strip().lower())
    if not action:
        continue
    print(json.dumps({"id": nid, "created": created, "action": action,
                      "who": (n.get("author") or {}).get("username", "?")},
                     ensure_ascii=False))
PY
if [ -s "$res_events" ]; then
  echo
  echo "== thread status changes =="
  gt_get_all "$mr_ep/discussions" > "$GT_API_TMP/disc.jsonlines"
  python3 - "$res_events" "$GT_API_TMP/disc.jsonlines" <<'PY'
import json, sys
events = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
disc = [json.loads(l) for l in open(sys.argv[2]) if l.strip()]
note_home = {}
for d in disc:
    for n in d.get("notes") or []:
        note_home[n.get("id")] = d
for e in events:  # newest first, same order as the notes section
    d = note_home.get(e["id"])
    print(f"{e['created']}  {e['who']}: {e['action']}")
    if d is None:
        print("    discussion: (all threads; MR timeline note)")
        print()
        continue
    print(f"    discussion: {d.get('id', '?')}")
    ns = [n for n in d.get("notes") or [] if not n.get("system")]
    anchor = ""
    for n in ns:
        p = n.get("position") or {}
        if p:
            path = p.get("new_path") or p.get("old_path") or "?"
            line = p.get("new_line") or p.get("old_line") or "?"
            side = "new" if p.get("new_line") else "old"
            anchor = f"{path}:{line} ({side} side)"
            break
    print(f"    anchor:     {anchor or '(no anchor)'}")
    ctx = ""
    for n in ns:  # prefer our original note, else the first note of the thread
        body = n.get("body") or ""
        if body.startswith("AI generated: "):
            ctx = body.splitlines()[0] if body.splitlines() else ""
            break
    if not ctx and ns:
        lines = (ns[0].get("body") or "").splitlines()
        ctx = lines[0] if lines else ""
    print(f"    context:    {ctx[:160] or '(empty)'}")
    print()
PY
fi

# ---- state update ------------------------------------------------------
if [ -n "$state_file" ]; then
  python3 - "$state_file" "$proj" "$iid" "$head_sha" "$head_created" "${head_short:-}" "$GT_API_TMP/notes.jsonlines" <<'PY'
import json, sys, os, datetime
state_path, proj, iid, head_sha, head_created, head_short, notes_path = sys.argv[1:]
old = {}
if os.path.exists(state_path):
    try:
        old = json.load(open(state_path))
    except Exception:
        old = {}
max_id = int(old.get("max_note_id") or 0)
max_ts = old.get("max_note_created_at") or ""
for line in open(notes_path):
    if not line.strip():
        continue
    n = json.loads(line)
    if n.get("id", 0) > max_id:
        max_id = n["id"]
        max_ts = n.get("created_at", "")
# never store a masked sha: the cutoff walk would search for "__SECRET_N__"
if not (len(head_sha) == 40 and all(ch in "0123456789abcdef" for ch in head_sha)):
    head_sha = ""
st = {
    "schema": 2,
    "project": proj,
    "iid": iid,
    "head_sha": head_sha,
    "head_short_id": head_short,
    "head_created_at": head_created,
    "max_note_id": max_id,
    "max_note_created_at": max_ts,
    "saved_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
d = os.path.dirname(state_path)
if d:
    os.makedirs(d, exist_ok=True)
tmp = state_path + ".tmp"
open(tmp, "w").write(json.dumps(st, indent=2) + "\n")
os.replace(tmp, state_path)
tag = head_sha if head_sha else "-"
print(f"state saved to {state_path}: head={tag} max_note_id={max_id}", file=sys.stderr)
PY
fi
