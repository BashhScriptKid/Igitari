# shellcheck shell=bash
# prune-branches — three independent conditions, one command.
#
# The three are built separately here because the whole design rests on them
# being different: a branch can be merged without being gone, gone without
# being merged, or squashed with no ancestry link at all.

# A branch that has been merged normally.
t_prune_merged() {
    commit_file a.txt one "first"
    git checkout -q -b done
    commit_file b.txt two "done work"
    git checkout -q master 2>/dev/null || git checkout -q main
    git merge -q --no-edit done

    prune_branches merged --dry-run >/dev/null 2>&1
    local out
    out=$(prune_branches merged --dry-run 2>&1)
    case "$out" in
        *done*) ;;
        *) fail_assert "a merged branch should be listed; got: $out" ;;
    esac
    case "$out" in
        *"(merged)"*) ;;
        *) fail_assert "it should say why; got: $out" ;;
    esac
}

# The case 'git branch --merged' cannot see: a squash-merge throws the
# ancestry away, so only a patch comparison finds it.
t_prune_squashed() {
    commit_file a.txt one "first"
    git checkout -q -b squashed
    commit_file b.txt two "squashed work"
    git checkout -q master 2>/dev/null || git checkout -q main
    git merge -q --squash squashed >/dev/null 2>&1
    git commit -q -m "squashed in"

    # Prove the premise: git's own ancestry test says no.
    if git merge-base --is-ancestor squashed HEAD 2>/dev/null; then
        fail_assert "premise broken: a squash-merge should not be an ancestor"
    fi

    local out
    out=$(prune_branches squashed --dry-run 2>&1)
    case "$out" in
        *squashed*) ;;
        *) fail_assert "a squash-merged branch should be listed; got: $out" ;;
    esac
    case "$out" in
        *"(squashed)"*) ;;
        *) fail_assert "it should say the reason was squashed; got: $out" ;;
    esac
}

# A branch whose remote was deleted. Built with a real remote, because [gone]
# is what a missing upstream looks like and nothing else produces it.
t_prune_gone() {
    git init -q --bare remote.git
    commit_file a.txt one "first"
    git remote add origin ./remote.git
    git push -q -u origin HEAD 2>/dev/null

    git checkout -q -b abandoned
    commit_file b.txt two "abandoned work"
    git push -q -u origin abandoned 2>/dev/null
    git checkout -q master 2>/dev/null || git checkout -q main
    git push -q origin --delete abandoned 2>/dev/null
    git fetch -q --prune

    local out
    out=$(prune_branches gone --dry-run 2>&1)
    case "$out" in
        *abandoned*) ;;
        *) fail_assert "a branch with a deleted remote should be listed; got: $out" ;;
    esac
}

# The one that must never be listed: a branch with work nobody has seen.
t_prune_leaves_unfinished_work_alone() {
    commit_file a.txt one "first"
    git checkout -q -b in-progress
    commit_file b.txt two "unfinished work"
    git checkout -q master 2>/dev/null || git checkout -q main

    local out
    out=$(prune_branches --dry-run 2>&1)
    case "$out" in
        *in-progress*) fail_assert "an unmerged branch with its work intact must not be listed" ;;
    esac
}

# And the current branch plus main/master are never candidates even when they
# would otherwise qualify.
t_prune_never_touches_current_or_main() {
    commit_file a.txt one "first"
    local main_branch
    main_branch=$(git symbolic-ref --short HEAD)

    local out
    out=$(prune_branches --dry-run 2>&1)
    case "$out" in
        *"$main_branch"*) fail_assert "the current branch must never be listed" ;;
    esac
}

# Dry run must not delete.
t_prune_dry_run_deletes_nothing() {
    commit_file a.txt one "first"
    git checkout -q -b done
    commit_file b.txt two "done work"
    git checkout -q master 2>/dev/null || git checkout -q main
    git merge -q --no-edit done

    local before
    before=$(git for-each-ref --format='%(refname:short)' refs/heads | wc -l)

    prune_branches --dry-run >/dev/null 2>&1

    assert_eq "$(git for-each-ref --format='%(refname:short)' refs/heads | wc -l)" \
        "$before" "branch count after a dry run"
}

# The delete itself, through the prompt. Uses a pty because the confirmation
# reads /dev/tty on purpose, so a piped answer cannot stand in for consent.
t_prune_deletes_after_confirmation() {
    commit_file a.txt one "first"
    git checkout -q -b done
    commit_file b.txt two "done work"
    git checkout -q master 2>/dev/null || git checkout -q main
    git merge -q --no-edit done

    # Through the dispatcher: a bash function cannot be named with a hyphen,
    # so the script answer_yes runs has to spell the command the way a user
    # would.
    answer_yes 'execute_command prune-branches'

    git show-ref --verify --quiet refs/heads/done \
        && fail_assert "the merged branch should be gone"
    git rev-parse --verify HEAD >/dev/null 2>&1 \
        || fail_assert "HEAD should still exist"
}
