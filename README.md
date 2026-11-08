# Igitari
*A kindly powerful Git companion* (formerly known as 'Git-env')

<p align="center">
    <img src="https://img.shields.io/badge/Version-3.10.10-blue">
</p>

> [!IMPORTANT]
> The project currently only focuses and maintained on mono-master branch. (I see no reason to modularise it further yet.)
> 
> **Igitari is currently not actively developed, but will be maintained.** Look at [Feature Requests](#feature-requests).

## Feature Requests

Igitari is currently feature-complete for its core goals. If you have ideas for new features:

1. **Check existing issues** to avoid duplicates
2. **Open an issue** describing:
   - The problem you're trying to solve
   - Your current workflow that's painful
   - How the feature would help
3. **👍 React to existing requests** you'd find useful

Features are prioritized by:
- Real-world pain points (not theoretical nice-to-haves)
- Alignment with Igitari's philosophy of being more as a helper than a wrapper
- Complexity vs. benefit tradeoff

**Note:** Igitari stays lightweight and focused. Features that introduce heavy dependencies, platform-specific APIs (GitHub/GitLab), or significant hidden complexity are likely out of scope.

The one exception is deliberate and narrow: forge support is **optional and gated**. If `gh` or `glab` is installed, a few commands can reach the remote (`forge`, `fzf prs`, `guess pr`); if neither is installed, those say so once and every existing command behaves exactly as before. Nothing in the prompt or `state` touches the network — the platform is never load-bearing, so Igitari remains fully usable without a forge. `fzf` set the pattern.

Final decisions are made by the maintainer, and may take personal interest and available time into account.

Pull requests are welcomed too!

## Introduction
Igitari is a Git shell companion born from the simple desire to type 'git' less often. It's designed to make Git approachable without sacrificing its power — because you shouldn't have to fight your tools to do great work.

Written in Bash from scratch, Igitari tries to avoid as many dependencies as possible. It is lightweight, portable, and flexible, with a philosophy of being "kindly powerful": helping you explore Git's capabilities while watching your back.

This project is licensed under AGPL-3.0-or-later.

## Philosophy: Kindly Powerful
Igitari aims to:
- **Reduce friction** in daily Git workflows
- **Provide safety nets** for common pitfalls
- **Stay out of your way** when you know what you're doing
- **Remain lightweight and modular** in its internal design
- **Rely on as few required dependencies as possible**

## Features
- Interactive Git shell with intelligent tab completion
- Dynamic prompt:
  - Branch name
  - Repository status
  - Dirty state markers
- Shell command execution (prefix with `>`)
- Operator support (`&&`, `||`, `;`)
- LazyGit integration (Ctrl+G when available)
- Optional forge support when `gh` or `glab` is installed:
  - `forge checkout pr:32`, `forge merge pr:32` — remote-side operations
  - `fzf prs` / `fzf issues` — pick one, get its number or `pr:32`
  - `guess pr` — this branch's pull request
  - `openweb origin issues 553` — blended into the existing `openweb`
- Web repository opening (`openweb` command)
- ~~Self-updating system~~ (Currently unmaintained due to small user base)
- Cross-platform (Linux, macOS, Windows WSL)

> [!WARNING]
> Igitari is primarily tested on Linux.
> Behavior on other platforms may vary—please report issues if you encounter discrepancies.

## Installation

### Quick Install
```sh
curl -L https://github.com/BashhScriptKid/igitari/raw/mono-master/igitari.sh -o ~/.local/bin/igitari
chmod +x ~/.local/bin/igitari
```

### Development Install
```sh
git clone https://github.com/BashhScriptKid/igitari.git
cd igitari
ln -s igitari.sh ~/.local/bin/igitari
```

### Global Install
```sh
sudo curl -L https://github.com/BashhScriptKid/igitari/raw/mono-master/igitari.sh -o /usr/bin/igitari
sudo chmod +x /usr/bin/igitari
```

### Dependencies
**Required:**
- Git
- Bash 4+
- GNU Coreutils

**Optional:**
- Lazygit (for TUI integration)
- FZF (For FZF-based query for commits, stashes, etc)

## Usage
Start Igitari:
```sh
igitari
```

Get help:
```sh
igitari -h
```

Start in a specific directory:
```sh
igitari -p /path/to/repo
```

Enable verbose logging:
```sh
igitari --verbose
```

---

Upon entering, you'll see:
```
Entering Igitari (Hi!). Press Ctrl+D or type 'exit' to quit.
Prefix commands with '>' to execute shell commands
Press Ctrl+G to launch LazyGit

[.../awesome-repo/ (master*)]igitari>
```

The prompt shows:
- Repository path (compressed for readability)
- Current branch
- Status markers: `*` (unstaged), `^` (staged), `_` (stash exists)

### Basic Usage
Run Git commands without typing `git`:
```
[.../awesome-repo/ (master)]igitari> status
On branch master
Your branch is up to date with 'origin/master'.

nothing to commit, working tree clean
```

Run shell commands (prefix with `>`):
```
[.../awesome-repo/ (master)]igitari> > ls
README.md  package.json  src/
```

Open repository in browser:
```
[.../awesome-repo/ (master)]igitari> openweb origin
Opened: https://github.com/user/repo
```

### Operator Support
```
[.../awesome-repo/ (master)]igitari> status && > ls -la
[.../awesome-repo/ (master)]igitari> add . || echo "Failed to add files"
```

### Comments and Continuation
```
[.../awesome-repo/ (master)]igitari> status          # what is staged?
[.../awesome-repo/ (master)]igitari> squash 3 \
                                     > "feat: one clean commit"
```

A `#` starts a comment anywhere outside quotes, so `commit -m "fix #123"`
still means what it says. A trailing `\` continues the command on the next
line.

## Uninstallation
```sh
rm $(which igitari)
```

## License
AGPL-3.0-or-later © 2025 BashhScriptKid

Igitari is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

See the full license in the script header or at https://www.gnu.org/licenses/
## Why AGPL?
Igitari uses AGPL-3.0-or-later to ensure it remains free and open. If you modify and distribute Igitari (including as part of a web service), you must share your changes. This prevents SaaS exploitation while encouraging community improvements.

---
Hope this is useful!

