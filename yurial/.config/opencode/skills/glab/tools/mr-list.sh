#!/usr/bin/env bash
# mr-list.sh - list merge requests by role across all accessible projects.
#
# usage: mr-list.sh [--role reviewer|author|assignee]
#                   [--state opened|closed|merged|all] [--draft|--no-draft]
#                   [--json] [--project <group/proj>] [--max N]
#
#   --role R        reviewer | author | assignee (default: reviewer)
#   --state S       opened | closed | merged | all (default: opened)
#   --draft         only draft MRs (work_in_progress / Draft:|WIP: title)
#   --no-draft      exclude draft MRs
#   --json          print a normalized JSON array (updated_at desc) instead
#                   of the text blocks; the count line goes to stderr
#   --project P     restrict to one project, <group>/<project> (exact match
#                   on the project path of references.full; the global
#                   endpoint returns no project object, only project_id;
#                   default: all accessible projects)
#   --max N         show at most N MRs, newest updates first
#
# The scenario behind the defaults: "which MRs await my review" - the global
# merge_requests endpoint queried by the CURRENT user's role (the username
# comes from a live `glab api user` call). scope=all is MANDATORY in every
# request: without it the endpoint silently defaults to created_by_me and
# returns only the caller's own MRs (SKILL.md section 5, the scope=all
# trap). Pagination runs per_page=100 + --paginate (lib.sh, glab 1.36 has
# no --per-page flag), concatenated page arrays parsed with repeated
# raw_decode. GET-only: no writes, no clone needed. Host per the toolkit
# convention: environment > config.sh > built-in default (lib.sh).
#
# Exit codes: 0 success (an empty result is a success with an info line),
# 1 failure (API error / unparsable response), 2 usage error (bad --role /
# --state / --max value, unknown option).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  cat >&2 <<'EOF'
usage: mr-list.sh [--role reviewer|author|assignee] [--state opened|closed|merged|all]
                  [--draft|--no-draft] [--json] [--project <group/proj>] [--max N]
EOF
  exit 2
}

arg_error() { printf 'ERROR: %s\n' "$*" >&2; usage; }

role="reviewer" state="opened" draft_mode="any" json=0 project="" max_n=0
while [ $# -gt 0 ]; do
  case "$1" in
    --role) [ $# -ge 2 ] || arg_error "--role needs a value"; role="$2"; shift ;;
    --state) [ $# -ge 2 ] || arg_error "--state needs a value"; state="$2"; shift ;;
    --draft) draft_mode="only" ;;
    --no-draft) draft_mode="exclude" ;;
    --json) json=1 ;;
    --project) [ $# -ge 2 ] || arg_error "--project needs a value"; project="$2"; shift ;;
    --max) [ $# -ge 2 ] || arg_error "--max needs a value"; max_n="$2"; shift
           { [[ "$max_n" =~ ^[0-9]+$ ]] && [ "$max_n" -ge 1 ]; } \
             || arg_error "--max expects a positive number, got: $max_n" ;;
    -h|--help) usage ;;
    -*) arg_error "unknown option: $1" ;;
    *) arg_error "unexpected argument: $1 (mr-list.sh takes options only)" ;;
  esac
  shift
done
case "$role" in
  reviewer|author|assignee) ;;
  *) arg_error "bad role '$role' (expected reviewer|author|assignee)" ;;
esac
case "$state" in
  opened|closed|merged|all) ;;
  *) arg_error "bad state '$state' (expected opened|closed|merged|all)" ;;
esac

# the role filters of the global endpoint take a username: use the current
# user (the live /user call doubles as the token-health probe)
username="$(gt_get user | python3 -c '
import json, sys
try:
    print(json.loads(sys.stdin.readline()).get("username") or "")
except Exception:
    print("")
')"
[ -n "$username" ] || gt_die "cannot determine the current user (glab api user returned no username)"

# scope=all is MANDATORY: without it the global merge_requests endpoint
# silently defaults to created_by_me and returns only the caller's own MRs
# (SKILL.md section 5, the scope=all trap)
gt_get_all "merge_requests?${role}_username=${username}&state=${state}&scope=all" \
  > "$GT_API_TMP/mrlist.jsonlines"

python3 - "$GT_API_TMP/mrlist.jsonlines" "$username" "$role" "$state" \
         "$draft_mode" "$project" "$max_n" "$json" <<'PY'
import json, sys

path, username, role, state = sys.argv[1:5]
draft_mode, project = sys.argv[5], sys.argv[6]
max_n, json_out = int(sys.argv[7]), sys.argv[8] == "1"

# dedupe by id (belt and braces over concatenated --paginate pages)
items = {}
for line in open(path, encoding="utf-8"):
    if not line.strip():
        continue
    mr = json.loads(line)
    items[mr.get("id")] = mr
mrs = list(items.values())

# the project path of an MR: the global endpoint carries no project object,
# but references.full is always "<group/project>!<iid>"
def proj_path(m):
    full = (m.get("references") or {}).get("full") or ""
    return full.rsplit("!", 1)[0] if "!" in full else ""

if project:
    mrs = [m for m in mrs if proj_path(m) == project]

def is_draft(m):
    if m.get("work_in_progress"):
        return True
    title = (m.get("title") or "").lstrip()
    return title.startswith(("Draft:", "WIP:", "draft:", "wip:"))

if draft_mode == "only":
    mrs = [m for m in mrs if is_draft(m)]
elif draft_mode == "exclude":
    mrs = [m for m in mrs if not is_draft(m)]

mrs.sort(key=lambda m: m.get("updated_at") or "", reverse=True)
if max_n > 0:
    mrs = mrs[:max_n]

def descr():
    parts = [f"role={role}({username})", f"state={state}"]
    if project:
        parts.append(f"project={project}")
    if draft_mode == "only":
        parts.append("drafts only")
    elif draft_mode == "exclude":
        parts.append("no drafts")
    if max_n > 0:
        parts.append(f"max={max_n}")
    return ", ".join(parts)

if json_out:
    print(json.dumps(mrs, ensure_ascii=False, indent=2))
    print(f"-- {len(mrs)} merge request(s): {descr()}", file=sys.stderr)
else:
    if not mrs:
        print(f"(no merge requests match: {descr()})")
    for m in mrs:
        refs = m.get("references") or {}
        full = refs.get("full") or \
            f"{(m.get('project') or {}).get('path_with_namespace', '?')}!{m.get('iid', '?')}"
        draft = " [DRAFT]" if is_draft(m) else ""
        updated = (m.get("updated_at") or "")[:10]
        author = (m.get("author") or {}).get("username", "?")
        print(f"== {full} =={draft} updated {updated} by {author}")
        print(f"   title: {m.get('title') or ''}")
        print(f"   url:   {m.get('web_url') or ''}")
    if mrs:
        print(f"-- {len(mrs)} merge request(s): {descr()}")
PY
