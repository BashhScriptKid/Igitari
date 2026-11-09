#!/usr/bin/env -S bash -i

##==============================================================================
## Igitari — A kindly powerful Git companion
## Make Git approachable without sacrificing its power
##==============================================================================
## Version: 4.0.0
## Author: BashhScriptKid <contact@bashh.slmail.me>
## Copyright (C) 2025 BashhScriptKid
## SPDX-License-Identifier: AGPL-3.0-or-later
##
##   This program is free software: you can redistribute it and/or modify
##   it under the terms of the GNU Affero General Public License as published
##   by the Free Software Foundation, either version 3 of the License, or
##   (at your option) any later version.
##
##   This program is distributed in the hope that it will be useful,
##   but WITHOUT ANY WARRANTY; without even the implied warranty of
##   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
##   GNU Affero General Public License for more details.
##
##   You should have received a copy of the GNU Affero General Public License
##   along with this program.  If not, see <https://www.gnu.org/licenses/>.
##
##==============================================================================
##
## "#--" is for decompilation purposes; please do not remove those lines on master branch
##
##==============================================================================
## Internal Architecture — Three-Tier Model
##==============================================================================
##
##  STDLIB  — Generic portable utilities. No Git knowledge, no Igitari context.
##            Safe to copy into any Bash project as-is.
##
##  GITLIB  — Git-aware helpers. Not tied to Igitari's UI or config.
##            Useful to any Git-related Bash tool.
##
##  IGITARI — Application layer. Igitari-specific features only.
##
##==============================================================================

#--|CONSTANTS                                                        [IGITARI]
#------------------------------------------------------------------------------
# Configuration Constants
#------------------------------------------------------------------------------
# These are readonly, which makes a second source() of this file abort on the
# first reassignment -- every definition after the constants is skipped. That
# matters for the test harness, which resources the script per throwaway repo,
# and for anyone who sources it from their own RC. Guarding the block makes
# re-sourcing a no-op for the constants instead of a failure.
if [[ -z "${IGITARI_VERSION:-}" ]]; then
    readonly IGITARI_VERSION="4.0.0"

    readonly GITSH_RC_FILE="${HOME}/.gitshrc"

    readonly DEFAULT_GIT_PATH="/usr/bin/git"

    readonly LOCALPATH="${HOME}/.local/share/igitari/"
    readonly RC_FILE="${LOCALPATH}.igitari-rc"
    readonly MAIN_HISTORY_FILE="${LOCALPATH}.igitari_hist"

    readonly REMOTE_LINK="https://github.com/BashhScriptKid/Igitari"
fi

#--|CONFIG_VARS                                                      [IGITARI]
#------------------------------------------------------------------------------
# Global Variables
#------------------------------------------------------------------------------
# Configuration flags
DO_LOGGING=0
NO_SOURCING=0
INIT_CLEAR=0
PRINT_HEADER=1
NOT_GitDir=0
CHECK_UPDATES=1
NO_MARKERS=0

RUNTIME_COMMIT="$(cat "${LOCALPATH}ref.sha")"
RUNTIME_VERSION="${IGITARI_VERSION}-${RUNTIME_COMMIT:0:7}"

# Runtime variables
TARGET_PATH=""
GIT_PATH=${DEFAULT_GIT_PATH}
HISTFILE=""
LAST_DIR=""
ARG=""
REPO_IS_DIRTY=0
REPO_IS_DIRTY_AND_STAGED=0
REPO_STASH_DIRTY=0
GIT_REFLOG=""
GIT_REFLOG_COUNT=0
GIT_WATCHER_PID=""
SELF_REALPATH=$(realpath "$0")

#--|SANITY_CHECKS                                                    [IGITARI]
#------------------------------------------------------------------------------
# Initialization & Safety Checks
#------------------------------------------------------------------------------

# Verify Git installation
check_git_installation() {
    if ! command -v git >/dev/null 2>&1; then
        echo "Error: Git is not installed or not in PATH. (Hello? You're forgetting the essential here.)"
        exit 1
    fi
}

check_localpath() {
    if [ ! -d "${LOCALPATH}" ]; then
        echo "Error: Local path ${LOCALPATH} does not exist. Creating..."
        mkdir -p "${LOCALPATH}"
    fi
}

get_commithash_ref() {
    latest_remote_sha="$(git ls-remote ${REMOTE_LINK}.git refs/heads/mono-master | awk '{print $1}')"
    echo "$latest_remote_sha" >>"${LOCALPATH}ref.sha"
}

# Disable history expansion to prevent issues with ! characters
disable_history_expansion() {
    set +H
}

# Prevent script from being sourced
# Set IGITARI_TEST=1 to bypass this and to skip main() at the bottom, so a
# test script or a scratch shell can 'source igitari.sh' and call functions
# directly. That is the only reason the gate exists: it is not a mode.
#
# In the pre-monolith tree this guard read $inHead, which _head.sh set to 1
# before sourcing the modules so only the launcher escaped the warning. In a
# single file there is no launcher/module split to distinguish, so the test
# that belongs there is simply "was I sourced?", with no variable needed.
#
# That split was reverted on purpose and will not come back. DISASSEMBLER.sh
# could cut the monolith into SRC/ but no ASSEMBLER was ever written, and the
# upkeep of keeping 18 files coherent cost more than it saved. One file is the
# point: she is meant to be a script you can drop anywhere and run.
if [[ "${IGITARI_TEST:-0}" != "1" ]]; then
    # 'return' succeeds only when sourced. In that case refuse to continue:
    # the script is meant to be run, not imported.
    (return 0 2>/dev/null) && {
        echo "PLEASE Don't source this script — run it directly, or set IGITARI_TEST=1"
        return 1
    }
fi

#--|LOGGER                                                           [STDLIB]
#------------------------------------------------------------------------------
# Logging System
#------------------------------------------------------------------------------

# Enhanced logging function with formatting options
# Usage: log [flags] "message"
# Flags: n (no newline), p (no prefix)
log() {
    local prefix
    local skip_newline=false
    local skip_prefix=false

    prefix="Igitari_debug: [$(date +%T)] "

    # Parse flags
    while [[ $# -gt 1 ]]; do
        case "$1" in
        n) skip_newline=true ;;
        p) skip_prefix=true ;;
        *) : ;; # Ignore unknown flags
        esac
        shift
    done

    # Only log if verbose mode is enabled
    [[ ${DO_LOGGING} -ne 1 ]] && return

    # Format output
    [[ ${skip_prefix} == true ]] && prefix=""

    if [[ ${skip_newline} == true ]]; then
        echo -n "${prefix}${1}"
    else
        echo "${prefix}${1}"
    fi
}

#--|DATA_SHOWOFF                                                     [IGITARI]
#------------------------------------------------------------------------------
# Help & Version Display
#------------------------------------------------------------------------------
# Display help information
show_help() {
    cat <<EOF
Igitari version ${RUNTIME_VERSION}

The lightweight and portable Git shell environment.
Supports DOS/GNU/Unix argument formats.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --help, -h, /?          Show this help and exit
    --version, -v           Show version information and exit
    --path, -p [DIR]        Start shell in specified directory
    --verbose, -V           Enable debug logging
    --skip-sourcing         Skip sourcing tab completion files
    --no-header             Suppress startup header (internal use)

EXAMPLES:
    $0 --path /home/user/project    # Start in specific directory
    $0 --verbose                    # Enable debug output
    $0 /?                           # Show help
EOF
}

# Display version and about information
show_version() {
    cat <<EOF
Igitari version ${RUNTIME_VERSION}

About:
    A lightweight Git companion
    designed to reduce friction and repetitive commands.

    It keeps Git approachable
    while staying close to how Git actually works.

    Portable, nearly dependency-free,
    and focused on preventing common foot-guns.

    Repository: https://github.com/BashhScriptKid/igitari

    License: AGPL-3.0-or-later

    Written in Bash by BashhScriptKid
EOF
    #'
}

# ---------------------------------------------------------------------------
# Help text registry
# ---------------------------------------------------------------------------
# One entry per documented command. Key = command name, value = the page.
# Collapse/expand freely in the editor; order here is irrelevant.
#
# Multi-line values use $'...' with \n escapes so every page is one array
# element, which keeps the table readable and the diffs small.
#
# Add a command by dropping in one line:
#   [reword]=$'USAGE:\n    reword "msg" [commit]\n...'
#
# Commands not listed here fall through to `git help <cmd>` at the call site.

declare -A HELP_TEXT=(
    [squash]=$(cat <<'EOF'
USAGE:
    squash [--yes] <amount | commit1..commit2> [message]

    --yes, -y         Skip the confirmation. May sit anywhere.

SQUASH WHAT
    amount            The last <amount> commits. At least 2, please. Squashing
                      one commit is just lying to yourself.
    commit1..commit2  Those commits. BOTH ends are folded in, so
                      'c2..c3' squashes c2 and c3, not just c3.

MESSAGE
    Optional. Leave it out and git opens your editor. Pass it and the
    editor stays shut:

        squash 3 "fix: tidy up the last three attempts"

EXAMPLES
    squash 3                      Fold the last 3 commits
    squash HEAD~4..HEAD           Same thing, spelled out
    squash abc1234..def5678       Fold that range (both included)
    squash 2 "feat: one clean commit"
    squash 3 "feat: one commit" --yes   Same, without stopping to ask

WHEN TO SAY --yes
    Scripting, or when you have already run it once and read the list. The
    command prints what it is about to fold together before asking, so
    answering a prompt you have not read is the only way --yes loses you
    anything -- and the confirmation is deliberately the last thing before
    the rewrite starts.

WHAT IT DOES
    Puts HEAD just below the range, then folds everything back in as one
    commit. The tree ends up identical to where you started, so if you get
    the message right, nothing was actually lost. Neat, isn't it?

WATCH OUT
    Uncommitted changes get stashed and re-applied for you. If a conflict
    shows up on the way back, your stash is still there.

    The range has to END at HEAD. Squashing a chunk buried under your
    current position is a job for 'git rebase -i', and I'll happily tell
    you the exact command instead of pretending I can do it.

    Nothing at all moves until you say 'y'. ^^
EOF
    )
    [untrack]=$(cat <<'EOF'
USAGE:
    untrack <path1> <path2> ...

WHAT IT DOES
    Stops git from tracking the paths, without deleting anything. The
    files stay on your disk, exactly where they are, with their contents
    untouched. Only git's index changes.

    Underneath it is 'git rm --cached'. I use it after checking what git
    actually thinks of each path, because '--cached' on its own will
    happily "untrack" something that was never tracked and claim success.

WHAT IT TELLS YOU
    Tracked now          Untracked, and the removal is staged.
    Removal pending      Already untracked, waiting to be committed.
    Removed earlier      Git hasn't tracked it since an old commit.
    Never tracked        Nothing to untrack. Git never met this file.

EXAMPLES
    untrack .env
    untrack local/db.sqlite node_modules

AFTER IT RUNS
    From that point on, to the git database, it is as if the file got
    deleted. It stays local; it is just invisible to git now.

    The removal is staged, not committed. 'status' will show it as a
    deletion until you commit it. If you commit by accident, the file is
    still on your disk, so nothing is lost.

    'retrack' puts it back.
EOF
    )
    [retrack]=$(cat <<'EOF'
USAGE:
    retrack <path1> <path2> ...

WHAT IT DOES
    Puts untracked paths back under git's eye. Underneath it is 'git add'.

    It is not just 'add' though: what it says changes depending on how git
    currently regards the path, because "put it back" means four different
    things depending on where you are. It also works on paths that .gitignore
    is still listing, which plain 'git add' refuses to do.

THE FOUR STATES
    Already tracked     Nothing to do. It already is.
    Removal pending     Cancels the uncommitted untrack. History untouched,
                        so the file is back to exactly how it was.
    Removed earlier     Git recorded the deletion in a commit. Adding it
                        back is a NEW commit, not a resurrection. The old
                        content is only in history, not on disk.
    Never tracked       Git never met this file. This is a plain add, and
                        I'll say so rather than pretend it's a retrack.

EXAMPLES
    retrack .env
    retrack local/db.sqlite

WATCH OUT
    In the "removed earlier" case, 'retrack' takes whatever is in the file
    right now. It does not restore the committed version. If the file on
    disk changed while it was untracked, that is what gets tracked.

    Want the old contents back instead? That's 'git checkout HEAD -- <path>',
    which is a different job with a different danger: it overwrites the
    file on disk.
EOF
    )
    [discard]=$(cat <<'EOF'
USAGE:
    discard [--yes] <file1> <file2> ...
    discard [--yes] all [tracked | untracked | staged | unstaged]

    --yes, -y       Skip the confirmation prompt. Bulk mode and named
                    files alike.

TWO WAYS
    With files      Throw away the changes to those files, by name.
    With 'all'      Throw away changes in bulk, optionally one category.

BY NAME
    Tracked file    'git checkout -- <file>'. Your edit is gone, file stays.
    Untracked file  Removed from disk. The file itself is gone. All of it.
    Ignored file    Not touched. .gitignore is a standing instruction to
                    leave it be, and 'git clean' respects that too unless you
                    pass -x. Naming an ignored file gets you a note, not a
                    deletion. If you really want it gone, rm it yourself.
    Directory       I walk into it and handle every file in there by the
                    rules above. Tracked files are restored to their
                    committed state, untracked ones are removed, ignored ones
                    are left alone. A directory
                    never gets deleted as a unit, and nothing tracked gets
                    un-tracked. Discarding throws away changes, it doesn't
                    change what git knows about. That's a different verb.

                    Directories left empty afterwards are pruned. A directory
                    still holding a restored file stays put.

BY CATEGORY
    all                 Everything dirty. 'reset --hard' + 'clean -fd'.
    all tracked         Modified tracked files. 'reset --hard'.
    all untracked       Untracked files. 'clean -fd'. This deletes them.
    all staged          Unstage everything, keep the edits in your tree.
    all unstaged        Drop working-tree edits, keep what is staged.

EXAMPLES
    discard notes.txt src/old.c
    discard all unstaged
    discard all

WATCH OUT
    There is no undo here. 'git checkout --' overwrites, 'clean -fd'
    deletes, 'reset --hard' nukes. If it is work you might miss, commit it
    or stash it first.

    I ask before every discard, named files included. A typo in a filename
    looks exactly like meaning it, and deleting doesn't offer a second
    opinion. Say --yes when you already know what you're doing.

    Paths that don't exist are reported and skipped; the rest still go
    through. If nothing was found at all, the exit code is 1.
EOF
    )
    [reword]=$(cat <<'EOF'
USAGE:
    reword "new message" [commit]

WHAT IT DOES
    No commit given    Amends HEAD. Cheap, no rebase, no drama.
    Commit given       Runs 'rebase -i <commit>^' with a scripted editor
                       that swaps that line to 'reword' and types your
                       message in. Real history rewrite.

EXAMPLES
    reword "fix: typo I noticed right after committing"
    reword "chore: actually describe what this does" abc1234

WATCH OUT
    Rewording anything but HEAD REWRITES EVERY COMMIT AFTER IT. New SHAs,
    all of them. If those are pushed, you're diverged and everyone pulling
    your branch gets to have a bad day.

    I warn you and ask before doing the rebase. Say no and nothing moves.

    Conflicts during the rebase leave you mid-rebase, not reverted. Finish
    with 'rebase --continue' or back out with 'rebase --abort'.

    Message with spaces needs quotes >.> Otherwise I get to guess which word
    is which, and I am not good at guessing.
EOF
    )
    [transplant]=$(cat <<'EOF'
USAGE:
    transplant <commit> <target-branch> [--force]
    transplant <n> <target-branch> [--force]

WHAT IT DOES
    Cherry-picks commits from your current branch onto <target-branch>,
    then takes them OFF the current branch by resetting it below them.
    They move house. No copies left behind.

WHAT YOU CAN NAME
    commit       One commit, by hash. Any commit, not just HEAD.
    n            The last n commits, as a run.

EXAMPLES
    transplant abc1234 feature        Move one commit to 'feature'
    transplant 3 feature              Move the last 3 commits there
    transplant 1 hotfix               Rescue a commit onto a hotfix branch

WHAT HAPPENS, IN ORDER
    1. Shows you exactly which commits are moving, and asks.
    2. Stashes uncommitted changes if you have any.
    3. Checks out the target branch and cherry-picks onto it.
    4. Checks back out, resets your branch '--hard' below the moved commits.
    5. Restores your stash.

WATCH OUT
    Step 4 is 'reset --hard'. If the cherry-pick half-worked and you had
    other uncommitted changes that slipped past the stash, they are gone.
    Commit or stash before you start.

    A conflict in step 3 stops everything mid-cherry-pick and leaves you on
    the TARGET branch. It prints the two commands to continue or abort.
    Your current branch has NOT been reset at that point, so nothing is lost.

    Moving commits that are already pushed rewrites published history.
    I check for that: if anything in the move exists upstream, I stop and
    list exactly which commits. Refusing is the default, because the people
    who already pulled those aren't here to object on their own behalf.

    --force skips that check. It does NOT make the push safe, and it skips
    nothing else. Two separate things, both still on you.
EOF
    )
    [decimate]=$(cat <<'EOF'
USAGE:
    decimate <file> [--all]

WHAT IT DOES
    Rewrites history so <file> looks like it was never committed. Not deleted
    -- never added. Every commit that touched it is rebuilt without it.

    This is for the file that should never have been in the repo in the first
    place: a leaked secret, a huge binary, a build artifact you committed by
    accident. 'git rm' handles "I don't want this any more". This handles
    "git should never have known about it".

    Without --all only the current branch is rewritten. With --all, every
    branch gets the same treatment.

HOW
    Uses git-filter-repo when it finds it. Otherwise falls back to a
    fast-export | awk | fast-import pipeline that strips the file's M and D
    lines and stitches the parent pointers exactly, so the rest of history
    stays byte-identical.

EXAMPLES
    decimate secrets.env                   Current branch, just that one
    decimate build/output.js --all         Every branch
    help decimate                          You are here

WATCH OUT
    This rewrites history. Every commit hash from the first affected commit
    onward changes. Anyone who has already cloned the repository keeps the
    old history and the file inside it. Rewriting does not reach them.
    Rotate the secret, invalidate the artifact. Do that first.

    If the file was pushed, the pushed copy stays on the remote until
    someone force-pushes over it, and even then it may survive in the
    remote's own reflog. This tool cannot guarantee deletion upstream.

    Uncommitted changes are stashed and restored. Conflicts on the way back
    leave the stash in place.

    Afterwards your reflog is expired and aggressive gc runs. That is the
    point, and it also means an undo does not exist. There is no --force
    here, and no flag that makes it safer. Read the prompt, then answer.
EOF
    )
    [movehead]=$(cat <<'EOF'
USAGE:
    movehead forward|backward [steps]

WHAT IT DOES
    Detaches HEAD and parks it a number of commits away from where it is now.
    No branch gets updated, so nothing you can lose stays lost.

    The working tree does follow you, because this is a checkout: files that
    only exist in the commits you walked past will vanish from disk until you
    walk forward again. Commit or stash first if the tree matters.

    backward <steps>   Walk back along the current history
    forward <steps>    Walk forward along the branch you left. Only works
                       while detached, because moving forward on behalf of a
                       branch is just "stay on the branch".

    'backward N' then 'forward N' returns you to where you started.

    Forward steps are counted in commits, up the first-parent chain of the
    branch that contains HEAD. Asking for more than that branch holds is
    refused rather than guessed at -- you get the exact count it could move
    and nothing moves.

EXAMPLES
    movehead backward 3           Stand three commits behind where I am
    movehead backward 1           Just the previous commit
    movehead forward 2            Two commits forward, up the branch I left
    movehead forward 1            Step forward one

WHY DETACHED
    Because moving on behalf of a branch would rewrite it. You are peeking,
    so HEAD detaches and the branch stays exactly where it was. If you step
    forward far enough to land on a branch tip, you get reattached to it.

WATCH OUT
    Detached HEAD is a place commits go to be lost. If you make a commit
    while detached, nothing points at it. Make a branch before committing, or
    the next checkout will abandon your work silently.

    Steps must be a plain number. No negative numbers, no HEAD~3 arithmetic,
    pick a direction and say how far. Zero is refused: it is nowhere, and
    reporting success for it would be a lie.

    If no branch contains HEAD at all -- you are detached on something no
    branch points at -- forward falls back to the reflog, which counts entries
    rather than commits. That is a real difference: the reflog remembers every
    checkout and reset, not just history. It is the only lead left in that
    case, but the landing place may not be 'steps' commits along any branch.
EOF
    )
    [undo]=$(cat <<'EOF'
USAGE:
    undo [steps]

WHAT IT DOES
    Winds HEAD back by following the reflog, then hard-resets to where it
    lands. Default one step. This is the "that was a mistake, take it back"
    button for the last few things that moved HEAD -- commits, merges,
    rebases, resets, checkouts.

EXAMPLES
    undo              Undo the last thing
    undo 3            Undo the last three things

WATCH OUT
    'git reset --hard' throws away uncommitted work. Anything you have not
    committed is gone, and this does not ask.

    It moves HEAD only. Untracked files are untouched. A merge that brought
    in other branches is undone as far as HEAD is concerned, but the reflog
    of those branches is not consulted.

    Going back too far and then trying to come forward again is what 'redo'
    is for. The reflog is what makes either possible, so do not expire it if
    you expect to change your mind.
EOF
    )
    [redo]=$(cat <<'EOF'
USAGE:
    redo

WHAT IT DOES
    The other half of 'undo'. Finds how far back HEAD was parked and steps
    forward one, by hard-resetting to that reflog entry.

EXAMPLES
    undo 2            Regret a bit too much
    redo              Take back one undo

WATCH OUT
    It checks that the last thing you did was a reset. If it wasn't, you get
    'Nothing to redo' rather than a silent jump backwards, so commit, merge
    and checkout in between all cancel the redo. That is deliberate.

    It is one step only, and it always targets the entry just before the
    reset -- the place you came from. Running redo again after a redo is a
    ping-pong between the two positions. If that is not what you want, make a
    branch and stop bouncing.

    Like 'undo', the reset is hard. Uncommitted work does not survive.
EOF
    )
    [openweb]=$(cat <<'EOF'
USAGE:
    openweb [remote] [issues|discussions|releases|pr|mr|prs|pr create|compare|wiki|settings] [number]

WHAT IT DOES
    Opens a remote's web page in your browser, or jumps straight to one of
    its usual corners. Saves you the copy-paste dance when you want to read
    an issue rather than grep a log.

EXAMPLES
    openweb origin                 The repo's front page
    openweb origin issues          The issue tracker
    openweb origin issues 553      One issue
    openweb upstream discussion 9553   One discussion
    openweb origin prs             Pull requests
    openweb origin prs 42          One pull request
    openweb origin releases v2.0   One release
    openweb origin pr create       Start a new pull request
    openweb origin compare         Same page, if you just want the diff
    openweb upstream wiki          Wiki

NUMBERS ARE THE LAST WORD
    Where a page takes one, the trailing word is the number, so no new syntax
    is needed: the page word already says what the number refers to.

    'openweb origin prs 42' is the page for PR 42. Open it this way rather
    than reaching for a forge command -- this needs no client installed and
    no authentication, because it is only a URL.

STARTING A PULL REQUEST
    'pr create' and 'compare' open the same page -- the compare view is where
    the new-pull form lives. Both spellings exist because people reach for
    different ones, and the difference is not worth making you guess.

WATCH OUT
    Needs a remote with a URL. A remote that is just a local path has nothing
    to open, and you get told so rather than a browser launching at a folder.

    Whatever opens it is whatever your system uses -- xdg-open and friends.
    With no browser configured it can fail quietly, which is your desktop's
    problem rather than this command's.
EOF
    )
    [fzf]=$(cat <<'EOF'
USAGE:
    fzf <commits|tags|reflogs|staged|unstaged|tracked|untracked|stashes|dangling|prs|issues|discussions> [return]

WHAT IT DOES
    Hands a list of things to fzf so you can pick one, then prints what you
    picked. Read-only: it picks, it does not act. Pipe the result into
    whatever needs it.

RETURN TYPES
    commits, reflogs   sha | message | diffs
    tags               sha | name
    stashes            ref | diff | name
    dangling           sha | type | content | message
    prs, issues,
    discussions        number | ref

    staged, unstaged, tracked and untracked take no return type -- they hand
    back paths.

EXAMPLES
    fzf commits sha                Pick a commit, get its hash
    fzf commits message            Pick a commit, get the message
    fzf stashes diff               Read around before you pop
    fzf dangling                   Hunt down something you thought was lost
    fzf prs                        Pick a pull request, get its number
    fzf prs ref                    Pick one, get 'pr:42'

FORGE SOURCES
    prs, issues and discussions come from the remote, not from your clone,
    and they are only offered when a forge client is installed. They print
    a bare number by default so the number can be handed to 'openweb':

        openweb origin prs $(fzf prs)
        openweb origin issues $(fzf issues number)

    'ref' prints the colon form the forge namespace wants:

        forge checkout $(fzf prs ref)

WATCH OUT
    fzf has to be installed. If it is not, you get told rather than an empty
    list, and the rest of Igitari keeps working.

    Forge sources may be empty because the repository has no forge, no client
    installed, or no such objects open. Each says which, rather than showing
    an empty picker.

    It prints a string. It does not remember what you picked, and it has no
    idea what you mean to do with it. This is a selector, not a mode.

    One selection at a time, so it always emits a single line.

COMBINING IT WITH OTHER COMMANDS
    Command lines are split the way a shell would, so $(...) runs and its
    output becomes an argument:

        reword $(fzf commits sha) "fix: tidy the parser"
        untrack $(fzf tracked)
        reword $(fzf commits message) "squashed"

    Anything inside $(...) is read the same way a normal command line is,
    which means it can be a git subcommand without the word 'git':

        squash $(rev-parse --short HEAD)

    Quotes work too, and $(...) inside double quotes stays part of the same
    word. Single quotes are literal, so '$(...)' is just text.
EOF
    )
    [state]=$(cat <<'EOF'
USAGE:
    state

WHAT IT DOES
    Tells you where you are, in four lines or fewer. Branch, distance from
    upstream, anything half-finished, and how much is uncommitted.

    Read-only. It changes nothing, asks nothing, and is safe in a pipe.

EXAMPLES
    state                         Where am I?
    state | grep operation        Is something unfinished?

WHAT IT REPORTS
    branch      the branch, or the detached commit
    upstream    ahead and behind counts, but only when an upstream exists
    operation   merge, rebase, am, cherry-pick, revert or bisect in progress,
                with a conflict count when there is one. Also catches the
                quiet case: a sequencer still holding commits you have not
                applied yet, which looks like an idle repo otherwise.
    work        staged, modified, untracked and stashed counts

WHY NOT JUST 'status'
    'status' is git's own report: thorough, verbose, meant for reading. This
    is the glance. Same facts, one line each, fixed order, so you can pipe it.

    The 'operation' line is the one that matters. A half-finished merge
    changes what every other command means, and 'status' buries it in a
    header paragraph.
EOF
    )
    [guess]=$(cat <<'EOF'
USAGE:
    guess prior          The branch you were on before this one
    guess merge-base     Where the merge in progress started from
    guess rebase-base    The commit you are rebasing onto
    guess root           The top of the working tree
    guess pr             This branch's pull request, as pr:<32>

WHAT IT IS FOR
    These are the values you keep digging out by hand mid-operation: which
    branch did I just leave, what am I rebasing onto, where does this merge
    fork. gitsh gives you them as variables ($_prior, $_merge_base); Igitari
    has commands rather than variables, so this prints one and stops.

    It prints a value and nothing else, which is what makes it composable --
    the output is the answer, with no label or decoration to strip:

        checkout $(guess prior)
        log $(guess rebase-base)..HEAD
        cd $(guess root)

EXAMPLES
    guess prior                  after switching, get the old branch back
    guess merge-base             show me where this merge started
    guess rebase-base            what am I rebasing onto?
    guess root                   where is this repo, from anywhere inside it

NOTHING IS PRINTED WHEN IT CANNOT ANSWER
    A failure goes to stderr with a non-zero status, and stdout stays empty.
    That is deliberate: '$(guess prior)' with an empty line in it would become
    the argument '' and quietly do something surprising. Silence plus an error
    is something a script can check; a blank value is not.

WHY NOT VARIABLES
    A variable layer would be a second thing to learn, and it only works
    inside Igitari's own input. A command prints to stdout, so it also works
    inside $(...) in a script, in a pipeline, and anywhere else a value is
    expected -- including 'git checkout $(guess prior)' typed by hand.

WATCH OUT
    'guess prior' reads git's reflog for this working copy, so it knows only
    about switches made here. If the last checkout was of a commit rather than
    a branch, it says so instead of handing you a detached hash to check out.

    'guess pr' is the one that asks the remote, so it needs a forge client
    installed and a branch that actually has a pull request. With none, it
    prints nothing and says so on stderr, like the others.
EOF
    )

    [session]=$(cat <<'EOF'
USAGE:
    config session <key> <value>     Override a setting for this session
    config session <key>             Read back an override
    config session                   List every override
    config session --get <key>       Read a value (override, else git's own)
    config session --unset <key>     Forget one override
    config session --clear           Forget them all

WHAT IT IS
    'git config' has --local, --global and --system. Session is the fourth
    scope, and the only one that leaves nothing behind: what you set applies
    until you exit Igitari, then it is gone. Nothing is written to disk, so
    there is no cleanup to remember and no chance of leaking an identity into
    a shared repo.

    It is spelled as a scope rather than as its own command because that is
    what it is. You already know which scope you want; this is the one git
    does not have.

EXAMPLES
    config session user.email me@example.com    Commit as somebody else
    config session user.email                   What am I using now?
    config session                              Everything I overrode
    config session --unset user.email           Back to my real identity
    config session --clear                      Forget all of it

PRECEDENCE
    Session wins over local, global and system, matching 'git -c'. It does
    NOT override a -c you pass to git yourself -- if you type
    'git -c user.email=x commit', git's own -c still wins for that command.
    You asked for that one explicitly and once; a session is a standing
    preference, not a command-line override.

    'config session' lists what each override displaced, so you can see the
    value you would get back without unsetting it first.

WATCH OUT
    It survives 'state' and every other command for the whole session. If a
    commit comes out with an unexpected author an hour later, this is where
    to look -- 'config session' answers in one line.

    Overrides are held in the environment of each git invocation, so they
    also apply to aliases, hooks and anything else the command runs. That is
    usually what you want; it does mean a hook that reads user.email sees the
    override rather than your real config.
EOF
    )
    [conflict]=$(cat <<'EOF'
USAGE:
    conflict                          List the conflicted paths
    conflict show <side> [file]       Print one side
    conflict throw <side> [file]      Discard one side, keep the other

SIDES
    ours      Your side (index stage 2)
    theirs    The side coming in (stage 3)
    both      Neither side: the common ancestor both started from (stage 1)

    'both' is not a third side to pick, it is the refusal to pick one. It
    restores the file as your ancestor had it, discarding both versions.

throw NAMES THE LOSER
    'conflict throw theirs' keeps yours. You name the side that dies, not the
    one that survives -- which is how you are actually thinking mid-conflict:
    the conflict markers are the thing you want gone.

    It is also the only spelling that survives git's vocabulary. During a
    rebase 'ours' means the upstream, not you, and 'throw ours' still reads
    correctly as "discard that side" because you are naming what dies rather
    than translating what you want.

EXAMPLES
    conflict                        What is actually unmerged?
    conflict show ours src/app.sh   What does my side look like?
    conflict show theirs            Every conflicted path, their versions
    conflict throw theirs app.sh    Keep mine, drop theirs
    conflict throw ours             Mine goes, theirs stays -- everywhere
    conflict throw both app.sh      Back to the ancestor, neither side

WHAT 'throw' DOES
    Writes the surviving side into the working tree and stages it. The staging
    is not optional politeness -- git still calls the path unmerged until it
    is added, so a bare checkout would leave you looking resolved and not
    actually resolved.

    It asks first. Taking a side is silent data loss for the other one, and a
    loop that overwrites six files without asking is not something to hand
    someone by accident.

WATCH OUT
    'conflict throw both' is not a resolution. It restores the file as your
    common ancestor had it, discarding both sides. Useful when the right
    answer is "start this file over", dangerous when you meant to pick a side.
    It says so before doing it.

    'ours' and 'theirs' mean what git means by them, which during a rebase is
    not what you would guess: 'ours' is the upstream you are rebasing onto,
    and 'theirs' is your own commits. 'throw' names the loser so the sentence
    stays true either way, but check 'state' if you want to be sure which
    operation you are in.
EOF
    )
    [forge]=$(cat <<'EOF'
USAGE:
    forge <verb> [<object>] [client flags...]

    forge checkout pr:32                     Take a PR into the working tree
    forge close    issue:88212 --reason "not planned"
    forge merge    pr:32 --squash --delete-branch
    forge review   pr:32 --approve
    forge diff     pr:32                     Remote-only: no local equivalent
    forge checks   pr:32                     CI status
    forge create   issue                     Start one (opens the client)

OBJECTS
    pr:32        A pull request (GitHub)
    mr:32        A merge request (GitLab -- the same object, their word)
    issue:88212  An issue
    release:v2.0 A release; 'checkout' takes its tag

WHY THE COLON
    Inside this namespace the object has to say what it is, because the verb
    is handed one token where git would expect a ref. Outside forge nothing
    needs it: viewing is 'openweb origin issues 553', and picking is
    'fzf issues'.

FLAGS ARE THE CLIENT'S, NOT MINE
    I translate the object and nothing else. Every other argument goes
    straight to gh or glab, so their own manuals stay correct:

        forge close issue:812 --comment "fixed in 1.4"

    A wrong flag fails with the client's own error message, which is how you
    learn the client rather than a private dialect of it. The one exception
    is -y/--yes, which is mine and never reaches the provider.

SAME IDEA, DIFFERENT WORD
    The two clients do not agree on verbs, only on objects. These are translated
    to whichever word your forge uses, so the verb above still works on both:

        gh                          glab
        forge comment  pr:5         forge comment  mr:5   (glab: note)
        forge edit     pr:5         forge edit     mr:5   (glab: update)
        forge review   pr:5         forge review   mr:5   (glab: approve)
        forge ready    pr:5         forge ready    mr:5   (glab: update --ready)

        forge checks   pr:5         forge checks   mr:5   (glab: ci status
                                                           --branch <source>)

    'checks' is a translation rather than a refusal because it can be done
    honestly: a merge request is not a pipeline in GitLab, but its source
    branch is, so the branch is resolved first and asked about. An MR from a
    fork keeps its pipeline in the fork's project, which glab cannot be told
    without a token -- you get glab's own 404 plus a line saying why.

    Refused on GitLab, because there is no honest equivalent: lock, revert.

WHAT ASKS FIRST
    checkout, merge, close, revert and delete confirm before doing anything.
    Add -y to skip -- scripted use is a real use.

WHICH FORGE
    Detected from origin's host. A self-hosted one cannot be guessed, so say
    it once: 'config session igitari.forge glab'. Refuses rather than guessing
    wrongly, since the wrong client produces a confusing error.

WATCH OUT
    Needs the matching client installed (gh or glab) and authenticated. With
    neither, this command says so and the rest of Igitari is unaffected --
    everything above is optional.

    The object is checked against the verb before any call: 'forge merge
    issue:812' is refused, rather than quietly becoming a provider command
    about the wrong thing.
EOF
    )
)

# Print the help page for one Igitari command.
# Returns 1 when there is no page, so the caller can fall back to `git help`.
show_command_help() {
    local cmd="$1"
    local page="${HELP_TEXT[$cmd]:-}"

    if [[ -z "$page" ]]; then
        return 1
    fi

    printf '%s\n' "$page"
}

#--|CONFIRM                                                          [STDLIB]
#------------------------------------------------------------------------------
# Confirmation Prompt
#------------------------------------------------------------------------------
# Ask a yes/no question and wait for a single key.
# Always reads from /dev/tty: prompts must never consume the command stream,
# otherwise a piped 'exit' answers the question for you.
#
# Usage: __igitari_confirm "question" [silent]
#   silent — pass -s to read, so the key you press isn't echoed back.
#
# Returns 0 for yes, 1 for no, 2 when no terminal was available to ask.
# Nothing is printed for "no" beyond the newline, and nothing is printed for
# 2 at all — the caller owns the wording, because every command says something
# different when you back out ("Squashing aborted", "Transplant aborted", ...).
#
# Only y and n count. Anything else is ignored and the prompt repeats.
#
# EXAMPLE — the exit status is the answer, so this is the normal shape:
#
#     __igitari_confirm "Proceed?" silent || {
#         echo "Squashing aborted! No changes are made."
#         return 1
#     }
#     # ...only reached on y
#
# EXAMPLE — when yes and no do different work rather than continue/abort:
#
#     if __igitari_confirm "Are you sure?"; then
#         do_the_thing
#     else
#         echo "Discard operation aborted."
#         return 1
#     fi
#
# Note the "||" covers both 1 and 2 on purpose: "you said no" and "nobody
# could be asked" are the same answer as far as a destructive command is
# concerned. Never treat 2 as consent.
__igitari_confirm() {
    local question="$1"
    local -a read_flags=(-n1 -r)
    local answer=''
    local tries=0

    [[ "${2:-}" == "silent" ]] && read_flags+=(-s)

    # No controlling terminal means nobody can answer. Refusing up front beats
    # opening /dev/tty and looping on a prompt no keypress will ever reach.
    if [[ ! -e /dev/tty ]] || ! { : </dev/tty; } 2>/dev/null; then
        return 2
    fi

    while [[ "$answer" != "y" && "$answer" != "n" ]]; do
        # -n1 returns non-zero on a newline as well as on EOF, so a blank
        # Enter must not be mistaken for "no terminal".
        if ! read "${read_flags[@]}" -p "$question (y/n) " answer 2>/dev/null </dev/tty; then
            ((++tries >= 3)) && return 2
            continue
        fi
        tries=0
    done
    echo

    [[ "$answer" == "y" ]]
}

#--|ARG_PROCESSOR                                                     [STDLIB]
#------------------------------------------------------------------------------
# Argument Processing
#------------------------------------------------------------------------------

# Process command line arguments
process_arguments() {

    # NOTE:    When using this function, order matters!
    #          Make sure to prioritise the right argument, especially if your argument is prone to collisions.
    #          Use 'a' in the second argument to allow blank arguments, otherwise it will be treated as an error.
    #
    # RETURNS: 0 if input matches any generated variant, 1 otherwise.
    #
    # USAGE:   validate_arg "$1" [a] "canonical1" "canonical2" ...
    #
    # EXAMPLE: validate_arg "$1" "help" "h"        # --help, -h, /HELP, /H
    #          validate_arg "$1" a "path" "dir"     # allows blank, --path, -p, /PATH, /P, --dir, -d, /DIR, /D
    validate_arg() {
        local input="$1"
        shift
        # The optional 'a' marker may or may not be there. Only shift past it
        # when it is, otherwise the first canonical name gets eaten and
        # long forms (--help, /HELP, help) silently stop matching.
        local allowBlankArg=1
        if [[ "${1:-}" == 'a' ]]; then
            allowBlankArg=0
            shift
        fi
        local -a canonical=("$@") # all canonical names passed by developer

        if [[ -z "$input" && $allowBlankArg -eq 1 ]] || [[ ${#canonical[@]} -eq 0 ]]; then
            echo "Error: Argument cannot be empty"
            return 1
        fi

        local -a variants=()
        for name in "${canonical[@]}"; do
            variants+=("--${name}")      # UNIX long
            variants+=("-${name:0:1}")   # UNIX short
            variants+=("/${name^^}")     # DOS long
            variants+=("/${name^^:0:1}") # DOS short
            variants+=("${name}")        # bare word
        done

        for variant in "${variants[@]}"; do
            [[ "$input" == "$variant" ]] && return 0
        done
        return 1
    }

    while [[ $# -gt 0 ]]; do
        if validate_arg "$1" a "help" "h" "?"; then
            show_help
            exit 0
        elif validate_arg "$1" a "version" "ver"; then
            show_version
            exit 0
        elif validate_arg "$1" a "path" "p"; then
            shift
            if [[ -z "$1" ]]; then
                echo "Error: Please put a path after --path, like this: --path /path/to/directory/"
                exit 1
            elif [[ -f "$1" ]]; then
                echo "Error: Hey! You're pointing to a file, not a directory!"
                exit 1
            else
                TARGET_PATH="$1"
            fi
        elif validate_arg "$1" a "verbose"; then
            # -v is taken by version, so short form intentionally collides — version wins
            DO_LOGGING=1
            echo "Verbose logging enabled. Debugging time! Or not."
        elif validate_arg "$1" a "skip-sourcing"; then
            echo "No tab completion? Sure, I guess :/"
            NO_SOURCING=1
        elif [[ "$1" == "--no-header" ]]; then
            log "Restarting shell without header"
            PRINT_HEADER=0
        else
            echo "Warning: I don't know what $1 is so I'll just ignore it."
        fi
        shift
    done
}

#--|DIR_CHANGE                                                        [STDLIB]
#------------------------------------------------------------------------------
# Directory Management
#------------------------------------------------------------------------------

# Change to user-specified directory if provided
setup_working_directory() {
    if [[ -n "${TARGET_PATH}" ]]; then
        LAST_DIR=$(pwd)
        if ! cd "${TARGET_PATH}/"; then
            echo "Error: I can't change the directory to ${TARGET_PATH} ; Are you sure this is accessible? (Does not exist or insufficient permissions)"
            exit 1
        fi
        # Set trap to restore original directory on exit
        trap 'cd "$LAST_DIR"' EXIT SIGTERM
        log "Changed working directory to: ${TARGET_PATH}"
    fi
}

# After git fails, offer the fix git already printed.
#
# This exists for one annoyance: git knows the answer and then makes you
# retype it. "git push --set-upstream origin master" is a long incantation to
# copy out of a paragraph, and the flag is not the one you would guess.
#
# So this never *constructs* a command. It lifts the line out of git's own
# stderr and offers it verbatim. That matters: a command we built could be
# subtly wrong (wrong remote, wrong branch) and would teach a bad habit. One
# git wrote cannot be.
#
# Only runs on failure, and only when git printed a fix. Nothing that
# succeeded gets a word, and no failure git stayed quiet about gets guessed
# at -- that is how a helper becomes a nag.
#
# Usage: __igitari_offer_fix <stderr-file>
__igitari_offer_fix() {
    local errfile="$1"
    [[ -s "$errfile" ]] || return 1

    # A suggestion line: indented, starts with 'git', then a subcommand.
    # Deliberately strict -- we would rather miss one than offer nonsense.
    #
    # Lines containing < or > are templates, not commands: 'git pull <remote>
    # <branch>' and 'git branch --set-upstream-to=origin/<branch>' are both
    # printed by a plain 'pull' with no upstream, and running either would
    # fail at the angle brackets. Offering one is worse than staying quiet,
    # so it has to be runnable as printed or it does not count.
    local suggestion
    suggestion=$(grep -oE '^[[:space:]]*git [a-z][a-z-]+( [^[:space:]].*)?$' "$errfile" \
        | grep -v '[<>]' \
        | tail -1 \
        | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    [[ -z "$suggestion" ]] && return 1

    echo
    echo "That can be fixed without retyping it:"
    echo "    ${suggestion}"
    echo

    __igitari_confirm "Want me to run that?" || {
        echo "Left it to you."
        return 1
    }

    # Same dispatcher as a typed command, so it behaves identically.
    execute_command "$suggestion"
}

#--|TABBER                                                           [IGITARI]
#------------------------------------------------------------------------------
# Tab Completion System
#------------------------------------------------------------------------------

try_source_completion() {
    local file="$1"
    log n "   Sourcing ${file}..."

    # shellcheck source=/dev/null
    if [[ -f "$file" ]] && source "$file" 2>/dev/null; then
        log p "ok."
        return 0
    else
        log p "failed."
        return 1
    fi
}

setup_git_completion() {
    [[ ${NO_SOURCING} -eq 1 ]] && return

    log "Attempting to source Git completion files:"

    if ! try_source_completion "/usr/share/git/completion/git-completion.bash" &&
        ! try_source_completion "/etc/bash_completion.d/git"; then
        echo "Warning: I can't source any Git completion files, sorry! >.<"
    fi
    echo
}

# ---------------------------------------------------------------------------
# Helpers — module scope
# ---------------------------------------------------------------------------

find_common_prefix() {
    local -a completions=("$@")
    local prefix="${completions[0]}"

    for ((i = 1; i < ${#completions[@]}; i++)); do
        local current="${completions[i]}"
        local temp_prefix=""

        for ((j = 0; j < ${#prefix} && j < ${#current}; j++)); do
            if [[ "${prefix:$j:1}" == "${current:$j:1}" ]]; then
                temp_prefix+="${prefix:$j:1}"
            else
                break
            fi
        done

        prefix="$temp_prefix"
        [[ -z "$prefix" ]] && break
    done

    echo "$prefix"
}

# Tab is bound with `bind -x`, which hands us READLINE_LINE and READLINE_POINT
# and nothing else -- in particular, not COMP_WORDS or COMP_CWORD. git's own
# completion is a `complete -F` function and gets those maintained for free,
# then uses __git_find_on_cmdline to see which subcommand is already typed.
# That question is what every handler deeper than one word needs to ask, so
# rebuild the two pieces of it from what we do have. Handlers that read
# COMP_* directly silently misbehave: an unset COMP_CWORD makes
# `(( cword <= 1 ))` true no matter where the cursor is.

# Index of the word under the cursor, counting from 0. `forge ` is word 0;
# `forge checkout ` leaves the cursor on word 1.
__igitari_cword() {
    local line="$1"
    local word_start="$2"
    local prefix="${line:0:$word_start}"
    local -a words=()

    # The text before the cursor ends in a space whenever a new word is
    # starting, so the word count is the count of *finished* words.
    read -ra words <<< "$prefix"
    echo "${#words[@]}"
}

# The first non-flag word after the command -- the subcommand in play.
__igitari_subcmd() {
    local line="$1"
    local word_start="$2"
    local prefix="${line:0:$word_start}"
    local -a words=()
    local i

    read -ra words <<< "$prefix"
    for ((i = 1; i < ${#words[@]}; i++)); do
        [[ "${words[i]}" == -* ]] && continue
        echo "${words[i]}"
        return
    done
}

# The word immediately before the one under the cursor, or empty when the
# cursor is on the first word. Handlers use it for flags that take a value:
# `notes add -m <TAB>` is a message, not a ref.
__igitari_prev_word() {
    local line="$1"
    local word_start="$2"
    local before="${line:0:$word_start}"
    local -a words=()

    # Drop the trailing space so the last finished word is the previous one.
    before="${before% }"
    read -ra words <<< "$before"
    ((${#words[@]} > 0)) && echo "${words[-1]}"
}

# The nth word of the command line before the cursor, counting from 0 at the
# command itself. Empty when the line is shorter than that.
#
# __igitari_subcmd answers the question "which subcommand is in play", which is
# the first non-flag word. That is the wrong question for a command whose
# first word is not verbose but a name -- openweb's word 1 is a remote and its
# page is word 2 -- so those reach for a known position instead.
__igitari_word_at() {
    local line="$1"
    local word_start="$2"
    local index="$3"
    local -a words=()

    read -ra words <<< "${line:0:$word_start}"
    echo "${words[index]-}"
}

# Flag completion straight from the installed git. Every command answers
# `--git-completion-helper` with its own option list, so this cannot drift out
# of step with the binary the way a hardcoded list does. Cached: spawning git
# on every Tab would be felt.
#
# A third argument asks for one subcommand's flags. Commands that have
# subcommands (worktree, stash) answer the bare helper with the subcommand
# names instead of flags, which is not what a word starting with '-' wants.
# `git worktree add --git-completion-helper` does return add's options, so the
# subcommand goes in after the command name.
_complete_git_flags() {
    local cmd="$1"
    local cur="$2"
    local sub="${3:-}"
    local var="_IGITARI_FLAGS_${cmd//-/_}${sub:+_${sub//-/_}}"
    local flags

    eval "flags=\${$var-}"
    if [[ -z "$flags" ]]; then
        flags=$(git "$cmd" ${sub:+"$sub"} --git-completion-helper 2>/dev/null | tr '\n' ' ')
        eval "$var=\"\$flags\""
    fi

    mapfile -t completions < <(compgen -W "${flags}" -- "$cur")
}

has_remote_branch_context() {
    local line="$1"
    [[ "$line" =~ openweb ]] && return 1

    local remotes
    remotes=$(git remote 2>/dev/null | tr '\n' '|')
    remotes=${remotes%|}

    [[ -z "$remotes" ]] && return 1

    [[ -n "$remotes" && "$line" =~ [[:space:]](${remotes})[[:space:]] ]]
}

_get_branches() {
    git branch 2>/dev/null | sed 's/^[* ]*//' | sort -u
}

# Remote-tracking branches, by the name you actually type.
#
# A push or pull against a remote wants these, not local branches: the whole
# point of naming the remote is that the other side's branches are on offer.
# Kept separate from _get_branches so 'checkout' still offers local ones.
_get_remote_branches() {
    # A symref is not a branch you can name: refs/remotes/origin is a pointer
    # to origin's default branch, and it prints as a bare 'origin'. Requiring
    # a slash drops those and keeps origin/feature.
    git for-each-ref --format='%(refname:short)|%(symref)' refs/remotes 2>/dev/null |
        awk -F'|' '$2 == "" && $1 ~ /\//' |
        cut -d'|' -f1 | sort -u
}

_get_remotes() {
    git remote 2>/dev/null | tr '\n' ' '
}

# Tag names, space separated. Was inlined in three handlers; one place means
# one definition of what "the tags" means.
_get_tags_list() {
    git tag -l 2>/dev/null | tr '\n' ' '
}

display_completions() {
    local completions=("$@")
    local num_completions=${#completions[@]}
    local response="Y"

    if ((num_completions > 10)); then
        echo "Display all $num_completions possibilities? (y or n)"
        read -r -n1 -s response </dev/tty || return 0
    fi

    [[ ! "$response" =~ ^[Yy]$ ]] && return 0

    echo
    echo "Available completions:"

    local cols max_len=0
    cols=$(tput cols 2>/dev/null || echo 80)

    for comp in "${completions[@]}"; do
        ((${#comp} > max_len)) && max_len=${#comp}
    done

    local col_width=$((max_len + 2))
    local num_cols=$((cols / col_width))
    ((num_cols < 1)) && num_cols=1

    local count=0
    for comp in "${completions[@]}"; do
        printf "%-${col_width}s" "$comp"
        ((count++))
        ((count % num_cols == 0)) && echo
    done
    ((count % num_cols != 0)) && echo
}

# ---------------------------------------------------------------------------
# Command lists (arrays)
# ---------------------------------------------------------------------------

# Guarded like the constants above, and for the same reason: these are
# readonly arrays, so a second source would abort here and skip every function
# defined after them -- which is most of the script.
if [[ -z "${_IGITARI_CMDS+x}" ]]; then
    readonly _GIT_CMDS=(
        config help bugreport init clone add status diff commit notes restore reset
        rm mv branch checkout switch merge mergetool log stash tag worktree fetch
        pull push remote submodule show difftool range-diff shortlog describe apply
        cherry-pick rebase revert bisect blame grep am imap-send format-patch
        send-email request-pull svn fast-import clean gc fsck reflog filter-branch
        instaweb archive bundle daemon update-server-info cat-file check-ignore
        checkout-index commit-tree count-objects diff-index for-each-ref hash-object
        ls-files ls-tree merge-base read-tree rev-list rev-parse show-ref
        symbolic-ref update-index update-ref verify-pack write-tree
    )

    readonly _IGITARI_CMDS=(
        help exit lazygit openweb squash discard reword fzf movehead version guess
        paginate no-pager forge
    )
fi

# ---------------------------------------------------------------------------
# FZF special completion (branch/tag/commit picker)
# ---------------------------------------------------------------------------

_fzf_specialcompletion() {
    local prompt="${1:-Select ref: }"

    {
        _get_branches | sed 's/^* /(Current branch) /'
        git tag -l 2>/dev/null
        git log --oneline --color=always 2>/dev/null
    } | command fzf \
        --height=40% \
        --layout=reverse \
        --ansi \
        --prompt "$prompt" \
        --preview='git show --color=always {1}' \
        --pointer '  '
}

# ---------------------------------------------------------------------------
# Completion handlers — each receives (line, current_word, word_start)
# Sets completions[] and optionally overrides READLINE_LINE/READLINE_POINT.
# ---------------------------------------------------------------------------

_complete_files() {
    mapfile -t completions < <(compgen -f -- "$current_word")
}

_complete_branch_ref() {
    if __check_fzf 2>/dev/null; then
        local selected
        selected=$(_fzf_specialcompletion "Select branch/tag/commit: ")
        if [[ -n "$selected" ]]; then
            READLINE_LINE="${line:0:$word_start}${selected}${line:$point}"
            READLINE_POINT=$((word_start + ${#selected}))
        fi
        return
    fi

    local branches tags
    branches=$(_get_branches)
    tags=$(git tag -l 2>/dev/null | tr '\n' ' ')
    mapfile -t completions < <(compgen -W "${branches} ${tags}" -- "$current_word")
}

_complete_remote_branch() {
    if has_remote_branch_context "$line"; then
        # A remote was named, so its own branches are the answer.
        mapfile -t completions < <(compgen -W "$(_get_remote_branches)" -- "$current_word")
    else
        mapfile -t completions < <(compgen -W "$(_get_remotes)" -- "$current_word")
    fi
}

_complete_openweb() {
    local cword
    cword=$(__igitari_cword "$line" "$word_start")

    if ((cword <= 1)); then
        mapfile -t completions < <(compgen -W "$(_get_remotes)" -- "$current_word")
        return
    fi

    # openweb <remote> <page> [create|new|number]
    if ((cword == 2)); then
        mapfile -t completions < <(compgen -W "issues discussions releases pr prs mr mrs pull-request compare wiki settings" -- "$current_word")
        return
    fi

    # The page decides what the third word is: the pull-request pages take
    # 'create'/'new' (they land on the compare page), everything else takes a
    # number that the user has to know already, so nothing is offered.
    #
    # The page is the third word, not __igitari_subcmd's answer: word 1 is the
    # remote, so the first non-flag word after the command is the remote's
    # name, not the page.
    local page
    page=$(__igitari_word_at "$line" "$word_start" 2)
    case "$page" in
    pr | prs | mr | mrs | pull-request)
        mapfile -t completions < <(compgen -W "create new" -- "$current_word")
        ;;
    *) completions=() ;;
    esac
}

_complete_guess() {
    # One word, always: guess prints a single value and takes no further
    # argument. There is no depth to add here.
    mapfile -t completions < <(compgen -W "prior merge-base rebase-base root pr" -- "$current_word")
}

_complete_forge() {
    # Word 0 is 'forge'. Offer a verb first, then an object kind.
    local cword
    cword=$(__igitari_cword "$line" "$word_start")

    if ((cword <= 1)); then
        mapfile -t completions < <(compgen -W "checkout close comment merge review ready reopen edit lock diff checks revert create delete" -- "$current_word")
        return
    fi

    if ((cword == 2)); then
        local verb
        verb=$(__igitari_subcmd "$line" "$word_start")
        local -a kinds=()
        case "$verb" in
        checkout) kinds=(pr: mr: release:) ;;
        merge | review | ready | diff | checks | revert) kinds=(pr: mr:) ;;
        close | comment | reopen | edit | lock) kinds=(pr: mr: issue:) ;;
        create) kinds=(pr: mr: issue:) ;;
        delete) kinds=(issue:) ;;
        esac
        mapfile -t completions < <(compgen -W "${kinds[*]}" -- "$current_word")
    fi
}

_complete_remote() {
    local cword
    cword=$(__igitari_cword "$line" "$word_start")

    if ((cword <= 1)); then
        mapfile -t completions < <(compgen -W "add remove rename set-url set-head get-url prune update show" -- "$current_word")
        return
    fi

    # Every remote subcommand but 'add' names an existing remote. 'add' names
    # one that does not exist yet, so there is nothing to offer.
    case "$(__igitari_subcmd "$line" "$word_start")" in
    add) completions=() ;;
    *) mapfile -t completions < <(compgen -W "$(_get_remotes)" -- "$current_word") ;;
    esac
}

_complete_branch() {
    local cword
    cword=$(__igitari_cword "$line" "$word_start")

    if ((cword <= 1)); then
        local branch_flags="--delete --force --move --copy --list --remotes --all --set-upstream-to"
        mapfile -t completions < <(compgen -W "${branch_flags} $(_get_branches)" -- "$current_word")
        return
    fi

    # Branch names are the argument for every verb, whether it is creating,
    # deleting, renaming or resetting one. Flags do not belong below this.
    mapfile -t completions < <(compgen -W "$(_get_branches)" -- "$current_word")
}

# The stash entries, by the only name git accepts for them. Slicing at the
# first colon is how git's own completion picks stash@{N} out of the list;
# the message after it is free text and never part of a ref.
_get_stashes() {
    git stash list 2>/dev/null | sed -n -e 's/:.*//p'
}

_complete_stash() {
    local cword
    cword=$(__igitari_cword "$line" "$word_start")

    if ((cword <= 1)); then
        # 'store' and 'save' are in the list as well as the usual verbs:
        # they are real, just rarely typed.
        mapfile -t completions < <(compgen -W "push pop apply drop list show branch clear create store save import export" -- "$current_word")
        return
    fi

    local sub
    sub=$(__igitari_subcmd "$line" "$word_start")
    local stashes
    stashes=$(_get_stashes | tr '\n' ' ')

    case "$sub" in
    show | apply | drop | pop | export)
        # All of these name an existing stash entry, and only one: once it is
        # typed there is nothing further to offer, so a second word gets
        # nothing rather than the same list again.
        if ((cword == 2)); then
            mapfile -t completions < <(compgen -W "${stashes}" -- "$current_word")
        else
            completions=()
        fi
        ;;
    branch)
        # First argument is a new branch name, which does not exist yet, so a
        # ref is the sensible offer; a second argument names the stash.
        if ((cword == 2)); then
            _complete_branch_ref
        else
            mapfile -t completions < <(compgen -W "${stashes}" -- "$current_word")
        fi
        ;;
    import)
        # Import takes a commit-ish to read the stash from.
        _complete_branch_ref
        ;;
    *)
        # push/save/store take a message, list and clear take nothing.
        completions=()
        ;;
    esac
}

_complete_tag() {
    local cword
    cword=$(__igitari_cword "$line" "$word_start")

    if ((cword <= 1)); then
        local tag_flags="--annotate --delete --list --force --message"
        mapfile -t completions < <(compgen -W "${tag_flags} $(_get_tags_list)" -- "$current_word")
        return
    fi

    # Below the first word it is a tag name: -d and -v name one, and so does
    # the tag being created. Flags do not belong here.
    mapfile -t completions < <(compgen -W "$(_get_tags_list)" -- "$current_word")
}

# Paths of the linked worktrees. The first entry of `list --porcelain` is the
# main worktree, which cannot be moved, removed, locked -- so skip it, the way
# git's own completion does.
_get_worktree_paths() {
    git worktree list --porcelain 2>/dev/null | sed -n -e '2,$ s/^worktree //p'
}

# Declared submodule paths, read from .gitmodules rather than from status: a
# submodule that was never initialised still has a path worth completing, and
# `submodule status` says nothing about it until it has been cloned.
_get_submodule_paths() {
    local top
    top=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
    git config -f "${top}/.gitmodules" --get-regexp 'submodule\..*\.path' 2>/dev/null |
        awk '{print $2}'
}

_complete_worktree() {
    local cword
    cword=$(__igitari_cword "$line" "$word_start")

    if ((cword <= 1)); then
        mapfile -t completions < <(compgen -W "add list lock move prune remove unlock" -- "$current_word")
        return
    fi

    local sub
    sub=$(__igitari_subcmd "$line" "$word_start")
    local paths
    paths=$(_get_worktree_paths | tr '\n' ' ')

    case "$sub" in
    lock | unlock | remove)
        # These name an existing worktree. Only a linked one: git refuses the
        # main worktree for all three, so _get_worktree_paths skips it.
        mapfile -t completions < <(compgen -W "${paths}" -- "$current_word")
        ;;
    move)
        # First argument is the worktree to move, the second is a destination
        # path that need not exist yet, so leave that one to filenames.
        if ((cword == 2)); then
            mapfile -t completions < <(compgen -W "${paths}" -- "$current_word")
        else
            mapfile -t completions < <(compgen -f -- "$current_word")
        fi
        ;;
    add)
        # The new worktree's path does not exist yet, so it is a filename.
        # The commit-ish after it is a ref.
        if ((cword == 2)); then
            mapfile -t completions < <(compgen -f -- "$current_word")
        else
            _complete_branch_ref
        fi
        ;;
    *)
        # list and prune take no positional argument, so offering filenames
        # here would be a guess at something git does not accept.
        completions=()
        ;;
    esac
}

_complete_submodule() {
    local cword
    cword=$(__igitari_cword "$line" "$word_start")

    if ((cword <= 1)); then
        mapfile -t completions < <(compgen -W "add status init deinit update set-branch set-url summary foreach sync absorbgitdirs" -- "$current_word")
        return
    fi

    local sub
    sub=$(__igitari_subcmd "$line" "$word_start")
    local paths
    paths=$(_get_submodule_paths | tr '\n' ' ')

    case "$sub" in
    add)
        # First argument is a repository URL to clone from, which is not on
        # this disk; the path after it is where it will land, so a filename.
        if ((cword == 2)); then
            completions=()
        else
            mapfile -t completions < <(compgen -f -- "$current_word")
        fi
        ;;
    summary | foreach | sync | status)
        mapfile -t completions < <(compgen -W "${paths}" -- "$current_word")
        ;;
    *)
        # init, deinit, update, set-url, set-branch, absorbgitdirs all name a
        # submodule by its path.
        mapfile -t completions < <(compgen -W "${paths}" -- "$current_word")
        ;;
    esac
}

_complete_config() {
    # Subcommands and keys are different arguments in different positions.
    # Offering them mixed meant `config get <Tab>` showed both, and the wrong
    # half is the one you would pick.
    local cword
    cword=$(__igitari_cword "$line" "$word_start")

    if ((cword <= 1)); then
        local config_subcmds="list get set unset rename-section remove-section edit"
        mapfile -t completions < <(compgen -W "${config_subcmds}" -- "$current_word")
        return
    fi

    local config_keys
    config_keys=$(git config --list 2>/dev/null | cut -d= -f1 | tr '\n' ' ')
    mapfile -t completions < <(compgen -W "${config_keys}" -- "$current_word")
}

_complete_fzf() {
    local cword
    cword=$(__igitari_cword "$line" "$word_start")

    if ((cword <= 1)); then
        mapfile -t completions < <(compgen -W "commits tags reflogs staged unstaged tracked untracked stashes dangling prs issues discussions" -- "$current_word")
        return
    fi

    # Return types differ per selector, and fzf's own help text is the
    # authority on which: offering all nine everywhere would list 'number'
    # for commits and 'diffs' for prs, neither of which fzf accepts.
    local -a types
    case "$(__igitari_subcmd "$line" "$word_start")" in
    commits | reflogs) types=(sha message diffs) ;;
    tags) types=(sha name) ;;
    stashes) types=(ref diff name) ;;
    dangling) types=(sha type content message) ;;
    prs | issues | discussions) types=(number ref) ;;
    # staged, unstaged, tracked and untracked take no return type at all.
    *) types=() ;;
    esac
    mapfile -t completions < <(compgen -W "${types[*]}" -- "$current_word")
}

_complete_reword() {
    local refs
    refs=$(git log --oneline -20 2>/dev/null | awk '{print $1}')
    mapfile -t completions < <(compgen -W "${refs}" -- "$current_word")
}

_complete_discard() {
    local modified_files
    modified_files=$(git status --porcelain 2>/dev/null | cut -c4- | tr '\n' ' ')
    mapfile -t completions < <(compgen -W "all ${modified_files}" -- "$current_word")
}

_complete_conflict() {
    # Word 1 is the verb, word 2 is a side, everything after is a path.
    local cword
    cword=$(__igitari_cword "$line" "$word_start")

    if ((cword <= 1)); then
        mapfile -t completions < <(compgen -W "show throw" -- "$current_word")
        return
    fi
    if ((cword == 2)); then
        mapfile -t completions < <(compgen -W "both ours theirs" -- "$current_word")
        return
    fi
    # Only actually conflicted paths, so Tab never offers a resolved file.
    local unmerged
    unmerged=$(git diff --name-only --diff-filter=U 2>/dev/null | tr '\n' ' ')
    mapfile -t completions < <(compgen -W "${unmerged}" -- "$current_word")
}

_complete_log_flags() {
    _complete_git_flags log "$current_word"
}

_complete_git_command_names() {
    mapfile -t completions < <(compgen -W "${_GIT_CMDS[*]}" -- "$current_word")
}

_complete_shell_passthrough() {
    if [[ "$line" =~ ^\>[^[:space:]]+[[:space:]]+ ]]; then
        mapfile -t completions < <(compgen -f -- "$current_word")
    else
        # compgen -c lists a name once per PATH entry that holds it, so the
        # same binary shows up repeatedly; dedupe before prefixing. The '>'
        # is kept: word_start is 0 for '>ech' and 2 for '> ech', so whether
        # it is already typed depends on the form, and the insertion code
        # replaces from word_start -- which needs the prefix present in the
        # candidate to give the same answer either way.
        local shell_prefix="${current_word#>}"
        mapfile -t completions < <(compgen -c "$shell_prefix" | sort -u | sed 's/^/>/')
    fi
}

# The bisect state lives in files inside the git directory, and the terms
# are user-renameable: `bisect start --term-new=broken --term-old=slow` makes
# broken/slow the words to type. Read them back rather than assuming
# bad/good, or a bisect begun with custom terms completes nothing usable.
_bisect_state_file() {
    local git_dir
    git_dir=$(git rev-parse --git-dir 2>/dev/null) || return 1
    echo "${git_dir}/${1}"
}

_bisect_started() {
    local f
    f=$(_bisect_state_file BISECT_START) || return 1
    [[ -f "$f" ]]
}

_bisect_terms() {
    local f
    f=$(_bisect_state_file BISECT_TERMS) || return 0
    [[ -f "$f" ]] || return 0
    # Two lines: the bad side first, then the good. git defines them by
    # asking the binary, which answers 'error: no terms defined' when there
    # are none -- the file is the same information without the parsing.
    tr '\n' ' ' <"$f"
}

_complete_bisect() {
    local cword
    cword=$(__igitari_cword "$line" "$word_start")

    if ((cword <= 1)); then
        # Outside a bisection only `start` and `replay` make sense; inside
        # one the whole set does, including the terms in force. git offers
        # bad/new/good/old regardless of the terms in use, because naming a
        # term that is not in force gets a clear error -- better than
        # silently completing nothing when the user is confused.
        local -a verbs
        if _bisect_started; then
            verbs=(start bad new good old terms skip reset visualize replay log run help)
        else
            verbs=(start replay)
        fi
        local terms
        terms=$(_bisect_terms)
        mapfile -t completions < <(compgen -W "${verbs[*]} ${terms}" -- "$current_word")
        return
    fi

    local sub
    sub=$(__igitari_subcmd "$line" "$word_start")

    case "$sub" in
    bad | new | good | old | skip | reset | visualize | log | run | help)
        # skip and reset take an optional ref; bad/new/good/old name the
        # revision to mark, which is a ref.
        case "$sub" in
        reset | visualize | log | run | help) completions=() ;;
        *) _complete_branch_ref ;;
        esac
        ;;
    start)
        _complete_branch_ref
        ;;
    terms)
        completions=()
        ;;
    *)
        # Any custom term in force behaves exactly like bad/good.
        local terms
        terms=$(_bisect_terms)
        if [[ " $terms " == *" $sub "* ]]; then
            _complete_branch_ref
        else
            completions=()
        fi
        ;;
    esac
}

# Notes refs are the --ref= targets, and `notes --ref=<TAB>` wants those
# rather than commits. Everything else in notes is a ref or a filename.
_get_notes_refs() {
    git for-each-ref --format='%(refname:short)' refs/notes 2>/dev/null
}

_complete_notes() {
    local cword
    cword=$(__igitari_cword "$line" "$word_start")
    local sub=""
    ((cword > 1)) && sub=$(__igitari_subcmd "$line" "$word_start")

    # --ref=<value> is completed as the ref name itself, not a whole word.
    if [[ "$current_word" == --ref=* ]]; then
        local refs
        refs=$(_get_notes_refs | tr '\n' ' ')
        mapfile -t completions < <(compgen -W "${refs}" -- "${current_word#--ref=}" | sed 's/^/--ref=/')
        return
    fi

    if ((cword <= 1)); then
        local notes_refs
        notes_refs=$(_get_notes_refs | tr '\n' ' ')
        mapfile -t completions < <(compgen -W "add append copy edit get-ref list merge prune remove show ${notes_refs}" -- "$current_word")
        return
    fi

    # The word after -m or -F is a message or a file, never a ref.
    local prev
    prev=$(__igitari_prev_word "$line" "$word_start")
    case "$prev" in
    -m | -F | --message | --file)
        completions=()
        [[ "$prev" == -F || "$prev" == --file ]] && mapfile -t completions < <(compgen -f -- "$current_word")
        return
        ;;
    esac

    case "$sub" in
    prune | get-ref)
        # Neither takes a commit: prune clears unreachable notes, get-ref
        # prints the ref in use. Offering refs here would be inventing an
        # argument git rejects.
        completions=()
        ;;
    *)
        _complete_branch_ref
        ;;
    esac
}

# Reflog takes a ref almost anywhere, plus a subcommand set at word 1. The
# subcommands and the refs are one list because both are valid there: `reflog
# drop 3` and `reflog main@{2}` are both things you type.
_complete_reflog() {
    local cword
    cword=$(__igitari_cword "$line" "$word_start")

    if ((cword <= 1)); then
        local reflog_verbs="show list exists write delete drop expire"
        local branches
        branches=$(_get_branches)
        mapfile -t completions < <(compgen -W "${reflog_verbs} ${branches}" -- "$current_word")
        return
    fi

    _complete_branch_ref
}

# Only the paths git would actually remove: untracked and not ignored. Asking
# ls-files rather than `clean -nd` because a dry run is one typo away from the
# real thing, and this handler runs on every Tab.
_complete_clean() {
    local untracked
    untracked=$(git ls-files --others --directory --exclude-standard 2>/dev/null | tr '\n' ' ')
    mapfile -t completions < <(compgen -W "${untracked}" -- "$current_word")
}

# Commands whose positional argument is a revision. Without a handler these
# fall to the filename fallback, which is the one wrong answer that looks
# confident: `reset ` offering the working directory instead of HEAD~1.
# -- precedes pathspecs, so after it a filename is right after all.
_complete_rev_ref() {
    # -m and -F take text and a file, so the word after them is not a ref.
    local prev
    prev=$(__igitari_prev_word "$line" "$word_start")
    case "$prev" in
    -m | -F | --message | --file)
        completions=()
        [[ "$prev" == -F || "$prev" == --file ]] && mapfile -t completions < <(compgen -f -- "$current_word")
        return
        ;;
    esac

    local seen_dd=0
    local -a words=()
    read -ra words <<< "${line:0:$word_start}"
    local w
    for w in "${words[@]}"; do
        [[ "$w" == "--" ]] && seen_dd=1
    done

    if ((seen_dd)); then
        mapfile -t completions < <(compgen -f -- "$current_word")
    else
        _complete_branch_ref
    fi
}

_complete_log_rev() {
    # Accepts revisions and paths in the same list, which is why git's own
    # completion calls this a revlist: `log main src/` is valid. The same
    # shape fits grep, blame, archive and cherry, which take a revision and
    # then pathspecs.
    #
    # Below the first revision only paths remain: `grep main <TAB>` is a
    # pathspec, and offering refs there is the mistake this guards.
    local cword
    cword=$(__igitari_cword "$line" "$word_start")

    if ((cword > 1)); then
        mapfile -t completions < <(compgen -f -- "$current_word")
        return
    fi

    local branches tags files
    branches=$(_get_branches | tr '\n' ' ')
    tags=$(_get_tags_list)
    mapfile -t files < <(compgen -f -- "$current_word")
    mapfile -t completions < <(compgen -W "${branches} ${tags}" -- "$current_word")
    completions+=("${files[@]}")
}

# Commands whose arguments are revisions and nothing else: no path belongs
# among them. Separate from _complete_rev_ref only in that it never falls
# back to filenames, because these take no pathspec at all.
_complete_rev_only() {
    local refs
    refs="$(_get_branches | tr '\n' ' ') $(_get_tags_list)"
    mapfile -t completions < <(compgen -W "${refs}" -- "$current_word")
}

# Two-word commands whose word 1 is a verb. Same shape as worktree and
# submodule, and the same failure without it: the filename fallback offers
# the working directory where git wants a verb.
_complete_bundle() {
    local cword
    cword=$(__igitari_cword "$line" "$word_start")

    if ((cword <= 1)); then
        mapfile -t completions < <(compgen -W "create verify list-heads unbundle" -- "$current_word")
        return
    fi

    # create takes an output file that need not exist yet; the rest take an
    # existing bundle. Either way a filename is the right answer here, which
    # is what the fallback would have given -- but only after word 1.
    mapfile -t completions < <(compgen -f -- "$current_word")
}

_complete_sparse_checkout() {
    local cword
    cword=$(__igitari_cword "$line" "$word_start")

    if ((cword <= 1)); then
        mapfile -t completions < <(compgen -W "list init set add reapply clean disable check-rules" -- "$current_word")
        return
    fi

    # set and add name paths; the rest take none or operate on the whole tree.
    case "$(__igitari_subcmd "$line" "$word_start")" in
    set | add) mapfile -t completions < <(compgen -f -- "$current_word") ;;
    *) completions=() ;;
    esac
}

# ---------------------------------------------------------------------------
# Dispatch table
# ---------------------------------------------------------------------------

declare -A _COMPLETE_HANDLERS=(
    [openweb]=_complete_openweb
    [pull]=_complete_remote_branch
    [push]=_complete_remote_branch
    [fetch]=_complete_remote_branch
    [checkout]=_complete_branch_ref
    [switch]=_complete_branch_ref
    [rebase]=_complete_branch_ref
    [merge]=_complete_branch_ref
    [revert]=_complete_branch_ref
    [cherry-pick]=_complete_branch_ref
    [add]=_complete_files
    [rm]=_complete_files
    [mv]=_complete_files
    [restore]=_complete_files
    [diff]=_complete_files
    [show]=_complete_files
    [branch]=_complete_branch
    [remote]=_complete_remote
    [stash]=_complete_stash
    [tag]=_complete_tag
    [config]=_complete_config
    [fzf]=_complete_fzf
    [guess]=_complete_guess
    [forge]=_complete_forge
    [reword]=_complete_reword
    [discard]=_complete_discard
    [conflict]=_complete_conflict
    [worktree]=_complete_worktree
    [submodule]=_complete_submodule
    [bisect]=_complete_bisect
    [notes]=_complete_notes
    [reflog]=_complete_reflog
    [clean]=_complete_clean
    [commit]=_complete_rev_ref
    [reset]=_complete_rev_ref
    [log]=_complete_log_rev
    [describe]=_complete_rev_ref
    [replace]=_complete_rev_ref
    [bundle]=_complete_bundle
    [sparse-checkout]=_complete_sparse_checkout
    # Revisions, then pathspecs.
    [grep]=_complete_log_rev
    [blame]=_complete_log_rev
    [archive]=_complete_log_rev
    [cherry]=_complete_log_rev
    # Revisions only -- these take no path at all.
    [shortlog]=_complete_rev_only
    [show-branch]=_complete_rev_only
    [merge-base]=_complete_rev_only
    [rev-list]=_complete_rev_only
    [rev-parse]=_complete_rev_only
    [name-rev]=_complete_rev_only
    [describe]=_complete_rev_only
    [cat-file]=_complete_rev_only
)

# ---------------------------------------------------------------------------
# Main completion function — bound to Tab
# ---------------------------------------------------------------------------

complete_git_env() {
    local line="${READLINE_LINE}"
    local point="${READLINE_POINT}"

    # Locate start of the word being completed
    local word_start=$point
    while [[ $word_start -gt 0 && "${line:$((word_start - 1)):1}" != " " ]]; do
        ((word_start--))
    done

    local current_word="${line:$word_start:$((point - word_start))}"
    # Shell passthrough puts the marker outside the word ('> ech'), or inside
    # it ('>ech'). The candidates carry the marker (see
    # _complete_shell_passthrough), so in the spaced form the span to replace
    # has to start at the '>' rather than at the word. Take the candidate as
    # '>'+word and let word_start point at the '>', skipping the space.
    local replace_start=$word_start
    local shell_gap=0
    if [[ "${line:0:$word_start}" == "> " ]]; then
        replace_start=0
        shell_gap=1
        current_word=">${line:$word_start:$((point - word_start))}"
    fi
    word_start=$replace_start
    local -a completions=()

    # Dispatch
    if [[ "$current_word" =~ ^\>_ ]]; then
        echo "Error: You are trying to complete an internal function." >&2
        return 1
    elif [[ "$line" =~ ^\> ]]; then
        _complete_shell_passthrough
    elif [[ "$line" =~ ^(help|bugreport)[[:space:]] ]]; then
        _complete_git_command_names
    elif [[ "$line" =~ ^(log|shortlog)[[:space:]].*--[[:alpha:]]* ]]; then
        _complete_log_flags
    elif [[ "$current_word" == -* && "$current_word" != *=* && "$line" =~ ^[a-z][a-z0-9_-]*[[:space:]] ]]; then
        # Any command asked for a flag gets the list from git itself. This
        # sits before the handler dispatch on purpose: a handler owns the
        # positional arguments of its command, not the flag space, and the
        # binary is a better authority on the latter than we could be. The
        # subcommand goes along because flags live per-subcommand.
        #
        # A word of the form --flag=value is not a bare flag any more, it is
        # a flag's argument, and the helper only knows flag names -- so it
        # belongs to the handler, which may know what the value should be.
        _complete_git_flags "${line%% *}" "$current_word" "$(__igitari_subcmd "$line" "$word_start")"
    else
        local cmd="${line%% *}"
        if [[ -n "${_COMPLETE_HANDLERS[$cmd]+_}" ]]; then
            "${_COMPLETE_HANDLERS[$cmd]}"
        elif [[ "$line" =~ ^[a-z][a-z0-9_-]*[[:space:]] ]]; then
            mapfile -t completions < <(compgen -f -- "$current_word")
        else
            mapfile -t completions < <(compgen -W "${_GIT_CMDS[*]} ${_IGITARI_CMDS[*]}" -- "${current_word}")
        fi
    fi

    # Apply completions to the readline buffer
    local num_completions=${#completions[@]}
    # The '> ' form had its space folded into word_start, so put it back
    # between the marker and the binary name on the way out. In the unspaced
    # form the '>' is part of the word already and is emitted untouched.
    local shell_head=""
    local -a emit=()
    if ((shell_gap)); then
        shell_head="> "
        local c
        for c in "${completions[@]}"; do emit+=("${c#>}"); done
    else
        emit=("${completions[@]}")
    fi

    if ((num_completions == 1)); then
        READLINE_LINE="${line:0:$word_start}${shell_head}${emit[0]} ${line:$point}"
        READLINE_POINT=$((word_start + ${#shell_head} + ${#emit[0]} + 1))

    elif ((num_completions > 1)); then
        local common_prefix
        common_prefix=$(find_common_prefix "${emit[@]}")

        if [[ -n "$common_prefix" && ${#common_prefix} -gt ${#current_word} ]]; then
            READLINE_LINE="${line:0:$word_start}${shell_head}${common_prefix}${line:$point}"
            READLINE_POINT=$((word_start + ${#shell_head} + ${#common_prefix}))
        fi

        display_completions "${completions[@]}"
    fi
}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

setup_custom_tab_completion() {
    [[ ! -t 0 ]] && return

    bind -x '"\t": complete_git_env' >/dev/null 2>&1
    log "Custom tab completion enabled"
}

#--|GIT_HELPERS                                                       [GITLIB]
#------------------------------------------------------------------------------
# Git Helpers
#------------------------------------------------------------------------------
# Adoptable Git operations: squash, discard, untrack/retrack, reword,
# undo/redo, transplant, decimate, and __git_track_state.
#
# Deliberately portable. The destructive commands call __refuse_mid_operation,
# so lifting these means taking that guard too — it lives in [GITLIB] GIT_FUNC
# and depends only on __git_operation_desc, which is likewise [GITLIB].
#
# Nothing here touches the prompt, TABBER, the REPL, or any Igitari UI
# variable, and that is the part worth keeping. The point is that someone can
# lift these into their own Git wrapper by also taking two [GITLIB] helpers.
# Adding a call into [IGITARI] from here would quietly break that.

## These are considered 'tricks' that is not well known or commonly used, but comes in handy

# Syntax: squash [amount | commit1..commit2] "[message (optional)]"
#   amount             — squash the last <amount> commits (must be >= 2)
#   commit1..commit2   — squash those commits, INCLUSIVE on both ends
#                        (`c2..c3` folds c2 and c3, not just c3)
#
# Both forms reduce to one shape: move HEAD to <base>, then `merge --squash`
# <tip> back in. Keeping a single code path means the range form can never
# drift from the count form.
squash() {
    __refuse_mid_operation squash || return 1

    local stash_created=false

    # --yes may sit anywhere, so pull the flags out before reading the
    # positional arguments: the first positional is the target and the second
    # is the message, and either can contain anything.
    local assume_yes=0
    local -a positional=()
    local arg
    for arg in "$@"; do
        case "$arg" in
        --yes | -y) assume_yes=1 ;;
        --*)
            echo "Error: I don't know the flag '$arg'. Only --yes lives here."
            return 1
            ;;
        *) positional+=("$arg") ;;
        esac
    done

    # ${2:-} so a one-argument call cannot die on set -u before the usage
    # check below gets a chance to explain itself.
    local target="${positional[0]:-}"
    local message="${positional[1]:-}"

    if ((${#positional[@]} == 0)) || [[ -z "$target" ]]; then
        echo "Usage: squash [--yes] <amount | commit1..commit2> [message]"
        echo "  squash 3                        — squash the last 3 commits"
        echo "  squash abc1234..def5678         — squash those commits (both ends included)"
        echo "  squash 3 'combined message'     — and set the resulting message"
        echo "  squash 3 --yes                  — do not ask, just do it"
        echo "  --yes, -y   Skip the confirmation. For scripts and for when you"
        echo "              have already read what is about to happen."
        return 1
    fi

    local range base tip n total

    if [[ "$target" =~ ^[0-9]+$ ]]; then
        n=$target
        total=$(git rev-list --count HEAD)

        if ((n < 2)); then
            echo "Error: You can't just squash $n commit, how the hell would that supposed to work? At least 2."
            return 1
        fi

        if ((total < n)); then
            echo "Error: Only $total commits exist, can't squash more than that. Are you squashing history you haven't made yet?"
            return 1
        fi

        tip=$(git rev-parse HEAD) || return 1
        base=$(git rev-parse "HEAD~${n}") || return 1
        range="${base}..${tip}"
    elif [[ "$target" == *..* ]]; then
        # Validate BEFORE anything mutates. rev-parse alone is too permissive:
        # it silently accepts unknown flags in ranges, so check both ends.
        local raw_base=${target%%..*}
        local raw_tip=${target#*..}

        if [[ -z "$raw_base" || -z "$raw_tip" ]]; then
            echo "Error: A range needs both ends, silly. 'abc1234..def5678', not '...I forgot one' >.>"
            return 1
        fi

        base=$(git rev-parse --verify --quiet "${raw_base}^{commit}") || {
            echo "Error: '$raw_base' isn't a commit I know about. Typo, or did you forget to fetch? >.>"
            return 1
        }
        tip=$(git rev-parse --verify --quiet "${raw_tip}^{commit}") || {
            echo "Error: '$raw_tip' isn't a commit I know about. Typo, or did you forget to fetch? >.>"
            return 1
        }

        if ! git merge-base --is-ancestor "$base" "$tip"; then
            echo "Error: '$(git rev-parse --short "$base")' isn't an ancestor of '$(git rev-parse --short "$tip")'. Those aren't"
            echo "the same line of history (merges and reverts in the way). Pick a range that goes uphill."
            return 1
        fi

        if [[ "$base" == "$tip" ]]; then
            echo "Error: '$(git rev-parse --short "$base")' is the same commit as '$(git rev-parse --short "$tip")'. You'd be squashing it into itself. No."
            return 1
        fi

        # The range is inclusive of $base, so the new parent is $base's own
        # parent. Squash keeps everything, we only move HEAD back to it.
        local new_parent
        new_parent=$(git rev-parse --verify --quiet "${base}~1") || {
            echo "Error: '$base' is the root commit. Nothing below it to squash down to, so this is impossible. Nice try though."
            return 1
        }

        range="${base}..${tip}"
        base=$new_parent
        n=$(git rev-list --count "$range")

        # A squash rewrites history, so the commits folded in must be the
        # ones you're standing on. Refuse otherwise instead of silently
        # detaching from the requested range.
        if ! git merge-base --is-ancestor "$tip" HEAD; then
            echo "Error: '$tip' isn't reachable from the branch you're standing, so squashing it"
            echo "wouldn't touch anything you can see. Go stand on that branch first."
            return 1
        fi

        if [[ $(git rev-parse HEAD) != "$tip" ]]; then
            echo "Error: HEAD is at $(git rev-parse --short HEAD), but your range ends at $(git rev-parse --short "$tip")."
            echo "Squashing a range that does not end at HEAD means rewriting commits you"
            echo "are standing on top of. My squash can't do that safely, so I won't pretend:"
            echo ""
            echo "Run this instead (no really, I genuinely can't do it for you >.>):"
            echo "  ${GIT_PATH:-git} rebase -i $base     # then fold the top $n by hand"
            return 1
        fi
    else
        echo "Error: That's neither a number nor a range. Give me '3' or 'abc1234..def5678', not modern art."
        return 1
    fi

    echo "You are about to squash these $n commit(s) into one:"
    git log --oneline --decorate --reverse "$range"
    echo "They will sit on top of: $(git log --oneline --no-decorate -1 "$base")"
    echo

    if ((assume_yes == 0)); then
        __igitari_confirm "Proceed?" silent || {
            echo "Squashing aborted! No changes are made."
            return 1
        }
    else
        echo "(--yes given, not asking.)"
    fi

    # Check if there are uncommitted changes
    if ! git diff-index --quiet HEAD --; then
        if git stash --include-untracked; then
            stash_created=true
        else
            echo "Failed to stash changes! Aborting. (I can't risk nuking your work)"
            return 1
        fi
    fi

    # Store original HEAD
    local original_head
    original_head=$(git rev-parse HEAD) || return 1

    # Move HEAD to the new parent, then fold the tip back in as one commit.
    git reset --hard "$base" || {
        echo "Error: Reset failed. That's on git, not me."
        echo "Your everything is still safe at: $original_head (recover: reset --hard $original_head)"
        return 1
    }

    git merge --squash --no-commit "$tip" || {
        echo "Error: Merge failed (conflicts?)"
        if [[ $stash_created == true ]]; then
            echo "Sorry, you need to resolve conflicts manually..."
            echo "When you're done, run 'stash pop --index' to restore your uncommitted changes."
            echo "If you wish to cancel this operation, run 'reset --hard $original_head'"
        fi
        return 1
    }

    if [[ -z "$message" ]]; then
        git commit || {
            echo "Commit failed. Squashed changes are staged but not committed."
            if [[ $stash_created == true ]]; then
                echo "Stashed changes NOT restored to avoid confusion."
                echo "When ready, manually: stash pop --index"
            fi
            return 1
        }
    else
        git commit -m "$message" || {
            echo "Commit failed. Squashed changes are staged but not committed."
            if [[ $stash_created == true ]]; then
                echo "Stashed changes NOT restored to avoid confusion."
                echo "When ready, manually: stash pop --index"
            fi
            return 1
        }
    fi

    # Restore stash if we created one
    if [[ $stash_created == true ]]; then
        git stash pop --index || {
            echo "Warning: Failed to fully reapply stashed changes."
            echo "Your stash is still safe."
            echo "Resolve conflicts or retry with: git stash apply --index"
            echo "If you want to discard partial application: reset --hard HEAD"
            return 1
        }
    fi
}

# Classify how git regards a path, so untrack/retrack can say the honest
# thing instead of guessing. Echoes one of:
#   tracked    — in the index right now
#   pending    — untracked, but a removal is staged and uncommitted
#   forgotten  — untracked, and a removal is already in history
#   stranger   — git has never seen this path in any commit
#
# Caller is expected to have checked the path exists on disk.
__git_track_state() {
    local path="$1"

    if git ls-files --error-unmatch -- "$path" >/dev/null 2>&1; then
        echo "tracked"
        return
    fi

    # A staged deletion sits in the index diff but nowhere on disk.
    if git diff --cached --name-status --diff-filter=D -- "$path" 2>/dev/null | grep -q .; then
        echo "pending"
        return
    fi

    # --full-history so renames/merges don't hide it. Any commit at all counts.
    if [[ -n "$(git log --oneline --all --full-history -1 -- "$path" 2>/dev/null)" ]]; then
        echo "forgotten"
        return
    fi

    echo "stranger"
}

# Syntax: untrack <path> <path> ...
# Stop tracking paths without deleting them. Stages the removal; the file
# stays on disk exactly where it is.
untrack() {
    if (($# < 1)) || [[ -z "$1" ]]; then
        echo "Usage: untrack <path1> <path2> ..."
        return 1
    fi

    local -a to_untrack=()
    local unknown=0
    local path state

    for path in "$@"; do
        if [[ ! -e "$path" ]]; then
            echo "'$path' isn't on disk, so there's nothing to stop tracking."
            unknown=1
            continue
        fi

        state=$(__git_track_state "$path")
        case "$state" in
        tracked) to_untrack+=("$path") ;;
        pending)
            echo "'$path' is already untracked (removal is staged, just not committed)."
            ;;
        forgotten)
            echo "'$path' isn't tracked anymore. Git hasn't tracked it since an older commit."
            ;;
        stranger)
            echo "'$path' was never tracked, so there's nothing to untrack. Git never met it."
            unknown=1
            ;;
        esac
    done

    if ((${#to_untrack[@]} == 0)); then
        ((unknown == 1)) && return 1
        return 0
    fi

    echo "Untracking ${#to_untrack[@]} path(s):"
    printf ' -  %s\n' "${to_untrack[@]}"
    echo

    __igitari_confirm "Proceed?" silent || {
        echo "Untrack aborted. Untracking nothing."
        return 1
    }

    if ! git rm --cached --quiet -- "${to_untrack[@]}"; then
        echo "Error: git refused to untrack. Nothing was changed."
        return 1
    fi

    echo "Done."
    echo
    echo "From now on, to the git database, it will be as if this got deleted."
    echo "It stays on your local disk, it just won't be tracked anymore."
    echo
    echo "The removal is staged, not committed. Commit it when you mean it."
    echo "Changed your mind? 'retrack <path>' puts it back."
}

# Syntax: retrack <path> <path> ...
# The inverse of untrack: put an untracked path back under git's eye.
retrack() {
    if (($# < 1)) || [[ -z "$1" ]]; then
        echo "Usage: retrack <path1> <path2> ..."
        return 1
    fi

    local -a to_add=()
    local nothing=0
    local path state

    for path in "$@"; do
        if [[ ! -e "$path" ]]; then
            echo "'$path' isn't on disk. Nothing to retrack."
            nothing=1
            continue
        fi

        state=$(__git_track_state "$path")
        case "$state" in
        tracked)
            echo "'$path' is already tracked. A retrack would be a no-op."
            ;;
        pending)
            echo "'$path' has an uncommitted removal staged. Retracking cancels that"
            echo "untrack. History was never touched."
            to_add+=("$path")
            ;;
        forgotten)
            echo "'$path' was removed in an earlier commit. Adding it back is a NEW"
            echo "commit, not a resurrection of the old one."
            to_add+=("$path")
            ;;
        stranger)
            echo "'$path' was never tracked. Git never met it, so this is a plain add."
            to_add+=("$path")
            ;;
        esac
    done

    echo
    if ((${#to_add[@]} == 0)); then
        ((nothing == 1)) && return 1
        return 0
    fi

    # A path can be both untracked and ignored - that is the normal end state
    # after untracking a file you then added to .gitignore. 'git add' refuses
    # those without -f, which would make retrack fail exactly where untrack
    # promised it would work. The user has already said they want it tracked,
    # so force past the ignore for these specific paths only.
    local -a ignored_ones=()
    local path
    for path in "${to_add[@]}"; do
        if git check-ignore -q -- "$path" 2>/dev/null; then
            ignored_ones+=("$path")
        fi
    done

    if ((${#ignored_ones[@]} > 0)); then
        echo "Note: .gitignore also lists these, but you asked to track them anyway:"
        printf ' -  %s\n' "${ignored_ones[@]}"
        echo "They'll be tracked, and .gitignore will keep ignoring them for anyone else."
        echo
    fi

    if ! git add -f -- "${to_add[@]}"; then
        echo "Error: git add failed. Nothing was staged."
        return 1
    fi

    echo "Retracking ${#to_add[@]} path(s):"
    printf ' -  %s\n' "${to_add[@]}"
    echo
    echo "They're in git's eye again, staged but not committed."
}

discard() {
    __refuse_mid_operation discard || return 1

    local assume_yes=0
    local -a args=()
    local arg

    # --yes may sit anywhere; everything else is positional.
    for arg in "$@"; do
        case "$arg" in
        --yes | -y) assume_yes=1 ;;
        --*)
            echo "Error: I don't know the flag '$arg'. Only --yes lives here."
            return 1
            ;;
        *)
            args+=("$arg")
            ;;
        esac
    done

    if ((${#args[@]} == 0)); then
        echo "Usage: discard [--yes] <file1> <file2> ..."
        echo "       discard [--yes] all (tracked | untracked | staged | unstaged)"
        echo "  --yes, -y   Skip the confirmation. For bulk mode and named files alike."
        return 1
    fi

    # Shared confirmation. Sets DISCARD_CONFIRMED to 1 when we should go ahead.
    DISCARD_CONFIRMED=0
    __warn_discard() {
        local n_file=$1
        local mode=$2
        local filelist=$3 # Supposed to be piped from git commands
        local danger=${4:-}

        [[ $n_file == 0 ]] && {
            echo "Nothing to discard."
            return 1
        }

        DISCARD_CONFIRMED=0

        # Plural/Singular text thing
        if ((n_file == 1)) && [[ -z $mode ]]; then
            echo "This file will be discarded:"
        elif ((n_file == 1)) && [[ -n $mode ]]; then
            echo "This $mode file will be discarded:"
        elif [[ -z $mode ]]; then
            echo "The following $n_file files will be discarded:"
        else
            echo "The following $n_file $mode files will be discarded:"
        fi

        printf '%s\n' "$filelist" | sed 's/^/ -  /'

        # Untracked paths get 'rm -rf'. Worth saying out loud.
        if [[ -n "$danger" ]]; then
            echo
            echo -e "\e[91m\e[1m$danger\e[0m"
        fi

        if ((assume_yes == 1)); then
            echo
            echo "(--yes given, not asking.)"
            DISCARD_CONFIRMED=1
            return 0
        fi

        echo
        if __igitari_confirm "Are you sure?"; then
            DISCARD_CONFIRMED=1
            return 0
        fi

        echo "Discard operation aborted."
        return 1
    }

    discard_files() {
        local file_array=("$@")
        local -a restore_files=() # git-tracked: put the committed version back
        local -a delete_files=()  # untracked and visible: remove from disk
        local file not_found=0
        local total=0
        local skipped_ignored=()

        # 'discard' means "throw away uncommitted changes", so a tracked path
        # is RESTORED, never removed. A directory is therefore not a unit of
        # deletion: walk into it and treat the tracked and untracked parts
        # separately, exactly as if you had named each file yourself.
        for file in "${file_array[@]}"; do
            if [[ ! -e "$file" ]]; then
                echo "'$file' not found."
                not_found=1
                continue
            fi

            if [[ -d "$file" ]]; then
                local entry
                while IFS= read -r -d '' entry; do
                    if git ls-files --error-unmatch -- "$entry" >/dev/null 2>&1; then
                        restore_files+=("$entry")
                    elif git check-ignore -q -- "$entry" 2>/dev/null; then
                        skipped_ignored+=("$entry")
                    else
                        delete_files+=("$entry")
                    fi
                done < <(find "$file" -type f -print0 2>/dev/null)
                continue
            fi

            # A single path. Ask whether git tracks *this file itself*;
            # ls-files --error-unmatch on a directory matches a file inside
            # it, which is why this check only runs for non-directories.
            if git ls-files --error-unmatch -- "$file" >/dev/null 2>&1; then
                restore_files+=("$file")
            elif git check-ignore -q -- "$file" 2>/dev/null; then
                # Ignored is not the same as untracked. .gitignore is a standing
                # instruction to leave this alone; 'git clean' honours it unless
                # you pass -x. Deleting it because you happened to name it would
                # be the one place in the ecosystem that ignores that guard.
                skipped_ignored+=("$file")
            else
                delete_files+=("$file")
            fi
        done

        if ((${#skipped_ignored[@]} > 0)); then
            echo "Not touching these, .gitignore is asking me to leave them alone:"
            printf ' -  %s\n' "${skipped_ignored[@]}"
            echo
        fi

        total=$(( ${#restore_files[@]} + ${#delete_files[@]} ))
        if ((total == 0)); then
            ((not_found == 1)) && return 1
            return 1
        fi

        local danger=""
        if ((${#delete_files[@]} > 0)); then
            danger="Also removing untracked: ${delete_files[*]} — gone for good."
        fi

        __warn_discard "$total" "" "${restore_files[*]} ${delete_files[*]}" "$danger" || return 1
        ((DISCARD_CONFIRMED == 1)) || return 1

        local failed=0
        local file

        for file in "${restore_files[@]}"; do
            echo "Taking '$file' back to its last committed self..."
            if git checkout -- "$file"; then
                echo "'$file' restored."
            else
                echo "Failed to discard '$file'."
                failed=1
            fi
        done

        for file in "${delete_files[@]}"; do
            echo "Sweeping away untracked '$file'..."
            if rm -f "$file"; then
                echo "'$file' removed."
            else
                echo "Failed to remove '$file'."
                failed=1
            fi
        done

        # Prune directories that are now empty. Deepest-first, so nested
        # empties collapse before their parents are tested. 'rmdir' without
        # --ignore-fail refuses non-empty dirs, which is exactly the guard we
        # want: a directory still holding a restored file survives untouched.
        for file in "${file_array[@]}"; do
            [[ -d "$file" ]] || continue
            find "$file" -depth -type d -print0 2>/dev/null \
                | while IFS= read -r -d '' dir; do
                    rmdir -- "$dir" 2>/dev/null || true
                done
done

        [[ $failed -ne 0 ]] && return 1
        return 0
    }

    discard_all() {

        local list filecount filelist

        case "$1" in
        "") # DISCARD EVERYTHING
            list=$(git status --porcelain)
            filecount=$(printf '%s\n' "$list" | sed '/^$/d' | wc -l)
            filelist=$(printf '%s\n' "$list" | sed 's/^.\{1,2\} //')

            __warn_discard "$filecount" "" "$filelist" && {
                git reset --hard HEAD
                git clean -fd
            }
            ;;
        tracked)
            list=$(git ls-files -m)
            filecount=$(printf '%s\n' "$list" | sed '/^$/d' | wc -l)

            __warn_discard "$filecount" "modified" "$list" &&
                git reset --hard HEAD
            ;;
        untracked)
            list=$(git ls-files --others --exclude-standard)
            filecount=$(printf '%s\n' "$list" | sed '/^$/d' | wc -l)

            __warn_discard "$filecount" "untracked" "$list" &&
                git clean -fd
            ;;
        staged)
            list=$(git diff --cached --name-only)
            filecount=$(printf '%s\n' "$list" | sed '/^$/d' | wc -l)

            __warn_discard "$filecount" "staged" "$list" &&
                git reset HEAD
            ;;
        unstaged)
            list=$(git diff --name-only)
            filecount=$(printf '%s\n' "$list" | sed '/^$/d' | wc -l)

            __warn_discard "$filecount" "unstaged" "$list" &&
                git checkout -- .
            ;;
        *)
            echo "Invalid mode '$1'."
            return 1
            ;;
        esac

        if (($filecount > 0)) && ((DISCARD_CONFIRMED == 1)); then
            [[ -z "$1" ]] && echo "All changes discarded." || echo "All $1 changes discarded."
        fi

    }

    # args[0] is the subcommand ('all' or a filename).
    if [[ "${args[0]}" == "all" ]]; then
        discard_all "${args[1]:-}"
    else
        discard_files "${args[@]}"
    fi
}

reword() {
    __refuse_mid_operation reword || return 1

    # ${1:-} so a bare 'reword' reaches the usage text instead of dying on
    # set -u one line earlier.
    if [[ -z "${1:-}" ]]; then
        echo "Usage: reword [new commit message] [<commit-hash> (optional)]"
        return 1
    fi

    if (($# > 2)); then
        echo "Error: Please put the new commit message in quotes, I can't tell which one is which >.> (Too many arguments)"
        return 1
    fi

    local target_commit=""
    local new_message=""

    new_message="$1"
    # ${2:-} not $2: the one-argument form is the documented default (amend
    # HEAD), and a bare $2 under 'set -u' kills the call before it starts.
    if [[ -z "${2:-}" ]]; then
        target_commit="$(git rev-parse HEAD)"
    else
        target_commit="$(git rev-parse "$2")"
    fi

    __reword_past_commit_that_for_some_fucking_reason_got_too_complicated() {
        local short_sha
        short_sha="$(git rev-parse --short "$target_commit")"
        local editor_script message_script
        editor_script="$(mktemp)"
        message_script="$(mktemp)"

        cat >"$editor_script" <<EOF_script
#!/bin/sh
sed -i -e 's/^pick $short_sha /reword $short_sha /' "\$1"
EOF_script

        # Properly escape the new message for the script
        cat >"$message_script" <<'EOF_msg'
#!/bin/sh
cat > "$1" <<'COMMIT_MSG'
EOF_msg
        printf '%s\n' "$new_message" >>"$message_script"
        cat >>"$message_script" <<'EOF_msg'
COMMIT_MSG
EOF_msg

        chmod +x "$editor_script" "$message_script"

        GIT_SEQUENCE_EDITOR="$editor_script" \
            GIT_EDITOR="$message_script" \
            git rebase -i "$target_commit^"

        rm -f "$editor_script" "$message_script"
    }

    if ! git cat-file -e "$target_commit^{commit}" 2>/dev/null; then
        echo "Error: '$target_commit' is not a valid commit."
        return 1
    fi

    if [[ "$(git rev-parse "$target_commit")" == "$(git rev-parse HEAD)" ]]; then
        git commit --amend -m "$new_message"
    else
        echo "Warning: You are about to reword commit '$target_commit', which is an older commit."
        echo "This will require a rebase, which may be dangerous ESPECIALLY if you have already pushed the commit."
        echo

        if __igitari_confirm "Proceed anyway?"; then
            __reword_past_commit_that_for_some_fucking_reason_got_too_complicated
        else
            echo "Alright, aborted."
        fi
    fi
}

# Undo last Git operation(s) using reflog. Usage: undo [steps]
undo() {
    # Read the reflog here rather than trusting $GIT_REFLOG: that global is
    # only filled in when something refreshes the status, which may not have
    # happened yet. Relying on it made 'undo' claim "no reflog available" in a
    # perfectly healthy repository.
    GIT_REFLOG=$(git reflog 2>/dev/null)
    GIT_REFLOG_COUNT=$(printf '%s\n' "$GIT_REFLOG" | sed '/^$/d' | wc -l | tr -d ' ')
    [[ -z "$GIT_REFLOG" ]] && { echo "Error: No reflog available. Are you in a git repository?"; return 1; }

    local target="${1:-1}"
    [[ $target =~ ^[0-9]+$ ]] || { echo "Usage: undo [steps]"; return 1; }

    if ((target >= GIT_REFLOG_COUNT)); then
        echo "Error: No more undo history."
        return 1
    fi

    echo "Undoing $target step(s)..."
    git log --oneline -1 "HEAD@{${target}}"
    git reset --hard "HEAD@{${target}}"
}

# Redo last undone Git operation using reflog. Usage: redo
redo() {
    # Same reasoning as 'undo': read it fresh, do not trust the global.
    GIT_REFLOG=$(git reflog 2>/dev/null)
    GIT_REFLOG_COUNT=$(printf '%s\n' "$GIT_REFLOG" | sed '/^$/d' | wc -l | tr -d ' ')
    [[ -z "$GIT_REFLOG" ]] && { echo "Error: No reflog available. Are you in a git repository?"; return 1; }

    # A redo only makes sense straight after an undo, which always leaves a
    # 'reset: moving to' entry at HEAD@{0}. Without that, HEAD@{1} is just the
    # previous commit and "redoing" to it would silently rewind history.
    local last_action
    last_action=$(git reflog --format='%gs' -1 HEAD 2>/dev/null)

    if [[ "$last_action" != reset:* ]]; then
        echo "Error: Nothing to redo."
        return 1
    fi

    # The reset moved us away FROM HEAD@{1}, so that is where we go back to.
    local previous
    previous=$(git reflog --format='%H' -1 "HEAD@{1}" 2>/dev/null)

    if [[ -z "$previous" ]]; then
        echo "Error: Nothing to redo."
        return 1
    fi

    echo "Redoing to $(git log --oneline -1 "$previous" 2>/dev/null)..."
    git reset --hard "$previous"
}

# Transplant commits from current branch to another branch
# Usage: transplant <commit | n> <to_branch>
#   commit — specific commit hash to transplant
#   n      — number of commits from HEAD to transplant (e.g. "3" = last 3 commits)
transplant() {
    __refuse_mid_operation transplant || return 1

    local source=""
    local source_shown=""
    local target_branch=""
    local force=0

    # --force may appear anywhere; the positional args are what's left.
    local arg
    for arg in "$@"; do
        case "$arg" in
        --force) force=1 ;;
        --*)
            echo "Error: I don't know the flag '$arg'. Only --force lives here."
            return 1
            ;;
        *)
            if [[ -z "$source" ]]; then
                source="$arg"
                source_shown="$arg"
            elif [[ -z "$target_branch" ]]; then
                target_branch="$arg"
            else
                echo "Error: Too many arguments, I'm not psychic >.> It's 'transplant <commit | n> <to_branch> [--force]'."
                return 1
            fi
            ;;
        esac
    done

    if [[ -z "$source" || -z "$target_branch" ]]; then
        echo "Usage: transplant <commit | n> <to_branch> [--force]"
        echo "  transplant abc1234 feature  — move commit abc1234 to 'feature'"
        echo "  transplant 3 feature        — move last 3 commits to 'feature'"
        echo "  --force                     — go ahead even if commits are already pushed"
        return 1
    fi

    local original_branch

    original_branch=$(git symbolic-ref --short HEAD 2>/dev/null) || {
        echo "Error: You're not even in a branch (detached HEAD), what are you even trying to transplant?"
        return 1
    }

    if [[ "$original_branch" == "$target_branch" ]]; then
        echo "Error: You're pointing at the same branch, make sure you check the capitalisation!"
        return 1
    fi

    if ! git rev-parse --verify "$target_branch" &>/dev/null; then
        echo "Error: Branch '$target_branch' doesn't exist."
        return 1
    fi

    # Resolve commit(s) to transplant
    local -a commits
    if [[ "$source" =~ ^[0-9]+$ ]]; then
        # Numeric — last N commits
        if ((source < 1)); then
            echo "Error: You're asking me to transplant none/negative commits? Huh?? >.>"
            return 1
        fi
        local total
        total=$(git rev-list --count HEAD)
        if ((source > total)); then
            echo "Error: Only $total commits exist (you asked for $source), you're asking too much!"
            return 1
        fi

        # 'HEAD~N..HEAD' needs a parent to anchor the range. Asking for every
        # commit means the range starts at the root, which has no parent, and
        # git fails with 'ambiguous argument HEAD~N..HEAD' -- an error about
        # the syntax of a command the user never typed. Say what is actually
        # wrong: there is nothing before the first commit to move from.
        if ((source == total)); then
            echo "Error: All $total commit(s) on this branch means the range starts"
            echo "at the very first one, and that has no parent to move from."
            echo "Ask for fewer, or name a specific commit."
            return 1
        fi

        mapfile -t commits < <(git rev-list --reverse "HEAD~${source}..HEAD")
    else
        # Commit hash
        if ! git cat-file -e "$source^{commit}" 2>/dev/null; then
            echo "Error: I can't find commit '$source'!"
            return 1
        fi
        commits=("$source")
    fi

    local commit_count=${#commits[@]}

    # Rewriting commits that already exist upstream means someone else has
    # them. The reset at the end of this function would quietly diverge you.
    if ((force == 0)); then
        local pushed_commits=()
        local ahead_count

        # Commits on this branch that the upstream does not have.
        ahead_count=$(git rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo 0)

        local c
        for c in "${commits[@]}"; do
            # "In the remote branch" is the real question, not "on some
            # remote". Ask git whether the tip of upstream contains it.
            if git merge-base --is-ancestor "$c" '@{upstream}' 2>/dev/null; then
                pushed_commits+=("$c")
            fi
        done

        if ((${#pushed_commits[@]} > 0)); then
            echo "Error: These commits are already pushed. Moving them would rewrite"
            echo "published history:"
            for c in "${pushed_commits[@]}"; do
                echo "  $(git log --oneline --no-decorate -1 "$c")"
            done
            echo
            echo "Anyone who already pulled them ends up with a diverged branch and has"
            echo "to sort it out. That is their problem because of your command, so I am"
            echo "not making that decision on your behalf."
            echo
            if [[ -z "$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)" ]]; then
                echo "Actually, this branch has no upstream at all, so I can't tell what's"
                echo "published at all. If you know these are safe to move, say: transplant $source_shown $target_branch --force"
            else
                echo "If you are certain this is safe (force-push arranged, nobody else on the branch):"
                echo "  transplant $source_shown $target_branch --force"
            fi
            return 1
        fi

        if [[ -z "$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)" ]] && ((ahead_count == 0)); then
            # No upstream configured. Nothing we can prove is published.
            :
        fi
    fi

    echo "Moving house: $commit_count commit(s) from '$original_branch' to '$target_branch'."
    for c in "${commits[@]}"; do
        git log --oneline -1 "$c"
    done
    echo

    __igitari_confirm "Proceed?" silent || {
        echo "Transplant aborted."
        return 1
    }

    # Stash uncommitted changes if any
    local stash_created=false
    if ! git diff-index --quiet HEAD --; then
        echo "Uncommitted changes detected. Stashing."
        if git stash --include-untracked; then
            echo "Done."
            stash_created=true
        else
            echo "Error: Failed to stash changes. Aborting."
            return 1
        fi
    fi

    echo "Checking out to $target_branch to start"
    # Cherry-pick onto target branch
    git checkout "$target_branch" || {
        echo "Error: Failed to checkout '$target_branch'."
        $stash_created && git stash pop --index
        return 1
    }

    if ! git cherry-pick "${commits[@]}"; then
        echo "Error: Cherry-pick failed (conflicts?)."
        echo "  Resolve conflicts, then run 'cherry-pick --continue && stash pop --index'"
        echo "  Or abort with 'cherry-pick --abort && checkout $original_branch'"
        $stash_created && echo "  Stashed changes will be restored on '$original_branch' after resolution."
        return 1
    fi

    # Return to original branch and reset
    git checkout "$original_branch" || {
        echo "Error: Failed to return to '$original_branch'."
        return 1
    }

    git reset --hard "${commits[0]}^" || {
        echo "Error: Failed to reset '$original_branch'."
        return 1
    }

    # Restore stash if created
    if $stash_created; then
        git stash pop --index || {
            echo "Warning: Failed to restore stashed changes."
            echo "  Run 'stash pop --index' manually when ready."
        }
    fi

    echo "Done! $commit_count commit(s) transplanted to '$target_branch'. They live there now. ^^"
}

# Remove a file from entire git history as if it never existed
# Usage: decimate <file> [--all]
decimate() {
    __refuse_mid_operation decimate || return 1

    if [[ -z "$1" ]]; then
        echo "Usage: decimate <file> [--all]"
        echo "  --all    Rewrite all branches (default: current branch only)"
        return 1
    fi

    local target_file="$1"
    local rewrite_all=0
    [[ "${2:-}" == "--all" ]] && rewrite_all=1

    # Check if file exists in any commit
    if ! git log --all --diff-filter=A -- "$target_file" | grep -q .; then
        echo "Error: '$target_file' doesn't even exist to git (yet)! (Untracked)"
        return 1
    fi

    local current_branch target_ref scope_desc
    current_branch=$(git branch --show-current 2>/dev/null)
    target_ref="${current_branch:-HEAD}"

    if [[ $rewrite_all -eq 1 ]]; then
        scope_desc="ALL branches"
        target_ref=""
    else
        scope_desc="current branch '${current_branch:-HEAD}'"
    fi

    local commit_count
    if [[ $rewrite_all -eq 1 ]]; then
        commit_count=$(git log --all --oneline -- "$target_file" | wc -l)
    else
        commit_count=$(git log --oneline -- "$target_file" | wc -l)
    fi

    echo "This will remove '$target_file' from $commit_count commit(s) in $scope_desc, as if it never existed."
    echo "WARNING: This rewrites history! Do not use on pushed branches (without concrete reason, that is)."
    echo

    __igitari_confirm "Proceed?" silent || {
        echo "Decimate aborted."
        return 1
    }

    # Stash dirty changes so filter-branch/filter-repo can rewrite cleanly
    local did_stash=0
    if ! git diff --quiet 2>/dev/null || ! git diff --staged --quiet 2>/dev/null; then
        echo "Stashing dirty changes first..."
        git stash push -q -m "decimate: auto-stash before rewriting"
        did_stash=1
    fi

    echo "Snapping '$target_file' out of existence..."

    local filter_exit=0
    if command -v git-filter-repo &>/dev/null; then
        echo "Using filter-repo."
        local -a repo_args=(--invert-paths --path "$target_file" --force)
        [[ $rewrite_all -eq 0 ]] && repo_args+=(--refs "$target_ref")
        git filter-repo "${repo_args[@]}" || filter_exit=$?
    else
        echo "Using fast-export/fast-import (bash-native) with exact parent stitching."

        # 1. Locate the exact commit where the file was first added
        local add_commit base_commit
        add_commit=$(git log --diff-filter=A --format="%H" -1 -- "$target_file" 2>/dev/null || true)

        if [[ -n "$add_commit" ]]; then
            # Parent of the ADD commit (suppress stderr if add_commit is root commit)
            base_commit=$(git rev-parse "${add_commit}~1" 2>/dev/null || true)
        fi

        # 2. Build bounded export arguments
        local -a export_args=()
        if [[ $rewrite_all -eq 1 ]]; then
            if [[ -n "$base_commit" ]]; then
                export_args=(--all "^${base_commit}")
            else
                export_args=(--all)
            fi
        else
            if [[ -n "$base_commit" ]]; then
                export_args=("${base_commit}..${target_ref}")
            else
                export_args=("${target_ref}")
            fi
        fi

        # 3. Export with --reference-excluded-parents to preserve parent pointers
        git fast-export --no-progress --reference-excluded-parents "${export_args[@]}" | \
            awk -v file="$target_file" '
                # Drop M and D lines strictly matching " " + file at end of line
                ($1 == "M" || $1 == "D") && substr($0, length($0) - length(file)) == " " file {
                    next
                }
                { print }
            ' | git fast-import --force

        # Check exit codes of all pipeline stages
        local pipe_status=("${PIPESTATUS[@]}")
        if [[ ${pipe_status[0]} -ne 0 || ${pipe_status[1]} -ne 0 || ${pipe_status[2]} -ne 0 ]]; then
            filter_exit=1
        fi

        # 4. Sync working tree
        if [[ $filter_exit -eq 0 ]]; then
            git reset --hard HEAD
        fi
    fi

    if [[ $filter_exit -ne 0 ]]; then
        echo -e "\e[91mError: Filtering failed (exit code $filter_exit). History was NOT rewritten.\e[0m"
        [[ $did_stash -eq 1 ]] && git stash pop -q 2>/dev/null
        return 1
    fi

    echo "Filtering done, cleaning up the remains:"

    # Clean up
    git reflog expire --expire=now --all
    git gc --prune=now --aggressive

    # Restore stashed changes
    [[ $did_stash -eq 1 ]] && git stash pop -q 2>/dev/null

    echo "Done! '$target_file' has been snapped out of existence."
}

# Print one of the values you keep having to dig out by hand.
#
#   guess prior          The branch you were on before this one
#   guess merge-base     Where the branch being merged started
#   guess rebase-base    The commit you are rebasing onto
#   guess root           The top of the working tree
#
# gitsh has these as injected variables ($_prior, $_merge_base). Igitari has a
# command layer rather than a variable layer, so they are a command instead:
# it prints a value and exits, which composes wherever a value would go.
#
# Value goes to stdout and nothing else does, so 'checkout $(guess prior)'
# works. Failure goes to stderr with a non-zero status, and NOTHING is printed
# on stdout -- an empty line would be read as a value by whoever asked.
guess() {
    local what="${1:-}"

    case "$what" in
        "")
            echo "Usage: guess <prior|merge-base|rebase-base|root|pr>"
            echo "  guess prior         The branch you were on before this one"
            echo "  guess merge-base    Where the merge in progress started from"
            echo "  guess rebase-base   The commit you are rebasing onto"
            echo "  guess root          The top of the working tree"
            echo "  guess pr            This branch's pull request, as pr:<n>"
            return 1
            ;;
        prior)       __guess_prior ;;
        merge-base)  __guess_merge_base ;;
        rebase-base) __guess_rebase_base ;;
        root)        __guess_root ;;
        pr)          __guess_pr ;;
        *)
            echo "Error: I don't know what '$what' is. Try prior, merge-base, rebase-base, root or pr." >&2
            return 1
            ;;
    esac
}

__guess_prior() {
    local branch
    branch=$(git rev-parse --abbrev-ref '@{-1}' 2>/dev/null) || {
        echo "Error: no previous branch. This session has not switched branches." >&2
        return 1
    }

    # --abbrev-ref normalises a detached checkout back to the branch it left,
    # so the useful check here is that it named something at all. 'HEAD' is
    # kept as a guard because that is what abbrev-ref prints when it cannot
    # work out a branch name, and handing that back would re-detach.
    if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
        echo "Error: the last checkout was not a branch (detached HEAD)." >&2
        return 1
    fi

    printf '%s\n' "$branch"
}

__guess_merge_base() {
    local gitdir
    gitdir=$(git rev-parse --git-dir 2>/dev/null) || {
        echo "Error: not in a git repository." >&2
        return 1
    }

    if [[ ! -f "${gitdir}/MERGE_HEAD" ]]; then
        echo "Error: no merge in progress, so there is no merge base to guess." >&2
        return 1
    fi

    git merge-base HEAD MERGE_HEAD 2>/dev/null || {
        echo "Error: these histories share nothing, so there is no merge base." >&2
        return 1
    }
}

__guess_rebase_base() {
    local gitdir
    gitdir=$(git rev-parse --git-dir 2>/dev/null) || {
        echo "Error: not in a git repository." >&2
        return 1
    }

    # An interactive rebase keeps 'onto' in rebase-merge; an am-style one in
    # rebase-apply. Read the file rather than trusting one directory name.
    local onto=""
    if [[ -f "${gitdir}/rebase-merge/onto" ]]; then
        onto=$(cat "${gitdir}/rebase-merge/onto" 2>/dev/null)
    elif [[ -f "${gitdir}/rebase-apply/onto" ]]; then
        onto=$(cat "${gitdir}/rebase-apply/onto" 2>/dev/null)
    fi

    if [[ -z "$onto" ]]; then
        echo "Error: no rebase in progress, so there is nothing to guess." >&2
        return 1
    fi

    printf '%s\n' "$onto"
}

__guess_pr() {
    local provider bin number

    if ! provider=$(__forge_provider 2>/dev/null) || [[ -z "$provider" ]]; then
        # Same silence rule as the rest of guess: stdout stays empty so a
        # $(...) capture never becomes a surprise argument.
        echo "Error: I can't tell which forge this is. Set FORGE_PROVIDER=gh or glab." >&2
        return 1
    fi

    if ! bin=$(__forge_bin); then
        echo "Error: '$provider' is not installed." >&2
        return 1
    fi

    case "$provider" in
    gh)
        # 'pr view' only answers when the local branch is the PR head it knows
        # about, which needs the branch to be tracking something. A branch
        # created by hand, or one that was never pushed, falls through to
        # --head, which matches on the name alone.
        number=$("$bin" pr view --json number --template '{{.number}}' 2>/dev/null)
        if [[ -z "$number" ]]; then
            local branch default_branch matches
            branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
            default_branch=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)
            default_branch="${default_branch#origin/}"

            # --head matches on the branch NAME alone, so on 'master' it would
            # happily return some fork's PR that happens to use the same word.
            # Never guess there: a wrong PR number is worse than no answer.
            if [[ -n "$branch" && "$branch" != "HEAD" && "$branch" != "$default_branch" ]]; then
                matches=$("$bin" pr list --head "$branch" --limit 2 --json number \
                    --template '{{range .}}{{.number}}{{"\n"}}{{end}}' 2>/dev/null)
                # Two matches means the name is not unique. Stay quiet.
                [[ -n "$matches" && "$(printf '%s\n' "$matches" | wc -l)" -eq 1 ]] &&
                    number="$matches"
            fi
        fi
        ;;
    glab)
        # UNVERIFIED beyond the flag existing (glab 1.128.0): resolving the
        # current branch's MR needs a token, and nobody has watched this
        # succeed. 'glab mr view' with no id does pick the branch's MR.
        number=$("$bin" mr view 2>/dev/null |
            sed -n 's/^!\([0-9][0-9]*\).*/\1/p' | head -1)
        ;;
    esac

    if [[ -z "$number" ]]; then
        echo "Error: no $([[ "$provider" == "gh" ]] && echo 'pull request' || echo 'merge request') for this branch." >&2
        return 1
    fi

    printf '%s:%s\n' "$(__forge_object_kind prs)" "$number"
}

__guess_root() {
    local root
    root=$(git rev-parse --show-toplevel 2>/dev/null) || {
        echo "Error: not in a git working tree." >&2
        return 1
    }
    [[ -n "$root" ]] || {
        echo "Error: not in a git working tree." >&2
        return 1
    }
    printf '%s\n' "$root"
}

#--|MOVEHEAD                                                          [IGITARI]
#------------------------------------------------------------------------------
# Relative HEAD movement — move forward/backward in commit history
#------------------------------------------------------------------------------

# Relative HEAD movement command (forward/backward) without explicit checkout
movehead() {
    local direction="$1"
    local steps=${2:-1}

    if [[ -z "$direction" ]]; then
        echo "Usage: movehead (forward | backward) <steps>"
        return 1
    fi

    if ! [[ "$steps" =~ ^[0-9]+$ ]]; then
        echo "Error: '$steps' is not a valid number."
        return 1
    fi

    if ((steps == 0)); then
        echo "Zero steps is nowhere. HEAD stays where it is."
        return 1
    fi

    if [[ "$direction" == "backward" ]]; then
        git checkout "HEAD~${steps}"
    elif [[ "$direction" == "forward" ]]; then
        if git symbolic-ref --short HEAD 2>/dev/null >/dev/null; then
            echo "Already on a branch — nothing to move forward to."
            return 1
        fi

        # Walk FORWARD along history, which is not the same as reading the
        # reflog: 'backward' writes reflog entries of its own, so counting
        # offsets from here lands short by however many it just made. Instead
        # find where we are in the branch we left, then step up it.
        local here target_branch chain target
        here=$(git rev-parse HEAD)

        # The branch we came from is the one whose history contains us.
        target_branch=""
        local b
        for b in $(git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null); do
            if git merge-base --is-ancestor "$here" "$b" 2>/dev/null; then
                target_branch="$b"
                break
            fi
        done

        local available=0
        if [[ -n "$target_branch" ]]; then
            # First-parent chain of that branch, and our place in it. idx is
            # 1-based from the tip, so the most we can move forward is idx-1.
            chain=$(git rev-list --first-parent "$target_branch" 2>/dev/null)
            local idx
            idx=$(printf '%s\n' "$chain" | grep -nx "$here" | head -1 | cut -d: -f1)
            if [[ -n "$idx" ]]; then
                available=$((idx - 1))
                if ((steps > available)); then
                    # Asking for more than the branch holds used to fall
                    # through to the reflog, which then answered with some
                    # unrelated commit a fixed number of entries back -- a
                    # plausible-looking landing place that was neither the tip
                    # nor 'steps' away. Refuse instead of inventing an answer.
                    echo "Only $available commit(s) forward on '$target_branch' (asked for $steps)."
                    echo "Nothing was moved."
                    return 1
                fi
                target=$(printf '%s\n' "$chain" | sed -n "$((idx - steps))p")
            fi
        fi

        # No branch contains us at all: the reflog is the only remaining lead.
        # It is a guess about *which* commit, but it is not a guess about
        # distance -- HEAD@{N} is N entries back, which is a different thing
        # from N commits forward, so only use it when no branch can answer.
        if [[ -z "${target:-}" ]]; then
            target=$(git rev-parse "HEAD@{$steps}" 2>/dev/null)
        fi

        if [[ -z "${target:-}" ]] || ! git checkout "$target" 2>/dev/null; then
            echo "Cannot move forward. Try 'reflog' to see recent commits."
            return 1
        fi

        if ! git symbolic-ref --short HEAD 2>/dev/null >/dev/null; then
            # Only a real branch reattaches us. When HEAD is detached,
            # 'git branch --points-at' prints "(HEAD detached at abc1234)" as a
            # pseudo-entry, and checking that string out fails with an
            # unfriendly pathspec error -- while still restoring the files, so
            # it looked like it half-worked.
            local branch_at_head
            # for-each-ref over refs/heads, not 'git branch --points-at':
            # the latter invents the pseudo-entry "(HEAD detached at abc1234)"
            # when detached, which is not a branch and cannot be checked out.
            branch_at_head=$(git for-each-ref --points-at HEAD --format='%(refname:short)' refs/heads 2>/dev/null | head -1)
            if [[ -n "$branch_at_head" ]]; then
                echo "At tip of '$branch_at_head', reattaching HEAD."
                git checkout "$branch_at_head"
            fi
        fi
    else
        echo "Error: Invalid direction '$direction'. Use 'forward' or 'backward'."
        return 1
    fi
}

# Read-only summary of where you are. One line per fact, nothing hidden behind
# a pager, safe to pipe.
#
# Different question from 'status', which is git's own verbose report. This is
# the glance: what branch, how far from upstream, is anything half-finished,
# and how much is lying around uncommitted.
state() {
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        echo "Not in a git repository. Nothing to report on."
        return 1
    fi

    local branch
    branch=$(git symbolic-ref --short HEAD 2>/dev/null)

    if [[ -n "$branch" ]]; then
        echo "branch    ${branch}"
    else
        echo "branch    (detached at $(git rev-parse --short HEAD 2>/dev/null))"
    fi

    local upstream
    upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)
    if [[ -n "$upstream" ]]; then
        # Split without trusting IFS, which may have been left as something
        # exotic by whoever called us. rev-list also emits a tab, not a space.
        local rel ahead behind
        rel=$(__git_relative_head)
        ahead=${rel%%[[:space:]]*}
        behind=${rel##*[[:space:]]}
        echo "upstream  ${upstream}  +${ahead:-0} -${behind:-0}"
    fi

    # Half-finished business first. It changes what every other command means.
    local st op_desc
    st=$(__git_state)
    op_desc=$(__git_operation_desc)

    if [[ -n "$op_desc" ]]; then
        if [[ "$st" == *c* ]]; then
            echo "operation ${op_desc}, $(__git_conflict_n) conflict(s)"
        else
            echo "operation ${op_desc}"
        fi
    fi

    # Counts. Cheap enough, and 'git status --porcelain' is one call.
    local staged=0 modified=0 untracked=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        case "${line:0:2}" in
            '??') untracked=$((untracked + 1)) ;;
            '  ') ;;
            *)    staged=$((staged + 1)) ;;
        esac
        case "${line:1:1}" in
            [MDT]) [[ "${line:0:1}" != "?" ]] && modified=$((modified + 1)) ;;
        esac
    done < <(git status --porcelain 2>/dev/null)

    local stash_n
    stash_n=$(git stash list 2>/dev/null | wc -l | tr -d ' ')

    local work=""
    [[ $staged -gt 0 ]] && work+="${staged} staged, "
    [[ $modified -gt 0 ]] && work+="${modified} modified, "
    [[ $untracked -gt 0 ]] && work+="${untracked} untracked, "
    [[ $stash_n -gt 0 ]] && work+="${stash_n} stash, "

    if [[ -n "$work" ]]; then
        echo "work      ${work%, }"
    else
        echo "work      clean"
    fi
}

#--|GIT_FUNC                                                          [GITLIB]
#------------------------------------------------------------------------------
# Git Repository Functions
#------------------------------------------------------------------------------

# Parse current Git branch
parse_git_branch() {
    local branch_list
    branch_list=$(git branch 2>/dev/null) || return 1

    if [[ -n "${branch_list}" ]]; then
        echo "${branch_list}" | sed -n 's/^\* //p'
    else
        return 1
    fi
}

# Evaluate cleanliness
dirty_check() {
    if ! git diff --quiet >/dev/null; then
        REPO_IS_DIRTY=1
    else
        REPO_IS_DIRTY=0
    fi

    if ! git diff --staged --quiet >/dev/null; then
        REPO_IS_DIRTY_AND_STAGED=1
    else
        REPO_IS_DIRTY_AND_STAGED=0
    fi

    if git rev-parse --verify refs/stash >/dev/null 2>&1; then
        REPO_STASH_DIRTY=1
    else
        REPO_STASH_DIRTY=0
    fi

    GIT_REFLOG=$(git reflog 2>/dev/null)
    GIT_REFLOG_COUNT=$(echo "$GIT_REFLOG" | sed '/^$/d' | wc -l)
}

# Display Git repository status
display_git_status() {
    local branch
    branch=$(parse_git_branch) || branch='None (Not in git repository.)'

    echo "On branch ${branch}"
    git status 2>/dev/null || echo "Status undefined."
}

# Check if current directory is in a Git repository
check_git_repository() {
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        if [[ "${NOT_GitDir}" != "1" ]]; then
            echo -e "\e[93m\e[1mWarning: You're not inside a git repository right now!"
            echo -e "You have to either:\n Type 'init' to create a new repository here.\n Change directory to a real git repository. \e[0m"
            NOT_GitDir=1
        fi
        return 1
    else
        NOT_GitDir=0
        return 0
    fi
}

# Read or throw away one side of a conflicted path.
#
#   conflict                          List the conflicted paths
#   conflict show <side> [file]       Print that side (index stage)
#   conflict throw <side> [file]      Discard that side, keeping the other
#
# Sides are ours (stage 2) and theirs (stage 3), plus 'both' for the common
# ancestor (stage 1), which is what you get when neither side is chosen.
#
# 'throw' names the LOSER, not the winner. Mid-conflict you are usually
# deciding what to delete -- the conflict markers are the thing you want gone
# -- so 'throw theirs' says what you mean directly. The alternative spelling,
# 'take ours', would say the same thing and make you translate.
#
# Naming the loser also survives git's confusing vocabulary: during a rebase
# 'ours' is the upstream, not you, and 'throw ours' still reads correctly as
# "discard that side" because you are naming the side that dies.
#
# Usage: conflict [show|throw <ours|theirs|both> [file]]
conflict() {
    local action="${1:-}"
    shift || true

    case "$action" in
        "")
            conflict_list
            return
            ;;
        show|throw) ;;
        *)
            echo "Usage: conflict                                  List conflicts"
            echo "       conflict show <ours|theirs|both> [file]   Print a side"
            echo "       conflict throw <ours|theirs|both> [file] Discard a side"
            return 1
            ;;
    esac

    local side="${1:-}"
    local only_file="${2:-}"

    if [[ -z "$side" ]]; then
        echo "Usage: conflict ${action} <ours|theirs|both> [file]"
        return 1
    fi

    # The two actions use the index stage very differently: show reads the
    # named side, throw keeps the OTHER one, so the stage it writes is the
    # opposite. Keeping both in one variable is how this gets written wrong.
    local read_stage write_stage
    case "$side" in
        both)   read_stage=1; write_stage=1 ;;
        ours)   read_stage=2; write_stage=3 ;;
        theirs) read_stage=3; write_stage=2 ;;
        *)
            echo "Error: '$side' is neither side. Try ours, theirs or both."
            return 1
            ;;
    esac

    local -a paths=()
    if [[ -n "$only_file" ]]; then
        if ! git ls-files -u -- "$only_file" | grep -q .; then
            echo "'$only_file' is not conflicted. Nothing to ${action}."
            return 1
        fi
        paths=("$only_file")
    else
        local p
        while IFS= read -r p; do
            [[ -n "$p" ]] && paths+=("$p")
        done < <(git diff --name-only --diff-filter=U 2>/dev/null)
    fi

    if [[ ${#paths[@]} -eq 0 ]]; then
        echo "No conflicts. Nothing is unmerged."
        return 1
    fi

    if [[ "$action" == "show" ]]; then
        local file
        for file in "${paths[@]}"; do
            if [[ ${#paths[@]} -gt 1 ]]; then
                echo "=== ${file} (${side}) ==="
            fi
            if ! git cat-file -e ":${read_stage}:${file}" 2>/dev/null; then
                echo "(no ${side} version -- this side does not have the file)"
                continue
            fi
            git show ":${read_stage}:${file}"
        done
        return 0
    fi

    # --- throw ------------------------------------------------------------

    # Throwing away 'base' is what 'take base' used to mean: the file goes
    # back to the common ancestor with both sides discarded. Worth saying out
    # loud, because it is the odd one out of the three.
    if [[ "$side" == "both" ]]; then
        echo "Throwing 'both' restores the file as your common ancestor had it:"
        echo "neither side is chosen, and nothing is resolved by picking."
    fi

    # Throwing a side away destroys it. Ask once, and name every path and any
    # that is missing on that side before writing anything.
    local listing="" f
    for f in "${paths[@]}"; do
        if git cat-file -e ":${read_stage}:${f}" 2>/dev/null; then
            listing+="  ${f}"$'\n'
        else
            listing+="  ${f}  (no ${side} version)"$'\n'
        fi
    done

    echo "About to throw away the '${side}' version of:"
    printf '%s' "$listing"
    __igitari_confirm "Proceed?" silent || {
        echo "Left alone. Nothing was written."
        return 1
    }

    _conflict_take "$write_stage" "$side" "${paths[@]}"
}

# Write one index stage into the working tree and stage it.
# The caller decides which stage survives; this only performs it.
_conflict_take() {
    local stage="$1"
    local threw="$2"
    shift 2
    local -a paths=("$@")

    local file wrote=0 failed=0
    for file in "${paths[@]}"; do
        if ! git cat-file -e ":${stage}:${file}" 2>/dev/null; then
            echo "Skipped '${file}': there is no version left to keep."
            continue
        fi

        # Write the stage out, then stage it so the path stops being unmerged.
        if git checkout-index -f --stage="${stage}" -- "${file}" 2>/dev/null \
            && git add -- "${file}" 2>/dev/null; then
            echo "Threw away '${threw}' for '${file}'."
            wrote=$((wrote + 1))
        else
            echo -e "\e[91mCould not resolve '${file}'.\e[0m"
            failed=$((failed + 1))
        fi
    done

    if [[ $failed -gt 0 ]]; then
        return 1
    fi
    if [[ $wrote -eq 0 ]]; then
        echo "Nothing was resolved."
        return 1
    fi

    if [[ -z "$(git diff --name-only --diff-filter=U 2>/dev/null)" ]]; then
        echo "All conflicts are resolved. Finish the operation when you're ready."
    else
        echo "$(git diff --name-only --diff-filter=U 2>/dev/null | wc -l | tr -d ' ') path(s) still unmerged."
    fi
}

# List the conflicted paths, one per line. Nothing else, so it pipes.
conflict_list() {
    local -a unmerged=()
    local p
    while IFS= read -r p; do
        [[ -n "$p" ]] && unmerged+=("$p")
    done < <(git diff --name-only --diff-filter=U 2>/dev/null)

    if [[ ${#unmerged[@]} -eq 0 ]]; then
        echo "No conflicts. Nothing is unmerged."
        return 1
    fi

    printf '%s\n' "${unmerged[@]}"
}

# Refuse to rewrite history while an operation is half-finished. A merge,
# rebase or am in progress means the working tree and index are in a state the
# rewrite would make sense of differently than you expect.
#
# Echoes a reason on refusal and returns 1, so the caller can just:
#     __refuse_mid_operation squash || return 1
__refuse_mid_operation() {
    local verb="${1:-this}"
    local op_desc
    op_desc=$(__git_operation_desc)

    if [[ -n "$op_desc" ]]; then
        echo "Hold on — ${op_desc}. Finish it or abort it before asking me to ${verb}."
        echo "Nothing has been touched. (check with 'state')"
        return 1
    fi
    return 0
}

# Which operation is half-finished. Only meaningful when __git_state reported
# 'o' -- on a clean repository there is nothing to name and this returns empty.
#
# Echoes exactly one character:
#   m  merge          r  rebase          y  rebase --apply
#   p  cherry-pick    v  revert          b  bisect
#   e  am (email patches)
#
# The operations are mutually exclusive; git will not let you start a second
# one while the first is unfinished. That is why this is a single code rather
# than a set of composable flags -- unlike 'c' and 'd' in __git_state, these
# cannot co-occur.
__git_operation() {
    local gitdir
    gitdir=$(git rev-parse --git-dir 2>/dev/null)
    [[ -z "$gitdir" ]] && return 1

    # Most specific first. A rebase conflict leaves both rebase-merge/ and a
    # CHERRY_PICK_HEAD, so rebase has to be checked before cherry-pick.
    if [[ -f "${gitdir}/MERGE_HEAD" ]]; then
        echo "m"
    elif [[ -d "${gitdir}/rebase-merge" ]]; then
        echo "r"
    elif [[ -d "${gitdir}/rebase-apply" ]]; then
        # Both backends share this directory. '--apply' rebase leaves a
        # 'rebasing' marker; git am leaves 'applying'. Without checking,
        # a rebase would be reported as an email patch session.
        if [[ -f "${gitdir}/rebase-apply/rebasing" ]]; then
            echo "y"
        else
            echo "e"
        fi
    elif [[ -f "${gitdir}/CHERRY_PICK_HEAD" ]]; then
        echo "p"
    elif [[ -f "${gitdir}/REVERT_HEAD" ]]; then
        echo "v"
    elif [[ -f "${gitdir}/BISECT_LOG" ]]; then
        echo "b"
    else
        return 1
    fi
}

# How many commits a sequencer still has queued. Echoes 0 when there is no
# sequencer, so callers need no special case -- only cherry-pick and revert
# use a sequencer, which is why both can report a remaining count.
__git_sequencer_left() {
    local todo
    todo="$(git rev-parse --git-dir 2>/dev/null)/sequencer/todo"

    [[ -f "$todo" ]] || { echo 0; return 0; }
    grep -c '' "$todo" 2>/dev/null || echo 0
}

# Human name for the half-finished operation, expanding the 'o' flag from
# __git_state. Echoes nothing when there is no operation, so callers can test
# for emptiness rather than fetching a code they then have to translate.
#
# The wording lives here and nowhere else. Anything that wants to name an
# operation calls this instead of switching on __git_operation itself.
__git_operation_desc() {
    local op left
    op=$(__git_operation) || return 0

    case "$op" in
        m) echo "merge in progress" ;;
        r) echo "rebase in progress" ;;
        y) echo "rebase --apply in progress" ;;
        e) echo "am in progress" ;;
        p|v)
            # Both run through the sequencer, so both can have a queue left.
            local verb="cherry-pick"
            [[ "$op" == "v" ]] && verb="revert"

            left=$(__git_sequencer_left)
            if [[ "${left:-0}" -gt 1 ]]; then
                echo "${verb} in progress (${left} left)"
            else
                echo "${verb} in progress"
            fi
            ;;
        b) echo "bisecting" ;;
        *) ;;
    esac
}

# What is the repository busy with right now?
#
# Echoes a string of single-character flags, meaning:
#   a  an 'am' patch application is in progress
#   c  there are conflicted paths
#   d  the branch has diverged from its upstream (both ahead and behind)
#   o  a multi-step operation is half-done and waiting for you: merge, rebase,
#      am, cherry-pick, revert or bisect -- including when the tree is clean
#      because you already resolved the conflict and have not continued yet,
#      and including a sequencer with commits still queued. 'o' only says one
#      exists; call __git_operation to find out which.
#
# No flags means nothing to report: a normal working repository.
#
# The flags are PRESENCE-only. Callers test for a character, they do not index
# into the string:
#
#     st=$(__git_state)
#     [[ "$st" == *c* ]] && ...
#
# Order is therefore not part of the contract -- do not rely on it, and do not
# start slicing. '' is the sentinel for "nothing going on".
__git_state() {
    local flags=""

    # An 'am' session in progress. rebase-apply is shared with 'rebase --apply',
    # which writes a 'rebasing' marker instead; only count the am case, so a
    # rebase is not announced as a patch session. Note 'am' can stop WITHOUT
    # conflicts (the patch simply did not apply), so this flag does not depend
    # on unmerged paths -- being mid-am is the fact.
    if [[ -f "$(git rev-parse --git-dir 2>/dev/null)/rebase-apply/applying" ]]; then
        flags+="a"
    fi

    # Any unmerged path, whichever operation left it that way.
    [[ -n "$(git diff --name-only --diff-filter=U 2>/dev/null)" ]] && flags+="c"

    # Half-finished operation, however clean the tree looks. This is the flag
    # that matters most: a resolved-but-not-continued cherry-pick or a
    # sequencer with commits still queued has no conflicts and no divergence,
    # so without it the repository looks completely idle when it is not.
    local gitdir
    gitdir=$(git rev-parse --git-dir 2>/dev/null)
    if [[ -f "${gitdir}/MERGE_HEAD" ]] \
        || [[ -d "${gitdir}/rebase-merge" ]] \
        || [[ -d "${gitdir}/rebase-apply" ]] \
        || [[ -f "${gitdir}/CHERRY_PICK_HEAD" ]] \
        || [[ -f "${gitdir}/REVERT_HEAD" ]] \
        || [[ -f "${gitdir}/BISECT_LOG" ]] \
        || [[ -s "${gitdir}/sequencer/todo" ]]; then
        flags+="o"
    fi

    # Diverged means both directions are non-empty. Ahead alone or behind alone
    # does not break a plain push/pull, so it is not news.
    local upstream ahead behind
    upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)
    if [[ -n "$upstream" ]]; then
        # --left-right counts the UPSTREAM side first, so read as behind,ahead.
        local behind ahead
        read -r behind ahead < <(git rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null)
        if [[ "${ahead:-0}" -gt 0 && "${behind:-0}" -gt 0 ]]; then
            flags+="d"
        fi
    fi

    echo "$flags"
}

# How many paths are conflicted. 0 when there are none.
__git_conflict_n() {
    git diff --name-only --diff-filter=U 2>/dev/null | wc -l | tr -d ' '
}

# Ahead and behind counts against upstream, as "ahead behind".
# Echoes nothing when there is no upstream to compare against.
__git_relative_head() {
    local upstream
    upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)
    [[ -z "$upstream" ]] && return 1

    # --left-right counts upstream-side first, so flip them back.
    local behind ahead
    read -r behind ahead < <(git rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null)
    echo "${ahead:-0} ${behind:-0}"
}

#--|FORGE_ADAPTER                                                     [GITLIB]
#------------------------------------------------------------------------------
# Forge providers -- GitHub and GitLab, through gh and glab
#------------------------------------------------------------------------------
#
# A forge is where a repository's collaboration state lives: pull requests,
# issues, discussions, releases. git cannot see any of it, which is why this
# belongs in GITLIB and not in Igitari's UI layer -- it is git-aware (it reads
# the remote to decide who to ask) but it knows nothing about prompts, colours
# or command names.
#
# Everything here is silent on failure and reports through the exit status.
# Wording belongs to the IGITARI layer, so an RC or a test can use this tier
# without inheriting the chatter.
#
# Nothing here touches the network. These are detection and parsing helpers;
# the calls that reach a server are made by the commands that need them. That
# is what keeps sourcing this tier free, so the prompt and 'state' stay offline.

# The host a remote points at: no scheme, no user, no path, lowercased.
# Prints nothing and returns 1 when the remote is missing or is a local path.
__forge_remote_host() {
    local remote="${1:-origin}"
    local url
    url=$(git remote get-url "$remote" 2>/dev/null) || return 1
    [[ -z "$url" ]] && return 1

    case "$url" in
    *://*)
        # https://host/..., ssh://git@host/..., git://host/...
        url="${url#*://}"
        url="${url%%/*}"
        url="${url#*@}"  # strip a user, if any
        url="${url%%:*}"  # and a port: :2222 is the sshd, not the web host
        ;;
    *:*)
        # scp syntax: git@host:user/repo. No scheme, so the colon is the split.
        url="${url%%:*}"
        url="${url#*@}"
        ;;
    *)
        # A plain path is a folder, not a forge.
        return 1
        ;;
    esac

    [[ -z "$url" ]] && return 1
    printf '%s\n' "${url,,}"
}

# Which provider this repository talks to: 'gh' or 'glab'.
#
# Order matters. An explicit choice wins, because a self-hosted GitLab can sit
# on any hostname and no amount of sniffing will guess 'git.example.com'. The
# remote is only consulted when nobody has said otherwise.
#
# Returns 1 when the host is not recognisable. Guessing there would be worse
# than failing: the wrong client produces a confusing error, while silence plus
# a usage line tells the user exactly which variable to set.
__forge_provider() {
    local forced="${FORGE_PROVIDER:-}"

    if [[ -z "$forced" ]]; then
        # 'config session igitari.forge glab' exports through GIT_CONFIG_*, so
        # a session override is readable exactly like a real git setting.
        forced=$(git config --get igitari.forge 2>/dev/null)
    fi

    forced="${forced,,}"
    case "$forced" in
    gh | github)
        echo gh
        return 0
        ;;
    glab | gitlab)
        echo glab
        return 0
        ;;
    "") : ;;
    *)
        # Said something we do not understand. Do not fall through to sniffing:
        # a typo in the override must not be silently ignored.
        return 1
        ;;
    esac

    local host
    host=$(__forge_remote_host origin) || return 1

    case "$host" in
    github.com | *.github.com | github.*)
        echo gh
        return 0
        ;;
    gitlab.com | *.gitlab.com | gitlab.*)
        echo glab
        return 0
        ;;
    *) return 1 ;;
    esac
}

# Path of the provider's client, printing nothing when it is not installed.
__forge_bin() {
    local provider
    provider=$(__forge_provider) || return 1
    command -v "$provider" 2>/dev/null
}

# True when a forge can actually be reached: provider known, client installed.
# Silent -- callers are expected to produce the wording.
__forge_available() {
    __forge_bin >/dev/null 2>&1
}

# Split a forge object ('pr:32') into its kind and its id.
#
# The kind is what the caller validates against the verb it is about to run.
# The id is passed through untouched, because the client is the authority on
# what a valid number looks like -- and because guessing there would reject
# forms like 'release:v2.0' or 'pr:owner/repo#12'.
#
# Usage: __forge_parse_object "<object>" <kind-var> <id-var>
# Returns 1 when the object is not of the form kind:id.
__forge_parse_object() {
    local object="$1"
    local -n _fkind="$2"
    local -n _fid="$3"
    _fkind=""
    _fid=""

    [[ "$object" == *:* ]] || return 1
    _fkind="${object%%:*}"
    _fid="${object#*:}"

    [[ -z "$_fkind" || -z "$_fid" ]] && return 1
    # One token, a word of lowercases for the kind, and no whitespace anywhere
    # -- an object is never a phrase, and it is never a path with a space.
    [[ "$_fkind" =~ ^[a-z]+$ ]] || return 1
    [[ "$_fid" =~ ^[A-Za-z0-9._/-]+$ ]] || return 1
    return 0
}

# Which object kind a source word stands for, in the provider's own spelling.
# 'prs' is a pull request on GitHub and a merge request on GitLab, and the
# colon noun has to match the tool the user will look up in the docs.
__forge_object_kind() {
    local source="$1"
    local provider
    provider=$(__forge_provider 2>/dev/null) || return 1

    case "$source" in
    prs)
        [[ "$provider" == "glab" ]] && echo mr || echo pr
        ;;
    issues) echo issue ;;
    discussions) echo discussion ;;
    *) return 1 ;;
    esac
}

# List objects, normalised to one per line:
#
#   <number> TAB <title>
#
# This is the only place that knows what gh or glab actually print. The UI
# layer gets a stable shape and never parses a provider's output itself.
#
# On failure: nothing on stdout, non-zero status. The caller owns the wording,
# same as the rest of this tier.
__forge_list() {
    local source="$1" # prs | issues | discussions
    local limit="${FORGE_LIMIT:-30}"
    local bin provider
    bin=$(__forge_bin) || return 1
    provider=$(__forge_provider) || return 1

    case "$provider" in
    gh)
        # --template keeps this dependency-free: no jq, and no JSON in Bash.
        case "$source" in
        prs)
            "$bin" pr list --limit "$limit" --json number,title \
                --template '{{range .}}{{.number}}{{"\t"}}{{.title}}{{"\n"}}{{end}}'
            ;;
        issues)
            "$bin" issue list --limit "$limit" --json number,title \
                --template '{{range .}}{{.number}}{{"\t"}}{{.title}}{{"\n"}}{{end}}'
            ;;
        discussions)
            # gh wraps these in {"discussions": [...]}, unlike the others.
            "$bin" discussion list --limit "$limit" --json number,title \
                --template '{{range .discussions}}{{.number}}{{"\t"}}{{.title}}{{"\n"}}{{end}}'
            ;;
        *) return 1 ;;
        esac
        ;;
    glab)
        # See __forge_list_glab: JSON preferred, table as a fallback, nothing
        # at all rather than something wrong.
        __forge_list_glab "$source" "$limit" "$bin" || return 1
        ;;
    *) return 1 ;;
    esac
}

# glab's JSON output is a contract; its table output is a guess. Prefer the
# former, fall back to the latter, and print nothing at all if neither parses.
#
# The JSON path is verified against glab 1.128.0 and a public project: the
# output is the GitLab API's own, with 'iid' before 'title'. The table fallback
# has only ever been exercised by tests -- reaching it needs a glab too old for
# --output json -- so it stays a guess, pinned by tests/cases/forge.sh.
#
# The failure mode is deliberate: an unparseable listing prints nothing, so the
# picker says there is nothing to pick. Wrong numbers would be worse than none.
__forge_list_glab() {
    local source="$1" limit="$2" bin="$3"
    local out=""

    case "$source" in
    prs) out=$("$bin" mr list --per-page "$limit" --output json 2>/dev/null) ;;
    issues | discussions) out=$("$bin" issue list --per-page "$limit" --output json 2>/dev/null) ;;
    *) return 1 ;;
    esac

    if [[ -n "$out" ]]; then
        local parsed
        # GitLab puts 'iid' (the per-project number users see as !12) before
        # 'title' in each object. Pair them in one pass, no jq required.
        # Newlines removed first: glab's JSON may be pretty-printed, and the
        # pairing below walks iid -> title in document order.
        parsed=$(printf '%s' "$out" | tr -d '\n' | awk '
            {
                rest = $0
                while (match(rest, /"iid"[ ]*:[ ]*[0-9]+/)) {
                    id = substr(rest, RSTART, RLENGTH)
                    gsub(/[^0-9]/, "", id)
                    rest = substr(rest, RSTART + RLENGTH)
                    if (match(rest, /"title"[ ]*:[ ]*"[^"]*"/)) {
                        title = substr(rest, RSTART, RLENGTH)
                        sub(/.*"title"[ ]*:[ ]*"/, "", title)
                        sub(/"$/, "", title)
                        # A title with an escaped quote ends the match early; drop the
                        # trailing escape rather than print a stray backslash.
                        sub(/\\$/, "", title)
                        printf "%s\t%s\n", id, title
                        rest = substr(rest, RSTART + RLENGTH)
                    } else break
                }
            }')

        # Non-empty JSON that yields no pairs is not a listing: it is a
        # message, a version mismatch, or a format change. Fall through.
        if [[ -n "$parsed" ]]; then
            printf '%s\n' "$parsed"
            return 0
        fi
    fi

    # Older glab, or one without --output json: fall back to the table.
    local table
    case "$source" in
    prs) table=$("$bin" mr list --per-page "$limit" 2>/dev/null) ;;
    issues | discussions) table=$("$bin" issue list --per-page "$limit" 2>/dev/null) ;;
    *) return 1 ;;
    esac

    table=$(printf '%s\n' "$table" |
        sed -n 's/^[!#]\{0,1\}\([0-9][0-9]*\)[[:space:]]\{1,\}[[:space:]]*\(.*\)$/\1\t\2/p')

    # Nothing parsed means the format moved. Say so by failing, not by
    # returning an empty success the caller would read as "no pull requests".
    [[ -n "$table" ]] || return 1
    printf '%s\n' "$table"
}

# Run a provider verb against one object.
#
# The noun is the only thing translated: 'pr' and 'mr' both become the
# provider's own word for the object, and every trailing argument is passed
# through untouched. No flag is ever invented here, so the client's own docs
# stay correct and a wrong flag fails with the client's own error.
#
# Usage: __forge_call <verb> <kind> <id> [args...]
__forge_call() {
    local verb="$1" kind="$2" id="$3"
    shift 3

    local bin provider sub
    bin=$(__forge_bin) || return 1
    provider=$(__forge_provider) || return 1

    case "$provider:$kind" in
    gh:pr | gh:mr) sub="pr" ;;
    gh:issue) sub="issue" ;;
    glab:pr | glab:mr) sub="mr" ;;
    glab:issue) sub="issue" ;;
    *) return 1 ;;
    esac

    # glab reports pipelines, not checks, and a pipeline belongs to a branch
    # rather than to a merge request. So the object is honoured by resolving it
    # to its source branch first: 'forge checks mr:5' asks about the pipeline
    # that MR actually runs. The one case this cannot reach is an MR from a
    # fork, whose pipeline lives in the fork's project; glab's own answer there
    # is honest, and forge says so when the branch cannot be read at all.
    if [[ "$provider:$verb" == "glab:checks" ]]; then
        local branch
        branch=$("$bin" mr view "$id" --output json 2>/dev/null |
            awk 'match($0, /"source_branch"[ ]*:[ ]*"[^"]*"/) {
                     s = substr($0, RSTART, RLENGTH)
                     sub(/.*:[ ]*"/, "", s)
                     sub(/"$/, "", s)
                     print s
                     exit
                 }')
        [[ -n "$branch" ]] || return 3
        "$bin" ci status --branch "$branch" "$@" || return 4
        return 0
    fi

    # The client's word for the verb, where the two disagree: glab says
    # 'note', 'update' and 'approve' where gh says 'comment', 'edit' and
    # 'review'. A verb name is translated because it is the part the user is
    # asking Igitari for; a flag is not, because flags are what they read in
    # the client's own manual.
    case "$provider:$verb" in
    glab:comment) verb="note" ;;
    glab:edit) verb="update" ;;
    glab:review) verb="approve" ;;
    glab:ready)
        verb="update"
        set -- "$@" --ready # glab's spelling of the same request
        ;;
    esac

    if [[ -n "$id" ]]; then
        "$bin" "$sub" "$verb" "$id" "$@"
    else
        "$bin" "$sub" "$verb" "$@"
    fi
}

#--|EXTRAS                                                           [IGITARI]
#------------------------------------------------------------------------------
# Custom features
#------------------------------------------------------------------------------

## FZF-dependent features
# Requires fzf to be installed on system but will not affect overall functionality.
__check_fzf() {
    if ! command -v fzf &>/dev/null; then
        echo -e "\e[93m\e[1mWarning: You're accessing fzf-based features but it's not installed on your system! The command name should've been obvious though :/ \e[0m"
        return 1
    fi

}

# Forge-dependent features
# Same contract as fzf: an optional door. Missing provider or client is one
# line and a non-zero status, and nothing else in Igitari notices.
__check_forge() {
    local provider

    if ! provider=$(__forge_provider 2>/dev/null) || [[ -z "$provider" ]]; then
        echo -e "\e[93m\e[1mThis isn't a forge I can talk to.\e[0m"
        echo "  Neither origin's host nor FORGE_PROVIDER says GitHub or GitLab."
        echo "  If it is one, say so: config session igitari.forge gh"
        return 1
    fi

    if ! __forge_available; then
        echo -e "\e[93m\e[1m'$provider' is not installed.\e[0m"
        echo "  That's the client Igitari uses to reach ${provider}."
        return 1
    fi

    return 0
}

# Override normal fzf for git-specialised operations
# shellcheck disable=SC2016
# shellcheck disable=SC2329
# fzf [type] [return]
fzf() {
    __check_fzf || return 1

    sys_fzf=$(which fzf)

    # Apparently you can't easily use a variable and suddenly use it as a command
    sys_fzf() {
        "$sys_fzf" "$@"
    }

    build_helptext() {
        helptext_top="fzf (commits | tags | reflogs | staged | unstaged | tracked | untracked | stashes | dangling | prs | issues | discussions) [returns]\n"
        helptext_returntype=("Return types:"
            "   commits (sha | message | diffs)"
            "   tags (sha | name)"
            "   reflogs (sha | message | diffs)"
            "   stashes (ref | diff | name)"
            "   dangling (sha | type | content | message)"
            "   prs (number | ref)"
            "   issues (number | ref)"
            "   discussions (number | ref)"
            "\nstaged/unstaged/tracked/untracked doesn't take a return type")

        # Join with newlines
        printf "%b\n" "$helptext_top" "${helptext_returntype[@]}"
    }

    fzf_logcommits() {

        __fzf-exec() {
            sys_fzf --height=25% \
                --layout=reverse \
                --ansi \
                --prompt "Select a commit: " \
                --preview='git show --color=always {1}' \
                --pointer '  '
        }

        selected_commit=$(git log --oneline --color=always | __fzf-exec)

        # Extract the short SHA from the selected commit
        short_sha=${selected_commit%% *}

        # Return the requested value, short_sha by default
        case "$1" in
        sha) echo "$short_sha" ;;
        message) git show -s --format='%s' "$short_sha" ;;
        diffs) git show --color=always "$short_sha" ;;
        *) echo "$short_sha" ;;
        esac
    }

    fzf_reflogs() {

        __fzf-exec() {
            sys_fzf --height=25% \
                --layout=reverse \
                --ansi \
                --prompt "Search last HEAD location: " \
                --preview='git show --color=always {1}' \
                --pointer '  '
        }

        selected_location=$(git reflog --color=always | __fzf-exec)

        # Extract the short SHA from the selected commit
        short_sha=${selected_location%% *}

        # Return the requested value, short_sha by default
        case "$1" in
        sha) echo "$short_sha" ;;
        message) git show -s --format='%s' "$short_sha" ;;
        diffs) git show --color=always "$short_sha" ;;
        *) echo "$short_sha" ;;
        esac
    }

    fzf_stashlist() {

        __fzf-exec() {
            sys_fzf --height=25% \
                --layout=reverse \
                --ansi \
                --prompt "Select a stash: " \
                --preview='git stash show --color=always {1}' \
                --pointer '  '
        }
        stash_list=$(git stash list)

        if [[ -z $stash_list ]]; then
            echo "There are no stashes to show!"
            return 1
        fi

        selected_stash=$(echo "$stash_list" | __fzf-exec)

        # Extract the short SHA from the selected stash (strip trailing colon)
        stash_ref=$(echo "$selected_stash" | cut -d' ' -f1 | sed 's/:.*//')

        case $1 in
        ref) echo "$stash_ref" ;;
        diff) git stash show -p "$stash_ref" ;;
        name) git stash show -s --format='%s' "$stash_ref" ;;
        *) echo "$stash_ref" ;;
        esac
    }

    # the next 4 function are copy-pasted, which I do not give a fuck about to abstract
    fzf_stagedfile() {
        __fzf-exec() {
            sys_fzf --height=25% \
                --layout=reverse \
                --ansi \
                --multi \
                --prompt "Select staged files: " \
                --preview 'git diff --cached --color=always {}' \
                --pointer '  '
        }

        staged_filelist=$(git diff --cached --name-only)

        [[ -z $staged_filelist ]] && echo "There are no staged files!" && return 1

        selected_files=$(echo "$staged_filelist" | __fzf-exec)

        [[ -z $selected_files ]] && return 1

        # Probably fine stripping newlines; echo is ok
        echo "$selected_files"
    }

    fzf_unstagedfile() {
        __fzf-exec() {
            sys_fzf --height=25% \
                --layout=reverse \
                --ansi \
                --multi \
                --prompt "Select unstaged files: " \
                --preview 'git diff --color=always {}' \
                --pointer '  '
        }

        unstaged_filelist=$(git diff --name-only)

        [[ -z $unstaged_filelist ]] && echo "There are no unstaged files!" && return 1

        selected_files=$(echo "$unstaged_filelist" | __fzf-exec)

        [[ -z $selected_files ]] && return 1

        # Probably fine stripping newlines; echo is ok
        echo "$selected_files"
    }

    fzf_trackedfile() {
        __fzf-exec() {
            sys_fzf --height=25% \
                --layout=reverse \
                --ansi \
                --multi \
                --prompt "Select tracked files: " \
                --preview 'git diff --color=always {}' \
                --pointer '  '
        }

        tracked_filelist=$(git ls-files)

        [[ -z $tracked_filelist ]] && echo "There are no tracked files!" && return 1

        selected_files=$(echo "$tracked_filelist" | __fzf-exec)

        [[ -z $selected_files ]] && return 1

        # Probably fine stripping newlines; echo is ok
        echo "$selected_files"
    }

    fzf_untrackedfile() {
        __fzf-exec() {
            sys_fzf --height=25% \
                --layout=reverse \
                --ansi \
                --multi \
                --prompt "Select untracked files: " \
                --preview 'cat {}' \
                --pointer '  '
        }

        untracked_filelist=$(git ls-files --others --exclude-standard)

        [[ -z $untracked_filelist ]] && echo "There are no untracked files!" && return 1

        selected_files=$(echo "$untracked_filelist" | __fzf-exec)

        [[ -z $selected_files ]] && return 1

        # Probably fine stripping newlines; echo is ok
        echo "$selected_files"
    }

    fzf_dangles() {

        # 100% height is intentional to allow better previews
        __fzf-exec() {
            sys_fzf --height=100% \
                --layout=reverse \
                --ansi \
                --prompt "Select a dangling object: " \
                --preview='git show --color=always {2}' \
                --pointer '  '
        }

        fsck_list=$(git fsck --lost-found 2>/dev/null | awk '/dangling/ { print $2, $3 }')

        selected_object=$(echo "$fsck_list" | __fzf-exec)
        [[ -z $selected_object ]] && return 1

        # Extract the short SHA from the selected commit (herestrings)
        object_type=$(echo "$selected_object" | awk '{print $1}')
        object_sha=$(echo "$selected_object" | awk '{print $2}')

        case $1 in
        sha) echo "$object_sha" ;;
        type) echo "$object_type" ;;
        content) git show --color=always "$object_sha" 2>/dev/null ;;
        message)
            if [[ $object_type == commit ]]; then
                git log -1 --format='%s' "$object_sha" 2>/dev/null
            else
                echo "<Expected commit object; got $object_type instead.>" 1>&2
            fi
            ;;
        *) echo "$object_sha" ;;
        esac

    }

    fzf_tags() {
        __fzf-exec() {
            sys_fzf --height=25% \
                --layout=reverse \
                --ansi \
                --prompt "Select a tag: " \
                --preview='git show --color=always {1}' \
                --pointer '  '
        }

        tag_list=$(git tag -l)

        if [[ -z $tag_list ]]; then
            echo -e "\e[91m\e[1mError: No tags found in the repository.\e[0m"
            return 1
        fi

        selected_tag=$(echo "$tag_list" | __fzf-exec)
        [[ -z $selected_tag ]] && return 1

        # Extract the short SHA from the selected tag (herestrings)
        tag_sha=$(git rev-parse "$selected_tag")

        case $1 in
        sha) echo "$tag_sha" ;;
        name) echo "$selected_tag" ;;
        *) echo "$tag_sha" ;;
        esac

    }

    fzf_forge() {
        local source="$1" returntype="${2:-number}"

        __check_forge || return 1

        local list
        list=$(__forge_list "$source") || {
            echo "Error: could not list $source." >&2
            return 1
        }

        if [[ -z "$list" ]]; then
            echo "There is nothing to pick from -- no open $source."
            return 1
        fi

        # No --preview on purpose: a preview would run a provider command per
        # cursor move, which is a network call per keystroke and a rate limit
        # waiting to happen.
        local selected
        selected=$(printf '%s\n' "$list" | sys_fzf \
            --height=25% \
            --layout=reverse \
            --prompt "Select ($source): " \
            --pointer '  ')
        [[ -z "$selected" ]] && return 1

        local number="${selected%%$'\t'*}"
        case "$returntype" in
        number) echo "$number" ;;
        ref) echo "$(__forge_object_kind "$source"):${number}" ;;
        *) echo "$number" ;;
        esac
    }

    # Defaulted, not bare $2: every source is legal with no return type, and
    # under 'set -u' a missing one aborted the whole picker.
    local returntype="${2:-}"

    case $1 in
    commits*) fzf_logcommits $returntype ;;
    tags*) fzf_tags $returntype ;;
    reflogs*) fzf_reflogs $returntype ;;
    staged) fzf_stagedfile ;;
    unstaged) fzf_unstagedfile ;;
    tracked) fzf_trackedfile ;;
    untracked) fzf_untrackedfile ;;
    stashes*) fzf_stashlist $returntype ;;
    dangling*) fzf_dangles $returntype ;;
    prs*) fzf_forge prs $returntype ;;
    issues*) fzf_forge issues $returntype ;;
    discussions*) fzf_forge discussions $returntype ;;
    *) build_helptext 1>&2 && return 1 ;;
    esac
}

# Turn a remote URL into a browser-openable https URL.
#
# git hands back whatever the user cloned with, and only one of those forms is
# something a browser understands. The four shapes seen in the wild:
#
#   https://host/user/repo(.git)   already fine
#   http://host/user/repo(.git)    fine, and worth upgrading to https
#   git@host:user/repo(.git)       scp syntax -- no scheme, colon separator
#   ssh://git@host[:port]/user/repo   real URL, ssh scheme
#
# The ssh forms carry no port a web server would use, so the port is dropped
# rather than carried over: :2222 is the sshd, not the HTTP listener.
#
# Prints the URL and returns 0, or prints nothing and returns 1 when the
# remote is a local path -- a folder has no web page to open.
#
# Usage: __remote_to_web_url <remote-url>
__remote_to_web_url() {
    local url="$1"

    case "$url" in
        # Local paths and file:// remotes: nothing to open.
        file://* | /* | ./* | ../*)
            return 1
            ;;

        # scp-like: [user@]host:path. The colon is what makes it scp syntax,
        # so it has to be tested before the generic schemes below -- there is
        # no '://' to match on here.
        *://*)
            # A real URL. Strip the scheme and any userinfo, then the port.
            url="${url#*://}"
            url="${url#*@}"
            # Optional :port before the first slash.
            if [[ "${url%%/*}" == *:* ]]; then
                local host_and_port="${url%%/*}"
                url="${host_and_port%%:*}/${url#*/}"
            fi
            ;;

        *@*:*)
            # scp-like with a user: user@host:path
            url="${url#*@}"
            url="${url%%:*}/${url#*:}"
            ;;

        *:*)
            # scp-like without a user: host:path
            url="${url%%:*}/${url#*:}"
            ;;

        *)
            # Bare host/path with no scheme. Treat it as https.
            ;;
    esac

    # A local path can also arrive userless and schemeless as /srv/git/x.git,
    # which the first case already caught. Anything left with no host is not
    # a URL, so refuse rather than hand xdg-open a relative path.
    [[ -z "$url" ]] && return 1

    # GitHub and friends all serve .git-less URLs; a trailing .git is a clone
    # URL, not a page.
    url="${url%.git}"

    printf 'https://%s\n' "$url"
}

# Open repository in web browser
# Usage: openweb [remote] [page]
# Pages: issues, pr, pull-request, wiki, settings
openweb() {
    local remote="${1:-}"
    local page="${2:-}"
    local sub="${3:-}"

    # Validate input
    if [[ -z "$remote" ]]; then
        echo "SYNTAX: openweb [remote] [issues|discussions|releases|pr|mrs|prs|pr create|compare|wiki|settings] [number]"
        return 1
    fi

    # Get remote URL
    local remote_url
    remote_url=$(git remote get-url "$remote" 2>/dev/null)

    if [[ -z "$remote_url" ]]; then
        echo -e "\e[91m\e[1mError: ...'$remote''s URL is empty?? See if it exists (simple type 'remote') \e[0m"
        echo "SYNTAX: openweb [remote] [issues|discussions|releases|pr|mrs|prs|pr create|compare|wiki|settings] [number]"
        return 1
    fi

    # A clone URL is not a web page: git@host:user/repo has no scheme and
    # would be handed to xdg-open as a relative filename.
    if ! remote_url=$(__remote_to_web_url "$remote_url"); then
        echo -e "\e[91m\e[1mError: '$remote' is a local path, not a hosted remote -- there's no page to open.\e[0m"
        return 1
    fi

    log "Base URL: ${remote_url}"

    # Forges spell pages differently. '/issues' and '/compare' are near
    # universal, but the pull-request list is not: GitLab calls it merge
    # requests, Bitbucket calls it pull-requests. Deriving it from the host
    # beats defaulting to GitHub's word and handing half the world a 404.
    # Forges spell their paths differently. '/issues' and '/compare' are near
    # universal, but the pull-request list is not: GitLab calls it merge
    # requests, Bitbucket calls it pull-requests. Deriving it from the host
    # beats defaulting to GitHub's word and handing half the world a 404.
    #
    # 'seg' is GitLab's '/-/' prefix. It is not cosmetic: the numbered forms
    # (/-/issues/553, /-/releases/v2.0) only exist under it, and without it
    # GitLab answers with a redirect or a 404 depending on the version.
    local pr_path="pulls"
    local wiki_path="wiki"
    local issues_path="issues"
    local releases_path="releases"
    local discussions_path="discussions"
    local seg=""
    case "${remote_url#https://}" in
    gitlab.com/* | *gitlab.*)
        pr_path="merge_requests"
        wiki_path="wikis"
        releases_path="releases"
        # GitLab has no separate discussions list; issues carry the threads.
        discussions_path="issues"
        seg="/-"
        ;;
    bitbucket.org/* | *bitbucket.*)
        pr_path="pull-requests"
        ;;
    esac

    # One number, when the page takes one. 'create'/'new' are words, not
    # numbers, so a sub for 'pr create' is never mistaken for a PR id.
    local number=""
    case "$page" in
    issues | pr | pull-request | prs | mr | mrs | discussions)
        [[ "$sub" =~ ^[0-9]+$ ]] && {
            number="$sub"
            sub=""
        }
        ;;
    releases)
        # A tag, not a number: v2.0 is as valid as 3.
        [[ -n "$sub" && "$sub" != "create" && "$sub" != "new" ]] && {
            number="$sub"
            sub=""
        }
        ;;
    esac
    local num_suffix="${number:+/${number}}"
    # Only numbered forms take GitLab's '/-/' prefix. The bare list pages keep
    # their old spelling: both answer 200 through a redirect, and changing a
    # URL nobody complained about is not this feature's business.
    local num_seg="${number:+${seg}}"

    case "$page" in
    "issues") remote_url+="${num_seg:-}/${issues_path}${num_suffix}" ;;
    "pr" | "pull-request" | "prs" | "mr" | "mrs")
        # 'mr'/'mrs' is GitLab's word for the same thing. Accepting it costs
        # nothing and saves a GitLab user from discovering the vocabulary
        # mismatch at the moment they wanted to open something.
        # 'pr create' lands on the compare page, which is where the new-pull
        # form lives. GitHub and Gitea both do it that way.
        if [[ "$sub" == "create" || "$sub" == "new" ]]; then
            remote_url+="/compare"
        else
            remote_url+="${num_seg:-}/${pr_path}${num_suffix}"
        fi
        ;;
    "discussions" | "discussion")
        remote_url+="${num_seg:-}/${discussions_path}${num_suffix}"
        ;;
    "releases")
        # GitHub's front page is /releases; a single one is /releases/tag/<tag>.
        if [[ -n "$number" && -z "$seg" ]]; then
            remote_url+="/${releases_path}/tag/${number}"
        else
            remote_url+="${num_seg:-}/${releases_path}${num_suffix}"
        fi
        ;;
    "compare") remote_url+="/compare" ;;
    "wiki") remote_url+="/${wiki_path}" ;;
    "settings") remote_url+="/settings" ;; # GitLab's real path is /edit, and
                                                   # guessing it would be worse
                                                   # than the existing redirect.
    "") : ;; # No page specified
    *) echo "Error: Unknown page '$page'" && return 1 ;;
    esac

    # Open URL in default browser (cross-platform)
    if command -v xdg-open >/dev/null; then
        log "Opening with xdg-open (Linux)"
        xdg-open "$remote_url" >/dev/null 2>&1 &
    elif command -v open >/dev/null; then
        log "Opening with open (macOS)"
        open "$remote_url"
    elif command -v cmd.exe >/dev/null; then
        log "Opening with cmd (Windows)"
        cmd.exe /C start "" "$remote_url"
    else
        echo -e "\e[91m\e[1mError: Eh?! What the heck is this OS? I can't find a way to open a browser in your system!\e[0m"
        return 1
    fi

    echo "Opened: $remote_url"
    echo "Check your browser, or Ctrl+click this link to open manually."
}

# Which object kinds a forge verb takes. Kept next to the verbs themselves so
# the answer to 'what can I close?' is one screen away from the answer to
# 'what does close do?'.
#
# The list is deliberately short and checked before any network call: a typo in
# the object kind must not become a provider command about the wrong thing.
__forge_verb_accepts() {
    local verb="$1" kind="$2"

    case "$verb" in
    checkout) [[ "$kind" == "pr" || "$kind" == "mr" || "$kind" == "release" ]] ;;
    merge | review | ready | diff | checks | revert)
        [[ "$kind" == "pr" || "$kind" == "mr" ]]
        ;;
    close | comment | reopen | edit | lock)
        [[ "$kind" == "pr" || "$kind" == "mr" || "$kind" == "issue" ]]
        ;;
    create) [[ "$kind" == "pr" || "$kind" == "mr" || "$kind" == "issue" ]] ;;
    delete) [[ "$kind" == "issue" ]] ;;
    *) return 1 ;;
    esac
}

# Verbs that a provider simply does not have. Refusing with the client's own
# alternative is more useful than letting the client call it an unknown command,
# which reads like the user made a typo.
__forge_verb_supported() {
    local provider="$1" verb="$2"

    if [[ "$provider" == "glab" ]]; then
        case "$verb" in
        lock | revert) return 1 ;;
        esac
    fi
    return 0
}

__forge_verb_hint() {
    local provider="$1" verb="$2"

    case "$provider:$verb" in
    glab:lock) echo "glab has no 'lock' subcommand; see 'glab mr update --help'." ;;
    glab:revert) echo "glab has no 'revert'; revert with git, then open a merge request." ;;
    *) echo "$provider has no '$verb' for that object." ;;
    esac
}

# The verbs that change something someone else can see, or throw work away.
# These ask first.
__forge_verb_is_destructive() {
    case "$1" in
    checkout | merge | close | revert | delete) return 0 ;;
    *) return 1 ;;
    esac
}

forge() {
    local verb="${1:-}"

    if [[ -z "$verb" || "$verb" == "-h" || "$verb" == "--help" ]]; then
        show_command_help "forge"
        return 0
    fi

    shift || true
    local object="${1:-}"
    [[ $# -gt 0 ]] && shift
    local -a args=("$@")

    # Third-party clients are a door, not a wall: say what is missing once and
    # stop. Nothing about git or the rest of Igitari is affected either way.
    __check_forge || return 1

    # -y/--yes is ours, so it never reaches the provider. Everything else is
    # passed through untouched -- translating flags would build a dialect of
    # the client, which is exactly what this namespace exists to avoid.
    local assume_yes=0
    local -a passthrough=()
    local a
    if [[ ${#args[@]} -gt 0 ]]; then
        for a in "${args[@]}"; do
            case "$a" in
            -y | --yes) assume_yes=1 ;;
            *) passthrough+=("$a") ;;
            esac
        done
    fi

    local kind="" id=""

    if [[ "$verb" == "create" ]]; then
        # 'create' takes a kind, not an object: forge create issue
        kind="$object"
        case "$kind" in
        issue | pr | mr) : ;;
        *)
            echo "Error: 'create' needs a kind: forge create issue|pr|mr" >&2
            return 1
            ;;
        esac
    else
        if ! __forge_parse_object "$object" kind id; then
            echo "Error: '$object' is not a forge object. Expected pr:32, mr:32, issue:812, release:v2.0." >&2
            return 1
        fi

        if ! __forge_verb_accepts "$verb" "$kind"; then
            if __forge_verb_accepts "$verb" "pr"; then
                echo "Error: '$verb' does not take a '$kind'. It takes a pull request." >&2
            elif __forge_verb_accepts "$verb" "issue"; then
                echo "Error: '$verb' does not take a '$kind'. It takes an issue." >&2
            else
                echo "Error: '$verb' is not a forge verb. Try checkout, close, comment, merge, review, ready, reopen, edit, lock, diff, checks, revert, create or delete." >&2
            fi
            return 1
        fi
    fi

    local provider
    provider=$(__forge_provider) || return 1
    if ! __forge_verb_supported "$provider" "$verb"; then
        echo "Error: $(__forge_verb_hint "$provider" "$verb")" >&2
        return 1
    fi

    if __forge_verb_is_destructive "$verb" && ((!assume_yes)); then
        __igitari_confirm "Really ${verb} ${object}?" || {
            echo "Left it to you."
            return 1
        }
    fi

    if [[ "$kind" == "release" ]]; then
        # A release is not a provider-side verb: the tag has to be local, and
        # then checking it out is git's job, not the client's.
        local bin
        bin=$(__forge_bin) || return 1
        if [[ "$(__forge_provider)" == gh ]]; then
            "$bin" release view "$id" --json tagName >/dev/null 2>&1 || {
                echo "Error: no release '$id' on the remote." >&2
                return 1
            }
        else
            "$bin" release view "$id" >/dev/null 2>&1 || {
                echo "Error: no release '$id' on the remote." >&2
                return 1
            }
        fi
        git fetch --tags --quiet 2>/dev/null
        git checkout "$id"
        return $?
    fi

    local status=0
    if [[ ${#passthrough[@]} -gt 0 ]]; then
        __forge_call "$verb" "$kind" "$id" "${passthrough[@]}"
        status=$?
    else
        __forge_call "$verb" "$kind" "$id"
        status=$?
    fi

    if ((status == 3)); then
        echo "Error: could not read ${object}'s source branch, so there is no pipeline to ask about." >&2
        return 1
    fi
    if ((status == 4)); then
        # GitLab keeps a fork's pipelines in the fork's project, and the client
        # cannot be told that without a token. Say the likely reason instead of
        # letting a bare 404 stand as the whole answer.
        echo "No pipeline found for ${object}'s source branch. If it comes from a fork," >&2
        echo "its pipeline lives there: glab ci status --branch <branch> -R <fork>." >&2
        return 1
    fi
    return "$status"
}

# ------------------------------------------------------
# Integrity verification system for git files
# ------------------------------------------------------
verify_gitfiles() {
    local file="$1"

    case "$file" in
        *.mbox)
            local tmp_dir
            tmp_dir=$(mktemp -d)

            log "Checking mbox integrity: $file"

            local count
            count=$(git mailsplit -o "$tmp_dir" "$file" 2>/dev/null)
            local status=$?

            if [ $status -eq 0 ] && [ "$count" -gt 0 ]; then
                log "Mbox is valid. Contains $count patch(es)."
                rm -rf "$tmp_dir"
                return 0
            else
                log "Mbox is corrupted, empty, or improperly formatted."
                rm -rf "$tmp_dir"
                return 1
            fi
            ;;

        *.bundle)
            log "Checking bundle integrity: $file"

            if git bundle verify "$file" 2>/dev/null; then
                log "Bundle is valid and intact."
                return 0
            else
                log "Bundle is corrupted or invalid."
                return 1
            fi
            ;;

        # patch and diff file interchangeably may contain format-patch or raw diff
        # this is general integrity checker; not this function's concern.
        *.patch | *.diff)
            log "Checking structural integrity: $file"

            if ! git apply --stat "$file" > /dev/null 2>&1; then
                log "Integrity check failed: File is corrupted, truncated, or not a valid diff/patch."
                return 1
            fi

            log "Structural integrity verified (valid diff syntax)."
            return 0
            ;;

        *)
            log "Error: Unsupported file type for '$file'. Expected .mbox, .bundle, .patch, or .diff"
            return 1
            ;;
    esac
}

differentiate_patchdiff() {
    local file="$1" # File existence already checked

    # git format-patch outputs standard mbox email headers.
    # The most reliable indicators are 'From <hash>' (the envelope sender)
    # and 'Subject: [PATCH' (the patch subject line).
    # A raw diff will start with 'diff --git' or '--- a/' and lack these.

    if grep -m 1 -qE "^(From [0-9a-f]{7,40} Mon Sep 17 00:00:00 2001|Subject: \[PATCH)" "$file"; then
        echo "mbox"
    else
        echo "raw"
    fi
}

show_stat_gitfile() {
    local file="$1"
    local ext="${file##*.}"

    echo ""
    echo -e "\e[1mFile: ${file}\e[0m"
    echo ""

    case "${ext}" in
        mbox)
            echo -e "\e[93mType:\e[0m mbox (format-patch email)"
            local count
            count=$(git mailsplit -o "$(mktemp -d)" "$file" 2>/dev/null | wc -l)
            echo -e "\e[93mPatches:\e[0m ${count:-?}"
            echo -e "\e[93mAction:\e[0m git am (will create commits)"
            ;;
        bundle)
            echo -e "\e[93mType:\e[0m bundle"
            echo -e "\e[93mContents:\e[0m"
            git bundle verify "$file" 2>&1 | head -5
            echo -e "\e[93mAction:\e[0m git fetch (updates remote refs, no commits)"
            ;;
        patch|diff)
            local kind
            kind=$(differentiate_patchdiff "$file")
            if [[ "${kind}" == "mbox" ]]; then
                echo -e "\e[93mType:\e[0m format-patch (mbox headers detected)"
                echo -e "\e[93mAction:\e[0m git am (will create commits)"
            else
                echo -e "\e[93mType:\e[0m raw ${ext}"
                echo -e "\e[93mStat:\e[0m"
                git apply --stat "$file" 2>/dev/null
                echo -e "\e[93mAction:\e[0m git apply (modifies working tree only)"
            fi
            ;;
    esac
    echo ""
}

prompt_user_apply_gitfile() {
    local file="$1"
    local ext="${file##*.}"

    local action
    case "${ext}" in
        mbox|patch|diff)
            local kind
            kind=$(differentiate_patchdiff "${file}" 2>/dev/null || echo "raw")
            if [[ "${ext}" == "mbox" || "${kind}" == "mbox" ]]; then
                action="am (apply and create commits)"
            else
                action="apply (working tree only)"
            fi
            ;;
        bundle)
            action="fetch (update remote refs)"
            ;;
        *)
            action="apply"
            ;;
    esac

    read -r -p "Apply with git ${action}? (y/n) " confirm </dev/tty
    [[ "${confirm}" =~ ^[Yy] ]]
}

apply_gitfile() {
    local file="$1"
    local ext="${file##*.}"

    case "${ext}" in
        mbox)
            git am "${file}"
            ;;
        bundle)
            git fetch "${file}"
            ;;
        patch|diff)
            local kind
            kind=$(differentiate_patchdiff "$file")
            if [[ "${kind}" == "mbox" ]]; then
                git am "${file}"
            else
                git apply "${file}"
            fi
            ;;
        *)
            echo -e "\e[91mError: Unknown file type .${ext}\e[0m"
            return 1
            ;;
    esac
}

# Initialise keybinds
# This is for non-core features that users can simply add.
# Interactive mode only!
initialise_keybinds() {
    # Don't initialise on non-interactive mode
    if [[ $- != *i* ]]; then
        return
    fi

    #-----------------#
    #     Macros      #
    #-----------------#

    # This is for more advanced operations that require more than executing single-line commands.

    f_lazygit() {
        if command -v lazygit >/dev/null 2>&1; then
            lazygit
        fi
    }

    ### Keybind setup

    # Refer to https://www.gnu.org/software/bash/manual/html_node/Bindable-Readline-Commands.html
    # OR https://www.geeksforgeeks.org/linux-unix/bind-command-in-linux-with-examples/ for usage

    # CTRL + G
    bind -x '"\C-g":f_lazygit'
}

# Hot-reload self
_reload() {
    echo "Reloading!"
    echo "________________________________________________________________"
    echo
    exec "$SELF_REALPATH" "${ARG[@]}"
}


#--|SESSION_CONFIG                                                   [IGITARI]
#------------------------------------------------------------------------------
# Session-scoped configuration
#------------------------------------------------------------------------------
#
# 'git config' reads and writes files. There is no scope for "this session
# only", which is the one scope you want when you are about to make a handful
# of commits as somebody else, or turn on a setting for one awkward rebase.
#
#   config session user.email me@example.com    Just this session
#   config session --list                       What have I overridden?
#   config session --unset user.email           Forget one override
#   config session --clear                      Forget them all
#
# Nothing is written to disk, by construction: the values live in an
# associative array and are handed to each git invocation through the
# environment. Exit Igitari and they are gone.
#
# 'session' reads as the fifth scope next to --local, --global and --system,
# which is why it is spelled as a scope rather than as its own verb.

# -g on purpose: this file is sometimes sourced from inside a function (the
# test harness does it per throwaway repo), and a plain 'declare -A' there
# creates a function-local array that dies when the caller returns, leaving
# SESSION_CONFIG as an indexed array that treats 'user.email' as arithmetic.
declare -gA SESSION_CONFIG=()

# Apply the session overrides to a git command's environment.
#
# GIT_CONFIG_COUNT is used rather than rewriting the command line: it applies
# to whatever git actually runs, including aliases and pipelines, and it
# cannot be confused by a value containing spaces. git ignores these
# variables when no overrides are set.
__session_config_export() {
    local key
    local n=0

    # Drop any pointers we exported last time. A shorter session must not
    # leave stale GIT_CONFIG_KEY_n entries behind from a longer one, or git
    # would keep honouring an override the user already removed.
    local previous="${__SESSION_CONFIG_EXPORTED:-0}"
    while ((n < previous)); do
        unset "GIT_CONFIG_KEY_${n}" "GIT_CONFIG_VALUE_${n}"
        ((n++))
    done
    unset GIT_CONFIG_COUNT __SESSION_CONFIG_EXPORTED

    if [[ ${#SESSION_CONFIG[@]} -eq 0 ]]; then
        return 0
    fi

    n=0
    for key in "${!SESSION_CONFIG[@]}"; do
        export "GIT_CONFIG_KEY_${n}=${key}"
        export "GIT_CONFIG_VALUE_${n}=${SESSION_CONFIG[$key]}"
        ((n++))
    done
    export GIT_CONFIG_COUNT="$n"
    __SESSION_CONFIG_EXPORTED="$n"
}

# Handle 'config session ...' before it reaches raw git, which has no such
# scope and would only say so unhelpfully.
#
# Returns 0 if the command was a session-config command and was handled,
# 1 if it was not (so the caller forwards it to git untouched).
__handle_session_config() {
    local cmd="$1"
    __SESSION_HANDLED=0

    # Segments arrive with surrounding whitespace from the operator splitter,
    # so trim before matching.
    cmd="${cmd#"${cmd%%[![:space:]]*}"}"
    cmd="${cmd%"${cmd##*[![:space:]]}"}"

    # Cheap prefix check so the common path costs nothing. The trailing
    # space-or-end matters: 'sessionary' is not our scope.
    case "$cmd" in
        config\ session|config\ session\ *) ;;
        *) return 1 ;;
    esac

    __SESSION_HANDLED=1

    local -a words=()
    __split_argv "$cmd" words || { __SESSION_HANDLED=0; return 1; }

    # words[0] is 'config', words[1] is 'session'. What follows is either a
    # flag (--list, --get ...) or, for a plain set, the key itself -- so the
    # third word is read as a potential flag and re-read as a key below.
    local action="${words[2]:-}"
    local key=""
    local value=""

    case "$action" in
        "")
            __session_config_list
            return 0
            ;;
        --list|-l)
            __session_config_list
            return 0
            ;;
        --clear)
            if [[ ${#SESSION_CONFIG[@]} -eq 0 ]]; then
                echo "No session overrides to clear."
            else
                SESSION_CONFIG=()
                __session_config_export
                echo "Cleared all session overrides."
            fi
            return 0
            ;;
        --unset)
            key="${words[3]:-}"
            if [[ -z "$key" ]]; then
                echo "Usage: config session --unset <key>"
                return 0
            fi
            if [[ -z "${SESSION_CONFIG[$key]+set}" ]]; then
                echo "'$key' is not overridden this session."
                # Return 1 so 'a || b' chains, the way a failed unset would.
                # The caller distinguishes "not mine" from "mine and failed"
                # by the __SESSION_HANDLED flag rather than the status.
                __SESSION_HANDLED=1
                return 1
            else
                unset 'SESSION_CONFIG[$key]'
                __session_config_export
                echo "Forgot the session override for '$key'."
            fi
            return 0
            ;;
        --get)
            key="${words[3]:-}"
            if [[ -z "$key" ]]; then
                echo "Usage: config session --get <key>"
                return 0
            fi
            if [[ -n "${SESSION_CONFIG[$key]+set}" ]]; then
                echo "${SESSION_CONFIG["$key"]}"
            else
                # Fall through to whatever git would say, so --get is always
                # answerable rather than only when something is overridden.
                __session_config_export
                git config --get "$key"
            fi
            return 0
            ;;
        -*) 
            echo "Unknown session config option: '$action'"
            echo "Try: config session <key> <value> | --list | --get <key> | --unset <key> | --clear"
            return 0
            ;;
    esac

    # A set: 'config session <key> [value]'. The third word is the key; the
    # value is everything after it, joined back together -- a display name or
    # a formatted value contains spaces, and splitting it would silently keep
    # only the first word.
    key="$action"
    if [[ ${#words[@]} -gt 3 ]]; then
        value="${words[*]:3}"
    else
        value=""
    fi

    if [[ -z "$key" ]]; then
        echo "Usage: config session <key> <value>"
        return 0
    fi

    # A bare key with no value reads it back, the way 'git config key' does.
    if [[ -z "$value" ]]; then
        if [[ -n "${SESSION_CONFIG[$key]+set}" ]]; then
            echo "${SESSION_CONFIG["$key"]}"
        else
            echo "'$key' is not overridden this session."
            return 0
        fi
        return 0
    fi

    local previous="${SESSION_CONFIG[$key]-}"
    SESSION_CONFIG["$key"]="$value"
    __session_config_export

    if [[ -n "$previous" ]]; then
        echo "Session: $key = $value   (was: $previous)"
    else
        echo "Session: $key = $value"
    fi
    echo "Applies until you exit Igitari. Nothing was written to disk."
    return 0
}

# Print the overrides in a stable order, with the value git would otherwise
# have used, so the difference is visible without checking.
__session_config_list() {
    if [[ ${#SESSION_CONFIG[@]} -eq 0 ]]; then
        echo "No session overrides. git is reading its own config files."
        return 0
    fi

    local key
    local -a keys=()
    for key in "${!SESSION_CONFIG[@]}"; do
        keys+=("$key")
    done
    mapfile -t keys < <(printf '%s\n' "${keys[@]}" | sort)

    for key in "${keys[@]}"; do
        local fallback
        fallback=$(env -u GIT_CONFIG_COUNT git config --get "$key" 2>/dev/null)
        if [[ -n "$fallback" ]]; then
            printf '%s = %s   (was: %s)\n' "$key" "${SESSION_CONFIG[$key]}" "$fallback"
        else
            printf '%s = %s\n' "$key" "${SESSION_CONFIG[$key]}"
        fi
    done
}

# Read a line of input, honouring '#' comments and trailing backslash.
#
# Both features need the same thing -- to know which characters are inside
# quotes -- so they share one scanner rather than each guessing with sed. A
# naive 's/#.*//' would cut 'commit -m "fix #123"' down to 'commit -m "fix ',
# silently changing a command before it runs, which is worse than the error
# you get from not supporting comments at all.
#
# Arguments:
#   $1  the raw line
# Sets:
#   READ_CMD  the line with comments removed and continuations joined
# Returns:
#   0 when a complete command was collected
#   1 when the line ended in an unquoted '\' (caller should read another)
#
# Never eval, never expand: this only inspects characters.
__join_continuation() {
    local line="$1"
    local out=""
    local in_single=0 in_double=0
    local i ch
    local len=${#line}

    for ((i = 0; i < len; i++)); do
        ch="${line:i:1}"

        if ((in_single)); then
            [[ "$ch" == "'" ]] && in_single=0
            out+="$ch"
            continue
        fi

        if ((in_double)); then
            # Inside double quotes a backslash only escapes '$', '`', '"', '\'
            # and newline, but for our purpose -- finding the closing quote --
            # skipping the next character is right, because '\\"' is a literal
            # backslash then a closing quote only if the author meant that.
            if [[ "$ch" == '\' ]]; then
                out+="$ch"
                ((i++))
                [[ $i -lt $len ]] && out+="${line:i:1}"
                continue
            fi
            [[ "$ch" == '"' ]] && in_double=0
            out+="$ch"
            continue
        fi

        case "$ch" in
            "'") in_single=1; out+="$ch" ;;
            '"') in_double=1; out+="$ch" ;;
            '#')
                # A comment runs to the end of the line. Not inside quotes,
                # which is the whole reason this is a scanner.
                break
                ;;
            '\')
                # A trailing backslash continues onto the next line; anywhere
                # else it is an escape and both characters are kept.
                if ((i == len - 1)); then
                    READ_CMD="$out"
                    return 1
                fi
                out+="$ch"
                ((i++))
                [[ $i -lt $len ]] && out+="${line:i:1}"
                ;;
            *) out+="$ch" ;;
        esac
    done

    READ_CMD="$out"
    return 0
}

#--|CMD_PROC_ENGINE                                                  [IGITARI]
#------------------------------------------------------------------------------
# Command Processing Engine
#------------------------------------------------------------------------------

# Split a command line into words the way a shell would: honour single and
# double quotes, and resolve $(...) by running the inner command through
# execute_command rather than eval.
#
# Quoting follows Bash: single quotes are literal, double quotes still expand
# $(...) and do not word-split the result, unquoted $(...) substitutes and
# then splits on whitespace.
#
# No eval anywhere. The text inside $(...) is handed to execute_command, so it
# can only be a command Igitari already knows about or a git subcommand.
#
# Usage: __split_argv "<line>" <outarray-name>
__split_argv() {
    local line="$1"
    local -n _out="$2"
    _out=()

    local word=""
    local have_word=0
    local i=0
    local len=${#line}
    local q=""          # active quote: '' for none, "'" or '"'
    local depth=0       # nested $( ) depth
    local subst=""      # captured $( ) contents

    while ((i < len)); do
        local ch="${line:i:1}"

        # Inside a substitution: capture until the matching close paren.
        if ((depth > 0)); then
            if [[ "$ch" == "(" ]]; then
                ((depth++))
                subst+="$ch"
            elif [[ "$ch" == ")" ]]; then
                ((depth--))
                if ((depth == 0)); then
                    local result
                    result=$(__subst_run "$subst")
                    if [[ "$q" == '"' ]]; then
                        # Inside double quotes: spliced, no word splitting.
                        word+="$result"
                        have_word=1
                    else
                        # Unquoted: split the result on whitespace.
                        if [[ -n "$result" ]]; then
                            local -a pieces
                            read -r -a pieces <<<"$result"
                            if (( ${#pieces[@]} > 0 )); then
                                # First piece continues the current word.
                                word+="${pieces[0]}"
                                have_word=1
                                local k
                                for ((k = 1; k < ${#pieces[@]}; k++)); do
                                    _out+=("$word")
                                    word="${pieces[$k]}"
                                done
                            fi
                        fi
                    fi
                    subst=""
                else
                    subst+="$ch"
                fi
            else
                subst+="$ch"
            fi
            ((i++))
            continue
        fi

        case "$ch" in
            "'")
                if [[ "$q" == "'" ]]; then
                    q=""
                elif [[ -z "$q" ]]; then
                    q="'"
                else
                    word+="$ch"
                fi
                have_word=1
                ;;
            '"')
                if [[ "$q" == '"' ]]; then
                    q=""
                elif [[ -z "$q" ]]; then
                    q='"'
                else
                    word+="$ch"
                fi
                have_word=1
                ;;
            '$')
                if [[ "${line:i+1:1}" == "(" && "$q" != "'" ]]; then
                    depth=1
                    subst=""
                    ((i += 2))
                    continue
                fi
                word+="$ch"
                have_word=1
                ;;
            ' '|$'\t')
                if [[ -n "$q" ]]; then
                    word+="$ch"
                elif ((have_word)); then
                    _out+=("$word")
                    word=""
                    have_word=0
                fi
                ;;
            *)
                word+="$ch"
                have_word=1
                ;;
        esac
        ((i++))
    done

    ((have_word)) && _out+=("$word")
    return 0
}

# Run a substituted command and hand back its output. Kept separate so the
# tokenizer stays readable and so this is the one place that decides how the
# inner command is invoked -- through the dispatcher, never through eval.
__subst_run() {
    local inner="$1"
    local out=""

    # Capture stdout only. stderr is left attached so a failure is visible
    # instead of silently becoming an empty argument. The flag tells the
    # dispatcher it is being used for value capture, so it keeps quiet.
    out=$(IGITARI_IN_SUBST=1; execute_command "$inner" 2>/dev/null)

    # Trailing newlines are never wanted in an argument.
    while [[ "$out" == *$'\n' ]]; do
        out="${out%$'\n'}"
    done

    printf '%s' "$out"
}

# Execute individual command
execute_command() {
    local EXPOSED_FUNCS=("openweb" "squash" "discard" "reword" "fzf" "movehead" "undo" "redo" "transplant" "decimate" "untrack" "retrack" "state" "conflict" "guess" "forge")
    local cmd="$1"
    local git_path="${2:-$GIT_PATH}"

    [[ -z "${cmd}" ]] && {
        handle_empty_command
        return 0
    }

    case "$cmd" in
    "exit")
        log "Exit command received"
        return 24 # Special exit code
        ;;

    "git"*)
        # The reminder is fine when typed, but it would corrupt any value a
        # $(...) substitution is trying to capture.
        [[ "${IGITARI_IN_SUBST:-0}" == "1" ]] || echo "Do you even have to type 'git' in here? Sure."
        eval "${git_path}" "${cmd#git }"
        ;;

    "lazygit")
        if command -v lazygit >/dev/null 2>&1; then
            echo "Starting LazyGit..."
            lazygit
        else
            echo -e "\e[93m\e[1mError: LazyGit is not installed\e[0m"
            return 1
        fi
        ;;

    "help")
        git help
        echo -e "\n\e[1m\e[34mAdditional Igitari commands:\e[0m"
        cat <<'EOF'
  openweb       Open repository in web browser
  forge         Reach the forge (PRs, issues, releases) via gh or glab
  squash      * Squash commits into one (last n, or an inclusive c1..c2 range)
  discard     * Intelligently discard changes
  untrack     * Stop tracking paths, keep them on disk
  retrack     * Put untracked paths back under git
  reword      * Change a commit message
  movehead      Move HEAD forward/backward relative to current position
  undo          Undo last Git operation (reflog-based)
  redo          Redo last undone Git operation
  transplant  * Move commits from current branch to another branch
  decimate      Remove a file from entire git history (current branch only, --all for all)
  lazygit       Launch LazyGit TUI (requires installation)
  version       Display Igitari version
  paginate      Pass output through a pager
  no-pager      Disable pager for output
  >command      Execute shell command (prefix with >)
EOF
        echo -e "\n\e[90mTip: 'help <command>' for the details. Marked * have a written page;\e[0m"
        echo -e "\e[90m     the rest fall through to git's own docs or their usage line.\e[0m"
        ;;

    "help "*)
        local help_target="${cmd#help }"
        read -r help_target <<< "${help_target}"

        if [[ -z "$help_target" ]]; then
            execute_command "help" "$git_path"
        elif show_command_help "$help_target" 2>/dev/null; then
            :
        elif declare -F "$help_target" >/dev/null 2>&1; then
            echo "No help page written for '$help_target' yet. (It's one of mine, I just haven't"
            echo "gotten around to documenting it. Run it with no arguments and it'll tell you the usage.)"
        else
            # Not one of ours — let git answer, the same way it would outside.
            eval "${git_path}" help "${help_target}"
        fi
        ;;

    "version"|"-v")
        show_version
        ;;

    "paginate")
        eval "${git_path}" --paginate "${cmd#paginate }"
        ;;

    "no-pager")
        eval "${git_path}" --no-pager "${cmd#no-pager }"
        ;;

    \>*)
        # Shell command execution (prefixed with >)
        local shell_cmd="${cmd#>}"
        read -r shell_cmd <<< "${shell_cmd}" # Trim whitespace

        [[ -n "${shell_cmd}" ]] || return 0

        log "Executing shell command: ${shell_cmd}"
        eval "${shell_cmd}"
        notify_git_watcher
        ;;

    *.patch|*.diff|*.bundle|*.mbox)
        local patch_file="${cmd}"
        # Strip wrapping quotes if present (user may type "path with spaces/file.patch")
        [[ "${patch_file}" =~ ^\"(.+)\"$ ]] && patch_file="${BASH_REMATCH[1]}"
        [[ "${patch_file}" =~ ^\'(.+)\'$ ]] && patch_file="${BASH_REMATCH[1]}"
        # Unescape spaces (user may type path\ with\ spaces/file.patch)
        patch_file="${patch_file//\\ / }"

        [[ -f "${patch_file}" ]] || {
            echo -e "\e[91mError: File not found: ${patch_file}\e[0m"
            return 1
        }
        [[ -r "${patch_file}" ]] || {
            echo -e "\e[91mError: File not readable: ${patch_file}\e[0m"
            return 1
        }

        verify_gitfiles "${patch_file}" || return 1

        #   Dirty working tree check
        if [[ ${REPO_IS_DIRTY} -eq 1 || ${REPO_IS_DIRTY_AND_STAGED} -eq 1 ]]; then
            echo -e "\e[93mWarning: You have uncommitted changes.\e[0m"
            echo "Applying a patch with a dirty working tree may cause merge conflicts or lost work."
            read -r -p "Continue anyway? (y/n) " confirm </dev/tty
            [[ "${confirm}" =~ ^[Yy] ]] || return 1
        fi

        # 2. Inform user what this file will do
        local ext="${patch_file##*.}"
        case "${ext}" in
            mbox|bundle)
                echo -e "\e[93mThis file will create commits on your current branch.\e[0m"
                ;;
            *)
                echo -e "\e[93mThis file will only modify your working directory (no commits).\e[0m"
                ;;
        esac

        show_stat_gitfile "${patch_file}"

        # 3. Branch isolation options
        echo ""
        echo "Apply options:"
        echo "  1) Apply directly to current branch    (default)"
        echo "  2) Create a new branch and apply there (recommended)"
        echo "  3) Create a worktree and apply there   (safest)"
        read -r -p "Choose [1/2/3]: " apply_mode </dev/tty

        case "${apply_mode}" in
            2)
                local branch_name
                branch_name="patch-$(date +%Y%m%d-%H%M%S)"
                git checkout -b "${branch_name}" || {
                    echo -e "\e[91mError: Failed to create branch ${branch_name}\e[0m"
                    return 1
                }
                echo "Created and switched to branch: ${branch_name}"
                ;;
            3)
                local worktree_dir
                worktree_dir=".worktrees/patch-$(date +%Y%m%d-%H%M%S)"
                mkdir -p .worktrees 2>/dev/null
                git worktree add "${worktree_dir}" -b "wt-$(basename "${worktree_dir}")" || {
                    echo -e "\e[91mError: Failed to create worktree at ${worktree_dir}\e[0m"
                    return 1
                }
                echo "Created worktree at: ${worktree_dir}"
                cd "${worktree_dir}" || return 1
                ;;
        esac

        prompt_user_apply_gitfile "${patch_file}" || return 1
        apply_gitfile "${patch_file}"
        ;;

    *)
        # Check if command matches any exposed function
        local fn
        local base_cmd="${cmd%% *}" # Everything before first space

        # Check if it's in exposed functions
        for fn in "${EXPOSED_FUNCS[@]}"; do
            # log "Checking exposed function: ${fn} == ${base_cmd}"
            if [[ "${fn}" == "${base_cmd}" ]]; then
                log "Executing exposed function: ${fn}"

                # Get the arguments (everything after first word).
                #
                # Named arg_text, not args: 'args' is an array elsewhere in
                # this script, and a string called args reads like a mistake
                # even in a different scope.
                local arg_text="${cmd#* }"
                local -a split_args=()

                # If cmd had no spaces, arg_text will equal cmd (no arguments).
                # Otherwise split like a shell would, so quotes hold words
                # together and $(...) runs a nested Igitari command.
                if ! [[ "$arg_text" == "$cmd" ]]; then
                    __split_argv "$arg_text" split_args
                else
                    split_args=()
                fi

                # Call the function with args
                $fn "${split_args[@]}"
                exit_code=$?
                ((exit_code == 0)) && history -s "${cmd}"
                return $exit_code
            fi
        done

        # 'config session ...' is Igitari's own scope, so it has to be
        # handled before the fallthrough -- raw git reports an unknown scope
        # and says nothing useful about it.
        __handle_session_config "${cmd}" && return 0
        if [[ "${__SESSION_HANDLED:-0}" == "1" ]]; then
            # Mine, and it reported a failure: let '&&' and '||' see it
            # without forwarding the line to git.
            return 1
        fi

        # Default: treat as git command.
        #
        # stderr is tee'd rather than captured: it still appears live, so a
        # progress bar or a password prompt behaves normally, but a copy is
        # kept in case git fails and we want to read its suggestion. The
        # subshell form keeps the exit code intact.
        log "Executing Git command: ${git_path} ${cmd}"
        __session_config_export
        local __err="${TMPDIR:-/tmp}/igitari-stderr.$$"
        : >"$__err"
        eval "${git_path}" "${cmd}" 2> >(tee "$__err" >&2)
        local __rc=$?

        # Give the process substitution a moment to flush before reading.
        [[ -s "$__err" ]] || sleep 0.05

        ((__rc != 0)) && __igitari_offer_fix "$__err"

        rm -f "$__err"

        # Report git's status explicitly. Falling through to the '$?' read
        # below would report 'rm' instead, which is always 0 -- that silently
        # made every failing git command look successful, so '&&' ran on
        # failure and '||' never ran at all.
        ((__rc == 0)) && history -s "${cmd}"
        return "$__rc"
        ;;

    esac

    local exit_code=$?
    ((exit_code == 0)) && history -s "${cmd}"
    return $exit_code
}

# Process command line with operator support (&&, ||, ;)
process_command_line() {
    local input="$1"
    local git_path="${2:-$GIT_PATH}"

    # Trim whitespace using bash builtins (avoids xargs interpreting --version etc.)
    read -r input <<< "$input"
    [[ -z "$input" ]] && return 0

    # Split on operators while preserving quoted strings
    local IFS=$'\n'
    local commands

    mapfile -t commands < <(echo "$input" | sed 's/&&/\n\&\&\n/g; s/||/\n||\n/g; s/;/\n;\n/g' | sed '/^$/d')

    local last_exit_code=0
    local should_execute=1

    while [[ ${#commands[@]} -gt 0 ]]; do
        local cmd="${commands[0]}"
        commands=("${commands[@]:1}") # drop first element

        case "$cmd" in
        "&&")  should_execute=$(( last_exit_code == 0 && should_execute )) ;;
        "||")  should_execute=$(( last_exit_code != 0 && should_execute )) ;;
        ";")   should_execute=1 ;;
        *)
            if [[ "$should_execute" -eq 1 ]]; then
                read -r cmd <<< "${cmd}" # Trim whitespace
                execute_command "${cmd}" "${git_path}"
                last_exit_code=$?
            else
                log "Skipping command: ${cmd} (condition not met)"
            fi
            ;;
        esac
    done

    return $last_exit_code
}

#--|HIST_MGMT                                                         [STDLIB]
#------------------------------------------------------------------------------
# History Management
#------------------------------------------------------------------------------

# Initialize command history
setup_command_history() {
    export HISTCONTROL=ignoredups:ignorespace
    export HISTFILE="$MAIN_HISTORY_FILE"
    export HISTSIZE=1000
    export HISTFILESIZE=2000

    if [[ ! -f "$HISTFILE" ]]; then
        echo "Creating main history file..."
        touch "$HISTFILE"
        chmod 600 "$HISTFILE"
    fi

    # Disable history during setup
    set +o history

    # Set up arrow key history navigation (interactive mode only)
    if [[ -t 0 ]]; then
        bind '"\e[A": history-search-backward' 2>/dev/null
        bind '"\e[B": history-search-forward' 2>/dev/null
    fi

    # Load main history file
    if history -r; then
        log "Loaded history from $HISTFILE"
    else
        log "Could not load history from $HISTFILE"
    fi

    log "Session history will be saved to $HISTFILE"
}

#--|RC_SETUP                                                          [STDLIB]
#------------------------------------------------------------------------------
# RC File Management
#------------------------------------------------------------------------------

# Handle RC file initialization and GitSh compatibility
setup_rc_file() {
    # shellcheck source=/dev/null
    if [[ -f "$RC_FILE" ]]; then
        if ((NO_SOURCING == 0)); then
            log n "Sourcing $RC_FILE..."
            if source "$RC_FILE"; then
                log p "ok."
            else
                log p "failed."
                echo "Warning: Error sourcing $RC_FILE. Continuing anyway."
            fi
        fi
    elif [[ -f "$GITSH_RC_FILE" && "${PRINT_HEADER}" -eq 1 ]]; then
        # Offer to migrate from GitSh
        cat <<EOF
Found GitSh configuration file!

Would you like to copy it for use with Igitari?
This will create a copy as .igitari-rc without affecting your GitSh setup.

Note: Functionality may not be 100% compatible with GitSh.
EOF
        read -rp "Copy GitSh config? (y/n): " answer </dev/tty || answer="n"

        if [[ ${answer} =~ ^[Yy]$ ]]; then
            echo "Copying .gitshrc to .igitari-rc..."
            if cp "$GITSH_RC_FILE" "$RC_FILE"; then
                echo "Configuration copied successfully!"
                NO_SOURCING=0
                if source "$RC_FILE"; then
                    echo "Configuration loaded. This will be your default RC file."
                fi
            else
                echo "Error: Failed to copy configuration file."
            fi
        fi
    fi
}

#--|SIGHANDLERS                                                      [IGITARI]
#------------------------------------------------------------------------------
# Signal Handlers
#------------------------------------------------------------------------------

# Handle Ctrl+C (SIGINT)
handle_interrupt() {
    # Ignore further SIGINT until we finish
    trap : SIGINT
    # Ensure terminal echo is on
    stty echo
    echo -n
    exec "$SELF_REALPATH" --no-header "${ARG[@]}"
}

# Handle termination signals
handle_termination() {
    [[ -n "$GIT_WATCHER_PID" ]] && kill "$GIT_WATCHER_PID" 2>/dev/null
    [[ -n "$UPDATER_PID" ]] && kill "$UPDATER_PID" 2>/dev/null
    history -w && log "Successfully saved command history."
    echo
    echo "Igitari terminated."
    exit 130
}

# Cleanup on normal exit
cleanup_and_exit() {
    [[ -n "$GIT_WATCHER_PID" ]] && kill "$GIT_WATCHER_PID" 2>/dev/null
    [[ -n "$UPDATER_PID" ]] && kill "$UPDATER_PID" 2>/dev/null
    set +o history
    history -w && log "Successfully saved command history."
    echo
    echo "Byee!"
    exit 0
}

# Handle external git changes (SIGUSR1 from inotifywait watcher)
handle_external_change() {
    log "External change detected, refreshing state"
    check_git_repository >/dev/null
    dirty_check
}

# Start background inotifywait watcher on .git directory
# Watches refs, HEAD, and index for changes; sends SIGUSR1 on update
# Also handles SIGUSR1 from parent to re-evaluate git dir on repo switch
start_git_watcher() {
    command -v inotifywait &>/dev/null || return 0
    [[ -n "$GIT_WATCHER_PID" ]] && kill "$GIT_WATCHER_PID" 2>/dev/null

    (
        local git_dir
        git_dir=$(git rev-parse --git-dir 2>/dev/null) || exit 1
        local watch_dir="$git_dir"
        log "Watcher: started on $watch_dir"

        trap '
            git_dir=$(git rev-parse --git-dir 2>/dev/null) || exit 1
            if [[ "$git_dir" != "$watch_dir" ]]; then
                log "Watcher: git dir changed $watch_dir -> $git_dir"
                watch_dir="$git_dir"
                kill "$child" 2>/dev/null
            fi
        ' USR1

        while kill -0 "$$" 2>/dev/null; do
            inotifywait -q -r -e modify,create,delete,move \
                "$watch_dir/refs" "$watch_dir/HEAD" "$watch_dir/index" >/dev/null 2>&1 &
            child=$!
            wait "$child" 2>/dev/null
            local exit_code=$?
            # inotifywait returns non-zero when killed (dir change) — don't exit
            ((exit_code > 128)) && continue
            # Normal event — notify parent
            log "Watcher: change detected in $watch_dir"
            kill -USR1 "$$" 2>/dev/null || exit 0
        done
        log "Watcher: exited"
    ) &
    GIT_WATCHER_PID=$!
    disown "$GIT_WATCHER_PID"
}

# Notify watcher to re-evaluate git directory (e.g. after >cd)
notify_git_watcher() {
    if [[ -n "$GIT_WATCHER_PID" ]]; then
        log "Watcher: notifying to re-evaluate git dir"
        kill -USR1 "$GIT_WATCHER_PID" 2>/dev/null
    fi
}

#--|INTERFACES                                                       [IGITARI]
#------------------------------------------------------------------------------
# User Interface
#------------------------------------------------------------------------------

# Print startup header
print_header() {
    [[ ${PRINT_HEADER} -eq 0 ]] && return

    cat <<EOF
Entering Igitari (Hi!). Press Ctrl+D or type 'exit' to quit.
Prefix commands with '>' to execute shell commands
EOF

    # Show LazyGit keybind if available
    if [[ -t 0 ]] && command -v lazygit >/dev/null 2>&1; then
        echo "Press Ctrl+G to launch LazyGit"
    fi

    echo
}

# Generate dynamic prompt
generate_prompt() {
    if check_git_repository; then
        local top subdir repo_name branch_info root_indicator dirty_markers

        # Resolve repository root and prefix safely
        top=$(git rev-parse --show-toplevel 2>/dev/null)
        subdir=$(git rev-parse --show-prefix 2>/dev/null)
        repo_name=${top##*/}

        # Add markers per dirty flag
        dirty_markers="" # Reset first
        if ((NO_MARKERS != 1)); then
            ((REPO_IS_DIRTY == 1)) && dirty_markers+="\e[91m*\e[0m"
            ((REPO_IS_DIRTY_AND_STAGED == 1)) && dirty_markers+="\e[93m^\e[0m"
            ((REPO_STASH_DIRTY == 1)) && dirty_markers+="\e[94m_\e[0m"
        fi

        # Normalize subdir (remove trailing slash)
        subdir=${subdir%/}

        # Compact root indicator
        [[ "$(dirname "$PWD")" != "/" ]] && root_indicator=".../"

        branch_info=$(parse_git_branch)

        # Final prompt
        echo -e "\e[34m[\e[1m${root_indicator}${repo_name}/${subdir}\e[32m (${branch_info}${dirty_markers})\e[0m\e[34m]Git>\e[0m "
    else
        log "Repository not detected! Commands will stop working."
        echo -e "[\e[93m\e[1mN/A\e[0m]Git> "
    fi
}

# Default action when empty command is entered.
#
# Deliberately does nothing. gitsh runs 'status' on a bare Enter, and it is
# tempting, but a bare Enter is how you get a clean prompt back -- and a wall
# of status is the last thing you want mid-rebase or mid-conflict, which is
# exactly when your finger is on the key. Dumping output on Enter also makes
# it impossible to tell a stray Enter from a deliberate request.
#
# One line if you disagree. Replace the ':' below with:
#     display_git_status
handle_empty_command() {
    :
}

#--|GIST_UPDATER                                                     [IGITARI]
#------------------------------------------------------------------------------
# Updater (GitHub)
#------------------------------------------------------------------------------

Updater() {
    [[ ${CHECK_UPDATES} -ne 1 ]] && return

    local SCRIPT_URL="${_UPDATER_RAW_URL}/igitari.sh"
    local REF_FILE="${LOCALPATH}ref.sha"
    local latest_sha local_sha

    _updater_check_prereqs "${_UPDATER_RAW_URL}/igitari.sh" || return $?
    latest_sha="$(_updater_fetch_hash)" || return 1

    # No local ref stored — first run, save baseline
    if [[ ! -s "$REF_FILE" ]]; then
        log "No ref.sha found, storing baseline."
        mkdir -p "$LOCALPATH"
        echo "$latest_sha" >"$REF_FILE"
        return 0
    fi

    local_sha="$(cat "$REF_FILE")"
    if [[ "$latest_sha" == "$local_sha" ]]; then
        log "Updater: already up to date."
        return 0
    fi

    _updater_resolve_status "$local_sha" "$latest_sha" "$SCRIPT_URL"
}

#--| Updater helpers                                                 [IGITARI]
#------------------------------------------------------------------------------

_UPDATER_RAW_URL='https://raw.githubusercontent.com/BashhScriptKid/Igitari/mono-master'

# The update check reaches GitHub two ways, so certify both: curl fetches the
# compare payload and the script itself, while git ls-remote finds the tip SHA
# and the shallow clone walks history. Checking only curl let a git-less box
# through, only to fail later with "ls-remote came up empty" -- which blames
# the network for a missing binary.
_updater_check_prereqs() {
    if ! command -v curl >/dev/null 2>&1; then
        echo "Error: curl isn't installed. How am I supposed to check for updates without it? :/"
        return 1
    fi

    if ! command -v git >/dev/null 2>&1; then
        echo "Error: git isn't installed. It's how I find out what's new out there."
        return 1
    fi

    if ! curl -fsSL --max-time 5 --head "$1" >/dev/null 2>&1; then
        echo "Warning: Can't reach GitHub. Skipping update check."
        return 254
    fi
}

_updater_fetch_hash() {
    local sha
    sha="$(git ls-remote "${REMOTE_LINK}".git refs/heads/mono-master 2>/dev/null | awk '{print $1}')"
    if [[ -z "$sha" ]]; then
        # git is known present (prereqs checked it), so an empty answer is the
        # transport talking: ssh, a proxy, or a renamed branch.
        echo "Warning: Couldn't fetch the latest commit hash. ls-remote came up empty."
        return 1
    fi
    echo "$sha"
}

_updater_resolve_status() {
    local local_sha="$1" latest_sha="$2" script_url="$3"
    local remote_has_local

    log "Updater: You're on ${local_sha:0:7}, latest is ${latest_sha:0:7}."

    # Fast check: is the local hash a ref tip in the remote?
    remote_has_local="$(git ls-remote "${REMOTE_LINK}".git | awk -v h="$local_sha" '$1 == h {found=1} END {print (found ? "yes" : "no")}')"

    # Slow fallback: shallow clone to search full history
    if [[ "$remote_has_local" == "no" ]]; then
        log "Updater: Version isn't a branch tip — digging deeper..."
        remote_has_local="$(_updater_hash_in_remote "$local_sha")"
    fi

    if [[ "$remote_has_local" == "no" ]]; then
        _updater_handle_ahead "$script_url" "$latest_sha"
        return $?
    fi

    _updater_handle_behind "$local_sha" "$latest_sha" "$script_url"
}

# Check if a commit hash exists in remote history via shallow clone
# Returns "yes" or "no"
_updater_hash_in_remote() {
    local target_sha="$1"
    local tmp_dir

    tmp_dir="$(mktemp -d /tmp/igitari-clone-XXXX)" || {
        log "mktemp failed — can't do the deep search."
        echo "no"
        return
    }

    # Shallow clone mono-master — just enough to walk history
    if git clone --depth=2048 --single-branch --no-tags -b mono-master "${REMOTE_LINK}.git" "$tmp_dir" >/dev/null 2>&1; then
        if git -C "$tmp_dir" cat-file -e "$target_sha^{commit}" 2>/dev/null; then
            rm -rf "$tmp_dir"
            echo "yes"
            return
        fi
    fi

    rm -rf "$tmp_dir"
    echo "no"
}

_updater_handle_ahead() {
    local script_url="$1" latest_sha="$2"

    # igitari.sh tracked locally = dev build, skip
    if git ls-files --error-unmatch igitari.sh >/dev/null 2>&1; then
        log "Updater: dev build detected (igitari.sh is tracked). Skipping."
        return 0
    fi

    # Background mode: notify only, don't overwrite
    if [[ "${_UPDATER_BACKGROUND:-}" == "1" ]]; then
        echo "$latest_sha" > "$UPDATE_NEW_SHA_FILE"
        echo "Warning: Your version isn't in the remote history, and this isn't a dev repo." > "$UPDATE_PENDING_FILE"
        return 0
    fi

    # Foreground: ask before overwriting
    echo "Warning: Your version isn't in the remote history, and this isn't a dev repo."
    echo "          Either something's been tampered with or things got weird."
    read -rp "Overwrite with latest? (Y/N) " -n1 response </dev/tty || { echo; echo "Updater: no answer, leaving things alone."; return 0; }
    echo
    [[ "${response}" =~ ^[Yy]$ ]] || { echo "Updater: Sure, I'll mind my own business."; return 0; }
    _updater_replace "$latest_sha"
}

_updater_handle_behind() {
    local local_sha="$1" latest_sha="$2" script_url="$3"

    local changelog version_name target_sha formatted_changelog response

    changelog="$(curl -s "https://api.github.com/repos/BashhScriptKid/Igitari/compare/${local_sha}...${latest_sha}" 2>/dev/null)"

    # The release target is the tip of the newest release, not the commit that
    # announces it: commits keep landing after "Bump version to X", and they
    # belong to X. So we walk the top-level "commits" array and remember the
    # bump; the target is the last commit that belongs to it.
    #
    # Parsing keys on the 2-space indent of the outer "commits" array, because
    # each commit carries nested "sha" keys (its tree, parents) that would
    # otherwise be mistaken for commits.
    read -r target_sha version_name <<<"$(printf '%s' "$changelog" | awk '
        /^  "commits": \[/ { f = 1; next }
        f && /^  \]/        { f = 0 }
        f && /^      "sha": "/ {
            s = $0; gsub(/[",]/, "", s); sub(/.*sha: */, "", s); sha = s; next
        }
        f && /^        "message": "/ {
            m = $0
            sub(/.*"message": "/, "", m)
            sub(/\\n.*/, "", m)
            sub(/" *,?$/, "", m)
            if (m ~ /^Bump version to /) {
                v = m; sub(/^Bump version to /, "", v)
                rel = v; seen = 1
            }
            last_sha = sha
            next
        }
        END { if (seen) print last_sha, rel }
    ')"

    if [[ -z "$target_sha" ]]; then
        log "No 'Bump version to' commit found. Can't determine a stable release."
        return 1
    fi

    [[ -z "$version_name" ]] && version_name="${target_sha:0:7}"

    # Build the changelog from the same payload: one subject per commit,
    # skipping merges and the version bump itself.
    formatted_changelog="$(printf '%s' "$changelog" | awk '
        /^  "commits": \[/ { f = 1; next }
        f && /^  \]/        { f = 0 }
        f && /^        "message": "/ {
            m = $0
            sub(/.*"message": "/, "", m)
            sub(/\\n.*/, "", m)    # subject only: escaped newline starts the body
            sub(/" *,?$/, "", m)   # drop the closing JSON quote and comma
            gsub(/\\"/, "\"", m)
            gsub(/\\t/, " ", m)
            if (m ~ /^Merge / || m ~ /^Bump version/) next
            print "* " m
        }
    ')"

    # Build the version label. When both sides carry the same version number we
    # are moving between builds of one release, so show the SHAs -- otherwise
    # the notification reads "4.0.0 -> 4.0.0" and says nothing about what is
    # actually changing.
    local from_label to_label
    if [[ "$version_name" == "$IGITARI_VERSION" ]]; then
        from_label="${IGITARI_VERSION}-${local_sha:0:7}"
        to_label="${version_name}-${target_sha:0:7}"
    else
        from_label="$IGITARI_VERSION"
        to_label="$version_name"
    fi

    # Background mode: just write notification, don't prompt
    if [[ "${_UPDATER_BACKGROUND:-}" == "1" ]]; then
        echo "$target_sha" > "$UPDATE_NEW_SHA_FILE"
        {
            echo "Update available: ${from_label} -> ${to_label}"
            if [[ -n "$formatted_changelog" ]]; then
                echo
                echo "Changes:"
                echo "$formatted_changelog" | sed 's/^/  /'
            fi
            echo
            echo "Run 'igitari' to update, or check https://github.com/BashhScriptKid/Igitari"
        } > "$UPDATE_PENDING_FILE"
        return 0
    fi

    # Foreground mode: interactive prompt
    echo
    echo "New version available: ${from_label} -> ${to_label}"
    echo
    if [[ -n "$formatted_changelog" ]]; then
        echo "Changes since your version:"
        echo "$formatted_changelog" | sed 's/^/  /'
        echo
    fi

    read -rp "Update now? (Y/N) " -n1 response </dev/tty || { echo; echo "Updater: no answer, not updating."; return 0; }
    echo
    if [[ ! "${response}" =~ ^[Yy]$ ]]; then
        echo "Updater: Sure, I'll mind my own business."
        return 0
    fi

    _updater_replace "$target_sha"
}

_updater_replace() {
    local target_sha="$1"
    local script_path temp_file
    script_path="$(realpath "$0")"

    # raw.githubusercontent.com does serve commit-specific URLs, so ask for the
    # exact SHA we're about to record in ref.sha. Downloading the branch tip
    # instead would let the file and the recorded ref drift apart when a push
    # lands between the check and the download.
    local script_url="https://raw.githubusercontent.com/BashhScriptKid/Igitari/${target_sha}/igitari.sh"

    temp_file="$(mktemp /tmp/igitari-update-XXXX.sh)" || {
        echo "Error: mktemp failed — can't create temp file to write the update to."
        return 1
    }

    echo "Updater: Downloading..."
    if ! curl -fL "$script_url" -o "$temp_file"; then
        echo "Error: Download failed. Either your connection is flaky or GitHub is having a moment."
        rm -f "$temp_file"
        return 1
    fi

    if ! bash -n "$temp_file"; then
        echo -e "\e[1m\e[93m"
        echo "This version is broken. Either you're using an outdated Bash or she made a mistake writing it. Try again later?"
        echo -e "\e[0m"
        rm -f "$temp_file"
        return 1
    fi

    if [[ ! -s "$temp_file" ]]; then
        echo "Updater: Huh, the update file is empty. Weird. I'm gonna…abort it real quick."
        rm -f "$temp_file"
        return 1
    fi

    if ! cat "$temp_file" >"$script_path"; then
        echo "Error: Couldn't write to ${script_path}. Check permissions, maybe?"
        rm -f "$temp_file"
        return 1
    fi
    chmod +x "$script_path"
    rm -f "$temp_file"

    echo "$target_sha" >"${LOCALPATH}ref.sha"

    echo "[Update applied! Restart Igitari to use the new version.]" > "$UPDATE_PENDING_FILE"
}

do_update() {
    [[ ${CHECK_UPDATES} -ne 1 ]] && return

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"

    if [[ -n "$GIT_ROOT" && "$SCRIPT_DIR" == "$GIT_ROOT" ]]; then
        log "Updater skipped: running from Igitari repo itself."
        return
    fi

    # Run in background — don't block the prompt
    (
        # Exit immediately if parent is gone (handles SIGKILL orphan case)
        kill -0 "$$" 2>/dev/null || exit 0

        _UPDATER_BACKGROUND=1
        Updater

        # Exit if parent is gone before signaling
        kill -0 "$$" 2>/dev/null || exit 0

        # If we got here with a notification to show, signal the main shell
        if [[ -f "$UPDATE_PENDING_FILE" ]]; then
            log "updater: signaling main shell"
            kill -SIGRTMIN $$ 2>/dev/null
        else
            log "updater: no update found"
        fi
    ) &
    UPDATER_PID=$!
    disown "$UPDATER_PID"
}

#--|MAIN                                                             [IGITARI]
#------------------------------------------------------------------------------
# Main Program Loop
#------------------------------------------------------------------------------

UPDATE_PENDING_FILE="${LOCALPATH}.update_pending"
UPDATE_NEW_SHA_FILE="${LOCALPATH}.update_new_sha"
UPDATER_PID=""

# Handle SIGRTMIN from background update check
_updater_signal_handler() {
    [[ ! -f "$UPDATE_PENDING_FILE" ]] && return

    local msg new_sha
    msg="$(<"$UPDATE_PENDING_FILE")"
    rm -f "$UPDATE_PENDING_FILE"

    # READLINE_LINE is the current input buffer — empty means user hasn't typed
    if [[ -z "${READLINE_LINE:-}" ]]; then
        # User hasn't typed — take over the terminal for interactive update
        echo -ne "\r\033[K"
        echo "$msg"
        echo
        read -rp "Update now? (Y/N) " -n1 response </dev/tty || { echo; echo "Updater: no answer, not updating."; return 0; }
        echo
        if [[ "${response}" =~ ^[Yy]$ ]]; then
            new_sha="$(<"$UPDATE_NEW_SHA_FILE")"
            rm -f "$UPDATE_NEW_SHA_FILE"
            _updater_replace "$new_sha"
        else
            rm -f "$UPDATE_NEW_SHA_FILE"
        fi
    else
        # User has typed — notify without disrupting
        echo
        echo "$msg"
    fi
}

# Main interactive loop
main_loop() {
    local cmd exit_code

    # Trap SIGRTMIN from background update checker
    trap '_updater_signal_handler' SIGRTMIN
    trap 'handle_external_change' USR1

    # Start filesystem watcher for external git changes
    start_git_watcher

    while true; do
        # Update repository status
        check_git_repository >/dev/null
        dirty_check

        trap handle_interrupt SIGINT

        # Display prompt and read command.
        #
        # A line ending in a backslash continues: keep reading and join, so a
        # long message does not have to be written on one line. The secondary
        # prompt is a bare '>' rather than the full prompt because it is a
        # continuation, not a new command.
        if ! read -rep "$(generate_prompt)" cmd; then
            break # EOF (Ctrl+D) pressed
        fi

        while ! __join_continuation "$cmd"; do
            cmd="$READ_CMD"
            local more=""
            if ! read -rep "> " more; then
                break 2 # EOF mid-continuation: drop the partial line
            fi
            cmd+="$more"
        done
        cmd="$READ_CMD"

        # Process command
        if [[ -z "$cmd" ]]; then
            # A comment, or nothing but a continuation join: a blank line back
            # is the right answer, not a status dump.
            handle_empty_command
        else
            process_command_line "$cmd"
            exit_code=$?
            if [[ $exit_code -eq 24 ]]; then
                echo "Exiting Igitari..."
                break
            fi
        fi
    done

    [[ -n "$GIT_WATCHER_PID" ]] && kill "$GIT_WATCHER_PID" 2>/dev/null
}
#------------------------------------------------------------------------------
# Program Entry Point
#------------------------------------------------------------------------------

main() {
    # Source RC file here since this allows for maximum function overloading
    setup_rc_file

    # Initial safety checks
    disable_history_expansion

    # Process command line arguments
    process_arguments "$@"

    # Save argument data in case of update / SIGINT
    ARG=("$@")

    # Core initialization
    check_git_installation
    check_localpath
    if [[ ! -f "${LOCALPATH}ref.sha" ]]; then
        log "Reference update commit hash not found, fetching latest (this may break if the script is run long after the file deletion)."
        get_commithash_ref
    fi

    setup_working_directory

    # Check for non-interactive mode
    if [[ $- != *i* ]]; then
        echo -e "\e[93m\e[1mWarning: Running in non-interactive mode. Some features may not work.\e[0m"
    fi

    # Setup components
    setup_git_completion
    setup_custom_tab_completion

    # Clear initial history anomaly
    if ((INIT_CLEAR == 0)); then
        history -c
        INIT_CLEAR=1
        log "Cleared initial history entry"
    fi
    setup_command_history
    initialise_keybinds >/dev/null 2>&1 # It complains, but works

    # Setup signal handlers
    trap 'handle_termination' SIGTERM
    trap 'handle_interrupt' SIGINT
    trap 'cleanup_and_exit' EXIT

    # Display startup information
    print_header

    # Run update check in background so it doesn't block the prompt
    do_update

    # Enter main interactive loop
    main_loop
}

#--|m
#------------------------------------------------------------------------------
# Execute main function with all arguments
#------------------------------------------------------------------------------
# IGITARI_TEST=1 means "I only wanted the functions", so don't start a shell.
[[ "${IGITARI_TEST:-0}" == "1" ]] || main "$@"

#--|END
