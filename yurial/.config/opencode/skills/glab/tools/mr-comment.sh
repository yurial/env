#!/usr/bin/env bash
# mr-comment.sh - post ONE line-anchored comment on a merge request.
#
# usage: mr-comment.sh <project> <mr_iid> <path> <line> <body-or-@file>
#                      [--old-side] [--no-prefix] [--force] [--dry-run]
#                      [--repo <dir>]
#
# Traps handled:
#   * diff_refs shas are masked (__SECRET_N__): the head sha is taken from
#     the unmasked commits endpoint, the merge-base is recovered locally
#     with git; without a clone the script fails with a clear message.
#   * the /diffs endpoint collapses most files, so the line is validated
#     against hunk ranges built locally with
#     `git diff --unified=0 <merge-base>..<head> -- <path>`; anchors outside
#     hunks get HTTP 400 from GitLab and are refused here unless --force.
#   * a POST may answer rc=0 with {"message":"500 Internal Server Error"}
#     while the note WAS created - creation is verified by a follow-up GET,
#     never by the POST response alone.
#   * every posted comment must start with "AI generated: " unless
#     --no-prefix is given.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  cat >&2 <<'EOF'
usage: mr-comment.sh <project> <mr_iid> <path> <line> <body-or-@file>
                     [--old-side] [--no-prefix] [--force] [--dry-run]
                     [--repo <dir>]

  path           repo-relative file path exactly as in the MR diff
  line           line number (new side by default; old side with --old-side)
  body-or-@file  comment text, or @path/to/file (or @- for stdin)

options:
  --old-side    anchor on the old (removed) line
  --no-prefix   skip the mandatory "AI generated: " prefix check
  --force       if the anchor is invalid, post unpositioned with the body
                prefixed by "path:line" instead of refusing
  --dry-run     print the exact payload (incl. position) and do not POST
  --repo DIR    clone used for sha recovery / hunk building
                (default: GITLAB_REPO or the clone containing $PWD)
EOF
  exit 2
}

proj="" iid="" path="" line="" bodyarg="" repo_arg=""
old_side=0 no_prefix=0 force=0 dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --old-side) old_side=1 ;;
    --no-prefix) no_prefix=1 ;;
    --force) force=1 ;;
    --dry-run) dry=1 ;;
    --repo) [ $# -ge 2 ] || usage; repo_arg="$2"; shift ;;
    -h|--help) usage ;;
    -*) gt_die "unknown option: $1" ;;
    *) if [ -z "$proj" ]; then proj="$1"
       elif [ -z "$iid" ]; then iid="$1"
       elif [ -z "$path" ]; then path="$1"
       elif [ -z "$line" ]; then line="$1"
       elif [ -z "$bodyarg" ]; then bodyarg="$1"
       else gt_die "unexpected argument: $1"
       fi ;;
  esac
  shift
done
# <project> may be omitted when GITLAB_DEFAULT_PROJECT is configured
if [ -n "$line" ] && [ -z "$bodyarg" ] && [ -n "$proj" ] && [ -n "$iid" ] && [ -n "$path" ] \
   && [ -n "$GITLAB_DEFAULT_PROJECT" ]; then
  bodyarg="$line"; line="$path"; path="$iid"; iid="$proj"; proj="$GITLAB_DEFAULT_PROJECT"
fi
[ -n "$proj" ] && [ -n "$iid" ] && [ -n "$path" ] && [ -n "$line" ] && [ -n "$bodyarg" ] || usage
[[ "$line" =~ ^[0-9]+$ ]] || gt_die "<line> must be a positive integer, got: $line"
side="new"; if [ "$old_side" = 1 ]; then side="old"; fi

body_file="$GT_API_TMP/body.txt"
gt_body_from_arg "$bodyarg" > "$body_file"
body="$(cat "$body_file")"
if ! gt_prefix_ok "$body" "$no_prefix"; then
  gt_die "$(gt_prefix_error)"
fi

enc="$(gt_urlencode "$proj")"
repo="$repo_arg"
[ -n "$repo" ] || repo="$GITLAB_REPO"
[ -n "$repo" ] || repo="$(gt_git_dir)"
gt_resolve_shas "$repo" "$enc" "$iid"
gt_check_anchor "$repo" "$path" "$line" "$side"

positioned=1
prepend=""
case "$GT_ANCHOR_STATUS" in
  ok) : ;;
  no-repo)
    positioned=0
    prepend="$path:$line

"
    gt_note "posting unpositioned (no local clone to build hunk ranges); body will be prefixed with '$path:$line'" ;;
  not-in-diff)
    if [ "$force" != 1 ]; then
      gt_die "path '$path' is not part of the MR diff ($GT_BASE..$GT_HEAD).
list changed paths:  git -C <repo> diff --name-only $GT_BASE..$GT_HEAD
pass --force to post an unpositioned comment (body prefixed with '$path:$line')"
    fi
    positioned=0
    prepend="$path:$line

" ;;
  out-of-hunk)
    if [ "$force" != 1 ]; then
      gt_die "line $line ($side side) of '$path' is not inside any diff hunk ($GT_BASE..$GT_HEAD).
GitLab rejects anchors outside hunks with HTTP 400. Valid ranges for this path:
$(gt_ranges_summary "$GT_HUNKS_FILE")
pick a line inside a hunk, or pass --force to post unpositioned (body prefixed with '$path:$line')"
    fi
    positioned=0
    prepend="$path:$line

" ;;
esac

payload="$GT_API_TMP/payload.json"
final_body="$GT_API_TMP/body.final"
python3 - "$body_file" "$payload" "$final_body" "$path" "$line" "$old_side" "$positioned" \
         "$GT_BASE" "$GT_START" "$GT_HEAD" "$prepend" "$GT_PREFIX" <<'PY'
import json, sys
(src, out, out_body, path, line, old_side, positioned, base, start, head, prepend, prefix) = sys.argv[1:]
line = int(line)
old_side = old_side == "1"
positioned = positioned == "1"
body = open(src, encoding="utf-8").read()
if prepend:
    if body.startswith(prefix):
        body = prefix + prepend + body[len(prefix):]
    else:
        body = prepend + body
payload = {"body": body}
if positioned:
    pos = {
        "position_type": "text",
        "base_sha": base,
        "start_sha": start,
        "head_sha": head,
        "old_path": path,
        "new_path": path,
    }
    if old_side:
        pos["old_line"] = line
    else:
        pos["new_line"] = line
    payload["position"] = pos
open(out, "w", encoding="utf-8").write(json.dumps(payload, ensure_ascii=False))
open(out_body, "w", encoding="utf-8").write(body)
PY

ep="projects/$enc/merge_requests/$iid/discussions"
if [ "$dry" = 1 ]; then
  echo "== dry-run: nothing will be posted =="
  echo "POST https://$GITLAB_HOST/api/v4/$ep"
  echo "Content-Type: application/json"
  echo "anchor: $path:$line ($side side) | status: $GT_ANCHOR_STATUS | positioned: $positioned"
  echo "shas: base=$GT_BASE start=$GT_START head=$GT_HEAD"
  echo
  python3 -m json.tool "$payload"
  exit 0
fi

gt_post_json "$ep" "$payload"
resp_state="ok"
if { [ "$GT_RC" -ne 0 ] || [ "$GT_HTTP_CODE" != "0" ] || gt_body_is_error "$GT_BODY"; }; then
  resp_state="suspicious"
  gt_note "POST answer looked like a failure (rc=$GT_RC, HTTP=$GT_HTTP_CODE, body: $(tr -d '\n' <"$GT_BODY" | tail -c 200)).
this instance sometimes answers {\"message\":\"500 Internal Server Error\"} while the note IS
created - verifying with a follow-up GET before declaring failure."
fi

# verify by GET (never trust the POST response alone)
disc_id="$(gt_json_items "$GT_BODY" | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.readline() or "{}")
except Exception:
    d = {}
print(d.get("id", "") if isinstance(d, dict) else "")
' || true)"

found=""
if [ -n "$disc_id" ]; then
  gt_get "projects/$enc/merge_requests/$iid/discussions/$disc_id" > "$GT_API_TMP/verify.jsonlines" || found=""
else
  gt_get_all "projects/$enc/merge_requests/$iid/discussions" > "$GT_API_TMP/verify.jsonlines"
fi
found="$(python3 - "$GT_API_TMP/verify.jsonlines" "$final_body" "$path" "$line" "$old_side" "$positioned" <<'PY'
import json, sys
want = open(sys.argv[2], encoding="utf-8").read()
path, line, old_side, positioned = sys.argv[3], int(sys.argv[4]), sys.argv[5] == "1", sys.argv[6] == "1"
for line_ in open(sys.argv[1]):
    if not line_.strip():
        continue
    d = json.loads(line_)
    for n in d.get("notes") or []:
        if (n.get("body") or "") != want:
            continue
        if positioned:
            p = n.get("position") or {}
            if p.get("new_path") != path:
                continue
            if old_side and p.get("old_line") != line:
                continue
            if not old_side and p.get("new_line") != line:
                continue
        print(json.dumps({"discussion": d.get("id", ""), "note": n.get("id", "")}))
        sys.exit(0)
sys.exit(0)
PY
)"

if [ -z "$found" ]; then
  gt_die "could not verify the comment after POST (POST state: $resp_state).
the note was not found by a follow-up GET of the discussions - check the MR manually.
POST body was: $(tr -d '\n' <"$payload" | tail -c 300)"
fi

disc="$(printf '%s' "$found" | python3 -c 'import json,sys; print(json.loads(sys.stdin.readline())["discussion"])')"
note="$(printf '%s' "$found" | python3 -c 'import json,sys; print(json.loads(sys.stdin.readline())["note"])')"
extra=""
if [ "$resp_state" = "suspicious" ]; then
  extra=" (POST reply was an error body, but the note is confirmed via GET - the 500-in-body trap)"
fi
echo "posted + verified: discussion $disc, note $note, anchor $path:$line ($side side)$extra"
