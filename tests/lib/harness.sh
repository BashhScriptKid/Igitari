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

    # Never let a test reach the developer's desktop, the terminal, or the
    # network. 'openweb' ends in 'xdg-open "$url" &', so every assertion about
    # a URL was launching the real browser -- with a locked profile, one
    # "Firefox is already running" dialog each. The rest are the same class of
    # accident waiting to happen: 'lazygit' and a bare 'fzf' take over the
    # tty, and the updater curls GitHub.
    #
    # Stubbed here rather than in each case so new cases inherit the safety,
    # and kept OUTSIDE the repo so the stub files cannot make it dirty.
    #
    # GUI and TUI fakes claim success (a test that opens a page only needs the
    # URL it built). Network fakes fail, so an unexpected fetch is visible
    # rather than quietly answered by the developer's connection.
    STUB_BIN="$(mktemp -d "${TMPDIR:-/tmp}/igitari-stub.XXXXXX")"
    for _desktop in xdg-open open lazygit fzf zenity kdialog notify-send; do
        printf '#!/bin/sh\nexit 0\n' >"$STUB_BIN/$_desktop"
        chmod +x "$STUB_BIN/$_desktop"
    done
    for _network in curl wget; do
        printf '#!/bin/sh\nexit 1\n' >"$STUB_BIN/$_network"
        chmod +x "$STUB_BIN/$_network"
    done
    export PATH="$STUB_BIN:$PATH"

    git init -q
    git config user.email "test@example.com"
    git config user.name "Test User"
    git config commit.gpgsign false
    git config tag.gpgsign false
    export GIT_EDITOR=true
    export GIT_SEQUENCE_EDITOR=true
    export GIT_AUTHOR_DATE="2020-01-01T00:00:00+0000"
    export GIT_COMMITTER_DATE="2020-01-01T00:00:00+0000"
    export IGITARI_TEST=1

    # Igitari itself is NOT sourced here. new_repo is a function, so a
    # `declare -A` at Igitari's top level would create a local variable in
    # this function's scope and vanish when it returns -- which is exactly
    # why _COMPLETE_HANDLERS was invisible to every test that asked for it.
    # Functions survived (declare -f is global) so the gap went unnoticed
    # until a test needed one of her associative tables.
    #
    # Sourcing here keeps every test starting from the same globals, which
    # several depend on (session config, for one, would otherwise carry a
    # previous test's settings into the next). It is safe for the associative
    # tables because this runs inside a function and so do they -- see
    # load_igitari below, which does the real load at top level.
    load_igitari
}

# Run a command through Igitari's own dispatcher, as if typed at its prompt.
#
# Use this for anything that does not prompt: it exercises the real dispatch
# path (so 'config session ...' is intercepted exactly as a user's would be)
# without needing a pty. Commands that ask a question need answer_yes instead.
execute_cmd() {
    execute_command "$1"
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
    [[ -n "${STUB_BIN:-}" && -d "${STUB_BIN:-}" ]] && rm -rf "$STUB_BIN"
    WORK=""
    STUB_BIN=""
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

# The other half of assert_contains: for proving a string did NOT come from
# somewhere, which is how 'this never reached git' is expressed.
assert_not_contains() {
    local haystack="$1" needle="$2" what="${3:-output}"
    [[ "$haystack" != *"$needle"* ]] || fail_assert "$what: did not expect to find [$needle] in [$haystack]"
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

    # The answer cannot simply be written up front: a pty buffers input
    # before the prompt exists, and anything sent early is flushed away when
    # the reading process starts. So keep offering 'y' at short intervals
    # until the command is done -- extra characters are harmless, and the
    # whole thing finishes as soon as the command exits instead of waiting
    # out a fixed sleep.
    #
    # Bounded by ANSWER_LIMIT so a genuinely stuck command still ends. A test
    # that hangs is worse than one that fails.
    (
        for _ in $(seq 1 "${ANSWER_LIMIT:-20}"); do
            printf 'y\n' 2>/dev/null || exit 0
            sleep 0.15
        done
    ) | timeout "${ANSWER_TIMEOUT:-30}" script -qec "bash --norc $script_file" /dev/null >/dev/null 2>&1 || true
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

# --- tab completion ------------------------------------------------------

# Ask Igitari to complete a line, as if the user typed it and pressed Tab.
#
# complete_git_env reads READLINE_LINE and READLINE_POINT and writes them
# back, so it can be driven directly -- no pty needed. Two things are
# stubbed: display_completions, which would print a menu and block on a
# y/n prompt over /dev/tty, and the fzf picker, which would try to take
# over the terminal. What each test checks is the buffer the insertion
# leaves behind, which is the part a user actually sees.
#
# Sets:
#   COMPLETION_LINE   the line after Tab
#   COMPLETION_POINT  the cursor position after Tab
#   COMPLETION_WORDS  the candidates that were offered, space separated
complete_line() {
    local line="$1"
    local offered_file
    offered_file="$(mktemp "${TMPDIR:-/tmp}/igitari-offer.XXXXXX")"

    # Both stubs are saved and restored rather than simply unset: Igitari
    # defines real versions of __check_fzf and display_completions, and she is
    # now sourced once for the whole run (see the bottom of this file). Leaving
    # them unset would take the real ones away from every later test.
    local had_check_fzf=0 had_display=0
    declare -f __check_fzf >/dev/null && had_check_fzf=1
    declare -f display_completions >/dev/null && had_display=1

    # display_completions would print a menu and block on a y/n prompt over
    # /dev/tty. Recording the candidates is all a test needs.
    # shellcheck disable=SC2329  # called by complete_git_env, not here
    display_completions() { printf '%s\n' "$@" >"$offered_file"; }
    # The fzf picker would try to take over the terminal.
    # shellcheck disable=SC2329  # called by the handlers, not here
    __check_fzf() { return 1; }

    READLINE_LINE="$line"
    READLINE_POINT=${#line}
    complete_git_env 2>/dev/null

    COMPLETION_LINE="$READLINE_LINE"
    # Exposed alongside the line for tests that care where the cursor lands.
    # shellcheck disable=SC2034  # read by tests, not by this file
    COMPLETION_POINT="$READLINE_POINT"
    COMPLETION_WORDS="$(tr '\n' ' ' <"$offered_file" 2>/dev/null)"
    COMPLETION_WORDS="${COMPLETION_WORDS% }"

    rm -f "$offered_file"
    ((had_check_fzf)) || unset -f __check_fzf
    ((had_display)) || unset -f display_completions
}

# Assert that completing <line> leaves the buffer equal to <expected>.
assert_completes_to() {
    local line="$1" expected="$2"
    complete_line "$line"
    assert_eq "$COMPLETION_LINE" "$expected" "completing [$line]"
}

# Assert that completing <line> offers <word> among the candidates.
assert_offers() {
    local line="$1" word="$2"
    complete_line "$line"
    [[ " $COMPLETION_WORDS " == *" $word "* ]] \
        || fail_assert "completing [$line]: expected [$word] in [$COMPLETION_WORDS]"
}

# Assert that completing <line> offers no candidates at all. Used for the
# positions where offering something would be inventing an argument.
assert_offers_nothing() {
    local line="$1"
    complete_line "$line"
    assert_eq "$COMPLETION_WORDS" "" "candidates for [$line]"
}

# --- loading Igitari -----------------------------------------------------

# Igitari is sourced at the BOTTOM of this file, at top level, and that
# placement is the point.
#
# Sourcing from inside a function would make every `declare` and `readonly` at
# the top of the script local to that function. The functions all survive,
# because `declare -f` always defines globally, so the loss stays invisible
# until something reaches for an associative table -- which is how
# _COMPLETE_HANDLERS turned out to be missing from every test that asked.
#
# new_repo still calls this so a test can assume the functions are there; the
# variable guard makes the second and later calls free.
# IGITARI_TEST must be set BEFORE the source, not just inside new_repo: the
# script calls main "$@" at the end unless it is set, and a sourced main runs
# her setup -- which re-declares state in a way that leaves her associative
# tables local to whatever called this. Setting it here is what makes the
# tables survive to the tests.
export IGITARI_TEST=1

# --- loading Igitari -----------------------------------------------------

# Two loads happen, on purpose.
#
# The top-level one below runs once and is what makes Igitari's associative
# tables (COMPLETE_HANDLERS and friends) global. `declare` inside a function
# makes a LOCAL, and functions survive anyway because `declare -f` defines
# globally -- so sourcing only from new_repo left those tables invisible to
# every test, unnoticed until a test asked for one.
#
# The per-test one inside new_repo still has to happen, because several tests
# depend on starting from untouched globals. Called from a function, the
# tables it declares are local to it and the global ones from here survive.
load_igitari() {
    # shellcheck source=/dev/null
    source "$IGITARI" >/dev/null 2>&1
}

# shellcheck source=/dev/null
source "$IGITARI" >/dev/null 2>&1
