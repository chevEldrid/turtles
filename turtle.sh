#!/usr/bin/env bash
set -euo pipefail

# turtle: PR-per-task branch prep for 4 persistent git worktrees (no tmux)
# You keep 4 terminal windows open yourself and run `codex` manually in each.
#
# Default layout:
#   Repo:        ~/work/myrepo           (set REPO=... to override)
#   Orchestration: ~/codex-orch          (set ORCH=... to override)
#   Worktrees:   ~/codex-orch/worktrees/<turtle>
#   Logs:        ~/codex-orch/logs/<turtle>/
#   Manifests:   ~/codex-orch/manifests/<turtle>.md

# --- CONFIG ---
REPO="${REPO:-$HOME/work/myrepo}"      # <-- change this default if you want
ORCH="${ORCH:-$HOME/codex-orch}"
TRUNK="${TRUNK:-main}"
REMOTE="${REMOTE:-origin}"

# --- HELP ---
usage() {
  cat <<'USAGE'
turtle: codex multi-agent worktree prep (NO tmux) with PR-per-task branches

Usage:
  turtle init
  turtle prep <turtle> "<objective text>"     # creates/checks out new per-task branch; prints next steps
  turtle status
  turtle open <turtle>                        # prints worktree path
  turtle reset <turtle>                       # hard reset & clean worktree to origin/main (DANGEROUS)
  turtle remove <turtle>                      # remove worktree (keeps branches)
  turtle help

Turtles: raphael | donatello | michelangelo | leonardo

Env vars:
  REPO=/path/to/repo
  ORCH=/path/to/orch (default: ~/codex-orch)
  TRUNK=main
  REMOTE=origin

Recommended workflow (4 separate terminal windows):
  Window 1: cd "$(turtle open raphael)"
  Window 2: cd "$(turtle open donatello)"
  Window 3: cd "$(turtle open michelangelo)"
  Window 4: cd "$(turtle open leonardo)"

Then for each new task:
  turtle prep raphael "Fix flaky tests in JournalEntryService update suite"
  # In Raphael window: run the printed codex command (or just 'codex' if you don't care about tee logs)
USAGE
}

die(){ echo "Error: $*" >&2; exit 1; }

turtle_ok() {
  case "${1:-}" in
    raphael|donatello|michelangelo|leonardo) ;;
    *) die "Unknown turtle '${1:-}'. Must be raphael|donatello|michelangelo|leonardo." ;;
  esac
}

wt_path() { echo "$ORCH/worktrees/$1"; }
log_dir() { echo "$ORCH/logs/$1"; }
manifest() { echo "$ORCH/manifests/$1.md"; }
base_branch() { echo "agent/$1-base"; } # anchors persistent worktree

slugify() {
  echo "$*" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g' \
    | cut -c1-48
}

task_branch() {
  local t="$1"
  local objective="$2"
  local ts slug
  ts="$(date '+%Y%m%d-%H%M')"
  slug="$(slugify "$objective")"
  echo "agent/$t/${slug:-task}-$ts"
}

ensure_dirs() {
  mkdir -p "$ORCH"/{worktrees,logs,manifests,locks}
}

ensure_repo() {
  [ -d "$REPO/.git" ] || die "REPO not a git repo: $REPO (set REPO=...)"
}

ensure_manifest() {
  local t="$1"
  local m; m="$(manifest "$t")"
  if [ ! -f "$m" ]; then
    cat > "$m" <<EOF
# $t

Objective:
Scope:
Constraints:
Status:
Next action:
PR:
Started:
Last updated:
EOF
  fi
}

ensure_worktree() {
  local t="$1"
  local w; w="$(wt_path "$t")"
  local b; b="$(base_branch "$t")"

  if [ -d "$w/.git" ] || [ -f "$w/.git" ]; then
    return 0
  fi

  mkdir -p "$(dirname "$w")"
  ( cd "$REPO"
    git fetch "$REMOTE" --prune
    # Create a stable base branch for the turtle worktree if needed
    if git show-ref --verify --quiet "refs/heads/$b"; then
      git worktree add "$w" "$b"
    else
      git worktree add -b "$b" "$w" "$REMOTE/$TRUNK"
    fi
  )
}

checkout_new_task_branch() {
  local t="$1"
  local objective="$2"
  local w; w="$(wt_path "$t")"
  local b; b="$(task_branch "$t" "$objective")"

  ( cd "$w"
    # Don't stomp on work-in-progress
    if ! git diff --quiet || ! git diff --cached --quiet; then
      echo "Error: $t has uncommitted changes in $w; commit/stash before starting a new task." >&2
      exit 1
    fi

    git fetch "$REMOTE" --prune
    # Create new branch off latest trunk
    git checkout -B "$b" "$REMOTE/$TRUNK" >/dev/null
    echo "$b"
  )
}

write_manifest_update() {
  local t="$1"
  local objective="$2"
  local branch_name="$3"
  local m; m="$(manifest "$t")"
  local now; now="$(date '+%Y-%m-%d %H:%M:%S')"

  ensure_manifest "$t"

  cat >> "$m" <<EOF

---
Run: $now
Objective: $objective
Branch: $branch_name
Status: prepared
EOF
}

make_logfile() {
  local t="$1"
  local ldir; ldir="$(log_dir "$t")"
  mkdir -p "$ldir"
  echo "$ldir/$(date '+%F_%H-%M-%S').log"
}

cmd_init() {
  ensure_dirs
  ensure_repo
  for t in raphael donatello michelangelo leonardo; do
    ensure_manifest "$t"
    ensure_worktree "$t"
  done
  echo "Initialized."
  echo "Open 4 terminals and run:"
  echo "  cd \"$(wt_path raphael)\""
  echo "  cd \"$(wt_path donatello)\""
  echo "  cd \"$(wt_path michelangelo)\""
  echo "  cd \"$(wt_path leonardo)\""
}

cmd_prep() {
  local t="${1:-}"; shift || true
  local objective="${1:-}"; shift || true
  [ -n "$t" ] || die "Missing turtle name."
  [ -n "$objective" ] || die "Missing objective string."
  turtle_ok "$t"

  ensure_dirs
  ensure_repo
  ensure_manifest "$t"
  ensure_worktree "$t"

  local new_branch logfile w
  new_branch="$(checkout_new_task_branch "$t" "$objective")"
  write_manifest_update "$t" "$objective" "$new_branch"

  logfile="$(make_logfile "$t")"
  w="$(wt_path "$t")"

  cat <<EOF

Prepared: $t
Worktree: $w
Branch:   $new_branch
Manifest: $(manifest "$t")
Log:      $logfile

Next (run in your $t terminal window):
  cd "$w"
  # optional: confirm branch
  git status -sb
  # start codex with logging
  codex 2>&1 | tee -a "$logfile"

When ready for PR:
  git push -u $REMOTE HEAD
  # open PR in your host (or use gh pr create if you use GitHub CLI)

EOF
}

cmd_status() {
  ensure_repo
  for t in raphael donatello michelangelo leonardo; do
    local w; w="$(wt_path "$t")"
    if [ -d "$w" ]; then
      echo "== $t ==";
      (cd "$w" && git status -sb) || true
      echo
    else
      echo "== $t == (no worktree at $w)"
      echo
    fi
  done
}

cmd_open() {
  local t="${1:-}"
  turtle_ok "$t"
  echo "$(wt_path "$t")"
}

cmd_reset() {
  local t="${1:-}"
  turtle_ok "$t"
  local w; w="$(wt_path "$t")"
  [ -d "$w" ] || die "No worktree for $t at $w"
  echo "WARNING: This will HARD RESET and CLEAN: $w -> $REMOTE/$TRUNK"
  (cd "$w" && git fetch "$REMOTE" && git reset --hard "$REMOTE/$TRUNK" && git clean -fd)
  echo "Reset $t to $REMOTE/$TRUNK"
}

cmd_remove() {
  local t="${1:-}"
  turtle_ok "$t"
  local w; w="$(wt_path "$t")"
  (cd "$REPO" && git worktree remove "$w") || true
  echo "Removed worktree: $w"
}

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    init) cmd_init ;;
    prep|start) cmd_prep "$@" ;;   # 'start' alias for convenience
    status) cmd_status ;;
    open) cmd_open "$@" ;;
    reset) cmd_reset "$@" ;;
    remove) cmd_remove "$@" ;;
    -h|--help|help|"") usage ;;
    *) die "Unknown command '$cmd'. Run: turtle help" ;;
  esac
}

main "$@"
