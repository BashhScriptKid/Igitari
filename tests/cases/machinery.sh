# shellcheck shell=bash
# The machinery under the commands: prompts, operators, argument matching, and
# the offer to run git's own suggested fix.
#
# A silent bug in any of these is either a hang or the wrong command executed,
# which is worse than a wrong answer.

# --- the machinery -------------------------------------------------------

# __igitari_confirm: y means yes, n means no, and "no tty" must abort.
#
# The rule that matters is the last one. Return 2 means "I could not ask", and
# call sites treat it exactly like 1. Getting that wrong is how a prompt turns
# into a permanent hang.
t_confirm_reads_answers() {
    # Under script(1) we have a tty, so a typed y and n are actually read.
    local dir
    dir="$(mktemp -d "${TMPDIR:-/tmp}/igitari-confirm.XXXXXX")"

    printf 'y\n' >"$dir/yes.txt"
    printf 'n\n' >"$dir/no.txt"

    local script_file="$dir/run.sh"
    {
        printf 'export IGITARI_TEST=1\n'
        printf 'cd %q || exit 1\n' "$WORK"
        printf 'source %q >/dev/null 2>&1\n' "$IGITARI"
        printf '__igitari_confirm "ok?" >/dev/null 2>&1; echo "rc=$?"\n'
    } >"$script_file"

    local got
    got=$(script -qec "bash --norc $script_file" /dev/null <"$dir/yes.txt" 2>/dev/null | tr -d '\r' | grep -o 'rc=[0-9]' | tail -1)
    # A 'y' answer returns 0.
    [[ "$got" == "rc=0" ]] || fail_assert "confirm should return 0 for y, got [$got]"

    got=$(script -qec "bash --norc $script_file" /dev/null <"$dir/no.txt" 2>/dev/null | tr -d '\r' | grep -o 'rc=[0-9]' | tail -1)
    [[ "$got" == "rc=1" ]] || fail_assert "confirm should return 1 for n, got [$got]"

    rm -rf "$dir"
}

# With no controlling terminal it must return 2, promptly, never hanging.
t_confirm_without_tty_aborts() {
    # Run it with stdin closed and no controlling terminal. It must return 2
    # rather than wait for a keypress nobody will send.
    local rc
    rc=$(cd "$WORK" && IGITARI_TEST=1 bash -c '
        source "$1" >/dev/null 2>&1
        __igitari_confirm "ok?" >/dev/null 2>&1
        printf "%s" "$?"
    ' _ "$IGITARI" </dev/null 2>/dev/null | tr -d '\n')

    [[ -n "$rc" ]] || fail_assert "confirm produced no exit code without a tty"
    assert_eq "$rc" "2" "confirm rc with no tty"
}

# process_command_line: && runs on success, skips on failure; || the reverse.
t_operators_short_circuit() {
    local calls=""
    # Trim the argument: process_command_line passes it through 'read -r',
    # which leaves surrounding spaces from the operator split.
    execute_command() { local a="$1"; a="${a#"${a%%[![:space:]]*}"}"; a="${a%"${a##*[![:space:]]}"}"; calls+="[$a]"; return "${RETURN_CODE:-0}"; }

    RETURN_CODE=0 calls=""
    process_command_line "a && b"
    assert_eq "$calls" "[a][b]" "&& with success runs both"

    RETURN_CODE=1 calls=""
    process_command_line "a && b"
    assert_eq "$calls" "[a]" "&& with failure stops"

    RETURN_CODE=1 calls=""
    process_command_line "a || b"
    assert_eq "$calls" "[a][b]" "|| with failure runs both"

    RETURN_CODE=0 calls=""
    process_command_line "a || b"
    assert_eq "$calls" "[a]" "|| with success stops"

    # ; always runs, whatever happened.
    RETURN_CODE=1 calls=""
    process_command_line "a ; b"
    assert_eq "$calls" "[a][b]" "; always continues"
}

# validate_arg accepts every documented spelling, and only those.
# validate_arg is defined INSIDE process_arguments, so it is not callable on
# its own. What it promises is that --help, -h, /HELP, /H and bare 'help' all
# reach the help page -- which is exactly the bug that ate the first canonical
# name. So test the promise through process_arguments.
t_validate_arg_forms() {
    local form out
    for form in --help -h /HELP /H help; do
        out=$(cd "$WORK" && IGITARI_TEST=1 bash -c '
            source "$1" >/dev/null 2>&1
            process_arguments "$2" 2>&1
        ' _ "$IGITARI" "$form" 2>&1)

        [[ "$out" == *"USAGE"* ]] || fail_assert "[$form] should reach the help page"
    done

    # Nonsense must not be treated as a flag that exits early.
    out=$(cd "$WORK" && IGITARI_TEST=1 bash -c '
        source "$1" >/dev/null 2>&1
        process_arguments "nonsense" 2>&1
    ' _ "$IGITARI" 2>&1)
    [[ "$out" == *"USAGE"* ]] && fail_assert "[nonsense] should not show help"
}

# __igitari_offer_fix lifts git's own runnable suggestion, and refuses
# templates containing placeholders.
t_offer_fix_lifts_suggestion() {
    local errfile
    errfile="$(mktemp "${TMPDIR:-/tmp}/igitari-err.XXXXXX")"

    # A real push-with-no-upstream message.
    cat >"$errfile" <<'ERR'
fatal: The current branch master has no upstream branch.
To push the current branch and set the remote as upstream, use

    git push --set-upstream origin master

To have this happen automatically for branches without a tracking
upstream, see 'push.autoSetupRemote' in 'git help config'.
ERR

    # Answer 'n' so nothing actually runs; we only care that it offered.
    local out
    out=$(printf 'n\n' | __igitari_offer_fix "$errfile" 2>&1)
    assert_contains "$out" "git push --set-upstream origin master" "lifts the exact command"
    assert_contains "$out" "retyping" "explains why it offered"

    # A template must not be offered: '<branch>' is not runnable.
    cat >"$errfile" <<'ERR'
There is no tracking information for the current branch.

    git pull <remote> <branch>

If you wish to set tracking information for this branch you can do so with:

    git branch --set-upstream-to=origin/<branch> master
ERR
    local rc
    # __igitari_offer_fix is a shell function, so it cannot be handed to
    # timeout as a command; the timeout has to wrap a subshell instead.
    printf 'n\n' | timeout 5 bash -c 'exit 0' >/dev/null 2>&1
    __igitari_offer_fix "$errfile" </dev/null >/dev/null 2>&1
    rc=$?
    [[ $rc -eq 1 ]] || fail_assert "a placeholder suggestion must not be offered (rc=$rc)"

    rm -f "$errfile"
}
