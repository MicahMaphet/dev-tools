#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 [branch=HEAD] [chunk_size=10] [mode=touch|diff]

Outputs which files changed in each window of N commits on a branch.

Modes:
  touch  (default) - list unique files touched by commits in each window of N commits
                    (uses 'git show' per commit, so it captures files that were changed
                     and possibly reverted within the window).
  diff   - use 'git diff --name-only old_commit new_commit' between boundary commits
           (shows the net tree differences).

Examples:
  $0                 # HEAD, 10-commit windows, 'touch' mode
  $0 main 20 diff    # main, 20-commit windows, 'diff' mode
EOF
}

branch="${1:-HEAD}"
chunk_size="${2:-10}"
mode="${3:-touch}"

# basic checks
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "Not a git repository (run this inside a repo)."
  exit 1
fi

if ! [[ "$chunk_size" =~ ^[1-9][0-9]*$ ]]; then
  echo "chunk_size must be a positive integer."
  usage
  exit 1
fi

if [[ "$mode" != "touch" && "$mode" != "diff" ]]; then
  echo "mode must be 'touch' or 'diff'."
  usage
  exit 1
fi

# Get commits oldest -> newest for the specified branch/ref
mapfile -t commits < <(git rev-list --reverse "$branch")
num_commits=${#commits[@]}

if [ "$num_commits" -eq 0 ]; then
  echo "No commits found on '$branch'."
  exit 0
fi

chunk_count=$(( (num_commits + chunk_size - 1) / chunk_size ))

for (( i=0; i<chunk_count; i++ )); do
  if [ "$i" -eq 0 ]; then
    start_idx=0
  else
    start_idx=$(( i * chunk_size - 1 ))
  fi

  end_idx=$(( (i + 1) * chunk_size - 1 ))
  if [ "$end_idx" -gt $(( num_commits - 1 )) ]; then
    end_idx=$(( num_commits - 1 ))
  fi

  start_sha=${commits[$start_idx]}
  end_sha=${commits[$end_idx]}
  start_short=$(git rev-parse --short "$start_sha")
  end_short=$(git rev-parse --short "$end_sha")

  printf "\n=== commits %d..%d (%s -> %s) ===\n" $((start_idx+1)) $((end_idx+1)) "$start_short" "$end_short"

  if [ "$mode" = "diff" ]; then
    # Net tree diff between the two boundary commits
    git diff --name-only "$start_sha" "$end_sha" | sed '/^$/d' | sort -u || true
  else
    # 'touch' mode: list files touched by the commits inside this window.
    # For the first window include commits 1..N; for subsequent windows include commits (boundary+1)..N
    if [ "$i" -eq 0 ]; then
      range_start=0
    else
      range_start=$(( start_idx + 1 ))
    fi

    range_count=$(( end_idx - range_start + 1 ))
    if [ $range_count -le 0 ]; then
      echo "(no commits in this range)"
      continue
    fi

    chunk_hashes=( "${commits[@]:$range_start:$range_count}" )
    git show --pretty=format: --name-only --no-patch "${chunk_hashes[@]}" | sed '/^$/d' | sort -u || true
  fi
done

# end script
