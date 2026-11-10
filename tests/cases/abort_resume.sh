# shellcheck shell=bash
# abort / resume: stop or carry on whichever half-finished operation is running.

t_abort_nothing() {
    commit_file a.txt one "first"
    local out rc
    out=$(abort 2>&1); rc=$?
    [[ $rc -ne 0 ]] || fail_assert "abort with nothing in progress should fail"
    assert_contains "$out" "Nothing in progress" "abort with nothing in progress"
}

t_resume_nothing() {
    commit_file a.txt one "first"
    local out rc
    out=$(resume 2>&1); rc=$?
    [[ $rc -ne 0 ]] || fail_assert "resume with nothing in progress should fail"
    assert_contains "$out" "Nothing in progress" "resume with nothing in progress"
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

t_resume_merge_blocked_by_conflicts() {
    printf 'base\n' > f.txt && git add -- f.txt && git commit -q -m base
    git checkout -q -b side
    printf 'side\n' > f.txt && git commit -q -am side
    git checkout -q master 2>/dev/null || git checkout -q main
    printf 'main\n' > f.txt && git commit -q -am main
    git merge side >/dev/null 2>&1 || true

    local out rc
    out=$(resume --yes 2>&1); rc=$?
    [[ $rc -ne 0 ]] || fail_assert "resume should refuse with unmerged paths"
    assert_contains "$out" "Unmerged paths remain" "resume refuses unmerged"
}
