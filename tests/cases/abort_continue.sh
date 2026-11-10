# shellcheck shell=bash
# abort / continue: stop or carry on whichever half-finished operation is running.
#
# 'continue' is a case arm and not a function, so it is called here the way a
# user would type it -- through the dispatcher -- rather than directly.

t_abort_nothing() {
    commit_file a.txt one "first"
    local out rc
    out=$(abort 2>&1); rc=$?
    [[ $rc -ne 0 ]] || fail_assert "abort with nothing in progress should fail"
    assert_contains "$out" "Nothing in progress" "abort with nothing in progress"
}

t_continue_nothing() {
    commit_file a.txt one "first"
    local out rc
    out=$(execute_cmd 'continue' 2>&1); rc=$?
    [[ $rc -ne 0 ]] || fail_assert "continue with nothing in progress should fail"
    assert_contains "$out" "Nothing in progress" "continue with nothing in progress"
}

t_abort_merge() {
    printf 'base\n' > f.txt && git add -- f.txt && git commit -q -m base
    git checkout -q -b side
    printf 'side\n' > f.txt && git commit -q -am side
    git checkout -q master 2>/dev/null || git checkout -q main
    printf 'main\n' > f.txt && git commit -q -am main
    git merge side >/dev/null 2>&1 || true

    local out
    out=$(abort --yes 2>&1)
    assert_eq "$(__git_operation 2>/dev/null || true)" "" "merge aborted"
    assert_contains "$out" "conflict resolutions" "abort merge warns about resolutions"
}

t_continue_merge_blocked_by_conflicts() {
    printf 'base\n' > f.txt && git add -- f.txt && git commit -q -m base
    git checkout -q -b side
    printf 'side\n' > f.txt && git commit -q -am side
    git checkout -q master 2>/dev/null || git checkout -q main
    printf 'main\n' > f.txt && git commit -q -am main
    git merge side >/dev/null 2>&1 || true

    local out rc
    out=$(execute_cmd 'continue --yes' 2>&1); rc=$?
    [[ $rc -ne 0 ]] || fail_assert "continue should refuse with unmerged paths"
    assert_contains "$out" "Unmerged paths remain" "continue refuses unmerged"
}

# The reason the verb is a case arm and not a function: a bash function
# called 'continue' shadows the builtin for the whole session, which is what
# broke twenty-two tests when the command wore that name.
#
# This runs in the shell the harness sourced Igitari into, so it is the real
# collision and not a rehearsal of it.
t_continue_does_not_shadow_the_builtin() {
    local out=""

    for i in 1 2 3; do
        out+="$i "
        continue
        out+="SHOULD-NOT-REACH "
    done

    assert_eq "$out" "1 2 3 " "the builtin still skips to the next iteration"
}

# And the thing it is for: carrying on a half-finished operation once the
# conflict is resolved. The refusal cases above only prove it says no.
t_continue_carries_on_a_merge() {
    printf 'base\n' > f.txt && git add -- f.txt && git commit -q -m base
    git checkout -q -b side
    printf 'side\n' > f.txt && git commit -q -am side
    git checkout -q master 2>/dev/null || git checkout -q main
    printf 'main\n' > f.txt && git commit -q -am main
    git merge side >/dev/null 2>&1 || true

    # Resolve it the way a user would, then let the command finish the job.
    printf 'resolved\n' > f.txt
    git add -- f.txt

    local out rc
    out=$(execute_cmd 'continue --yes' 2>&1); rc=$?

    assert_eq "$rc" 0 "continue finished the merge"
    assert_eq "$(__git_operation 2>/dev/null || true)" "" "no operation left in progress"
    assert_contains "$(git log --format=%s -1)" "Merge" "the merge commit was made"
}
