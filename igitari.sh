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
readonly IGITARI_VERSION="4.0.0"

readonly GITSH_RC_FILE="${HOME}/.gitshrc"

readonly DEFAULT_GIT_PATH="/usr/bin/git"

readonly LOCALPATH="${HOME}/.local/share/igitari/"
readonly RC_FILE="${LOCALPATH}.igitari-rc"
readonly MAIN_HISTORY_FILE="${LOCALPATH}.igitari_hist"

readonly REMOTE_LINK="https://github.com/BashhScriptKid/Igitari"

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
    squash [amount | commit1..commit2] [message]

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
    forward <steps>    Follow the reflog forward again, after you have walked
                       back. Only works while detached.

    'backward N' then 'forward N' returns you to where you started.

EXAMPLES
    movehead backward 3           Stand three commits behind where I am
    movehead forward 1            Step forward one
    movehead forward              Moving forward after 'forward' overshot

WHY DETACHED
    Because moving on behalf of a branch would rewrite it. You are peeking,
    so HEAD detaches and the branch stays exactly where it was. If you step
    forward far enough to land on a branch tip, you get reattached to it.

WATCH OUT
    Detached HEAD is a place commits go to be lost. If you make a commit
    while detached, nothing points at it. Make a branch before committing, or
    the next checkout will abandon your work silently.

    Steps must be a plain number. No negative numbers, no HEAD~3 arithmetic,
    pick a direction and say how far.
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
    openweb [remote] [issues|pr|prs|pr create|compare|wiki|settings]

WHAT IT DOES
    Opens a remote's web page in your browser, or jumps straight to one of
    its usual corners. Saves you the copy-paste dance when you want to read
    an issue rather than grep a log.

EXAMPLES
    openweb origin                 The repo's front page
    openweb origin issues          The issue tracker
    openweb origin prs             Pull requests
    openweb origin pr create       Start a new pull request
    openweb origin compare         Same page, if you just want the diff
    openweb upstream wiki          Wiki

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
    fzf <commits|tags|reflogs|staged|unstaged|tracked|untracked|stashes|dangling> [return]

WHAT IT DOES
    Hands a list of things to fzf so you can pick one, then prints what you
    picked. Read-only: it picks, it does not act. Pipe the result into
    whatever needs it.

RETURN TYPES
    commits, reflogs   sha | message | diffs
    tags               sha | name
    stashes            ref | diff | name
    dangling           sha | type | content | message

    staged, unstaged, tracked and untracked take no return type -- they hand
    back paths.

EXAMPLES
    fzf commits sha                Pick a commit, get its hash
    fzf commits message            Pick a commit, get the message
    fzf stashes diff               Read around before you pop
    fzf dangling                   Hunt down something you thought was lost

WATCH OUT
    fzf has to be installed. If it is not, you get told rather than an empty
    list, and the rest of Igitari keeps working.

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
    [conflict]=$(cat <<'EOF'
USAGE:
    conflict                          List the conflicted paths
    conflict show <side> [file]       Print one side
    conflict throw <side> [file]      Discard one side, keep the other

SIDES
    base      The common ancestor both sides started from (index stage 1)
    ours      Your side (stage 2)
    theirs    The side coming in (stage 3)

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

WHAT 'throw' DOES
    Writes the surviving side into the working tree and stages it. The staging
    is not optional politeness -- git still calls the path unmerged until it
    is added, so a bare checkout would leave you looking resolved and not
    actually resolved.

    It asks first. Taking a side is silent data loss for the other one, and a
    loop that overwrites six files without asking is not something to hand
    someone by accident.

WATCH OUT
    'conflict throw base' is not a resolution. It restores the file as your
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

_get_remotes() {
    git remote 2>/dev/null | tr '\n' ' '
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
    help exit lazygit openweb squash discard reword fzf movehead version
    paginate no-pager
)

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
        mapfile -t completions < <(compgen -W "$(_get_branches)" -- "$current_word")
    else
        mapfile -t completions < <(compgen -W "$(_get_remotes)" -- "$current_word")
    fi
}

_complete_openweb() {
    if [[ "$line" =~ ^openweb[[:space:]]+[^[:space:]]+[[:space:]]+ ]]; then
        mapfile -t completions < <(compgen -W "issues pr pull-request wiki settings" -- "$current_word")
    else
        mapfile -t completions < <(compgen -W "$(_get_remotes)" -- "$current_word")
    fi
}

_complete_remote() {
    mapfile -t completions < <(compgen -W "add remove rename set-url set-head prune update show" -- "$current_word")
}

_complete_branch() {
    local branch_flags="--delete --force --move --copy --list --remotes --all"
    mapfile -t completions < <(compgen -W "${branch_flags} $(_get_branches)" -- "$current_word")
}

_complete_stash() {
    mapfile -t completions < <(compgen -W "push pop apply drop list show branch clear create store" -- "$current_word")
}

_complete_tag() {
    local tag_flags="--annotate --delete --list --force --message"
    local existing_tags
    existing_tags=$(git tag -l 2>/dev/null | tr '\n' ' ')
    mapfile -t completions < <(compgen -W "${tag_flags} ${existing_tags}" -- "$current_word")
}

_complete_config() {
    local config_subcmds="list get set unset rename-section remove-section edit"
    local config_keys
    config_keys=$(git config --list 2>/dev/null | cut -d= -f1 | tr '\n' ' ')
    mapfile -t completions < <(compgen -W "${config_subcmds} ${config_keys}" -- "$current_word")
}

_complete_fzf() {
    if [[ "$line" =~ ^fzf[[:space:]]+[^[:space:]]+[[:space:]]+ ]]; then
        mapfile -t completions < <(compgen -W "sha message diffs name ref diff content type" -- "$current_word")
    else
        mapfile -t completions < <(compgen -W "commits tags reflogs staged unstaged tracked untracked stashes dangling" -- "$current_word")
    fi
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
    if [[ $COMP_CWORD -le 1 ]]; then
        mapfile -t completions < <(compgen -W "show throw" -- "$current_word")
        return
    fi
    if [[ $COMP_CWORD -eq 2 ]]; then
        mapfile -t completions < <(compgen -W "base ours theirs" -- "$current_word")
        return
    fi
    # Only actually conflicted paths, so Tab never offers a resolved file.
    local unmerged
    unmerged=$(git diff --name-only --diff-filter=U 2>/dev/null | tr '\n' ' ')
    mapfile -t completions < <(compgen -W "${unmerged}" -- "$current_word")
}

_complete_log_flags() {
    local log_flags="--oneline --graph --decorate --all --follow --stat --patch --format --since --until --author --grep --no-merges --merges --first-parent --reverse"
    mapfile -t completions < <(compgen -W "${log_flags}" -- "$current_word")
}

_complete_git_command_names() {
    mapfile -t completions < <(compgen -W "${_GIT_CMDS[*]}" -- "$current_word")
}

_complete_shell_passthrough() {
    if [[ "$line" =~ ^\>[^[:space:]]+[[:space:]]+ ]]; then
        mapfile -t completions < <(compgen -f -- "$current_word")
    else
        local shell_prefix="${current_word#>}"
        mapfile -t completions < <(compgen -c "$shell_prefix" | sed 's/^/>/')
    fi
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
    [reword]=_complete_reword
    [discard]=_complete_discard
    [conflict]=_complete_conflict
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

    if ((num_completions == 1)); then
        READLINE_LINE="${line:0:$word_start}${completions[0]} ${line:$point}"
        READLINE_POINT=$((word_start + ${#completions[0]} + 1))

    elif ((num_completions > 1)); then
        local common_prefix
        common_prefix=$(find_common_prefix "${completions[@]}")

        if [[ -n "$common_prefix" && ${#common_prefix} -gt ${#current_word} ]]; then
            READLINE_LINE="${line:0:$word_start}${common_prefix}${line:$point}"
            READLINE_POINT=$((word_start + ${#common_prefix}))
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

    # ${2:-} so a one-argument call cannot die on set -u before the usage
    # check below gets a chance to explain itself.
    local message="${2:-}"
    local stash_created=false

    if (($# < 1)) || [[ -z "$1" ]]; then
        echo "Usage: squash [amount | commit1..commit2] [message(optional)]"
        echo "  squash 3                 — squash the last 3 commits"
        echo "  squash abc1234..def5678  — squash those commits (both ends included, don't ask twice)"
        return 1
    fi

    local range base tip n total

    if [[ "$1" =~ ^[0-9]+$ ]]; then
        n=$1
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
    elif [[ "$1" == *..* ]]; then
        # Validate BEFORE anything mutates. rev-parse alone is too permissive:
        # it silently accepts unknown flags in ranges, so check both ends.
        local raw_base=${1%%..*}
        local raw_tip=${1#*..}

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

    __igitari_confirm "Proceed?" silent || {
        echo "Squashing aborted! No changes are made."
        return 1
    }

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

        if [[ -n "$target_branch" ]]; then
            # First-parent chain of that branch, and our place in it.
            chain=$(git rev-list --first-parent "$target_branch" 2>/dev/null)
            local idx
            idx=$(printf '%s\n' "$chain" | grep -nx "$here" | head -1 | cut -d: -f1)
            if [[ -n "$idx" ]] && ((idx > steps)); then
                target=$(printf '%s\n' "$chain" | sed -n "$((idx - steps))p")
            fi
        fi

        # No branch contains us (or we went past its tip): the reflog is the
        # only remaining lead, and it is a best guess at best.
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
# Sides are base (stage 1, the common ancestor), ours (stage 2) and theirs
# (stage 3).
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
# Usage: conflict [show|throw <base|ours|theirs> [file]]
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
            echo "       conflict show <base|ours|theirs> [file]   Print a side"
            echo "       conflict throw <base|ours|theirs> [file]  Discard a side"
            return 1
            ;;
    esac

    local side="${1:-}"
    local only_file="${2:-}"

    if [[ -z "$side" ]]; then
        echo "Usage: conflict ${action} <base|ours|theirs> [file]"
        return 1
    fi

    # The two actions use the index stage very differently: show reads the
    # named side, throw keeps the OTHER one, so the stage it writes is the
    # opposite. Keeping both in one variable is how this gets written wrong.
    local read_stage write_stage
    case "$side" in
        base)   read_stage=1; write_stage=1 ;;
        ours)   read_stage=2; write_stage=3 ;;
        theirs) read_stage=3; write_stage=2 ;;
        *)
            echo "Error: '$side' is not a side. Try base, ours or theirs."
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
    if [[ "$side" == "base" ]]; then
        echo "Throwing 'base' restores the file as your common ancestor had it:"
        echo "both sides are discarded, and nothing is resolved by choosing."
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
        helptext_top="fzf (commits | tags | reflogs | staged | unstaged | tracked | untracked | stashes | dangling) [returns]\n"
        helptext_returntype=("Return types:"
            "   commits (sha | message | diffs)"
            "   tags (sha | name)"
            "   reflogs (sha | message | diffs)"
            "   stashes (ref | diff | name)"
            "   dangling (sha | type | content | message)"
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

    returntype=$2

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
    *) build_helptext 1>&2 && return 1 ;;
    esac
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
        echo "SYNTAX: openweb [remote] [issues|pr|pull-request|prs|wiki|settings|compare]"
        return 1
    fi

    # Get remote URL
    local remote_url
    remote_url=$(git remote get-url "$remote" 2>/dev/null)

    if [[ -z "$remote_url" ]]; then
        echo -e "\e[91m\e[1mError: ...'$remote''s URL is empty?? See if it exists (simple type 'remote') \e[0m"
        echo "SYNTAX: openweb [remote] [issues|pr|pull-request|prs|wiki|settings|compare]"
        return 1
    fi

    # Clean URL and append page path
    remote_url="${remote_url%.git}"
    log "Base URL: ${remote_url}"

    case "$page" in
    "issues") remote_url+="/issues" ;;
    "pr" | "pull-request" | "prs")
        # 'pr create' lands on the compare page, which is where the new-pull
        # form lives. GitHub and Gitea both do it that way.
        if [[ "$sub" == "create" || "$sub" == "new" ]]; then
            remote_url+="/compare"
        else
            remote_url+="/pulls"
        fi
        ;;
    "compare") remote_url+="/compare" ;;
    "wiki") remote_url+="/wiki" ;;
    "settings") remote_url+="/settings" ;;
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
    local EXPOSED_FUNCS=("openweb" "squash" "discard" "reword" "fzf" "movehead" "undo" "redo" "transplant" "decimate" "untrack" "retrack" "state" "conflict")
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

        # Default: treat as git command.
        #
        # stderr is tee'd rather than captured: it still appears live, so a
        # progress bar or a password prompt behaves normally, but a copy is
        # kept in case git fails and we want to read its suggestion. The
        # subshell form keeps the exit code intact.
        log "Executing Git command: ${git_path} ${cmd}"
        local __err="${TMPDIR:-/tmp}/igitari-stderr.$$"
        : >"$__err"
        eval "${git_path}" "${cmd}" 2> >(tee "$__err" >&2)
        local __rc=$?

        # Give the process substitution a moment to flush before reading.
        [[ -s "$__err" ]] || sleep 0.05

        ((__rc != 0)) && __igitari_offer_fix "$__err"

        rm -f "$__err"
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

_updater_check_prereqs() {
    if ! command -v curl >/dev/null 2>&1; then
        echo "Error: curl isn't installed. How am I supposed to check for updates without it? :/"
        return 1
    fi

    if ! curl -fsSL --max-time 5 --head "$1" >/dev/null 2>&1; then
        echo "Warning: Can't reach GitHub. Skipping update check."
        return 254
    fi
}

_updater_fetch_hash() {
    local sha
    sha="$(git ls-remote "${REMOTE_LINK}".git refs/heads/mono-master | awk '{print $1}')"
    if [[ -z "$sha" ]]; then
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

    # Find the "Version bump to" commit — that's the release target, not HEAD
    target_sha="$(echo "$changelog" | awk -F'"' '
        /"sha":/ && !target { gsub(/"/, "", $4); sha = $4 }
        /"message":/ && /Version bump to/ { target = sha; sub(/.*Version bump to /, "", $4); version_name = $4; exit }
        END { if (target) print target }
    ')"

    if [[ -z "$target_sha" ]]; then
        log "No 'Version bump to' commit found. Can't determine a stable release."
        return 1
    fi

    [[ -z "$version_name" ]] && version_name="${target_sha:0:7}"

    # Build changelog from target SHA back to local (skip merge and version bump)
    local target_changelog
    target_changelog="$(curl -s "https://api.github.com/repos/BashhScriptKid/Igitari/compare/${local_sha}...${target_sha}" 2>/dev/null)"
    formatted_changelog="$(echo "$target_changelog" | awk '
        /"message":/ {
            sub(/.*"message": "/, ""); sub(/",?$/, "");
            if ($0 !~ /^Merge/ && $0 !~ /^Version bump/) print "* " $0
        }
    ')"

    # Background mode: just write notification, don't prompt
    if [[ "${_UPDATER_BACKGROUND:-}" == "1" ]]; then
        echo "$target_sha" > "$UPDATE_NEW_SHA_FILE"
        {
            echo "Update available: ${IGITARI_VERSION} -> ${version_name}"
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
    echo "New version available: ${IGITARI_VERSION} -> ${version_name}"
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

    # raw.githubusercontent.com doesn't support commit-specific URLs,
    # so we download from the branch and trust that mono-master is stable.
    local script_url="${_UPDATER_RAW_URL}/igitari.sh"

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

        # Display prompt and read command
        if ! read -rep "$(generate_prompt)" cmd; then
            break # EOF (Ctrl+D) pressed
        fi

        # Process command
        if [[ -z "$cmd" ]]; then
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
