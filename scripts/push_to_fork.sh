#!/usr/bin/env zsh
# Push current workspace to your GitHub fork and create a branch
# Usage: ./scripts/push_to_fork.sh <your-fork-ssh-or-https-url> [branch-name]
# Example: ./scripts/push_to_fork.sh git@github.com:michaelgabbard/MilkDrop3.git macos/metal-port

set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <your-fork-ssh-or-https-url> [branch-name]"
  exit 1
fi

FORK_URL="$1"
BRANCH_NAME="${2:-macos/metal-port}"

# Ensure we're in the repo root
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Add remote named 'fork' if it doesn't exist
if git remote get-url fork >/dev/null 2>&1; then
  echo "Remote 'fork' already exists: $(git remote get-url fork)"
else
  git remote add fork "$FORK_URL"
  echo "Added remote 'fork' -> $FORK_URL"
fi

# Stage all changes
git add -A

# Default commit message
DEFAULT_MSG="macOS Metal port initial scaffold"

read -r -p "Commit message (press Enter for default): " COMMIT_MSG
COMMIT_MSG="${COMMIT_MSG:-$DEFAULT_MSG}"

# Commit (if there are staged changes)
if git diff --cached --quiet; then
  echo "No staged changes to commit. Skipping commit."
else
  git commit -m "$COMMIT_MSG"
fi

# Push current HEAD to the fork under the chosen branch name
git push -u fork "HEAD:$BRANCH_NAME"

echo "Pushed to fork remote 'fork' on branch '$BRANCH_NAME'."

echo "Open a Pull Request from your fork/branch to the upstream repository when ready."
