#!/bin/bash

# Usage: ./cleanup_do_tags.sh 14d
# Deletes TAGS older than the given age.
# If a repository has NO valid tags (only manifests/digests),
# it will delete old manifest digests instead.

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

echo "🧹 Cleaning items older than: $THRESHOLD_DATE"
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

# --- Get repo list from JSON to avoid headers/columns/junk ---
REPOS=$(doctl registry repository list --output json 2>/dev/null | jq -r '.[].name')

for repo in $REPOS; do
  # Extra safety: skip empty / weird entries
  if [[ -z "$repo" || "$repo" == "Name" ]]; then
    echo "⚠️  Skipping invalid repo entry: '$repo'"
    continue
  fi

  # Skip repositories in EXEMPTED
  if [[ " ${EXEMPTED[@]} " =~ " $repo " ]]; then
    echo "⚙️  Skipping exempted repo: $repo"
    continue
  fi

  echo "📦 Processing repository: $repo"

  # ---- TAG HANDLING ----
  TAGS_JSON=$(doctl registry repository list-tags "$repo" --output json 2>/dev/null || echo '[]')

  # Compute VALID_TAG_COUNT safely (no jq error spam)
  if ! VALID_TAG_COUNT=$(echo "$TAGS_JSON" | jq -r '[ .[] | select(.tag != null and .tag != "") ] | length' 2>/dev/null); then
    echo "⚠️  Failed to parse tags JSON for $repo. Treating as tagless."
    VALID_TAG_COUNT=0
  fi

  # ==========================================
  # CASE 1: REPO HAS REAL TAGS → CLEAN TAGS
  # ==========================================
  if [[ "$VALID_TAG_COUNT" -gt 0 ]]; then
    echo "🔹 $repo has $VALID_TAG_COUNT valid tag(s). Cleaning tags..."

    echo "$TAGS_JSON" \
      | jq -c '.[] | select(.tag != null and .tag != "")' \
      | while read -r tag; do
          tag_name=$(echo "$tag" | jq -r '.tag')
          updated_at=$(echo "$tag" | jq -r '.updated_at')

          # updated_at might be empty/null in weird cases
          if [[ -z "$updated_at" || "$updated_at" == "null" ]]; then
            echo "⚠️  Skipping tag with missing updated_at: $repo:$tag_name"
            continue
          fi

          UPDATED_SECS=$(date -d "$updated_at" +%s 2>/dev/null || echo 0)

          if (( UPDATED_SECS < THRESHOLD_SECS )); then
            echo "🗑️  DELETE TAG: $repo:$tag_name (updated $updated_at)"
            if [[ "$DRY_RUN" != "true" ]]; then
              doctl registry repository delete-tag "$repo" "$tag_name" --force || \
                echo "⚠️ Failed to delete tag: $tag_name"
            fi
          else
            echo "✅ KEEP TAG:   $repo:$tag_name (updated $updated_at)"
          fi
        done

    echo ""
    continue
  fi

  # ==========================================
  # CASE 2: REPO HAS NO VALID TAGS → CLEAN MANIFESTS
  # ==========================================
  echo "ℹ️  $repo has NO VALID TAGS — cleaning manifests..."

  MANIFESTS_JSON=$(doctl registry repository list-manifests "$repo" --output json 2>/dev/null || echo '[]')

  # Make sure it's a JSON array before iterating
  if ! echo "$MANIFESTS_JSON" | jq -e 'type=="array"' >/dev/null 2>&1; then
    echo "⚠️  Invalid manifest JSON for $repo. Skipping."
    echo ""
    continue
  fi

  echo "$MANIFESTS_JSON" | jq -c '.[]' | while read -r manifest; do
    digest=$(echo "$manifest" | jq -r '.digest')
    updated_at=$(echo "$manifest" | jq -r '.updated_at')

    if [[ -z "$digest" || "$digest" == "null" ]]; then
      echo "⚠️  Skipping manifest with no digest in $repo"
      continue
    fi

    if [[ -z "$updated_at" || "$updated_at" == "null" ]]; then
      echo "⚠️  Skipping $repo@$digest (missing updated_at)"
      continue
    fi

    UPDATED_SECS=$(date -d "$updated_at" +%s 2>/dev/null || echo 0)

    if (( UPDATED_SECS < THRESHOLD_SECS )); then
      echo "🗑️  DELETE DIGEST: $repo@$digest (updated $updated_at)"
      if [[ "$DRY_RUN" != "true" ]]; then
        doctl registry repository delete-manifest "$repo" "$digest" --force || \
          echo "⚠️ Failed to delete manifest: $digest"
      fi
    else
      echo "✅ KEEP DIGEST:   $repo@$digest (updated $updated_at)"
    fi
  done

  echo ""

done

echo "✅ Cleanup complete."