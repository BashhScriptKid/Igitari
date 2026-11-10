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

# unstage -- the one exception to "never rename a verb git already has".
# The word is the point: it takes things back out of the index without
# touching the working tree, and it says so when it cannot.
#
# It is also the inverse of 'git add', with git add's grammar: the same
# pathspecs, the same flags. These pin both halves of that.
t_unstage_one_file_leaves_the_index() {
    commit_file a.txt one "first"
    echo b > b.txt
    git add b.txt

    execute_cmd "unstage b.txt"

    assert_eq "$(git diff --cached --name-only)" "" "the index after unstage"
    assert_eq "$(cat b.txt)" "b" "the working-tree file must survive"
}

# 'git add' wants a pathspec, so 'unstage' does too: on its own it says
# nothing was specified and stops, the way git does.
t_unstage_without_a_path_specified_stops() {
    commit_file a.txt one "first"
    echo b > b.txt
    git add b.txt

    local out status=0
    out=$(execute_cmd "unstage" 2>&1) || status=$?

    assert_eq "$status" "0" "no pathspec is not a failure: [$out]"
    assert_contains "$out" "Nothing specified, nothing unstaged" "what it says"
    assert_contains "$out" "unstage ." "the hint it gives"
    assert_eq "$(git diff --cached --name-only)" "b.txt" "and it staged nothing"
}

# 'unstage .' is the mirror of 'git add .': this directory and below.
t_unstage_dot_covers_the_current_directory() {
    commit_file a.txt one "first"
    mkdir -p sub
    echo b > sub/b.txt
    git add sub/b.txt

    execute_cmd "unstage ."

    assert_eq "$(git diff --cached --name-only)" "" "the index after unstage ."
}

# 'git add -A' is the whole tree, from anywhere. So is 'unstage -A'.
t_unstage_all_covers_the_whole_tree() {
    commit_file a.txt one "first"
    mkdir -p sub
    echo b > sub/b.txt
    git add sub/b.txt

    cd sub || return 1
    execute_cmd "unstage -A"

    assert_eq "$(git diff --cached --name-only)" "" "the index after unstage -A"
}

# 'git add -u' never adds a new file, so 'unstage -u' never unstages one.
t_unstage_update_leaves_new_files_staged() {
    commit_file a.txt one "first"
    printf 'changed\n' > a.txt
    git add a.txt
    echo new > b.txt
    git add b.txt

    execute_cmd "unstage -u"

    assert_eq "$(git diff --cached --name-only)" "b.txt" "the new file stays staged"
    assert_eq "$(git diff --cached --name-only -- a.txt)" "" "the tracked file does not"
}

# 'git add -n' says what it would do and does nothing. So does this.
t_unstage_dry_run_changes_nothing() {
    commit_file a.txt one "first"
    echo b > b.txt
    git add b.txt

    local out status=0
    out=$(execute_cmd "unstage -n b.txt" 2>&1) || status=$?

    assert_eq "$status" "0" "a dry run is not a failure: [$out]"
    assert_contains "$out" "unstage 'b.txt'" "what it would have done"
    assert_eq "$(git diff --cached --name-only)" "b.txt" "and it did nothing"
}

# A repo with no commits has no HEAD, and 'git restore --staged' needs one.
# This is the first unstage a new project ever does, so it has to work.
t_unstage_works_before_the_first_commit() {
    echo a > a.txt
    git add a.txt

    local out status=0
    out=$(execute_cmd "unstage a.txt" 2>&1) || status=$?

    assert_eq "$status" "0" "unstaging on a repo with no commits: [$out]"
    assert_eq "$(git diff --cached --name-only)" "" "the index after unstage"
    assert_eq "$(cat a.txt)" "a" "the file must survive"
    assert_eq "$(git status --porcelain)" "?? a.txt" "and be untracked again"
}

# Nothing to do is not an error. It says so and stops.
t_unstage_with_nothing_staged_is_a_no_op() {
    commit_file a.txt one "first"

    local out status=0
    out=$(execute_cmd "unstage -A" 2>&1) || status=$?

    assert_eq "$status" "0" "an empty index is not a failure: [$out]"
    assert_contains "$out" "Nothing to unstage" "what it says"
}

# A path that is known to git but has nothing staged is a no-op too, and it
# says so rather than claiming it unstaged something.
t_unstage_of_an_unstaged_path_is_a_no_op() {
    commit_file a.txt one "first"

    local out status=0
    out=$(execute_cmd "unstage a.txt" 2>&1) || status=$?

    assert_eq "$status" "0" "a path with nothing staged is not a failure: [$out]"
    assert_contains "$out" "Nothing to unstage for 'a.txt'" "what it says"
    assert_not_contains "$out" "Unstaged" "it must not claim to have unstaged it"
}

# A file git has never heard of cannot be unstaged. That is worth a
# non-zero status, so 'unstage x && something' does not run the something.
t_unstage_reports_a_file_that_is_not_staged() {
    commit_file a.txt one "first"

    local out status=0
    out=$(execute_cmd "unstage nope.txt" 2>&1) || status=$?

    ((status != 0)) || fail_assert "unstaging a file that is not staged should fail"
    assert_contains "$out" "nope.txt" "which file was the problem"
}

# A flag git's 'add' does not know is refused, not passed on to git. The
# git command behind this one has flags of its own that would lose work.
t_unstage_refuses_an_unknown_flag() {
    commit_file a.txt one "first"

    local out status=0
    out=$(execute_cmd "unstage --hard" 2>&1) || status=$?

    ((status != 0)) || fail_assert "an unknown flag should fail"
    assert_contains "$out" "unknown option" "what it says"
    assert_eq "$(git status --porcelain)" "" "and nothing was touched"
}
