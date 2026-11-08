# shellcheck shell=bash
# Forge adapter -- detection and parsing, without touching the network.
#
# These tests protect the tier boundary. The adapter must be silent on failure
# and must never guess which client to use: a wrong guess reaches the network
# with the wrong tool, which is worse than saying nothing at all.

t_forge_remote_host_https() {
    git remote add origin https://github.com/owner/repo.git
    assert_eq "$(__forge_remote_host origin)" "github.com" "https host"
}

t_forge_remote_host_scp_syntax() {
    git remote add origin git@gitlab.com:owner/repo.git
    assert_eq "$(__forge_remote_host origin)" "gitlab.com" "scp host"
}

t_forge_remote_host_drops_user_and_port() {
    git remote add origin ssh://git@git.example.com:2222/owner/repo.git
    assert_eq "$(__forge_remote_host origin)" "git.example.com" \
        "a port belongs to the sshd, not the host"
}

t_forge_remote_host_is_lowercased() {
    git remote add origin https://GitHub.COM/owner/repo.git
    assert_eq "$(__forge_remote_host origin)" "github.com" "host is case-folded"
}

t_forge_remote_host_rejects_a_local_path() {
    git remote add origin /tmp/somewhere/repo.git
    __forge_remote_host origin >/dev/null
    assert_eq "$?" "1" "a folder has no forge"
}

t_forge_provider_detects_github() {
    git remote add origin https://github.com/owner/repo.git
    assert_eq "$(__forge_provider)" "gh" "github.com is gh"
}

t_forge_provider_detects_gitlab() {
    git remote add origin git@gitlab.com:owner/repo.git
    assert_eq "$(__forge_provider)" "glab" "gitlab.com is glab"
}

t_forge_provider_override_beats_the_remote() {
    # The whole point: a self-hosted forge sits on a hostname nobody can sniff.
    git remote add origin https://github.com/owner/repo.git
    # Must be exported, not a prefix assignment: $(...) expands before a
    # 'VAR=x cmd' assignment takes effect, so the prefix form would be invisible
    # to the function under test.
    export FORGE_PROVIDER=glab
    assert_eq "$(__forge_provider)" "glab" \
        "an explicit provider wins over the remote"
    unset FORGE_PROVIDER
}

t_forge_provider_reads_the_session_setting() {
    git remote add origin https://github.com/owner/repo.git
    execute_cmd "config session igitari.forge glab" >/dev/null
    assert_eq "$(__forge_provider)" "glab" "session override is honoured"
}

t_forge_provider_rejects_an_unknown_override() {
    git remote add origin https://github.com/owner/repo.git
    FORGE_PROVIDER=nonsense __forge_provider >/dev/null
    assert_eq "$?" "1" "a typo must not silently fall back to sniffing"
}

t_forge_provider_refuses_to_guess_an_unknown_host() {
    git remote add origin https://git.example.com/owner/repo.git
    # A session override is exported into GIT_CONFIG_* and survives between
    # tests in this shell, so clear it before asking what the remote says.
    SESSION_CONFIG=()
    __session_config_export
    __forge_provider >/dev/null
    assert_eq "$?" "1" "unknown host is not a guess"
}

t_forge_available_needs_a_client() {
    git remote add origin https://github.com/owner/repo.git
    # Nothing on PATH means nothing to exec, whatever the provider says.
    PATH="" __forge_available
    assert_eq "$?" "1" "no client, no forge"
}

t_forge_available_when_the_client_exists() {
    git remote add origin https://github.com/owner/repo.git
    mkdir -p fakebin
    printf '#!/bin/sh\nexit 0\n' >fakebin/gh
    chmod +x fakebin/gh
    PATH="$PWD/fakebin:$PATH" __forge_available
    assert_eq "$?" "0" "a client on PATH is enough"
}

t_forge_parse_object_splits_kind_and_id() {
    local kind id
    __forge_parse_object "pr:32" kind id
    assert_eq "$kind" "pr" "kind"
    assert_eq "$id" "32" "id"
}

t_forge_parse_object_keeps_dots_and_slashes() {
    local kind id
    __forge_parse_object "release:v2.0" kind id
    assert_eq "$kind" "release" "kind"
    assert_eq "$id" "v2.0" "a tag is not a number"
}

t_forge_parse_object_rejects_a_bare_number() {
    # A bare 1234 must stay git's path-or-ref, never a forge object.
    local kind id
    __forge_parse_object "1234" kind id
    assert_eq "$?" "1" "bare integers are not objects"
}

t_forge_parse_object_rejects_an_empty_id() {
    local kind id
    __forge_parse_object "pr:" kind id
    assert_eq "$?" "1" "kind without id"
}

t_forge_parse_object_rejects_whitespace() {
    local kind id
    __forge_parse_object "pr:3 2" kind id
    assert_eq "$?" "1" "an object is one token"
}

t_forge_parse_object_rejects_an_empty_kind() {
    local kind id
    __forge_parse_object ":32" kind id
    assert_eq "$?" "1" "id without kind"
}

# --- listings and the blend points ---------------------------------------
#
# A fake client on PATH keeps these hermetic: no network, no auth, and the
# assertions are about the shape Igitari hands on, not about gh's behaviour.

__fake_client() {
    mkdir -p fakebin
    cat >fakebin/gh <<'FAKE'
#!/bin/sh
case "$1 $2" in
"pr list") printf '7\tFaster tests\n12\tFix the parser\n' ;;
"issue list") printf '9\tBad docs\n' ;;
"discussion list") printf '3\tRoadmap question\n' ;;
"pr view") printf '7' ;;
esac
exit 0
FAKE
    chmod +x fakebin/gh
    PATH="$PWD/fakebin:$PATH"
    export PATH
}

t_forge_list_prs_is_number_tab_title() {
    git remote add origin https://github.com/owner/repo.git
    __fake_client

    assert_eq "$(__forge_list prs)" "$(printf '7\tFaster tests\n12\tFix the parser')" \
        "prs listing"
}

t_forge_list_discussions_unwraps_gh_shape() {
    git remote add origin https://github.com/owner/repo.git
    __fake_client

    assert_eq "$(__forge_list discussions)" "$(printf '3\tRoadmap question')" \
        "discussions listing"
}

t_forge_list_is_silent_without_a_client() {
    git remote add origin https://github.com/owner/repo.git
    PATH="" __forge_list prs
    assert_eq "$?" "1" "no client, no listing"
}

t_forge_object_kind_follows_the_provider() {
    git remote add origin https://github.com/owner/repo.git
    assert_eq "$(__forge_object_kind prs)" "pr" "github says pull request"
    assert_eq "$(__forge_object_kind issues)" "issue" "issues everywhere"
    assert_eq "$(__forge_object_kind discussions)" "discussion" "discussions"

    export FORGE_PROVIDER=glab
    assert_eq "$(__forge_object_kind prs)" "mr" "gitlab says merge request"
    unset FORGE_PROVIDER
}

t_guess_pr_prints_the_colon_noun() {
    git remote add origin https://github.com/owner/repo.git
    __fake_client

    assert_eq "$(guess pr)" "pr:7" "guess pr returns a forge object"
}

t_guess_pr_keeps_stdout_empty_on_failure() {
    git remote add origin https://github.com/owner/repo.git
    # No client on PATH, so it cannot answer.
    local out
    out=$(PATH="" guess pr 2>/dev/null)
    assert_eq "$out" "" "a failed guess must not print a value"
}

t_fzf_forge_returns_a_bare_number_by_default() {
    git remote add origin https://github.com/owner/repo.git
    __fake_client
    # Pick the first line of whatever it is handed, like a user pressing enter.
    cat >fakebin/fzf <<'FAKE'
#!/bin/sh
head -1
FAKE
    chmod +x fakebin/fzf

    assert_eq "$(fzf prs)" "7" "fzf prs hands back the number"
}

t_fzf_forge_ref_returns_the_colon_form() {
    git remote add origin https://github.com/owner/repo.git
    __fake_client
    cat >fakebin/fzf <<'FAKE'
#!/bin/sh
head -1
FAKE
    chmod +x fakebin/fzf

    assert_eq "$(fzf prs ref)" "pr:7" "fzf prs ref feeds the forge namespace"
}

t_fzf_forge_says_so_when_there_is_no_forge() {
    git remote add origin https://git.example.com/owner/repo.git
    SESSION_CONFIG=()
    __session_config_export
    local out
    out=$(fzf prs 2>/dev/null)
    assert_contains "$out" "isn't a forge" "no forge is explained"
}

# --- the forge namespace --------------------------------------------------
#
# The fake client records its arguments, so these assert what Igitari decided
# to send: the noun is translated, everything else is the client's own.

__recording_client() {
    mkdir -p fakebin
    cat >fakebin/gh <<'FAKE'
#!/bin/sh
printf '%s\n' "$*" >> "$FAKE_LOG"
case "$1 $2" in
"release view") exit 0 ;;
esac
exit 0
FAKE
    chmod +x fakebin/gh
    PATH="$PWD/fakebin:$PATH"
    export PATH
    FAKE_LOG="$PWD/calls.log"
    : >"$FAKE_LOG"
    export FAKE_LOG
}

t_forge_needs_a_client() {
    git remote add origin https://github.com/owner/repo.git
    # Say which provider, so detection does not need git on PATH: this test is
    # about the missing client, not about detection.
    export FORGE_PROVIDER=gh
    local out
    out=$(PATH="" forge checkout pr:32 -y 2>&1)
    unset FORGE_PROVIDER
    assert_contains "$out" "not installed" "the missing client is named"
}

t_forge_checkout_translates_the_noun() {
    git remote add origin https://github.com/owner/repo.git
    __recording_client

    forge checkout pr:32 -y >/dev/null 2>&1
    assert_eq "$(cat calls.log)" "pr checkout 32" "pr:32 becomes 'pr checkout 32'"
}

t_forge_checkout_refuses_a_bad_object() {
    git remote add origin https://github.com/owner/repo.git
    __recording_client

    local out
    out=$(forge checkout 32 -y 2>&1)
    assert_contains "$out" "not a forge object" "a bare number is not an object"
    assert_eq "$(cat calls.log)" "" "nothing was called"
}

t_forge_checks_the_object_against_the_verb() {
    git remote add origin https://github.com/owner/repo.git
    __recording_client

    local out
    out=$(forge merge issue:812 -y 2>&1)
    assert_contains "$out" "does not take a 'issue'" "kind mismatch is refused"
    assert_eq "$(cat calls.log)" "" "no network call for a mismatch"
}

t_forge_passes_flags_through_untouched() {
    git remote add origin https://github.com/owner/repo.git
    __recording_client

    forge close issue:812 -y --reason "not planned" >/dev/null 2>&1
    assert_eq "$(cat calls.log)" "issue close 812 --reason not planned" \
        "the client's own flags survive"
}

t_forge_never_forwards_its_own_yes() {
    git remote add origin https://github.com/owner/repo.git
    __recording_client

    forge close issue:812 -y >/dev/null 2>&1
    assert_eq "$(cat calls.log)" "issue close 812" "-y is Igitari's, not gh's"
}

t_forge_create_takes_a_kind_not_an_object() {
    git remote add origin https://github.com/owner/repo.git
    __recording_client

    forge create issue --title "Broken" >/dev/null 2>&1
    assert_eq "$(cat calls.log)" "issue create --title Broken" \
        "create passes the kind with no id"
}

t_forge_rejects_an_unknown_verb() {
    git remote add origin https://github.com/owner/repo.git
    __recording_client

    local out
    out=$(forge frobnicate pr:1 -y 2>&1)
    assert_contains "$out" "not a forge verb" "unknown verbs are named"
    assert_eq "$(cat calls.log)" "" "nothing was called"
}

t_forge_release_checkout_is_git_work() {
    git remote add origin https://github.com/owner/repo.git
    __recording_client
    commit_file a.txt one "first"
    git tag v1.0

    commit_file b.txt two "second"
    forge checkout release:v1.0 -y >/dev/null 2>&1

    assert_eq "$(git rev-parse --abbrev-ref HEAD)" "HEAD" \
        "a release checks out its tag, detached"
    assert_eq "$(git rev-parse HEAD)" "$(git rev-parse v1.0)" "at the tag"
}

t_guess_pr_never_guesses_on_the_default_branch() {
    git remote add origin https://github.com/owner/repo.git
    commit_file a.txt one "first"
    # Pretend origin's default is master, and that some fork has a PR whose
    # head branch happens to be called master. That is a real situation, and
    # returning its number would point at somebody else's work.
    git update-ref refs/remotes/origin/master HEAD
    git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/master

    mkdir -p fakebin
    cat >fakebin/gh <<'FAKE'
#!/bin/sh
case "$1 $2" in
"pr view") exit 1 ;;
"pr list") printf '6154\n' ;;
esac
exit 0
FAKE
    chmod +x fakebin/gh
    PATH="$PWD/fakebin:$PATH"
    export PATH

    local out
    out=$(guess pr 2>/dev/null)
    assert_eq "$out" "" "a shared branch name is not an answer"
}
