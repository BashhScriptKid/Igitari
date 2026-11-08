# shellcheck shell=bash
# Input scanning: comments and line continuation.
#
# Both features have to know which characters sit inside quotes, so they share
# one scanner. These tests are written against the scanner directly because
# that is where a mistake would be silent: a comment stripped one character
# too early turns a valid command into a different valid command.

# The trap the roadmap warned about: a '#' inside quotes is data.
t_scan_keeps_hashes_inside_quotes() {
    __join_continuation 'commit -m "fix #123"' || fail_assert "should be complete"
    assert_eq "$READ_CMD" 'commit -m "fix #123"' "double-quoted hash survives"

    __join_continuation "commit -m 'fix #123'" || fail_assert "should be complete"
    assert_eq "$READ_CMD" "commit -m 'fix #123'" "single-quoted hash survives"
}

t_scan_strips_unquoted_comments() {
    __join_continuation 'status   # what is going on' || fail_assert "should be complete"
    assert_eq "$READ_CMD" 'status   ' "text before the hash is kept"

    __join_continuation '# the whole line is a note' || fail_assert "should be complete"
    assert_eq "$READ_CMD" "" "a comment-only line leaves nothing"
}

# An escaped hash is a literal hash, not the start of a comment.
t_scan_respects_escaped_hash() {
    __join_continuation 'log --grep=a \#b -1' || fail_assert "should be complete"
    assert_eq "$READ_CMD" 'log --grep=a \#b -1' "escaped hash is data"
}

t_scan_reports_continuation() {
    __join_continuation 'squash 3 \' && fail_assert "trailing backslash should continue"
    assert_eq "$READ_CMD" 'squash 3 ' "the backslash itself is dropped"

    __join_continuation 'squash 3' || fail_assert "a plain line is complete"
    assert_eq "$READ_CMD" 'squash 3' "plain line unchanged"
}

# A backslash that is not last is an escape: both characters stay, and the
# escaped character must not be re-examined as a comment or a quote.
t_scan_keeps_interior_backslash_and_escaped_quote() {
    __join_continuation 'echo a\ b' || fail_assert "should be complete"
    assert_eq "$READ_CMD" 'echo a\ b' "interior backslash kept with its character"

    __join_continuation 'commit -m "say \"hi\""' || fail_assert "should be complete"
    assert_eq "$READ_CMD" 'commit -m "say \"hi\""' "escaped quotes do not close the string"
}

# A quote inside a comment must not open a string, or the rest of the line
# would be swallowed looking for a close that will never come.
t_scan_ignores_quotes_after_a_comment() {
    __join_continuation "status # don't parse this ' or this \"" || fail_assert "should be complete"
    assert_eq "$READ_CMD" 'status ' "everything after the hash is gone"
}

# And the loop itself: a commented line must not reach git, and a continued
# line must dispatch as one command. Driven through main_loop's stdin rather
# than by calling the scanner, so the wiring is covered too.
t_main_loop_strips_comments_and_joins_continuations() {
    commit_file a.txt one "first"
    commit_file a.txt two "second"

    local out
    out=$(
        printf 'log --oneline \\\n  -2\nstatus # a note\n' |
            timeout 20 bash --norc -c '
                export IGITARI_TEST=1
                cd "$1" || exit 1
                source "$2" >/dev/null 2>&1
                main_loop
            ' _ "$WORK" "$IGITARI" 2>/dev/null
    )

    # The two commits came back, so the continuation joined into one command.
    local subjects
    subjects=$(printf '%s\n' "$out" | grep -c 'second\|first' || true)
    [[ "$subjects" -ge 2 ]] || fail_assert "the continued command should have listed both commits; got: $out"

    # And the comment never reached git, which would have errored on it.
    case "$out" in
        *"is not a git command"*)
            fail_assert "a comment must not be dispatched to git; got: $out"
            ;;
    esac
}
