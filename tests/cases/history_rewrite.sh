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

# transplant refuses to move a commit that is already pushed, and --force is
# the documented way past it. Two tests, because a force flag is only correct
# if it overrides the check it names and nothing else.
t_transplant_refuses_pushed_commit() {
    git init -q --bare remote.git
    commit_file a.txt one "first"
    commit_file a.txt two "second"
    git remote add origin ./remote.git
    git push -q -u origin HEAD 2>/dev/null

    git checkout -q -b feat
    commit_file b.txt three "feat work"
    git push -q -u origin feat 2>/dev/null
    git checkout -q master 2>/dev/null || git checkout -q main
    local tip
    tip=$(git rev-parse master 2>/dev/null || git rev-parse main)

    local out
    out=$(transplant 1 feat 2>&1) && fail_assert "should refuse to move a pushed commit"

    case "$out" in
        *"already pushed"*) ;;
        *) fail_assert "should say the commits are pushed; got: $out" ;;
    esac
    assert_eq "$(git rev-parse HEAD)" "$tip" "HEAD after a refused transplant"
}

t_transplant_force_overrides_pushed_check() {
    git init -q --bare remote.git
    commit_file a.txt one "first"
    commit_file a.txt two "second"
    git remote add origin ./remote.git
    git push -q -u origin HEAD 2>/dev/null

    git checkout -q -b feat
    commit_file b.txt three "feat work"
    git push -q -u origin feat 2>/dev/null
    # transplant moves the CURRENT branch's commit to another branch, so stand
    # on feat and name master as the destination.
    git checkout -q feat

    answer_yes 'transplant 1 master --force'
    assert_eq "$(git log -1 --format='%s' master)" "feat work" \
        "the transplanted commit should land on the target branch"
}

# And --force must not wave through a genuinely broken transplant: it overrides
# the published-history check, not the ability to name a real commit.
t_transplant_force_still_rejects_nothing_it_cannot_do() {
    commit_file a.txt one "first"

    transplant 1 nosuchbranch --force >/dev/null 2>&1 \
        && fail_assert "--force must not invent a missing branch"

    transplant 1 2>/dev/null; : # keep shell happy
    local before
    before=$(git rev-parse HEAD)
    transplant 99 nosuchbranch --force >/dev/null 2>&1 && fail_assert "should fail"
    assert_eq "$(git rev-parse HEAD)" "$before" "HEAD after a failed forced transplant"
}

# Asking for every commit on a branch means the range starts at the root,
# which has no parent for 'HEAD~N' to anchor to. That used to surface as
# "fatal: ambiguous argument 'HEAD~1..HEAD'" -- git complaining about syntax
# the user never typed. Say what is actually wrong instead.
t_transplant_whole_history_explains_itself() {
    commit_file a.txt one "only commit"
    git checkout -q -b feature

    local out
    out=$(transplant 1 master 2>&1 || transplant 1 main 2>&1) \
        && fail_assert "transplanting the entire history should be refused"

    case "$out" in
        *"no parent to move from"*) ;;
        *) fail_assert "should explain the missing parent; got: $out" ;;
    esac
    case "$out" in
        *"ambiguous argument"*) fail_assert "must not leak git's raw syntax error" ;;
    esac
}

# --yes exists so squash can be scripted. The contrast is what matters: the
# same call with no terminal to ask on must abort cleanly rather than assume
# consent.
t_squash_yes_skips_the_prompt() {
    commit_file a.txt 1 "one"
    commit_file a.txt 2 "two"
    commit_file a.txt 3 "three"

    squash 2 "combined" --yes >/dev/null 2>&1 \
        || fail_assert "squash --yes should not need a terminal"

    assert_eq "$(n_commits)" "2" "commit count after squashing"
    assert_eq "$(git log -1 --format='%s')" "combined" "squashed message"
}

# Without --yes and without a tty, the prompt cannot be answered, and an
# unanswerable prompt is not a yes.
t_squash_without_yes_aborts_with_no_terminal() {
    commit_file a.txt 1 "one"
    commit_file a.txt 2 "two"
    commit_file a.txt 3 "three"

    local before
    before=$(n_commits)

    squash 2 "combined" >/dev/null 2>&1 \
        && fail_assert "squash should refuse when it cannot ask"

    assert_eq "$(n_commits)" "$before" "commits must be untouched after aborting"
}

# The flag is a flag, not a positional: it must work before the target and
# must not be swallowed as the message.
t_squash_yes_takes_any_position() {
    commit_file a.txt 1 "one"
    commit_file a.txt 2 "two"
    commit_file a.txt 3 "three"

    squash --yes 2 "front flag" >/dev/null 2>&1 \
        || fail_assert "--yes before the target should work"

    assert_eq "$(n_commits)" "2" "commit count"
    assert_eq "$(git log -1 --format='%s')" "front flag" "message was not the flag"
}
