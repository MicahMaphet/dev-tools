#!/usr/bin/env bash
#
# contributor-lines.sh
#
# Walks a git repository's CURRENT files (respecting .gitignore) and reports
# how many lines of code each contributor "owns" right now, using
# `git blame` so that lines are credited to whoever last touched them,
# not just whoever originally wrote the file.
#
# Usage:
#   ./contributor-lines.sh [path-to-repo] [-e]
#
#   path-to-repo   Defaults to the current directory.
#   -e             Group by author email instead of author name.
#
# Requires: git, awk, file. Must be run against a git repository
# (it relies on git itself to interpret .gitignore correctly).

set -euo pipefail

usage() {
  echo "Usage: $0 [path-to-repo] [-e]" >&2
  echo "  -e   group by author email instead of name" >&2
  exit 1
}

REPO_DIR="."
BY_EMAIL=0

for arg in "$@"; do
  case "$arg" in
    -e) BY_EMAIL=1 ;;
    -h|--help) usage ;;
    -*) usage ;;
    *) REPO_DIR="$arg" ;;
  esac
done

cd "$REPO_DIR" 2>/dev/null || { echo "Error: no such directory '$REPO_DIR'" >&2; exit 1; }

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: '$REPO_DIR' is not a git repository (needed to honor .gitignore)." >&2
  exit 1
fi
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

TMP_COUNTS="$(mktemp)"
trap 'rm -f "$TMP_COUNTS"' EXIT

if [ "$BY_EMAIL" -eq 1 ]; then
  BLAME_FIELD="author-mail"
else
  BLAME_FIELD="author"
fi

# All files git considers "real" right now: tracked files, plus untracked
# files that are NOT ignored. This is exactly what .gitignore should exclude.
mapfile -d '' FILES < <(git ls-files -z --cached --others --exclude-standard)

FILE_COUNT=0
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue

  # Skip binary files (images, archives, compiled artifacts, etc.)
  case "$(file --brief --mime-encoding -- "$f" 2>/dev/null)" in
    binary) continue ;;
  esac

  FILE_COUNT=$((FILE_COUNT + 1))

  if git ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
    # Tracked file -> blame it. --line-porcelain repeats full commit info
    # (including author/author-mail) before every content line, so this
    # correctly re-associates each line even across many small commits.
    git blame --line-porcelain -- "$f" 2>/dev/null | awk -v field="$BLAME_FIELD" '
      $0 ~ "^" field " " { sub("^" field " ", ""); who = $0 }
      /^\t/ { print who }
    ' >> "$TMP_COUNTS"
  else
    # Untracked-but-not-ignored file (e.g. brand new, not yet `git add`ed).
    wc -l < "$f" | awk '{ for (i=0;i<$1;i++) print "(uncommitted, untracked)" }' >> "$TMP_COUNTS"
  fi
done

TOTAL=$(wc -l < "$TMP_COUNTS" | tr -d ' ')

if [ "$TOTAL" -eq 0 ]; then
  echo "No lines found across $FILE_COUNT file(s)."
  exit 0
fi

echo "Contributor breakdown for $REPO_ROOT"
echo "($FILE_COUNT files scanned, .gitignore respected)"
echo

sort "$TMP_COUNTS" | uniq -c | sort -rn | while read -r count who; do
  pct=$(awk -v c="$count" -v t="$TOTAL" 'BEGIN{printf "%.2f", (c/t)*100}')
  printf "%-8s %6.2f%%   %s\n" "$count" "$pct" "$who"
done

echo
echo "Total: $TOTAL lines"
