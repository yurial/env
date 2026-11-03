#!/usr/bin/env bash
# mr-diff.sh - the true local MR diff: the diff traps of the /diffs endpoint
# (collapsed files) and the merge-base rule made operational as one command.
#
# usage: mr-diff.sh <project> <mr_iid> [--files|--stat|--hunks|--conflicts]
#                   [--repo <dir>]
#
#   --files      one line per changed path with its status:
#                new <path> | deleted <path> | renamed <old> -> <new>
#                | modified <path>
#   --stat       the diffstat: <files> files, +<insertions>/-<deletions>
#   --hunks      machine-readable new-side hunk ranges per changed file:
#                <path>\t<start>-<end> <start>-<end> ...
#                (a path with no new side carries "-" in place of ranges) -
#                the anchor-validation source of truth, the SAME shared
#                hunk construction (lib.sh gt_hunks) mr-comment.sh and
#                mr-draft-review.sh validate anchors against
#   --conflicts  write-free local merge simulation (git merge-tree
#                --write-tree) between the target-branch tip and the MR
#                head: exit 0 = clean merge, exit 1 = conflicts (the
#                conflicting paths on stdout), exit 3 = could not be
#                performed at all (no usable clone or head, a git failure)
#   --repo DIR   clone used for sha recovery and the diff
#                (clone is configured via GITLAB_REPO env or config.sh)
#
# A usable clone is REQUIRED; without one the script exits 1 with a clear
# message. Construction: shas are recovered through the ladder of lib.sh
# (masked 40-hex ids -> short_id -> ls-remote -> local refs) and the diff
# ALWAYS runs <merge-base>..<head> with the merge-base from git merge-base
# against the target branch (fallback origin/main / origin/master) - never
# from diff_refs.start_sha (on this instance it is the target-branch tip)
# and never as a two-dot origin/<target>..<head> (a target that moved ahead
# unfolds other authors' commits).
#
# Clone-freshness guard: when the clone lacks the true MR head, every mode
# prints a loud warning naming the expected head and the fallback tip and
# degrades to the local source-branch tip; a --conflicts verdict computed
# from the fallback head is labeled as such.
#
# Exit codes: 0/1/2 per the shared contract for all modes except
# --conflicts, which owns the 0/1 pair as its verdict (0 clean, 1
# conflicts) and exits 3 when the check could not be performed. Usage
# errors exit 2 in every mode. GET-only plus read-only clone use; nothing
# is fetched or written.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  cat >&2 <<'EOF'
usage: mr-diff.sh <project> <mr_iid> [--files|--stat|--hunks|--conflicts]
                  [--repo <dir>]

  --files      changed paths with their status (new/deleted/renamed/modified)
  --stat       diffstat: files, insertions, deletions
  --hunks      new-side hunk ranges per file: <path>\t<start>-<end> ...
  --conflicts  local merge simulation: 0 clean, 1 conflicts (paths on
               stdout), 3 could not be performed
  --repo DIR   clone for the diff (a usable clone is required;
               clone is configured via GITLAB_REPO env or config.sh)
EOF
  exit 2
}

die_usage() { printf 'ERROR: %s\n' "$*" >&2; usage; }

proj="" iid="" repo_arg=""
mode="diff"
while [ $# -gt 0 ]; do
  case "$1" in
    --files) mode="files" ;;
    --stat) mode="stat" ;;
    --hunks) mode="hunks" ;;
    --conflicts) mode="conflicts" ;;
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
if [ -z "$repo" ]; then
  printf 'ERROR: mr-diff.sh requires a usable git clone of the project (a local diff cannot be computed without one).
run from inside a clone, or pass --repo <dir> / set GITLAB_REPO (%s)\n' "$GT_REPO_HINT" >&2
  exit 1
fi

enc="$(gt_urlencode "$proj")"

# gt_resolve_shas dies (exit 1) when the ladder meets no usable clone/head;
# for --conflicts that outcome is a "could not be performed" failure -> rc 3.
# Run it in a subshell and pass the resolved values through a file so the
# main shell can choose the exit code (variables set in a subshell do not
# survive it).
shas_file="$GT_API_TMP/diff.shas"
resolve_failed=0
(
  gt_resolve_shas "$repo" "$enc" "$iid"
  printf '%s\n' "$GT_BASE" "$GT_START" "$GT_HEAD" \
    "$GT_MR_SRC_BRANCH" "$GT_MR_TGT_BRANCH" > "$shas_file"
) || resolve_failed=1
if [ "$resolve_failed" = 1 ]; then
  if [ "$mode" = "conflicts" ]; then
    printf 'ERROR: --conflicts could not be performed: sha recovery failed (see the diagnostics above).\nrefresh the clone (git fetch origin <target> <source>) or pass --repo <dir> / set GITLAB_REPO (%s)\n' "$GT_REPO_HINT" >&2
    exit 3
  fi
  exit 1
fi
mapfile -t sf < "$shas_file"
GT_BASE="${sf[0]}"; GT_HEAD="${sf[2]}"
GT_MR_SRC_BRANCH="${sf[3]}"; GT_MR_TGT_BRANCH="${sf[4]}"
export GT_BASE GT_HEAD GT_MR_SRC_BRANCH GT_MR_TGT_BRANCH

# clone-freshness guard: the true MR head or the local source-branch tip
# (with a loud warning naming both)
diff_head="$(gt_diff_head "$repo")"
if [ -z "$diff_head" ]; then
  printf 'ERROR: the clone lacks the MR head %s and no local source-branch ref was found.
run: git -C '%s' fetch origin '%s' '%s'\n' \
    "$GT_HEAD" "$repo" "$GT_MR_TGT_BRANCH" "$GT_MR_SRC_BRANCH" >&2
  if [ "$mode" = "conflicts" ]; then exit 3; fi
  exit 1
fi
fallback_head=0
if [ "$diff_head" != "$GT_HEAD" ]; then
  fallback_head=1
fi

diff_range="$GT_BASE..$diff_head"

case "$mode" in
  diff)
    git -C "$repo" diff "$diff_range"
    exit $?
    ;;
  files)
    git -C "$repo" diff --name-status "$diff_range" | python3 -c '
import sys
for line in sys.stdin:
    parts = line.rstrip("\n").split("\t")
    if len(parts) == 2:
        status, path = parts
        kind = {"A": "new", "D": "deleted"}.get(status[:1], "modified")
        print(f"{kind} {path}")
    elif len(parts) >= 3:
        # R100/C75 old new -> renamed <old> -> <new>, anything else modified
        if parts[0][:1] == "R":
            print(f"renamed {parts[1]} -> {parts[2]}")
        else:
            print(f"modified {parts[2]}")
'
    ;;
  stat)
    git -C "$repo" diff --numstat "$diff_range" | python3 -c '
import sys
files = adds = dels = 0
for line in sys.stdin:
    parts = line.rstrip("\n").split("\t")
    if len(parts) == 3:
        files += 1
        if parts[0] != "-":
            adds += int(parts[0])
        if parts[1] != "-":
            dels += int(parts[1])
print(f"{files} files, +{adds}/-{dels}")
'
    ;;
  hunks)
    # the SAME shared hunk construction the anchor validators use: lib.sh
    # gt_hunks over git diff --unified=0 <merge-base>..<head> -- <path>
    git -C "$repo" diff --name-status "$diff_range" | python3 -c '
import sys
for line in sys.stdin:
    parts = line.rstrip("\n").split("\t")
    print(parts[-1])
' | while IFS= read -r p; do
      [ -n "$p" ] || continue
      ranges="$(gt_hunks "$repo" "$GT_BASE" "$diff_head" "$p" \
        | awk '$1 == "new" { printf "%s-%s ", $2, $3 }')"
      if [ -n "$ranges" ]; then
        printf '%s\t%s\n' "$p" "${ranges% }"
      else
        printf '%s\t-\n' "$p"
      fi
    done
    ;;
  conflicts)
    # target-branch tip: origin/<target>, then origin/main / origin/master
    target_tip=""
    for ref in "origin/$GT_MR_TGT_BRANCH" origin/main origin/master; do
      if [ -n "$(gt_git_sha "$repo" "$ref")" ]; then
        target_tip="$ref"
        break
      fi
    done
    if [ -z "$target_tip" ]; then
      printf 'ERROR: --conflicts could not be performed: no target-branch ref found (origin/%s, origin/main, origin/master).
run: git -C '\''%s'\'' fetch origin '\''%s'\'' '\''%s'\''\n' \
        "$GT_MR_TGT_BRANCH" "$repo" "$GT_MR_TGT_BRANCH" "$GT_MR_SRC_BRANCH" >&2
      exit 3
    fi
    mt_out="$GT_API_TMP/merge-tree.out"
    # isolate the ODB write of merge-tree --write-tree: the freshly written
    # tree/blob objects land in a scratch object directory (the clone's ODB
    # stays untouched), while the clone's objects remain readable through
    # the alternates chain; the 0/1 rc semantics of merge-tree are kept
    mt_odb="$GT_API_TMP/mt-odb"
    mkdir -p "$mt_odb"
    mt_alt="$(git -C "$repo" rev-parse --git-path objects)"
    mt_rc=0
    GIT_OBJECT_DIRECTORY="$mt_odb" \
    GIT_ALTERNATE_OBJECT_DIRECTORIES="$mt_alt" \
      git -C "$repo" merge-tree --write-tree --name-only "$target_tip" "$diff_head" \
      > "$mt_out" 2>"$GT_API_TMP/merge-tree.err" || mt_rc=$?
    if [ "$mt_rc" -ne 0 ] && [ "$mt_rc" -ne 1 ]; then
      printf 'ERROR: --conflicts could not be performed: git merge-tree failed (rc=%s): %s\n' \
        "$mt_rc" "$(tr -d '\n' <"$GT_API_TMP/merge-tree.err" | tail -c 300)" >&2
      exit 3
    fi
    if [ "$fallback_head" = 1 ]; then
      printf '# NOTE: verdict computed from the local fallback tip %s (the clone lacks the MR head %s; refresh it for an exact verdict)\n' \
        "${diff_head:0:12}" "${GT_HEAD:0:12}"
    fi
    if [ "$mt_rc" = 0 ]; then
      exit 0
    fi
    # conflict output: line 1 is the tree oid, then the conflicting paths,
    # then an empty line and the informational messages
    python3 - "$mt_out" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8", errors="replace").read().splitlines()
paths = []
for line in lines[1:]:
    if not line.strip():
        break
    paths.append(line)
for p in paths:
    print(p)
PY
    exit 1
    ;;
esac
