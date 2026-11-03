#!/usr/bin/env bash
# mr-threads.sh - dump MR discussions as readable text.
#
# usage: mr-threads.sh <project> <mr_iid> [--open|--all] [--ai-only]
#                      [--no-system] [--max-chars N] [--full] [--repo <dir>]
#
#   --open          only unresolved threads (default)
#   --all           all discussions, resolved included
#   --ai-only       only discussions containing a note that starts with the
#                   configured comment prefix (GITLAB_COMMENT_PREFIX,
#                   default "[ai] ")
#   --no-system     drop notes with system:true from the dump; a thread
#                   consisting only of system notes is not printed at all
#                   (CI-bot progress comments bury the human review threads
#                   otherwise); the count line keeps its meaning - under
#                   --no-system the system-only threads drop out of the
#                   shown count
#   --max-chars N   truncate note bodies to N chars (default 400)
#   --full          never truncate
#   --repo DIR      accepted for interface uniformity (this script needs no
#                   clone; clone is configured via GITLAB_REPO env or
#                   config.sh)
#
# A thread counts resolved iff every non-system note has resolved:true (the
# instance-independent rule; the resolved state of a printed thread is
# always computed over its non-system notes, with or without --no-system).
# Traps handled: pagination (per_page=100 + --paginate), concatenated page
# arrays parsed with repeated raw_decode, error detection without relying on
# the glab exit code.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  cat >&2 <<'EOF'
usage: mr-threads.sh <project> <mr_iid> [--open|--all] [--ai-only] [--no-system]
                     [--max-chars N] [--full] [--repo <dir>]

  --no-system  drop system notes; system-only threads are not printed
  --repo DIR   accepted for interface uniformity (no clone needed;
               clone is configured via GITLAB_REPO env or config.sh)
EOF
  exit 2
}

die_usage() { printf 'ERROR: %s\n' "$*" >&2; usage; }

proj="" iid="" repo_arg=""
mode="open" ai_only=0 no_system=0 max_chars=400
while [ $# -gt 0 ]; do
  case "$1" in
    --open) mode="open" ;;
    --all) mode="all" ;;
    --ai-only) ai_only=1 ;;
    --no-system) no_system=1 ;;
    --max-chars) [ $# -ge 2 ] || die_usage "--max-chars needs a value"; max_chars="$2"; shift
                 [[ "$max_chars" =~ ^[0-9]+$ ]] || die_usage "--max-chars expects a number" ;;
    --full) max_chars=-1 ;;
    --repo) [ $# -ge 2 ] || die_usage "--repo needs a directory"; repo_arg="$2"; shift ;;
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
# --repo is validated everywhere it is accepted, even though this script
# makes no clone use of the value (R12.4)
gt_repo_arg_ok "$repo_arg" || die_usage "--repo: no such directory: $repo_arg"

enc="$(gt_urlencode "$proj")"
gt_get_all "projects/$enc/merge_requests/$iid/discussions" > "$GT_API_TMP/disc.jsonlines"

python3 - "$GT_API_TMP/disc.jsonlines" "$mode" "$ai_only" "$no_system" "$max_chars" \
         "$GT_PREFIX" <<'PY'
import json, sys

path = sys.argv[1]
mode = sys.argv[2]
ai_only = sys.argv[3] == "1"
no_system = sys.argv[4] == "1"
max_chars = int(sys.argv[5])
PREFIX = sys.argv[6]

def truncate(s):
    if max_chars < 0 or len(s) <= max_chars:
        return s
    return s[:max_chars] + f" ... [+{len(s) - max_chars} chars, use --full]"

def anchor_of(notes):
    for n in notes:
        pos = n.get("position") or {}
        if not pos:
            continue
        p = pos.get("new_path") or pos.get("old_path") or "?"
        lr = pos.get("line_range")
        if isinstance(lr, dict):
            s, e = lr.get("start") or {}, lr.get("end") or {}
            if s.get("new_line") and e.get("new_line"):
                return f"{p}:{s['new_line']}-{e['new_line']} (new side)"
            if s.get("old_line") and e.get("old_line"):
                return f"{p}:{s['old_line']}-{e['old_line']} (old side)"
        if pos.get("new_line"):
            return f"{p}:{pos['new_line']} (new side)"
        if pos.get("old_line"):
            return f"{p}:{pos['old_line']} (old side)"
    return None

items = [json.loads(l) for l in open(path) if l.strip()]
total = len(items)
shown = 0
for d in items:
    all_notes = d.get("notes") or []
    # the resolved state is ALWAYS computed over the non-system notes
    non_system = [n for n in all_notes if not n.get("system")]
    if no_system:
        notes = non_system  # system notes dropped from the dump entirely
        if not notes:
            continue  # a system-only thread is not printed at all
    else:
        notes = all_notes  # the default dump includes the system notes
    resolved = all(n.get("resolved") is True for n in non_system) if non_system else True
    if mode == "open" and resolved:
        continue
    if ai_only and not any((n.get("body") or "").startswith(PREFIX) for n in non_system):
        continue
    shown += 1
    did = d.get("id", "?")
    individual = " individual" if d.get("individual_note") else ""
    authors = ", ".join(dict.fromkeys((n.get("author") or {}).get("username", "?") for n in notes))
    resolvable_n = sum(1 for n in non_system if n.get("resolvable"))
    tag = "RESOLVED" if resolved else "UNRESOLVED"
    print(f"== discussion {did} == {tag}{individual} ({len(notes)} notes, {resolvable_n} resolvable)")
    a = anchor_of(notes)
    if a:
        print(f"   anchor : {a}")
    print(f"   authors: {authors}")
    for n in sorted(notes, key=lambda x: x.get("id") or 0):
        who = (n.get("author") or {}).get("username", "?")
        flags = []
        if n.get("system"):
            flags.append("system")
        if n.get("resolvable"):
            flags.append("resolved" if n.get("resolved") else "unresolved")
        if (n.get("body") or "").startswith(PREFIX):
            flags.append("AI")
        fl = (" [" + ",".join(flags) + "]") if flags else ""
        print(f"   --- note #{n.get('id', '?')} {n.get('created_at', '')} {who}{fl}")
        body = truncate(n.get("body") or "")
        for bl in body.splitlines() or [""]:
            print(f"       {bl}")
    print()

print(f"-- shown {shown} of {total} discussions "
      f"(mode={mode}, ai_only={ai_only}, no_system={no_system}, max_chars={max_chars})")
PY
