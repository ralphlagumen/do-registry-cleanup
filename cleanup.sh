#!/bin/bash

# Usage: ./cleanup_docr_images.sh <age>
# Example: ./cleanup_docr_images.sh 14d

AGE=$1
DEBUG_MODE=${DEBUG_MODE:-false}
MOCK_MODE=${MOCK_MODE:-false}
SKIP_REPOSITORIES=${SKIP_REPOSITORIES:-""}

if [[ "$DEBUG_MODE" == "true" ]]; then
  set -x
fi

IFS=',' read -r -a exempted <<< "$SKIP_REPOSITORIES"

# --- Prerequisites ---
if [[ "$MOCK_MODE" != "true" ]]; then
  if ! command -v doctl &> /dev/null; then
    echo "❌ Error: doctl not installed. Install before running this script."
    exit 1
  fi
  if ! doctl auth init &>/dev/null; then
    echo "❌ Error: doctl not authenticated. Run 'doctl registry login' first."
    exit 1
  fi
fi

# --- Validate AGE ---
if [[ -z "$AGE" ]]; then
  echo "❌ Error: Age parameter is required (e.g. 7d, 2w, 1m)"
  exit 1
elif [[ ! "$AGE" =~ ^[0-9]+[dwm]$ ]]; then
  echo "❌ Error: Invalid age format. Use <number>d, <number>w, or <number>m."
  exit 1
fi

# --- Convert AGE to seconds ---
case "$AGE" in
  *d) AGE_SECONDS=$(( ${AGE%d} * 86400 )) ;;
  *w) AGE_SECONDS=$(( ${AGE%w} * 604800 )) ;;
  *m) AGE_SECONDS=$(( ${AGE%m} * 2592000 )) ;;
esac

THRESHOLD_DATE=$(date -d "@$(( $(date +%s) - AGE_SECONDS ))" +%Y-%m-%dT%H:%M:%SZ)
echo "🧹 Cleaning images older than $THRESHOLD_DATE"

# --- Get repositories ---
if [[ "$MOCK_MODE" == "true" ]]; then
  echo "🧪 MOCK MODE ENABLED"
  repositories=("mock-repo")
  manifests="digest1 application/vnd.docker.distribution.manifest.list.v2+json 2024-01-01T12:00:00Z
digest2 application/vnd.docker.distribution.manifest.v2+json 2024-10-10T12:00:00Z"
else
  repositories=$(doctl registry repository list --format Name --no-header)
fi

# --- Iterate repositories ---
for repo in $repositories; do
  if [[ " ${exempted[@]} " =~ " $repo " ]]; then
    echo "⚙️  Skipping exempted repository: $repo"
    continue
  fi

  echo "📦 Processing repository: $repo"

  if [[ "$MOCK_MODE" == "true" ]]; then
    manifest_list="$manifests"
  else
    manifest_list=$(doctl registry repository list-manifests $repo \
      --format Digest,MediaType,UpdatedAt --no-header)
  fi

  if [[ -z "$manifest_list" ]]; then
    echo "ℹ️  No manifests found in $repo"
    continue
  fi

  while IFS= read -r image; do
    digest=$(echo "$image" | awk '{print $1}')
    mediatype=$(echo "$image" | awk '{print $2}')
    updated_at=$(echo "$image" | awk '{print $3}')

    # Only delete parent manifest lists
    if [[ "$mediatype" != "application/vnd.docker.distribution.manifest.list.v2+json" ]]; then
      echo "⏭️  Skipping child manifest $digest ($mediatype)"
      continue
    fi

    if [[ "$updated_at" < "$THRESHOLD_DATE" ]]; then
      echo "🗑️  Deleting parent manifest $digest from $repo (updated at $updated_at)"
      if [[ "$MOCK_MODE" != "true" ]]; then
        doctl registry repository delete-manifest $repo $digest --force || \
          echo "⚠️  Warning: Failed to delete $digest from $repo"
      else
        echo "🧪 MOCK: Would delete $digest from $repo"
      fi
    else
      echo "✅ Keeping $digest (updated at $updated_at)"
    fi
  done <<< "$manifest_list"

  echo ""
done

echo "✅ Cleanup complete."