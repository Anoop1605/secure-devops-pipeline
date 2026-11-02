#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Detect the repository from git remote or gh context
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

if [ -z "$REPO" ]; then
  echo "Error: Could not resolve repository. Ensure you are inside the git repo or logged into gh."
  exit 1
fi

echo "Target repository: $REPO"
echo "Fetching and deleting all workflow runs across all branches..."

while true; do
  # Fetch up to 100 run IDs in the current page
  RUN_IDS=$(gh api "repos/$REPO/actions/runs?per_page=100" --jq '.workflow_runs[].id')

  # If no runs are returned, cleanup is complete
  if [ -z "$RUN_IDS" ]; then
    echo "No workflow runs found. All runs deleted successfully!"
    break
  fi

  # Delete each run ID found in this batch
  for ID in $RUN_IDS; do
    echo "Deleting run ID: $ID"
    gh api -X DELETE "repos/$REPO/actions/runs/$ID" > /dev/null
  done
done