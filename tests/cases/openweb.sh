# shellcheck shell=bash
# openweb — turn a git remote into a browser-openable HTTPS URL.
#
# The core of this file used to assume the remote was an https URL and hand
# whatever git said to the browser. ssh remotes (git@host:user/repo, or
# ssh://git@host:port/user/repo) arrived as relative filenames and failed in
# the browser. These tests pin the normaliser that replaces that assumption,
# and the refusal path for local-path remotes.

t_openweb_ssh_scp_remote_becomes_https() {
    new_repo
    git remote add origin git@github.com:user/repo.git

    local out status=0
    out=$(openweb origin 2>/dev/null) || status=$?

    assert_contains "$out" "https://github.com/user/repo" "scp-style remote"
    ((status == 0)) || fail_assert "openweb should succeed for an ssh remote"
}

t_openweb_https_remote_is_left_alone_and_dotgit_trimmed() {
    new_repo
    git remote add origin https://github.com/user/repo.git

    local out
    out=$(openweb origin 2>/dev/null)

    assert_contains "$out" "https://github.com/user/repo" "https remote, .git trimmed"
}

t_openweb_ssh_url_with_port_drops_the_port() {
    new_repo
    git remote add origin ssh://git@gitlab.com:2222/grp/sub/proj.git

    local out
    out=$(openweb origin issues 2>/dev/null)

    # :2222 is the ssh listener, not the web server: it must not survive.
    assert_contains "$out" "https://gitlab.com/grp/sub/proj/issues" "port dropped"
}

t_openweb_nested_paths_survive() {
    new_repo
    git remote add origin git@gitlab.com:group/sub/repo.git

    local out
    out=$(openweb origin pr 2>/dev/null)

    assert_contains "$out" "https://gitlab.com/group/sub/repo/pulls" "nested group path"
}

t_openweb_pages_append_to_any_remote() {
    new_repo
    git remote add origin git@example.com:thing.git

    local out
    out=$(openweb origin issues 2>/dev/null)
    assert_contains "$out" "https://example.com/thing/issues" "issues page"

    out=$(openweb origin pr create 2>/dev/null)
    assert_contains "$out" "https://example.com/thing/compare" "pr create page"

    out=$(openweb origin wiki 2>/dev/null)
    assert_contains "$out" "https://example.com/thing/wiki" "wiki page"
}

t_openweb_refuses_a_local_path_remote() {
    new_repo
    git remote add origin /srv/git/thing.git

    local out status=0
    out=$(openweb origin issues 2>/dev/null) || status=$?

    # Errors go to stdout here, the way the rest of Igitari's messages do, so
    # the check is that no URL was produced -- not that nothing was printed.
    [[ "$out" != *"https://"* ]] || fail_assert "no URL should be built for a local path remote"
    assert_contains "$out" "local path" "the refusal explains itself"
    ((status != 0)) || fail_assert "local path remote should fail loudly"
}

t_openweb_refuses_when_remote_does_not_exist() {
    new_repo

    local out status=0
    out=$(openweb nope issues 2>/dev/null) || status=$?

    [[ "$out" != *"https://"* ]] || fail_assert "no URL should be built for an unknown remote"
    ((status != 0)) || fail_assert "unknown remote should fail loudly"
}