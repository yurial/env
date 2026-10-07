#!/usr/bin/env bash
# mr-reply.sh - reply into an existing MR discussion thread.
#
# usage: mr-reply.sh <project> <mr_iid> <discussion_id> <body-or-@file>
#                    [--no-prefix] [--dry-run]
#
# Traps handled:
#   * the REST reply route POST .../discussions/<id>/notes may answer 404,
#     and POST .../notes?in_reply_to_discussion_id=... is silently ignored
#     (the note lands outside the discussion) - so after any POST the note is
#     verified INSIDE the discussion by GET, and on 404/orphan the script
#     falls back to GraphQL createNote with
#     gid://gitlab/Discussion/<discussion_id>, then verifies again.
#   * every posted comment must start with "AI generated: " unless
#     --no-prefix is given.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  cat >&2 <<'EOF'
usage: mr-reply.sh <project> <mr_iid> <discussion_id> <body-or-@file>
                   [--no-prefix] [--dry-run]

  body-or-@file  reply text, or @path/to/file (or @- for stdin)
  --no-prefix    skip the mandatory "AI generated: " prefix check
  --dry-run      print the REST payload and the GraphQL fallback, post nothing
EOF
  exit 2
}

proj="" iid="" did="" bodyarg=""
no_prefix=0 dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --no-prefix) no_prefix=1 ;;
    --dry-run) dry=1 ;;
    -h|--help) usage ;;
    -*) gt_die "unknown option: $1" ;;
    *) if [ -z "$proj" ]; then proj="$1"
       elif [ -z "$iid" ]; then iid="$1"
       elif [ -z "$did" ]; then did="$1"
       elif [ -z "$bodyarg" ]; then bodyarg="$1"
       else gt_die "unexpected argument: $1"
       fi ;;
  esac
  shift
done
# <project> may be omitted when GITLAB_DEFAULT_PROJECT is configured
if [ -n "$did" ] && [ -z "$bodyarg" ] && [ -n "$proj" ] && [ -n "$iid" ] \
   && [ -n "$GITLAB_DEFAULT_PROJECT" ]; then
  bodyarg="$did"; did="$iid"; iid="$proj"; proj="$GITLAB_DEFAULT_PROJECT"
fi
[ -n "$proj" ] && [ -n "$iid" ] && [ -n "$did" ] && [ -n "$bodyarg" ] || usage

body_file="$GT_API_TMP/body.txt"
gt_body_from_arg "$bodyarg" > "$body_file"
body="$(cat "$body_file")"
if ! gt_prefix_ok "$body" "$no_prefix"; then
  gt_die "$(gt_prefix_error)"
fi

enc="$(gt_urlencode "$proj")"
ep="projects/$enc/merge_requests/$iid"

# sanity: the discussion must exist (GET is cheap and read-only)
gt_get "$ep/discussions/$did" > "$GT_API_TMP/disc.jsonlines" \
  || gt_die "discussion $did not found on $proj!$iid (GET failed)"
python3 - "$GT_API_TMP/disc.jsonlines" <<'PY'
import json, sys
d = json.loads(open(sys.argv[1]).readline())
notes = d.get("notes") or []
ns = [n for n in notes if not n.get("system")]
resolved = all(n.get("resolved") is True for n in ns) if ns else False
print(f"target discussion: {d.get('id')} | {len(ns)} note(s) | {'resolved' if resolved else 'unresolved'}", file=sys.stderr)
for n in ns[-2:]:
    who = (n.get("author") or {}).get("username", "?")
    print(f"  last: #{n.get('id')} {who}: {(n.get('body') or '')[:80]!r}", file=sys.stderr)
PY

payload="$GT_API_TMP/payload.json"
python3 - "$body_file" "$payload" <<'PY'
import json, sys
body = open(sys.argv[1], encoding="utf-8").read()
open(sys.argv[2], "w", encoding="utf-8").write(json.dumps({"body": body}, ensure_ascii=False))
PY

gql_query="$GT_API_TMP/gql.query"
gql_vars="$GT_API_TMP/gql.vars.json"
cat > "$gql_query" <<'EOF'
mutation($input: CreateNoteInput!) {
  createNote(input: $input) {
    note { id body discussion { id } }
    errors
  }
}
EOF

if [ "$dry" = 1 ]; then
  echo "== dry-run: nothing will be posted =="
  echo
  echo "attempt 1 (REST, may 404 on this instance):"
  echo "  POST https://$GITLAB_HOST/api/v4/$ep/discussions/$did/notes"
  cat "$payload"
  echo
  echo "attempt 2 (fallback, GraphQL createNote; needs the MR global id):"
  echo "  query: project(fullPath: \"$proj\") { mergeRequest(iid: \"$iid\") { id } }"
  echo "  mutation: $(tr -d '\n' <"$gql_query")"
  echo "  variables: {\"input\": {\"noteableId\": \"gid://gitlab/MergeRequest/<global_id>\", \"discussionId\": \"gid://gitlab/Discussion/$did\", \"body\": <see payload above>}}"
  exit 0
fi

reply_body_file="$body_file"

verify_inside() {
  # verify_inside -> prints note id if a note with our body sits inside $did
  gt_get "$ep/discussions/$did" > "$GT_API_TMP/verify.jsonlines" || return 1
  python3 - "$GT_API_TMP/verify.jsonlines" "$reply_body_file" <<'PY'
import json, sys
want = open(sys.argv[2], encoding="utf-8").read()
d = json.loads(open(sys.argv[1]).readline())
for n in d.get("notes") or []:
    if (n.get("body") or "") == want:
        print(n.get("id", ""))
        sys.exit(0)
sys.exit(1)
PY
}

# ---- attempt 1: REST discussions/<id>/notes ----------------------------
gt_post_json "$ep/discussions/$did/notes" "$payload"
rest_state="ok"
if { [ "$GT_RC" -ne 0 ] || [ "$GT_HTTP_CODE" != "0" ] || gt_body_is_error "$GT_BODY"; }; then
  rest_state="failed"
fi
note_id=""
if [ "$rest_state" = "ok" ]; then
  if note_id="$(verify_inside)"; then
    echo "replied + verified via REST: discussion $did, note $note_id"
    exit 0
  fi
  gt_note "REST POST looked successful but the note is NOT inside discussion $did
(this is the silent-orphan trap of in_reply_to_discussion_id on this instance) - falling back to GraphQL"
else
  gt_note "REST reply route failed (rc=$GT_RC, HTTP=$GT_HTTP_CODE, body: $(tr -d '\n' <"$GT_BODY" | tail -c 200)) - falling back to GraphQL"
fi

# ---- attempt 2: GraphQL createNote ------------------------------------
qfile="$GT_API_TMP/gid.query"
cat > "$qfile" <<'EOF'
query($p: ID!, $i: String!) {
  project(fullPath: $p) {
    mergeRequest(iid: $i) { id }
  }
}
EOF
printf '%s' "{\"p\":\"$proj\",\"i\":\"$iid\"}" > "$GT_API_TMP/gid.vars.json"
gt_graphql "$qfile" "$GT_API_TMP/gid.vars.json"
if [ "$GT_RC" -ne 0 ] || [ "$GT_HTTP_CODE" != "0" ]; then
  gt_die "GraphQL MR-id lookup failed (rc=$GT_RC, HTTP=$GT_HTTP_CODE): $(tr -d '\n' <"$GT_ERR" | tail -c 200)"
fi
mr_gid="$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
try:
    print(d["data"]["project"]["mergeRequest"]["id"])
except Exception:
    print("")
' "$GT_BODY")"
[ -n "$mr_gid" ] || gt_die "GraphQL MR-id lookup returned no id: $(head -c 300 "$GT_BODY")"

python3 - "$mr_gid" "$did" "$reply_body_file" "$gql_vars" <<'PY'
import json, sys
mr_gid, did = sys.argv[1], sys.argv[2]
body = open(sys.argv[3], encoding="utf-8").read()
vars = {"input": {
    "noteableId": mr_gid,
    "discussionId": f"gid://gitlab/Discussion/{did}",
    "body": body,
}}
open(sys.argv[4], "w").write(json.dumps(vars))
PY

gt_graphql "$gql_query" "$gql_vars"
if [ "$GT_RC" -ne 0 ] || [ "$GT_HTTP_CODE" != "0" ]; then
  gt_die "GraphQL createNote request failed (rc=$GT_RC, HTTP=$GT_HTTP_CODE): $(tr -d '\n' <"$GT_ERR" | tail -c 300)"
fi
gql_errs="$(gt_graphql_errors)"
if [ -n "$gql_errs" ]; then
  gt_die "GraphQL createNote returned errors:
$gql_errs"
fi

if note_id="$(verify_inside)"; then
  gql_note_id="$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
n = ((d.get("data") or {}).get("createNote") or {}).get("note") or {}
print(n.get("id", ""))
' "$GT_BODY")"
  echo "replied + verified via GraphQL: discussion $did, note $note_id (gql id: ${gql_note_id:-?})"
  exit 0
fi
gt_die "GraphQL createNote reported success but the note is not inside discussion $did after GET.
inspect the MR manually; GraphQL response was: $(tr -d '\n' <"$GT_BODY" | tail -c 300)"
