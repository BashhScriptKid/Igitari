# Igitari — Ideas & Backlog

Design notes stashed for later. Nothing here is committed to a plan.

## PRIORITY — fix the fzf layer

The fzf integration is the closest thing Igitari has to a differentiator, and
it is only half-wired. Two halves:

1. **Composability is blocked.** `$(...)` command substitution only expands
   through the raw-git path (`eval` at `igitari.sh:2166`). Exposed helpers
   invoke `$fn ${args[@]}` without `eval` (`igitari.sh:2157`), so
   `reword $(fzf commits sha)` passes the literal string `$(fzf` as an argument.
   This same bug blocks `guess` (below).
   - Do **not** `eval` a resolved command — refs/paths are user-controlled.
   - Dispatch through a whitelist table (subcommand -> function + positional args).
   - Suppress history for internally-generated invocations (`history -s` at
     `igitari.sh:2159`, `2172`).

2. **The picker isn't bound where it matters.** `_fzf_specialcompletion`
   (`igitari.sh:456`) already overlays the prompt, previews, and returns a
   value — the "popup" idea, already built. It's only bound to six raw git
   subcommands (`igitari.sh:588-593`). Bind it to `reword` / `transplant` /
   `discard`, and add an ambient keybind. (Note: Ctrl+M is Enter, Ctrl+I is
   Tab, Ctrl+J is LF — pick another key.)

## Completion — delegate to git-completion, don't reinvent

**Why it never worked:** `git-completion.bash` registers itself with
`complete ... git`, keyed on the literal command word `git`. Igitari drops that
word, so the first token (`status`, `add`, …) has no completion spec and
readline falls back to filename completion — the loaded engine can never fire.
`try_source_completion` also hides failures (`2>/dev/null`, `igitari.sh:327`).

**Option A — delegate (high ROI, gets gitsh-level breadth free):** in
`complete_git_env`, for raw-git commands, invoke git-completion with a synthetic
leading `git`:
```sh
COMP_WORDS=(git "${words[@]}")
COMP_CWORD=$((cword + 1))          # +1 for injected "git"
COMP_LINE="git $line"; COMP_POINT=$((point + 4))
__git_main                          # routes COMP_WORDS[1] -> _git_<cmd>
# read COMPREPLY -> existing display / fzf layer
```
`__git_main` handles aliases and enumerates third-party commands, so this pulls
in breadth; keep the hand-written handlers for Igitari's own commands and the
fzf-ref path.

**Option B — full DSL (only if a user-facing completion DSL is the product):**
gitsh's engine is an NFA over tokens loaded from rules. Engine ~20% of effort,
rule corpus for every git subcommand/option ~80% — and ongoing maintenance
against git. Skip unless the DSL itself is the feature.

## HIGH PRIORITY — updater download isn't pinned to the release SHA

`_updater_replace` is handed `target_sha` (the resolved "Version bump to"
commit) but downloads branch HEAD:

```sh
# igitari.sh:2658
local script_url="${_UPDATER_RAW_URL}/igitari.sh"   # -> .../mono-master/igitari.sh
```

`target_sha` is used only to write `ref.sha` (igitari.sh:2694), so the bytes
on disk and the recorded SHA diverge.

The comment at `igitari.sh:2656-2657` claims raw.githubusercontent doesn't
support commit-specific URLs — **false**; verified commit SHA and short SHA
both return HTTP 200.

Fix (one line):
```sh
local script_url="https://raw.githubusercontent.com/BashhScriptKid/Igitari/${target_sha}/igitari.sh"
```
or make `_UPDATER_RAW_URL` ref-less and compose `.../Igitari/${ref}/igitari.sh`.
Then the downloaded script matches `ref.sha` and the release is truly pinned.

## `guess <context>` — explicit magic variables

Explicit beats gitsh's auto-injected `$_vars` here, since Igitari has a command
layer, not a variable layer. Selector-shaped: prints a value and exits.
Depends on the composability fix above to feed any helper.

| `guess ...`       | returns                    | plumbing                                    |
|-------------------|----------------------------|---------------------------------------------|
| `guess prior`     | previous branch            | `git rev-parse --abbrev-ref '@{-1}'`        |
| `guess merge-base`| merge base hash            | `git merge-base HEAD MERGE_HEAD`            |
| `guess rebase-base`| commit being rebased onto | `.git/rebase-merge/onto` / `rebase-apply/onto` |
| `guess root`      | repo root                  | `git rev-parse --show-toplevel`             |

Rules:
- Value -> stdout; failure -> stderr + nonzero. Never print an empty line
  (mirrors gitsh magic vars "acting unset").
- Read plumbing, not human output.
- No `eval` on the result.

Open question: `guess` as a ref resolver, vs. a stray-`git`-prefix / typo
corrector (`git status` -> `status`, `stat` -> suggest `status`).
gitsh handles the latter via `help.autocorrect`. (Author typed `git status`
147x inside Igitari per history.)

## Input handling — comments, line continuation, grouping

Current engine: `process_command_line` splits on `&&`/`||`/`;` via sed with
`should_execute` arithmetic (`igitari.sh:2185-2214`); `main_loop` reads a single
line with `read -rep` (`igitari.sh:2791`).

- **`#comments`** — strip from the input before dispatch, but not inside quotes
  (a naive `sed 's/#.*//'` mangles `commit -m "a #b"`).
- **Multi-line continuation** — a trailing `\` continues the prompt instead of
  dispatching; loop the `read` in `main_loop` and accumulate until the line has
  no unquoted trailing `\`.
- **Parentheses grouping** — `(a || b) && c`. The big one: sed + arithmetic
  can't express grouping, so this needs a real tokenizer with precedence, not
  string splitting. Keep the no-eval discipline. Decide the semantics first —
  Igitari's current left-to-right matches `sh`; gitsh's `&&`-binds-tighter-than-
  `||` is a deviation from POSIX.

## `help` extra semantics

Current `help` (`igitari.sh:2015-2034`) runs `git help` then dumps a flat
heredoc list of Igitari commands. No per-command detail, so the helpers stay
undiscoverable.

Proposed:
- `help` -> Igitari overview (commands + one-liners), then `git help`.
- `help <igitari-cmd>` -> usage, description, examples for that helper
  (e.g. `help transplant`).
- `help <git-subcommand>` -> delegate to `git help <cmd>`.
- `help -a` / `help --all` -> flat list of everything.
- Unknown command -> fall back to `git help` semantics, not a hard error.

Implementation:
- A per-command help registry (assoc array `HELP_TEXT[cmd]`, or each exposed
  function handling `--help`).
- A `register_help` seam so RC-defined commands can document themselves (ties
  into the mutability section).

## Session-scoped config — `git config session ...`

Intent: user explicitly types a scope token, e.g.
`git config session user.email me@example.com` (or `--session`), and it applies
only for the current Igitari session, forgotten on exit. This is gitsh's `:set`
behaviour, but surfaced through `git config` instead of a `:` builtin.

Semantics:
- `git config session <key> [value]` sets an override for the session.
- Support session-scoped `--get` / `--list` / `--unset` / `--clear` too.
- Precedence: session wins over local/global/system for the session, matching
  `git -c` (highest precedence).
- No disk writes, by construction.

Implementation (no `eval`):
- Intercept in the dispatch layer before the raw-git fallthrough
  (`execute_command`, `igitari.sh:2133-2167`): match `config` + `session` and
  handle it in-shell.
- Store in an associative array `SESSION_CONFIG[key]=value`.
- When dispatching any git command, prepend `-c key=value` for each entry
  (array-built), or export `GIT_CONFIG_COUNT` / `GIT_CONFIG_KEY_n` /
  `GIT_CONFIG_VALUE_n`.
- Must intercept before raw git, otherwise `git config session ...` just errors
  on an unknown scope.

## Distribution — bootstrap + rolling updater

The model is deliberate: no release tags. Version points are "Version bump to
X" commits, resolved via the GitHub compare API, and the updater auto-updates
in the background. So this is not "add tags/checksums" — those don't fit.

Done:
- [x] README install URLs pointed at `master`, where `igitari.sh` doesn't
  exist. Now `mono-master` (README.md:71, :84). Repo default branch also
  switched to `mono-master`.

To do:
- [ ] **Revive the updater** (currently disabled/unmaintained). For an
  auto-update model this *is* the distribution channel, not a nice-to-have —
  "easy in, no update out" is the worst state.
- [ ] Pin the updater download to the resolved release SHA — see the HIGH
  PRIORITY section above.
- [ ] Add `curl --fail` to the README bootstrap. Without `-f`, a 404 body gets
  written and `chmod +x`'d into a "working" binary.
- [ ] Stop hardcoding versions in docs. Releases live in commit messages, not
  tags, so the README badge / CLAUDE.md / `IGITARI_VERSION` drift (3.10.10 vs
  3.11.1 vs 4.0.0). Derive or drop the static number; `RUNTIME_VERSION` already
  appends the commit.

Not doing:
- Checksums/signatures — the updater authenticates via SHA-in-remote-history
  (`_updater_resolve_status`) plus `curl -fL` over HTTPS; a checksum adds little.
- Package managers (brew/AUR) — low ROI, conflicts with the rolling
  single-hackable-file model, and only buys discovery.


## Scope guard: selector-in, selector-out

- **Not doing:** a stateful fullscreen staging/hunk manager. That is lazygit's
  core panel and Igitari already delegates to lazygit via Ctrl+G.
- **Allowed shape:** a stage ends by *returning a value*, not by becoming a
  mode. Two-stage tree selector -> return file -> delegate to `git add -p`, or
  hunk list -> multi-select -> emit a patch. Never a screen that holds state.
- Test: "does it end by returning a value, or by becoming a mode?"

## Testability — `--test` gate

Tests aren't moot: operator splitting (`process_command_line`),
`differentiate_patchdiff`, the awk in `_updater_handle_behind`, and
`validate_arg` are pure, silent-failing logic. But the script can't be loaded
in isolation — it refuses to be sourced (`igitari.sh:~113-120`) and calls
`main "$@"` unconditionally (`igitari.sh:2874`).

Add a `--test` flag (or `IGITARI_TEST=1`) that:
- bypasses the source guard, and
- skips `main "$@"`,

so a test script can `source igitari.sh` and exercise functions directly.
Prerequisite for any unit tests; interaction/e2e tests stay out of scope.

## LOWEST PRIORITY — mutability / extension points

Goal: let user config extend Igitari as far as it can. Trust is a non-issue —
an RC you author and `source` is the same as `.bashrc`.

Blockers today:
- `_GIT_CMDS` / `_IGITARI_CMDS` are `readonly` (`igitari.sh:435, 447`).
- `EXPOSED_FUNCS` is a `local` array inside `execute_command`
  (`igitari.sh:1985`) — an RC can only shadow already-exposed functions.
- `setup_rc_file` sources exactly one file (`igitari.sh:2260`), before
  `process_arguments` (`igitari.sh:2816`), so it can't react to CLI flags.

Ideas:
- Source `~/.config/igitari/rc.d/*.sh` in lexical order (bash `profile.d`
  pattern), isolated so one bad file doesn't kill startup.
- `register_command` / `register_completion` helpers pushing into overridable
  tables (same "plugin-style registration" CLAUDE.md describes for
  `register_error_handler()`).
- A runtime `source <file>` command (gitsh has `:source`) for mid-session
  reload; `_reload` already exists.
- Add `--git PATH` to `process_arguments`; `GIT_PATH`/`git_path` is already
  threaded through dispatch (`igitari.sh:1987, 2179, 2205`), so this gives
  gitsh-style wrapper passthrough (hub, etc.) for free.

## Forge objects as nouns — optional gh/glab support (planned)

The first Igitari feature that talks to a network, and the first that depends on
something other than git. It must therefore be *additive*, never load-bearing:
with no forge CLI installed, Igitari must behave exactly as it does today.

### Why this is not the rejected "platform APIs" feature

The README puts GitHub/GitLab APIs out of scope **as first-class commands**. The
distinction is *does absence cripple you*, not *does it mention a forge*:

- **First-class (rejected):** `pr`, `issue` in `_IGITARI_CMDS`, in completion,
  in `help`, in the prompt. A GitLab user or a machine without `gh` runs a
  crippled Igitari.
- **Optional granted subset (this):** every existing path untouched; the
  feature is a door that is either open or simply absent. `__check_fzf`
  (`igitari.sh:3389`) is the precedent — gate, warn, return 1, rest of Igitari
  carries on. `__check_forge` is the same shape one section down.

Consequence to write into the README: the sentence should read "out of scope
*as first-class commands*; an optional gated extension that changes no existing
behaviour is allowed — `fzf` sets the precedent."

### Architecture — the forge is a vocabulary, not a second program

An earlier draft of this plan gave the forge its own command (`forge prs`,
`forge checkout`) and kept every existing verb untouched. That is wrong in
kind, not in detail: it makes the forge a second companion binary living inside
Igitari, a thing bolted on and consulted rather than a thing Igitari
understands. The forge is where a repo's *collaboration state* lives, so
Igitari should speak it the way she speaks branches — as nouns.

**The move: extend the noun, not the verb.**

Igitari's verbs already take nouns: refs, paths, stashes, shas. Add forge
objects to that vocabulary and the verbs need no flags at all, because they
already know how to act on a noun they can resolve.

```
pr:123          a pull request      (GitHub)
mr:123          a merge request     (GitLab; same object, their word)
issue:123       an issue
```

`#123` is **unavailable** — Igitari strips `#` comments (`igitari.sh:4319`),
verified. `pr:`/`mr:` collide with nothing: no git ref syntax, no Igitari
syntax, and already greppable as absent from the file. The qualified form is
self-describing, which a bare `123` can never be.

**The split: blend where the grammar already fits, `forge` only where it cannot.**

Two mechanisms, and the order matters — blending is tried first:

1. **Blend** the object into the argument slot the command already has. A page
   word for `openweb`, a source word for `fzf`, a question for `guess`. No new
   syntax at all; the verb's own grammar simply gained a word.
2. **`forge`** only where the operation reaches the remote in a way git cannot
   express, so no existing verb's slot can hold it without being reinterpreted.
   Today that is exactly one operation: taking a PR/MR into the working tree.

| need | spelling | why here |
|---|---|---|
| open a discussion | `openweb upstream discussion 9553` | `openweb` already takes `[remote] [page] [sub]` |
| find a PR | `fzf prs` | `fzf` already takes a source word |
| which PR is this branch? | `guess pr` | `guess` already dispatches on a question |
| take a PR into the tree | `forge checkout pr:32` | no git verb does this; it fetches a fork and invents tracking |

`forge checkout` is not a wrapper around `checkout`: it is the one place where
"client-side reference" and "git reference" genuinely diverge, and where the
remote has to be consulted to produce a local ref that did not exist before.
Naming that for what it is (`forge`, not a flag on `checkout`) is why `checkout`
keeps its meaning untouched — a bare `1234` is still git's path-or-ref.

**The colon noun is the dialect of `forge`, not of Igitari.** `pr:32` exists
because `forge checkout` must be told *which kind* of remote object it is being
handed; `mr:32` and `release:v2.0` answer the same question. Outside `forge`,
nothing needs it: `openweb` says `discussion 9553`, because that is the slot it
already has. `guess pr` and `fzf prs` print a colon noun exactly when the thing
they produce is destined for `forge`; `fzf prs number` prints the bare number
for the blended spelling.

Consequences, all of them simplifications:

- **No pre-dispatch resolver and no rewrite of the command line.** The riskiest
  part of the earlier draft — a hook on the most reflex-typed command — is
  deleted outright. `forge` is an ordinary exposed command, dispatched like
  `squash` or `conflict`.
- **`checkout`, `show`, `diff`, `log` gain nothing** and stay pure git.
- **No `pr:` token appears in any git-bound argument**, so nothing can be
  silently misinterpreted by `eval` in the fallthrough path.

**Tier placement — this is the part that answers "afterthought".** The
provider adapters (`__forge_list_prs`, `__forge_resolve`, `__forge_url`) go in
**`[GITLIB]`**, beside `GIT_HELPERS` and `GIT_FUNC`. That tier is defined as
"Git-aware helpers not tied to Igitari's UI; useful to any Git-related Bash
tool" — a forge adapter is exactly that citizen. The `[IGITARI]` layer only
wires nouns into verbs. The forge is therefore a *library capability*, not an
app living in the app.

**No ambient network.** Nothing contacts a server unless you type a forge word
or ask `guess`/`fzf` for one. The prompt and `state` stay byte-identical and
offline, so the invariant survives integration rather than being the reason
integration was skipped.

### Objects: when a name is needed at all

"PRs only" is too narrow, and "everything" is not a plan. The test is not "is
it a forge object" but **does anything need to refer to it by name**. Two
answers:

**Blended — needs no noun at all.** The object fits a slot a command already
has, so it is named by position, using the bare number:

| need | spelling | existing slot |
|---|---|---|
| open a discussion | `openweb upstream discussion 9553` | `[remote] [page] [sub]` |
| open issue 553 | `openweb upstream issues 553` | same |
| find a PR | `fzf prs` | source table |
| which PR is this branch? | `guess pr` | dispatch word |

The page word *is* the prefix — `openweb upstream discussion 9553` needs no
`discussion:` token, and the bare number cannot be misread because the word in
front of it already said what it refers to.

**Named — a colon noun, because `forge` must be told the kind.** A `forge`
object verb receives one token where git would expect a ref, so that token has
to carry its own type:

| noun | resolves to | via |
|---|---|---|
| `pr:32` | local branch, else head sha | `gh pr checkout` / `--json headRefOid` |
| `mr:32` | same object, GitLab's word | `glab mr checkout` (flags unverified) |
| `issue:88212` | the issue itself | `gh issue close|comment|edit ...` |
| `discussion:553` | the discussion itself | `gh discussion` (preview) |
| `release:v2.0` | its tag | `gh release list` has **no** `url` field (verified); `tagName` is |

`issue:` and `discussion:` earn a noun because `forge close issue:88212` needs
the same self-description `pr:32` does — the verb says *what* to do, the noun
says *what to do it to*. They are not needed for viewing, which blends into
`openweb`, and that is the point: a noun exists where a namespace needs a kind,
not everywhere an object exists.

The colon is a **dialect of `forge`, not of Igitari**. Nothing git-bound ever
sees one, which is what keeps the fallthrough path safe. `fzf prs` therefore
has two return types, matching its existing convention: `fzf prs number` prints
`32` for the blended spelling, `fzf prs ref` prints `pr:32` for `forge`.

A release is a tag plus notes and assets. The noun earns its place only because
it disambiguates "the release" from "the tag"; if that distinction ever feels
thin, drop it and let tags do the work.

**Non-nouns — do not invent syntax.** Labels, milestones, projects,
notifications, action runs, users. These are metadata or lists with no single
object worth naming; `>gh <cmd>` already reaches them. A `label:` syntax would
be a DSL built for no gain.

**Wikis stay a page.** A forge wiki is a git repo (`repo.wiki.git`) or a page
tree, not an API object — `gh` has no `wiki` command (verified). `openweb
origin wiki` already opens it and already handles GitLab's `wikis` spelling
(`igitari.sh:3788`). No noun needed, and inventing one would duplicate the
path.

**The "one command, not a procedure" test is scoped to git, not to the forge.**
That matters, and CLAUDE.md's rule should say so explicitly.

The rule exists to stop a **git** dialect forming: `stage` works through
`git stage` while meaning something slightly different, so the user learns a
word that betrays them in a plain shell, and the mistyping can break an index
or a working tree. That hazard needs a namespace collision — the near-miss.
`forge` cannot produce it: `git forge ...` fails loudly (verified), so nothing
under this namespace can ever be mistaken for git, and no git habit is broken
by learning it.

The rule guards against **deceiving people about git**; it is not a prohibition
on exposing another tool's own verbs. So `forge close issue:88212 --unplanned`
is legitimate — with one guardrail:

**Only the noun is translated; every other argument passes to the provider
verbatim.**

- `forge close issue:88212 --reason "not planned"` -> `gh issue close 88212
  --reason "not planned"`. No flag is invented, so no dialect forms, and the
  provider's own docs stay valid for the user.
- A wrong flag fails with the *provider's* error. `--unplanned` is not a `gh`
  flag (its spelling is `--reason "not planned"`), so on GitHub it returns gh's
  own message about `--reason`, which teaches the real tool instead of quietly
  absorbing a mistake.
- Verbs map 1:1 onto documented provider commands (verified against `gh pr` /
  `gh issue`): `close`, `comment`, `merge`, `review`, `ready`, `reopen`,
  `edit`, `lock`, `diff`, `checks`, `revert`, `create`, `delete`.

The noun translation is where the care goes, and it is the only thing the
provider adapter is allowed to interpret.

**Worth amending in CLAUDE.md**, so the next reader does not re-derive this:
the "command or procedure" test applies to commands *addressed at git*. A
namespaced delegation to a different program is judged instead by (a) does the
namespace collide with git's vocabulary, and (b) is every argument but the noun
the provider's own.

### Subsets: what each verb actually gains

| command | gains | because |
|---|---|---|
| `openweb` | page words `issues`, `discussions`, `releases`, plus an optional number in the existing `sub` slot | Blends into `[remote] [page] [sub]`; no new syntax, no new argument position. |
| `fzf` | `prs`, `issues`, `discussions` sources; `number` vs `ref` return types | The source table already exists. `number` feeds `openweb`, `ref` feeds `forge`. |
| `guess` | `guess pr` -> `pr:32` | One more arm in an existing dispatch; prints one value and stops. |
| `forge` | object verbs: `checkout`, `close`, `comment`, `merge`, `review`, `ready`, `reopen`, `edit`, `lock`, `diff`, `checks`, `revert`, `create`, `delete` | Not a subset — a namespace. See below. |
| `checkout`, `show`, `diff`, `log` | **nothing** | Stay pure git. No colon noun can reach them, so nothing is reinterpreted. |
| `state`, prompt, `squash`, `reword`, `discard`, `transplant`, `decimate`, `untrack`, `retrack`, `conflict`, `movehead`, `undo`, `redo` | **nothing** | Local history/index/working-tree verbs, and ambient network in `state`/prompt would break their offline contract. |
| `config` | `forge.provider` | Rides the existing `config session` scope. |

### `forge` — a namespaced delegation, not a git command

`checkout` is not in `EXPOSED_FUNCS` (verified) — pure fallthrough to git, with
only a completion handler. Hanging the PR case off it would mean reinterpreting
git's own ref grammar on the most reflex-typed command, and would require a
pre-dispatch rewrite of the command line. Both are avoidable:

- `forge` is an **ordinary exposed command**, dispatched exactly like `squash`
  or `conflict`. No hook, no rewriting engine, no new interception point in the
  hot path.
- The colon noun is `forge`'s own dialect, so `forge` may grow verbs freely in
  a space where git habits cannot be corrupted. It is a namespace, and that is
  the honest description of it.
- Blending still wins wherever an existing grammar can hold the operation:
  viewing is `openweb ... discussion 553`, not `forge open discussion:553`.

**What `forge` is for, stated accurately:** operations whose subject lives on
the remote and whose effect git cannot produce locally — a ref that did not
exist here, a state change only the forge knows about. Reading and discovery
blend; mutation and remote-side refs go through `forge`.

```
forge checkout pr:32                     take a PR into the working tree
forge checkout mr:32                     same, GitLab's word
forge close    issue:88212 --reason "not planned"
forge merge    pr:32 --squash --delete-branch
forge review   pr:32 --approve
forge diff     pr:32                     remote-only: no local equivalent
forge checks   pr:32                     CI status, remote-only
```

**Grammar:** `forge <verb> [<object>] [provider flags...]`. The verb whitelist
above is for completion and for the help page; execution passes the verb
through, so an unlisted-but-real provider verb still works, and a typo returns
the provider's own usage text.

**Noun/verb pairing is checked, not guessed.** `close` accepts `issue:` and
`pr:`; `merge`/`review`/`ready`/`checks` accept only `pr:`/`mr:`; `checkout`
accepts `pr:`, `mr:` and `release:`. A mismatch is refused before any network
call, so `forge merge issue:812` never becomes `gh pr merge 812`.

**Destructive verbs confirm.** `merge`, `close`, `revert`, `delete` ask first,
the way `squash` and `conflict throw` do — a namespaced command is not a licence
to act without asking.

### Provider abstraction

One adapter per CLI, ~20 lines each, isolated so a wrong flag is a one-line fix:

| provider | list PRs | checkout | list issues |
|---|---|---|---|
| `gh` (GitHub) | `gh pr list --json number,headRefName,title --template ...` | `gh pr checkout <n>` | `gh issue list --json number,title --template ...` |
| `glab` (GitLab) | **unverified** | **unverified** | **unverified** |

**Verified against the live binary (gh 2.102.0):** `--template` emits TSV with no
`jq` dependency — this matters, Igitari avoids dependencies. `gh pr checkout`
takes a bare number across forks. With no GitHub remote, `gh` exits **1 with
empty stdout**, so the negative case is cleanly detectable.

**Not verified:** `glab` is not installed here and the docs search provider is
down. Its flags must be checked against a real install *before* implementing
that adapter. Fallback if `glab` lacks machine output: parse `glab mr list`
text (brittle) or drop to phase 3.

Provider detection reuses the host sniffing already in `openweb`
(`igitari.sh:3787`): `git remote get-url` of the upstream, else `origin`;
`github.*` -> gh, `gitlab.*` -> glab. Override by `FORGE_PROVIDER` in the RC or
`config session forge.provider` — the session-config feature already exists, so
no new override machinery is needed.

### Word-splitting hazard (recorded because it bites)

`__split_argv` (`igitari.sh:4258`) splits an *unquoted* `$(...)` on whitespace.
`guess pr` and `fzf prs` must therefore emit a single token — `32` or `pr:32`,
never a title or message. Both forms are one word by construction, which is
part of why numbers and colon nouns are the right return types. (The existing
`fzf commits message` examples return multi-word text and have the same latent
flaw — worth fixing separately.)

### Touchpoints

`forge` is a real command with a verb table, so it takes the usual registration
slots — and `checkout` needs none, which is the point.

| what | where |
|---|---|
| `FORGE_ADAPTER` section (providers, resolve, url) | new, inside `[GITLIB]` before `igitari.sh:2760` |
| `forge()` + `forge checkout` | `[IGITARI]`, beside `openweb`, `igitari.sh:3753` |
| `HELP_TEXT[forge]` | `igitari.sh:255` block |
| `_IGITARI_CMDS` gains `forge` | `igitari.sh:1280` |
| `_COMPLETE_HANDLERS[forge]=_complete_forge` | `igitari.sh:1433` |
| `_complete_forge()` (verb, then `pr:`/`mr:`/`release:`) | beside `_complete_fzf`, `igitari.sh:1375` |
| `EXPOSED_FUNCS` gains `forge` | `igitari.sh:4491` |
| `guess` gets a `pr` arm | `case` in `guess()`, `igitari.sh:~790` |
| `_complete_guess()` gains `pr` | completion block |
| `fzf` gets `prs` / `issues` / `discussions` arms | source `case`, `igitari.sh:3672` |
| `_complete_fzf()` gains sources and `number`/`ref` | `igitari.sh:1375` |
| `openweb` gains page words + optional number | `igitari.sh:3753` |
| `_complete_openweb()` gains `discussions`/`releases` | `igitari.sh:1320` |
| `GH_PATH` / `GLAB_PATH` / `FORGE_PROVIDER` | `CONFIG_VARS`, `igitari.sh:66` |
| `help` free-text list mentions `forge` | `igitari.sh:~4447` |

`checkout`, the prompt and `state` are **not** in this table — that is the
offline guarantee and git's ref grammar both holding, not an omission.

### Phasing, lowest risk first

- **P0** — `FORGE_ADAPTER` in GITLIB: provider detection, `__forge_available`,
  `__forge_resolve`. No user-visible surface, so it cannot regress anything;
  proves the tier is silent when nothing is installed.
- **P1** — the blend points: `guess pr`, `fzf prs` / `issues` / `discussions`,
  and `openweb` growing `discussions` / `releases` plus the optional number in
  its existing `sub` slot. All three are extra arms in tables the commands
  already have, and everything here works with no `forge` in sight.
- **P2** — `forge` itself: the namespace mechanics plus `checkout`. Noun/verb
  validation, flag passthrough, confirmation on destructive verbs, and
  `checkout pr:<n>` / `mr:<n>` / `release:<tag>`. A new exposed command,
  dispatched like `squash`; no hook, no rewriting. `--yes` confirm like
  `squash`, since it creates a branch and moves HEAD.
- **P3** — the mutation verbs, which need nothing but the noun table P2 already
  validates: `close`, `comment`, `review`, `ready`, `reopen`, `merge`. Purely
  additive to the adapter, and the point where the namespace proves it is not
  a one-verb excuse.
- **P4** — `fzf prs ref` / `guess pr` returning `pr:<n>` rather than a bare
  number, once `forge` exists to consume it. Deliberately after P2/P3 so the
  colon dialect ships with its consumers.
- **P5** — docs: `HELP_TEXT[forge]`, the `guess`/`fzf`/`openweb` usage lines,
  README scope amendment, `tests/cases/forge.sh` (the harness needs no
  registration — `tests/run.sh` finds case files).

Tests worth having from P0: no CLI installed -> `forge` says so and returns 1,
and nothing else changes; no forge remote -> clean message, not an empty picker;
`GH_PATH` unset changes nothing else; `forge checkout pr:999` fails loudly,
never silently to something else.

### Related: this supersedes the `--git PATH` item below

LOWEST PRIORITY lists "Add `--git PATH` ... gives gitsh-style wrapper
passthrough (hub, etc.) for free." That is wrong, and the code says so:
`git_path` reaches **10** call sites while **157** call sites hardcode bare
`git`. A `--git` flag would re-point only the fallthrough
(`igitari.sh:4631`), leaving the prompt and all 15 helper verbs still calling
real git — a prompt that reports `mono-master` while `gh` answers every
command. gitsh gets away with `--git` *because gitsh is thin*; Igitari is
deliberately not. Recommendation: delete that item; non-git tools are reached
through the noun vocabulary and the `>cmd` passthrough.

### Not doing

- `forge` verbs inventing or translating **flags**. The noun is the only thing
  translated; everything else is the provider's own, so no dialect can form.
- A pre-dispatch command-line rewriter, or colon nouns reaching git-bound
  arguments. `checkout`, `show`, `diff` and `log` keep pure git grammar.
- A `wiki:` noun. A wiki is a git repo or a page tree, not an API object, and
  `openweb <remote> wiki` already covers both forge spellings.
- Nouns for labels, milestones, projects, notifications, action runs, users.
  No object identity worth a namespace; they are flags on verbs that already
  take them (`forge edit issue:812 --add-label bug`).
- `forge` verbs duplicating a blend point: `forge open issue:812` instead of
  `openweb origin issues 812`, or `forge list prs` instead of `fzf prs`. If an
  existing grammar holds it, the grammar wins.
- `pr` / `issue` / `mr` as *top-level* commands. Behind `forge` they are fine;
  loose at top level they would compete with git's vocabulary.
- `state` or the prompt showing forge status. Ambient network there breaks
  offline/instant/safe-in-a-pipe; names are opt-in by design.
- A per-forge command pair (`gh`/`glab` verbs). One adapter table, one
  vocabulary.
- Caching or background prefetch. Network-per-typed-noun is the contract; if
  that becomes annoying the answer is a shell alias, not a cache layer.
- JSON parsing in Bash. Use `--template` where offered; do not hand-roll a
  JSON parser to avoid a dependency on `jq` we do not have to take.

## Not doing (explicitly rejected)

- **Injecting Igitari config into the git config DB** (`gitsh.gitCommand`-style).
  Igitari's own RC is the config home; don't colonise git's namespace.
- **Bare magic variables** (`$_prior`). A command layer gets commands — `guess`
  is the right shape. Expecting `$_x` here is a category mismatch.
- **Stateful fullscreen staging/hunk manager.** See scope guard; Ctrl+G -> lazygit.
- **Full test suite / man page / packaging / CI.** Only the `--test` gate (above)
  and a `shellcheck` check are worth it.

