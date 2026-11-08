# shellcheck shell=bash
# Moving HEAD around: undo, redo, movehead.
#
# Every test here is about stepping backwards that must be reversible or must
# refuse. 'backward N then forward N' is the property that broke.

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
