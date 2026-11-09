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

# A failing git command must report its own status, not the status of the
# cleanup that follows it. This was silently broken: the dispatch arm ended
# with 'rm -f', so every failing git command returned 0 as far as the operator
# splitter could see, and '||' never ran while '&&' ran on failure.
t_failing_git_reports_its_status() {
    commit_file a.txt one "first"

    execute_cmd 'rev-parse --verify nosuchref' >/dev/null 2>&1 \
        && fail_assert "a failing git command should return non-zero"

    # And the operator splitter must see it.
    local out
    out=$(process_command_line 'rev-parse --verify nosuchref || config session' 2>/dev/null)
    case "$out" in
        *"No session overrides"*) ;;
        *) fail_assert "'||' should run after a failed git command; got: $out" ;;
    esac

    # '&&' must not run on failure.
    out=$(process_command_line 'rev-parse --verify nosuchref && config session' 2>/dev/null)
    case "$out" in
        *"No session overrides"*) fail_assert "'&&' ran after a failed git command" ;;
    esac
}

# --- she boots ------------------------------------------------------------

t_the_script_runs_as_she_is_shebangged() {
    # The failure this pins is narrow and total: she is run with 'bash -i', so
    # bash reads the whole file before executing any of it, and history
    # expansion applies during that read. '((!assume_yes))' is an event
    # reference to bash in that state, and the parse dies at the next 'fi' --
    # no prompt, no error the user can act on, just a shell that will not
    # start. Every other test here sources the file, which does not reproduce
    # it, so this one has to execute the real thing.
    local script
    script="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/igitari.sh"
    [[ -f "$script" ]] || fail_assert "igitari.sh not found at $script"

    # Not asserting on the exit status: without a tty the interactive loop can
    # die on the way out ('timeout' reports a core dump), which says nothing
    # about whether she started. What matters is that the file parsed and the
    # prompt was reached.
    # -i is the whole point and is not optional: the shebang is
    # 'bash -i', and only an interactive shell expands history while parsing
    # the file. Running her with plain 'bash' passes even when she is broken.
    #
    # IGITARI_TEST is exported by the harness so the source-based tests skip
    # main(); the child has to see it unset or she exits before the prompt.
    local out
    out="$(cd "$WORK" && printf 'exit\n' |
        env -u IGITARI_TEST timeout 60 bash -i "$script" 2>&1 |
        grep -v 'job control\|process group' |
        sed 's/\x1b\[[0-9;]*m//g')"

    [[ "$out" != *"event not found"* ]] || fail_assert "history expansion bit: [$out]"
    [[ "$out" != *"syntax error"* ]] || fail_assert "syntax error at parse: [$out]"
    assert_contains "$out" "Entering Igitari" "she reached her prompt"
}

t_history_expansion_is_off_me_before_any_bang_is_parsed() {
    # The set has to be top level. Inside a function it runs after the parse,
    # which is the bug above; asserting on the file itself keeps anyone from
    # helpfully tidying it back into disable_history_expansion().
    local script
    script="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/igitari.sh"

    local line
    line=$(grep -n '^set +H$' "$script" | head -1 | cut -d: -f1)
    [[ -n "$line" ]] || fail_assert "'set +H' is not a top-level statement"

    # Nothing that history expansion would eat may appear above it. Comments
    # are skipped: this very explanation mentions the pattern.
    local bang
    bang=$(grep -nE '^[^#]*\(\(!' "$script" | head -1 | cut -d: -f1)
    if [[ -n "$bang" ]]; then
        ((line < bang)) \
            || fail_assert "'set +H' at line $line comes after ((!..)) at $bang"
    fi
}
