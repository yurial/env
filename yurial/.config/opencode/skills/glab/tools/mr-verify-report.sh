#!/usr/bin/env bash
# mr-verify-report.sh - turn a reviewer verdict list into replies and drafts.
#
# usage: mr-verify-report.sh <project> <mr_iid> <verdicts.json>
#                            [--emit <out.json>] [--post] [--yes] [--repo <dir>]
#
# verdicts.json = JSON array of:
#   {"action": "acknowledge"|"contest",
#    "thread_hint": "<substring of our original note text>",
#    "text": "..."}
#   {"action": "new", "path": "a/b.cpp", "line": 102,
#    "old_side": true (optional), "text": "..."}
#
# "text" is the body WITHOUT the "AI generated: " prefix - the prefix is
# added by this script (a text already carrying it is not doubled).
# acknowledge/contest locate the target thread by thread_hint: a discussion
# containing a note that starts with "AI generated: " and contains the hint
# substring; zero or several matching discussions is an error (the plan is
# never built on a guess). "new" validates the anchor like mr-comment.sh
# (out-of-diff / out-of-hunk anchors are refused with the valid ranges).
#
# Modes (the full plan is always printed before any write):
#   --emit FILE   write a batch file for mr-draft-review.sh (replies encoded
#                 as {"reply_to_discussion_id": ..., "body": ...}) - the only
#                 write is that local file, no MR writes
#   --post        post now even when --emit is also given
#   (neither)     post now
#   Posting needs --yes as well; without --yes only the plan is printed.
#   Replies go through mr-reply.sh (REST + GraphQL fallback, verified by
#   GET); "new" items go through the draft_notes flow of mr-draft-review.sh
#   and stay private (never published from here).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  cat >&2 <<'EOF'
usage: mr-verify-report.sh <project> <mr_iid> <verdicts.json>
                           [--emit <out.json>] [--post] [--yes] [--repo <dir>]

  --emit FILE   write an mr-draft-review.sh batch file instead of posting
  --post        post now even when --emit is also given
  --yes         required for any MR write (replies + draft creation)
  --repo DIR    clone used for sha recovery / hunk building of "new" items
EOF
  exit 2
}

proj="" iid="" input="" emit="" repo_arg=""
post=0 yes=0
while [ $# -gt 0 ]; do
  case "$1" in
    --emit) [ $# -ge 2 ] || usage; emit="$2"; shift ;;
    --post) post=1 ;;
    --yes) yes=1 ;;
    --repo) [ $# -ge 2 ] || usage; repo_arg="$2"; shift ;;
    -h|--help) usage ;;
    -*) gt_die "unknown option: $1" ;;
    *) if [ -z "$proj" ]; then proj="$1"
       elif [ -z "$iid" ]; then iid="$1"
       elif [ -z "$input" ]; then input="$1"
       else gt_die "unexpected argument: $1"
       fi ;;
  esac
  shift
done
# <project> may be omitted when GITLAB_DEFAULT_PROJECT is configured
if [ -n "$iid" ] && [ -z "$input" ] && [ -n "$GITLAB_DEFAULT_PROJECT" ]; then
  input="$iid"; iid="$proj"; proj="$GITLAB_DEFAULT_PROJECT"
fi
[ -n "$proj" ] && [ -n "$iid" ] && [ -n "$input" ] || usage
[ -f "$input" ] || gt_die "verdicts file not found: $input"

enc="$(gt_urlencode "$proj")"
ep="projects/$enc/merge_requests/$iid"

# ---- 1) validate + normalize verdicts ------------------------------------
python3 - "$input" "$GT_API_TMP/plan.json" "$GT_PREFIX" <<'PY'
import json, sys
src, out, prefix = sys.argv[1:]
try:
    data = json.load(open(src, encoding="utf-8"))
except Exception as e:
    sys.exit(f"cannot parse {src}: {e}")
if not isinstance(data, list) or not data:
    sys.exit(f"{src} must be a non-empty JSON array of verdict objects")
plan, bad = [], []
for i, v in enumerate(data):
    action = v.get("action")
    text = v.get("text")
    if action not in ("acknowledge", "contest", "new"):
        bad.append(f"  #{i}: action must be acknowledge|contest|new, got {action!r}")
        continue
    if not isinstance(text, str) or not text.strip():
        bad.append(f"  #{i} ({action}): missing/empty 'text'")
        continue
    body = text if text.startswith(prefix) else prefix + text
    if action == "new":
        path, line = v.get("path"), v.get("line")
        if not isinstance(path, str) or not path:
            bad.append(f"  #{i} (new): missing/invalid 'path'")
            continue
        if not isinstance(line, int) or line < 1:
            bad.append(f"  #{i} (new {path}): missing/invalid 'line'")
            continue
        plan.append({"idx": i, "action": "new", "body": body, "path": path,
                     "line": line, "old_side": bool(v.get("old_side"))})
    else:
        hint = v.get("thread_hint")
        if not isinstance(hint, str) or not hint.strip():
            bad.append(f"  #{i} ({action}): missing/empty 'thread_hint'")
            continue
        plan.append({"idx": i, "action": action, "body": body, "hint": hint.strip()})
if bad:
    print("verdict validation failed:", file=sys.stderr)
    print("\n".join(bad), file=sys.stderr)
    sys.exit(1)
json.dump(plan, open(out, "w", encoding="utf-8"), ensure_ascii=False)
n_new = sum(1 for p in plan if p["action"] == "new")
print(f"parsed {len(plan)} verdict(s) from {src}: "
      f"{len(plan) - n_new} acknowledge/contest, {n_new} new", file=sys.stderr)
PY

# ---- 2) shas (only "new" items need them) --------------------------------
n_new="$(python3 -c '
import json, sys
plan = json.load(open(sys.argv[1], encoding="utf-8"))
print(sum(1 for p in plan if p["action"] == "new"))
' "$GT_API_TMP/plan.json")"
repo="$repo_arg"
if [ "$n_new" -gt 0 ]; then
  [ -n "$repo" ] || repo="$GITLAB_REPO"
  [ -n "$repo" ] || repo="$(gt_git_dir)"
  gt_resolve_shas "$repo" "$enc" "$iid"
fi

# ---- 3) resolve reply targets + validate anchors (read-only) --------------
n_replies_now="$(python3 -c '
import json, sys
plan = json.load(open(sys.argv[1], encoding="utf-8"))
print(sum(1 for p in plan if p["action"] != "new"))
' "$GT_API_TMP/plan.json")"
if [ "$n_replies_now" -gt 0 ]; then
  gt_get_all "$ep/discussions" > "$GT_API_TMP/disc.jsonlines"
fi
if [ "$n_replies_now" -eq 0 ]; then
  printf '{}' > "$GT_API_TMP/hintmap.json"
else
  python3 - "$GT_API_TMP/plan.json" "$GT_API_TMP/disc.jsonlines" "$GT_API_TMP/hintmap.json" "$GT_PREFIX" <<'PY'
import json, sys
plan = json.load(open(sys.argv[1], encoding="utf-8"))
disc = [json.loads(l) for l in open(sys.argv[2]) if l.strip()]
out, prefix = sys.argv[3], sys.argv[4]
# discussions with our original notes: first line per discussion for reports
ours = {}
for d in disc:
    hits = []
    for n in d.get("notes") or []:
        if n.get("system"):
            continue
        body = n.get("body") or ""
        if body.startswith(prefix):
            first = body.splitlines()[0] if body.splitlines() else ""
            hits.append(first)
    if hits:
        ours[d.get("id", "?")] = hits
errors = []
hintmap = {}
for p in plan:
    if p["action"] == "new":
        continue
    hint = p["hint"]
    matches = {did: hits for did, hits in ours.items()
               if any(hint in h for h in hits)}
    if not matches:
        errors.append(f"  #{p['idx']} ({p['action']}): no discussion with an "
                      f"'{prefix.strip()} ...' note containing hint {hint!r}")
    elif len(matches) > 1:
        listing = "\n".join(f"    {did}: {hits[0][:100]}" for did, hits in sorted(matches.items()))
        errors.append(f"  #{p['idx']} ({p['action']}): hint {hint!r} matches "
                      f"{len(matches)} discussions - refine the hint:\n{listing}")
    else:
        did, hits = next(iter(matches.items()))
        p["did"] = did
        p["matched"] = hits[0]
        hintmap[p["idx"]] = did
# persist the resolved targets back into the plan for the later steps
json.dump(plan, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
json.dump(hintmap, open(out, "w", encoding="utf-8"))
if errors:
    print("reply target resolution failed:", file=sys.stderr)
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
PY
fi

# anchor validation for "new" items (like mr-comment.sh: refuse bad anchors;
# a missing clone is tolerated -> unpositioned, with a warning)
anchor_fail=0
if [ "$n_new" -gt 0 ]; then
  while IFS=$'\t' read -r idx p line old_side; do
    side="new"
    if [ "$old_side" = "True" ]; then side="old"; fi
    gt_check_anchor "$repo" "$p" "$line" "$side"
    case "$GT_ANCHOR_STATUS" in
      ok)
        printf '  #%s anchor %s:%s (%s) ok\n' "$idx" "$p" "$line" "$side" ;;
      no-repo)
        gt_warn "entry #$idx: no clone to validate $p:$line - the draft will be posted unpositioned" ;;
      not-in-diff)
        gt_warn "entry #$idx: path '$p' is not part of the MR diff ($GT_BASE..$GT_HEAD)"
        anchor_fail=$((anchor_fail + 1)) ;;
      out-of-hunk)
        gt_warn "entry #$idx: line $line ($side side) of '$p' is not inside any diff hunk ($GT_BASE..$GT_HEAD).
valid ranges for this path:
$(gt_ranges_summary "$GT_HUNKS_FILE")"
        anchor_fail=$((anchor_fail + 1)) ;;
    esac
  done < <(python3 -c '
import json, sys
plan = json.load(open(sys.argv[1], encoding="utf-8"))
for x in plan:
    if x["action"] == "new":
        print("\t".join(map(str, (x["idx"], x["path"], x["line"], x["old_side"]))))
' "$GT_API_TMP/plan.json")
fi
if [ "$anchor_fail" -gt 0 ]; then
  gt_die "$anchor_fail 'new' item(s) have invalid anchors - nothing will be written; fix the verdicts or use mr-comment.sh --force"
fi

# ---- 4) the plan (always printed in full before any write) ----------------
echo "== plan =="
python3 - "$GT_API_TMP/plan.json" <<'PY'
import json, sys
plan = json.load(open(sys.argv[1], encoding="utf-8"))
for p in plan:
    if p["action"] == "new":
        side = "old" if p["old_side"] else "new"
        print(f"#{p['idx']} new      -> draft on {p['path']}:{p['line']} ({side} side)")
    else:
        print(f"#{p['idx']} {p['action']:<9}-> reply into discussion {p['did']}")
        print(f"   hint matched: {p['matched'][:120]}")
    print(f"   body: {p['body']}")
    print()
PY
n_replies="$(python3 -c '
import json, sys
plan = json.load(open(sys.argv[1], encoding="utf-8"))
print(sum(1 for p in plan if p["action"] != "new"))
' "$GT_API_TMP/plan.json")"

if [ -n "$emit" ] && [ "$post" != 1 ]; then
  d="$(dirname "$emit")"
  [ -z "$d" ] || [ "$d" = "." ] || mkdir -p "$d"
  python3 - "$GT_API_TMP/plan.json" "$emit" <<'PY'
import json, sys
plan = json.load(open(sys.argv[1], encoding="utf-8"))
batch = []
for p in plan:
    if p["action"] == "new":
        batch.append({"path": p["path"], "line": p["line"], "body": p["body"],
                      "old_side": p["old_side"]})
    else:
        batch.append({"reply_to_discussion_id": p["did"], "body": p["body"]})
open(sys.argv[2], "w", encoding="utf-8").write(
    json.dumps(batch, ensure_ascii=False, indent=2) + "\n")
PY
  echo "== batch written: $emit =="
  echo "   ($n_replies reply/replies, $n_new new) - apply it later with:"
  echo "     mr-draft-review.sh <project> <mr_iid> $emit"
  echo "   (reply items post immediately during that run; draft items stay private"
  echo "   unless --publish is passed)"
  exit 0
fi

if [ "$yes" != 1 ]; then
  echo "== plan only: nothing was posted (pass --yes to post, or --emit <file> to write a batch) =="
  exit 0
fi

# ---- 5) post: replies via mr-reply.sh, "new" via the draft flow -----------
reply_fail=0
posted_replies=0
for idx_did in $(python3 -c '
import json, sys
plan = json.load(open(sys.argv[1], encoding="utf-8"))
for p in plan:
    if p["action"] != "new":
        print(str(p["idx"]) + ":" + p["did"])
' "$GT_API_TMP/plan.json"); do
  idx="${idx_did%%:*}"; did="${idx_did#*:}"
  bf="$GT_API_TMP/reply-body.$idx.txt"
  python3 - "$GT_API_TMP/plan.json" "$idx" > "$bf" <<'PY'
import json, sys
plan = {p["idx"]: p for p in json.load(open(sys.argv[1], encoding="utf-8"))}
print(plan[int(sys.argv[2])]["body"], end="")
PY
  echo "-- entry #$idx: replying into discussion $did (via mr-reply.sh)"
  if "$SCRIPT_DIR/mr-reply.sh" "$proj" "$iid" "$did" "@$bf"; then
    posted_replies=$((posted_replies + 1))
  else
    gt_warn "entry #$idx: reply into discussion $did FAILED"
    reply_fail=$((reply_fail + 1))
  fi
done
if [ "$reply_fail" -gt 0 ]; then
  gt_die "$reply_fail reply item(s) failed - no drafts were created; fix and re-run"
fi

if [ "$n_new" -gt 0 ]; then
  batch="$GT_API_TMP/new-items.batch.json"
  python3 - "$GT_API_TMP/plan.json" "$batch" <<'PY'
import json, sys
plan = json.load(open(sys.argv[1], encoding="utf-8"))
batch = [{"path": p["path"], "line": p["line"], "body": p["body"], "old_side": p["old_side"]}
         for p in plan if p["action"] == "new"]
open(sys.argv[2], "w", encoding="utf-8").write(json.dumps(batch, ensure_ascii=False, indent=2))
PY
  echo
  echo "-- creating $n_new draft(s) via mr-draft-review.sh (--ignore-stray: this tool never publishes, stale drafts are harmless here)"
  draft_args=("$SCRIPT_DIR/mr-draft-review.sh" "$proj" "$iid" "$batch" --ignore-stray)
  if [ -n "$repo" ]; then draft_args+=(--repo "$repo"); fi
  if ! "${draft_args[@]}"; then
    gt_die "draft creation failed - the replies above are already posted"
  fi
fi
echo
echo "== done: $posted_replies reply/replies posted, $n_new draft(s) created (private; publish is a separate mr-draft-review.sh --publish run) =="
