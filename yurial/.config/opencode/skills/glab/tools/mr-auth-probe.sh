#!/usr/bin/env bash
# mr-auth-probe.sh - live token-health probe: the mechanical form of the
# live-probe rule (SKILL.md section 15: `glab auth status` output is a hint,
# never a verdict - only a live API call decides whether the token works).
#
# usage: mr-auth-probe.sh [host]
#
#   host   optional positional: the host to probe for THIS invocation
#          (overrides GITLAB_HOST; when omitted the host resolves per the
#          shared runtime contract: environment > config.sh > built-in
#          default)
#
# Performs exactly ONE API call - GET `user` - through the gt_api machinery
# of lib.sh, so the `glab api` rc=0-on-HTTP-error trap is neutralized
# centrally (failures are detected from the stderr HTTP line and the
# error-shaped body, never from the glab exit code).
#
# Exit codes:
#   0  the call answered 200; stdout carries exactly "ok <username>"
#   1  the probe failed (an HTTP error, 401 first of all, or a network
#      failure); a stderr diagnostic line names the host and the HTTP code
#      (or the network error)
#   2  usage error
#
# GET-only: no writes, no clone, no state files. Token values are never
# read, echoed, or stored - the script only interprets the API answer.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  cat >&2 <<'EOF'
usage: mr-auth-probe.sh [host]

  host   target host for this invocation (default: GITLAB_HOST >
         config.sh > built-in default)
EOF
  exit 2
}

die_usage() { printf 'ERROR: %s\n' "$*" >&2; usage; }

host=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage ;;
    -*) die_usage "unknown option: $1" ;;
    *) if [ -z "$host" ]; then host="$1"
       else die_usage "unexpected argument: $1"
       fi ;;
  esac
  shift
done
# the optional [host] positional selects the target host for this invocation
[ -z "$host" ] || GITLAB_HOST="$host"

# exactly one API call; never abort on HTTP errors (glab exits 0 anyway)
gt_api GET user

fail() {
  printf 'ERROR: auth probe failed for host %s: %s\n' "$GITLAB_HOST" "$1" >&2
  exit 1
}

if [ "$GT_RC" -ne 0 ]; then
  fail "network failure (rc=$GT_RC): $(tr -d '\n' <"$GT_ERR" | tail -c 200)"
fi
if [ "$GT_HTTP_CODE" != "0" ]; then
  fail "HTTP $GT_HTTP_CODE: $(tr -d '\n' <"$GT_ERR" | tail -c 200)"
fi
if gt_body_is_error "$GT_BODY"; then
  fail "error body: $(tr -d '\n' <"$GT_BODY" | tail -c 200)"
fi

username="$(gt_json_items "$GT_BODY" | python3 -c '
import json, sys
try:
    u = json.loads(sys.stdin.readline()).get("username") or ""
except Exception:
    u = ""
print(u)
')"
[ -n "$username" ] || fail "the user payload carried no username field: $(tr -d '\n' <"$GT_BODY" | tail -c 200)"
printf 'ok %s\n' "$username"
