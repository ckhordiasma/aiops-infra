#!/usr/bin/env bash
# validate-component-onboarding-jira.sh — Validate component onboarding Jira ticket
#
# Usage:
#   ./scripts/validate-component-onboarding-jira.sh <jira-url>
#
# Required env vars:
#   JIRA_USER_EMAIL    Atlassian account email
#   JIRA_API_TOKEN     Atlassian API token
#
# Optional env vars:
#   JIRA_SERVER        Jira server URL (default: https://redhat.atlassian.net)

set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parse inputs ──────────────

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <jira-url>" >&2
  exit 1
fi

JIRA_URL="$1"

# Parse Jira URL
eval "$(bash "$SCRIPTS_DIR/parse_jira_url.sh" "$JIRA_URL")"
echo "JIRA_URL : $JIRA_URL"
echo "JIRA_ID  : $JIRA_ID"

# ── Check prerequisites ───────

bash "$SCRIPTS_DIR/check_prerequisites.sh" --env "JIRA_USER_EMAIL JIRA_API_TOKEN" --tools "uv"

# ── Set up working directory ──

eval "$(bash "$SCRIPTS_DIR/init_workdir.sh" --jira-url "$JIRA_URL")"
YAML_PATH="${WORKDIR}/component_onboarding_details.yaml"
SCHEMA_PATH="${SCRIPTS_DIR}/../playbooks/assets/component_onboarding_details.schema.json"
echo "Working directory: $WORKDIR"

# ── Step 1: Fetch Jira details ──

cd "$WORKDIR"
uv run --script "$SCRIPTS_DIR/fetch_jira_details.py" "$JIRA_URL" || {
  echo "ERROR in Step 1 (Fetch Jira Details): Could not fetch issue details. Aborting." >&2
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --add-label "validation-failed" \
    --remove-label "validation-successful" \
    --comment "Validation failed at Step 1 (Fetch Jira Details).

Could not fetch issue details. This is typically caused by:
- An invalid or expired JIRA_API_TOKEN
- An incorrect issue key
- A network or permissions issue

Please check your credentials and issue key, then re-run validation." 2>/dev/null || true
  exit 1
}

# ── Step 2: Download YAML ──────

cd "$WORKDIR"
uv run --script "$SCRIPTS_DIR/download_jira_attachment.py" "$JIRA_URL" component_onboarding_details.yaml || {
  echo "ERROR in Step 2 (Download Attachment): 'component_onboarding_details.yaml' not found. Aborting." >&2
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --add-label "validation-failed" \
    --remove-label "validation-successful" \
    --comment "Validation failed at Step 2 (Download Attachment).

The required attachment 'component_onboarding_details.yaml' was not found on this issue.

Please attach a valid 'component_onboarding_details.yaml' file to this ticket and re-run validation." 2>/dev/null || true
  exit 1
}

# ── Step 3: Validate YAML schema ──

VALIDATION_ERRORS=$(uv run --script "$SCRIPTS_DIR/validate_yaml_schema.py" \
  "$YAML_PATH" \
  "$SCHEMA_PATH" 2>&1) || {
  echo "ERROR in Step 3 (Schema Validation): The YAML failed validation. See errors below." >&2
  echo "$VALIDATION_ERRORS" >&2
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --add-label "validation-failed" \
    --remove-label "validation-successful" \
    --comment "Validation failed at Step 3 (Schema Validation).

The 'component_onboarding_details.yaml' attachment did not pass schema validation.

Errors found:
$VALIDATION_ERRORS

Please fix the YAML, re-upload it as an attachment to this ticket, and re-run validation." 2>/dev/null || true
  exit 1
}

echo "Schema validation passed."

# ── Step 3b: Cross-validate branch for RHOAI ──

PRODUCT_CONTEXT=$(grep -m1 'product_context:' "$YAML_PATH" | awk '{print $2}')
REPO_BRANCH=$(grep -m1 'repo_branch:' "$YAML_PATH" | awk '{print $2}')

if [[ "${PRODUCT_CONTEXT^^}" == "RHOAI" ]]; then
  TARGET_VERSION=$(grep -m1 'target_rhoai_version:' "$YAML_PATH" | awk '{print $2}')

  # Derive expected branch
  if [[ "$TARGET_VERSION" =~ ^([0-9]+)\.([0-9]+)-ea-([0-9]+)$ ]]; then
    EXPECTED_BRANCH="rhoai-${BASH_REMATCH[1]}.${BASH_REMATCH[2]}-ea.${BASH_REMATCH[3]}"
  elif [[ "$TARGET_VERSION" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
    EXPECTED_BRANCH="rhoai-${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
  else
    echo "ERROR in Step 3b: Invalid target_rhoai_version format: $TARGET_VERSION" >&2
    exit 1
  fi

  if [[ "$REPO_BRANCH" != "$EXPECTED_BRANCH" ]]; then
    echo "ERROR in Step 3b (Branch Cross-Validation): repo_branch mismatch." >&2
    echo "  target_rhoai_version : $TARGET_VERSION" >&2
    echo "  expected repo_branch : $EXPECTED_BRANCH" >&2
    echo "  actual repo_branch   : $REPO_BRANCH" >&2
    uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
      --add-label "validation-failed" \
      --remove-label "validation-successful" \
      --comment "Validation failed at Step 3b (Branch Cross-Validation).

For RHOAI components, repo_branch must match the target version.
  target_rhoai_version : $TARGET_VERSION
  expected repo_branch : $EXPECTED_BRANCH
  actual repo_branch   : $REPO_BRANCH

Please correct repo_branch in the YAML, re-upload it, and re-run validation." 2>/dev/null || true
    exit 1
  fi
fi

# ── Step 3c: Dockerfile digest check (RHOAI only) ──

if [[ "${PRODUCT_CONTEXT^^}" == "RHOAI" ]]; then
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

  DIGEST_ERRORS=$(uv run --script "$SCRIPTS_DIR/check_dockerfile_digests.py" \
    --dockerfile-url "$DOCKERFILE_RAW_URL" 2>&1) && DIGEST_EXIT=0 || DIGEST_EXIT=$?

  case "$DIGEST_EXIT" in
    0)
      echo "Dockerfile digest check passed."
      ;;
    2)
      echo "ERROR in Step 3c (Dockerfile Digest Check): Could not fetch Dockerfile. Aborting." >&2
      uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
        --add-label "validation-failed" \
        --remove-label "validation-successful" \
        --comment "Validation failed at Step 3c (Dockerfile Digest Check).

Could not fetch the Dockerfile at:
  $DOCKERFILE_RAW_URL

Ensure the repo_url, repo_branch, context_path, and dockerfile_path in the YAML are correct
and that the Dockerfile exists on the specified branch." 2>/dev/null || true
      exit 1
      ;;
    1)
      echo "ERROR in Step 3c (Dockerfile Digest Check): FROM instructions without @sha256 digests found. Aborting." >&2
      echo "$DIGEST_ERRORS" >&2
      uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
        --add-label "validation-failed" \
        --remove-label "validation-successful" \
        --comment "Validation failed at Step 3c (Dockerfile Digest Check).

The Dockerfile at $DOCKERFILE_RAW_URL contains FROM instructions that do not pin images
with @sha256 digests:

$DIGEST_ERRORS

All base and builder images must be pinned using SHA digests, not tags alone.
Example: FROM registry.access.redhat.com/ubi9/ubi-minimal@sha256:<hex>

Please update the Dockerfile and re-run validation." 2>/dev/null || true
      exit 1
      ;;
  esac
else
  echo "Dockerfile digest check skipped (not required for ODH components)."
fi

# ── Step 4: Update Jira on success ──

ALREADY_VALIDATED=$(jq -r '[.fields.labels[] | select(. == "validation-successful")] | length > 0' \
  "$WORKDIR/component_onboarding_details.json")

if [[ "$ALREADY_VALIDATED" == "true" ]]; then
  # Silent update
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --add-label "validation-successful" \
    --remove-label "validation-failed" \
    --status "In Progress" || echo "WARN: Could not update Jira. Update manually." >&2
else
  # Full comment
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --add-label "validation-successful" \
    --remove-label "validation-failed" \
    --comment "Validation passed for $JIRA_ID.

All pre-flight checks completed successfully:
- Jira issue details fetched
- component_onboarding_details.yaml attachment downloaded
- Schema validation passed

This ticket is ready for onboarding automation. Moving to In Progress." \
    --status "In Progress" || echo "WARN: Could not update Jira. Update manually." >&2
fi

# ── Done ──────────────────────

echo ""
echo "Validation complete for $JIRA_ID."
echo ""
echo "  component_onboarding_details.json  — Jira issue details saved"
echo "  component_onboarding_details.yaml  — Attachment downloaded"
echo "  Schema validation            — PASSED"
echo "  Jira issue updated           — label: validation-successful, status: In Progress"
echo ""
echo "The Jira ticket is valid and ready for onboarding automation."
echo "Output files are in: $WORKDIR"
echo ""
