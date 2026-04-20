# Turtles (Raphael / Donatello / Michelangelo / Leonardo)
A lightweight “4-agent” workflow for running **four concurrent Codex sessions** against the **same repo** safely using:

- **git worktrees** (one per turtle) to avoid file collisions
- **PR-per-task branches** (one branch/PR for every task you assign)
- **four persistent terminal windows** (you launch Codex through `turtle start`)
- **Splinter shared memory** generated from turtle run artifacts
- orchestration artifacts stored **outside** the repo (`~/src/codex-orch`) to keep work clean

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
turtle prep <turtle> "TASK-12345"
turtle start <turtle>
```

## Installation
1) Choose an orchestration directory
This guide uses:

Orchestration home: ~/src/codex-orch (outside the repo)

Create it:
```bash
mkdir -p ~/src/codex-orch/{worktrees,manifests,locks,runs}
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

Optional: install the Splinter helper beside it:
```bash
cp splinter.sh ~/bin/splinter
chmod +x ~/bin/splinter
which splinter
splinter help
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
~/src/codex-orch/worktrees/raphael
~/src/codex-orch/worktrees/donatello
~/src/codex-orch/worktrees/michelangelo
~/src/codex-orch/worktrees/leonardo
```
4 manifests:
```bash
~/src/codex-orch/manifests/<turtle>.md
```
Run artifacts as you start sessions:
```bash
~/src/codex-orch/runs/<turtle>/<run_id>/
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
turtle prep raphael "TRUE-12345"
```
You’ll see output like:

- Worktree path
- Newly created branch name
- Manifest path

2) Start the turtle session
From that turtle’s terminal window:
```bash
turtle start raphael
```

`turtle start` now does the runtime setup:

- creates a run record under `~/src/codex-orch/runs/...`
- generates a Splinter brief for that run
- mirrors the brief into the worktree as `SPLINTER_BRIEF.md`
- excludes `SPLINTER_BRIEF.md` from git status
- logs the session output
- runs `splinter ingest` when the session exits

By default, `turtle start` launches:
```bash
codex --dangerously-bypass-approvals-and-sandbox
```

If you need to override the Codex launch command temporarily:
```bash
TURTLE_CODEX_CMD='codex --dangerously-bypass-approvals-and-sandbox' turtle start raphael
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
open ~/src/codex-orch/manifests/raphael.md
```

## Splinter memory

`splinter` is the shared-memory sidecar for turtles. The intended flow is:

1. `turtle start` creates a run artifact set
2. the session log and git metadata are ingested automatically
3. Splinter stores raw observations in `signals.jsonl`
4. when `codex exec` is available, Splinter distills raw signals into `learnings.ai.md`
5. Splinter mirrors the AI-distilled memory into `learnings.auto.md` for turtle briefs
6. you edit `learnings.md` when you want to keep or correct a durable learning

Initialize Splinter storage:
```bash
splinter init
```

That creates:
```bash
~/src/codex-orch/splinter/signals.jsonl
~/src/codex-orch/splinter/learnings.md
~/src/codex-orch/splinter/learnings.auto.md
~/src/codex-orch/splinter/learnings.ai.md
~/src/codex-orch/splinter/briefs/
~/src/codex-orch/splinter/reviews/
```

Useful manual controls:
```bash
splinter ingest
splinter learnings
splinter open
splinter show
```

What each command does:

- `splinter ingest`: re-run ingestion across turtle runs, or ingest a specific run with `--run-file`
- `splinter learnings`: print the curated and generated learnings files
- `splinter open`: open `learnings.md` for manual curation
- `splinter show`: inspect recent raw signals

AI distillation is enabled automatically when `codex exec` is available:
```bash
splinter ingest --ai
splinter ingest --no-ai
SPLINTER_AI=0 splinter ingest
SPLINTER_AI_MODEL=gpt-5.4-mini splinter ingest
```

The distillation review packets are saved under:
```bash
~/src/codex-orch/splinter/reviews/
```

If you want to regenerate a brief manually for a known run:
```bash
splinter brief --run-file ~/src/codex-orch/runs/raphael/<run_id>/run.env
```

The main files are:

- `signals.jsonl`: append-only raw auto-ingested observations
- `learnings.auto.md`: generated memory included in future turtle briefs
- `learnings.ai.md`: generated AI distillation from raw signals
- `learnings.md`: human-edited shared memory future turtles should trust
