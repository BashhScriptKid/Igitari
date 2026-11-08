# shellcheck shell=bash
# Verbs that move the working tree around: discard, untrack, retrack.
#
# The theme here is that "throw away changes" and "stop tracking a file" are
# different operations, and the help pages are explicit about which is which.

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
