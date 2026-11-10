# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Igitari is a single-file Bash script (`igitari.sh`) that provides an interactive Git shell — a "kindly powerful Git companion." It reduces friction in daily Git workflows with an interactive REPL, smart tab completion, and helper commands for common operations.

**Version:** 3.11.1 | **License:** AGPL-3.0-or-later

## Single-File Architecture

Everything is in `igitari.sh` (~2250 lines). The script is organized into labeled sections following a **three-tier model**, each marked with `#--|SECTION_NAME [TIER]`:

### Tiers

- **`[STDLIB]`** — Generic portable Bash utilities. No Git knowledge, no Igitari context. Safe to copy into any Bash project.
  - `LOGGER` — Logging function with formatting options (`log n p "msg"`)
  - `ARG_PROCESSOR` — Multi-format argument validation (Unix/DOS/GNU styles via `validate_arg()`)
  - `DIR_CHANGE` — Working directory setup
  - `HIST_MGMT` — Command history initialization
  - `RC_SETUP` — RC file sourcing for user overrides

- **`[GITLIB]`** — Git-aware helpers not tied to Igitari's UI. Reusable in any Git-related Bash tool.
  - `GIT_HELPERS` — `squash()`, `discard()`, `reword()` (high-level Git operations)
  - `GIT_FUNC` — `parse_git_branch()`, `dirty_check()`, `display_git_status()`, `check_git_repository()`
  - `FORGE_ADAPTER` — optional `gh`/`glab` detection and object parsing. No network, no user-visible wording; fails silently and reports by exit status. Must never run on prompt or `state`.

- **`[IGITARI]`** — Application layer. Igitari-specific features only.
  - `CONSTANTS` / `CONFIG_VARS` — Script configuration and runtime variables
  - `SANITY_CHECKS` — Git installation check, local path setup
  - `TABBER` — Tab completion system: dispatch table mapping commands to handler functions, bound to Tab via `bind -x`
  - `MOVEHEAD` — `movehead forward/backward <steps>` for relative HEAD movement
  - `EXTRAS` — FZF-dependent features (`fzf()`, `openweb()`)
  - `CMD_PROC_ENGINE` — Command parsing with operator support (`&&`, `||`, `;`)
  - `SIGHANDLERS` — Signal handling for SIGINT, SIGTERM, EXIT
  - `INTERFACES` — Startup header, dynamic prompt generation, empty command handling
  - `GIST_UPDATER` — Self-update mechanism (checks GitHub for newer version, background check with signal notification)
  - `MAIN` — Entry point and main interactive loop

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

## Key Design Patterns

- **`validate_arg()`** — A centralized argument matcher that accepts Unix (`--help`), short (`-h`), DOS (`/?`), and bare-word forms.
- **`register_error_handler()`** — Plugin-style pattern: handlers are called in order until one claims the error (returns 0). Common handlers are registered via `register_error_handler __specific_handler_name`.
- **Command dispatch** — Commands not matched to built-in functions are forwarded to `git <cmd>` via `run_git_with_intercept()`.
- **Operator splitting** — `process_command_line()` splits input on `&&`, `||`, `;` using sed with arithmetic-based `should_execute` state tracking (no eval on the user's raw input).

### What earns a command

> Igitari adds verbs raw git lacks — commands you would otherwise **write a script for**. It never renames a verb raw git already has.

Two tests, both must pass:

1. **Is the manual version a command or a procedure?** `squash 3`, `reword <sha>`, `transplant`, `decimate`, `undo`, `conflict show` all replace a multi-step sequence or scripted interactive rebase. `stage`/`unstage` would wrap `git add -A` and `git reset HEAD` — one command each, so they do not qualify.
2. **Does the word collide with git's own vocabulary?** `reword`, `transplant`, `decimate`, `undo` do not exist in git, so `git reword` fails loudly and the user knows they are somewhere else. A near-miss like `stage` does exist (`git stage` is an alias for `add`) and would sort-of work while meaning something slightly different — that is how a dialect gets built.

This is why there is no `stage`, `unstage`, `bisect`, `submodule` or `worktree` command. Git's versions are forwarded verbatim, hints and all: a dev hitting `Maybe you wanted to say 'git add .'` in Igitari learns something that transfers; a dev typing `stage` learns something that does not.

The failing feature request is always a *wrapper*, and it always looks justified by git's confusing surface (`add .` silently skips deletions). Fixing that confusion by teaching a different word is the wrong direction — the user then never meets the choice.

### The forge exception, and its own guardrail

Both tests above are about *git* commands, where a near-miss is the danger. `forge` is judged differently because `git forge` fails loudly — nothing learned there can be mistaken for git — while the operations it holds (a PR, an issue, a release) live on the remote and have no argument slot in any git verb.

So a forge verb earns its place by being remote-native, and the rule that keeps it from becoming a second program is narrower: **only the noun is translated**. `pr:32` becomes `gh`'s or `glab`'s word for that object; every other argument goes to the provider untouched. Never invent or translate a provider flag — a wrong flag should fail with the client's own error, so its manual stays correct.

Blending comes first. If an existing command's grammar already holds the operation, extend it (`openweb origin issues 553`, `fzf prs`, `guess pr`) rather than adding a verb. `forge` is for what only the remote can answer. Nothing may touch the network on the prompt or `state`, and any absent client must leave existing behaviour untouched.

## Development

Since this is a single Bash script, there is no build system and no package manager. The test
harness is plain Bash too, so it needs nothing installed.

- **Making changes** — Edit `igitari.sh` directly. The script is run in-place (symlinked to `~/.local/bin/igitari`).
- **Manual testing** — Run `./igitari.sh` in the repo root. The `test-repo/` directory is a throwaway git repo for manual smoke-testing.
- **Automated tests** — `tests/run.sh` runs every case in `tests/cases/*.sh` (roughly 180 tests) and
  exits 0 only when all pass. `tests/run.sh <pattern>` runs only matching test names; `--list` shows
  them with the file each lives in. Shared scaffolding is in `tests/lib/harness.sh`. Adding a test
  means adding a function to the right case file — there is nothing to register.
- **ShellCheck** — Run `shellcheck igitari.sh` to check for common issues. The script uses `# shellcheck disable=SC...` annotations for intentional overrides.
- **Naming conventions** — Global variables are `UPPER_CASE`. Functions are `snake_case`. Private helpers are prefixed with double underscore (`__check_fzf`). Section labels use `#--|SECTION_NAME [TIER]`.

## Code Conventions

- Bash with `set +H` (disable history expansion for `!` compatibility)
- `readonly` for constants, plain variables for config flags
- Error messages use colored output (`\e[93m` for yellow warnings, `\e[91m` for red errors)
- `log()` function for debug output (guarded by `DO_LOGGING=1` flag, enabled with `--verbose`)
- `eval` used intentionally in limited contexts (shell commands and git dispatch) — care needed to avoid injection
- The `#--` markers in section headers are kept for navigation. They are **not** consumed by any tool any more: the split-into-`SRC/` experiment (DISASSEMBLER.sh) was abandoned, and the single file is a deliberate selling point — Igitari is portable precisely because she is one script you can drop anywhere. Keep the markers tidy for readers; do not reintroduce a build step.
