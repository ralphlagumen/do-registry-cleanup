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

if [[ -z "$AGE" ]]; then
  echo "❌ Error: Age parameter is required (e.g. 7d, 2w, 1m)"
  exit 1
elif [[ ! "$AGE" =~ ^[0-9]+[dwm]$ ]]; then
  echo "❌ Error: Invalid age format. Use <number>d, <number>w, or <number>m."
  exit 1
fi

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

if ! command -v doctl &> /dev/null; then
  echo "❌ Error: doctl not installed."
  exit 1
fi
if ! doctl registry validate >/dev/null 2>&1; then
  echo "❌ Error: doctl not authenticated. Run: doctl registry login"
  exit 1
fi

REPOS=$(doctl registry repository list --format Name --no-header)

for repo in $REPOS; do

  if [[ " ${EXEMPTED[@]} " =~ " $repo " ]]; then
    echo "⚙️  Skipping exempted repo: $repo"
    continue
  fi

  echo "📦 Processing repository: $repo"

  TAGS_JSON=$(doctl registry repository list-tags "$repo" --output json 2>/dev/null)

  # Validate JSON
  if ! echo "$TAGS_JSON" | jq empty 2>/dev/null; then
    echo "⚠️  Invalid tag JSON for $repo. Treating as tagless."
    VALID_TAG_COUNT=0
  else
    VALID_TAG_COUNT=$(echo "$TAGS_JSON" | jq '[ .[] | select(.tag != null and .tag != "") ] | length')
  fi

  if [[ "$VALID_TAG_COUNT" -gt 0 ]]; then
    echo "🔹 $repo has $VALID_TAG_COUNT valid tag(s). Cleaning tags..."

    echo "$TAGS_JSON" | jq -c '.[]' | while read -r tag; do

      # skip malformed
      if ! echo "$tag" | jq -e 'has("tag") and (.tag|type=="string") and (.tag != "")' >/dev/null; then
        continue
      fi

      tag_name=$(echo "$tag" | jq -r '.tag')
      updated_at=$(echo "$tag" | jq -r '.updated_at')
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


  echo "ℹ️  $repo has NO VALID TAGS — cleaning manifests..."

  MANIFESTS_JSON=$(doctl registry repository list-manifests "$repo" --output json)

  echo "$MANIFESTS_JSON" | jq -c '.[]' | while read -r manifest; do
    digest=$(echo "$manifest" | jq -r '.digest')
    updated_at=$(echo "$manifest" | jq -r '.updated_at')
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