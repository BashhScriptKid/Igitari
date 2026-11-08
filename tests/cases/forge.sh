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
