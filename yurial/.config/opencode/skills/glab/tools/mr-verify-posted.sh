#!/usr/bin/env bash
# mr-verify-posted.sh - read-only post-publish verification for MR comments.
#
# usage: mr-verify-posted.sh <project> <mr_iid> [--expect <expected.json>]
#                            [--drafts] [--max-note-id] [--ai-only]
#                            [--max-chars N] [--full]
#
# GET-only: no POST/PUT/DELETE is ever sent (write tools verify their own
# writes; this script re-checks afterwards, e.g. after a mr-draft-review.sh
# --publish run plus raw timeline notes).
#
# Checks:
#   --drafts        pending draft_notes of your user on the MR (count + ids;
#                   the pre-existing-draft check before a batch run)
#   --max-note-id   highest note id on the MR (marker/baseline for follow-up
#                   posts, same basis as the mr-updates.sh --state marker);
#                   fetched as ONE sort=desc page - the newest notes are on
#                   page 1, and the max runs over every note of that page
#   --expect FILE   verify that expected comment bodies are really posted.
#                   FILE = the same JSON array schema as mr-draft-review.sh
#                   comments.json:
#                     {"path": "a/b.cpp", "line": 102, "body": "...",
#                      "old_side": true (optional)}          anchored item
#                     {"body": "..."}                        unanchored item
#                     {"reply_to_discussion_id": "<id>", "body": "..."}
#                                                          reply item
#                   A body string starting with "@" names a file whose exact
#                   bytes are the body (same @file convention as
#                   mr-comment.sh / mr-reply.sh; "@-" stdin is not supported
#                   here). No "AI generated: " prefix is forced: expected
#                   bodies are the FINAL posted bodies, compared
#                   byte-exactly as given - an out-of-hunk batch item posts
#                   unpositioned with "path:line" prepended after the
#                   prefix (mr-draft-review.sh), so expect that body there.
#
# Verdicts per expected item:
#   ok              byte-equal body at the required place (anchor / discussion
#                   / anywhere on the MR)
#   anchor-mismatch byte-equal body found, but anchored differently than
#                   expected (anchored items only)
#   body-mismatch   the expected place exists (anchor occupied / discussion
#                   exists / the body exists elsewhere on the MR) but no note
#                   satisfies both body AND place - e.g. a reply that landed
#                   outside its thread (the silent-orphan trap)
#   not-found       neither the body nor the expected place found
#
# Exit codes: 0 all requested checks ok (or only informational flags given);
# 1 an expected item is not ok; 2 usage error.
#
# Traps handled: pagination (per_page=100 + --paginate), concatenated page
# arrays parsed with repeated raw_decode, error detection without relying on
# the glab exit code, thread resolved == every non-system note resolved
# (no discussion-level flag on this instance).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  cat >&2 <<'EOF'
usage: mr-verify-posted.sh <project> <mr_iid> [--expect <expected.json>]
                           [--drafts] [--max-note-id] [--ai-only]
                           [--max-chars N] [--full]

  --expect FILE   verify posted comments against expected.json (schema of
                  mr-draft-review.sh comments.json; bodies may be "@file")
  --drafts        print the pending draft_notes count (+ ids) of your user
  --max-note-id   print the highest note id on the MR
  --ai-only       --expect matches only "AI generated: " notes;
                  --max-note-id considers only "AI generated: " notes
  --max-chars N   truncate body previews to N chars (default 400)
  --full          never truncate previews

Exit code 1 when any --expect item is not ok; GET-only, never writes.
EOF
  exit 2
}

proj="" iid="" input=""
drafts=0 max_note_id=0 ai_only=0 max_chars=400
while [ $# -gt 0 ]; do
  case "$1" in
    --expect) [ $# -ge 2 ] || usage; input="$2"; shift ;;
    --drafts) drafts=1 ;;
    --max-note-id) max_note_id=1 ;;
    --ai-only) ai_only=1 ;;
    --max-chars) [ $# -ge 2 ] || usage; max_chars="$2"; shift; [[ "$max_chars" =~ ^[0-9]+$ ]] || gt_die "--max-chars expects a number" ;;
    --full) max_chars=-1 ;;
    -h|--help) usage ;;
    -*) gt_die "unknown option: $1" ;;
    *) if [ -z "$proj" ]; then proj="$1"
       elif [ -z "$iid" ]; then iid="$1"
       else gt_die "unexpected argument: $1"
       fi ;;
  esac
  shift
done
# <project> may be omitted when GITLAB_DEFAULT_PROJECT is configured
if [ -n "$proj" ] && [ -z "$iid" ] && [ -n "$GITLAB_DEFAULT_PROJECT" ]; then
  iid="$proj"; proj="$GITLAB_DEFAULT_PROJECT"
fi
[ -n "$proj" ] && [ -n "$iid" ] || usage
if [ -z "$input" ] && [ "$drafts" != 1 ] && [ "$max_note_id" != 1 ]; then
  gt_die "nothing to do: pass --expect <file> and/or --drafts and/or --max-note-id"
fi
[ -z "$input" ] || [ -f "$input" ] || gt_die "expected file not found: $input"

enc="$(gt_urlencode "$proj")"
ep="projects/$enc/merge_requests/$iid"

# ---- 1) parse + validate the expect file; resolve @file bodies -----------
if [ -n "$input" ]; then
  python3 - "$input" "$GT_API_TMP/exp.raw.json" "$GT_API_TMP/exp.atfile.args" <<'PY'
import json, sys
src, out, atfile_out = sys.argv[1:4]
try:
    data = json.load(open(src, encoding="utf-8"))
except Exception as e:
    sys.exit(f"cannot parse {src}: {e}")
if not isinstance(data, list) or not data:
    sys.exit(f"{src} must be a non-empty JSON array of expected-comment objects")
clean, bad, atfiles = [], [], []
for i, c in enumerate(data):
    body = c.get("body")
    did = c.get("reply_to_discussion_id")
    path = c.get("path")
    line = c.get("line")
    if not isinstance(body, str) or not body.strip():
        bad.append(f"  #{i}: missing/empty 'body'")
        continue
    if body == "@-":
        bad.append(f"  #{i}: stdin bodies ('@-') are not supported in --expect files")
        continue
    entry = {"idx": i, "body": body}
    if did is not None:
        if not isinstance(did, str) or not did.strip():
            bad.append(f"  #{i}: invalid 'reply_to_discussion_id'")
            continue
        if path is not None or line is not None:
            bad.append(f"  #{i} ({did}): a reply item must not carry 'path'/'line'")
            continue
        entry.update(kind="reply", did=did.strip())
    elif path is not None or line is not None:
        if not isinstance(path, str) or not path:
            bad.append(f"  #{i}: missing/invalid 'path'")
            continue
        if not isinstance(line, int) or line < 1:
            bad.append(f"  #{i} ({path}): missing/invalid 'line'")
            continue
        entry.update(kind="anchored", path=path, line=line,
                     old_side=bool(c.get("old_side")))
    else:
        entry.update(kind="unanchored")
    if body.startswith("@"):
        atfiles.append(body)
    clean.append(entry)
if bad:
    print("expected-file validation failed:", file=sys.stderr)
    print("\n".join(bad), file=sys.stderr)
    sys.exit(1)
json.dump(clean, open(out, "w", encoding="utf-8"), ensure_ascii=False)
open(atfile_out, "w", encoding="utf-8").write("\n".join(atfiles) + ("\n" if atfiles else ""))
print(f"parsed {len(clean)} expected item(s) from {src}", file=sys.stderr)
PY

  # resolve @file bodies through gt_body_from_arg (the same @file helper as
  # mr-comment.sh / mr-reply.sh; dies when the body file is missing)
  i=0
  while IFS= read -r farg; do
    [ -n "$farg" ] || continue
    gt_body_from_arg "$farg" > "$GT_API_TMP/exp.body.$i"
    i=$((i + 1))
  done < "$GT_API_TMP/exp.atfile.args"

  python3 - "$GT_API_TMP/exp.raw.json" "$GT_API_TMP/exp.body." "$i" "$GT_API_TMP/exp.jsonl" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1], encoding="utf-8"))
prefix, n = sys.argv[2], int(sys.argv[3])
files = [open(f"{prefix}{k}", encoding="utf-8").read() for k in range(n)]
out = sys.argv[4]
k = 0
with open(out, "w", encoding="utf-8") as f:
    for e in entries:
        if e["body"].startswith("@"):
            e["body"] = files[k]  # exact bytes, including any trailing newline
            k += 1
        f.write(json.dumps(e, ensure_ascii=False) + "\n")
PY
fi

# ---- 2) fetch what the requested checks need (GET-only) -------------------
disc_jsonlines="/dev/null"
if [ -n "$input" ]; then
  gt_get_all "$ep/discussions" > "$GT_API_TMP/verify.disc.jsonlines"
  disc_jsonlines="$GT_API_TMP/verify.disc.jsonlines"
fi

if [ "$drafts" = 1 ]; then
  gt_get_all "$ep/draft_notes" > "$GT_API_TMP/verify.drafts.jsonlines"
  echo "== pending drafts (your user) =="
  python3 - "$GT_API_TMP/verify.drafts.jsonlines" <<'PY'
import json, sys
items = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
ids = ", ".join(str(d.get("id")) for d in items)
print(f"count: {len(items)}")
print(f"ids:   {ids or '(none)'}")
PY
fi

if [ "$max_note_id" = 1 ]; then
  # sort=desc puts the newest notes on page 1, so ONE page (per_page=100,
  # no --paginate walk) suffices; the python side still maxes over every
  # fetched note, so the within-page ordering never matters
  gt_get "$ep/notes?sort=desc&order_by=created_at&per_page=100" > "$GT_API_TMP/verify.notes.jsonlines"
  echo "== max note id =="
  python3 - "$GT_API_TMP/verify.notes.jsonlines" "$ai_only" "$GT_PREFIX" <<'PY'
import json, sys
ai_only = sys.argv[2] == "1"
prefix = sys.argv[3]
items = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
if ai_only:
    items = [n for n in items if (n.get("body") or "").startswith(prefix)]
if not items:
    print("(no notes)" + (" matching the prefix" if ai_only else ""))
    sys.exit(0)
n = max(items, key=lambda x: x.get("id") or 0)
who = (n.get("author") or {}).get("username", "?")
first = (n.get("body") or "").splitlines()
first = first[0][:80] if first else ""
print(f"max note id: {n.get('id')} (created {n.get('created_at', '?')} by {who}: {first!r})")
PY
fi

# ---- 3) verdicts for the expected items -----------------------------------
if [ -n "$input" ]; then
  echo "== expected comments =="
  ok_all=0
  python3 - "$GT_API_TMP/exp.jsonl" "$disc_jsonlines" "$ai_only" "$max_chars" \
           "$GT_PREFIX" <<'PY' || ok_all=$?
import json, sys

exp_path, disc_path = sys.argv[1], sys.argv[2]
ai_only = sys.argv[3] == "1"
max_chars = int(sys.argv[4])
AI = sys.argv[5]

def trunc(s):
    if max_chars < 0 or len(s) <= max_chars:
        return s
    return s[:max_chars] + f" ... [+{len(s) - max_chars} chars, use --full]"

def preview(s):
    lines = s.splitlines() or [""]
    return trunc(lines[0])

entries = [json.loads(l) for l in open(exp_path, encoding="utf-8") if l.strip()]
discs = [json.loads(l) for l in open(disc_path, encoding="utf-8") if l.strip()]

# candidate notes: non-system notes inside discussions (a standalone note
# arrives as an individual discussion); --ai-only narrows to our prefix
cands = []
for d in discs:
    for n in d.get("notes") or []:
        if n.get("system"):
            continue
        if ai_only and not (n.get("body") or "").startswith(AI):
            continue
        cands.append((d, n))

def anchor_of(n):
    p = n.get("position") or {}
    if not p:
        return None
    path = p.get("new_path") or p.get("old_path") or "?"
    lr = p.get("line_range")
    if isinstance(lr, dict):
        s, e = lr.get("start") or {}, lr.get("end") or {}
        if s.get("new_line") and e.get("new_line"):
            return f"{path}:{s['new_line']}-{e['new_line']} (new)"
        if s.get("old_line") and e.get("old_line"):
            return f"{path}:{s['old_line']}-{e['old_line']} (old)"
    if p.get("new_line") is not None:
        return f"{path}:{p['new_line']} (new)"
    if p.get("old_line") is not None:
        return f"{path}:{p['old_line']} (old)"
    return f"{path}:? (position without a line)"

def anchored(n, e):
    p = n.get("position") or {}
    if e["old_side"]:
        return p.get("old_path") == e["path"] and p.get("old_line") == e["line"]
    return p.get("new_path") == e["path"] and p.get("new_line") == e["line"]

def resolved_str(n):
    if n.get("resolvable"):
        return "yes" if n.get("resolved") else "no"
    return "n/a"

def newest(pairs):
    return max(pairs, key=lambda dn: (dn[1].get("id") or 0))

def report(tag, e, pair, extra=""):
    if e["kind"] == "anchored":
        want = f"{e['path']}:{e['line']} ({'old' if e['old_side'] else 'new'})"
    elif e["kind"] == "reply":
        want = f"reply into discussion {e['did']}"
    else:
        want = "(unanchored)"
    if pair is None:
        place = "not found"
    else:
        d, n = pair
        a = anchor_of(n)
        place = (f"note #{n.get('id', '?')}  discussion {d.get('id', '?')}  "
                 f"anchor {a if a else '(unanchored)'}  resolved={resolved_str(n)}")
    print(f"#{e['idx']} {tag:<15} want {want}")
    print(f"     {place}")
    if extra:
        print(f"     {extra}")

bad = 0
for e in entries:
    body = e["body"]
    body_hits = [(d, n) for d, n in cands if (n.get("body") or "") == body]
    if e["kind"] == "anchored":
        exact = [dn for dn in body_hits if anchored(dn[1], e)]
        if exact:
            pair = newest(exact)
            note = f" ({len(exact)} matches, showing newest)" if len(exact) > 1 else ""
            report("ok", e, pair, note)
            continue
        if body_hits:
            pair = newest(body_hits)
            report("anchor-mismatch", e, pair,
                   f"exact body found at a different anchor; expected body: {preview(body)!r}")
            bad += 1
            continue
        at_anchor = [dn for dn in cands if anchored(dn[1], e)]
        if at_anchor:
            pair = newest(at_anchor)
            report("body-mismatch", e, pair,
                   f"a note sits at the expected anchor but its body differs; "
                   f"expected body: {preview(body)!r}")
            bad += 1
            continue
        report("not-found", e, None,
               f"neither the body nor the anchor found; expected body: {preview(body)!r}")
        bad += 1
    elif e["kind"] == "reply":
        in_disc = [dn for dn in body_hits if dn[0].get("id") == e["did"]]
        if in_disc:
            pair = newest(in_disc)
            note = f" ({len(in_disc)} matches, showing newest)" if len(in_disc) > 1 else ""
            report("ok", e, pair, note)
            continue
        disc_exists = any(d.get("id") == e["did"] for d in discs)
        if body_hits:
            pair = newest(body_hits)
            where = ("the discussion exists but the body is not inside it"
                     if disc_exists else "the discussion itself was not found")
            report("body-mismatch", e, pair,
                   f"exact body found OUTSIDE discussion {e['did']} (orphan reply?); {where}")
        elif disc_exists:
            # the expected place exists (the discussion) while the body is
            # nowhere on the MR: body-mismatch, not not-found
            in_disc_any = [dn for dn in cands if dn[0].get("id") == e["did"]]
            pair = newest(in_disc_any) if in_disc_any else None
            report("body-mismatch", e, pair,
                   f"the discussion exists but the body is not inside it; "
                   f"expected body: {preview(body)!r}")
        else:
            report("not-found", e, None,
                   f"neither the body nor the discussion found; expected body: {preview(body)!r}")
        bad += 1
    else:  # unanchored: the body anywhere on the MR
        if body_hits:
            pair = newest(body_hits)
            note = f" ({len(body_hits)} matches, showing newest)" if len(body_hits) > 1 else ""
            report("ok", e, pair, note)
            continue
        report("not-found", e, None,
               f"body not found in any discussion; expected body: {preview(body)!r}")
        bad += 1

print(f"-- {len(entries) - bad}/{len(entries)} expected comments verified")
sys.exit(1 if bad else 0)
PY
  if [ "$ok_all" -ne 0 ]; then
    gt_die "expected-comment verification failed (see the not-ok verdicts above)"
  fi
fi
