# shellcheck shell=bash
# Test harness helpers.
#
# Sourced by tests/run.sh before any case file. Nothing here asserts anything
# about Igitari -- it only builds throwaway repos, provides assertions, and
# runs the notifications. Case files should read like a description of
# behaviour, not like scaffolding.

# A fresh repo in a temp dir, exported so Igitari sees it as the repo.
# Commits are dated in sequence so 'git log' order is deterministic.
new_repo() {
    WORK="$(mktemp -d "${TMPDIR:-/tmp}/igitari-test.XXXXXX")"
    cd "$WORK" || return 1
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test"
    git config commit.gpgsign false
    git config tag.gpgsign false
    export GIT_EDITOR=true
    export GIT_SEQUENCE_EDITOR=true
    export GIT_AUTHOR_DATE="2020-01-01T00:00:00+0000"
    export GIT_COMMITTER_DATE="2020-01-01T00:00:00+0000"
    export IGITARI_TEST=1
    # shellcheck source=/dev/null
    source "$IGITARI" >/dev/null 2>&1
}

# Commit a file with content, so histories are readable in failure output.
commit_file() {
    local name="$1" content="$2" msg="${3:-add $1}"
    printf '%s\n' "$content" > "$name"
    git add -- "$name"
    git commit -q -m "$msg"
}

cleanup_repo() {
    cd "$REPO_ROOT" || true
    [[ -n "${WORK:-}" && -d "${WORK:-}" ]] && rm -rf "$WORK"
    WORK=""
}

# --- assertions ----------------------------------------------------------
#
# Each records failure text and lets the test run on, so one broken assertion
# does not hide the next one in the same test.

ASSERT_ERRORS=""

fail_assert() {
    ASSERT_ERRORS+="    ${*}"$'\n'
}

assert_eq() {
    local actual="$1" expected="$2" what="${3:-value}"
    [[ "$actual" == "$expected" ]] || fail_assert "$what: expected [$expected], got [$actual]"
}

assert_contains() {
    local haystack="$1" needle="$2" what="${3:-output}"
    [[ "$haystack" == *"$needle"* ]] || fail_assert "$what: expected to find [$needle] in [$haystack]"
}

assert_file() {
    local path="$1" expected="$2"
    if [[ ! -f "$path" ]]; then
        fail_assert "$path: file does not exist"
        return
    fi
    assert_eq "$(cat "$path")" "$expected" "content of $path"
}

assert_no_file() {
    local path="$1"
    [[ -e "$path" ]] && fail_assert "$path: should not exist, but does"
}

assert_clean() {
    local st
    st=$(git status --porcelain 2>/dev/null)
    [[ -z "$st" ]] || fail_assert "worktree should be clean, got: [$st]"
}

# --- answering prompts ---------------------------------------------------

# Run a command that will ask a yes/no question, and answer 'y'.
#
# Igitari asks on /dev/tty on purpose (so a piped stdin cannot answer for
# you), which means a plain redirect gives no tty and the command correctly
# aborts. script(1) provides a pty so the prompt can actually be answered.
answer_yes() {
    local body="$1"
    local script_file
    script_file="$(mktemp "${TMPDIR:-/tmp}/igitari-answer.XXXXXX")"

    # The repo must be entered BEFORE sourcing: Igitari's startup does its own
    # path setup, so sourcing from the wrong directory inspects the wrong repo.
    #
    # Paths are written with single quotes rather than expanded, because this
    # project's own path contains '!' which history expansion would eat.
    {
        printf 'set -uo pipefail\n'
        printf 'export IGITARI_TEST=1 GIT_EDITOR=true GIT_SEQUENCE_EDITOR=true\n'
        printf 'cd %q || exit 1\n' "$WORK"
        printf 'source %q >/dev/null 2>&1\n' "$IGITARI"
        printf '%s\n' "$body"
    } >"$script_file"

    # The prompt can take a while to appear: decimate runs filter-branch and
    # prints pages of object counts first. Answering too early is silently
    # lost, so give it room and answer late.
    ( sleep 1.2; printf 'y\n'; sleep 2.5 ) \
        | script -qec "bash --norc $script_file" /dev/null >/dev/null 2>&1
    rm -f "$script_file"
}

# --- repository states ---------------------------------------------------
#
# Several guards are only interesting mid-operation, so those states are built
# by name rather than pasted into every test.

# Put the repo into a real conflicted merge.
make_conflicted_merge() {
    printf 'base\n' > f.txt
    git add -- f.txt && git commit -q -m base
    git checkout -q -b side
    printf 'theirs\n' > f.txt && git commit -q -am side
    git checkout -q master 2>/dev/null || git checkout -q main
    printf 'ours\n' > f.txt && git commit -q -am main
    git merge side >/dev/null 2>&1
    git diff --name-only --diff-filter=U | grep -q . \
        || fail_assert "setup: expected a conflict, got none"
}

# Put the repo into a stopped cherry-pick with a conflict.
make_conflicted_cherry_pick() {
    printf 'base\n' > f.txt
    git add -- f.txt && git commit -q -m base
    git checkout -q -b side
    printf 'theirs\n' > f.txt && git commit -q -am side
    local pick
    pick=$(git rev-parse HEAD)
    git checkout -q master 2>/dev/null || git checkout -q main
    printf 'ours\n' > f.txt && git commit -q -am main
    git cherry-pick "$pick" >/dev/null 2>&1
    [[ -f "$(git rev-parse --git-dir)/CHERRY_PICK_HEAD" ]] \
        || fail_assert "setup: expected a stopped cherry-pick"
}

# --- small facts ---------------------------------------------------------

# Number of commits on the current branch.
n_commits() {
    git rev-list --count HEAD 2>/dev/null || echo 0
}
