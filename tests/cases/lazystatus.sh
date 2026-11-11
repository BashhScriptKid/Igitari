# shellcheck shell=bash
# lazystatus: a tree of what changed, drawn the way lazygit draws it.
#
# The theme here is that the display means something: the code is the one git
# writes, the name carries lazygit's colour rule, and the same output comes
# out of both renderers (tree(1) when installed, the built-in fallback
# otherwise). Every test that cares compares byte-for-byte behaviour, not
# shape.

# Outside a repository, lazystatus says so and exits 1 rather than answering
# nothing.
t_lazystatus_outside_a_repo_fails() {
    local outside
    outside=$(mktemp -d "${TMPDIR:-/tmp}/igitari-notarepo.XXXXXX")
    cd "$outside" || return 1

    local out status=0
    out=$(execute_command "lazystatus" 2>&1) || status=$?

    assert_eq "$status" "1" "exit status outside a repo"
    assert_contains "$out" "Not in a git repository" "message outside a repo"

    cd "$REPO_ROOT" || true
    rm -rf "$outside"
}

# A changed file appears with the code git wrote for it, and an untouched
# file does not appear without --all.
t_lazystatus_lists_changed_and_only_changed() {
    commit_file a.txt one "first"
    commit_file b.txt one "second"
    printf 'modified\n' > b.txt

    local out
    out=$(execute_cmd "lazystatus")

    assert_contains "$out" "b.txt" "changed file appears"
    assert_contains "$out" " M b.txt" "unstaged code appears"
    assert_not_contains "$out" "a.txt" "untouched file is absent"
}

# A tracked file that has not changed is only listed with --all, and carries
# no code.
t_lazystatus_all_includes_unchanged() {
    commit_file a.txt one "first"

    local out
    out=$(execute_cmd "lazystatus --all")

    assert_contains "$out" "a.txt" "--all lists unchanged tracked files"
    assert_contains "$out" "   a.txt" "an unchanged file carries a blank code"

    out=$(execute_cmd "lazystatus")
    assert_eq "$out" "" "a clean tree prints nothing"
}

# The name colour is lazygit's rule, not ours: green staged-only, yellow
# staged and unstaged, default otherwise.
t_lazystatus_name_colour_matches_lazygit() {
    # Commit everything first, then make the three states: this helper
    # sweeps anything still staged into the next commit, so creating the
    # states first and committing later would mix them up.
    commit_file staged.txt one "one"
    commit_file both.txt one "two"
    commit_file work.txt one "three"

    printf 'staged change\n' > staged.txt && git add staged.txt
    printf 'staged part\n' > both.txt && git add both.txt && printf 'worktree part\n' > both.txt
    printf 'work\n' > work.txt

    local out
    out=$(execute_cmd "lazystatus --color")

    assert_contains "$out" "$(printf '\e[32m')" "staged-only name is green"
    assert_contains "$out" "$(printf '\e[33m')" "staged and unstaged name is yellow"

    # Unstaged-only: the name carries no colour of its own, so neither the
    # green nor the yellow escape may appear on that line.
    local line
    line=$(printf '%s\n' "$out" | grep -F "work.txt") || line=""
    assert_not_contains "$line" "$(printf '\e[32m')" "unstaged-only name is not green"
    assert_not_contains "$line" "$(printf '\e[33m')" "unstaged-only name is not yellow"
}

# An unmerged path keeps both codes: 'UU'. The colour rule still colours each
# character separately.
t_lazystatus_conflict_shows_uu() {
    commit_file a.txt base "base"
    git checkout -q -b other
    printf 'other\n' > a.txt && git commit -q -am other
    git checkout -q master 2>/dev/null || git checkout -q main
    printf 'master\n' > a.txt && git commit -q -am master
    git merge other >/dev/null 2>&1 || true

    local out
    out=$(execute_cmd "lazystatus")
    assert_contains "$out" "a.txt" "conflicted file appears"
    assert_contains "$out" "UU" "both-modified code is UU"

    git merge --abort >/dev/null 2>&1 || true
}

# A renamed file is shown as old -> new, not as one file vanishing and
# another appearing.
t_lazystatus_rename_shows_old_and_new() {
    commit_file oldname.txt one "first"
    git mv oldname.txt newname.txt

    local out
    out=$(execute_cmd "lazystatus")
    assert_contains "$out" "oldname.txt -> newname.txt" "rename shows old and new"
}

# --simple drops the box-drawing and indents with four spaces per level, so
# no line may contain the tree glyphs.
t_lazystatus_simple_indents_without_box_drawing() {
    commit_file a.txt one "first"
    printf 'modified\n' > a.txt
    mkdir sub && commit_file sub/b.txt one "in sub"

    local out
    out=$(execute_cmd "lazystatus --all --simple")

    assert_not_contains "$out" "|--" "simple mode has no box drawing"
    assert_not_contains "$out" "+---" "simple mode has no branch glyphs"
    assert_contains "$out" "    " "simple mode indents with spaces"
}

# With --no-collapse every directory gets its own line, one level per line.
t_lazystatus_no_collapse_draws_every_directory() {
    mkdir -p x/y/z
    commit_file x/y/z/deep.txt one "deep"
    printf 'modified\n' > x/y/z/deep.txt

    local out
    out=$(execute_cmd "lazystatus --no-collapse")

    assert_contains "$out" "x/" "top directory on its own line"
    assert_contains "$out" "y/" "middle directory on its own line"
    assert_contains "$out" "z/" "leaf directory on its own line"
}

# The path filter restricts to the paths given, the same way git status
# does.
t_lazystatus_path_filter_restricts_output() {
    mkdir -p src other
    commit_file src/a.txt one "src"
    commit_file other/b.txt one "other"
    printf 'changed\n' > src/a.txt
    printf 'changed\n' > other/b.txt

    local out
    out=$(execute_cmd "lazystatus src/")

    assert_contains "$out" "a.txt" "matching path appears"
    assert_not_contains "$out" "b.txt" "other path is filtered out"
}

# tree(1) and the built-in renderer must print the same bytes. The fallback
# is forced by running with a PATH that has everything except tree.
t_lazystatus_fallback_matches_the_tree_renderer() {
    commit_file a.txt one "first"
    printf 'modified\n' > a.txt
    mkdir sub && commit_file sub/b.txt one "in sub" && printf 'modified\n' > sub/b.txt
    echo untracked > new.txt

    local farm tree_out farm_out
    farm=$(mktemp -d "${TMPDIR:-/tmp}/igitari-treeless.XXXXXX")
    local t
    for t in /usr/bin/*; do
        [[ $(basename "$t") == tree ]] && continue
        [[ -x $t && ! -d $t ]] && ln -sf "$t" "$farm/" 2>/dev/null
    done

    tree_out=$(execute_cmd "lazystatus --all")
    farm_out=$(PATH="$farm" execute_cmd "lazystatus --all")
    rm -rf "$farm"

    assert_eq "$tree_out" "$farm_out" "fallback output must match the tree renderer"
}
