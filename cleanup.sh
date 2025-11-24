#!/bin/bash

# Usage: ./cleanup_do_tags.sh 14d
# Deletes TAGS older than the given age.
# DigitalOcean automatically cleans up manifests + blobs afterwards.

AGE=$1
DEBUG_MODE=${DEBUG_MODE:-false}
DRY_RUN=${DRY_RUN:-false}
SKIP_REPOSITORIES=${SKIP_REPOSITORIES:-""}

if [[ "$DEBUG_MODE" == "true" ]]; then
  set -x
fi

IFS=',' read -r -a EXEMPTED <<< "$SKIP_REPOSITORIES"

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

THRESHOLD_SECS=$(( $(date +%s) - AGE_SECONDS ))
THRESHOLD_DATE=$(date -d "@$THRESHOLD_SECS" +%Y-%m-%dT%H:%M:%SZ)

echo "🧹 Cleaning TAGS older than: $THRESHOLD_DATE"
echo "DRY_RUN: $DRY_RUN"
echo ""

# --- Ensure doctl is authenticated ---
if ! command -v doctl &> /dev/null; then
  echo "❌ Error: doctl not installed."
  exit 1
fi
if ! doctl registry validate >/dev/null 2>&1; then
  echo "❌ Error: doctl not authenticated. Run: doctl registry login"
  exit 1
fi

# --- List all repositories ---
REPOS=$(doctl registry repository list --format Name --no-header)

for repo in $REPOS; do
  # Skip repositories in EXEMPTED
  if [[ " ${EXEMPTED[@]} " =~ " $repo " ]]; then
    echo "⚙️  Skipping exempted repo: $repo"
    continue
  fi

  echo "📦 Processing repository: $repo"

  # Fetch tags with timestamps
  TAGS_JSON=$(doctl registry repository list-tags "$repo" --output json)
  TAG_COUNT=$(echo "$TAGS_JSON" | jq length)

  if [[ "$TAG_COUNT" -eq 0 ]]; then
    echo "ℹ️  No tags found."
    echo ""
    continue
  fi

  # Iterate through tags
  echo "$TAGS_JSON" | jq -c '.[]' | while read -r tag; do
    tag_name=$(echo "$tag" | jq -r '.tag')
    updated_at=$(echo "$tag" | jq -r '.updated_at')

    # Convert updated_at → seconds
    UPDATED_SECS=$(date -d "$updated_at" +%s)

    if (( UPDATED_SECS < THRESHOLD_SECS )); then
      echo "🗑️  DELETE: $repo:$tag_name (updated $updated_at)"
      if [[ "$DRY_RUN" != "true" ]]; then
        doctl registry repository delete-tag "$repo" "$tag_name" --force || \
          echo "⚠️  Warning: failed to delete tag: $tag_name"
      fi
    else
      echo "✅ KEEP:   $repo:$tag_name (updated $updated_at)"
    fi
  done

  echo ""
done

echo "✅ Cleanup complete."