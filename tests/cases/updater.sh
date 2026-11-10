# shellcheck shell=bash
# The updater's changelog: which commits it asks GitHub for, and what it says
# when it could not get them all.
#
# The bug these pin is invisible from the outside. GitHub's compare endpoint
# returns the LAST 250 commits of a range when no page is asked for, and pages
# from the OLDEST end when one is. So a user who was a long way behind their
# install was shown a changelog that began halfway through their own history,
# with nothing saying it had been cut short. The fix is to ask for pages
# explicitly, and to be honest about what is missing.
#
# No network here: _updater_api_get is replaced with a stub that serves
# fixtures, so the paging is exercised and the developer's connection is
# never touched.

# --- fixtures -------------------------------------------------------------

# A compare payload shaped the way GitHub sends one. The parser keys on the
# indentation -- 2 spaces for the array, 6 for a sha, 8 for a message -- so a
# fixture with a different shape would prove nothing.
#
# Usage: make_compare_page <total_commits> <sha>|<subject> ...
make_compare_page() {
    local total="$1"
    shift
    local first=1 entry sha msg

    printf '{\n  "total_commits": %s,\n  "commits": [\n' "$total"
    for entry in "$@"; do
        sha="${entry%%|*}"
        msg="${entry#*|}"
        [[ $first -eq 1 ]] || printf ',\n'
        first=0
        printf '    {\n      "sha": "%s",\n      "commit": {\n        "message": "%s"\n      }\n    }' \
            "$sha" "$msg"
    done
    printf '\n  ],\n  "files": []\n}\n'
}

# A sha that looks like a sha, because the parser treats it as one.
fixture_sha() {
    printf '%040d' "$1"
}

# --- the stub -------------------------------------------------------------

# Run a body against a stubbed GitHub, in its own shell so the stub cannot
# leak into the next test.
#
# The body may use $PAGES_DIR (a directory of page-N fixtures) and $REQUESTS
# (a file the stub appends every requested URL to).
run_with_stub() {
    local body="$1"
    local script_file
    script_file="$(mktemp "${TMPDIR:-/tmp}/igitari-updater.XXXXXX")"

    {
        printf 'set -uo pipefail\n'
        printf 'export IGITARI_TEST=1\n'
        printf 'source %q >/dev/null 2>&1\n' "$IGITARI"
        printf '%s\n' "$body"
    } >"$script_file"

    local out
    out="$(bash --norc "$script_file" 2>&1)"
    rm -f "$script_file"
    printf '%s' "$out"
}

# The stub itself, written into the test shell.
#
# It serves "$PAGES_DIR/page-N" for a URL ending in page=N, and fails for
# anything else -- so a request that forgot to ask for a page is visible
# rather than quietly answered.
STUB_SOURCE='
_updater_api_get() {
    local url="$1"
    printf "%s\n" "$url" >>"${REQUESTS:-/dev/null}"
    local page
    page="${url##*page=}"
    [[ "$page" == "$url" ]] && return 1
    [[ -f "$PAGES_DIR/page-$page" ]] || return 1
    cat "$PAGES_DIR/page-$page"
    return 0
}
'

# --- the tests ------------------------------------------------------------

# The whole point of the fix: the oldest end of the range, not the newest.
t_compare_asks_for_the_oldest_end() {
    local dir out requests
    dir="$(mktemp -d "${TMPDIR:-/tmp}/igitari-pages.XXXXXX")"
    requests="${dir}/requests"

    # One page, three commits. The oldest one is the one that would go
    # missing if the endpoint were left to its default.
    make_compare_page 3 \
        "$(fixture_sha 1)|oldest commit" \
        "$(fixture_sha 2)|middle commit" \
        "$(fixture_sha 3)|newest commit" >"${dir}/page-1"

    out="$(PAGES_DIR="$dir" REQUESTS="$requests" run_with_stub "$STUB_SOURCE"'
        mkdir -p "$PAGES_DIR/out"
        _updater_fetch_compare base head "$PAGES_DIR/out"
    ')" 2>&1

    # The request must name a page. Without one the endpoint answers with the
    # newest 250 of the range, which is the bug.
    [[ -f "$requests" ]] || { rm -rf "$dir"; fail_assert "no request was made"; return; }
    assert_contains "$(cat "$requests")" "page=1" "the request asks for a page"

    # And the oldest commit must be in what came back.
    local payload="${dir}/out/all"
    [[ -f "$payload" ]] || { rm -rf "$dir"; fail_assert "no payload was assembled"; return; }
    assert_contains "$(cat "$payload")" "oldest commit" "the oldest commit is in the payload"

    rm -rf "$dir"
}

# A range longer than one page: the release marker lives on the last page,
# and the changelog has to hold every page.
t_compare_spans_pages_and_finds_the_marker() {
    local dir out payload
    dir="$(mktemp -d "${TMPDIR:-/tmp}/igitari-pages.XXXXXX")"

    # Three pages' worth: 250 + 250 + 100 commits.
    local -a p1=() p2=() p3=()
    local i
    for i in $(seq 1 250); do p1+=("$(fixture_sha $i)|page one commit $i"); done
    for i in $(seq 251 500); do p2+=("$(fixture_sha $i)|page two commit $i"); done
    for i in $(seq 501 600); do p3+=("$(fixture_sha $i)|page three commit $i"); done
    # The marker is on the last page, with the head after it.
    p3+=("$(fixture_sha 601)|Bump version to 9.9.9")
    p3+=("$(fixture_sha 602)|the head commit")

    make_compare_page 600 "${p1[@]}" >"${dir}/page-1"
    make_compare_page 600 "${p2[@]}" >"${dir}/page-2"
    make_compare_page 600 "${p3[@]}" >"${dir}/page-3"

    out="$(PAGES_DIR="$dir" run_with_stub "$STUB_SOURCE"'
        mkdir -p "$PAGES_DIR/out"
        _updater_fetch_compare base head "$PAGES_DIR/out"
    ')" 2>&1

    payload="${dir}/out/all"
    [[ -f "$payload" ]] || { rm -rf "$dir"; fail_assert "no payload was assembled"; return; }

    # The marker and the head are both found.
    local parsed
    parsed="$(PAGES_DIR="$dir" run_with_stub "$STUB_SOURCE"'
        _updater_parse_compare "$PAGES_DIR/out/all"
    ')" 2>&1
    assert_contains "$parsed" "9.9.9" "the version comes from the marker"
    assert_contains "$parsed" "$(fixture_sha 602)" "the target is the head commit"

    # And the changelog holds the oldest page too, not just the new end.
    assert_contains "$(cat "$payload")" "page one commit 1" "the oldest page is held"
    assert_contains "$(cat "$payload")" "page three commit 600" "the newest page is held"

    rm -rf "$dir"
}

# A range longer than the budget: the walk must stop, and what it holds must
# still be a contiguous window at the head with the marker in it.
t_compare_stops_at_the_budget() {
    local dir out requests
    dir="$(mktemp -d "${TMPDIR:-/tmp}/igitari-pages.XXXXXX")"
    requests="${dir}/requests"

    # Twenty pages' worth. The budget is four requests.
    local -a p1=() p18=() p19=() p20=()
    local i
    for i in $(seq 1 250); do p1+=("$(fixture_sha $i)|ancient commit $i"); done
    for i in $(seq 1 250); do p18+=("$(fixture_sha $i)|recent commit $i"); done
    for i in $(seq 1 250); do p19+=("$(fixture_sha $i)|recent commit $i"); done
    p20+=("$(fixture_sha 9001)|Bump version to 8.8.8")
    p20+=("$(fixture_sha 9002)|the head commit")

    make_compare_page 5000 "${p1[@]}" >"${dir}/page-1"
    make_compare_page 5000 "${p18[@]}" >"${dir}/page-18"
    make_compare_page 5000 "${p19[@]}" >"${dir}/page-19"
    make_compare_page 5000 "${p20[@]}" >"${dir}/page-20"

    out="$(PAGES_DIR="$dir" REQUESTS="$requests" run_with_stub "$STUB_SOURCE"'
        mkdir -p "$PAGES_DIR/out"
        _updater_fetch_compare base head "$PAGES_DIR/out"
    ')" 2>&1

    # The budget is the whole point: a check that runs on every start cannot
    # spend sixty requests an hour.
    local count
    count="$(grep -c . "$requests" 2>/dev/null || echo 0)"
    [[ "$count" -le 4 ]] \
        || fail_assert "the fetch spent $count requests; the budget is 4"

    # The window is anchored at the head, and the marker is in it.
    local payload="${dir}/out/all"
    [[ -f "$payload" ]] || { rm -rf "$dir"; fail_assert "no payload was assembled"; return; }
    assert_contains "$(cat "$payload")" "Bump version to 8.8.8" "the marker is in the window"

    # And it is a window, not a scatter: the page it could not reach is not
    # in there, so there is no hole pretending to be a list.
    [[ "$(cat "$payload")" != *"ancient commit 1"* ]] \
        || fail_assert "the unreachable page was kept, leaving a hole in the list"

    rm -rf "$dir"
}

# What the user is told has to match what was fetched.
t_the_notice_says_when_the_changelog_is_short() {
    local dir out home pending
    dir="$(mktemp -d "${TMPDIR:-/tmp}/igitari-pages.XXXXXX")"
    home="$(mktemp -d "${TMPDIR:-/tmp}/igitari-home.XXXXXX")"

    # A range of one page, but with more subjects than the print limit, so
    # the notice has to admit it left some out. The release marker has to be
    # in there too: without one there is no release, and the notice is
    # rightly not written.
    local -a commits=()
    local i
    for i in $(seq 1 40); do commits+=("$(fixture_sha $i)|commit number $i"); done
    commits+=("$(fixture_sha 901)|Bump version to 5.5.5")
    commits+=("$(fixture_sha 902)|the head commit")
    make_compare_page 42 "${commits[@]}" >"${dir}/page-1"

    pending="${home}/.update_pending"

    out="$(HOME="$home" PAGES_DIR="$dir" run_with_stub "$STUB_SOURCE"'
        export HOME="'"$home"'"
        UPDATE_PENDING_FILE="'"$pending"'"
        UPDATE_NEW_SHA_FILE="'"$home"'/.update_new_sha"
        _UPDATER_BACKGROUND=1
        _updater_handle_behind 1111111111111111111111111111111111111111 2222222222222222222222222222222222222222 ""
    ')" 2>&1

    [[ -f "$pending" ]] || { rm -rf "$dir" "$home"; fail_assert "no notice was written"; return; }
    local notice
    notice="$(cat "$pending")"

    assert_contains "$notice" "Update available" "the notice names the update"
    assert_contains "$notice" "5.5.5" "the notice names the version"
    assert_contains "$notice" "the head commit" "the newest commit is listed"
    assert_contains "$notice" "more commits since your version" \
        "the notice says the list was shortened"

    rm -rf "$dir" "$home"
}
