# shellcheck shell=bash
# tab completion — what Tab offers, and what it inserts.
#
# These tests protect the second half of every handler: the position logic.
# A handler that offers the right words at the wrong cursor position passes
# every test about its vocabulary and still breaks the prompt, which is
# exactly what happened when the first handlers read COMP_CWORD under
# `bind -x`, where it does not exist.
#
# So each test drives complete_git_env with a real line and asserts on the
# buffer it leaves behind. The offered list is checked where the interesting
# property is "these words and not those" -- for the positions where an
# offer would be inventing an argument git refuses.

# --- the positional helpers ---------------------------------------------
#
# Everything below depends on these, so they are checked first and in
# isolation: if __igitari_cword is wrong, every handler is wrong with it.

t_cword_counts_the_word_under_the_cursor() {
    commit_file a.txt one "first"

    # The helper takes word_start, which is where complete_git_env has
    # already walked back to -- not the cursor point. 'forge ' ends in a
    # space, so that word is finished and the cursor sits on word 1.
    assert_eq "$(__igitari_cword "forge " 6)" "1" "word after 'forge'"
    assert_eq "$(__igitari_cword "forge checkout " 15)" "2" "word after the verb"
    # Mid-word: 'log --on' has one finished word, so the cursor is on 1.
    assert_eq "$(__igitari_cword "log --on" 4)" "1" "word still being typed"
}

t_subcmd_finds_the_word_after_the_command() {
    commit_file a.txt one "first"

    assert_eq "$(__igitari_subcmd "forge checkout " 15)" "checkout" "the verb"
    assert_eq "$(__igitari_subcmd "worktree add newdir " 21)" "add" "worktree verb"
    # Flags are not subcommands.
    assert_eq "$(__igitari_subcmd "stash push --all " 17)" "push" "skips flags"
    assert_eq "$(__igitari_subcmd "forge " 6)" "" "no subcommand yet"
}

t_prev_word_finds_the_word_before_the_cursor() {
    commit_file a.txt one "first"

    assert_eq "$(__igitari_prev_word "notes add -m " 14)" "-m" "the flag just typed"
    assert_eq "$(__igitari_prev_word "notes " 6)" "notes" "the command itself"
    assert_eq "$(__igitari_prev_word "" 0)" "" "nothing typed"
}

# --- words a handler owns ------------------------------------------------
#
# The failure these guard against is not a missing word but a wrong one:
# handlers that read COMP_CWORD offered the fourteen forge verbs wherever
# the cursor stood.

t_forge_offers_verbs_at_the_first_word() {
    commit_file a.txt one "first"

    assert_offers "forge " "checkout"
    assert_offers "forge " "merge"
}

t_forge_offers_object_kinds_after_the_verb() {
    commit_file a.txt one "first"

    assert_offers "forge checkout " "pr:"
    assert_offers "forge checkout " "release:"
    assert_offers "forge merge " "mr:"
    # Every row spells the kind with the colon that marks it as a kind, so
    # 'create' does too -- it is a verb that takes a noun, not a revision.
    assert_offers "forge create " "pr:"
}

t_forge_does_not_offer_verbs_where_kinds_belong() {
    commit_file a.txt one "first"

    complete_line "forge checkout "
    [[ " $COMPLETION_WORDS " != *" checkout "* ]] \
        || fail_assert "after 'forge checkout' the verbs should be gone, got [$COMPLETION_WORDS]"
}

t_conflict_offers_sides_after_the_verb() {
    commit_file a.txt one "first"

    assert_offers "conflict " "show"
    assert_offers "conflict show " "theirs"
    assert_offers "conflict show " "ours"
}

t_config_keeps_subcommands_and_keys_apart() {
    commit_file a.txt one "first"

    # Word 1 is a subcommand; a key there would be the mixed list this
    # handler was fixed to stop offering.
    complete_line "config "
    [[ " $COMPLETION_WORDS " != *" user.name "* ]] \
        || fail_assert "word 1 should offer subcommands only, got [$COMPLETION_WORDS]"
    assert_offers "config " "get"

    # Below that it is a key, and the subcommands are gone.
    complete_line "config get "
    [[ " $COMPLETION_WORDS " != *" get "* ]] \
        || fail_assert "a setting name should not be offered subcommands, got [$COMPLETION_WORDS]"
}

# --- two-word commands ---------------------------------------------------
#
# Each of these had no handler and fell to the filename fallback, which is
# the failure that looks confident: it offers the working directory where git
# wants a verb.

t_worktree_offers_verbs_then_only_linked_worktrees() {
    commit_file a.txt one "first"
    # Inside $WORK, so the name cannot collide with a leftover from an
    # earlier run the way a bare ../wt-one would.
    git worktree add -q "wt-one" 2>/dev/null
    git worktree add -q "wt-two" 2>/dev/null

    assert_offers "worktree " "add"
    assert_offers "worktree " "unlock"

    # lock/remove name an existing linked worktree. The main worktree is
    # never an answer: git refuses it for all three. The linked ones live
    # under $WORK, so compare whole words rather than a substring.
    complete_line "worktree lock "
    assert_contains "$COMPLETION_WORDS" "wt-" "linked worktrees offered"
    local w offered_main=0
    for w in $COMPLETION_WORDS; do
        [[ "$w" == "$WORK" ]] && offered_main=1
    done
    ((offered_main == 0)) \
        || fail_assert "the main worktree must not be offered: [$COMPLETION_WORDS]"
}

t_worktree_list_and_prune_offer_nothing() {
    commit_file a.txt one "first"

    # Neither takes a positional argument, so any offer would be a guess at
    # something git rejects.
    assert_offers_nothing "worktree list "
    assert_offers_nothing "worktree prune "
}

t_submodule_completes_the_paths_from_gitmodules() {
    commit_file a.txt one "first"
    # A declared submodule that was never initialised: the path still exists
    # in .gitmodules, and `submodule status` says nothing about it.
    cat >.gitmodules <<'MOD'
[submodule "libs/lib"]
	path = libs/lib
	url = https://example.invalid/lib.git
MOD
    git add .gitmodules && git commit -q -m submodule

    assert_offers "submodule " "init"
    assert_completes_to "submodule init " "submodule init libs/lib "
}

t_submodule_offers_nothing_where_a_url_belongs() {
    commit_file a.txt one "first"

    # `submodule add <url>` clones from the network; nothing on this disk is
    # a candidate, so offering files would be inventing one.
    assert_offers_nothing "submodule add "
}

# --- bisect: a vocabulary the user can rename -----------------------------

t_bisect_offers_only_start_and_replay_when_idle() {
    commit_file a.txt one "first"

    complete_line "bisect "
    assert_offers "bisect " "start"
    assert_offers "bisect " "replay"
    # Nothing to reset, skip or mark outside a bisection.
    [[ " $COMPLETION_WORDS " != *" reset "* ]] \
        || fail_assert "idle bisect should not offer reset, got [$COMPLETION_WORDS]"
}

t_bisect_offers_custom_terms_in_force() {
    commit_file a.txt one "first"
    for i in 2 3 4 5 6 7 8; do commit_file f.txt "$i" "c$i"; done
    git bisect start --term-old=slow --term-new=broken >/dev/null 2>&1
    git bisect slow "$(git rev-list --max-parents=0 HEAD)" >/dev/null 2>&1
    git bisect broken HEAD >/dev/null 2>&1

    # The whole point: the words in force are not bad/good, so a hardcoded
    # list would offer terms git rejects and miss the ones it accepts.
    assert_offers "bisect " "broken"
    assert_offers "bisect " "slow"

    git bisect reset >/dev/null 2>&1
}

# --- notes: a --ref= target, and a message that is not a ref --------------

t_notes_completes_the_ref_value_not_a_word() {
    commit_file a.txt one "first"
    # Two refs, so the interesting case is the shared prefix rather than a
    # single insertion. A plain add makes notes/commits.
    git notes add -m "a note" >/dev/null 2>&1
    git notes --ref=reviews add -m "a review" >/dev/null 2>&1

    complete_line "notes --ref="
    assert_eq "$COMPLETION_LINE" "notes --ref=notes/" "common prefix of the note refs"
    assert_contains "$COMPLETION_WORDS" "notes/commits" "note refs offered after --ref="
    assert_contains "$COMPLETION_WORDS" "notes/reviews" "every note ref, not just the default"
    # And the value is completed as a value, not as a whole word.
    assert_completes_to "notes --ref=notes/r" "notes --ref=notes/reviews "
}

t_notes_will_not_complete_refs_into_a_message() {
    commit_file a.txt one "first"

    # -m takes text. Completing refs there would paste a sha into the note.
    assert_offers_nothing "notes add -m "
}

# --- revision-taking commands --------------------------------------------
#
# These offered the working directory where git wants a revision, which is
# the version of the mistake that reads as authoritative.

t_reset_offers_revisions_not_files() {
    commit_file a.txt one "first"
    git tag v1.2.3

    assert_offers "reset " "master"
    assert_offers "reset " "v1.2.3"
}

t_revision_commands_give_way_to_pathspecs_after_doubledash() {
    commit_file a.txt one "first"
    commit_file zz.txt z "second"

    # After -- git stops reading revisions, so a filename is right again.
    complete_line "reset -- "
    assert_offers "reset -- " "zz.txt"
}

t_clean_offers_only_what_git_would_remove() {
    commit_file tracked.txt one "first"
    printf 'loose\n' > loose.txt

    # One candidate, so it is inserted rather than listed -- assert on the
    # buffer, which is what a user sees.
    assert_completes_to "clean " "clean loose.txt "

    # Tracked, so git will not remove it.
    printf 'also loose\n' > other.txt
    complete_line "clean "
    assert_contains "$COMPLETION_WORDS" "loose.txt" "untracked files are candidates"
    [[ " $COMPLETION_WORDS " != *" tracked.txt "* ]] \
        || fail_assert "tracked files are not candidates: [$COMPLETION_WORDS]"
}

t_completion_offers_nothing_on_a_clean_tree() {
    commit_file tracked.txt one "first"

    # Nothing to remove, so nothing to offer -- rather than a guess.
    assert_offers_nothing "clean "
}
