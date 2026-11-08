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

    assert_contains "$out" "https://gitlab.com/group/sub/repo/merge_requests" "nested group path"
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

    # $(...) here is only how a test observes a function whose job is to open
    # a browser; openweb is a terminal action and is never substituted in real
    # use, so its stdout carries prose and that is fine. (Contrast 'guess',
    # which promises empty-on-failure because scripts DO substitute it.)
    # So the check is that no URL was built -- not that nothing was printed.
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
# Forges disagree on what to call the pull-request list, so the path is
# derived from the host instead of defaulting to GitHub's word. Bitbucket's
# 'pull-requests' is the trap here: a naive '%s' match would also catch it.
t_openweb_github_uses_pulls() {
    new_repo
    git remote add origin git@github.com:user/repo.git

    local out
    out=$(openweb origin pr 2>/dev/null)
    assert_contains "$out" "https://github.com/user/repo/pulls" "github pr list"
}

t_openweb_gitlab_uses_merge_requests() {
    new_repo
    git remote add origin git@gitlab.com:grp/proj.git

    local out
    out=$(openweb origin pr 2>/dev/null)
    assert_contains "$out" "https://gitlab.com/grp/proj/merge_requests" "gitlab pr list"

    out=$(openweb origin wiki 2>/dev/null)
    assert_contains "$out" "https://gitlab.com/grp/proj/wikis" "gitlab wiki"
}

t_openweb_bitbucket_uses_pull_requests() {
    new_repo
    git remote add origin git@bitbucket.org:team/repo.git

    local out
    out=$(openweb origin pr 2>/dev/null)
    assert_contains "$out" "https://bitbucket.org/team/repo/pull-requests" "bitbucket pr list"
}

t_openweb_self_hosted_forgejo_keeps_pulls() {
    new_repo
    git remote add origin https://forgejo.example.com/u/r.git

    local out
    out=$(openweb origin pr 2>/dev/null)
    assert_contains "$out" "https://forgejo.example.com/u/r/pulls" "self-hosted gitea family"
}

t_openweb_pr_create_is_the_same_page_everywhere() {
    new_repo
    git remote add origin git@gitlab.com:grp/proj.git

    # The new-pull form lives on /compare for both, so the forge mapping must
    # not leak into this branch of the case statement.
    local out
    out=$(openweb origin pr create 2>/dev/null)
    assert_contains "$out" "https://gitlab.com/grp/proj/compare" "pr create on gitlab"
}

# --- blended forge objects ------------------------------------------------
#
# The number goes in the slot the page word already opened. No client, no
# auth, no network: these are URL arithmetic, which is why openweb can do it
# on a machine with no forge installed at all.

t_openweb_issue_number() {
    git remote add origin https://github.com/user/repo.git
    local out
    out=$(openweb origin issues 553 2>/dev/null)
    assert_contains "$out" "https://github.com/user/repo/issues/553" "one issue"
}

t_openweb_pull_request_number() {
    git remote add origin https://github.com/user/repo.git
    local out
    out=$(openweb origin prs 42 2>/dev/null)
    assert_contains "$out" "https://github.com/user/repo/pulls/42" "one pull request"
}

t_openweb_discussion_number() {
    git remote add origin https://github.com/user/repo.git
    git remote add upstream https://github.com/other/repo.git
    local out
    out=$(openweb upstream discussions 9553 2>/dev/null)
    assert_contains "$out" "https://github.com/other/repo/discussions/9553" "one discussion"
}

t_openweb_release_tag() {
    git remote add origin https://github.com/user/repo.git
    local out
    out=$(openweb origin releases v2.0 2>/dev/null)
    assert_contains "$out" "https://github.com/user/repo/releases/tag/v2.0" "one release"
}

t_openweb_gitlab_numbered_paths_use_the_dash_prefix() {
    git remote add origin https://gitlab.com/grp/proj.git

    local out
    out=$(openweb origin issues 553 2>/dev/null)
    assert_contains "$out" "https://gitlab.com/grp/proj/-/issues/553" "gitlab issue"

    out=$(openweb origin mr 7 2>/dev/null)
    assert_contains "$out" "https://gitlab.com/grp/proj/-/merge_requests/7" "gitlab MR"
}

t_openweb_number_is_not_mistaken_for_a_subcommand() {
    # 'pr create' must still reach compare: 'create' is a word, not a number.
    git remote add origin https://github.com/user/repo.git
    local out
    out=$(openweb origin pr create 2>/dev/null)
    assert_contains "$out" "https://github.com/user/repo/compare" "pr create"
}
