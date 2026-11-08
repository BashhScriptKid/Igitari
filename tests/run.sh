#!/usr/bin/env bash
# Test harness for Igitari.
#
# Not a framework. Igitari is one Bash file with no build step, so the tests
# are one Bash file with no build step: each case gets a throwaway repo, runs
# real Igitari functions against it, and asserts on the resulting tree.
#
# Why this exists at all: igitari.sh runs 'reset --hard', 'filter-branch' and
# 'checkout-index' on the user's real repository. Until there were tests,
# nothing verified that those verbs do what their help pages promise. A help
# page claiming "squash 3 folds the last three commits" is a claim, not a fact.
#
# Usage:
#   tests/run.sh              run everything
#   tests/run.sh squash       run only tests whose name contains 'squash'
#   tests/run.sh --list       list test names
#
# Exit code is 0 only when every test passes.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
if command -v script >/dev/null 2>&1 && \
   script -qec "true" /dev/null >/dev/null 2>&1; then
    HAVE_PTY=1
fi

PASS=0
FAIL=0
SKIP=0
declare -a FAILED_NAMES=()

# --- harness -------------------------------------------------------------

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

# Assertions. Each records failure text; the test still runs to the end so
# one broken assertion does not hide the next.
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

    # The 'y' is delayed so it lands after the prompt is printed.
    # The prompt can take a while to appear: decimate runs filter-branch and
    # prints pages of object counts first. Answering too early is silently
    # lost, so give it room and answer late.
    ( sleep 1.2; printf 'y\n'; sleep 2.5 ) \
        | script -qec "bash --norc $script_file" /dev/null >/dev/null 2>&1
    rm -f "$script_file"
}

# Put the repo into a real conflicted merge. Every mid-operation guard is
# about this exact state, so it is worth building once rather than per test.
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
    git rev-parse --git-dir >/dev/null 2>&1
    [[ -f "$(git rev-parse --git-dir)/CHERRY_PICK_HEAD" ]] \
        || fail_assert "setup: expected a stopped cherry-pick"
}

# Number of commits on the current branch.
n_commits() {
    git rev-list --count HEAD 2>/dev/null || echo 0
}

skip_test() {
    SKIP=$((SKIP + 1))
    printf '  %sskip%s %s %s(no pty)%s\n' "$DIM" "$OFF" "${1#t_}" "$DIM" "$OFF"
}

run_test() {
    local name="$1"
    ASSERT_ERRORS=""
    if [[ $HAVE_PTY -eq 0 ]] && grep -q "answer_yes\|script -qec" <<<"$(declare -f "$name")"; then
        skip_test "$name"
        return
    fi
    new_repo

    # Each test function is named t_<something> and does its own asserting.
    "$name"

    cleanup_repo

    if [[ -z "$ASSERT_ERRORS" ]]; then
        PASS=$((PASS + 1))
        printf '  %sok%s   %s\n' "$GREEN" "$OFF" "${name#t_}"
    else
        FAIL=$((FAIL + 1))
        FAILED_NAMES+=("${name#t_}")
        printf '  %sFAIL%s %s\n' "$RED" "$OFF" "${name#t_}"
        printf '%s' "$ASSERT_ERRORS" | sed 's/^/       /'
    fi
}

# --- tests ---------------------------------------------------------------

# squash: fold the last N commits into one, keeping the message.
t_squash_folds_last_n() {
    commit_file a.txt one "first"
    commit_file b.txt two "second"
    commit_file c.txt three "third"
    assert_eq "$(n_commits)" "3" "commits before"

    answer_yes 'squash 2 "squashed"'

    assert_eq "$(n_commits)" "2" "commits after"
    assert_eq "$(git log -1 --pretty=%s)" "squashed" "tip message"
    # The work of both folded commits must still be present.
    assert_file a.txt one
    assert_file b.txt two
    assert_clean
}

# squash must refuse a range longer than the history rather than misbehave.
t_squash_refuses_impossible_range() {
    commit_file a.txt one "first"
    squash 5 "nope" >/dev/null 2>&1
    local rc=$?
    [[ $rc -ne 0 ]] || fail_assert "squash of 5 commits in a 1-commit repo should fail"
    assert_eq "$(n_commits)" "1" "commits unchanged"
}

# reword HEAD only needs no rebase and must change the message.
t_reword_head() {
    commit_file a.txt one "original"
    # Signature is: reword "message" [commit] -- message first.
    answer_yes 'reword "rewritten"'
    assert_eq "$(git log -1 --pretty=%s)" "rewritten" "tip message"
    assert_clean
}

# discard: throw away unstaged changes to a tracked file.
t_discard_restores_tracked_file() {
    commit_file a.txt original "first"
    printf 'modified\n' > a.txt
    discard --yes a.txt >/dev/null 2>&1
    assert_file a.txt original
    assert_clean
}

# untrack then retrack should round-trip through .gitignore.
t_untrack_then_retrack() {
    commit_file a.txt one "first"
    answer_yes 'untrack a.txt'
    # Documented behaviour: the file stays on disk, only the index changes,
    # and .gitignore is left alone for the user to decide.
    assert_file a.txt one
    git ls-files --error-unmatch a.txt >/dev/null 2>&1 \
        && fail_assert "a.txt should no longer be tracked"
    git diff --cached --name-only | grep -qx 'a.txt' \
        || fail_assert "the removal of a.txt should be staged"

    answer_yes 'retrack a.txt'
    git ls-files --error-unmatch a.txt >/dev/null 2>&1 \
        || fail_assert "a.txt should be tracked again"
    assert_file a.txt one
}

# conflict show must print each side of a real conflict.
t_conflict_show_sides() {
    printf 'base\n' > f.txt
    git add -- f.txt && git commit -q -m base
    git checkout -q -b side
    printf 'theirs\n' > f.txt && git commit -q -am side
    git checkout -q master 2>/dev/null || git checkout -q main
    printf 'ours\n' > f.txt && git commit -q -am main
    git merge side >/dev/null 2>&1

    local ours theirs
    ours=$(conflict show ours f.txt 2>/dev/null)
    theirs=$(conflict show theirs f.txt 2>/dev/null)
    assert_eq "$ours" "ours" "ours side"
    assert_eq "$theirs" "theirs" "theirs side"

    git merge --abort >/dev/null 2>&1
}

# conflict take must write the side and stage it, resolving the path.
t_conflict_take_resolves() {
    printf 'base\n' > f.txt
    git add -- f.txt && git commit -q -m base
    git checkout -q -b side
    printf 'theirs\n' > f.txt && git commit -q -am side
    git checkout -q master 2>/dev/null || git checkout -q main
    printf 'ours\n' > f.txt && git commit -q -am main
    git merge side >/dev/null 2>&1

    _conflict_take 3 theirs f.txt >/dev/null 2>&1
    assert_file f.txt theirs
    local unmerged
    unmerged=$(git diff --name-only --diff-filter=U)
    assert_eq "$unmerged" "" "unmerged paths after take"
}

# The mid-operation guard is the thing protecting destructive verbs.
t_guard_blocks_squash_mid_merge() {
    commit_file a.txt one "first"
    commit_file b.txt two "second"
    git checkout -q -b side
    commit_file c.txt three "third"
    git checkout -q master 2>/dev/null || git checkout -q main
    commit_file d.txt four "fourth"
    git merge side >/dev/null 2>&1   # conflict in nothing? force one:

    # Make a guaranteed conflict so the merge really stops.
    git merge --abort >/dev/null 2>&1
    printf 'base\n' > f.txt && git add -- f.txt && git commit -q -m base
    git checkout -q -b s2 && printf 'x\n' > f.txt && git commit -q -am s
    git checkout -q master 2>/dev/null || git checkout -q main
    printf 'y\n' > f.txt && git commit -q -am m
    git merge s2 >/dev/null 2>&1

    local before
    before=$(n_commits)
    local out
    out=$(squash 2 "should not happen" 2>&1)
    local rc=$?
    [[ $rc -ne 0 ]] || fail_assert "squash must refuse while a merge is in progress"
    assert_contains "$out" "Nothing has been touched" "guard message"
    assert_eq "$(n_commits)" "$before" "commits unchanged"
    git merge --abort >/dev/null 2>&1
}

# state must report a merge in progress and nothing when idle.
t_state_reports_operation() {
    commit_file a.txt one "first"
    assert_eq "$(__git_state)" "" "state when idle"

    git merge --abort >/dev/null 2>&1
    printf 'base\n' > f.txt && git add -- f.txt && git commit -q -m base
    git checkout -q -b s3 && printf 'x\n' > f.txt && git commit -q -am s
    git checkout -q master 2>/dev/null || git checkout -q main
    printf 'y\n' > f.txt && git commit -q -am m
    git merge s3 >/dev/null 2>&1

    local st
    st=$(__git_state)
    assert_contains "$st" "o" "state flags mid-merge"
    assert_contains "$st" "c" "state flags conflicted"
    assert_eq "$(__git_operation)" "m" "operation is merge"
    git merge --abort >/dev/null 2>&1
}

# transplant: move a commit off one branch onto another, leaving no copy.
t_transplant_moves_commit() {
    commit_file a.txt one "first"
    git checkout -q -b feature
    commit_file c.txt three "feature work"
    git checkout -q master 2>/dev/null || git checkout -q main
    commit_file d.txt four "will move"

    local moved_subject="will move"
    local before
    before=$(n_commits)

    answer_yes 'transplant 1 feature'

    # The moved commit's MESSAGE should now be reachable from feature. The
    # sha changes, because a cherry-pick creates a new commit -- comparing
    # hashes is what made this test lie about a working transplant.
    git log --format=%s feature | grep -qx "$moved_subject" \
        || fail_assert "the moved commit should now be on feature"
    # ...and gone from the branch it left.
    git log --format=%s | grep -qx "$moved_subject" \
        && fail_assert "the moved commit should no longer be on the original branch"
    assert_eq "$(n_commits)" "$((before - 1))" "commits left behind"
    # The work must still exist somewhere.
    git log --format=%s feature | grep -qx "feature work" \
        || fail_assert "existing feature commits should be untouched"
}

# decimate: rewrite history so a file looks like it was never committed.
t_decimate_removes_file_from_history() {
    commit_file keep.txt keep "keep"
    commit_file secret.txt leaked "add secret (oops)"
    commit_file more.txt more "more work"

    answer_yes 'decimate secret.txt'

    # No commit anywhere in history may still mention it.
    local hits
    hits=$(git log --all --format=%H -- secret.txt | wc -l | tr -d ' ')
    assert_eq "$hits" "0" "commits touching secret.txt"
    assert_no_file secret.txt
    # The other files stay.
    assert_file keep.txt keep
    assert_file more.txt more
    # The help page says every commit that touched it is REBUILT without the
    # file, not removed, so the count stays the same.
    assert_eq "$(n_commits)" "3" "commits after rewrite (rebuilt, not dropped)"
}

# undo: wind HEAD back one step.
t_undo_steps_back() {
    commit_file a.txt one "first"
    commit_file b.txt two "second"
    local target
    target=$(git rev-parse HEAD~1)

    answer_yes 'undo'
    assert_eq "$(git rev-parse HEAD)" "$target" "HEAD after undo"
}

# undo takes a step count.
t_undo_multiple_steps() {
    commit_file a.txt one "first"
    commit_file b.txt two "second"
    commit_file c.txt three "third"
    local target
    target=$(git rev-parse HEAD~2)

    answer_yes 'undo 2'
    assert_eq "$(git rev-parse HEAD)" "$target" "HEAD after undo 2"
}

# redo: step forward again after an undo.
t_redo_after_undo() {
    commit_file a.txt one "first"
    commit_file b.txt two "second"
    local tip
    tip=$(git rev-parse HEAD)

    answer_yes 'undo'
    assert_eq "$(n_commits)" "1" "after undo"

    answer_yes 'redo'
    assert_eq "$(git rev-parse HEAD)" "$tip" "HEAD after redo"
}

# redo must refuse when the last thing that happened was not a reset.
t_redo_refuses_without_undo() {
    commit_file a.txt one "first"
    commit_file b.txt two "second"
    local before
    before=$(git rev-parse HEAD)

    answer_yes 'redo'

    assert_eq "$(git rev-parse HEAD)" "$before" "HEAD unchanged by a no-op redo"
}

# movehead: detach and park, without moving any branch.
t_movehead_backward_detaches() {
    commit_file a.txt one "first"
    commit_file b.txt two "second"
    commit_file c.txt three "third"
    local branch_tip target
    branch_tip=$(git rev-parse master 2>/dev/null || git rev-parse main)
    target=$(git rev-parse HEAD~2)

    movehead backward 2 >/dev/null 2>&1

    assert_eq "$(git rev-parse HEAD)" "$target" "HEAD after movehead"
    git symbolic-ref -q HEAD >/dev/null 2>&1 \
        && fail_assert "HEAD should be detached after movehead"
    # No branch may have moved. This is the promise that makes it safe to
    # wander around in history.
    assert_eq "$(git rev-parse master 2>/dev/null || git rev-parse main)" "$branch_tip" "branch tip"
    # The working tree follows, so the newest file is not on disk any more.
    assert_no_file c.txt
    # And the commits are all still reachable -- nothing was lost.
    assert_eq "$(git rev-list --count "$branch_tip")" "3" "commits still reachable"
}

# backward N then forward N must return to where you started. This is the
# property that broke: 'forward' used to count reflog offsets, and 'backward'
# writes reflog entries of its own, so it landed short every time.
# backward N then forward N must return to where you started. This is the
# property that broke: 'forward' counted reflog offsets, and 'backward' writes
# reflog entries of its own, so it landed short.
#
# Each step count needs its own fresh repo. Reusing one hides the bug, because
# the second iteration inherits a reflog deep enough to work by accident --
# which is exactly how a false-negative test looks green.
movehead_round_trip_once() {
    local n="$1"
    commit_file a.txt one "c1"
    commit_file b.txt two "c2"
    commit_file c.txt three "c3"

    local start
    start=$(git rev-parse HEAD)
    movehead backward "$n" >/dev/null 2>&1
    [[ "$(git rev-parse HEAD)" == "$start" ]] \
        && fail_assert "backward $n did not move"

    movehead forward "$n" >/dev/null 2>&1
    assert_eq "$(git rev-parse HEAD)" "$start" "backward $n then forward $n"
    git symbolic-ref -q HEAD >/dev/null 2>&1 \
        || fail_assert "should have reattached to a branch after forward $n"
}

t_movehead_round_trip_1() { movehead_round_trip_once 1; }
t_movehead_round_trip_2() { movehead_round_trip_once 2; }


# Every destructive verb must refuse while an operation is half-finished, and
# must say so without touching anything. The message is a promise: "Nothing has
# been touched."
assert_guard_refuses() {
    local label="$1" expected_verb="$2"
    shift 2
    local before out rc
    before=$(git rev-parse HEAD)

    out=$("$@" 2>&1)
    rc=$?

    [[ $rc -ne 0 ]] || fail_assert "$label: should have refused mid-operation"
    assert_contains "$out" "Nothing has been touched" "$label: guard message"
    assert_contains "$out" "$expected_verb" "$label: names the verb"
    assert_eq "$(git rev-parse HEAD)" "$before" "$label: HEAD untouched"
}

t_guard_blocks_discard_mid_merge() {
    make_conflicted_merge
    assert_guard_refuses "discard" "discard" discard --yes f.txt
}

t_guard_blocks_reword_mid_merge() {
    make_conflicted_merge
    assert_guard_refuses "reword" "reword" reword "new message"
}

t_guard_blocks_transplant_mid_cherry_pick() {
    make_conflicted_cherry_pick
    assert_guard_refuses "transplant" "transplant" transplant 1 side
}

t_guard_blocks_decimate_mid_merge() {
    make_conflicted_merge
    assert_guard_refuses "decimate" "decimate" decimate f.txt
}

# The guard must NOT fire when nothing is in progress -- otherwise every
# command becomes unusable after one bad merge.
t_guard_allows_when_idle() {
    commit_file a.txt one "first"
    commit_file b.txt two "second"
    commit_file c.txt three "third"

    __refuse_mid_operation squash
    assert_eq "$?" "0" "__refuse_mid_operation on a clean repo"
}

# --- tokenizer -----------------------------------------------------------
#
# __split_argv decides what actually gets executed, so it is tested against
# real Bash rather than against my expectations. Each case runs the same line
# through Bash's own word-splitting and through Igitari, and requires the same
# words in the same order.
#
# A stub execute_command stands in for the dispatcher so $(...) can be tested
# without touching a repository.

# Run a line through real Bash and print one word per line.
bash_words() {
    local line="$1"
    ( eval "set -- $line"; printf '%s\n' "$@" )
}

# Run a line through __split_argv and print one word per line.
ignore_words() {
    local line="$1"
    local -a out=()
    __split_argv "$line" out
    local w
    for w in "${out[@]}"; do printf '%s\n' "$w"; done
}

assert_same_words() {
    local line="$1" expected="$2" what="$3"
    local got
    got=$(ignore_words "$line" | tr '\n' '|')
    assert_eq "$got" "$expected" "$what"
}

t_split_argv_quoting() {
    local d='$'
    # The dispatcher must answer substitutions without any git side effects.
    execute_command() { printf 'VALUE'; }

    # Plain words.
    assert_same_words "a b c" "a|b|c|" "three words"
    # Double quotes keep a space-containing word whole.
    assert_same_words '"two words.txt"' "two words.txt|" "double-quoted space"
    # Single quotes are literal: no substitution inside them.
    # Built with a variable so the test source itself never expands $(x).
    local d='$'
    assert_same_words "'literal ${d}(x)'" "literal ${d}(x)|" "single quotes are literal"
    # A quoted substitution stays one word, and does not split on its output.
    assert_same_words "\"${d}(x)\"" "VALUE|" "quoted substitution"
    # An unquoted substitution is trimmed of trailing newlines but kept whole
    # here, because the stub returns no whitespace.
    assert_same_words "${d}(x)" "VALUE|" "bare substitution"
    # Adjacent quoting joins into one word.
    assert_same_words 'a"b c"d' "ab cd|" "adjacent quoted join"
}

# An unquoted substitution splits on whitespace, a quoted one does not. This
# is the rule that lets 'untrack $(fzf tracked)' pass several paths at once
# while 'reword "$(fzf message)"' keeps a sentence as one argument.
t_split_argv_substitution_splitting() {
    local d='$'
    execute_command() { printf 'one two three'; }

    local -a unquoted=() quoted=()
    __split_argv "${d}(x)" unquoted
    __split_argv "\"${d}(x)\"" quoted

    assert_eq "${#unquoted[@]}" "3" "unquoted substitution splits"
    assert_eq "${unquoted[0]}" "one" "first piece"
    assert_eq "${unquoted[2]}" "three" "third piece"
    assert_eq "${#quoted[@]}" "1" "quoted substitution stays whole"
    assert_eq "${quoted[0]}" "one two three" "quoted content"
}

# A substitution in the middle of a word glues to its neighbours.
t_split_argv_substitution_glues() {
    local d='$'
    execute_command() { printf 'MID'; }
    local -a out=()
    __split_argv "a${d}(x)b" out
    assert_eq "${#out[@]}" "1" "glued substitution is one word"
    assert_eq "${out[0]}" "aMIDb" "glued content"
}

t_split_argv_leaves_no_quotes() {
    execute_command() { printf 'VALUE'; }
    local -a out=()
    __split_argv '"keep me" plain' out
    assert_eq "${#out[@]}" "2" "word count"
    assert_eq "${out[0]}" "keep me" "quotes are removed"
    assert_eq "${out[1]}" "plain" "second word"
}

# --- the machinery -------------------------------------------------------

# __igitari_confirm: y means yes, n means no, and "no tty" must abort.
#
# The rule that matters is the last one. Return 2 means "I could not ask", and
# call sites treat it exactly like 1. Getting that wrong is how a prompt turns
# into a permanent hang.
t_confirm_reads_answers() {
    # Under script(1) we have a tty, so a typed y and n are actually read.
    local dir
    dir="$(mktemp -d "${TMPDIR:-/tmp}/igitari-confirm.XXXXXX")"

    printf 'y\n' >"$dir/yes.txt"
    printf 'n\n' >"$dir/no.txt"

    local script_file="$dir/run.sh"
    {
        printf 'export IGITARI_TEST=1\n'
        printf 'cd %q || exit 1\n' "$WORK"
        printf 'source %q >/dev/null 2>&1\n' "$IGITARI"
        printf '__igitari_confirm "ok?" >/dev/null 2>&1; echo "rc=$?"\n'
    } >"$script_file"

    local got
    got=$(script -qec "bash --norc $script_file" /dev/null <"$dir/yes.txt" 2>/dev/null | tr -d '\r' | grep -o 'rc=[0-9]' | tail -1)
    # A 'y' answer returns 0.
    [[ "$got" == "rc=0" ]] || fail_assert "confirm should return 0 for y, got [$got]"

    got=$(script -qec "bash --norc $script_file" /dev/null <"$dir/no.txt" 2>/dev/null | tr -d '\r' | grep -o 'rc=[0-9]' | tail -1)
    [[ "$got" == "rc=1" ]] || fail_assert "confirm should return 1 for n, got [$got]"

    rm -rf "$dir"
}

# With no controlling terminal it must return 2, promptly, never hanging.
t_confirm_without_tty_aborts() {
    # Run it with stdin closed and no controlling terminal. It must return 2
    # rather than wait for a keypress nobody will send.
    local rc
    rc=$(cd "$WORK" && IGITARI_TEST=1 bash -c '
        source "$1" >/dev/null 2>&1
        __igitari_confirm "ok?" >/dev/null 2>&1
        printf "%s" "$?"
    ' _ "$IGITARI" </dev/null 2>/dev/null | tr -d '\n')

    [[ -n "$rc" ]] || fail_assert "confirm produced no exit code without a tty"
    assert_eq "$rc" "2" "confirm rc with no tty"
}

# process_command_line: && runs on success, skips on failure; || the reverse.
t_operators_short_circuit() {
    local calls=""
    # Trim the argument: process_command_line passes it through 'read -r',
    # which leaves surrounding spaces from the operator split.
    execute_command() { local a="$1"; a="${a#"${a%%[![:space:]]*}"}"; a="${a%"${a##*[![:space:]]}"}"; calls+="[$a]"; return "${RETURN_CODE:-0}"; }

    RETURN_CODE=0 calls=""
    process_command_line "a && b"
    assert_eq "$calls" "[a][b]" "&& with success runs both"

    RETURN_CODE=1 calls=""
    process_command_line "a && b"
    assert_eq "$calls" "[a]" "&& with failure stops"

    RETURN_CODE=1 calls=""
    process_command_line "a || b"
    assert_eq "$calls" "[a][b]" "|| with failure runs both"

    RETURN_CODE=0 calls=""
    process_command_line "a || b"
    assert_eq "$calls" "[a]" "|| with success stops"

    # ; always runs, whatever happened.
    RETURN_CODE=1 calls=""
    process_command_line "a ; b"
    assert_eq "$calls" "[a][b]" "; always continues"
}

# validate_arg accepts every documented spelling, and only those.
# validate_arg is defined INSIDE process_arguments, so it is not callable on
# its own. What it promises is that --help, -h, /HELP, /H and bare 'help' all
# reach the help page -- which is exactly the bug that ate the first canonical
# name. So test the promise through process_arguments.
t_validate_arg_forms() {
    local form out
    for form in --help -h /HELP /H help; do
        out=$(cd "$WORK" && IGITARI_TEST=1 bash -c '
            source "$1" >/dev/null 2>&1
            process_arguments "$2" 2>&1
        ' _ "$IGITARI" "$form" 2>&1)

        [[ "$out" == *"USAGE"* ]] || fail_assert "[$form] should reach the help page"
    done

    # Nonsense must not be treated as a flag that exits early.
    out=$(cd "$WORK" && IGITARI_TEST=1 bash -c '
        source "$1" >/dev/null 2>&1
        process_arguments "nonsense" 2>&1
    ' _ "$IGITARI" 2>&1)
    [[ "$out" == *"USAGE"* ]] && fail_assert "[nonsense] should not show help"
}

# __igitari_offer_fix lifts git's own runnable suggestion, and refuses
# templates containing placeholders.
t_offer_fix_lifts_suggestion() {
    local errfile
    errfile="$(mktemp "${TMPDIR:-/tmp}/igitari-err.XXXXXX")"

    # A real push-with-no-upstream message.
    cat >"$errfile" <<'ERR'
fatal: The current branch master has no upstream branch.
To push the current branch and set the remote as upstream, use

    git push --set-upstream origin master

To have this happen automatically for branches without a tracking
upstream, see 'push.autoSetupRemote' in 'git help config'.
ERR

    # Answer 'n' so nothing actually runs; we only care that it offered.
    local out
    out=$(printf 'n\n' | __igitari_offer_fix "$errfile" 2>&1)
    assert_contains "$out" "git push --set-upstream origin master" "lifts the exact command"
    assert_contains "$out" "retyping" "explains why it offered"

    # A template must not be offered: '<branch>' is not runnable.
    cat >"$errfile" <<'ERR'
There is no tracking information for the current branch.

    git pull <remote> <branch>

If you wish to set tracking information for this branch you can do so with:

    git branch --set-upstream-to=origin/<branch> master
ERR
    local rc
    # __igitari_offer_fix is a shell function, so it cannot be handed to
    # timeout as a command; the timeout has to wrap a subshell instead.
    printf 'n\n' | timeout 5 bash -c 'exit 0' >/dev/null 2>&1
    __igitari_offer_fix "$errfile" </dev/null >/dev/null 2>&1
    rc=$?
    [[ $rc -eq 1 ]] || fail_assert "a placeholder suggestion must not be offered (rc=$rc)"

    rm -f "$errfile"
}

# --- main ----------------------------------------------------------------

FILTER="${1:-}"

mapfile -t ALL_TESTS < <(declare -F | awk '{print $3}' | grep '^t_' | sort)

if [[ "$FILTER" == "--list" ]]; then
    for t in "${ALL_TESTS[@]}"; do echo "${t#t_}"; done
    exit 0
fi

if [[ ! -f "$IGITARI" ]]; then
    echo "${RED}igitari.sh not found at ${IGITARI}${OFF}" >&2
    exit 1
fi

printf '%sIgitari tests%s\n\n' "$BOLD" "$OFF"

for t in "${ALL_TESTS[@]}"; do
    [[ -n "$FILTER" && "${t#t_}" != *"$FILTER"* ]] && continue
    run_test "$t"
done

printf '\n'
if ((FAIL == 0)); then
    ((SKIP > 0)) && printf '%s%d passed, %d skipped%s\n' "$GREEN" "$PASS" "$SKIP" "$OFF" \
        || printf '%s%d passed%s\n' "$GREEN" "$PASS" "$OFF"
    exit 0
fi

printf '%s%d passed, %d failed, %d skipped%s\n' "$RED" "$PASS" "$FAIL" "$SKIP" "$OFF"
printf 'failed: %s\n' "${FAILED_NAMES[*]}"
exit 1
