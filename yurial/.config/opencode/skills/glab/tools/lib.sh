#!/usr/bin/env bash
# lib.sh - shared helpers for the gitlab-tools scripts (sourced by all of them).
#
# Instance traps baked in (self-managed GitLab 18.x-ee; default host
# gitlab.corp.mail.ru, override with GITLAB_HOST):
#
#   1. `glab api` exits 0 even on HTTP errors. Failures are detected from the
#      stderr line `glab: ... (HTTP <code>)` and/or from a response body that
#      holds only {"message":...} / {"error":...} keys (this also covers the
#      fake {"message":"500 Internal Server Error"} bodies that arrive while
#      the object WAS created - so write scripts verify by follow-up GET).
#   2. API responses (REST and GraphQL alike) mask 40-hex shas as
#      __SECRET_N__ placeholders. Real shas are recovered locally: the MR
#      head via the (unmasked) commits endpoint or git rev-parse of the
#      source branch, the merge-base via git merge-base with the target
#      branch / origin-main.
#   3. List endpoints default to 20/30 records, so every listing goes through
#      --paginate with per_page=100 in the URL (glab 1.36 has no --per-page
#      flag). Pages arrive as concatenated JSON arrays on stdout and are
#      parsed with repeated json.JSONDecoder().raw_decode.
#   4. The MR /diffs endpoint returns most files with collapsed:true and an
#      empty diff, so hunk ranges are built locally with
#      `git diff --unified=0 <merge-base>..<head> -- <path>`.
#
# Output is plain text, no ANSI colors (NO_COLOR-safe by construction).

set -euo pipefail

# Optional config file next to lib.sh; it only fills unset/empty variables,
# so values already present in the environment are never clobbered
# (precedence: env > config.sh > built-in defaults below).
GT_TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$GT_TOOLS_DIR/config.sh" ]; then
  # shellcheck source=config.sh
  . "$GT_TOOLS_DIR/config.sh"
fi

GITLAB_HOST="${GITLAB_HOST:-gitlab.corp.mail.ru}"
GITLAB_REPO="${GITLAB_REPO:-}"
GITLAB_DEFAULT_PROJECT="${GITLAB_DEFAULT_PROJECT:-}"
# location-independent default: markers live next to the toolkit (<tools>/.state)
GITLAB_TOOLS_STATE_DIR="${GITLAB_TOOLS_STATE_DIR:-$GT_TOOLS_DIR/.state}"
export GITLAB_HOST GITLAB_DEFAULT_PROJECT GITLAB_TOOLS_STATE_DIR
GT_PREFIX="AI generated: "

GT_API_TMP="$(mktemp -d "${TMPDIR:-/tmp}/gt-api.XXXXXX")"
trap 'rm -rf "$GT_API_TMP"' EXIT

gt_die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
gt_warn() { printf 'WARN: %s\n' "$*" >&2; }
gt_note() { printf 'NOTE: %s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# Low-level API access
# ---------------------------------------------------------------------------

# gt_api METHOD ENDPOINT [glab-api-args...]
# Runs one `glab api` call; never aborts on HTTP errors (glab exits 0 anyway).
# Sets: GT_RC, GT_BODY (response file), GT_ERR (stderr file),
#       GT_HTTP_CODE (code parsed from stderr, "0" when none seen).
gt_api() {
  local method="$1"; shift
  GT_BODY="$GT_API_TMP/body"
  GT_ERR="$GT_API_TMP/err"
  set +e
  glab api --hostname "$GITLAB_HOST" --method "$method" "$@" >"$GT_BODY" 2>"$GT_ERR"
  GT_RC=$?
  set -e
  GT_HTTP_CODE="0"
  local m
  m="$(grep -oE '\(HTTP [0-9]{3}\)' "$GT_ERR" | tail -n 1 | grep -oE '[0-9]{3}' || true)"
  if [ -n "$m" ]; then GT_HTTP_CODE="$m"; fi
  return 0
}

# gt_json_items FILE - parse plain or concatenated JSON (the --paginate trap),
# print one canonical JSON document per line (top-level arrays flattened).
# Tolerates readers that exit early (BrokenPipeError -> exit 0, so a
# `set -o pipefail` pipeline is not killed when a filter cuts the stream).
gt_json_items() {
  python3 - "$1" <<'PY'
import json, os, sys
try:
    text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
    dec = json.JSONDecoder()
    i, n = 0, len(text)
    while i < n:
        while i < n and text[i] in " \t\r\n":
            i += 1
        if i >= n:
            break
        obj, i = dec.raw_decode(text, i)
        if isinstance(obj, list):
            for item in obj:
                print(json.dumps(item, ensure_ascii=False))
        else:
            print(json.dumps(obj, ensure_ascii=False))
    sys.stdout.flush()
except BrokenPipeError:
    try:
        devnull = os.open(os.devnull, os.O_WRONLY)
        os.dup2(devnull, sys.stdout.fileno())
    except Exception:
        pass
    sys.exit(0)
PY
}

# gt_try_get ENDPOINT OUTFILE [glab-args...] - like gt_get but returns 1
# instead of dying (for optional fetches); canonical items go to OUTFILE.
gt_try_get() {
  local endpoint="$1" out="$2"; shift 2
  gt_api GET "$endpoint" "$@"
  if [ "$GT_RC" -ne 0 ] || [ "$GT_HTTP_CODE" != "0" ]; then return 1; fi
  if gt_body_is_error "$GT_BODY"; then return 1; fi
  gt_json_items "$GT_BODY" > "$out"
}

# gt_body_is_error FILE - exit 0 iff every parsed document is a JSON object
# whose keys are only "message"/"error" (GitLab error payload shape,
# including the misleading {"message":"500 Internal Server Error"}).
gt_body_is_error() {
  python3 - "$1" <<'PY'
import json, sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read().strip()
if not text:
    sys.exit(1)
dec = json.JSONDecoder()
i, n, docs = 0, len(text), []
try:
    while i < n:
        while i < n and text[i] in " \t\r\n":
            i += 1
        if i >= n:
            break
        obj, i = dec.raw_decode(text, i)
        docs.append(obj)
except Exception:
    sys.exit(1)
if not docs:
    sys.exit(1)
ok = all(isinstance(d, dict) and d and set(d.keys()) <= {"message", "error"} for d in docs)
sys.exit(0 if ok else 1)
PY
}

# gt_get ENDPOINT [glab-args...] - single GET; dies on any detected failure
# (stderr HTTP code, glab rc, or error-shaped body); prints one canonical
# JSON item per line.
gt_get() {
  local endpoint="$1"; shift
  gt_api GET "$endpoint" "$@"
  if [ "$GT_RC" -ne 0 ]; then
    gt_die "GET $endpoint failed (rc=$GT_RC): $(tr -d '\n' <"$GT_ERR" | tail -c 300)"
  fi
  if [ "$GT_HTTP_CODE" != "0" ]; then
    gt_die "GET $endpoint -> HTTP $GT_HTTP_CODE: $(tr -d '\n' <"$GT_ERR" | tail -c 300)"
  fi
  if gt_body_is_error "$GT_BODY"; then
    gt_die "GET $endpoint returned an error body: $(tr -d '\n' <"$GT_BODY" | tail -c 300)"
  fi
  gt_json_items "$GT_BODY"
}

# gt_get_all ENDPOINT [glab-args...] - paginated GET. per_page=100 goes into
# the URL (glab 1.36 has no --per-page flag); --paginate walks all pages.
gt_get_all() {
  local endpoint="$1"; shift
  local sep='?'
  if [[ "$endpoint" == *\?* ]]; then sep='&'; fi
  gt_get "${endpoint}${sep}per_page=100" --paginate "$@"
}

# gt_post_json ENDPOINT PAYLOAD_FILE - raw-JSON POST. Deliberately does NOT
# decide success: on this instance a POST can answer rc=0 with an error body
# while the object was created. Callers must check GT_RC/GT_HTTP_CODE/
# gt_body_is_error AND verify with a follow-up GET.
gt_post_json() {
  local endpoint="$1" file="$2"; shift 2
  gt_api POST "$endpoint" --input "$file" -H "Content-Type: application/json" "$@"
}

gt_urlencode() {
  python3 -c 'import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

gt_is_sha() { [[ "${1:-}" =~ ^[0-9a-f]{40}$ ]]; }
GT_ISO_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}[Tt ][0-9]{2}:[0-9]{2}'
gt_is_iso() { [[ "${1:-}" =~ $GT_ISO_RE ]]; }

# gt_body_from_arg ARG - echo the body given as a literal or @file (or @-).
gt_body_from_arg() {
  case "$1" in
    @-) cat ;;
    @*) [ -f "${1#@}" ] || gt_die "body file not found: ${1#@}"; cat "${1#@}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# gt_prefix_ok BODY NO_PREFIX_FLAG(0|1) - 0 when the body may be posted.
gt_prefix_ok() {
  if [ "$2" = "1" ]; then return 0; fi
  [[ "$1" == "$GT_PREFIX"* ]]
}

gt_prefix_error() {
  printf 'refusing to post: every posted comment must start with "%s"\n' "$GT_PREFIX"
  printf 'add the prefix to the body, or pass --no-prefix to skip this check\n'
}

# ---------------------------------------------------------------------------
# Local git helpers (read-only unless the caller opts into a fetch)
# ---------------------------------------------------------------------------

# gt_git_dir - print a usable git toplevel (GITLAB_REPO, else cwd upward);
# empty string when none.
gt_git_dir() {
  local start="${GITLAB_REPO:-$PWD}" t
  if t="$(git -C "$start" rev-parse --show-toplevel 2>/dev/null)"; then
    printf '%s\n' "$t"
  fi
}

# gt_git_sha REPO REF - full sha for REF (also resolves short ids), empty
# when unknown.
gt_git_sha() {
  git -C "$1" rev-parse --verify --quiet "${2}^{commit}" 2>/dev/null || true
}

# gt_lsremote_head REPO BRANCH - current sha of refs/heads/<branch> on
# `origin` via git ls-remote: a network READ that writes nothing to the
# clone, and it bypasses the instance's sha masking entirely (plain git
# protocol). Disable with GT_LSREMOTE=0.
gt_lsremote_head() {
  local repo="$1" branch="$2" s=""
  if [ "${GT_LSREMOTE:-1}" != "1" ]; then return 0; fi
  if command -v timeout >/dev/null 2>&1; then
    s="$(timeout 15 git -C "$repo" ls-remote origin "refs/heads/$branch" 2>/dev/null | awk 'NR==1{print $1}' || true)"
  else
    s="$(git -C "$repo" ls-remote origin "refs/heads/$branch" 2>/dev/null | awk 'NR==1{print $1}' || true)"
  fi
  if [ -n "$s" ]; then printf '%s\n' "$s"; fi
}

# ---------------------------------------------------------------------------
# MR loading and sha recovery
# ---------------------------------------------------------------------------

# gt_load_mr ENCODED_PROJECT IID - fills GT_MR_* from the single-MR endpoint.
gt_load_mr() {
  local enc="$1" iid="$2" f="$GT_API_TMP/mr.fields"
  gt_get "projects/$enc/merge_requests/$iid" > "$GT_API_TMP/mr.json"
  python3 - "$GT_API_TMP/mr.json" > "$f" <<'PY'
import json, sys
mr = json.loads(open(sys.argv[1]).readline())
dr = mr.get("diff_refs") or {}
vals = [
    mr.get("source_branch") or "",
    mr.get("target_branch") or "",
    dr.get("base_sha") or "",
    dr.get("start_sha") or "",
    dr.get("head_sha") or "",
    mr.get("sha") or "",
    mr.get("web_url") or "",
    mr.get("state") or "",
    "yes" if mr.get("draft") else "no",
    mr.get("updated_at") or "",
]
print("\n".join(vals))
PY
  local l
  mapfile -t l < "$f"
  GT_MR_SRC_BRANCH="${l[0]}"
  GT_MR_TGT_BRANCH="${l[1]}"
  GT_MR_API_BASE="${l[2]}"
  GT_MR_API_START="${l[3]}"
  GT_MR_API_HEAD="${l[4]}"
  GT_MR_API_SHA="${l[5]}"
  GT_MR_URL="${l[6]}"
  GT_MR_STATE="${l[7]}"
  GT_MR_DRAFT="${l[8]}"
  GT_MR_UPDATED="${l[9]}"
}

# gt_recover_base REPO TARGET_BRANCH HEAD_SHA - merge-base of HEAD_SHA with
# the target branch (falls back to origin/main / origin/master).
gt_recover_base() {
  local repo="$1" target="$2" head="$3" ref b
  for ref in "origin/$target" origin/main origin/master; do
    if [ -n "$(gt_git_sha "$repo" "$ref")" ]; then
      b="$(git -C "$repo" merge-base "$ref" "$head" 2>/dev/null || true)"
      if [ -n "$b" ]; then printf '%s\n' "$b"; return 0; fi
    fi
  done
  return 1
}

# gt_resolve_shas REPO ENCODED_PROJECT IID
# Sets GT_BASE / GT_START / GT_HEAD (real 40-hex shas). Head-recovery ladder
# (the API masks 40-hex shas as __SECRET_N__, per-response and flakily, but
# leaves short_id alone):
#   1. GT_HEAD_SHA env override
#   2. commits endpoint `id` when it arrives unmasked
#   3. commits endpoint `short_id` resolved locally (git rev-parse)
#   4. git ls-remote origin <source branch> (fresh, never masked)
#   5. local refs: origin/<branch>, then refs/heads/<branch>
# base: git merge-base of the target branch (origin/<target>, then
# origin/main, origin/master) with the head / local source tip; start = base.
# Dies with a clear message when masking meets no usable clone.
gt_resolve_shas() {
  local repo="$1" enc="$2" iid="$3"
  gt_load_mr "$enc" "$iid"

  GT_HEAD="${GT_HEAD_SHA:-}"
  local head_short=""
  if [ -z "$GT_HEAD" ]; then
    if gt_try_get "projects/$enc/merge_requests/$iid/commits?per_page=1" "$GT_API_TMP/commits1.jsonlines"; then
      { read -r GT_HEAD; read -r head_short; } < <(python3 -c '
import json, sys
try:
    c = json.loads(open(sys.argv[1]).readline())
except Exception:
    c = {}
print(c.get("id", ""))
print(c.get("short_id", ""))
' "$GT_API_TMP/commits1.jsonlines")
    fi
  fi
  if ! gt_is_sha "$GT_HEAD" && [ -n "$head_short" ] && [ -n "$repo" ]; then
    GT_HEAD="$(gt_git_sha "$repo" "$head_short")"
  fi
  if ! gt_is_sha "$GT_HEAD" && [ -n "$repo" ]; then
    GT_HEAD="$(gt_lsremote_head "$repo" "$GT_MR_SRC_BRANCH")"
  fi
  if ! gt_is_sha "$GT_HEAD" && [ -n "$repo" ]; then
    GT_HEAD="$(gt_git_sha "$repo" "origin/$GT_MR_SRC_BRANCH")"
  fi
  if ! gt_is_sha "$GT_HEAD" && [ -n "$repo" ]; then
    GT_HEAD="$(gt_git_sha "$repo" "refs/heads/$GT_MR_SRC_BRANCH")"
  fi
  if ! gt_is_sha "$GT_HEAD"; then
    gt_die "cannot recover the MR head sha: the API masks shas (got '${GT_MR_API_HEAD:-?}'), and no clone is available to resolve the commit short_id / run git ls-remote.
run from inside a clone of the project (or pass --repo <dir> / set GITLAB_REPO)"
  fi

  GT_BASE="${GT_BASE_SHA:-}"
  if [ -z "$GT_BASE" ] && [ -n "$repo" ]; then
    GT_BASE="$(gt_recover_base "$repo" "$GT_MR_TGT_BRANCH" "$GT_HEAD" || true)"
    if [ -z "$GT_BASE" ]; then
      # head may be newer than the clone; merge the local source branch tip
      local src_tip
      src_tip="$(gt_git_sha "$repo" "origin/$GT_MR_SRC_BRANCH")"
      if [ -n "$src_tip" ]; then
        GT_BASE="$(gt_recover_base "$repo" "$GT_MR_TGT_BRANCH" "$src_tip" || true)"
      fi
    fi
  fi
  if ! gt_is_sha "$GT_BASE"; then
    gt_die "cannot recover the base sha: the API masks diff_refs ($GT_MR_API_BASE) and no local merge-base with origin/$GT_MR_TGT_BRANCH (or origin/main) is available.
run from inside an up-to-date clone (git fetch origin main $GT_MR_SRC_BRANCH),
or pass --repo <dir> / set GITLAB_REPO / set GT_BASE_SHA explicitly"
  fi

  GT_START="${GT_START_SHA:-}"
  [ -n "$GT_START" ] || GT_START="$GT_BASE"

  if ! gt_is_sha "$GT_MR_API_HEAD"; then
    gt_note "API shas masked (e.g. $GT_MR_API_HEAD); recovered locally: base=$GT_BASE start=$GT_START head=$GT_HEAD"
  fi
}

# ---------------------------------------------------------------------------
# Hunk ranges (the /diffs endpoint collapses most files -> build locally)
# ---------------------------------------------------------------------------

# gt_hunks REPO BASE_SHA HEAD_SHA PATH - print hunk line ranges, one per line:
#   new FROM TO  /  old FROM TO   (inclusive)
# Hints: the real MR diff runs merge-base..head; start_sha on this instance
# is the target-branch tip and would drag in unrelated target-side changes.
gt_hunks() {
  local repo="$1" base="$2" head="$3" path="$4"
  git -C "$repo" diff --unified=0 "$base..$head" -- "$path" | python3 -c '
import re, sys
pat = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")
for line in sys.stdin:
    m = pat.match(line)
    if not m:
        continue
    a = int(m.group(1)); b = int(m.group(2)) if m.group(2) is not None else 1
    c = int(m.group(3)); d = int(m.group(4)) if m.group(4) is not None else 1
    if b > 0:
        print("old", a, a + b - 1)
    if d > 0:
        print("new", c, c + d - 1)
'
}

# gt_ranges_in FILE SIDE LINE - 0 iff LINE is inside a SIDE range.
gt_ranges_in() {
  local file="$1" side="$2" line="$3" s f t
  while read -r s f t; do
    if [ "$s" = "$side" ] && [ "$line" -ge "$f" ] && [ "$line" -le "$t" ]; then
      return 0
    fi
  done < "$file"
  return 1
}

# gt_ranges_summary FILE - human-readable range list for error messages.
gt_ranges_summary() {
  local file="$1" s f t new="" old=""
  while read -r s f t; do
    if [ "$s" = "new" ]; then new="$new $f-$t"; else old="$old $f-$t"; fi
  done < "$file"
  printf '  new side:%s\n' "${new:- (none)}"
  printf '  old side:%s\n' "${old:- (none)}"
}

# gt_diff_head REPO - best locally available head commit for hunk building:
# GT_HEAD when the clone has it, else the local source-branch tip (with a
# staleness warning). Empty when the clone cannot help at all.
gt_diff_head() {
  local repo="$1" tip
  if [ -n "$(gt_git_sha "$repo" "$GT_HEAD")" ]; then
    printf '%s\n' "$GT_HEAD"
    return 0
  fi
  tip="$(gt_git_sha "$repo" "origin/$GT_MR_SRC_BRANCH")"
  if [ -z "$tip" ]; then
    tip="$(gt_git_sha "$repo" "refs/heads/$GT_MR_SRC_BRANCH")"
  fi
  if [ -n "$tip" ]; then
    gt_warn "local clone lacks MR head $GT_HEAD (stale fetch); validating hunks against local tip $tip - run 'git fetch origin $GT_MR_SRC_BRANCH' in the clone for exact validation"
    printf '%s\n' "$tip"
  fi
}

# gt_check_anchor REPO PATH LINE SIDE
# Sets GT_ANCHOR_STATUS: ok | not-in-diff | out-of-hunk | no-repo
# Fills GT_HUNKS_FILE with the ranges (may be empty). When the true MR head
# is missing locally (stale clone), falls back to the local source-branch tip
# for the range computation and warns.
gt_check_anchor() {
  local repo="$1" path="$2" line="$3" side="$4"
  GT_HUNKS_FILE="$GT_API_TMP/hunks"
  GT_ANCHOR_STATUS="no-repo"
  if [ -z "$repo" ]; then
    gt_warn "no git clone available: the anchor cannot be validated locally; a bad anchor is rejected by GitLab with HTTP 400"
    return 0
  fi
  local diff_head
  diff_head="$(gt_diff_head "$repo")"
  if [ -z "$diff_head" ]; then
    gt_warn "local clone lacks MR head $GT_HEAD and no local '$GT_MR_SRC_BRANCH' ref found; anchor not validated"
    GT_ANCHOR_STATUS="no-repo"
    return 0
  fi
  GT_ANCHOR_STATUS="ok"
  gt_hunks "$repo" "$GT_BASE" "$diff_head" "$path" > "$GT_HUNKS_FILE" \
    || gt_die "git diff failed for '$path' (is $GT_BASE..$diff_head available in $repo?)"
  if [ ! -s "$GT_HUNKS_FILE" ]; then
    GT_ANCHOR_STATUS="not-in-diff"
    return 0
  fi
  if ! gt_ranges_in "$GT_HUNKS_FILE" "$side" "$line"; then
    GT_ANCHOR_STATUS="out-of-hunk"
  fi
}

# ---------------------------------------------------------------------------
# GraphQL
# ---------------------------------------------------------------------------

# gt_graphql QUERY_FILE [VARIABLES_JSON_FILE] - POST to the GraphQL endpoint
# (--input keeps JSON types intact; -f would stringify nested variables).
# Sets GT_* like gt_api; callers must inspect the body for {"errors": [...]}.
gt_graphql() {
  local qfile="$1" vars="${2:-}" payload="$GT_API_TMP/gql-payload.json"
  python3 - "$qfile" "$vars" "$payload" <<'PY'
import json, sys
payload = {"query": open(sys.argv[1]).read()}
if sys.argv[2]:
    payload["variables"] = json.load(open(sys.argv[2]))
open(sys.argv[3], "w").write(json.dumps(payload))
PY
  gt_api POST graphql --input "$payload" -H "Content-Type: application/json"
}

gt_graphql_errors() {
  python3 - "$GT_BODY" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
for e in data.get("errors") or []:
    print(e.get("message", str(e)))
PY
}
