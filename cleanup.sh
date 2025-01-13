#!/bin/bash

# Input: age threshold (e.g., 7d, 2w, 1m)
AGE=$1
DEBUG_MODE=${DEBUG_MODE:-false}
MOCK_MODE=${MOCK_MODE:-false}
SKIP_REPOSITORIES=${SKIP_REPOSITORIES:-""}

if [[ "$DEBUG_MODE" == "true" ]]; then
  set -x  # Enable debug mode
fi

# Convert skipped repositories to an array
IFS=',' read -r -a exempted <<< "$SKIP_REPOSITORIES"

# Check if `doctl` is installed (skip if MOCK_MODE is enabled)
if [[ "$MOCK_MODE" != "true" ]]; then
  if ! command -v doctl &> /dev/null; then
    echo "Error: doctl is not installed. Please install doctl before running this action."
    exit 1
  fi
fi

# Check if `doctl` is authenticated (skip if MOCK_MODE is enabled)
if [[ "$MOCK_MODE" != "true" ]]; then
  if ! doctl auth init &>/dev/null; then
    echo "Error: doctl is not authenticated. Please run 'doctl auth init' or 'doctl registry login' before using this action."
    exit 1
  fi
fi

# Validate the `AGE` input
if [[ -z "$AGE" ]]; then
  echo "Error: Age parameter is required (e.g., '7d' for 7 days, '2w' for 2 weeks, or '1m' for 1 month)."
  exit 1
elif [[ ! "$AGE" =~ ^[0-9]+[dwm]$ ]]; then
  echo "Error: Invalid age format. Use a valid format such as '7d' for 7 days, '2w' for 2 weeks, or '1m' for 1 month."
  exit 1
fi

# Convert `AGE` to seconds
AGE_SECONDS=0
case "$AGE" in
  *d) AGE_SECONDS=$(( ${AGE%d} * 86400 )) ;;     # Days
  *w) AGE_SECONDS=$(( ${AGE%w} * 604800 )) ;;    # Weeks
  *m) AGE_SECONDS=$(( ${AGE%m} * 2592000 )) ;;   # Months (approximate 30 days)
  *) echo "Error: Invalid age format. Use <number>d, <number>w, or <number>m."; exit 1 ;;
esac

# Calculate threshold date
THRESHOLD_DATE=$(date -d "@$(( $(date +%s) - AGE_SECONDS ))" +%Y-%m-%dT%H:%M:%SZ)

# Mock `doctl` outputs for testing if MOCK_MODE is enabled
if [[ "$MOCK_MODE" == "true" ]]; then
  echo "MOCK MODE: Skipping actual doctl commands."
  repositories=("mock-repo")
  images="digest1 2024-01-01T12:00:00Z
digest2 2024-10-10T12:00:00Z"
else
  # Retrieve actual repositories in the registry
  repositories=$(doctl registry repository list --format Name --no-header)
fi

# Process each repository
for repo in $repositories; do
  # Skip exempted repositories
  if [[ " ${exempted[@]} " =~ " $repo " ]]; then
    echo "Skipping repository: $repo"
    continue
  fi

  echo "Processing repository: $repo"
  if [[ "$MOCK_MODE" == "true" ]]; then
    # Use mock images data
    manifest_list="$images"
  else
    # Fetch actual image manifests
    manifest_list=$(doctl registry repository list-manifests $repo --format Digest,UpdatedAt --no-header)
  fi

  while IFS= read -r image; do
    digest=$(echo "$image" | awk '{print $1}')
    updated_at=$(echo "$image" | awk '{print $2"T"$3"Z"}')

    if [[ "$updated_at" < "$THRESHOLD_DATE" ]]; then
      echo "Deleting image $digest from $repo (updated at $updated_at)"
      # Mock deletion in MOCK_MODE
      if [[ "$MOCK_MODE" != "true" ]]; then
        doctl registry repository delete-manifest $repo $digest --force
      else
        echo "MOCK MODE: Would delete $digest from $repo."
      fi
    else
      echo "Keeping image $digest from $repo (updated at $updated_at)"
    fi
  done <<< "$manifest_list"
done

echo "Cleanup complete."