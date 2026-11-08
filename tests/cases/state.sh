# shellcheck shell=bash
# Operator-state detection.
#
# __git_state is a string of co-occurring facts, not an enum, so the tests ask
# whether a fact is present rather than indexing into it. 'o' is a pointer
# ("something is half-done, go ask") and __git_operation expands it.

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
