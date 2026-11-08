#!/usr/bin/env bash
# Test runner for Igitari.
#
# The tests live in tests/cases/*.sh, grouped by what they are about, and the
# shared scaffolding lives in tests/lib/. This file only finds them, runs them
# and reports. Adding a test means adding a function to the right case file --
# there is nothing to register.
#
# Usage:
#   tests/run.sh                run everything
#   tests/run.sh squash         run only tests whose name contains 'squash'
#   tests/run.sh --list         list test names, with the file they live in
#   tests/run.sh --files        list the case files instead
#
# Exit code is 0 only when every test passes.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
IGITARI="${REPO_ROOT}/igitari.sh"

# Colour only when talking to a terminal.
if [[ -t 1 ]]; then
    RED=$'\e[31m' GREEN=$'\e[32m' DIM=$'\e[2m' BOLD=$'\e[1m' OFF=$'\e[0m'
else
    RED='' GREEN='' DIM='' BOLD='' OFF=''
fi

# Igitari asks its yes/no questions on /dev/tty on purpose, so tests that need
# an answer have to run under a pty. script(1) provides one, but the flags
# differ between util-linux (Linux) and BSD (macOS). Detect it once, and skip
# rather than fail where it is unavailable -- a skipped prompt test is honest,
# a failed one would be a lie about the code.
HAVE_PTY=0
if command -v script >/dev/null 2>&1 &&
    script -qec "true" /dev/null >/dev/null 2>&1; then
    HAVE_PTY=1
fi

PASS=0
FAIL=0
SKIP=0
declare -a FAILED_NAMES=()

if [[ ! -f "$IGITARI" ]]; then
    echo "${RED}igitari.sh not found at ${IGITARI}${OFF}" >&2
    exit 1
fi

# shellcheck source=/dev/null
source "${TESTS_DIR}/lib/harness.sh"

# Load every case file. Sorted so runs are reproducible.
declare -a CASE_FILES=()
while IFS= read -r f; do CASE_FILES+=("$f"); done < <(find "${TESTS_DIR}/cases" -name '*.sh' -type f | sort)

if [[ ${#CASE_FILES[@]} -eq 0 ]]; then
    echo "${RED}no case files found in ${TESTS_DIR}/cases${OFF}" >&2
    exit 1
fi

# Which file each test came from, for --list and for failure reports.
declare -A TEST_FILE=()
for f in "${CASE_FILES[@]}"; do
    # Snapshot which functions exist before and after sourcing, so each test
    # can be attributed to the file that defined it.
    before=$(declare -F | awk '{print $3}' | sort)
    # Source in THIS shell, not in a command substitution: $(...) runs in a
    # subshell, so the functions it defines would vanish with it.
    _load_err="$(mktemp "${TMPDIR:-/tmp}/igitari-load.XXXXXX")"
    # shellcheck disable=SC1090  # case files are found at runtime
    if ! source "$f" 2>"$_load_err"; then
        echo "${RED}${f} failed to load:${OFF}" >&2
        sed 's/^/    /' "$_load_err" >&2
        rm -f "$_load_err"
        exit 1
    fi
    rm -f "$_load_err"
    after=$(declare -F | awk '{print $3}' | sort)
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        TEST_FILE["$name"]="$(basename "$f")"
    done < <(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | grep '^t_')
done

mapfile -t ALL_TESTS < <(printf '%s\n' "${!TEST_FILE[@]}" | sort)

FILTER="${1:-}"

if [[ "$FILTER" == "--files" ]]; then
    for f in "${CASE_FILES[@]}"; do echo "$(basename "$f")"; done
    exit 0
fi

if [[ "$FILTER" == "--list" ]]; then
    for t in "${ALL_TESTS[@]}"; do
        printf '%-34s %s\n' "${t#t_}" "${TEST_FILE[$t]}"
    done
    exit 0
fi

skip_test() {
    SKIP=$((SKIP + 1))
    printf '  %sskip%s %s %s(needs a pty)%s\n' "$DIM" "$OFF" "${1#t_}" "$DIM" "$OFF"
}

# Run one test in a fresh repo, then report. A test that calls for a pty is
# skipped when there is none, rather than failing for the wrong reason.
run_test() {
    local name="$1"
    ASSERT_ERRORS=""
    if [[ $HAVE_PTY -eq 0 ]] && grep -q "answer_yes\|script -qec" <<<"$(declare -f "$name")"; then
        skip_test "$name"
        return
    fi
    new_repo

    "$name"

    cleanup_repo

    if [[ -z "$ASSERT_ERRORS" ]]; then
        PASS=$((PASS + 1))
        printf '  %sok%s   %s\n' "$GREEN" "$OFF" "${name#t_}"
    else
        FAIL=$((FAIL + 1))
        FAILED_NAMES+=("${name#t_} (${TEST_FILE[$name]})")
        printf '  %sFAIL%s %s\n' "$RED" "$OFF" "${name#t_}"
        printf '%s' "$ASSERT_ERRORS" | sed 's/^/       /'
    fi
}

printf '%sIgitari tests%s %s(%d in %d files)%s\n\n' \
    "$BOLD" "$OFF" "$DIM" "${#ALL_TESTS[@]}" "${#CASE_FILES[@]}" "$OFF"

for t in "${ALL_TESTS[@]}"; do
    [[ -n "$FILTER" && "${t#t_}" != *"$FILTER"* ]] && continue
    run_test "$t"
done

printf '\n'
if ((FAIL == 0)); then
    if ((SKIP > 0)); then
        printf '%s%d passed, %d skipped%s\n' "$GREEN" "$PASS" "$SKIP" "$OFF"
    else
        printf '%s%d passed%s\n' "$GREEN" "$PASS" "$OFF"
    fi
    exit 0
fi

printf '%s%d passed, %d failed, %d skipped%s\n' "$RED" "$PASS" "$FAIL" "$SKIP" "$OFF"
printf 'failed:\n'
for n in "${FAILED_NAMES[@]}"; do printf '  %s\n' "$n"; done
exit 1
