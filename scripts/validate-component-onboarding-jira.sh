#!/usr/bin/env bash
# validate-component-onboarding-jira.sh — Pre-flight validation for ODH/RHOAI
# component onboarding Jira tickets.
#
# Usage:
#   ./scripts/validate-component-onboarding-jira.sh <jira-url>
#
# Required env vars:
#   JIRA_USER_EMAIL  — your Atlassian account email
#   JIRA_API_TOKEN   — Atlassian Cloud API token
#
# Optional:
#   JIRA_SERVER — override default Jira server (default: https://redhat.atlassian.net)

set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_PATH="$(cd "$SCRIPTS_DIR/../playbooks/assets" && pwd)/component_onboarding_details.schema.json"

# ── Parse inputs ──────────────────────────────────────────────────────────────

JIRA_URL="${1:?Usage: $0 <jira-url>}"

if [[ "$JIRA_URL" != *"/browse/"* ]]; then
  # If only a key was given (e.g. RHOAIENG-1234), construct the full URL
  JIRA_SERVER="${JIRA_SERVER:-https://redhat.atlassian.net}"
  JIRA_URL="${JIRA_SERVER}/browse/${JIRA_URL}"
fi

JIRA_ID="${JIRA_URL##*/}"
echo "JIRA_URL : $JIRA_URL"
echo "JIRA_ID  : $JIRA_ID"

# ── Check prerequisites ──────────────────────────────────────────────────────

bash "$SCRIPTS_DIR/check_prerequisites.sh" \
  --env "JIRA_USER_EMAIL JIRA_API_TOKEN" \
  --tools "uv"

# ── Set up working directory ─────────────────────────────────────────────────

eval "$(bash "$SCRIPTS_DIR/init_workdir.sh" --jira-url "$JIRA_URL")"
YAML_PATH="${WORKDIR}/component_onboarding_details.yaml"
echo "Working directory: $WORKDIR"

# ── Step 3: Fetch Jira issue details ─────────────────────────────────────────

echo ""
echo "Fetching Jira issue details..."
if ! (cd "$WORKDIR" && uv run --script "$SCRIPTS_DIR/fetch_jira_details.py" "$JIRA_URL"); then
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --add-label "validation-failed" \
    --remove-label "validation-successful" \
    --comment "Validation failed at Step 1 (Fetch Jira Details).

Could not fetch issue details. This is typically caused by:
- An invalid or expired JIRA_API_TOKEN
- An incorrect issue key
- A network or permissions issue

Please check your credentials and issue key, then re-run /validate-component-onboarding-jira." 2>/dev/null || true

  echo "ERROR in Step 1 (Fetch Jira Details): Could not fetch Jira issue. Aborting."
  exit 1
fi

# ── Step 4: Download YAML attachment ─────────────────────────────────────────

echo "Downloading component_onboarding_details.yaml..."
if ! (cd "$WORKDIR" && uv run --script "$SCRIPTS_DIR/download_jira_attachment.py" "$JIRA_URL" component_onboarding_details.yaml); then
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --add-label "validation-failed" \
    --remove-label "validation-successful" \
    --comment "Validation failed at Step 2 (Download Attachment).

The required attachment 'component_onboarding_details.yaml' was not found on this issue.

Please attach a valid 'component_onboarding_details.yaml' file to this ticket and re-run /validate-component-onboarding-jira." 2>/dev/null || true

  echo "ERROR in Step 2 (Download Attachment): Attachment not found. Aborting."
  exit 1
fi

# ── Step 5: Validate YAML against schema ─────────────────────────────────────

echo "Validating YAML against schema..."
VALIDATION_ERRORS=""
if ! VALIDATION_ERRORS=$(uv run --script "$SCRIPTS_DIR/validate_yaml_schema.py" \
  "$YAML_PATH" "$SCHEMA_PATH" 2>&1); then

  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --add-label "validation-failed" \
    --remove-label "validation-successful" \
    --comment "Validation failed at Step 3 (Schema Validation).

The 'component_onboarding_details.yaml' attachment did not pass schema validation.

Errors found:
${VALIDATION_ERRORS}

Please fix the YAML, re-upload it as an attachment to this ticket, and re-run /validate-component-onboarding-jira." 2>/dev/null || true

  echo "$VALIDATION_ERRORS"
  echo "ERROR in Step 3 (Schema Validation): The YAML failed validation. See errors above. Aborting."
  exit 1
fi

echo "Schema validation passed."

# ── Step 5b: Cross-validate repo_branch for RHOAI ────────────────────────────

PRODUCT_CONTEXT=$(grep -m1 'product_context:' "$YAML_PATH" | awk '{print $2}')
REPO_BRANCH=$(grep -m1 'repo_branch:' "$YAML_PATH" | awk '{print $2}')

if [[ "${PRODUCT_CONTEXT^^}" == "RHOAI" ]]; then
  TARGET_VERSION=$(grep -m1 'target_rhoai_version:' "$YAML_PATH" | awk '{print $2}')

  # Parse version components
  VERSION_X=$(echo "$TARGET_VERSION" | cut -d. -f1)
  VERSION_Y=$(echo "$TARGET_VERSION" | cut -d. -f2 | cut -d- -f1)
  VERSION_N=""
  if echo "$TARGET_VERSION" | grep -qE 'ea[-.]?[0-9]+'; then
    VERSION_N=$(echo "$TARGET_VERSION" | grep -oE '[0-9]+$')
  fi

  # Derive expected branch
  if [[ -n "$VERSION_N" ]]; then
    EXPECTED_BRANCH="rhoai-${VERSION_X}.${VERSION_Y}-ea.${VERSION_N}"
  else
    EXPECTED_BRANCH="rhoai-${VERSION_X}.${VERSION_Y}"
  fi

  if [[ "$REPO_BRANCH" != "$EXPECTED_BRANCH" ]]; then
    uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
      --add-label "validation-failed" \
      --remove-label "validation-successful" \
      --comment "Validation failed at Step 3b (Branch Cross-Validation).

For RHOAI components, repo_branch must match the target version.
  target_rhoai_version : $TARGET_VERSION
  expected repo_branch : $EXPECTED_BRANCH
  actual repo_branch   : $REPO_BRANCH

Please correct repo_branch in the YAML, re-upload it, and re-run /validate-component-onboarding-jira." 2>/dev/null || true

    echo "ERROR in Step 3b (Branch Cross-Validation): repo_branch '$REPO_BRANCH' does not match expected '$EXPECTED_BRANCH'. Aborting."
    exit 1
  fi

  echo "Branch cross-validation passed."
fi

# ── Step 5c: Dockerfile digest check (RHOAI only) ────────────────────────────

if [[ "${PRODUCT_CONTEXT^^}" == "ODH" ]]; then
  echo "Dockerfile digest check skipped (not required for ODH components)."
else
  REPO_URL=$(grep -m1 'repo_url:' "$YAML_PATH" | awk '{print $2}')
  CONTEXT_PATH=$(grep -m1 'context_path:' "$YAML_PATH" | awk '{print $2}')
  DOCKERFILE_PATH=$(grep -m1 'dockerfile_path:' "$YAML_PATH" | awk '{print $2}')

  REPO_RAW_BASE="${REPO_URL/github.com/raw.githubusercontent.com}"
  CLEAN_CTX="${CONTEXT_PATH%/}"; CLEAN_CTX="${CLEAN_CTX#./}"

  if [[ -z "$CLEAN_CTX" || "$CLEAN_CTX" == "." ]]; then
    DOCKERFILE_RAW_URL="${REPO_RAW_BASE}/${REPO_BRANCH}/${DOCKERFILE_PATH}"
  else
    DOCKERFILE_RAW_URL="${REPO_RAW_BASE}/${REPO_BRANCH}/${CLEAN_CTX}/${DOCKERFILE_PATH}"
  fi

  echo "Checking Dockerfile digest pinning..."
  DIGEST_ERRORS=""
  DIGEST_EXIT=0
  DIGEST_ERRORS=$(uv run --script "$SCRIPTS_DIR/check_dockerfile_digests.py" \
    --dockerfile-url "$DOCKERFILE_RAW_URL" 2>&1) || DIGEST_EXIT=$?

  if [[ $DIGEST_EXIT -eq 2 ]]; then
    uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
      --add-label "validation-failed" \
      --remove-label "validation-successful" \
      --comment "Validation failed at Step 5c (Dockerfile Digest Check).

Could not fetch the Dockerfile at:
  $DOCKERFILE_RAW_URL

Ensure the repo_url, repo_branch, context_path, and dockerfile_path in the YAML are correct
and that the Dockerfile exists on the specified branch." 2>/dev/null || true

    echo "ERROR in Step 5c (Dockerfile Digest Check): Could not fetch Dockerfile. Aborting."
    exit 1

  elif [[ $DIGEST_EXIT -eq 1 ]]; then
    uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
      --add-label "validation-failed" \
      --remove-label "validation-successful" \
      --comment "Validation failed at Step 5c (Dockerfile Digest Check).

The Dockerfile at $DOCKERFILE_RAW_URL contains FROM instructions that do not pin images
with @sha256 digests:

${DIGEST_ERRORS}

All base and builder images must be pinned using SHA digests, not tags alone.
Example: FROM registry.access.redhat.com/ubi9/ubi-minimal@sha256:<hex>

Please update the Dockerfile and re-run /validate-component-onboarding-jira." 2>/dev/null || true

    echo "$DIGEST_ERRORS"
    echo "ERROR in Step 5c (Dockerfile Digest Check): FROM instructions without @sha256 digests found. Aborting."
    exit 1
  fi

  echo "Dockerfile digest check passed."
fi

# ── Step 6: Update Jira on success ───────────────────────────────────────────

ALREADY_VALIDATED=$(jq -r '[.fields.labels[] | select(. == "validation-successful")] | length > 0' \
  "$WORKDIR/component_onboarding_details.json" 2>/dev/null || echo "false")

if [[ "$ALREADY_VALIDATED" == "true" ]]; then
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --add-label "validation-successful" \
    --remove-label "validation-failed" \
    --status "In Progress" 2>/dev/null || true
else
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --add-label "validation-successful" \
    --remove-label "validation-failed" \
    --comment "Validation passed for ${JIRA_ID}.

All pre-flight checks completed successfully:
- Jira issue details fetched
- component_onboarding_details.yaml attachment downloaded
- Schema validation passed

This ticket is ready for onboarding automation. Moving to In Progress." \
    --status "In Progress" 2>/dev/null || true
fi

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "Validation complete for ${JIRA_ID}."
echo ""
echo "  component_onboarding_details.json  — Jira issue details saved"
echo "  component_onboarding_details.yaml  — Attachment downloaded"
echo "  Schema validation            — PASSED"
echo "  Jira issue updated           — label: validation-successful, status: In Progress"
echo ""
echo "The Jira ticket is valid and ready for onboarding automation."
echo "Output files are in: $WORKDIR"
