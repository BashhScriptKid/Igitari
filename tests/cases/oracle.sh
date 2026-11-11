# shellcheck shell=bash
# Differential tests: an independent implementation is the oracle.
#
# Every other case file in this suite asserts against a fixture -- an expected
# value written by hand, checked by whoever wrote the test. That catches a
# change in behaviour. It cannot catch a behaviour that was *never right*,
# because the fixture encodes the same misunderstanding.
#
# These two cases ask a different question: not "does it do what the test
# says" but "does it do what an independent implementation says". The oracle
# for the operator layer is bash itself. The oracle for the updater's commit
# range is git itself. Neither oracle shares code with the thing it judges.

# --- the operator layer, against bash ---------------------------------------

# What bash itself would run for a line.
#
# bash's own parser, its own quoting rules and its own short-circuit
# semantics, all of them independent of anything Igitari does. The xtrace
# output is the list of commands it actually executed, which is what the
# comparison is about: not what bash parses, but what bash *does*.
_oracle_bash() {
    local line="$1"
    bash -x -c "$line" 2>&1 | sed -n 's/^+ //p'
}

# What Igitari would run for a line, with the dispatcher stubbed out so the
# segments can be collected instead of executed.
#
# The stub is defined inside a subshell so it cannot leak into the next test.
_subject_igitari() {
    local line="$1"
    (
        execute_command() { printf '%s\n' "$1"; return 0; }
        process_command_line "$line"
    ) 2>/dev/null
}

# Normalise a command for comparison.
#
# bash re-quotes its trace output ('a && b' where the user wrote "a && b"),
# and Igitari's segments keep the user's own quotes. The quoting is not what
# is being compared, so it comes out on both sides.
_normalise_cmd() {
    local s="$1"
    s="${s//\"/}"
    s="${s//\'/}"
    s="${s//[[:space:]]/ }"
    s="${s# }"
    s="${s% }"
    printf '%s' "$s"
}

_normalise_list() {
    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        _normalise_cmd "$line"
        printf '\n'
    done
}

# The corpus. Every command is 'echo', so both sides run something real and
# both sides succeed.
#
# No '#' comments: those are stripped by the reader before the operator layer
# ever sees them, and that scanner has its own case file.
_operator_corpus() {
    cat <<'CORPUS'
echo one && echo two
echo one ; echo two
echo one || echo two
echo one && echo two && echo three
echo one && echo two || echo three
echo one || echo two && echo three
echo "a && b" && echo done
echo 'a && b' && echo done
echo "a ; b" && echo done
echo 'a ; b' && echo done
echo "a || b" && echo done
echo one && echo "two && three"
echo one && echo 'two ; three'
echo one && echo "two | three"
echo one && echo "two && three" && echo four
CORPUS
}

# The two must agree, command for command.
t_operator_layer_agrees_with_bash() {
    local line oracle subject
    local -a corpus=()
    mapfile -t corpus < <(_operator_corpus)

    for line in "${corpus[@]}"; do
        [[ -z "$line" ]] && continue

        oracle="$(_oracle_bash "$line" | _normalise_list)"
        subject="$(_subject_igitari "$line" | _normalise_list)"

        [[ "$oracle" == "$subject" ]] && continue

        fail_assert "bash and Igitari disagree on [$line]"$'\n' \
            "        bash:    $(printf '%s' "$oracle" | tr '\n' '|')"$'\n' \
            "        igitari: $(printf '%s' "$subject" | tr '\n' '|')"
    done
}

# The specific failure that motivated the oracle, kept as its own case so the
# reason it exists is not lost.
t_operator_layer_does_not_split_inside_quotes() {
    local subject
    subject="$(_subject_igitari 'echo "a && b" && echo done' | _normalise_list)"

    assert_eq "$subject" "echo a && b"$'\n'"echo done" \
        "a quoted && is part of the message, not an operator"
}

# And the short-circuit rule, which POSIX defines as left to right:
# 'a || b && c' is '(a || b) && c', so a successful 'a' means 'b' is
# skipped and 'c' still runs.
t_operator_layer_short_circuits_left_to_right() {
    local subject
    subject="$(_subject_igitari 'echo one || echo two && echo three' | _normalise_list)"

    assert_eq "$subject" "echo one"$'\n'"echo three" \
        "a satisfied || still lets the && run"
}

# --- the updater's commit range, against git -------------------------------

# The compare payload GitHub returns, built from a real commit list.
#
# The shape is GitHub's -- 2-space indent for the array, 6 for a sha, 8 for a
# message -- because the parser keys on the indentation, and a fixture with
# the wrong shape would prove nothing.
_make_compare_payload() {
    local total="$1"
    local -a shas=()
    mapfile -t shas

    local first=1 sha
    {
        printf '{\n  "total_commits": %s,\n  "commits": [\n' "$total"
        for sha in "${shas[@]}"; do
            [[ $first -eq 1 ]] || printf ',\n'
            first=0
            printf '    {\n      "sha": "%s",\n      "commit": {\n        "message": "commit %s"\n      }\n    }' \
                "$sha" "${sha:0:8}"
        done
        printf '\n  ],\n  "files": []\n}\n'
    }
}

# The updater's commit range must be exactly git's.
#
# The oracle is git: the set of commits between two SHAs is a fact git can
# answer, and it is the same fact the updater is trying to report to the
# user. A fixture could only assert that the updater still agrees with a
# list someone wrote down; this asserts that it agrees with git.
#
# The payload is served by a stub that models the endpoint's two modes: a
# request for a page returns that page, and a request for NO page returns the
# LAST page -- which is what the endpoint actually does, and how the
# truncation happened.
#
# The page size is dropped so the range spans many pages. That is what makes
# the test bite: with one page, a client that fetched the tail and a client
# that fetched the whole range would look identical.
t_updater_range_matches_git_log() {
    local base head
    base="$(git -C "$REPO_ROOT" rev-list --max-parents=0 mono-master)"
    head="$(git -C "$REPO_ROOT" rev-parse mono-master)"

    local -a commits=()
    mapfile -t commits < <(git -C "$REPO_ROOT" rev-list --reverse "$base..$head")

    [[ ${#commits[@]} -gt 20 ]] \
        || fail_assert "the oracle needs a real history, got ${#commits[@]} commits"

    local payload_file
    payload_file="$(mktemp "${TMPDIR:-/tmp}/igitari-payload.XXXXXX")"
    _make_compare_payload "${#commits[@]}" < <(printf '%s\n' "${commits[@]}") >"$payload_file"

    # The stub is written to a file rather than an inline string: it has
    # enough quoting in it to be worth reading.
    local stub
    stub="$(mktemp "${TMPDIR:-/tmp}/igitari-stub.XXXXXX")"
    cat >"$stub" <<'STUB'
source "$1" >/dev/null 2>&1

# Small pages, so the range spans many of them.
_UPDATER_COMPARE_PAGE_SIZE=10
# ...and enough of them to fetch the whole range. The budget is a separate
# limit with its own case; this one is about correctness.
_UPDATER_MAX_COMPARE_PAGES=64

# The commits, read out of the payload in GitHub's shape.
mapfile -t all_shas < <(sed -n 's/^      "sha": "\(.*\)",$/\1/p' "$2")

# Serve a page of the range in GitHub's shape.
#
# Two modes, and the second one is the one that matters: asked for a page,
# it returns that page; asked for NOTHING, it returns the LAST page, which is
# what the endpoint actually does, and how the truncation happened.
_updater_api_get() {
    local url="$1"
    local page="" per=250

    # "&page=" not "page=": the URL also carries "per_page=", and that ends
    # in the same three letters.
    [[ "$url" == *"&page="* ]] && page="${url##*&page=}"
    if [[ "$url" == *"per_page="* ]]; then
        per="${url##*per_page=}"
        per="${per%%&*}"
    fi

    local -a slice=()
    if [[ -z "$page" ]]; then
        local start=$(( ${#all_shas[@]} - per ))
        (( start < 0 )) && start=0
        slice=("${all_shas[@]:start}")
    else
        local start=$(( (page - 1) * per ))
        (( start < ${#all_shas[@]} )) && slice=("${all_shas[@]:start:per}")
    fi

    printf '{\n  "total_commits": %s,\n  "commits": [\n' "${#all_shas[@]}"
    local first=1 sha
    for sha in "${slice[@]}"; do
        [[ $first -eq 1 ]] || printf ',\n'
        first=0
        printf '    {\n      "sha": "%s",\n      "commit": {\n        "message": "commit %s"\n      }\n    }' \
            "$sha" "${sha:0:8}"
    done
    printf '\n  ],\n  "files": []\n}\n'
}

dir="$(mktemp -d "${TMPDIR:-/tmp}/igitari-range.XXXXXX")"
stats="$(_updater_fetch_compare base head "$dir")" || { echo "fetch failed"; exit 1; }
printf '%s\n' "$stats"

# What the updater actually assembled.
sed -n 's/^      "sha": "\(.*\)",$/\1/p' "$dir/all" | sort
rm -rf "$dir"
STUB

    local out
    out="$(cd "$WORK" && IGITARI_TEST=1 bash "$stub" "$IGITARI" "$payload_file" 2>/dev/null)"
    rm -f "$stub"

    rm -f "$payload_file"

    local stats
    stats="$(printf '%s\n' "$out" | head -1)"
    local got
    got="$(printf '%s\n' "$out" | tail -n +2 | sort)"

    local -a want=()
    mapfile -t want < <(printf '%s\n' "${commits[@]}" | sort)

    local -a have=()
    mapfile -t have <<<"$got"

    if [[ "${#have[@]}" != "${#want[@]}" ]]; then
        fail_assert "the updater assembled $((${#have[@]} - ${#want[@]})) too few commits; stats=[$stats]"
    fi

    # Membership by string search, not by piping into grep.
    #
    # 'printf ... | grep -qx' is a trap: grep -q exits the moment it finds a
    # match, the writer takes SIGPIPE, and under 'set -o pipefail' the
    # pipeline reports failure even though the match was found. The commit
    # that gets reported missing is whichever one sat early enough in the
    # list for grep to exit before printf finished -- so the test's verdict
    # depended on the sort order.
    local missing=""
    local have_joined=" ${have[*]} "
    local c
    for c in "${want[@]}"; do
        [[ "$have_joined" == *" $c "* ]] || missing+="$c "
    done
    assert_eq "$missing" "" "no commit is missing from the updater's range"
}
