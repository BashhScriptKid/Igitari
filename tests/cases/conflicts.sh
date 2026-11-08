# shellcheck shell=bash
# Reading and taking sides of a conflict.
#
# Git keeps three versions of every unmerged path and moving between them by
# hand means remembering 'git show :1:file'. These check that each side is
# reachable and that 'take' actually resolves a path.

# conflict show must print each side of a real conflict.
t_conflict_show_sides() {
    printf 'base\n' > f.txt
    git add -- f.txt && git commit -q -m base
    git checkout -q -b side
    printf 'theirs\n' > f.txt && git commit -q -am side
    git checkout -q master 2>/dev/null || git checkout -q main
    printf 'ours\n' > f.txt && git commit -q -am main
    git merge side >/dev/null 2>&1

    local ours theirs
    ours=$(conflict show ours f.txt 2>/dev/null)
    theirs=$(conflict show theirs f.txt 2>/dev/null)
    assert_eq "$ours" "ours" "ours side"
    assert_eq "$theirs" "theirs" "theirs side"

    git merge --abort >/dev/null 2>&1
}

# conflict throw must write the surviving side and stage it, resolving the path.
# conflict throw NAMES THE LOSER, so 'throw theirs' must keep YOURS. This is
# the inversion that makes the command survive a rebase, where 'ours' is the
# upstream -- getting the mapping backwards here would silently keep the wrong
# side, which is the whole failure mode the word was chosen to avoid.
t_conflict_throw_keeps_the_other_side() {
    make_conflicted_merge

    answer_yes 'conflict throw theirs f.txt'
    assert_file f.txt ours

    local unmerged
    unmerged=$(git diff --name-only --diff-filter=U)
    assert_eq "$unmerged" "" "unmerged paths after throw"
}

# And the other direction, so the test cannot pass by always keeping one side.
t_conflict_throw_ours_keeps_theirs() {
    make_conflicted_merge

    answer_yes 'conflict throw ours f.txt'
    assert_file f.txt theirs
}
