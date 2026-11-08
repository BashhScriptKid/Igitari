# shellcheck shell=bash
# Verbs that rewrite history: squash, reword, transplant, decimate.
#
# These rebuild commits, so the assertions are about what survives: the work
# must still be there, the file that should be gone must be gone from every
# commit, and nothing may be left uncommitted afterwards.

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
