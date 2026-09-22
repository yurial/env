#!/bin/sh
# Test suite for speclint — mechanical checks of the spec skill.
#
# Run from the skill directory (no arguments):   sh tests/run.sh
# Dependencies: sh, awk, mktemp only. Every fixture project is
# generated inside a temporary directory (mktemp -d) and removed on
# exit — no .md files with deliberate violations are left in the
# repository tree.
#
# Each case fixes a small project (specs/index.md, specs/GLOSSARY.md,
# spec files), runs speclint on it, and checks the exit code plus the
# presence/absence of specific diagnostic substrings. On failure the
# case prints its name, what was expected, and the captured output.
# Exit status: 0 — all cases green, 1 — at least one failure.

set -u

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
skill_dir=$(CDPATH= cd -- "$tests_dir/.." && pwd) || exit 1
SPECLINT="$skill_dir/speclint"

work=$(mktemp -d "${TMPDIR:-/tmp}/speclint.tests.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

total=0
failed=0
rc=0
out=
fx=

# check_case <name> <expected-exit> [pattern]...
#   Checks the exit code of the last run_lint against <expected-exit>
#   and the captured output against the patterns: a pattern must occur
#   in the output (substring match); a pattern starting with '!' must
#   NOT occur. A case with several expectation violations reports all
#   of them plus the full captured output.
check_case() {
    _name=$1; _want=$2; shift 2
    _why=
    if [ "$rc" -ne "$_want" ]; then
        _why="$_why
  exit code: expected $_want, got $rc"
    fi
    for _pat in "$@"; do
        case $_pat in
        '!'*)
            _p=${_pat#?}
            case $out in
            *"$_p"*) _why="$_why
  unexpected message: $_p" ;;
            esac
            ;;
        *)
            case $out in
            *"$_pat"*) ;;
            *) _why="$_why
  missing message: $_pat" ;;
            esac
            ;;
        esac
    done
    total=$((total + 1))
    if [ -z "$_why" ]; then
        printf 'ok   %s\n' "$_name"
    else
        failed=$((failed + 1))
        printf 'FAIL %s\n' "$_name"
        printf '%s\n' "$_why"
        printf '  speclint output (exit %s):\n' "$rc"
        printf '%s\n' "$out" | awk '{ print "    " $0 }'
    fi
}

run_lint() {
    out=$("$SPECLINT" "$@" 2>&1)
    rc=$?
}

# Fixture helpers -----------------------------------------------------------

new_fixture() {
    # $1: fixture name; sets fx to the fixture root, with specs/ inside
    fx=$work/$1
    rm -rf "$fx"
    mkdir -p "$fx/specs"
}

std_index() {
    # Valid index (queue, yt-core-bus) with the spec files it points to
    cat > "$fx/specs/index.md" <<'EOF'
# Specification Index

| Path | Reference | Status | Summary |
|---|---|---|---|
| specs/queue.md | queue | draft | Persistent queue delivery guarantees |
| specs/bus.md | yt-core-bus | draft | Message bus transport contract |
EOF
    cat > "$fx/specs/queue.md" <<'EOF'
# Queue Specification

Status: draft
Spec source of truth for: queue

## Requirements
- R1. A read of an expired key returns NOT_FOUND.
EOF
    cat > "$fx/specs/bus.md" <<'EOF'
# Bus Specification

Status: draft
Spec source of truth for: yt-core-bus

## Requirements
- R1. The bus delivers every accepted message at least once.
EOF
}

glossary() {
    # $@: none; GLOSSARY.md body arrives on stdin
    cat > "$fx/specs/GLOSSARY.md"
}

# --- term ID language checks -------------------------------------------------

new_fixture lang-cyr-term
std_index
glossary <<'EOF'
# Specification Glossary

| Term | Definition | Defined in |
|---|---|---|
| auth/очередь | Cyrillic letters in the term part | auth |
EOF
run_lint "$fx/specs/GLOSSARY.md"
check_case "glossary: Cyrillic in term part (auth/очередь) — language error" 2 \
    "term ID must be strictly English (auth/очередь)" \
    "!must be lowercase"

new_fixture lang-cyr-prefix
std_index
glossary <<'EOF'
# Specification Glossary

| Term | Definition | Defined in |
|---|---|---|
| очередь/lease | Cyrillic letters in the reference prefix | очередь |
EOF
run_lint "$fx/specs/GLOSSARY.md"
check_case "glossary: Cyrillic in prefix (очередь/lease) — language error" 2 \
    "term ID must be strictly English (очередь/lease)" \
    "!must be lowercase"

new_fixture lang-mixed
std_index
glossary <<'EOF'
# Specification Glossary

| Term | Definition | Defined in |
|---|---|---|
| queue/очередь | Mixed alphabets inside one term ID | queue |
EOF
run_lint "$fx/specs/GLOSSARY.md"
check_case "glossary: mixed-alphabet ID (queue/очередь) — language error" 2 \
    "term ID must be strictly English (queue/очередь)" \
    "!must be lowercase"

new_fixture lang-upper
std_index
glossary <<'EOF'
# Specification Glossary

| Term | Definition | Defined in |
|---|---|---|
| auth/Lease | Uppercase letter in the term part | auth |
| Auth/lease | Uppercase letter in the reference prefix | Auth |
EOF
run_lint "$fx/specs/GLOSSARY.md"
check_case "glossary: uppercase letter in either part (auth/Lease, Auth/lease) — language error" 2 \
    "term ID must be strictly English (auth/Lease)" \
    "term ID must be strictly English (Auth/lease)" \
    "!must be lowercase"

new_fixture lang-valid-digits
std_index
glossary <<'EOF'
# Specification Glossary

| Term | Definition | Defined in |
|---|---|---|
| yt-core-bus/connection-v2 | Versioned connection protocol of the bus | yt-core-bus |
EOF
run_lint "$fx/specs/GLOSSARY.md"
check_case "glossary: digits and hyphens in both parts (yt-core-bus/connection-v2) — passes form and language" 0 \
    "!strictly English" \
    "!must be lowercase"

# --- term ID form checks (priority: one finding of one class per row) --------

new_fixture form-broken
std_index
glossary <<'EOF'
# Specification Glossary

| Term | Definition | Defined in |
|---|---|---|
| queue/lease | Exclusive time-bounded ownership of a message | queue |
| queue | No slash — broken form | queue |
| a/b/c | Two slashes — broken form | a |
| queue/ | Empty term part — broken form | queue |
EOF
run_lint "$fx/specs/GLOSSARY.md"
check_case "glossary: broken form (no slash, two slashes, empty part) — form error only, no language error" 2 \
    "term ID must be lowercase <reference>/<term>: queue" \
    "term ID must be lowercase <reference>/<term>: a/b/c" \
    "term ID must be lowercase <reference>/<term>: queue/" \
    "!strictly English"

new_fixture glossary-valid
std_index
glossary <<'EOF'
# Specification Glossary

| Term | Definition | Defined in |
|---|---|---|
| queue/ack | Positive delivery confirmation from a consumer | queue |
| queue/lease | Exclusive time-bounded ownership of a message | queue (R2) |
| yt-core-bus/connection-v2 | Versioned connection protocol of the bus | yt-core-bus |
EOF
run_lint "$fx/specs/GLOSSARY.md"
check_case "glossary: fully valid glossary — clean" 0 \
    "!strictly English" \
    "!must be lowercase" \
    "!not alphabetical" \
    "!Defined in must equal"

# --- basic existing checks ---------------------------------------------------

new_fixture alpha-order
std_index
glossary <<'EOF'
# Specification Glossary

| Term | Definition | Defined in |
|---|---|---|
| queue/lease | Exclusive time-bounded ownership of a message | queue |
| queue/ack | Positive delivery confirmation from a consumer | queue |
EOF
run_lint "$fx/specs/GLOSSARY.md"
check_case "glossary: not alphabetical — error" 2 \
    "glossary not alphabetical: queue/ack after queue/lease"

new_fixture defined-in
std_index
glossary <<'EOF'
# Specification Glossary

| Term | Definition | Defined in |
|---|---|---|
| queue/lease | Exclusive time-bounded ownership of a message | auth |
EOF
run_lint "$fx/specs/GLOSSARY.md"
check_case "glossary: Defined in disagrees with the term prefix — error" 2 \
    "Defined in must equal the term prefix queue"

# No specs/ tree: a lone GLOSSARY.md with no sibling index.md —
# references are not collected, prefix resolution is skipped
fx=$work/no-refs
rm -rf "$fx"
mkdir -p "$fx"
cat > "$fx/GLOSSARY.md" <<'EOF'
# Specification Glossary

| Term | Definition | Defined in |
|---|---|---|
| queue/ack | Positive delivery confirmation from a consumer | queue |
EOF
run_lint "$fx/GLOSSARY.md"
check_case "glossary: no collected index references — warning, exit 1" 1 \
    "warning: no index references collected" \
    "!term ID must"

new_fixture spec-clean
std_index
run_lint "$fx/specs/queue.md"
check_case "spec: clean spec file — clean" 0

new_fixture spec-broken-rid
cat > "$fx/broken.md" <<'EOF'
# Broken Specification

Status: draft
Spec source of truth for: broken

## Requirements
- R1 The line lacks the period and space after the ID.
EOF
run_lint "$fx/broken.md"
check_case "spec: R entry with broken ID syntax — format error" 2 \
    "requirement ID must be followed by a period and a space"

new_fixture spec-literal
cat > "$fx/retry.md" <<'EOF'
# Retry Specification

Status: draft
Spec source of truth for: retry

## Requirements
- R1. The worker retries 3 times before dead-lettering.
EOF
run_lint "$fx/retry.md"
check_case "spec: bare numeric literal outside Configuration/Examples — literal error" 2 \
    "bare numeric literal (3)"

new_fixture index-bad-status
std_index
cat > "$fx/specs/bad.md" <<'EOF'
# Bad Specification

Status: draft
Spec source of truth for: bad
EOF
cat > "$fx/specs/index.md" <<'EOF'
# Specification Index

| Path | Reference | Status | Summary |
|---|---|---|---|
| specs/queue.md | queue | deprecated | Persistent queue delivery guarantees |
EOF
run_lint "$fx/specs/index.md"
check_case "index: invalid Status — error" 2 \
    "Status must be draft or stable, got: deprecated"

# -----------------------------------------------------------------------------

printf '%d run, %d failed\n' "$total" "$failed"
[ "$failed" -eq 0 ]
