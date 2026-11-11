# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Igitari is a single-file Bash script (`igitari.sh`) that provides an interactive Git shell — a "kindly powerful Git companion." It reduces friction in daily Git workflows with an interactive REPL, smart tab completion, and helper commands for common operations.

**Version:** 7.4.0 | **License:** AGPL-3.0-or-later

## Origin, and goal

Two different things, and conflating them is how a project loses its plot.

**The origin stays.** She began as a throwaway: a three-minute script from ChatGPT, born of a real annoyance — typing `git` over and over while fixing conflicts, before lazygit was known to her. The shape was borrowed from bluetoothctl, because bluetoothctl already had the interface she wanted for something else: a ctl for a domain. Version 1.0's own banner said it *"solves a problem that doesn't exist"*, the licence was a custom WTFPL, and the distribution was a GitHub gist with a `le-changelog.txt` beside the script.

None of that needs explaining away. It is the before-picture, and without it the next phase is only a slogan.

**The permission came in December 2025**, in the pull request that renamed her: *"I have added so many QoL changes ... which means I poured more hours into it -> more care towards the codebase."* That was the week the licence hardened from WTFPL to AGPL, the name became Igitari, the kitsune arrived, and the direction was declared: **"make git kindly powerful"** — delve into the true power of git while reducing the risk as much as a shell allows. *Because you shouldn't experience falling in the cliff just to be good at avoiding it.*

**The goal is what came after**, and it is not a retroactive origin. The goal is **lazygit-parity in her own domain**: the intuitive interface for git, in the shell. That is the same ambition the December pull request described in general terms, with a concrete benchmark attached, and it is still accreting. The shell has three intuition channels where lazygit has a screen, and she has all three:

| lazygit | Igitari |
|---|---|
| status bar | the prompt: branch, `*` dirty, `^` staged, `_` stash |
| status panel | `state` — branch, upstream, ahead/behind, operation, work. It pipes. |
| mouse and key navigation | `fzf` — commits, tags, reflogs, stashes, dangling objects, and the staged / unstaged / tracked / untracked file lists |
| **the rebase todo list** | **not yet** |

The last row is the remaining distance. `reword` already runs a scripted `git rebase -i`, so the machinery is here; what is missing is the list to drive it.

**Do not write the goal into the origin.** A document that says she was always meant to be lazygit-in-words is a lie about May 2025, and it is the kind of lie a design document tells when nobody wrote down where the ambition came from.

## Single-File Architecture

Everything is in `igitari.sh` (~8000 lines). The script is organized into labeled sections following a **three-tier model**, each marked with `#--|SECTION_NAME [TIER]`:

### Tiers

- **`[STDLIB]`** — Generic portable Bash utilities. No Git knowledge, no Igitari context. Safe to copy into any Bash project.
  - `LOGGER` — Logging function with formatting options (`log n p "msg"`)
  - `CONFIRM` — `__igitari_confirm`, the one prompt. Returns 2 when it could not
    ask (no tty), and every caller treats that as abort — "couldn't ask" is not
    "yes".
  - `ARG_PROCESSOR` — Multi-format argument validation (Unix/DOS/GNU styles via `validate_arg()`)
  - `DIR_CHANGE` — Working directory setup
  - `HIST_MGMT` — Command history initialization
  - `RC_SETUP` — RC file sourcing for user overrides
  - `TREEDRAW` — `__tree_render`, a sorted list of paths laid out as a tree. No git, no colours, nothing to Igitari; the drawing is byte-identical to `tree --charset=ascii` and safe to copy out.

- **`[GITLIB]`** — Git-aware helpers not tied to Igitari's UI. Reusable in any Git-related Bash tool.
  - `GIT_HELPERS` — `squash()`, `discard()`, `reword()` (high-level Git operations)
  - `GIT_FUNC` — `parse_git_branch()`, `dirty_check()`, `display_git_status()`, `check_git_repository()`
  - `FORGE_ADAPTER` — optional `gh`/`glab` detection and object parsing. No network, no user-visible wording; fails silently and reports by exit status. Must never run on prompt or `state`.

- **`[IGITARI]`** — Application layer. Igitari-specific features only.
  - `CONSTANTS` / `CONFIG_VARS` — Script configuration and runtime variables
  - `DATA_SHOWOFF` — Table and field formatting for human-readable output (`state`, `conflict show`, transfer classification)
  - `SANITY_CHECKS` — Git installation check, local path setup
  - `TABBER` — Tab completion system: dispatch table mapping commands to handler functions, bound to Tab via `bind -x`
  - `MOVEHEAD` — `movehead forward/backward <steps>` for relative HEAD movement
  - `SESSION_CONFIG` — `config session <key> <value>`, the fourth git scope, passed
    through `GIT_CONFIG_COUNT` env vars. Writes nothing to disk.
  - `EXTRAS` — FZF-dependent features (`fzf()`, `openweb()`)
  - `CMD_PROC_ENGINE` — Command parsing with operator support (`&&`, `||`, `;`)
  - `SIGHANDLERS` — Signal handling for SIGINT, SIGTERM, EXIT
  - `INTERFACES` — Startup header, dynamic prompt generation, empty command handling
  - `GIST_UPDATER` — Self-update mechanism. Resolves the release boundary from
    the "Bump version to X" commit, fetches the commit range between the
    installed SHA and the head, and notifies in the background by signal. See
    "The release model" below.
  - `MAIN` — Entry point and main interactive loop

Two exposed commands sit in `[IGITARI]` without a `#--|` marker of their own:
`guess()` (strict stdout contract, so `checkout $(guess prior)` works) and
`prune_branches()` (the user-facing word is `prune-branches`; the dispatcher
translates the hyphen to an underscore at the call site, since bash function
names cannot contain one).

### Execution Flow

```
main()
  ├─ setup_rc_file()        — Source user RC overrides
  ├─ process_arguments()    — Parse CLI flags
  ├─ check_git_installation() / check_localpath()
  ├─ setup_working_directory()
  ├─ setup_git_completion() / setup_custom_tab_completion()
  ├─ setup_command_history()
  ├─ initialise_keybinds()
  ├─ print_header()
  ├─ do_update()
  └─ main_loop()
       └─ generate_prompt() + process_command_line()
            └─ execute_command()      — dispatch to git, shell (>), or built-in commands
                 └─ run_git_with_intercept() — stderr capture + error intercept
```

## Personality — who she is, and who writes her

Igitari is a **character**, not a mascot bolted onto a tool. She is a *sassy
robot foxgirl* who **means her professionalism**. The sass and the competence
are not in tension; the joke is that she is playful about small things because
she is completely straight about serious ones. Read the section below as
authoring guidance, not flavour text — the voice is a feature with rules, and
breaking it is a regression.

### The author is a character too, and she makes mistakes

Igitari is written by a person who signs her work *she*. When Igitari says
**"she made a mistake writing it"** in the update path, *she* is the author.
That is deliberate and it is the warmest line in the program:

```bash
echo "This version is broken. Either you're using an outdated Bash or she made a mistake writing it. Try again later?"
```

Three things to take from it:

- **The author admits fault in the third person, in her own voice.** A bug is
  not an anonymous "an error occurred"; it is the author's mistake, said out
  loud, in the same breath as the tool being broken.
- **Never make it self-deprecating.** She says *she made a mistake*, then
  offers the two real causes. No grovelling, no apology loop, no blaming the
  user for a bug that is hers.
- **When you write error text in this repo, you are writing as her about her
  author.** The same rule applies to your own additions: own the fault
  plainly, name the likely cause, move on.

Same register, same brevity: `"PLEASE Don't source this script — run it
directly, or set IGITARI_TEST=1"` — capitals because it matters, no insult, and
the fix offered in the same line.

### Where the sass is allowed

Cheek about *the situation*, never about *the person*:

| Allowed | Not allowed |
|---|---|
| The install is missing: `Warning: You're accessing fzf-based features but it's not installed on your system! The command name should've been obvious though :/` | Anything implying the user is stupid |
| A remote that is not a forge: `This isn't a forge I can talk to.` | Sneering at their choice of host |
| An unknown flag/typo — a dry, one-line correction | A paragraph of jokes while they are stuck |
| Empty results: `Nothing to discard.` / `Nothing to redo.` | Cheerleading, exclamation marks, or emoji spam |

The `:/` and the `Hi!` in the banner are the ceiling of the whimsy. If a line
needs a winking face to land, it is not funny enough to include.

### Where she is flat, and must stay flat

Anything that **loses work or rewrites history** gets zero jokes. This is the
rule that makes the sass survivable:

```bash
echo "This will remove '$target_file' from $commit_count commit(s) in $scope_desc, as if it never existed."
echo "WARNING: This rewrites history! Do not use on pushed branches (without concrete reason, that is)."
```

Note the shape: a **precise statement of what will happen** (count, scope,
"as if it never existed"), then a warning, and only *then* — inside a trailing
parenthetical — the smallest possible wink. The wink never comes before the
warning, and never replaces a number.

Concretely:
- `discard`, `decimate`, `transplant`, `squash`, `reword`, `conflict throw`,
  `prune-branches` — numbers first, personality second, and second may be
  nothing at all.
- Never a joke in a confirmation prompt. A prompt is read once, by someone
  about to do something irreversible.
- Never guess the user's intent back at them in a failure message.

### Typos and chatter

Cheeky, brief, and *useful in the same line*: name what was wrong, offer the
word they probably wanted, move on. One line. She is not annoyed, she is not
amused enough to go on about it.

### Never describe the characterisation

She does not introduce herself as a character, explain her humour, or narrate
her own personality ("as your sassy assistant, I…"). She speaks *as* herself.
The one permitted reference to her own nature is the author saying *she made a
mistake writing it*, because that is about **her conduct**, not her concept.

### Register check, before you commit output text

1. Would she say this to someone mid-conflict-resolution? If it is long, cut it.
2. Is the number, path, or branch name in it? If it is serious and the answer
   is no, it is wrong.
3. Does any joke survive if the user is having a bad day? If not, delete it.
4. Did I write "she" where I meant the author? Then the third person is right,
   and the fault is admitted plainly.

## Key Design Patterns

- **`validate_arg()`** — A centralized argument matcher that accepts Unix (`--help`), short (`-h`), DOS (`/?`), and bare-word forms.
- **`register_error_handler()`** — Plugin-style pattern: handlers are called in order until one claims the error (returns 0). Common handlers are registered via `register_error_handler __specific_handler_name`.
- **Command dispatch** — Commands not matched to built-in functions are forwarded to `git <cmd>` via `run_git_with_intercept()`.
- **Operator splitting** — `process_command_line()` splits input on `&&`, `||`, `;` with `__split_operators()`, a quote-aware scanner that leaves an operator inside quotes or inside a `$(...)` alone (no eval on the user's raw input). The flags it sets are per-operator decisions on the last command that ran, which is POSIX's left-to-right rule.

### What earns a command

> Igitari adds verbs raw git lacks — commands you would otherwise **write a script for**. It never renames a verb raw git already has.

Two tests, both must pass:

1. **Is the manual version a command or a procedure?** `squash 3`, `reword <sha>`, `transplant`, `decimate`, `undo`, `conflict show` all replace a multi-step sequence or scripted interactive rebase. `stage` would wrap `git add` — one command, so it does not qualify. `unstage` also fails this test and is allowed anyway; see "The one exception" below.
2. **Does the word collide with git's own vocabulary?** `reword`, `transplant`, `decimate`, `undo` do not exist in git, so `git reword` fails loudly and the user knows they are somewhere else. A near-miss like `stage` does exist (`git stage` is an alias for `add`) and would sort-of work while meaning something slightly different — that is how a dialect gets built.
3. **Does the word collide with bash's vocabulary?** Test 2 says *git's*
   vocabulary, but the sharper hazard is the shell's. A **function** named
   `continue` **shadows the builtin of the same name**, so every `continue`
   statement in every loop of `igitari.sh` calls the command instead. Twenty
   call sites printing "Nothing in progress to continue." in the middle of
   unrelated work; the suite went 191 passed to 173, 22 failures across six
   case files that had nothing to do with it.

   The hazard is the function, not the word. A verb does not have to be a
   function: `continue` is a case arm in `execute_command`, with the
   implementation under a name the builtin cannot collide with. Nothing
   shadows anything — not this script, not the test harness, and not the
   user's own RC file, which is sourced into this shell. `abort` is an
   ordinary function and needs no such care: bash has no `abort`.

   Check `type -t <word>` before exposing a name *as a function*. Anything
   that appears in the script's own loops is out as a function: `continue`,
   `break`, `return`, `wait`, `test`, `exec`, `cd`, `read`, `source`,
   `eval`, `shift`, `set`, `unset`, `trap`, `kill`, `time`, `command`,
   `type`, `hash`, `getopts`, `readonly`, `local`, `export`, `declare`,
   `echo`, `printf`, `true`, `false`.

   **The rule generalises: the name must be free in both namespaces she runs
   in**, because she is a program made of shell. A name that cannot be a
   function may still be a verb, if it can be a case arm instead.

   ### The fourth test: is the word even meaningful here?

   A name can clear all three tests and still be the wrong word, because the
   thing it names only exists in a context she does not have.

   `break` and `next` are **loop** statements. They take their meaning from
   an enclosing `while` or `for` — outside one, bash errors with *"only
   meaningful in a 'for', 'while' or 'until' loop"*. At her prompt there is
   no loop: you type a line, she runs it, she returns the prompt. A user
   cannot write `prune-branches && break` and have it mean anything, because
   the nesting that would give it a referent does not exist. She is not that
   composable — and this is the doc saying so deliberately, not a limitation
   to be fixed later. An operator layer joining two commands is not a
   control-flow language.

   `continue` is the interesting one, because it is a loop statement in bash
   and a procedure in git. It was renamed once, to `resume`, on the grounds
   that it promised loop semantics she cannot honour. That was the wrong
   call, and the reason is the second test rather than the fourth: git
   already uses the word for exactly this operation — `git rebase
   --continue`, `git cherry-pick --continue` — so `continue` is git's own
   vocabulary rather than a dialect of it, and a user who has just read a git
   error mentioning `--continue` already knows the word. `resume` matched
   nothing in git, so the rename swapped one dialect word for another while
   breaking the pair with `abort`, which is `git rebase --abort`.

   Ask it before naming anything: **would this word still mean something to
   someone who never writes a loop?** `prior`, `gone`, `throw`, `continue`,
   `decimate` — yes. `break`, `next`, `yield`, `await` — no.

This is why there is no `stage`, `bisect`, `submodule` or `worktree` command. Git's versions are forwarded verbatim, hints and all: a dev hitting `Maybe you wanted to say 'git add .'` in Igitari learns something that transfers; a dev typing `stage` learns something that does not.

The failing feature request is always a *wrapper*, and it always looks justified by git's confusing surface (`add .` silently skips deletions). Fixing that confusion by teaching a different word is the wrong direction — the user then never meets the choice.

### The one exception: `unstage`

`unstage` breaks the rule on purpose, and the exception is **grandfathered once**,
not a precedent.

The rule above says the manual version must be a *procedure*, and `unstage` is a
single `git restore --staged` — or, for the whole tree, a single `git reset`. By
the letter of the rule, it loses. By every other measure it is the most-typed
non-verb in daily git, and git's refusal to name it is not a design insight — it
is boilerplate the designer mistook for elegance:

- `stage` at least owns its keep, because it exists and translates cleanly to
  `add`. You can type `git stage` and get what you meant.
- `unstage` has **no inverse word at all**. The answer is `git restore --staged`,
  or `git reset HEAD <file>` depending on which manual page you land on, which
  is three words for a direction a human brain already has.
- Every tool that ever gave people a simple, straightforward procedure — lazygit,
  the various GUIs — has a stage/unstage pair. Users arrive having *already*
  learned it. Git then says no, and they are annoyed.
- And the newcomers never get the word at all. Git's boilerplate was written for
  people who already have the vocabulary in their fingers; hand a beginner
  `git restore --staged` before they know what a stage *is*, and you are asking
  them to infer the rest. The designer optimised for the expert and spent the
  beginner's afternoon on it.

The mind wants a verb and its inverse. `stage` / `unstage` is the smallest such
pair git has, and refusing the second half teaches nothing: there is no choice
being made at `git restore --staged` worth meeting, only syntax to memorise.

The derivation is not git's to invent and not the user's to guess: stage, "un"
it, unstage. The word is already in the language, and git's refusal to say it
is a refusal with no design content behind it.

So: `unstage` is allowed, **and it is the only one**. `stage` is still refused,
because `git stage` works. The symmetry is deliberately broken in one direction
and that asymmetry is the whole point of the exception — the missing word is the
one being supplied, not the one git already gave you.

The exception holds only because the *grammar* matches too. `unstage` takes the
same pathspecs and the same flags as `git add`, because it is `git add` run
backwards: `-A`, `-u`, `-n`, `-p`, `--`, and the same "Nothing specified,
nothing unstaged" when no pathspec is given. A shorter word with a different
argument shape would be a dialect — the exact thing the rule above exists to
prevent — and would not qualify. The missing word is what earns the exception;
matching git's own grammar is what makes it safe.

Anyone proposing a second exception has to show it meets the same three tests
this one does, which are stricter than the note above:

1. **The concept has no git word at all**, not merely a confusing one.
2. **Users arrive already knowing the word** from prior tools, so it needs no
   teaching.
3. **Refusing it supplies nothing to learn.** If the git alternative is a real
   choice worth meeting, forward it instead.

`unstage` passes all three. Very little else will.

### The forge exception, and its own guardrail

Both tests above are about *git* commands, where a near-miss is the danger. `forge` is judged differently because `git forge` fails loudly — nothing learned there can be mistaken for git — while the operations it holds (a PR, an issue, a release) live on the remote and have no argument slot in any git verb.

So a forge verb earns its place by being remote-native, and the rule that keeps it from becoming a second program is narrower: **only the noun is translated**. `pr:32` becomes `gh`'s or `glab`'s word for that object; every other argument goes to the provider untouched. Never invent or translate a provider flag — a wrong flag should fail with the client's own error, so its manual stays correct.

Blending comes first. If an existing command's grammar already holds the operation, extend it (`openweb origin issues 553`, `fzf prs`, `guess pr`) rather than adding a verb. `forge` is for what only the remote can answer. Nothing may touch the network on the prompt or `state`, and any absent client must leave existing behaviour untouched.

### The release model

Igitari rolls, bounded by bump commits. Neither half is negotiable on its own, and together they are what the version number means.

**What this section is.** Rules, not state. Where a number or a quoted example appears, it belongs to one named release and will not describe the next one — the arithmetic for any given release lives in that release's bump commit body, which is where the tree keeps it. A section that restated the current release's counts would go stale the way the roadmap does, and would answer questions nobody asked it.

**The version is a vector over what the tree has accumulated, wearing semver's shape.** The major counts breaking changes — by judgement, not by a mechanical rule, because the judgement is the whole point. The minor and the patch count the rest of the accumulation. It is not strict semver and does not claim to be: the numbers are counts over the repository, not a compatibility promise to anyone.

**Releases are bounded by the "Bump version to X" commit.** That commit is the release marker, and everything after it belongs to X until the next bump — so a version names a *group* of commits, not a point release. A mid-group commit legitimately carries its group's number, and a version jump is therefore not a count of releases: one release can carry several breaking changes at once.

**The commits are the changelogs.** The bump commit's body is the release note: what was added, what changed, what broke, and which release points were missed. The commit subjects are what the updater shows a user. Nothing summarises the tree over the tree — a curated `CHANGELOG.md` would duplicate what the repository already says and go stale on the next commit, which is the same reason the updater shows subjects rather than the bump body.

Three consequences, each of which has been proposed and declined:

- **Do not "fix" the version numbers to be semver-compliant.** The shape is deliberate; the contents are the author's.
- **Do not add a breaking-changes flag derived from the version delta.** The subjects already carry the severity, because they are written to say what changed: *"discard now asks before throwing work away"* is the severity statement. A synthetic flag re-encodes it in a weaker form.
- **Do not add a changelog file.** Same reason as the one above, and it is the reason the rule exists.

**The updater resolves the release boundary from the bump commit**, not by comparing version numbers, and it fetches the commit range between the installed SHA and the head. That range has to be asked for explicitly: GitHub's compare endpoint answers a range with the *last* 250 commits unless a page is requested, which silently truncates the changelog for anyone far behind their install. See `_UPDATER_COMPARE_PAGE_SIZE` and `_UPDATER_MAX_COMPARE_PAGES` in `igitari.sh`.

**A version number is consumed by nothing.** No library API, no plugin pinning a range, no package manager resolving a dependency. That is why a non-standard scheme costs nothing here, and it is also why the packaging route stays open: if a package manager ever ships her, the updater has to be switched off (`CHECK_UPDATES=0`) rather than left to fight it, because `_updater_replace` refuses only to overwrite a file inside a git checkout and would happily clobber a package manager's copy.

## Development

Since this is a single Bash script, there is no build system and no package manager. The test
harness is plain Bash too, so it needs nothing installed.

- **Making changes** — Edit `igitari.sh` directly. The script is run in-place (symlinked to `~/.local/bin/igitari`).
- **Manual testing** — Run `./igitari.sh` in the repo root. The `test-repo/` directory is a throwaway git repo for manual smoke-testing.
- **Automated tests** — `tests/run.sh` runs every case in `tests/cases/*.sh` (226 tests) and
  exits 0 only when all pass. `tests/run.sh <pattern>` runs only matching test names; `--list` shows
  them with the file each lives in. Shared scaffolding is in `tests/lib/harness.sh`. Adding a test
  means adding a function to the right case file — there is nothing to register.
- **Two kinds of case** — most assert against a fixture: an expected value, written by hand.
  That catches a change in behaviour, and it cannot catch a behaviour that was never right, because
  the fixture encodes the same misunderstanding. `tests/cases/oracle.sh` asks a different question:
  not "does it do what the test says" but "does it do what an independent implementation says".
  The oracle for the operator layer is **bash**; the oracle for the updater's commit range is
  **git**. When a thing re-implements something, that something is the authority.
- **ShellCheck** — Run `shellcheck igitari.sh` to check for common issues. The script uses `# shellcheck disable=SC...` annotations for intentional overrides.
- **Naming conventions** — Global variables are `UPPER_CASE`. Functions are `snake_case`. Private helpers are prefixed with double underscore (`__check_fzf`). Section labels use `#--|SECTION_NAME [TIER]`.

## Code Conventions

- Bash with `set +H` (disable history expansion for `!` compatibility)
- **Bash 4.3+**, and the README says so. Namerefs (`local -n`) are used by the argument helpers (`__split_argv`, `__split_operators`) and the forge adapter; they arrived in 4.3. The requirement came in with the argument-processing design and the README kept the older, looser claim, so a user on 4.0–4.2 would have hit a nameref error instead of a sentence explaining it.
- `readonly` for constants, plain variables for config flags
- Error messages use colored output (`\e[93m` for yellow warnings, `\e[91m` for red errors)
- `log()` function for debug output (guarded by `DO_LOGGING=1` flag, enabled with `--verbose`)
- `eval` used intentionally in limited contexts (shell commands and git dispatch) — care needed to avoid injection
- The `#--` markers in section headers are kept for navigation. They are **not** consumed by any tool any more: the split-into-`SRC/` experiment (DISASSEMBLER.sh) was abandoned, and the single file is a deliberate selling point — Igitari is portable precisely because she is one script you can drop anywhere. Keep the markers tidy for readers; do not reintroduce a build step.
