#!/usr/bin/env bash
# mr-draft-review.sh - batch review flow on top of draft notes.
#
# usage: mr-draft-review.sh <project> <mr_iid> <comments.json>
#                           [--publish] [--dry-run] [--no-prefix] [--repo <dir>]
#                           [--ignore-stray]
#
# comments.json = JSON array of:
#   {"path": "a/b.cpp", "line": 102, "body": "AI generated: ...", "old_side": true}
#   {"reply_to_discussion_id": "<id>", "body": "AI generated: ..."}
#
# Draft items: every anchor is validated locally (hunks built from
# git diff --unified=0 <merge-base>..<head>), a validation table
# (ok / will-post-unpositioned) is printed, drafts are created via the
# draft_notes endpoint (Content-Type: application/json, top-level "note" +
# "position"), then verified via GET (the POST may answer rc=0 with a fake
# 500 error body while the draft was created).
# Reply items: posted immediately through mr-reply.sh (REST with the GraphQL
# createNote fallback) - they cannot be drafts, so they are real posts even
# without --publish; use --dry-run to preview.
#
# Stray-draft guard: before creating anything the pending draft_notes of your
# user are listed; if any already exist the script refuses (a later publish
# could sweep them along) unless --ignore-stray is passed.
#
# With --publish ONLY the drafts created by this run are published, one by
# one, via PUT .../draft_notes/<id>/publish, each verified by GET; if the
# single-publish route answers 404/400, the script falls back to bulk_publish
# with an explicit warning first (bulk_publish publishes ALL pending drafts
# of your user on the MR). Without --publish the draft ids are printed (each
# deletable: glab api -X DELETE .../draft_notes/<id>).
# Bodies must start with "AI generated: " unless --no-prefix is given.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  cat >&2 <<'EOF'
usage: mr-draft-review.sh <project> <mr_iid> <comments.json>
                          [--publish] [--dry-run] [--no-prefix] [--repo <dir>]
                          [--ignore-stray]

comments.json: array of
  {"path": str, "line": int, "body": str, "old_side": bool (optional)}
  {"reply_to_discussion_id": str, "body": str}        (posted at once)

without --publish: create drafts, print their ids (recoverable: delete by id);
                   reply items are posted immediately in any case
with    --publish: publish ONLY the drafts created by this run, one by one
                   (PUT draft_notes/<id>/publish, verified by GET; falls back
                   to bulk_publish with a warning when the route is missing)
with    --dry-run: validate and print payloads only, no writes at all
--ignore-stray:     proceed even when older pending drafts already exist
EOF
  exit 2
}

proj="" iid="" input="" repo_arg=""
publish=0 dry=0 no_prefix=0 ignore_stray=0
while [ $# -gt 0 ]; do
  case "$1" in
    --publish) publish=1 ;;
    --dry-run) dry=1 ;;
    --no-prefix) no_prefix=1 ;;
    --ignore-stray) ignore_stray=1 ;;
    --repo) [ $# -ge 2 ] || usage; repo_arg="$2"; shift ;;
    -h|--help) usage ;;
    -*) gt_die "unknown option: $1" ;;
    *) if [ -z "$proj" ]; then proj="$1"
       elif [ -z "$iid" ]; then iid="$1"
       elif [ -z "$input" ]; then input="$1"
       else gt_die "unexpected argument: $1"
       fi ;;
  esac
  shift
done
# <project> may be omitted when GITLAB_DEFAULT_PROJECT is configured
if [ -n "$iid" ] && [ -z "$input" ] && [ -n "$GITLAB_DEFAULT_PROJECT" ]; then
  input="$iid"; iid="$proj"; proj="$GITLAB_DEFAULT_PROJECT"
fi
[ -n "$proj" ] && [ -n "$iid" ] && [ -n "$input" ] || usage
[ -f "$input" ] || gt_die "comments file not found: $input"

enc="$(gt_urlencode "$proj")"
ep="projects/$enc/merge_requests/$iid"

# 1) parse input; enforce prefixes; split into draft and reply items
python3 - "$input" "$GT_API_TMP/entries.json" "$GT_API_TMP/paths.txt" \
          "$GT_API_TMP/replies.tsv" "$no_prefix" "$GT_PREFIX" <<'PY'
import json, sys
src, out, paths_out, replies_out, no_prefix, prefix = sys.argv[1:]
try:
    data = json.load(open(src, encoding="utf-8"))
except Exception as e:
    sys.exit(f"cannot parse {src}: {e}")
if not isinstance(data, list) or not data:
    sys.exit(f"{src} must be a non-empty JSON array of comment objects")
clean, bad = [], []
for i, c in enumerate(data):
    body = c.get("body")
    did = c.get("reply_to_discussion_id")
    path = c.get("path")
    line = c.get("line")
    if not isinstance(body, str) or not body.strip():
        bad.append(f"  #{i}: missing/empty 'body'")
        continue
    if no_prefix != "1" and not body.startswith(prefix):
        bad.append(f"  #{i}: body does not start with {prefix!r}")
        continue
    if did is not None:
        if not isinstance(did, str) or not did.strip():
            bad.append(f"  #{i}: invalid 'reply_to_discussion_id'")
            continue
        if path is not None or line is not None:
            bad.append(f"  #{i} ({did}): a reply item must not carry 'path'/'line'")
            continue
        clean.append({"idx": i, "kind": "reply", "did": did.strip(), "body": body})
        continue
    if not isinstance(path, str) or not path:
        bad.append(f"  #{i}: missing/invalid 'path' (or 'reply_to_discussion_id')")
        continue
    if not isinstance(line, int) or line < 1:
        bad.append(f"  #{i} ({path}): missing/invalid 'line'")
        continue
    clean.append({"idx": i, "kind": "draft", "path": path, "line": line, "body": body,
                  "old_side": bool(c.get("old_side"))})
if bad:
    print("input validation failed:", file=sys.stderr)
    print("\n".join(bad), file=sys.stderr)
    if no_prefix != "1":
        print("every body must start with the prefix, or pass --no-prefix", file=sys.stderr)
    sys.exit(1)
json.dump(clean, open(out, "w", encoding="utf-8"))
draft_paths = sorted({c["path"] for c in clean if c["kind"] == "draft"})
open(paths_out, "w").write("\n".join(draft_paths) + ("\n" if draft_paths else ""))
with open(replies_out, "w") as f:
    for c in clean:
        if c["kind"] == "reply":
            f.write(f"{c['idx']}\t{c['did']}\n")
n_replies = sum(1 for c in clean if c["kind"] == "reply")
n_drafts = len(clean) - n_replies
print(f"parsed {len(clean)} item(s) from {src}: {n_drafts} draft(s), {n_replies} reply/replies",
      file=sys.stderr)
PY

# 2) resolve shas + build hunk ranges for every unique draft path (locally;
# /diffs collapses them). Reply-only batches skip this: they need no shas
# and work without a clone. gt_diff_head falls back to the local
# source-branch tip when the clone lacks the true MR head (stale fetch).
n_drafts="$(python3 -c '
import json, sys
e = json.load(open(sys.argv[1], encoding="utf-8"))
print(sum(1 for c in e if c["kind"] == "draft"))
' "$GT_API_TMP/entries.json")"
if [ "$n_drafts" -gt 0 ]; then
  repo="$repo_arg"
  [ -n "$repo" ] || repo="$GITLAB_REPO"
  [ -n "$repo" ] || repo="$(gt_git_dir)"
  gt_resolve_shas "$repo" "$enc" "$iid"

  HUNKS_DIR="$GT_API_TMP/hunks"
  mkdir -p "$HUNKS_DIR"
  if [ -n "$repo" ]; then
    diff_head="$(gt_diff_head "$repo")"
  else
    diff_head=""
    gt_warn "no git clone available: anchors cannot be validated locally; out-of-hunk drafts will be posted unpositioned"
  fi
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    h="$HUNKS_DIR/$(printf '%s' "$p" | md5sum | cut -d' ' -f1)"
    if [ -n "$repo" ] && [ -n "$diff_head" ]; then
      gt_hunks "$repo" "$GT_BASE" "$diff_head" "$p" > "$h" || : > "$h"
    else
      : > "$h"
    fi
  done < "$GT_API_TMP/paths.txt"
else
  repo=""; diff_head=""
  HUNKS_DIR="$GT_API_TMP/hunks"; mkdir -p "$HUNKS_DIR"
fi

# 3) validate all entries; emit manifest (drafts) - replies are listed as-is
manifest="$GT_API_TMP/manifest.tsv"
python3 - "$GT_API_TMP/entries.json" "$manifest" "$HUNKS_DIR" "$repo" "$GT_API_TMP/replies.tsv" <<'PY'
import json, sys, hashlib, os
entries, manifest, hunks_dir, repo, replies_path = sys.argv[1:6]
replies = {}
for line in open(replies_path):
    if line.strip():
        idx, did = line.rstrip("\n").split("\t", 1)
        replies[int(idx)] = did
rows = []
for c in json.load(open(entries, encoding="utf-8")):
    if c["kind"] == "reply":
        rows.append((c["idx"], "-", 0, "-", 0, f"reply -> discussion {replies[c['idx']]}"))
        continue
    side = "old" if c["old_side"] else "new"
    h = os.path.join(hunks_dir, hashlib.md5(c["path"].encode()).hexdigest())
    ranges = []
    if repo:
        try:
            for ln in open(h):
                parts = ln.split()
                if len(parts) == 3:
                    ranges.append((parts[0], int(parts[1]), int(parts[2])))
        except OSError:
            pass
    ok = any(s == side and a <= c["line"] <= b for s, a, b in ranges)
    positioned = 1 if (ok or not repo) else 0
    status = "ok" if ok else ("cannot-validate (no clone)" if not repo else "will-post-unpositioned")
    rows.append((c["idx"], c["path"], c["line"], side, positioned, status))
with open(manifest, "w") as f:
    for r in rows:
        f.write("\t".join(map(str, r)) + "\n")
print("== validation table ==")
print(f"{'#':>3}  {'status':<40} anchor")
for idx, p, line, side, _, status in rows:
    if p == "-":
        print(f"{idx:>3}  {status:<40} (reply, posted at once)")
    else:
        print(f"{idx:>3}  {status:<40} {p}:{line} ({side} side)")
PY

# reply targets must exist (GET, read-only; also done for --dry-run)
if [ -s "$GT_API_TMP/replies.tsv" ]; then
  gt_note "reply items are posted immediately (mr-reply.sh: REST + GraphQL fallback) - they cannot be drafts; without --publish everything else stays private"
  while IFS=$'\t' read -r ridx rdid; do
    if ! gt_try_get "$ep/discussions/$rdid" "$GT_API_TMP/reply-target.json"; then
      gt_die "reply target discussion $rdid not found on $proj!$iid (entry #$ridx)"
    fi
    printf '  #%s -> discussion %s exists\n' "$ridx" "$rdid"
  done < "$GT_API_TMP/replies.tsv"
fi

# ---- stray-draft guard: never sweep older pending drafts along -----------
gt_get_all "$ep/draft_notes" > "$GT_API_TMP/pre.jsonlines"
stray_n="$(grep -c . "$GT_API_TMP/pre.jsonlines" || true)"
if [ "${stray_n:-0}" -gt 0 ]; then
  stray_ids="$(python3 -c '
import json, sys
ids = [str(json.loads(l).get("id")) for l in open(sys.argv[1]) if l.strip()]
print(", ".join(ids))
' "$GT_API_TMP/pre.jsonlines")"
  if [ "$dry" = 1 ]; then
    gt_note "dry-run: $stray_n pre-existing pending draft(s) on this MR (ids: $stray_ids) - a real run without --ignore-stray would refuse"
  elif [ "$ignore_stray" = 1 ]; then
    gt_warn "--ignore-stray: proceeding while $stray_n older pending draft(s) exist (ids: $stray_ids); --publish will still publish ONLY the drafts created by this run (unless the bulk_publish fallback fires)"
  else
    gt_die "refusing to create drafts: this MR already has $stray_n pending draft note(s) of your user (ids: $stray_ids).
mixing runs makes publish steps dangerous; delete the stale drafts first:
  glab api --hostname \"$GITLAB_HOST\" -X DELETE \"$ep/draft_notes/<id>\"
or pass --ignore-stray to accept the risk."
  fi
fi

if [ "$dry" = 1 ]; then
  echo
  echo "== dry-run: nothing will be written =="
  if [ "$n_drafts" -gt 0 ]; then
    echo "shas: base=$GT_BASE start=$GT_START head=$GT_HEAD"
    echo
    python3 - "$GT_API_TMP/entries.json" "$manifest" "$GT_BASE" "$GT_START" "$GT_HEAD" "$GT_PREFIX" <<'PY'
import json, sys
entries = {c["idx"]: c for c in json.load(open(sys.argv[1], encoding="utf-8"))}
base, start, head, prefix = sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]
for row in open(sys.argv[2]):
    idx, p, line, side, positioned, status = row.rstrip("\n").split("\t")
    if p == "-":
        continue  # replies are printed below
    idx, line, positioned = int(idx), int(line), int(positioned)
    c = entries[idx]
    body = c["body"]
    if not positioned:
        pre = f"{p}:{line}\n\n"
        body = (prefix + pre + body[len(prefix):]) if body.startswith(prefix) else (pre + body)
    payload = {"note": body}
    if positioned:
        pos = {"position_type": "text", "base_sha": base, "start_sha": start,
               "head_sha": head, "old_path": p, "new_path": p}
        if side == "old":
            pos["old_line"] = line
        else:
            pos["new_line"] = line
        payload["position"] = pos
    print(f"--- draft for entry #{idx} {p}:{line} ({side}) status={status}")
    print(json.dumps(payload, ensure_ascii=False, indent=2))
PY
  fi
  if [ -s "$GT_API_TMP/replies.tsv" ]; then
    echo
    python3 - "$GT_API_TMP/entries.json" "$GT_API_TMP/replies.tsv" <<'PY'
import json, sys
entries = {c["idx"]: c for c in json.load(open(sys.argv[1], encoding="utf-8"))}
for line in open(sys.argv[2]):
    if not line.strip():
        continue
    idx, did = line.rstrip("\n").split("\t")
    print(f"--- reply for entry #{idx} -> discussion {did} (via mr-reply.sh)")
    print(entries[int(idx)]["body"])
    print()
PY
  fi
  exit 0
fi

# 4) create drafts (POST may return a fake 500 error body while created)
if [ "$n_drafts" -gt 0 ]; then
  echo
  echo "== creating drafts =="
  mapfile -t rows < "$manifest"
  i=0
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r idx p line side positioned _ <<< "$row"
    if [ "$p" = "-" ]; then continue; fi  # reply rows are handled below
    i=$((i + 1))
    payload="$(python3 - "$GT_API_TMP/entries.json" "$idx" "$p" "$line" "$side" "$positioned" "$GT_BASE" "$GT_START" "$GT_HEAD" "$GT_PREFIX" <<'PY'
import json, sys
entries = {c["idx"]: c for c in json.load(open(sys.argv[1], encoding="utf-8"))}
idx, p, line, side, positioned = int(sys.argv[2]), sys.argv[3], int(sys.argv[4]), sys.argv[5], int(sys.argv[6])
base, start, head, prefix = sys.argv[7], sys.argv[8], sys.argv[9], sys.argv[10]
c = entries[idx]
body = c["body"]
if not positioned:
    pre = f"{p}:{line}\n\n"
    body = (prefix + pre + body[len(prefix):]) if body.startswith(prefix) else (pre + body)
payload = {"note": body}
if positioned:
    pos = {"position_type": "text", "base_sha": base, "start_sha": start,
           "head_sha": head, "old_path": p, "new_path": p}
    if side == "old":
        pos["old_line"] = line
    else:
        pos["new_line"] = line
    payload["position"] = pos
print(json.dumps(payload, ensure_ascii=False))
PY
)"
    pf="$GT_API_TMP/payload.$i.json"
    printf '%s' "$payload" > "$pf"
    gt_post_json "$ep/draft_notes" "$pf"
    if { [ "$GT_RC" -ne 0 ] || [ "$GT_HTTP_CODE" != "0" ] || gt_body_is_error "$GT_BODY"; }; then
      gt_note "draft POST answer looked like a failure (rc=$GT_RC, HTTP=$GT_HTTP_CODE, body: $(tr -d '\n' <"$GT_BODY" | tail -c 200)) - will verify by GET"
    fi
    rm -f "$pf"
  done
fi

# 5) verify drafts by GET (never trust POST responses alone)
if [ "$n_drafts" -gt 0 ]; then
  gt_get_all "$ep/draft_notes" > "$GT_API_TMP/drafts.jsonlines"
  python3 - "$GT_API_TMP/entries.json" "$manifest" "$GT_API_TMP/drafts.jsonlines" "$ep" <<'PY'
import json, sys
entries = {c["idx"]: c for c in json.load(open(sys.argv[1], encoding="utf-8"))}
manifest, drafts_path, ep = sys.argv[2], sys.argv[3], sys.argv[4]
drafts = [json.loads(l) for l in open(drafts_path) if l.strip()]
print("== drafts verified via GET ==")
n_draft_entries = sum(1 for c in entries.values() if c["kind"] == "draft")
ok = 0
ids = []
for row in open(manifest):
    idx, p, line, side, positioned, _ = row.rstrip("\n").split("\t")
    if p == "-":
        continue
    idx = int(idx)
    c = entries[idx]
    matches = [d for d in drafts if (d.get("note") or "") == c["body"]]
    if matches:
        d = max(matches, key=lambda x: x.get("id") or 0)
        ids.append(d["id"])
        note = "ok" if len(matches) == 1 else f"ok (ambiguous body, {len(matches)} drafts match)"
        print(f"#{idx} {p}:{line} ({side}) -> draft id {d['id']}  [{note}]")
        ok += 1
    else:
        print(f"#{idx} {p}:{line} ({side}) -> NOT FOUND among drafts (creation failed?)")
print(f"-- {ok}/{n_draft_entries} drafts verified")
if ok != n_draft_entries:
    sys.exit(1)
json.dump(ids, open(drafts_path + ".ids", "w"))
PY
else
  printf '[]' > "$GT_API_TMP/drafts.jsonlines.ids"
fi

# 5b) post reply items now (they cannot wait in the draft box)
reply_fail=0
if [ -s "$GT_API_TMP/replies.tsv" ]; then
  echo
  echo "== posting replies (mr-reply.sh) =="
  while IFS=$'\t' read -r ridx rdid; do
    bf="$GT_API_TMP/reply-body.$ridx.txt"
    python3 - "$GT_API_TMP/entries.json" "$ridx" > "$bf" <<'PY'
import json, sys
entries = {c["idx"]: c for c in json.load(open(sys.argv[1], encoding="utf-8"))}
print(entries[int(sys.argv[2])]["body"], end="")
PY
    echo "-- entry #$ridx: replying into discussion $rdid"
    if "$SCRIPT_DIR/mr-reply.sh" "$proj" "$iid" "$rdid" "@$bf"; then
      echo "-- entry #$ridx: reply ok"
    else
      gt_warn "entry #$ridx: reply into discussion $rdid FAILED"
      reply_fail=$((reply_fail + 1))
    fi
  done < "$GT_API_TMP/replies.tsv"
  if [ "$reply_fail" -gt 0 ]; then
    gt_die "$reply_fail reply item(s) failed - drafts (if any) above are still private and deletable"
  fi
fi

# 6) publish (opt-in): ONLY the drafts created by this run, one by one,
# each verified by GET; bulk fallback only when the single route is missing.
if [ "$publish" = 1 ]; then
  ids_file="$GT_API_TMP/drafts.jsonlines.ids"
  n_pub="$(python3 -c 'import json, sys; print(len(json.load(open(sys.argv[1]))))' "$ids_file")"
  if [ "$n_pub" -eq 0 ]; then
    gt_note "--publish: no drafts were created by this run; nothing to publish"
  else
    if [ -s "$GT_API_TMP/replies.tsv" ]; then
      gt_note "--publish covers draft items only; the reply items were already posted above"
    fi
    echo
    echo "== publishing the $n_pub draft(s) created by this run (one by one) =="
    idmap="$GT_API_TMP/idmap.json"
    python3 - "$GT_API_TMP/drafts.jsonlines" "$idmap" <<'PY'
import json, sys
m = {}
for line in open(sys.argv[1]):
    if line.strip():
        d = json.loads(line)
        m[str(d.get("id"))] = d.get("note") or ""
open(sys.argv[2], "w", encoding="utf-8").write(json.dumps(m, ensure_ascii=False))
PY

    # verify_published ID... - refresh drafts+discussions via GET; print a
    # per-id verdict; return 1 when any id is not (gone from drafts AND
    # posted as a thread with the same body)
    verify_published() {
      gt_get_all "$ep/draft_notes" > "$GT_API_TMP/pub.drafts" || return 1
      gt_get_all "$ep/discussions" > "$GT_API_TMP/pub.disc" || return 1
      python3 - "$idmap" "$GT_API_TMP/pub.drafts" "$GT_API_TMP/pub.disc" "$@" <<'PY'
import json, sys
idmap = json.load(open(sys.argv[1], encoding="utf-8"))
drafts = [json.loads(l) for l in open(sys.argv[2]) if l.strip()]
disc = [json.loads(l) for l in open(sys.argv[3]) if l.strip()]
pending_ids = {str(d.get("id")) for d in drafts}
thread_bodies = set()
for d in disc:
    for n in d.get("notes") or []:
        thread_bodies.add(n.get("body") or "")
bad = 0
for did in sys.argv[4:]:
    body = idmap.get(did, "")
    if did in pending_ids:
        print(f"draft {did} -> STILL PENDING (publish did not take effect)")
        bad += 1
    elif body and body in thread_bodies:
        print(f"draft {did} -> published + verified (thread with the same body found)")
    else:
        print(f"draft {did} -> gone from drafts but its body was NOT found in discussions (check manually)")
        bad += 1
sys.exit(1 if bad else 0)
PY
    }

    empty="$GT_API_TMP/empty.json"
    printf '{}' > "$empty"
    bulk_used=0
    publish_failed=0
    for id in $(python3 -c 'import json, sys; print("\n".join(map(str, json.load(open(sys.argv[1])))))' "$ids_file"); do
      gt_api PUT "$ep/draft_notes/$id/publish" --input "$empty" -H "Content-Type: application/json"
      if [ "$GT_HTTP_CODE" = "404" ] || [ "$GT_HTTP_CODE" = "400" ]; then
        gt_warn "single-draft publish route not available (PUT draft_notes/$id/publish -> HTTP $GT_HTTP_CODE)"
        gt_warn "FALLBACK: bulk_publish publishes ALL pending drafts of your user on this MR, not only the $n_pub created above"
        gt_post_json "$ep/draft_notes/bulk_publish" "$empty"
        bulk_used=1
        break
      fi
      # the PUT answer is never trusted (fake 500-in-body trap): GET decides
      if ! verify_published "$id"; then
        gt_warn "draft $id: single publish could not be verified"
        publish_failed=$((publish_failed + 1))
      fi
    done
    if [ "$bulk_used" = 1 ]; then
      echo
      echo "== verifying all drafts after the bulk_publish fallback =="
      if ! verify_published $(python3 -c 'import json, sys; print(" ".join(map(str, json.load(open(sys.argv[1])))))' "$ids_file"); then
        publish_failed=$((publish_failed + 1))
      fi
    fi
    if [ "$publish_failed" -gt 0 ]; then
      gt_die "$publish_failed draft(s) failed to publish or could not be verified - check the MR manually"
    fi
    echo "-- publish done: $n_pub draft(s) created by this run are published (older drafts, if any, were not touched"
    echo "   unless the bulk_publish fallback fired - see the warnings above)"
  fi
fi
