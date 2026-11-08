# shellcheck shell=bash
# guess — print a value, print nothing else.
#
# The contract these tests protect is the silent part: on failure stdout must
# be EMPTY, because the output is meant to be pasted into $(...). An error on
# stdout would become the argument; an empty line would become ''.

t_guess_root_is_the_worktree() {
    commit_file a.txt one "first"
    assert_eq "$(guess root)" "$(git rev-parse --show-toplevel)" "guess root"
}

t_guess_prior_is_the_branch_we_left() {
    commit_file a.txt one "first"
    git checkout -q -b feature
    commit_file b.txt two "feature work"
    git checkout -q master 2>/dev/null || git checkout -q main
    git checkout -q feature

    assert_eq "$(guess prior)" "master" "the branch before feature"
}

t_guess_merge_base_matches_git() {
    commit_file f.txt base "base"
    git checkout -q -b feature
    commit_file f.txt theirs "feature change"
    git checkout -q master 2>/dev/null || git checkout -q main
    commit_file f.txt ours "master change"
    git merge feature >/dev/null 2>&1 || true

    assert_eq "$(guess merge-base)" "$(git merge-base HEAD MERGE_HEAD)" \
        "guess merge-base should agree with git's own answer"

    git merge --abort >/dev/null 2>&1
}

t_guess_rebase_base_matches_the_onto_file() {
    commit_file f.txt base "base"
    git checkout -q -b feature
    commit_file f.txt theirs "feature change"
    git checkout -q master 2>/dev/null || git checkout -q main
    commit_file f.txt ours "master change"
    git checkout -q feature

    GIT_SEQUENCE_EDITOR="sed -i '1s/^pick/edit/'" \
        git -c core.editor=true rebase -i master >/dev/null 2>&1 || true

    if [[ -f .git/rebase-merge/onto ]]; then
        assert_eq "$(guess rebase-base)" "$(cat .git/rebase-merge/onto)" \
            "guess rebase-base should agree with the onto file"
        git rebase --abort >/dev/null 2>&1
    fi
}

# The one that matters for composability: nothing on stdout when it fails.
t_guess_prints_nothing_on_stdout_when_it_fails() {
    commit_file a.txt one "first"

    local out status=0
    out=$(guess merge-base 2>/dev/null) || status=$?

    assert_eq "$out" "" "stdout when there is no merge"
    ((status != 0)) || fail_assert "a failed guess should return non-zero"

    # Same rule for an unknown word.
    out=$(guess nonsense 2>/dev/null) || status=$?
    assert_eq "$out" "" "stdout for an unknown context"
    ((status != 0)) || fail_assert "an unknown context should return non-zero"
}

# And the value itself is usable where a value would go.
t_guess_composes_in_a_substitution() {
    commit_file a.txt one "first"
    git checkout -q -b feature
    commit_file b.txt two "feature work"
    git checkout -q master 2>/dev/null || git checkout -q main
    git checkout -q feature

    local target
    target=$(guess prior)
    assert_eq "$target" "master" "value captured from \$(guess prior)"
    assert_eq "$(git rev-parse --abbrev-ref "$target")" "master" \
        "the captured value should be a usable ref"
}

# In a working copy that has never switched branches, @{-1} does not resolve
# at all and git fails with 'ambiguous argument'. That must become a sentence,
# and stdout must stay empty.
t_guess_prior_refuses_when_there_is_no_prior() {
    commit_file a.txt one "first"

    local out status=0
    out=$(guess prior 2>/dev/null) || status=$?

    assert_eq "$out" "" "stdout when there is no previous branch"
    ((status != 0)) || fail_assert "no previous branch should return non-zero"
}
