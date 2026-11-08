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

# 'a' is mid-'git am'. It is deliberately independent of 'c': a patch that
# does not apply stops am WITHOUT conflicts, so requiring unmerged paths would
# miss exactly the case this flag exists to report.
t_state_flags_am_without_conflicts() {
    commit_file a.txt original "first"

    # A patch that touches a line this branch has since changed: am stops, and
    # stops WITHOUT a conflict to resolve.
    git checkout -q -b topic
    commit_file a.txt changed-by-topic "topic change"
    local patch
    patch=$(mktemp "${TMPDIR:-/tmp}/igitari-am.XXXXXX")
    git format-patch -1 --stdout > "$patch"
    git checkout -q master 2>/dev/null || git checkout -q main
    git branch -q -D topic 2>/dev/null
    commit_file a.txt different-here "master change"

    git am "$patch" >/dev/null 2>&1 || true

    local st
    st=$(__git_state)
    assert_contains "$st" "a" "state flags an am session"
    assert_contains "$st" "o" "state flags half-finished work"
    case "$st" in
        *c*) fail_assert "an am that did not apply is not a conflict: [$st]" ;;
    esac

    git am --abort >/dev/null 2>&1
    rm -f "$patch"
}

# 'd' is divergence: ahead AND behind. Either alone is ordinary and must not
# be reported, or the flag would fire on every unpushed commit.
t_state_flags_divergence_only_when_both_sides() {
    git init -q --bare remote.git
    commit_file a.txt one "first"
    git remote add origin ./remote.git
    git push -q -u origin HEAD 2>/dev/null

    assert_eq "$(__git_state)" "" "state when in sync"

    # Ahead only: a local commit the remote does not have.
    commit_file a.txt two "local only"
    case "$(__git_state)" in
        *d*) fail_assert "ahead alone is not divergence" ;;
    esac

    # Behind only: clone, push from the clone, so this repo is behind.
    local clone
    clone=$(mktemp -d "${TMPDIR:-/tmp}/igitari-clone.XXXXXX")
    git clone -q ./remote.git "$clone" 2>/dev/null
    (
        cd "$clone" || exit 1
        git config user.email other@example.com
        git config user.name Other
        git commit -q --allow-empty -m "remote only"
        git push -q origin HEAD 2>/dev/null
    )
    rm -rf "$clone"

    git reset -q --hard HEAD~1 2>/dev/null
    git fetch -q origin 2>/dev/null
    case "$(__git_state)" in
        *d*) fail_assert "behind alone is not divergence" ;;
    esac

    # Both: one local commit on top of a stale base.
    commit_file a.txt three "local again"
    assert_contains "$(__git_state)" "d" "state flags divergence"
}
