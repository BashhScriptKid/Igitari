# shellcheck shell=bash
# Session-scoped configuration.
#
# The promise under test is narrow and worth pinning exactly: an override
# applies to git commands run afterwards, and nothing is written to disk. Both
# halves fail silently if broken -- a leaked write would only be noticed much
# later, in a repo you had since pushed.

t_session_overrides_git_identity() {
    commit_file a.txt one "first"

    execute_cmd 'config session user.email session@example.com' >/dev/null
    execute_cmd 'commit -q --allow-empty -m "as the session user"'

    assert_eq "$(git log -1 --format='%ae')" "session@example.com" \
        "author email of the new commit"
}

# The one that matters most: an override is a working-tree concern, never a
# config-file concern.
t_session_writes_nothing_to_disk() {
    commit_file a.txt one "first"
    local before
    before=$(cat .git/config)

    execute_cmd 'config session user.email session@example.com' >/dev/null
    execute_cmd 'commit -q --allow-empty -m "as the session user"'

    assert_eq "$(cat .git/config)" "$before" "the contents of .git/config"
    assert_eq "$(git config --file .git/config --get user.email)" "test@example.com" \
        "user.email on disk"
}

t_session_unset_restores_identity() {
    commit_file a.txt one "first"
    execute_cmd 'config session user.email session@example.com' >/dev/null
    execute_cmd 'config session --unset user.email' >/dev/null

    execute_cmd 'commit -q --allow-empty -m "back to me"'
    assert_eq "$(git log -1 --format='%ae')" "test@example.com" \
        "author email after unsetting the override"
}

# A shorter session must not keep honouring a longer one's stale pointers --
# the export is index-based, so this is where that would go wrong.
t_session_clear_forgets_everything() {
    commit_file a.txt one "first"
    execute_cmd 'config session user.email one@example.com' >/dev/null
    execute_cmd 'config session user.name Some One' >/dev/null
    execute_cmd 'config session --clear' >/dev/null

    execute_cmd 'commit -q --allow-empty -m "after clearing"'
    assert_eq "$(git log -1 --format='%ae')" "test@example.com" "author email"
    assert_eq "$(git log -1 --format='%an')" "Test User" "author name"
}

# Removing one of two overrides must not disturb the other.
t_session_unset_leaves_others_alone() {
    commit_file a.txt one "first"
    execute_cmd 'config session user.email one@example.com' >/dev/null
    execute_cmd 'config session user.name Some One' >/dev/null
    execute_cmd 'config session --unset user.email' >/dev/null

    execute_cmd 'commit -q --allow-empty -m "name kept, email restored"'
    assert_eq "$(git log -1 --format='%ae')" "test@example.com" "author email"
    assert_eq "$(git log -1 --format='%an')" "Some One" "author name"
}
