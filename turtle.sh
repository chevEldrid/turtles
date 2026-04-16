#!/usr/bin/env bash
set -euo pipefail

# turtle: PR-per-task branch prep for 4 persistent git worktrees plus
# a structured session start path that integrates with Splinter.
#
# Default layout:
#   Repo:          ~/work/myrepo              (set REPO=... to override)
#   Orchestration: ~/src/codex-orch          (set ORCH=... to override)
#   Worktrees:     ~/src/codex-orch/worktrees/<turtle>
#   Manifests:     ~/src/codex-orch/manifests/<turtle>.md
#   Runs:          ~/src/codex-orch/runs/<turtle>/<run_id>/

# --- CONFIG ---
REPO="${REPO:-$HOME/work/myrepo}"      # <-- change this default if you want
ORCH="${ORCH:-$HOME/src/codex-orch}"
TRUNK="${TRUNK:-main}"
REMOTE="${REMOTE:-origin}"

# --- HELP ---
usage() {
  cat <<'USAGE'
turtle: codex multi-agent worktree prep with PR-per-task branches

Usage:
  turtle init
  turtle prep <turtle> "<ticket-or-objective>"   # branch prep only
  turtle start <turtle> [command ...]            # generate Splinter brief, log session, then run codex
  turtle status
  turtle open <turtle>                           # prints worktree path
  turtle reset <turtle>                          # hard reset & clean worktree to origin/main (DANGEROUS)
  turtle remove <turtle>                         # remove worktree (keeps branches)
  turtle cleanup <turtle>                        # resets and removes current branch (DANGEROUS)
  turtle help

Turtles: raphael | donatello | michelangelo | leonardo

Env vars:
  REPO=/path/to/repo
  ORCH=/path/to/orch (default: ~/src/codex-orch)
  TRUNK=main
  REMOTE=origin
  SPLINTER_CMD=/path/to/splinter
  TURTLE_CODEX_CMD='codex --some-flag'

Recommended workflow:
  turtle prep raphael "TRUE-12345"
  turtle start raphael

The start command creates a run record, writes a Splinter brief, mirrors it into
the turtle worktree as SPLINTER_BRIEF.md, logs the session, and asks Splinter
to ingest the run when the command exits.
USAGE
}

die(){ echo "Error: $*" >&2; exit 1; }

turtle_ok() {
  case "${1:-}" in
    raphael|donatello|michelangelo|leonardo) ;;
    *) die "Unknown turtle '${1:-}'. Must be raphael | donatello | michelangelo | leonardo." ;;
  esac
}

wt_path() { echo "$ORCH/worktrees/$1"; }
manifest() { echo "$ORCH/manifests/$1.md"; }
run_root() { echo "$ORCH/runs/$1"; }
run_path() { echo "$ORCH/runs/$1/$2"; }
base_branch() { echo "agent/$1-base"; } # anchors persistent worktree

shell_quote() {
  printf "%s" "${1:-}" | sed "s/'/'\\\\''/g"
}

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
  mkdir -p "$ORCH"/{worktrees,manifests,locks,runs}
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
    if git show-ref --verify --quiet "refs/heads/$b"; then
      git worktree add "$w" "$b"
    else
      git worktree add -b "$b" "$w" "$REMOTE/$TRUNK"
    fi
  )
}

current_branch() {
  local t="$1"
  local w; w="$(wt_path "$t")"
  ( cd "$w" && git rev-parse --abbrev-ref HEAD )
}

is_turtle_task_branch() {
  local t="$1"
  local b="$2"
  [[ "$b" == "agent/$t/"* ]]
}

ensure_local_trunk_branch() {
  local t="$1"
  local w; w="$(wt_path "$t")"
  ( cd "$w"
    git fetch "$REMOTE" --prune
    if git show-ref --verify --quiet "refs/heads/$TRUNK"; then
      git checkout "$TRUNK" >/dev/null
      git reset --hard "$REMOTE/$TRUNK" >/dev/null
    else
      git checkout -B "$TRUNK" "$REMOTE/$TRUNK" >/dev/null
    fi
  )
}

checkout_new_task_branch() {
  local t="$1"
  local objective="$2"
  local w; w="$(wt_path "$t")"
  local b; b="$(task_branch "$t" "$objective")"

  ( cd "$w"
    if ! git diff --quiet || ! git diff --cached --quiet; then
      echo "Error: $t has uncommitted changes in $w; commit/stash before starting a new task." >&2
      exit 1
    fi

    git fetch "$REMOTE" --prune
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

write_manifest_start() {
  local t="$1"
  local run_id="$2"
  local branch_name="$3"
  local log_file="$4"
  local brief_file="$5"
  local m; m="$(manifest "$t")"
  local now; now="$(date '+%Y-%m-%d %H:%M:%S')"

  cat >> "$m" <<EOF

---
Run ID: $run_id
Started: $now
Branch: $branch_name
Status: started
Brief: $brief_file
Log: $log_file
EOF
}

find_splinter_cmd() {
  local script_dir candidate

  if [ -n "${SPLINTER_CMD:-}" ] && [ -x "${SPLINTER_CMD:-}" ]; then
    echo "$SPLINTER_CMD"
    return 0
  fi

  if command -v splinter >/dev/null 2>&1; then
    command -v splinter
    return 0
  fi

  script_dir="$(cd "$(dirname "$0")" && pwd)"
  for candidate in "$script_dir/splinter" "$script_dir/splinter.sh"; do
    if [ -x "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

ensure_worktree_exclude() {
  local w="$1"
  local pattern="$2"
  local exclude_file

  exclude_file="$(git -C "$w" rev-parse --git-path info/exclude)"
  mkdir -p "$(dirname "$exclude_file")"
  touch "$exclude_file"

  if ! grep -qxF "$pattern" "$exclude_file"; then
    printf '\n%s\n' "$pattern" >> "$exclude_file"
  fi
}

write_run_file() {
  local run_file="$1"
  local run_id="$2"
  local turtle="$3"
  local branch_name="$4"
  local worktree="$5"
  local manifest_file="$6"
  local log_file="$7"
  local brief_file="$8"
  local started_at="$9"

  cat > "$run_file" <<EOF
RUN_ID='$(shell_quote "$run_id")'
TURTLE='$(shell_quote "$turtle")'
BRANCH='$(shell_quote "$branch_name")'
WORKTREE='$(shell_quote "$worktree")'
REPO='$(shell_quote "$REPO")'
TRUNK='$(shell_quote "$TRUNK")'
REMOTE='$(shell_quote "$REMOTE")'
MANIFEST='$(shell_quote "$manifest_file")'
LOGFILE='$(shell_quote "$log_file")'
BRIEF_FILE='$(shell_quote "$brief_file")'
STARTED_AT='$(shell_quote "$started_at")'
EOF
}

append_run_result() {
  local run_file="$1"
  local ended_at="$2"
  local exit_code="$3"

  cat >> "$run_file" <<EOF
ENDED_AT='$(shell_quote "$ended_at")'
EXIT_CODE='$(shell_quote "$exit_code")'
EOF
}

install_brief_into_worktree() {
  local worktree="$1"
  local brief_file="$2"
  local target="$worktree/SPLINTER_BRIEF.md"

  if [ -f "$brief_file" ]; then
    cp "$brief_file" "$target"
    ensure_worktree_exclude "$worktree" "SPLINTER_BRIEF.md"
  fi
}

run_with_logging() {
  local log_file="$1"
  shift || true

  if [ "$#" -gt 0 ]; then
    "$@" 2>&1 | tee -a "$log_file"
  elif [ -n "${TURTLE_CODEX_CMD:-}" ]; then
    bash -lc "$TURTLE_CODEX_CMD" 2>&1 | tee -a "$log_file"
  else
    codex 2>&1 | tee -a "$log_file"
  fi
}

cmd_init() {
  local splinter_cmd

  ensure_dirs
  ensure_repo
  for t in raphael donatello michelangelo leonardo; do
    ensure_manifest "$t"
    ensure_worktree "$t"
  done

  splinter_cmd="$(find_splinter_cmd || true)"
  if [ -n "$splinter_cmd" ]; then
    "$splinter_cmd" init >/dev/null
  fi

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

  local new_branch w
  new_branch="$(checkout_new_task_branch "$t" "$objective")"
  write_manifest_update "$t" "$objective" "$new_branch"
  w="$(wt_path "$t")"

  cat <<EOF

Prepared: $t
Worktree: $w
Branch:   $new_branch
Manifest: $(manifest "$t")

Next:
  cd "$w"
  git status -sb
  turtle start "$t"

When ready for PR:
  git push -u $REMOTE HEAD

EOF
}

cmd_start() {
  local t="${1:-}"
  local splinter_cmd branch_name worktree run_id run_dir run_file log_file brief_file started_at ended_at
  local exit_code=0
  shift || true

  [ -n "$t" ] || die "Missing turtle name."
  turtle_ok "$t"

  ensure_dirs
  ensure_repo
  ensure_manifest "$t"
  ensure_worktree "$t"

  worktree="$(wt_path "$t")"
  branch_name="$(current_branch "$t")"
  run_id="$(date '+%Y%m%d-%H%M%S')"
  run_dir="$(run_path "$t" "$run_id")"
  run_file="$run_dir/run.env"
  log_file="$run_dir/session.log"
  brief_file="$run_dir/splinter-brief.md"
  started_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  splinter_cmd="$(find_splinter_cmd || true)"

  mkdir -p "$run_dir"
  write_run_file "$run_file" "$run_id" "$t" "$branch_name" "$worktree" "$(manifest "$t")" "$log_file" "$brief_file" "$started_at"

  if [ -n "$splinter_cmd" ]; then
    "$splinter_cmd" brief --run-file "$run_file" --output "$brief_file" >/dev/null || true
  fi

  install_brief_into_worktree "$worktree" "$brief_file"
  write_manifest_start "$t" "$run_id" "$branch_name" "$log_file" "$brief_file"

  cat <<EOF

Starting: $t
Worktree: $worktree
Branch:   $branch_name
Run ID:   $run_id
Log:      $log_file
Brief:    $brief_file

The current brief is mirrored into the worktree as:
  $worktree/SPLINTER_BRIEF.md

EOF

  (
    cd "$worktree"
    run_with_logging "$log_file" "$@"
  ) || exit_code=$?

  ended_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  append_run_result "$run_file" "$ended_at" "$exit_code"

  if [ -n "$splinter_cmd" ]; then
    "$splinter_cmd" ingest --run-file "$run_file" >/dev/null || true
  fi

  return "$exit_code"
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

cmd_cleanup() {
  local t="${1:-}"
  turtle_ok "$t"
  local w; w="$(wt_path "$t")"
  [ -d "$w" ] || die "No worktree for $t at $w"
  local old_branch
  old_branch="$(current_branch "$t")"
  if (cd "$w" && (! git diff --quiet || ! git diff --cached --quiet)); then
    die "$t has uncommitted changes in $w. Commit/stash/discard before cleanup."
  fi
  echo "Cleaning up $t worktree: $w"
  echo "Current branch: $old_branch"
  echo "Target: $REMOTE/$TRUNK"
  ensure_local_trunk_branch "$t"
  ( cd "$w"
    git clean -fd >/dev/null
    git remote prune "$REMOTE" >/dev/null || true
  )
  if is_turtle_task_branch "$t" "$old_branch"; then
    ( cd "$w"
      git branch -D "$old_branch" >/dev/null 2>&1 || true
    )
    echo "Deleted local task branch: $old_branch"
  else
    echo "Not deleting branch (not a turtle task branch): $old_branch"
  fi
  echo "Cleanup complete. $t is now on $TRUNK at $(cd "$w" && git rev-parse --short HEAD)."
}

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    init) cmd_init ;;
    prep) cmd_prep "$@" ;;
    start) cmd_start "$@" ;;
    status) cmd_status ;;
    open) cmd_open "$@" ;;
    reset) cmd_reset "$@" ;;
    remove) cmd_remove "$@" ;;
    cleanup) cmd_cleanup "$@" ;;
    -h|--help|help|"") usage ;;
    *) die "Unknown command '$cmd'. Run: turtle help" ;;
  esac
}

main "$@"
