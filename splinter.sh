#!/usr/bin/env bash
set -euo pipefail

ORCH="${ORCH:-$HOME/src/codex-orch}"
SPLINTER_HOME="${SPLINTER_HOME:-$ORCH/splinter}"
RULES_FILE="$SPLINTER_HOME/rules.md"

usage() {
  cat <<'USAGE'
splinter: manual shared rules for turtle runs

Usage:
  splinter init
  splinter brief [--run-file /path/to/run.env] [--output /path/to/brief.md]
  splinter rules
  splinter open
  splinter help

Environment:
  ORCH=/path/to/orch (default: ~/src/codex-orch)
  SPLINTER_HOME=/path/to/splinter (default: $ORCH/splinter)

What Splinter manages:
  - rules.md: one human-edited rules document included in future turtle briefs

Splinter is manual-only. It does not ingest run logs, build memories, distill
signals, or run AI review cycles.
USAGE
}

die() {
  echo "Error: $*" >&2
  exit 1
}

ensure_dirs() {
  mkdir -p "$SPLINTER_HOME/briefs"

  if [ ! -f "$RULES_FILE" ]; then
    cat > "$RULES_FILE" <<'EOF'
# Splinter Rules

Edit this file directly. Keep entries short, durable, and reusable across turtle runs.

## Preferences

- Add durable preferences here.

## Corrections To Remember

- Add repeated correction patterns here.

## Repo-Specific Notes

- Add workflow or review notes that should apply to future runs.
EOF
  fi
}

load_run_file() {
  local run_file="$1"
  [ -f "$run_file" ] || die "Run file not found: $run_file"

  unset RUN_ID TURTLE BRANCH WORKTREE REPO TRUNK REMOTE MANIFEST LOGFILE BRIEF_FILE STARTED_AT ENDED_AT EXIT_CODE
  # shellcheck disable=SC1090
  source "$run_file"
}

cmd_init() {
  ensure_dirs
  echo "Initialized Splinter at $SPLINTER_HOME"
  echo "Rules: $RULES_FILE"
}

cmd_brief() {
  local run_file="" output_file="" branch_name="" turtle_name=""

  ensure_dirs

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --run-file)
        shift
        run_file="${1:-}"
        ;;
      --output)
        shift
        output_file="${1:-}"
        ;;
      --branch)
        shift
        branch_name="${1:-}"
        ;;
      --turtle)
        shift
        turtle_name="${1:-}"
        ;;
      *)
        die "Unknown argument for brief: $1"
        ;;
    esac
    shift || true
  done

  if [ -n "$run_file" ]; then
    load_run_file "$run_file"
    branch_name="${BRANCH:-$branch_name}"
    turtle_name="${TURTLE:-$turtle_name}"
  fi

  [ -n "$output_file" ] || output_file="$SPLINTER_HOME/briefs/${turtle_name:-shared}-$(date '+%Y%m%d-%H%M%S').md"

  {
    echo "# Splinter Brief"
    echo
    if [ -n "$turtle_name" ] || [ -n "$branch_name" ]; then
      echo "- Turtle: ${turtle_name:-unknown}"
      echo "- Branch: ${branch_name:-unknown}"
      echo
    fi
    echo "- Rules file: $RULES_FILE"
    echo
    echo "## Manual Rules"
    echo
    cat "$RULES_FILE"
  } > "$output_file"

  echo "$output_file"
}

cmd_rules() {
  ensure_dirs
  echo "Rules: $RULES_FILE"
  echo
  sed -n '1,260p' "$RULES_FILE"
}

cmd_open() {
  ensure_dirs

  if command -v open >/dev/null 2>&1; then
    open "$RULES_FILE"
  elif [ -n "${EDITOR:-}" ]; then
    "$EDITOR" "$RULES_FILE"
  else
    vi "$RULES_FILE"
  fi
}

main() {
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    init) cmd_init "$@" ;;
    brief) cmd_brief "$@" ;;
    rules) cmd_rules "$@" ;;
    open) cmd_open "$@" ;;
    -h|--help|help|"") usage ;;
    *) die "Unknown command '$cmd'. Run: splinter help" ;;
  esac
}

main "$@"
