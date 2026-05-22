#!/usr/bin/env bash
# integrate-component-with-bundle.sh — Adds component to ODH/RHOAI build config bundle
#
# Usage:
#   ./scripts/integrate-component-with-bundle.sh <jira-url> [--existing-pr-url <url>]
#
# Required env vars:
#   GITHUB_USER, GITHUB_TOKEN
#   JIRA_USER_EMAIL, JIRA_API_TOKEN
#
# Optional env vars:
#   BUILD_CONFIG_REPO_URL (default: derived from product_context)
#   JIRA_SERVER (default: https://redhat.atlassian.net)

set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parse inputs ──────────────────────────────────────────────────────────────

JIRA_URL=""
EXISTING_PR_URL=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --existing-pr-url)
      EXISTING_PR_URL="$2"
      shift 2
      ;;
    *)
      if [[ -z "$JIRA_URL" ]]; then
        JIRA_URL="$1"
      else
        echo "ERROR: Unexpected argument '$1'"
        exit 1
      fi
      shift
      ;;
  esac
done

[[ -z "$JIRA_URL" ]] && {
  echo "Usage: $0 <jira-url> [--existing-pr-url <url>]"
  exit 1
}

# Idempotency fast-path
if [[ -n "$EXISTING_PR_URL" ]]; then
  echo "PR already raised: $EXISTING_PR_URL"
  exit 0
fi

# Parse Jira URL
eval "$(bash "$SCRIPTS_DIR/parse_jira_url.sh" "$JIRA_URL")"
echo "JIRA_URL : $JIRA_URL"
echo "JIRA_ID  : $JIRA_ID"

# ── Check prerequisites ───────────────────────────────────────────────────────

bash "$SCRIPTS_DIR/check_prerequisites.sh" --env "GITHUB_USER GITHUB_TOKEN JIRA_USER_EMAIL JIRA_API_TOKEN" --tools "uv git gh"

# ── Set up working directory ──────────────────────────────────────────────────

eval "$(bash "$SCRIPTS_DIR/init_workdir.sh" --jira-url "$JIRA_URL")"
echo "Working directory: $WORKDIR"

# ── Get component YAML ────────────────────────────────────────────────────────

if [[ ! -f "$WORKDIR/component_onboarding_details.yaml" ]]; then
  cd "$WORKDIR"
  uv run --script "$SCRIPTS_DIR/download_jira_attachment.py" \
    "$JIRA_URL" component_onboarding_details.yaml || {
    echo "ERROR: Could not download 'component_onboarding_details.yaml'."
    echo "  Ensure the attachment exists on the Jira issue."
    exit 1
  }
fi

if [[ ! -f "$WORKDIR/component_onboarding_details.json" ]]; then
  cd "$WORKDIR"
  uv run --script "$SCRIPTS_DIR/fetch_jira_details.py" "$JIRA_URL" || {
    echo "ERROR: Could not fetch Jira issue details."
    exit 1
  }
fi

# ── Parse YAML and derive variables ───────────────────────────────────────────

YAML_FILE="$WORKDIR/component_onboarding_details.yaml"

eval "$(bash "$SCRIPTS_DIR/parse_component_details.sh" \
  --workdir "$WORKDIR" \
  --jira-id "$JIRA_ID" \
  --scripts-dir "$SCRIPTS_DIR")"

echo "COMPONENT_NAME   : $COMPONENT_NAME"
echo "PRODUCT_CONTEXT  : $PRODUCT_CONTEXT"
echo "REPO_URL         : $REPO_URL"
echo "REPO_BRANCH      : $REPO_BRANCH"

# ── Resolve build config repository URL ───────────────────────────────────────

eval "$(bash "$SCRIPTS_DIR/resolve_bc_url.sh" \
  --product-context "$PRODUCT_CONTEXT" \
  ${BUILD_CONFIG_REPO_URL:+--override "$BUILD_CONFIG_REPO_URL"})"

echo "BC_URL  : $BC_URL"
echo "BC_PATH : $BC_PATH"

# ── Resolve bundle image reference ───────────────────────────────────────────

BUNDLE_IMAGE=$(bash "$SCRIPTS_DIR/resolve_bundle_image.sh" \
  --component-name "$COMPONENT_NAME" \
  --product-context "$PRODUCT_CONTEXT" \
  --quay-org "$QUAY_ORG" || echo "")

if [[ -z "$BUNDLE_IMAGE" ]]; then
  # Fallback to default pattern
  if [[ "$PRODUCT_CONTEXT" == "ODH" ]]; then
    BUNDLE_IMAGE="quay.io/opendatahub/${COMPONENT_NAME}:latest"
  else
    BUNDLE_IMAGE="quay.io/rhoai/${COMPONENT_NAME}:latest"
  fi
fi

echo "BUNDLE_IMAGE     : $BUNDLE_IMAGE"

# ── Set up GitHub playpen (fork + clone) ──────────────────────────────────────

cd "$WORKDIR"

PLAYPEN_OUTPUT=$(bash "$SCRIPTS_DIR/setup_github_playpen.sh" \
  --src-url "$BC_URL" \
  --dest-url "$BC_URL" \
  --src-branch main \
  --dest-branch "$JIRA_ID" \
  --sparse-files "bundle/Dockerfile") || {
  echo "ERROR: Playpen setup failed. See details above."
  echo "  Check GITHUB_TOKEN has 'repo' scope and fork/clone access."
  exit 1
}

CLONE_DIR=$(echo "$PLAYPEN_OUTPUT" | head -1)
DEST_BRANCH=$(echo "$PLAYPEN_OUTPUT" | tail -1)

echo "Clone directory: $CLONE_DIR"
echo "Branch: $DEST_BRANCH"

# ── Add bundle Dockerfile entries ─────────────────────────────────────────────

BUNDLE_DOCKERFILE="$CLONE_DIR/bundle/Dockerfile"
[[ -f "$BUNDLE_DOCKERFILE" ]] || {
  echo "ERROR: bundle/Dockerfile not found in $CLONE_DIR."
  echo "  Verify BC_URL points to the correct build config repository."
  exit 1
}

# Check if component already referenced in Dockerfile
if grep -qF "$COMPONENT_NAME" "$BUNDLE_DOCKERFILE"; then
  echo "'$COMPONENT_NAME' already referenced in bundle/Dockerfile — skipping edit."
else
  # Add LABEL entries for the component
  cat >> "$BUNDLE_DOCKERFILE" <<EOF

# ${COMPONENT_NAME}
LABEL com.redhat.component.${COMPONENT_NAME}.image="${BUNDLE_IMAGE}"
LABEL com.redhat.component.${COMPONENT_NAME}.source.git.url="${REPO_URL}"
LABEL com.redhat.component.${COMPONENT_NAME}.source.git.ref="${REPO_BRANCH}"
EOF

  echo "Bundle Dockerfile entries added for '$COMPONENT_NAME'."
fi

# ── Validate git labels (optional Python script) ──────────────────────────────

# If update_bundle_dockerfile_git_labels.py exists, use it for validation
if [[ -f "$SCRIPTS_DIR/update_bundle_dockerfile_git_labels.py" ]]; then
  python3 "$SCRIPTS_DIR/update_bundle_dockerfile_git_labels.py" \
    "$BUNDLE_DOCKERFILE" \
    --validate || echo "WARN: Git label validation script not available or failed."
fi

# ── Commit and push ───────────────────────────────────────────────────────────

bash "$SCRIPTS_DIR/git_commit_push.sh" \
  --clone-dir "$CLONE_DIR" \
  --files "bundle/Dockerfile" \
  --message "Add ${COMPONENT_NAME} to bundle manifest

Adds bundle Dockerfile entries for ${COMPONENT_NAME}.

Component: ${COMPONENT_NAME}
Image: ${BUNDLE_IMAGE}
Source: ${REPO_URL}@${REPO_BRANCH}

Related: ${JIRA_ID}" \
  --branch "$DEST_BRANCH" || {
  echo "ERROR: Could not push branch '$DEST_BRANCH'. See details above."
  exit 1
}

# ── Raise PR ──────────────────────────────────────────────────────────────────

PR_URL=$(uv run --script "$SCRIPTS_DIR/raise_github_pr.py" \
  --src-url "$BC_URL" \
  --src-branch "$DEST_BRANCH" \
  --dest-url "$BC_URL" \
  --dest-branch main \
  --title "Add ${COMPONENT_NAME} to bundle manifest" \
  --description "Adds bundle Dockerfile entries for ${COMPONENT_NAME}.

## Component details

| Field | Value |
|-------|-------|
| \`component_name\` | \`${COMPONENT_NAME}\` |
| \`bundle_image\` | \`${BUNDLE_IMAGE}\` |
| \`source_url\` | \`${REPO_URL}\` |
| \`source_ref\` | \`${REPO_BRANCH}\` |
| \`product_context\` | \`${PRODUCT_CONTEXT}\` |

**File changed:** \`bundle/Dockerfile\`
**Jira:** $JIRA_URL") || {
  echo "ERROR: Could not create PR."
  exit 1
}

echo "PR raised: $PR_URL"

# ── Jira updates ──────────────────────────────────────────────────────────────

uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
  --add-label "bundle-integration-pr-raised" \
  --comment "[step:bundle_integration] GitHub PR raised to integrate '${COMPONENT_NAME}' with the build config bundle.

PR URL: $PR_URL

File changed: bundle/Dockerfile
Bundle image: ${BUNDLE_IMAGE}
Source: ${REPO_URL}@${REPO_BRANCH}

The bundle integration will be active once the PR is merged."

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "Done."
echo ""
echo "  bundle/Dockerfile        — ${COMPONENT_NAME} entries added"
echo "  GitHub PR                : $PR_URL"
echo "  Jira                     : ${JIRA_ID} — label: bundle-integration-pr-raised"
