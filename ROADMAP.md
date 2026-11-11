# Igitari — Roadmap

Where she is, what is left, and why the rejected things stay rejected.

This file replaces an older one that had accumulated claims the code had since
outgrown: a `HELP_TEXT` registry listed as future work (it exists), session
config listed as future work (it exists), and a "not doing" entry for a test
suite and CI that both now exist. Everything below was checked against
`igitari.sh` and `tests/` before being written down.

## Where she is

| | |
|---|---|
| Version | 7.4.0 |
| Size | ~8000 lines, 183 functions, one file |
| Tests | 220, in 17 files under `tests/cases/` |
| CI | shellcheck + parse check + suite, `.github/workflows/tests.yml` |
| Verbs git lacks | `forge`, `guess`, `prune-branches`, `conflict`, `state`, `squash`, `discard`, `reword`, `transplant`, `decimate`, `undo`, `redo`, `movehead`, `untrack`, `retrack`, `unstage`, `abort`, `continue`, `openweb`, `fzf` |

## What is done

Recorded because the old roadmap kept listing these as pending, and a roadmap
that overstates the work left is as useless as one that understates it.

- **Help pages.** `HELP_TEXT` registry, one page per exposed command, reached
  with `help <cmd>`. Case-arm verbs are claimed too.
- **Session config.** `config session <key> <value>` and friends — the fourth
  git scope, `GIT_CONFIG_COUNT`-based, nothing on disk.
- **`guess`.** `prior`, `merge-base`, `rebase-base`, `root`. Strict contract:
  the value is the only thing on stdout, empty on failure.
- **Comments and line continuation.** One quote-aware scanner serving both;
  a naive `sed` fails every test in `tests/cases/input_scan.sh`.
- **`forge`.** gh/glab detection, noun translation only. See below.
- **`prune-branches`.** Three conditions as selectors, delete flag following
  the reason. This is where the git-extras port began and ended; see the
  rejected list.
- **`conflict throw`.** Names the loser, which survives the rebase inversion.
- **`abort` and `continue`.** Stop or carry on a half-finished merge, rebase,
  cherry-pick, revert or am. Git's own words, and the pair git already has.
  `continue` is a case arm rather than a function, because a function of that
  name would shadow the builtin — see "Not doing" below.
- **Tab completion** over subcommand arguments rather than siblings.

## What is left

### 1. Grouping: `(a || b) && c`

Unbuilt, and the only thing gitsh does not do either.

`process_command_line` splits on `&&`, `||`, `;` with `__split_operators()`,
a quote-aware scanner — an operator inside quotes or inside a `$(...)` is part
of the message, not an operator — and decides each operator on the status of the
last command that ran, which is POSIX's left-to-right rule. What it still cannot
do is express grouping: that needs an expression parser with precedence over the
scanner's output. `__split_argv` already tokenizes quotes and `$(...)`, so the
pieces exist — what is missing is the parser.

Decide first, before any code:
- Igitari's current left-to-right matches POSIX `sh`. gitsh binds `&&` tighter
  than `||`, which is a deviation. **Follow POSIX**, since the whole point of
  the operator layer is that it behaves like the shell you already know.
- Grouping must not soften the no-eval rule. The parser produces an argv and
  an order, never a string that gets evaluated.

Lowest priority of anything here: the payoff is rare and the engine change is
the riskiest thing on this list.

### 2. Extension points in the RC

`~/.igitari-rc` is sourced at startup and can define bash functions, but a
function defined there is not reachable as a command: dispatch matches
`EXPOSED_FUNCS`, a list baked into `execute_command`.

Two possible seams, in order of preference:
- **`register_command <name>`** — appends to `EXPOSED_FUNCS` and optionally
  registers a `HELP_TEXT` page. One line in the RC, real command.
- **Fall through to `type -t`** — if no exposed function matches and a shell
  function by that name exists, call it. Zero API, but it makes every typo
  that happens to collide with a function name into a command.

Prefer the explicit one. A new word appearing in her vocabulary should be a
deliberate act, not a side effect of what happens to be in scope.

### 3. The rebase todo list

The one lazygit channel she does not have. lazygit's signature interaction is
the list: reorder, squash, drop, edit a set of commits, with a preview of what
you get. She has the individual operations as words — `squash`, `reword`,
`transplant`, `decimate`, `movehead` — and the machinery, because `reword`
already runs a scripted `git rebase -i` with an editor that rewrites a line.

What is missing is the list to drive it with.

The form it should take is a `fzf` picker over the commits in the range, and
the thing it produces is the same scripted `rebase -i` that `reword` already
runs — one editor script, several lines. Which also means the safety rule
holds: the picker shows what would happen before it happens, and nothing is
rewritten on a guess.

This is the largest remaining piece of the goal (lazygit-parity in the
shell), and it is a known-shaped job rather than an open one.

### 4. `movehead` reflog fallback

`forward N` walks the first-parent chain of the branch containing HEAD, and
refuses when N exceeds what that branch holds. When no branch contains HEAD at
all — detached on an orphan commit — it falls back to `HEAD@{N}`, which counts
*reflog entries*, not commits.

That fallback is a different question answered with the same number. It is the
only remaining place where a value can be plausible and wrong. Options: remove
it (fail honestly instead), or name the difference in the output when it is
used. Removing is cleaner.

## Not doing — with reasons

### git-extras: 5 of 82 carried over, deliberately

`git-extras` offers 82 commands. Most fail one of the two tests in `CLAUDE.md`
— *is the manual version a procedure?* and *does the word collide with git's
own vocabulary?*

**Carried:** `prune-branches` (merges three of theirs into one, reason above),
`abort` and `continue` (the pair below — git's own `--abort` and `--continue`,
with the builtin hazard handled by making the second a case arm).

**Rejected — one git command each, so a new word teaches a dialect:**
`cp`, `mv`, `root`, `count`, `rename-branch`, `rename-tag`, `rename-file`,
`create-branch`, `delete-branch`, `delete-tag`, `reset-file`, `touch`.

Each is a near-miss: `git mv` exists and means the same thing, so a user who
learns `mv` here learns something that does not transfer. A word git does not
have fails loudly and tells you you are somewhere else. That is the safer
failure.

**Rejected — already better here:** `squash`, `undo`, `info`/`summary`
(`state`), `browse` (`openweb`), `repl` (the program).

**Rejected — reports, not procedures:** `changelog`, `authors`, `contrib`,
`effort`, `standup`, `guilt`. These generate prose from history. Large
implementations, no git verb replaced.

**Rejected — multi-repo or network orchestration:** `bulk`, `get`, `scp`,
`rscp`, `fork`, `force-clone`. Different tool.

**Rejected — dangerous history surgery already covered:** `obliterate`,
`reauthor`, `psykorebase`, `merge-repo`, `graft`. `decimate` covers the useful
case and previews before acting.

**Rejected — tooling for the tooling:** `alias`, `extras`, `setup`.

### Stateful screens

No fullscreen staging view, no hunk selector, no modes. The guard is
**selector-in, selector-out**: a command prints a value or acts, then returns
to the prompt. `Ctrl+G` hands you lazygit for anyone who wants that.

The consequence to keep in mind: no `stage`, because it is one `git add` and
`git stage` is itself an alias for `add` — a near-miss is worse than an unknown
word.

**`unstage` is the single exception**, and it is grandfathered once rather than
being a precedent. It fails the "is it a procedure?" test — it is one
`git restore --staged` — and is allowed anyway, because `stage` at least owns
its keep while `unstage` has no git word at all, users arrive already knowing
it from lazygit and the GUIs, newcomers never learn it from git at all, and
refusing it teaches nothing. The asymmetry is deliberate: `stage` works in git,
`unstage` does not exist. Full reasoning in `CLAUDE.md` under "The one
exception: `unstage`".

### `abort` and `continue` — landed

The pair exists, and it is the pair git already has:

```
abort       Stop whatever operation is in progress, whichever it is
continue    Carry it on, after you have resolved things
```

`git rebase --abort` and `git rebase --continue`. So do `cherry-pick`,
`revert` and `am`. A user who has just read a git error mentioning
`--continue` already knows this word, and learning one of the pair teaches
the other.

#### The name is git's, and the rename that came before it was wrong

It was called `resume` first, for a day, and that was a mistake worth
recording. The reasoning was that `continue` is a **loop statement** and she
has no loops, so the name promised loop semantics she cannot honour, while
`resume` named the operation instead.

That reasoning fails on the test about git's vocabulary. Git uses `continue`
as a **procedure**, not a loop statement: `git rebase --continue` does not
mean "skip to the next iteration", it means "carry on the half-finished
rebase". So `continue` is git's own word for exactly this operation, and
`resume` matched nothing in git at all. The rename swapped one dialect word
for another, and broke the pair with `abort`, which is `git rebase --abort`.

#### The builtin collision was real, and it was not about the word

A bash **function** named `continue` **shadows the builtin of the same name**.
Every loop in `igitari.sh` that used `continue` to skip an iteration called
the command instead — 20 call sites printing "Nothing in progress to
continue." in the middle of unrelated work. The suite went 191 passed / 0
failed → 173 / 22, and the damage was not confined to its own tests: it broke
`guards.sh`, `history_rewrite.sh`, `input_scan.sh`, `tokenizer.sh`,
`working_tree.sh` and one case in `prune_branches.sh`.

That is a fact about the **function namespace**, not about the word. So the
verb is a **case arm** in `execute_command` — `abort()` is an ordinary
function in `EXPOSED_FUNCS`, and `continue` is listed in
`IGITARI_CASE_VERBS` — and the implementation lives in
`__continue_operation`, a name the builtin cannot collide with. Nothing
shadows anything: not this script, not the test harness, and not the user's
own RC file, which is sourced into this shell.

`tests/cases/abort_continue.sh` covers the pair, and one of its cases runs a
loop with `continue` in it, in the shell Igitari was sourced into, and asserts
that the builtin still skips the iteration. That is the proof the collision is
gone rather than hidden.

#### Why the pair qualifies at all

The manual version is a *procedure* — you must first work out which of merge /
rebase / cherry-pick / revert / am is running, then type that one's word. That
detection exists as `__git_operation` and `__git_operation_desc`.

Rules for them:
- `abort` must never destroy uncommitted work without saying so. `merge
  --abort` throws away conflict resolutions; `rebase --abort` does too.
- `continue` must not guess. If the tree still has unmerged paths, say so
  rather than letting git fail with its own message.
- Both refuse when nothing is in progress, naming what they looked for.
- Neither introduces a new vocabulary: they wrap words git already has.

### `unstage` — landed

The exception above is decided and the command exists: `unstage` is in
`EXPOSED_FUNCS`, `HELP_TEXT[unstage]` has a page, and
`tests/cases/working_tree.sh` covers it.

It is the inverse of `git add`, **with git add's own grammar** — the same
pathspecs and the same flags. A command that renames a git operation but
keeps a different argument shape is a dialect, and a dialect is exactly what
the rule above exists to prevent, so the shape had to match too:

| | `git add` | `unstage` |
|---|---|---|
| a path | stages it | unstages it |
| a directory | stages the subtree | unstages the subtree |
| no pathspec | "Nothing specified, nothing added." | "Nothing specified, nothing unstaged." |
| `-A` | the whole tree | the whole tree |
| `-u` | tracked files only | tracked files only |
| `-n` | says what it would do | says what it would do |
| `-p` | picks hunks interactively | picks hunks interactively (`git reset -p`) |
| `--force` | adds ignored files anyway | refused: nothing is ignored in the index, and the working tree is never touched |

The mapping underneath is git's own: staging puts things into the index, and
the inverse of that is resetting the index back to HEAD.

What it does *not* do:

- **The working tree is never touched**, so nothing is discarded and nothing
  asks first. A path staged for the first time goes back to being untracked;
  a tracked path goes back to its committed state with the edits left in the
  working tree.
- **No flag is passed through to git.** `git reset` has options of its own,
  `--hard` among them, and handing this command's arguments to it unchecked
  would be a way to lose work. Unknown flags are refused.
- **A no-op is not a failure.** Nothing staged → "Nothing to unstage." A path
  with nothing staged → "Nothing to unstage for '<path>'." Both return 0. A
  path git does not know at all is an error, and git's own message says so.
- **A repo with no commits still works.** `git restore --staged` needs a HEAD
  to restore from, so with no HEAD it uses `git rm --cached` instead — the
  same result, and the file stays on disk. The fallback is used *only* while
  there is no HEAD: with one, it would untrack a file rather than unstaging
  it, which is a different operation.
- **Completion offers what is staged**, not every file on disk — the only
  paths that can be unstaged are the ones in the index.

The old rough edges (a stub that returned 0 on failure, a "Unstaging all
staged files." printed before discovering there was nothing to unstage, and
`rc=1` for an empty index) are gone.

### Bare magic variables

`$_prior` and friends are a category mismatch: Igitari has a command layer, not
a variable layer. `guess prior` is the right shape and is built.

### Injecting Igitari's config into git's config database

`gitsh.gitCommand`-style colonisation of git's namespace. `~/.igitari-rc` is
the config home, and `config session` covers the transient case without writing
anything anywhere.

## Known rough edges

Not planned work, just things known to be imperfect. Each has a test or a
comment naming it.

- **`fzf` layer** is the largest and least-tested area: ~90 references, and
  the only tests are for its *completion* (which return types each selector
  takes), not for what the selectors do. Everything else in it is interactive
  and needs a terminal. It is the likeliest source of surprises.
- **`fzf`** is the only exposed command whose behaviour has no test. Its
  argument completion is covered; the selection itself is not.
- **`openweb`** is tested at the URL level (ssh→https, `.git` trimming, ports,
  nested paths, `pages`); the browser launch itself is not, and cannot be.
- **Updater**: `ref.sha` holds one SHA; the download is not pinned by content
  hash, only by the ref it was fetched from.
- **Updater**: the changelog is fetched from GitHub's compare endpoint, which
  answers a range with **the last 250 commits** unless a page is asked for.
  The updater asks for pages explicitly now, and holds a window anchored at
  the head: the release marker lives at the new end by construction, so a
  window that ran out of budget still knows which version it is offering.
  Two limits remain, both deliberate: `_UPDATER_MAX_COMPARE_PAGES` (4) caps
  the requests at one per start, and `_UPDATER_CHANGELOG_LINES` (25) caps
  what is printed. Either way the notice says how much it left out — a
  changelog that is quietly short is worse than one that admits it.
- **`__git_state`** flags are `a` (am), `c` (conflicts), `o` (operation),
  `d` (diverged). All four are tested now; the flag string is not an enum, so
  consumers test for characters.

## The rules that decide all of the above

Kept here in full because they are the reason this roadmap says no as often as
it says yes.

### What earns a command

> Igitari adds verbs raw git lacks — commands you would otherwise **write a
> script for**. It never renames a verb raw git already has.

Two tests, both must pass:

1. **Is the manual version a command or a procedure?** `squash 3`,
   `reword <sha>`, `transplant`, `decimate`, `undo`, `conflict show` all
   replace a multi-step sequence. `stage` would wrap `git add` — one command,
   so it does not qualify. `unstage` fails this test too and is allowed anyway;
   see "The one exception" below.
2. **Does the word collide with git's own vocabulary?** `reword`,
   `transplant`, `decimate`, `undo` do not exist in git, so `git reword` fails
   loudly and you know you are somewhere else. A near-miss like `stage` does
   exist and would sort-of work while meaning something slightly different —
   that is how a dialect gets built.

### The forge exception

`forge` is judged differently because `git forge` fails loudly — nothing
learned there can be mistaken for git — while the operations it holds (a PR, an
issue, a release) live on the remote and have no argument slot in any git verb.

The narrower rule that keeps it from becoming a second program: **only the noun
is translated.** `pr:32` becomes `gh`'s or `glab`'s word for that object; every
other argument goes to the provider untouched. Never invent or translate a
provider flag — a wrong flag should fail with the client's own error, so its
manual stays correct.

Blending comes first. If an existing command's grammar already holds the
operation, extend it (`openweb origin issues 553`, `fzf prs`, `guess pr`)
rather than adding a verb. Nothing may touch the network on the prompt or
`state`, and any absent client must leave existing behaviour untouched.

### Personality

Sassy robot foxgirl who means her professionalism. Cheeky for typos and
chatter; flat and serious for data loss and history rewrite. Never describe the
characterisation in output — just be it.

### Monolithic is the product

No build step, no `SRC/` split. The `#--|SECTION [TIER]` markers are navigation
for readers; nothing consumes them. She is portable precisely because she is one
script you can drop anywhere.
