#!/usr/bin/env bash
# mr-resolve.sh - resolve or unresolve ONE discussion thread on a merge
# request via PUT .../discussions/<discussion_id>?resolved=true|false.
#
# usage: mr-resolve.sh <project> <mr_iid> <discussion_id> [--unresolve] [--dry-run]
#
# Guards (all decided by GET before any write):
#   * the discussion must exist (missing id -> refuse);
#   * the thread must contain resolvable notes (system-only or
#     non-resolvable discussions are refused);
#   * already in the requested state -> idempotent OK message, nothing sent.
# The PUT response is never trusted (this instance may answer rc=0 with a
# fake {"message":"500 ..."} body while the change WAS applied): the state is
# verified by a follow-up GET. --dry-run prints the current state and the
# exact request without sending anything. No batch mode by design: one call
# resolves one thread, so a mistake cannot scale.
# Every posted comment must start with "AI generated: " - not applicable
# here (no comment bodies are written), kept out on purpose.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  cat >&2 <<'EOF'
usage: mr-resolve.sh <project> <mr_iid> <discussion_id> [--unresolve] [--dry-run]

  --unresolve   unresolve the thread instead of resolving it
  --dry-run     print the current state and the request, send nothing
EOF
  exit 2
}

proj="" iid="" did=""
unresolve=0 dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --unresolve) unresolve=1 ;;
    --dry-run) dry=1 ;;
    -h|--help) usage ;;
    -*) gt_die "unknown option: $1" ;;
    *) if [ -z "$proj" ]; then proj="$1"
       elif [ -z "$iid" ]; then iid="$1"
       elif [ -z "$did" ]; then did="$1"
       else gt_die "unexpected argument: $1"
       fi ;;
  esac
  shift
done
# <project> may be omitted when GITLAB_DEFAULT_PROJECT is configured
if [ -n "$iid" ] && [ -z "$did" ] && [ -n "$GITLAB_DEFAULT_PROJECT" ]; then
  did="$iid"; iid="$proj"; proj="$GITLAB_DEFAULT_PROJECT"
fi
[ -n "$proj" ] && [ -n "$iid" ] && [ -n "$did" ] || usage

enc="$(gt_urlencode "$proj")"
ep="projects/$enc/merge_requests/$iid/discussions/$did"

# ---- current state (GET; doubles as the existence guard) ----------------
if ! gt_try_get "$ep" "$GT_API_TMP/disc.json"; then
  gt_die "discussion $did not found on $proj!$iid (GET failed) - nothing was changed"
fi
disc_fields="$GT_API_TMP/disc.fields"
python3 - "$GT_API_TMP/disc.json" > "$disc_fields" <<'PY'
import json, sys
d = json.loads(open(sys.argv[1]).readline())
ns = [n for n in d.get("notes") or [] if not n.get("system")]
res = [n for n in ns if n.get("resolvable")]
resolved = bool(res) and all(n.get("resolved") is True for n in res)
anchor = ""
for n in ns:
    p = n.get("position") or {}
    if p:
        path = p.get("new_path") or p.get("old_path") or "?"
        line = p.get("new_line") or p.get("old_line") or "?"
        anchor = f"{path}:{line}"
        break
orig = ""
for n in ns:
    lines = (n.get("body") or "").splitlines()
    orig = (lines[0] if lines else "")[:120]
    break
print(len(res))
print(1 if resolved else 0)
print(anchor)
print(orig)
PY
mapfile -t df < "$disc_fields"
resolvable_n="${df[0]}"; resolved_now="${df[1]}"; anchor="${df[2]}"; orig="${df[3]}"

if [ "$resolvable_n" -eq 0 ]; then
  gt_die "discussion $did has no resolvable notes - there is nothing to resolve/unresolve"
fi

state_now="unresolved"
if [ "$resolved_now" = "1" ]; then state_now="resolved"; fi
state_want="resolved"
value_want="true"
if [ "$unresolve" = "1" ]; then
  state_want="unresolved"
  value_want="false"
fi

echo "discussion:   $did"
echo "anchor:       ${anchor:-(no anchor)}"
echo "context:      ${orig:-(no non-system notes)}"
echo "resolvable:   $resolvable_n note(s)"
echo "state now:    $state_now"

if [ "$state_now" = "$state_want" ]; then
  echo "OK: discussion $did is already $state_now - nothing to do (idempotent)"
  exit 0
fi

if [ "$dry" = 1 ]; then
  echo "== dry-run: nothing will be sent =="
  echo "PUT https://$GITLAB_HOST/api/v4/$ep"
  echo "  body/form: resolved=$value_want   (equivalent: glab api -X PUT '$ep' -f resolved=$value_want)"
  exit 0
fi

gt_api PUT "$ep" -f "resolved=$value_want"
put_note=""
if [ "$GT_RC" -ne 0 ] || [ "$GT_HTTP_CODE" != "0" ] || gt_body_is_error "$GT_BODY"; then
  put_note=" (PUT answer looked like a failure: rc=$GT_RC, HTTP=$GT_HTTP_CODE, body: $(tr -d '\n' <"$GT_BODY" | tail -c 200)) - this instance sometimes answers a fake 500-in-body while the change IS applied; verifying by GET"
  gt_note "PUT answer looked like a failure (rc=$GT_RC, HTTP=$GT_HTTP_CODE) - verifying the state by GET"
fi

# ---- verify by GET (never trust the PUT response alone) ------------------
if ! gt_try_get "$ep" "$GT_API_TMP/after.json"; then
  gt_die "verify GET failed after the PUT - check the thread state manually$put_note"
fi
want_after=1
if [ "$unresolve" = "1" ]; then want_after=0; fi
after="$(python3 - "$GT_API_TMP/after.json" <<'PY'
import json, sys
d = json.loads(open(sys.argv[1]).readline())
res = [n for n in (d.get("notes") or []) if not n.get("system") and n.get("resolvable")]
print(1 if (res and all(n.get("resolved") is True for n in res)) else 0)
PY
)"
if [ "$after" = "$want_after" ]; then
  echo "OK: discussion $did is now $state_want (verified by GET)$put_note"
  exit 0
fi
gt_die "state of discussion $did did not change to $state_want after the PUT$put_note.
current state after GET: $([ "$after" = 1 ] && echo resolved || echo unresolved) - check the thread manually"
