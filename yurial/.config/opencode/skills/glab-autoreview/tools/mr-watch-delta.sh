#!/usr/bin/env bash
# mr-watch-delta.sh - supervisor gate: fire only on a real registry delta
# (or the heartbeat reification), never on an API failure.
#
# usage: mr-watch-delta.sh [--project <group/proj>] [--registry <file>]
#                          [--state <file>] [--force-interval <30m|12h|2d|0>]
#
#   --project P         group/project; required unless GITLAB_DEFAULT_PROJECT
#                       is set (env > glab tools config.sh > usage error)
#   --registry F        watcher registry; default ~/tmp/mr-watch/registry.md
#   --state F           fire marker: the epoch of the last fire; default
#                       <this dir>/.state/mr-watch-delta.state (created on
#                       demand; content that is not an integer falls back to
#                       the file mtime, so hand-backdating via `touch -d`
#                       works); written atomically, on every fire only
#   --force-interval D  heartbeat: fire with no delta when the last fire is
#                       older than D - 30m, 12h, 2d; 0 (and any zero
#                       duration) disables; default 12h
#
# The supervisor gate of the glab-autoreview skill (SKILL.md section 2).
# Runs the read-only reviewer listing through the glab tools mr-list.sh
# (scope=all and pagination built in; the path resolves relative to this
# script: glab-autoreview/tools/../../glab/tools/), parses the registry,
# and fires - exit 0 - only when:
#   NEW        an open MR represented in no registry section (an entry in
#              ANY section - drafts parked in closed/archived included -
#              keeps the MR known and silent);
#   GONE       a watched MR (watching section, state pending-launch or
#              watching) missing from the open listing - the supervisor
#              confirms the terminal state and completes the watcher;
#   HEARTBEAT  no delta for --force-interval - the periodic reification of
#              a consistent-looking world (a missing marker counts as
#              "never fired").
# A missing or empty registry is bootstrap: every open MR is NEW.
#
# The fire stdout (the wakeup payload): the delta block - one line per
# trigger, HEARTBEAT only when it fires alone - then the compact fresh
# listing rendered here, one line per MR
#   !<iid> [DRAFT] <title> (<source> -> <target>, updated <YYYY-MM-DD>)
# and the trailing count line; the marker is updated with the current
# epoch. The iid comes from the JSON `iid` field of `mr-list.sh --json`
# (the same objects that back the `== <project>!<iid> ==` text blocks;
# references.full is the fallback).
#
# Exit codes:
#   0  fire (delta and/or heartbeat; stdout as above)
#   1  no delta - one stderr line with the watching/opened counts and the
#      next heartbeat; also every no-fire skip: mr-list failed (a nonzero
#      rc or unparsable JSON), or an empty open listing while the registry
#      has watchers - mr-list filters --project client-side and exits 0 on
#      an unknown project, and a project typo or a partial API answer must
#      not look like a mass closure. Every skip prints
#      `mr-watch-delta: mr-list failed, skipping fire` on stderr (mr-list
#      diagnostics pass through); the delta is never lost, the next good
#      run catches it.
#   2  usage error
#
# Read-only: no GitLab traffic beyond the mr-list.sh GET listing; the
# registry is never written; no git clone, no sleep.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../glab/tools/lib.sh
. "$SCRIPT_DIR/../../glab/tools/lib.sh"

MR_LIST_SH="$SCRIPT_DIR/../../glab/tools/mr-list.sh"

show_usage() {
  cat >&2 <<'EOF'
usage: mr-watch-delta.sh [--project <group/proj>] [--registry <file>]
                         [--state <file>] [--force-interval <30m|12h|2d|0>]

  --project P         group/project; required unless GITLAB_DEFAULT_PROJECT
                      is set (env > glab tools config.sh)
  --registry F        watcher registry (default ~/tmp/mr-watch/registry.md)
  --state F           fire marker: epoch of the last fire (default
                      <this dir>/.state/mr-watch-delta.state, created on
                      demand; non-integer content falls back to file mtime)
  --force-interval D  heartbeat reification interval (30m, 12h, 2d; 0
                      disables; default 12h)
EOF
}

usage() { show_usage; exit 2; }
arg_error() { printf 'ERROR: %s\n' "$*" >&2; usage; }

project="" registry="$HOME/tmp/mr-watch/registry.md"
state_file="$SCRIPT_DIR/.state/mr-watch-delta.state" interval="12h"
while [ $# -gt 0 ]; do
  case "$1" in
    --project) [ $# -ge 2 ] || arg_error "--project needs a value"; project="$2"; shift ;;
    --registry) [ $# -ge 2 ] || arg_error "--registry needs a path"; registry="$2"; shift ;;
    --state) [ $# -ge 2 ] || arg_error "--state needs a path"; state_file="$2"; shift ;;
    --force-interval) [ $# -ge 2 ] || arg_error "--force-interval needs a duration"; interval="$2"; shift ;;
    -h|--help) show_usage; exit 0 ;;
    -*) arg_error "unknown option: $1" ;;
    *) arg_error "unexpected argument: $1" ;;
  esac
  shift
done

[ -n "$project" ] || project="${GITLAB_DEFAULT_PROJECT:-}"
[ -n "$project" ] || arg_error "--project is required when GITLAB_DEFAULT_PROJECT is not set"

interval_secs=0
if [ "$interval" != "0" ]; then
  if [[ "$interval" =~ ^([0-9]+)(m|h|d)$ ]]; then
    n="${BASH_REMATCH[1]}"
    case "${BASH_REMATCH[2]}" in
      m) interval_secs=$((n * 60)) ;;
      h) interval_secs=$((n * 3600)) ;;
      d) interval_secs=$((n * 86400)) ;;
    esac
  else
    arg_error "--force-interval expects <N>m, <N>h, <N>d, or 0, got: $interval"
  fi
fi
# a computed zero duration (0, 00m, ...) disables the heartbeat
[ "$interval_secs" -gt 0 ] || interval_secs=0

# 1. the fresh listing. Any failure of mr-list is a no-fire: the delta is
#    not lost, the next successful run catches it.
list_rc=0
"$MR_LIST_SH" --role reviewer --state opened --json --project "$project" \
  >"$GT_API_TMP/list.json" 2>"$GT_API_TMP/list.err" || list_rc=$?
if [ "$list_rc" -ne 0 ]; then
  cat "$GT_API_TMP/list.err" >&2
  printf 'mr-watch-delta: mr-list failed, skipping fire\n' >&2
  exit 1
fi

py_rc=0
python3 - "$GT_API_TMP/list.json" "$registry" "$state_file" "$project" \
          "$interval_secs" <<'PY' || py_rc=$?
import json, os, re, sys, time

list_path, registry_path, state_path, project = sys.argv[1:5]
interval_s = int(sys.argv[5])
now = int(time.time())

ENTRY = re.compile(r"^\s*-\s*!(\d+)\s*-")


def hum(sec):
    sec = max(0, int(sec))
    if sec >= 86400:
        return f"~{max(1, round(sec / 86400))}d"
    if sec >= 3600:
        return f"~{max(1, round(sec / 3600))}h"
    return f"~{max(1, round(sec / 60))}m"


# ---- 1. the fresh listing (validated JSON or no fire) -----------------------

try:
    with open(list_path, encoding="utf-8", errors="replace") as fh:
        mrs = json.load(fh)
except Exception:
    sys.exit(3)  # unparsable JSON: bash prints the mr-list-failed line
if not isinstance(mrs, list):
    sys.exit(3)


def is_draft(m):  # the same rule as mr-list.sh text blocks
    if m.get("work_in_progress"):
        return True
    title = (m.get("title") or "").lstrip()
    return title.startswith(("Draft:", "WIP:", "draft:", "wip:"))


open_iids = set()
listing = []
for m in mrs:
    iid = m.get("iid")
    if not isinstance(iid, int):
        full = (m.get("references") or {}).get("full") or ""
        tail = full.rsplit("!", 1)[-1] if "!" in full else ""
        iid = int(tail) if tail.isdigit() else None
    if iid is None:
        continue
    open_iids.add(iid)
    draft = " [DRAFT]" if is_draft(m) else ""
    src = m.get("source_branch") or "?"
    tgt = m.get("target_branch") or "?"
    updated = (m.get("updated_at") or "")[:10]
    listing.append(f"!{iid}{draft} {m.get('title') or ''} "
                   f"({src} -> {tgt}, updated {updated})")

# ---- 2. the registry --------------------------------------------------------

represented = set()   # "- !<iid> -" anywhere: known, never NEW
watched = set()       # watching section, state pending-launch|watching
try:
    if os.path.exists(registry_path):
        with open(registry_path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    else:
        text = ""
except OSError as exc:
    print(f"mr-watch-delta: registry unreadable ({exc}), skipping fire",
          file=sys.stderr)
    sys.exit(1)

if not text.strip():
    pass  # bootstrap: a missing or empty registry makes every open MR NEW
else:
    in_watching = False
    for line in text.splitlines():
        if line.startswith("##"):
            in_watching = line[2:].strip().lower().startswith("watching")
            continue
        m = ENTRY.match(line)
        if not m:
            continue
        iid = int(m.group(1))
        represented.add(iid)
        if in_watching:
            state_val = line[m.end():].split("(", 1)[0].strip()
            if state_val.startswith(("pending-launch", "watching")):
                watched.add(iid)

# ---- 3. suspect-answer guard ------------------------------------------------
# mr-list filters --project client-side and exits 0 on an unknown project:
# an empty listing while the registry has watchers is a typo or a partial
# answer, never a mass closure.

if not open_iids and watched:
    print(f"NOTE: empty opened listing while the registry watches "
          f"{len(watched)} MR(s); a project typo or a partial answer must "
          f"not fire a mass GONE", file=sys.stderr)
    sys.exit(4)

# ---- 4. the delta -----------------------------------------------------------

new_iids = sorted(open_iids - represented)
gone_iids = sorted(watched - open_iids)

# ---- 5. the heartbeat -------------------------------------------------------

heartbeat = False
hb_reason = ""
last_fire = None
if interval_s > 0:
    if os.path.exists(state_path):
        try:
            with open(state_path, encoding="utf-8", errors="replace") as fh:
                content = fh.read().strip()
            last_fire = int(content) if content.isdigit() else None
        except OSError:
            last_fire = None
        if last_fire is None:  # non-integer content: the mtime fallback
            try:
                last_fire = int(os.stat(state_path).st_mtime)
            except OSError:
                last_fire = None
    if last_fire is None:
        heartbeat = True
        hb_reason = "no marker yet - treated as never fired"
    else:
        age = now - last_fire
        if age >= interval_s:
            heartbeat = True
            hb_reason = f"last fire {hum(age)} ago (interval {hum(interval_s)})"

# ---- 6. the verdict ---------------------------------------------------------

if new_iids or gone_iids or heartbeat:
    out = []
    if new_iids:
        out.append("NEW: " + ", ".join(f"!{i}" for i in new_iids))
    if gone_iids:
        out.append("GONE: " + ", ".join(f"!{i}" for i in gone_iids))
    if heartbeat and not new_iids and not gone_iids:
        out.append("HEARTBEAT: " + hb_reason)
    print("\n".join(out))
    print()
    for line in listing:
        print(line)
    print(f"-- {len(open_iids)} merge request(s): "
          f"role=reviewer, state=opened, project={project}")
    try:
        directory = os.path.dirname(state_path)
        if directory:
            os.makedirs(directory, exist_ok=True)
        tmp = state_path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write(f"{now}\n")
        os.replace(tmp, state_path)
    except OSError as exc:
        print(f"WARN: cannot write the marker {state_path}: {exc}",
              file=sys.stderr)
    sys.exit(0)

if interval_s > 0:
    remaining = interval_s - (now - last_fire)
    tail = f"next heartbeat in {hum(remaining)}"
else:
    tail = "heartbeat off"
print(f"mr-watch-delta: no delta (watching={len(watched)}, "
      f"opened={len(open_iids)}, {tail})", file=sys.stderr)
sys.exit(1)
PY
case "$py_rc" in
  0) exit 0 ;;
  1) exit 1 ;;
  3) printf 'mr-watch-delta: mr-list failed, skipping fire\n' >&2; exit 1 ;;
  4) cat "$GT_API_TMP/list.err" >&2
     printf 'mr-watch-delta: mr-list failed, skipping fire\n' >&2; exit 1 ;;
  *) gt_die "internal error: unexpected python rc=$py_rc" ;;
esac
