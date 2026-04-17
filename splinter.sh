#!/usr/bin/env bash
set -euo pipefail

ORCH="${ORCH:-$HOME/src/codex-orch}"
SPLINTER_HOME="${SPLINTER_HOME:-$ORCH/splinter}"
RUNS_HOME="$ORCH/runs"
SIGNALS_FILE="$SPLINTER_HOME/signals.jsonl"
INGESTED_FILE="$SPLINTER_HOME/ingested-runs.txt"
LEARNINGS_FILE="$SPLINTER_HOME/learnings.md"
AUTO_FILE="$SPLINTER_HOME/learnings.auto.md"

usage() {
  cat <<'USAGE'
splinter: automatic shared memory for turtle runs

Usage:
  splinter init
  splinter ingest [--run-file /path/to/run.env] [--force]
  splinter brief [--run-file /path/to/run.env] [--output /path/to/brief.md]
  splinter learnings
  splinter open
  splinter show
  splinter help

Environment:
  ORCH=/path/to/orch (default: ~/src/codex-orch)
  SPLINTER_HOME=/path/to/splinter (default: $ORCH/splinter)

What Splinter manages:
  - signals.jsonl: append-only auto-ingested observations from turtle runs
  - learnings.auto.md: generated patterns from repeated signals
  - learnings.md: curated human-editable shared memory for future turtle runs
USAGE
}

die() {
  echo "Error: $*" >&2
  exit 1
}

ensure_dirs() {
  mkdir -p "$SPLINTER_HOME"/{briefs,reviews}
  touch "$SIGNALS_FILE" "$INGESTED_FILE"

  if [ ! -f "$LEARNINGS_FILE" ]; then
    cat > "$LEARNINGS_FILE" <<'EOF'
# Splinter Learnings

Edit this file directly. Keep entries short, durable, and reusable across turtle runs.

## Preferences

- Add durable preferences here.

## Corrections To Remember

- Add repeated correction patterns here.

## Repo-Specific Notes

- Add workflow or review notes that should apply to future runs.
EOF
  fi

  if [ ! -f "$AUTO_FILE" ]; then
    cat > "$AUTO_FILE" <<'EOF'
# Splinter Auto Learnings

Generated from ingested turtle runs. Edit `learnings.md` for curated memory.
EOF
  fi
}

json_escape() {
  local s="${1:-}"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

json_field() {
  local field="$1"
  sed -n "s/.*\"$field\":\"\\([^\"]*\\)\".*/\\1/p"
}

json_unescape() {
  printf '%b' "$(printf '%s' "${1:-}" | sed 's/\\"/"/g; s/\\\\/\\/g')"
}

trim_line() {
  printf '%s' "${1:-}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

reverse_lines() {
  awk '{ lines[NR] = $0 } END { for (i = NR; i >= 1; i--) print lines[i] }'
}

branch_keywords() {
  printf '%s\n' "${1:-}" \
    | tr '/:-_' ' ' \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9 ]+/ /g' \
    | tr ' ' '\n' \
    | awk 'length($0) >= 4 && $0 !~ /^(agent|base|main|head|true|task|raphael|donatello|michelangelo|leonardo)$/'
}

load_run_file() {
  local run_file="$1"
  [ -f "$run_file" ] || die "Run file not found: $run_file"

  unset RUN_ID TURTLE BRANCH WORKTREE REPO TRUNK REMOTE MANIFEST LOGFILE BRIEF_FILE STARTED_AT ENDED_AT EXIT_CODE
  # shellcheck disable=SC1090
  source "$run_file"
}

append_signal() {
  local type="$1"
  local source_name="$2"
  local run_id="$3"
  local turtle="$4"
  local branch="$5"
  local repo="$6"
  local summary="$7"
  local confidence="$8"
  local signal_id timestamp

  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  signal_id="${run_id:-$(date '+%Y%m%d%H%M%S')}-$(date '+%s')-$$"

  printf '{"id":"%s","ts":"%s","type":"%s","source":"%s","run_id":"%s","turtle":"%s","branch":"%s","repo":"%s","summary":"%s","confidence":"%s"}\n' \
    "$(json_escape "$signal_id")" \
    "$(json_escape "$timestamp")" \
    "$(json_escape "$type")" \
    "$(json_escape "$source_name")" \
    "$(json_escape "$run_id")" \
    "$(json_escape "$turtle")" \
    "$(json_escape "$branch")" \
    "$(json_escape "$repo")" \
    "$(json_escape "$summary")" \
    "$(json_escape "$confidence")" >> "$SIGNALS_FILE"
}

run_already_ingested() {
  local run_file="$1"
  grep -qxF "$run_file" "$INGESTED_FILE"
}

mark_run_ingested() {
  local run_file="$1"
  if ! run_already_ingested "$run_file"; then
    printf '%s\n' "$run_file" >> "$INGESTED_FILE"
  fi
}

base_ref_for_worktree() {
  if git -C "$WORKTREE" show-ref --verify --quiet "refs/heads/$TRUNK"; then
    echo "$TRUNK"
  elif git -C "$WORKTREE" show-ref --verify --quiet "refs/remotes/$REMOTE/$TRUNK"; then
    echo "$REMOTE/$TRUNK"
  else
    echo "HEAD~1"
  fi
}

collect_changed_files() {
  local base_ref merge_base
  base_ref="$(base_ref_for_worktree)"
  merge_base="$(git -C "$WORKTREE" merge-base HEAD "$base_ref" 2>/dev/null || true)"

  if [ -n "$merge_base" ]; then
    git -C "$WORKTREE" diff --name-only "$merge_base..HEAD" 2>/dev/null || true
  else
    git -C "$WORKTREE" diff --name-only HEAD~1..HEAD 2>/dev/null || true
  fi
}

collect_changed_areas() {
  collect_changed_files \
    | awk -F/ 'NF { print $1 }' \
    | sed '/^$/d' \
    | sort \
    | uniq \
    | head -n 8
}

collect_commit_subjects() {
  local base_ref
  base_ref="$(base_ref_for_worktree)"
  git -C "$WORKTREE" log --format='%s' "$base_ref..HEAD" 2>/dev/null | head -n 5
}

summarize_run() {
  local changed_areas commit_subjects test_status area_summary commit_summary

  changed_areas="$(collect_changed_areas | paste -sd ', ' -)"
  commit_subjects="$(collect_commit_subjects | paste -sd ' | ' -)"

  if collect_changed_files | grep -Eiq '(^|/)(__tests__|tests?)/|(\.test\.|\.spec\.)'; then
    test_status="tests changed"
  else
    test_status="no test-file changes observed"
  fi

  if [ -n "$changed_areas" ]; then
    area_summary="areas: $changed_areas"
  else
    area_summary="areas: none detected"
  fi

  if [ -n "$commit_subjects" ]; then
    commit_summary="commits: $commit_subjects"
  else
    commit_summary="commits: none detected"
  fi

  printf 'Run %s on %s touched %s; %s; %s.' "$RUN_ID" "$BRANCH" "$area_summary" "$test_status" "$commit_summary"
}

extract_candidate_lines() {
  [ -f "${LOGFILE:-}" ] || return 0

  perl -pe 's/\e\[[0-9;]*[A-Za-z]//g' "$LOGFILE" \
    | rg -i 'user (asked|wanted|prefers|requested)|prefer(s|red)?|smaller patch|before broader cleanup|follow[- ]?up|add tests|tests after|stable preference|durable preference' \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    | awk 'length($0) <= 220 && !seen[$0]++' \
    | head -n 12
}

rebuild_auto_learnings() {
  local candidate_lines area_lines

  candidate_lines="$(
    json_field type < "$SIGNALS_FILE" >/dev/null 2>&1 || true
    awk -F'"' '/"type":"candidate_learning"/ { for (i = 1; i <= NF; i++) if ($i == "summary") print $(i + 2) }' "$SIGNALS_FILE" \
      | sort \
      | uniq -c \
      | sort -nr \
      | head -n 12
  )"

  area_lines="$(
    awk -F'"' '/"type":"path_activity"/ { for (i = 1; i <= NF; i++) if ($i == "summary") print $(i + 2) }' "$SIGNALS_FILE" \
      | sort \
      | uniq -c \
      | sort -nr \
      | head -n 12
  )"

  {
    echo "# Splinter Auto Learnings"
    echo
    echo "Generated from ingested turtle runs. Edit \`learnings.md\` for curated memory."
    echo
    echo "## Candidate Learnings"
    echo
    if [ -n "$candidate_lines" ]; then
      printf '%s\n' "$candidate_lines" | while read -r count summary; do
        [ -n "${summary:-}" ] || continue
        echo "- [$count] $(json_unescape "$summary")"
      done
    else
      echo "- No candidate learnings discovered yet."
    fi
    echo
    echo "## Frequently Touched Areas"
    echo
    if [ -n "$area_lines" ]; then
      printf '%s\n' "$area_lines" | while read -r count area; do
        [ -n "${area:-}" ] || continue
        echo "- [$count] $(json_unescape "$area")"
      done
    else
      echo "- No repeated path activity discovered yet."
    fi
  } > "$AUTO_FILE"
}

ingest_one_run() {
  local run_file="$1"
  local force_ingest="$2"
  local run_summary changed_areas

  load_run_file "$run_file"

  if [ "$force_ingest" = "0" ] && run_already_ingested "$run_file"; then
    return 0
  fi

  [ -n "${WORKTREE:-}" ] || die "Run file missing WORKTREE: $run_file"

  run_summary="$(summarize_run)"
  append_signal "run_summary" "run_file" "${RUN_ID:-}" "${TURTLE:-}" "${BRANCH:-}" "${REPO:-}" "$run_summary" "medium"

  changed_areas="$(collect_changed_areas || true)"
  if [ -n "$changed_areas" ]; then
    printf '%s\n' "$changed_areas" | while IFS= read -r area; do
      [ -n "$area" ] || continue
      append_signal "path_activity" "git_diff" "${RUN_ID:-}" "${TURTLE:-}" "${BRANCH:-}" "${REPO:-}" "$area" "low"
    done
  fi

  extract_candidate_lines | while IFS= read -r line; do
    line="$(trim_line "$line")"
    [ -n "$line" ] || continue
    append_signal "candidate_learning" "session_log" "${RUN_ID:-}" "${TURTLE:-}" "${BRANCH:-}" "${REPO:-}" "$line" "low"
  done

  mark_run_ingested "$run_file"
}

collect_recent_signals() {
  local branch_name="$1"
  local turtle_name="$2"
  local keywords signal_lines

  keywords="$(branch_keywords "$branch_name" | paste -sd '|' -)"

  signal_lines="$(tail -n 200 "$SIGNALS_FILE" | reverse_lines)"
  if [ -n "$keywords" ]; then
    printf '%s\n' "$signal_lines" \
      | awk -v turtle_name="$turtle_name" -v keywords="$keywords" '
          BEGIN { count = 0 }
          /"type":"candidate_learning"/ || /"type":"run_summary"/ {
            line = $0
            turtle_match = (turtle_name != "" && line ~ "\"turtle\":\"" turtle_name "\"")
            keyword_match = (keywords != "" && tolower(line) ~ tolower(keywords))
            if (turtle_match || keyword_match) {
              print line
              count++
            }
            if (count >= 6) exit
          }
        '
  else
    printf '%s\n' "$signal_lines" \
      | awk -v turtle_name="$turtle_name" '
          BEGIN { count = 0 }
          /"type":"candidate_learning"/ || /"type":"run_summary"/ {
            line = $0
            turtle_match = (turtle_name != "" && line ~ "\"turtle\":\"" turtle_name "\"")
            if (turtle_match || turtle_name == "") {
              print line
              count++
            }
            if (count >= 6) exit
          }
        '
  fi
}

cmd_init() {
  ensure_dirs
  echo "Initialized Splinter at $SPLINTER_HOME"
  echo "Signals: $SIGNALS_FILE"
  echo "Curated learnings: $LEARNINGS_FILE"
  echo "Generated learnings: $AUTO_FILE"
}

cmd_ingest() {
  local run_file="" force_ingest="0"

  ensure_dirs

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --run-file)
        shift
        run_file="${1:-}"
        ;;
      --force)
        force_ingest="1"
        ;;
      *)
        die "Unknown argument for ingest: $1"
        ;;
    esac
    shift || true
  done

  if [ -n "$run_file" ]; then
    ingest_one_run "$run_file" "$force_ingest"
  else
    find "$RUNS_HOME" -type f -name 'run.env' 2>/dev/null | sort | while IFS= read -r one_run; do
      ingest_one_run "$one_run" "$force_ingest"
    done
  fi

  rebuild_auto_learnings
  echo "Ingest complete."
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
  rebuild_auto_learnings

  {
    echo "# Splinter Brief"
    echo
    if [ -n "$turtle_name" ] || [ -n "$branch_name" ]; then
      echo "- Turtle: ${turtle_name:-unknown}"
      echo "- Branch: ${branch_name:-unknown}"
      echo
    fi
    echo "## Curated Learnings"
    echo
    sed '1d' "$LEARNINGS_FILE"
    echo
    echo "## Auto Learnings"
    echo
    sed '1d' "$AUTO_FILE"
    echo
    echo "## Relevant Recent Signals"
    echo
    if [ -s "$SIGNALS_FILE" ]; then
      collect_recent_signals "$branch_name" "$turtle_name" | while IFS= read -r line; do
        local summary type
        summary="$(printf '%s\n' "$line" | json_field summary)"
        type="$(printf '%s\n' "$line" | json_field type)"
        [ -n "$summary" ] || continue
        echo "- [$type] $(json_unescape "$summary")"
      done
    else
      echo "- No signals ingested yet."
    fi
  } > "$output_file"

  echo "$output_file"
}

cmd_learnings() {
  ensure_dirs
  echo "Curated learnings: $LEARNINGS_FILE"
  echo
  sed -n '1,220p' "$LEARNINGS_FILE"
  echo
  echo "Auto learnings: $AUTO_FILE"
  echo
  sed -n '1,220p' "$AUTO_FILE"
}

cmd_open() {
  ensure_dirs

  if command -v open >/dev/null 2>&1; then
    open "$LEARNINGS_FILE"
  elif [ -n "${EDITOR:-}" ]; then
    "$EDITOR" "$LEARNINGS_FILE"
  else
    vi "$LEARNINGS_FILE"
  fi
}

cmd_show() {
  ensure_dirs

  if [ ! -s "$SIGNALS_FILE" ]; then
    echo "No Splinter signals recorded yet."
    return 0
  fi

  tail -n 20 "$SIGNALS_FILE"
}

main() {
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    init) cmd_init "$@" ;;
    ingest) cmd_ingest "$@" ;;
    brief) cmd_brief "$@" ;;
    learnings) cmd_learnings "$@" ;;
    open) cmd_open "$@" ;;
    show) cmd_show "$@" ;;
    -h|--help|help|"") usage ;;
    *) die "Unknown command '$cmd'. Run: splinter help" ;;
  esac
}

main "$@"
