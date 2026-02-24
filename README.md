# Turtles (Raphael / Donatello / Michelangelo / Leonardo)
A lightweight “4-agent” workflow for running **four concurrent Codex sessions** against the **same repo** safely using:

- **git worktrees** (one per turtle) to avoid file collisions
- **PR-per-task branches** (one branch/PR for every task you assign)
- **four persistent terminal windows** (you run `codex` manually in each)
- orchestration artifacts stored **outside** the repo (`~/codex-orch`) to keep work clean

This is intentionally minimal and “distinct” from the codebase: it doesn’t add files to your repo and doesn’t require tmux.

---

## Overview

You will keep 4 terminal windows open:

1. `raphael` worktree
2. `donatello` worktree
3. `michelangelo` worktree
4. `leonardo` worktree

Each time you assign a task to a turtle, you run:

```bash
turtle prep <turtle> "Your objective"
```

## Installation
1) Choose an orchestration directory
This guide uses:

Orchestration home: ~/codex-orch (outside the repo)

Create it:
```bash
mkdir -p ~/codex-orch/{worktrees,logs,manifests,locks}
```
2) Install the turtle script
Put the script at:
```bash
~/bin/turtle
```
Ensure ~/bin exists:
```bash
mkdir -p ~/bin
```
Create the file:
```bash
nano ~/bin/turtle
```
Paste the provided script contents into that file, save, then:
```bash
chmod +x ~/bin/turtle
```
3) Add ~/bin to your PATH
If it isn’t already:
```bash
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```
Verify:
```bash
which turtle
turtle help
```

## One-time setup
1) Initialize the turtles
Run:
```bash
turtle init
```
This creates:
4 worktrees:
```bash
~/codex-orch/worktrees/raphael
~/codex-orch/worktrees/donatello
~/codex-orch/worktrees/michelangelo
~/codex-orch/worktrees/leonardo
```
4 manifests:
```bash
~/codex-orch/manifests/<turtle>.md
```
Note: The worktrees are anchored to stable base branches like agent/raphael,
but each task creates a new branch under agent/<turtle>/....

2) Open 4 terminal windows (persistent)
Open four terminal windows/tabs and in each:

Raphael:
```bash
cd "$(turtle open raphael)"
```
Donatello:
```bash
cd "$(turtle open donatello)"
```
Michelangelo:
```bash
cd "$(turtle open michelangelo)"
```
Leonardo:
```bash
cd "$(turtle open leonardo)"
```
You now have four isolated workspaces ready for concurrent work.

## Daily workflow (PR per task)
1) Assign a task to a turtle
From any terminal:
```bash
turtle prep raphael "Fix flaky tests in JournalEntryService update suite"
```
You’ll see output like:

- Worktree path
- Newly created branch name
- Manifest path
- Log file path

“Next steps” commands to run in that turtle’s window

2) In that turtle’s terminal window, start Codex
```bash
codex --dangerously-bypass-approvals-and-sandbox
```

## Checking progress across turtles
Show status for all turtles
```bash
turtle status
```
This prints git status -sb for each turtle worktree.

### View manifests

Manifests are kept outside the repo:
```bash
open ~/codex-orch/manifests/raphael.md
```
