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
# shellcheck disable=SC2154
(return 0 2>/dev/null) && test "$inHead" -ne 1 && {
    echo "PLEASE Don't source this script — run it directly with ./git-shell.sh"
    return 1
}

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
    amount            The last <amount> commits. Needs at least 2, because
                      squashing one commit is just lying to yourself.
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
    Moves HEAD to just below the range, then folds everything back in as
    one commit. The resulting tree is identical to where you started, so
    nothing is lost if the message is right.

WATCH OUT
    Uncommitted changes get stashed and re-applied for you. If a conflict
    shows up on the way back, your stash is still there.

    The range has to END at HEAD. Squashing a chunk buried under your
    current position is a job for 'git rebase -i', and I'll happily tell
    you the exact command instead of pretending I can do it.

    Nothing is touched until you say 'y'.
EOF
    )
    [discard]=$(cat <<'EOF'
USAGE:
    discard <file1> <file2> ...
    discard all [tracked | untracked | staged | unstaged]

TWO WAYS
    With files      Throw away the changes to those files, by name.
    With 'all'      Throw away changes in bulk, optionally one category.

BY NAME
    Tracked file    'git checkout -- <file>'. Your edit is gone, file stays.
    Untracked file  'rm -rf <file>'. The file itself is gone. All of it.

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
    or stash it first. I ask before bulk mode, and only bulk mode.

    Named files go straight through, no confirmation. You asked for it by
    name, so I assume you meant it.

    Note the divide-by-zero-ish edge: typo'ing a filename you wanted to
    keep is indistinguishable from meaning it. Back up by hand if unsure.
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
    all of them. If any of those commits are pushed, you are now diverged
    and everyone pulling your branch gets to have a bad day.

    I warn you and ask before doing the rebase. Say no and nothing moves.

    Conflicts during the rebase leave you mid-rebase, not reverted. Finish
    with 'rebase --continue' or back out with 'rebase --abort'.

    Message with spaces needs quotes, or I get to guess which word is which
    and I will not guess well.
EOF
    )
    [transplant]=$(cat <<'EOF'
USAGE:
    transplant <commit> <target-branch>
    transplant <n> <target-branch>

WHAT IT DOES
    Cherry-picks commits from your current branch onto <target-branch>,
    then takes them OFF the current branch by resetting it below them.
    The commits move house. They do not get copied.

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

    Moving commits that are already pushed is a force-push waiting to
    happen. I do not check for that. You should.
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
        local allowBlankArg=$([[ "$1" == 'a' ]] && echo "0" || echo "1")
        shift
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
        read -r -n1 -s response
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
    local message="$2"
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
            echo "Error: A range needs both ends. 'abc1234..def5678', not '...I forgot one'."
            return 1
        fi

        base=$(git rev-parse --verify --quiet "${raw_base}^{commit}") || {
            echo "Error: '$raw_base' isn't a commit I know. Typo, or did you forget to fetch?"
            return 1
        }
        tip=$(git rev-parse --verify --quiet "${raw_tip}^{commit}") || {
            echo "Error: '$raw_tip' isn't a commit I know. Typo, or did you forget to fetch?"
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
            echo "Squashing something under your feet needs an interactive rebase, and I don't"
            echo "hold the shovel for that one. "
            echo ""
            echo "Do it yourself (no really, I genuinely can't >.>):"
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

    confirm=''
    while [[ $confirm != "y" && $confirm != "n" ]]; do
        read -s -n1 -p "Proceed? (y/n) " confirm </dev/tty || {
            echo "Aborted by user"
            return 1
        }
    done
    echo
    echo # 2 newline

    if [[ $confirm == "n" ]]; then
        echo "Squashing aborted! No changes are made."
        return 1
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

discard() {
    if [[ -z "$1" ]]; then
        echo "Usage: discard <file1> <file2> ... | all (tracked | untracked | staged | unstaged)"
        return 1
    fi

    discard_files() {
        local file_array=("$@")
        local tracked

        local failed=0
        for file in "${file_array[@]}"; do
            if [[ ! -e "$file" ]]; then
                echo "File '$file' not found."
                failed=1
                continue
            fi

            echo "Discarding file '$file'..."

            tracked=$(git ls-files --error-unmatch "$file" 2>/dev/null)

            if [[ -n "$tracked" ]]; then
                git checkout -- "$file"
            else
                rm -rf "$file"
            fi

            if (($? == 0)); then
                echo "File '$file' discarded."
            else
                echo "Failed to discard file '$file'."
                failed=1
            fi
        done

        [[ $failed -ne 0 ]] && return 1
    }

    discard_all() {

        local aborted=1
        __warn_discard() {
            local n_file=$1
            local mode=$2
            local filelist=$3 # Supposed to be piped from git commands

            [[ $n_file == 0 ]] && {
                echo "Nothing to discard."
                return 1
            }

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

            echo
            confirm=''
            echo -n "Are you sure? (y/n) "
            while [[ $confirm != "y" && $confirm != "n" ]]; do
                read -n 1 -r confirm
            done
            echo

            if [[ $confirm == "y" ]]; then
                aborted=0
                return 0
            elif [[ $confirm == "n" ]]; then
                echo "Discard operation aborted."
                return 1
            fi
        }

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

        if (($filecount > 0)) && (($aborted == 0)); then
            [[ -z "$1" ]] && echo "All changes discarded." || echo "All $1 changes discarded."
        fi

    }

    if [[ "$1" == "all" ]]; then
        mode=$2
        discard_all "$mode"
    else
        discard_files "$@"
    fi
}

reword() {
    if [[ -z "$1" ]]; then
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
    if [[ -z "$2" ]]; then
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

        local confirm=''
        echo -n "Proceed anyway? (y/n) "
        while [[ $confirm != "y" && $confirm != "n" ]]; do
            read -n 1 -r confirm
        done
        echo

        if [[ $confirm == "y" ]]; then
            __reword_past_commit_that_for_some_fucking_reason_got_too_complicated
        else
            echo "Alright, aborted."
        fi
    fi
}

# Undo last Git operation(s) using reflog. Usage: undo [steps]
undo() {
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
    [[ -z "$GIT_REFLOG" ]] && { echo "Error: No reflog available. Are you in a git repository?"; return 1; }

    local current
    current=$(echo "$GIT_REFLOG" | head -1 | grep -oP '@\{\K[0-9]+')

    if ((current == 0)); then
        echo "Error: Nothing to redo."
        return 1
    fi

    local target=$((current - 1))
    echo "Redoing to HEAD@{${target}}..."
    git log --oneline -1 "HEAD@{${target}}"
    git reset --hard "HEAD@{${target}}"
}

# Transplant commits from current branch to another branch
# Usage: transplant <commit | n> <to_branch>
#   commit — specific commit hash to transplant
#   n      — number of commits from HEAD to transplant (e.g. "3" = last 3 commits)
transplant() {
    if (($# < 2)); then
        echo "Usage: transplant <commit | n> <to_branch>"
        echo "  transplant abc1234 feature  — move commit abc1234 to 'feature'"
        echo "  transplant 3 feature        — move last 3 commits to 'feature'"
        return 1
    fi

    local source="$1"
    local target_branch="$2"
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

    echo "Transplanting $commit_count commit(s) from '$original_branch' to '$target_branch':"
    for c in "${commits[@]}"; do
        git log --oneline -1 "$c"
    done
    echo

    confirm=''
    while [[ $confirm != "y" && $confirm != "n" ]]; do
        read -s -n1 -p "Proceed? (y/n) " confirm </dev/tty || {
            echo "Aborted by user"
            return 1
        }
    done
    echo
    [[ $confirm == "n" ]] && { echo "Transplant aborted."; return 1; }

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

    echo "Done! $commit_count commit(s) transplanted to '$target_branch'."
}

# Remove a file from entire git history as if it never existed
# Usage: decimate <file> [--all]
decimate() {
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

    local confirm=''
    while [[ $confirm != "y" && $confirm != "n" ]]; do
        read -s -n1 -p "Proceed? (y/n) " confirm </dev/tty || {
            echo "Aborted by user"
            return 1
        }
    done
    echo
    [[ $confirm == "n" ]] && { echo "Decimate aborted."; return 1; }

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

        if ! git checkout "HEAD@{$steps}" 2>/dev/null; then
            echo "Cannot move forward. Try 'reflog' to see recent commits."
            return 1
        fi

        if ! git symbolic-ref --short HEAD 2>/dev/null >/dev/null; then
            local branch_at_head
            branch_at_head=$(git branch --points-at HEAD 2>/dev/null | sed -n 's/^[* ] //p' | head -1)
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
    local remote="$1"
    local page="$2"

    # Validate input
    if [[ -z "$remote" ]]; then
        echo "SYNTAX: openweb [remote] [issues|pr|pull-request|wiki|settings]"
        return 1
    fi

    # Get remote URL
    local remote_url
    remote_url=$(git remote get-url "$remote" 2>/dev/null)

    if [[ -z "$remote_url" ]]; then
        echo -e "\e[91m\e[1mError: ...'$remote''s URL is empty?? See if it exists (simple type 'remote') \e[0m"
        echo "SYNTAX: openweb [remote] [issues|pr|pull-request|wiki|settings]"
        return 1
    fi

    # Clean URL and append page path
    remote_url="${remote_url%.git}"
    log "Base URL: ${remote_url}"

    case "$page" in
    "issues") remote_url+="/issues" ;;
    "pr" | "pull-request") remote_url+="/pulls" ;;
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

# Execute individual command
execute_command() {
    local EXPOSED_FUNCS=("openweb" "squash" "discard" "reword" "fzf" "movehead" "undo" "redo" "transplant" "decimate")
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
        echo "Do you even have to type 'git' in here? Sure."
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
                local branch_name="patch-$(date +%Y%m%d-%H%M%S)"
                git checkout -b "${branch_name}" || {
                    echo -e "\e[91mError: Failed to create branch ${branch_name}\e[0m"
                    return 1
                }
                echo "Created and switched to branch: ${branch_name}"
                ;;
            3)
                local worktree_dir=".worktrees/patch-$(date +%Y%m%d-%H%M%S)"
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

                # Get the arguments (everything after first word)
                local args="${cmd#* }"

                # If cmd had no spaces, args will equal cmd (no arguments)
                # Otherwise, split args into arrays to ensure word splitting
                if ! [[ "$args" == "$cmd" ]]; then
                    IFS=' ' read -r -a args <<<"$args"
                else
                    args=()
                fi

                # Call the function with args
                # shellcheck disable=SC2068
                $fn ${args[@]} # Don't quote $args - we want word splitting
                exit_code=$?
                ((exit_code == 0)) && history -s "${cmd}"
                return $exit_code
            fi
        done

        # Default: treat as git command
        log "Executing Git command: ${git_path} ${cmd}"
        eval "${git_path}" "${cmd}"
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
    elif [[ -f "$GITSH_RC_FILE" && ((PRINT_HEADER == 1)) ]]; then
        # Offer to migrate from GitSh
        cat <<EOF
Found GitSh configuration file!

Would you like to copy it for use with Igitari?
This will create a copy as .igitari-rc without affecting your GitSh setup.

Note: Functionality may not be 100% compatible with GitSh.
EOF
        read -rp "Copy GitSh config? (y/n): " answer

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
        echo
    fi
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

# Default action when empty command is entered
handle_empty_command() {
    # Could display status here (per GitSh default), but currently does nothing
    # display_git_status
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
    read -rp "Overwrite with latest? (Y/N) " -n1 response
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

    read -rp "Update now? (Y/N) " -n1 response
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
        read -rp "Update now? (Y/N) " -n1 response
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
main "$@"

#--|END
