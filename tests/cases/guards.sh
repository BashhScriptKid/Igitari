# shellcheck shell=bash
# The mid-operation guard.
#
# __refuse_mid_operation is the only thing between a half-finished rebase and
# a reset --hard. Each destructive verb is checked at its own call site,
# because one shared test would only prove the helper works, not that anything
# calls it.
#
# squash is here too: its guard is the same promise as the others.

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

# Every destructive verb must refuse while an operation is half-finished, and
# must say so without touching anything. The message is a promise: "Nothing has
# been touched."
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

# 'help <x>' decides whether a word is one of Igitari's by asking declare -F,
# which cannot see the verbs dispatched from a 'case' arm in execute_command.
# Those fell through to 'git help' and printed "No manual entry for gitexit".
# Each case-arm verb must be claimed by Igitari, not handed to git.
t_help_claims_case_arm_verbs() {
    local verb out
    for verb in exit lazygit version paginate no-pager; do
        out=$(execute_cmd "help $verb" 2>&1)
        assert_not_contains "$out" "No manual entry" "help $verb: must not reach git"
        assert_contains "$out" "one of mine" "help $verb: claimed as Igitari's own"
    done
}

# ...and a word that is genuinely git's must still reach git's own manual.
t_help_still_defers_to_git_for_git_commands() {
    local out
    out=$(execute_cmd "help rebase" 2>&1)
    assert_not_contains "$out" "one of mine" "help rebase: not Igitari's"
    assert_contains "$out" "rebase" "help rebase: git answered"
}
