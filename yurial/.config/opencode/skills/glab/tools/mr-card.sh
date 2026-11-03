#!/usr/bin/env bash
# mr-card.sh - print the MR card: the mechanical "view one MR" step of the
# watcher loop (raw `glab mr view` remains the interactive project-scoped
# path).
#
# usage: mr-card.sh <project> <mr_iid> [--json] [--full] [--repo <dir>]
#
#   <project>   group/project path (omit when GITLAB_DEFAULT_PROJECT is set)
#   <mr_iid>    MR iid within the project
#   --json      one normalized JSON object with the same fields (diffstat as
#               an object of files/insertions/deletions); NOTE lines go to
#               stderr so stdout stays parseable
#   --full      print the description whole (default: truncated to 400 chars,
#               the thread-truncate convention of mr-threads.sh)
#   --repo DIR  clone used for the head-sha ladder and the diffstat
#               (clone is configured via GITLAB_REPO env or config.sh)
#
# Fields: title with a [DRAFT] mark, state, work_in_progress, author,
# reviewers, approved_by (the approvals endpoint), blocking_discussions_resolved,
# detailed_merge_status + legacy merge_status, branches, the recovered head
# sha with its provenance (the masked-sha ladder: commits-endpoint id ->
# short_id resolved locally -> git ls-remote -> local refs), changes_count,
# the description (truncated), plus the local diffstat of
# <merge-base>..<head>. Without a clone the card is still printed, without
# the diffstat, with an explicit NOTE (the degrade-and-say-so pattern).
#
# GET-only plus read-only clone use - nothing is fetched or written. Exit
# codes per the shared contract: 0 success, 1 failure (a missing
# project/MR included, with the HTTP diagnostics on stderr), 2 usage error.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  cat >&2 <<'EOF'
usage: mr-card.sh <project> <mr_iid> [--json] [--full] [--repo <dir>]

  --json      normalized JSON object instead of the text block
  --full      print the description whole (default: 400 chars)
  --repo DIR  clone for the head-sha ladder / diffstat
              (clone is configured via GITLAB_REPO env or config.sh)
EOF
  exit 2
}

die_usage() { printf 'ERROR: %s\n' "$*" >&2; usage; }

proj="" iid="" repo_arg=""
json=0 max_chars=400
while [ $# -gt 0 ]; do
  case "$1" in
    --json) json=1 ;;
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
[[ "$iid" =~ ^[0-9]+$ ]] || die_usage "<mr_iid> must be numeric, got: $iid"
gt_repo_arg_ok "$repo_arg" || die_usage "--repo: no such directory: $repo_arg"
repo="$(gt_repo_pick "$repo_arg")"

enc="$(gt_urlencode "$proj")"
mr_ep="projects/$enc/merge_requests/$iid"

# ---- GETs: the single-MR endpoint + approvals + head commit ---------------
gt_get "$mr_ep" > "$GT_API_TMP/card.mr.json"
gt_get "$mr_ep/approvals" > "$GT_API_TMP/card.appr.json" || true
if ! gt_try_get "$mr_ep/commits?per_page=1" "$GT_API_TMP/card.commits.jsonl"; then
  : > "$GT_API_TMP/card.commits.jsonl"
fi

# ---- fields from the single-MR endpoint ------------------------------------
python3 - "$GT_API_TMP/card.mr.json" > "$GT_API_TMP/card.fields" <<'PY'
import json, sys
mr = json.loads(open(sys.argv[1]).readline())
vals = [
    mr.get("title") or "",
    mr.get("state") or "",
    "yes" if mr.get("draft") else "no",
    "yes" if mr.get("work_in_progress") else "no",
    (mr.get("author") or {}).get("username") or "",
    ", ".join(sorted((r or {}).get("username") or "" for r in mr.get("reviewers") or [])),
    mr.get("blocking_discussions_resolved"),
    mr.get("detailed_merge_status") or "",
    mr.get("merge_status") or "",
    mr.get("source_branch") or "",
    mr.get("target_branch") or "",
    (mr.get("diff_refs") or {}).get("head_sha") or "",
    mr.get("changes_count") if mr.get("changes_count") is not None else "",
    mr.get("web_url") or "",
    mr.get("updated_at") or "",
]
print("\n".join(str(v) if not isinstance(v, bool) else ("true" if v else "false") for v in vals))
PY
mapfile -t f < "$GT_API_TMP/card.fields"
mr_title="${f[0]}"; mr_state="${f[1]}"; mr_draft="${f[2]}"; mr_wip="${f[3]}"
mr_author="${f[4]}"; mr_reviewers="${f[5]}"; mr_blocking="${f[6]}"
mr_dms="${f[7]}"; mr_ms="${f[8]}"; src_branch="${f[9]}"; tgt_branch="${f[10]}"
api_head="${f[11]}"; changes_count="${f[12]}"; mr_url="${f[13]}"; mr_updated="${f[14]}"

approved_by="$(python3 - "$GT_API_TMP/card.appr.json" <<'PY'
import json, sys
try:
    a = json.loads(open(sys.argv[1]).readline())
except Exception:
    a = {}
print(", ".join(sorted((x.get("user") or {}).get("username") or ""
                       for x in a.get("approved_by") or [])))
PY
)"

# ---- the masked-sha ladder for the head (R13.8) ---------------------------
head_sha=""; head_short=""; head_src=""
if [ -s "$GT_API_TMP/card.commits.jsonl" ]; then
  python3 - "$GT_API_TMP/card.commits.jsonl" > "$GT_API_TMP/card.head.fields" <<'PY'
import json, sys
try:
    c = json.loads(open(sys.argv[1]).readline())
except Exception:
    c = {}
print(c.get("id", ""))
print(c.get("short_id", ""))
PY
  mapfile -t hf < "$GT_API_TMP/card.head.fields"
  if gt_is_sha "${hf[0]:-}"; then
    head_sha="${hf[0]}"; head_src="commits endpoint"
  fi
  head_short="${hf[1]:-}"
fi
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
if ! gt_is_sha "$head_sha"; then
  head_sha="$api_head"
  head_src="API diff_refs (masked)"
fi

# ---- local diffstat <merge-base>..<head> (read-only clone use) ------------
# When the clone lacks the true MR head (stale fetch), the diffstat degrades
# to the local source-branch tip with a loud warning - the established
# fallback of the hunk validators (R13.8); the provenance line still names
# the recovered head above.
diffstat_file="$GT_API_TMP/card.diffstat"
base_sha=""
diff_head=""
if [ -n "$repo" ] && gt_is_sha "$head_sha" && [ "$head_src" != "API diff_refs (masked)" ]; then
  diff_head="$head_sha"
  if [ -z "$(gt_git_sha "$repo" "$head_sha")" ]; then
    local_tip="$(gt_git_sha "$repo" "origin/$src_branch")"
    [ -n "$local_tip" ] || local_tip="$(gt_git_sha "$repo" "refs/heads/$src_branch")"
    if [ -n "$local_tip" ]; then
      diff_head="$local_tip"
      gt_warn "local clone lacks MR head $head_sha (stale fetch); diffstat computed against the local source-branch tip $local_tip - run 'git fetch origin $src_branch' in the clone for the exact diffstat"
    else
      diff_head=""
    fi
  fi
  if [ -n "$diff_head" ]; then
    base_sha="$(gt_recover_base "$repo" "$tgt_branch" "$diff_head" || true)"
  fi
fi
if [ -n "$base_sha" ] && [ -n "$diff_head" ]; then
  git -C "$repo" diff --numstat "$base_sha..$diff_head" > "$GT_API_TMP/card.numstat" 2>/dev/null || true
  python3 - "$GT_API_TMP/card.numstat" "$diffstat_file" <<'PY'
import json, sys
files = adds = dels = 0
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    parts = line.rstrip("\n").split("\t")
    if len(parts) == 3:
        files += 1
        if parts[0] != "-":
            adds += int(parts[0])
        if parts[1] != "-":
            dels += int(parts[1])
open(sys.argv[2], "w").write(json.dumps({"files": files, "insertions": adds, "deletions": dels}))
PY
else
  : > "$diffstat_file"
  gt_note "no usable clone for the diffstat (head ${head_sha:0:8}, source branch '$src_branch') - the card is printed without it; $GT_REPO_HINT"
fi

# ---- output ---------------------------------------------------------------
python3 - "$GT_API_TMP/card.mr.json" "$diffstat_file" "$json" "$max_chars" \
         "$proj" "$iid" "$head_sha" "$head_src" "$api_head" "$approved_by" \
         "$mr_reviewers" "$mr_blocking" "$base_sha" "$diff_head" <<'PY'
import json, sys

(mr_path, stat_path, json_out, max_chars, proj, iid,
 head_sha, head_src, api_head, approved_by, reviewers, blocking, base_sha,
 diff_head) = sys.argv[1:15]
json_out = json_out == "1"
max_chars = int(max_chars)

mr = json.loads(open(mr_path).readline())
title = mr.get("title") or ""
draft_mark = " [DRAFT]" if (mr.get("draft") or mr.get("work_in_progress")
                            or title.lstrip().startswith(("Draft:", "WIP:", "draft:", "wip:"))) else ""
desc = mr.get("description") or ""

def truncate(s):
    if max_chars < 0 or len(s) <= max_chars:
        return s
    return s[:max_chars] + f" ... [+{len(s) - max_chars} chars, use --full]"

try:
    diffstat = json.load(open(stat_path)) if open(stat_path).read().strip() else None
except Exception:
    diffstat = None

card = {
    "project": proj,
    "iid": mr.get("iid"),
    "title": title,
    "draft": bool(draft_mark),
    "state": mr.get("state") or "",
    "work_in_progress": bool(mr.get("work_in_progress")),
    "author": (mr.get("author") or {}).get("username") or "",
    "reviewers": [u for u in reviewers.split(", ") if u],
    "approved_by": [u for u in approved_by.split(", ") if u],
    "blocking_discussions_resolved": mr.get("blocking_discussions_resolved"),
    "detailed_merge_status": mr.get("detailed_merge_status") or "",
    "merge_status": mr.get("merge_status") or "",
    "source_branch": mr.get("source_branch") or "",
    "target_branch": mr.get("target_branch") or "",
    "head_sha": head_sha,
    "head_provenance": head_src,
    "changes_count": mr.get("changes_count"),
    "diffstat": diffstat,
    "description": truncate(desc),
    "web_url": mr.get("web_url") or "",
    "updated_at": mr.get("updated_at") or "",
}

if json_out:
    print(json.dumps(card, ensure_ascii=False, indent=2))
    sys.exit(0)

full = f"{proj}!{iid}"
print(f"== {full} =={draft_mark} state {card['state']} updated {(card['updated_at'] or '')[:10]}")
print(f"   title: {title}")
print(f"   url:   {card['web_url']}")
print(f"   author: {card['author']}")
print(f"   reviewers: {', '.join(card['reviewers']) or '(none)'}")
print(f"   approved by: {', '.join(card['approved_by']) or '(none)'}")
print(f"   blocking_discussions_resolved: {blocking}")
print(f"   detailed_merge_status: {card['detailed_merge_status']}")
print(f"   merge_status: {card['merge_status']}")
print(f"   work_in_progress: {card['work_in_progress']}")
print(f"   branches: {card['source_branch']} -> {card['target_branch']}")
print(f"   head: {head_sha}  (from {head_src}; API diff_refs.sha reported: {api_head or '<none>'})")
print(f"   changes_count: {mr.get('changes_count') if mr.get('changes_count') is not None else '?'}")
if diffstat:
    tip = diff_head if diff_head else head_sha
    print(f"   diffstat ({tip[:8]} vs merge-base {base_sha[:8]}): "
          f"{diffstat['files']} files, +{diffstat['insertions']}/-{diffstat['deletions']}")
else:
    print("   diffstat: (no usable clone; see the NOTE on stderr)")
d = truncate(desc)
print(f"   description{' (truncated)' if d != desc else ''}:")
if d:
    for line in d.splitlines():
        print(f"     {line}")
else:
    print("     (empty)")
PY
