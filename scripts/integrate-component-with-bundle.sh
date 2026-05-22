#!/usr/bin/env bash
# integrate-component-with-bundle.sh — Add component to build-config bundle
#
# Usage:
#   ./scripts/integrate-component-with-bundle.sh --jira-url <url> [--existing-pr-url <url>]
#
# Required env vars:
#   GITHUB_USER, GITHUB_TOKEN, JIRA_USER_EMAIL, JIRA_API_TOKEN
#
# Optional:
#   BUILD_CONFIG_REPO_URL — override target build-config repo

set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parse inputs ──────────────
JIRA_URL=""
JIRA_ID=""
EXISTING_PR_URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --jira-url)        JIRA_URL="$2"; shift 2 ;;
    --existing-pr-url) EXISTING_PR_URL="$2"; shift 2 ;;
    --workdir)         WORKDIR="$2"; shift 2 ;;
    *)
      if [[ -z "$JIRA_URL" && "$1" == *"/browse/"* ]]; then
        JIRA_URL="$1"; shift
      else
        echo "Unknown argument: $1" >&2; exit 1
      fi
      ;;
  esac
done

if [[ -n "$EXISTING_PR_URL" ]]; then
  echo "PR already raised: $EXISTING_PR_URL"
  exit 0
fi

eval "$(bash "$SCRIPTS_DIR/parse_jira_url.sh" "${JIRA_URL:-}")"
[[ -z "$JIRA_URL" ]] && {
  echo "ERROR: Jira URL is required." >&2; exit 1
}

echo "BUILD_CONFIG_REPO_URL : ${BUILD_CONFIG_REPO_URL:-(not set, will derive from product_context)}"

# ── Check prerequisites ──────
bash "$SCRIPTS_DIR/check_prerequisites.sh" \
  --env "GITHUB_USER GITHUB_TOKEN JIRA_USER_EMAIL JIRA_API_TOKEN" \
  --tools "uv git"

# ── Set up working directory ──
eval "$(bash "$SCRIPTS_DIR/init_workdir.sh" --jira-url "$JIRA_URL")"
echo "Working directory: $WORKDIR"

# ── Fetch Jira and component YAML ──
if [[ ! -f "$WORKDIR/component_onboarding_details.json" ]]; then
  cd "$WORKDIR"
  uv run --script "$SCRIPTS_DIR/fetch_jira_details.py" "$JIRA_URL" || {
    echo "ERROR: Could not fetch Jira details." >&2; exit 1
  }
fi

if [[ ! -f "$WORKDIR/component_onboarding_details.yaml" ]]; then
  cd "$WORKDIR"
  uv run --script "$SCRIPTS_DIR/download_jira_attachment.py" \
    "$JIRA_URL" component_onboarding_details.yaml || {
    echo "ERROR: Could not download YAML." >&2; exit 1
  }
fi

# ── Parse YAML ────────────────
eval "$(bash "$SCRIPTS_DIR/parse_component_details.sh" \
  --workdir    "$WORKDIR" \
  --jira-id    "$JIRA_ID" \
  --scripts-dir "$SCRIPTS_DIR")"

TARGET_RHOAI_VERSION=$(grep -m1 'target_rhoai_version:' "$WORKDIR/component_onboarding_details.yaml" | awk '{print $2}')

if [[ "${PRODUCT_CONTEXT^^}" == "RHOAI" && -z "$TARGET_RHOAI_VERSION" ]]; then
  echo "ERROR: Missing 'target_rhoai_version' (required for RHOAI)." >&2; exit 1
fi

# ── Derive computed variables ──
eval "$(bash "$SCRIPTS_DIR/resolve_bc_url.sh" \
  --product-context "$PRODUCT_CONTEXT" \
  ${BUILD_CONFIG_REPO_URL:+--override "$BUILD_CONFIG_REPO_URL"})"
echo "BC_URL : $BC_URL"
echo "BC_PATH: $BC_PATH"

if [[ "${PRODUCT_CONTEXT^^}" == "RHOAI" ]]; then
  eval "$(bash "$SCRIPTS_DIR/parse_rhoai_version.sh" --version "$TARGET_RHOAI_VERSION")"
  QUAY_REPO_NAME="${COMPONENT_NAME}-rhel9"
  SRC_BRANCH="${BRANCH_NAME:-main}"
else
  QUAY_REPO_NAME="$COMPONENT_NAME"
  SRC_BRANCH="main"
fi

eval "$(bash "$SCRIPTS_DIR/resolve_bundle_image.sh" \
  --component-name "$COMPONENT_NAME" \
  --quay-org       "$QUAY_ORG" \
  --quay-repo      "$QUAY_REPO_NAME")"

echo "RELATED_IMAGE_NAME : $RELATED_IMAGE_NAME"
echo "RELATED_IMAGE_VALUE: $RELATED_IMAGE_VALUE"

# ── Fast-path check ───────────
check_result=0
bash "$SCRIPTS_DIR/check_github_file.sh" \
  --repo-path "$BC_PATH" \
  --file-path "bundle/bundle-patch.yaml" \
  --ref       "$SRC_BRANCH" \
  --grep      "$RELATED_IMAGE_NAME" || check_result=$?

if [[ "$check_result" -eq 0 ]]; then
  echo "$RELATED_IMAGE_NAME already exists in bundle-patch.yaml."
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --add-label "bundle-changes-done" \
    --comment "'$COMPONENT_NAME' ($RELATED_IMAGE_NAME) already present in bundle/bundle-patch.yaml."
  exit 0
fi

# ── Set up playpen ────────────
if [[ "${PRODUCT_CONTEXT^^}" == "ODH" ]]; then
  SPARSE_FILES="bundle"
else
  SPARSE_FILES="bundle config"
fi

cd "$WORKDIR"
PLAYPEN_OUTPUT=$(bash "$SCRIPTS_DIR/setup_github_playpen.sh" \
  --src-url "$BC_URL" \
  --src-branch "$SRC_BRANCH" \
  --dest-branch "$JIRA_ID" \
  --sparse-files "$SPARSE_FILES") || {
  echo "ERROR: Clone or push failed." >&2; exit 1
}

CLONE_DIR=$(echo "$PLAYPEN_OUTPUT" | head -1)
DEST_BRANCH=$(echo "$PLAYPEN_OUTPUT" | tail -1)

# ── Update bundle/bundle-patch.yaml ──
[[ -f "$CLONE_DIR/bundle/bundle-patch.yaml" ]] || {
  echo "ERROR: bundle/bundle-patch.yaml not found." >&2; exit 1
}

if ! grep -qF "$RELATED_IMAGE_NAME" "$CLONE_DIR/bundle/bundle-patch.yaml"; then
  COMPONENT_ARG=""
  [[ "${PRODUCT_CONTEXT^^}" == "ODH" ]] && COMPONENT_ARG="--component $COMPONENT_NAME"

  uv run --script "$SCRIPTS_DIR/edit_yaml.py" append-array-entry \
    "$CLONE_DIR/bundle/bundle-patch.yaml" \
    --array-key "patch.relatedImages" \
    --name      "$RELATED_IMAGE_NAME" \
    --value     "$RELATED_IMAGE_VALUE" \
    $COMPONENT_ARG || {
    echo "ERROR: Could not append relatedImages entry." >&2; exit 1
  }

  grep -qF "$RELATED_IMAGE_NAME" "$CLONE_DIR/bundle/bundle-patch.yaml" || {
    echo "ERROR: $RELATED_IMAGE_NAME not found after insert." >&2; exit 1
  }
fi

# ── Update config/build-config.yaml (RHOAI only) ──
GIT_URL_LABEL=""
GIT_COMMIT_LABEL=""
if [[ "${PRODUCT_CONTEXT^^}" == "RHOAI" ]]; then
  [[ -f "$CLONE_DIR/config/build-config.yaml" ]] || {
    echo "ERROR: config/build-config.yaml not found." >&2; exit 1
  }

  if ! grep -q "rhoai/${COMPONENT_NAME}-rhel9:" "$CLONE_DIR/config/build-config.yaml" 2>/dev/null; then
    uv run --script "$SCRIPTS_DIR/edit_yaml.py" insert-simple-map-entry \
      "$CLONE_DIR/config/build-config.yaml" \
      --map-key "config.replacements.0.repo_mappings" \
      --key     "rhoai/${COMPONENT_NAME}-rhel9" \
      --value   "rhoai/${COMPONENT_NAME}-rhel9" || {
      echo "ERROR: Could not insert repo_mappings entry." >&2; exit 1
    }
  fi

  # Update bundle/Dockerfile
  DOCKERFILE="$CLONE_DIR/bundle/Dockerfile"
  [[ -f "$DOCKERFILE" ]] || {
    echo "ERROR: bundle/Dockerfile not found." >&2; exit 1
  }

  eval "$(uv run --script "$SCRIPTS_DIR/update_bundle_dockerfile_git_labels.py" \
    "$DOCKERFILE" --component-name "$COMPONENT_NAME")" || {
    echo "ERROR: Could not update bundle/Dockerfile." >&2; exit 1
  }
fi

# ── Commit and push ───────────
if [[ "${PRODUCT_CONTEXT^^}" == "ODH" ]]; then
  COMMIT_FILES="bundle/bundle-patch.yaml"
  COMMIT_MSG="Add $COMPONENT_NAME to bundle-patch.yaml"
else
  COMMIT_FILES="bundle/bundle-patch.yaml config/build-config.yaml bundle/Dockerfile"
  COMMIT_MSG="Add $COMPONENT_NAME to bundle-patch.yaml, build-config.yaml, and bundle/Dockerfile"
fi

bash "$SCRIPTS_DIR/git_commit_push.sh" \
  --clone-dir "$CLONE_DIR" \
  --files     "$COMMIT_FILES" \
  --message   "$COMMIT_MSG" \
  --branch    "$DEST_BRANCH" || {
  echo "ERROR: Could not commit or push." >&2; exit 1
}

# ── Raise PR (up to 3 attempts) ──
if [[ "${PRODUCT_CONTEXT^^}" == "ODH" ]]; then
  FILES_CHANGED="- \`bundle/bundle-patch.yaml\` — added \`$RELATED_IMAGE_NAME\`"
else
  FILES_CHANGED="- \`bundle/bundle-patch.yaml\` — added \`$RELATED_IMAGE_NAME\`
- \`config/build-config.yaml\` — added \`rhoai/${COMPONENT_NAME}-rhel9\` to repo_mappings
- \`bundle/Dockerfile\` — added ARG and LABEL entries for \`${COMPONENT_NAME}\`"
fi

PLACEHOLDER_NOTE=""
if [[ "${USING_PLACEHOLDER:-true}" == "true" ]]; then
  PLACEHOLDER_NOTE="> **NOTE:** The SHA256 digest is a placeholder. Update before merging."
fi

MAX_ATTEMPTS=3
for attempt in $(seq 1 $MAX_ATTEMPTS); do
  PR_URL=$(uv run --script "$SCRIPTS_DIR/raise_github_pr.py" \
    --src-url "$BC_URL" \
    --src-branch "$DEST_BRANCH" \
    --dest-url "$BC_URL" \
    --dest-branch "$SRC_BRANCH" \
    --title "Add $COMPONENT_NAME to bundle-patch.yaml" \
    --description "Adds '$COMPONENT_NAME' to the ${BC_PATH} bundle relatedImages.

Product context: $PRODUCT_CONTEXT
Jira: $JIRA_URL

${FILES_CHANGED}

${PLACEHOLDER_NOTE}" 2>&1) && break

  echo "PR creation attempt $attempt failed: $PR_URL"
  if [[ $attempt -eq $MAX_ATTEMPTS ]]; then
    echo "ERROR: Could not create PR after $MAX_ATTEMPTS attempts." >&2; exit 1
  fi
  sleep 5
done

# ── Jira update ───────────────
uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
  --add-label "bundle-pr-raised" \
  --comment "GitHub PR raised to add '$COMPONENT_NAME' to ${BC_PATH}.

PR URL: $PR_URL"

echo ""
echo "Done."
echo "  PR raised: $PR_URL"
