#!/usr/bin/env bash
# create-component-onboarding-jira.sh — Creates or updates Jira onboarding ticket with YAML
#
# Usage:
#   ./scripts/create-component-onboarding-jira.sh [--jira-url <url>] [--component-name <name>] [...]
#
# Required env vars:
#   JIRA_USER_EMAIL, JIRA_API_TOKEN
#
# Optional env vars:
#   JIRA_SERVER (default: https://redhat.atlassian.net)
#
# Flags (for non-interactive mode):
#   --jira-url <url>              Existing Jira ticket to update (omit to create new)
#   --product-context <ODH|RHOAI> Product context
#   --component-name <name>       Component name
#   --repo-url <url>              GitHub repo URL
#   --repo-branch <branch>        Branch to build from
#   --context-path <path>         Build context path (default: .)
#   --dockerfile-path <path>      Dockerfile path (default: Dockerfile)
#   --quay-repo <repo>            Quay repo path
#   --is-operator <true|false>    Is this an operator?
#   --target-rhoai-version <ver>  RHOAI version (RHOAI only)

set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parse inputs ──────────────────────────────────────────────────────────────

JIRA_URL=""
PRODUCT_CONTEXT=""
COMPONENT_NAME=""
REPO_URL=""
REPO_BRANCH=""
CONTEXT_PATH="."
DOCKERFILE_PATH="Dockerfile"
QUAY_REPO=""
IS_OPERATOR="false"
TARGET_RHOAI_VERSION=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --jira-url)              JIRA_URL="$2"; shift 2 ;;
    --product-context)       PRODUCT_CONTEXT="$2"; shift 2 ;;
    --component-name)        COMPONENT_NAME="$2"; shift 2 ;;
    --repo-url)              REPO_URL="$2"; shift 2 ;;
    --repo-branch)           REPO_BRANCH="$2"; shift 2 ;;
    --context-path)          CONTEXT_PATH="$2"; shift 2 ;;
    --dockerfile-path)       DOCKERFILE_PATH="$2"; shift 2 ;;
    --quay-repo)             QUAY_REPO="$2"; shift 2 ;;
    --is-operator)           IS_OPERATOR="$2"; shift 2 ;;
    --target-rhoai-version)  TARGET_RHOAI_VERSION="$2"; shift 2 ;;
    *) echo "ERROR: Unknown argument '$1'" >&2; exit 1 ;;
  esac
done

# ── Check prerequisites ───────────────────────────────────────────────────────

bash "$SCRIPTS_DIR/check_prerequisites.sh" --env "JIRA_USER_EMAIL JIRA_API_TOKEN" --tools "uv jq curl"

JIRA_SERVER="${JIRA_SERVER:-https://redhat.atlassian.net}"

# ── Interactive questionnaire (if fields not provided) ────────────────────────

if [[ -z "$PRODUCT_CONTEXT" ]]; then
  read -rp "Product context (ODH or RHOAI): " PRODUCT_CONTEXT
fi

if [[ -z "$COMPONENT_NAME" ]]; then
  read -rp "Component name: " COMPONENT_NAME
fi

if [[ -z "$REPO_URL" ]]; then
  read -rp "Repository URL: " REPO_URL
fi

if [[ -z "$REPO_BRANCH" ]]; then
  if [[ "$PRODUCT_CONTEXT" == "RHOAI" ]]; then
    read -rp "Repository branch (e.g., rhoai-3.5): " REPO_BRANCH
  else
    read -rp "Repository branch (e.g., main): " REPO_BRANCH
  fi
fi

if [[ -z "$QUAY_REPO" ]]; then
  if [[ "$PRODUCT_CONTEXT" == "RHOAI" ]]; then
    DEFAULT_QUAY="quay.io/rhoai/$COMPONENT_NAME"
  else
    DEFAULT_QUAY="quay.io/opendatahub/$COMPONENT_NAME"
  fi
  read -rp "Quay repository [$DEFAULT_QUAY]: " QUAY_REPO
  QUAY_REPO="${QUAY_REPO:-$DEFAULT_QUAY}"
fi

if [[ -z "$IS_OPERATOR" ]]; then
  read -rp "Is this an operator? (true/false) [false]: " IS_OPERATOR
  IS_OPERATOR="${IS_OPERATOR:-false}"
fi

if [[ "$PRODUCT_CONTEXT" == "RHOAI" && -z "$TARGET_RHOAI_VERSION" ]]; then
  read -rp "Target RHOAI version (e.g., 3.5, 3.5-ea-1): " TARGET_RHOAI_VERSION
fi

# ── Generate YAML ─────────────────────────────────────────────────────────────

WORKDIR=$(mktemp -d)
trap "rm -rf '$WORKDIR'" EXIT

cd "$WORKDIR"

echo "Generating component_onboarding_details.yaml..."

if [[ "$PRODUCT_CONTEXT" == "RHOAI" ]]; then
  # Derive delivery repo path
  DELIVERY_REPO_PATH="rhoai/${COMPONENT_NAME}-container"

  cat > component_onboarding_details.yaml <<EOF
product_context: RHOAI
inputs:
  component_name: $COMPONENT_NAME
  repo_url: $REPO_URL
  repo_branch: $REPO_BRANCH
  context_path: $CONTEXT_PATH
  dockerfile_path: $DOCKERFILE_PATH
  quay_repo: $QUAY_REPO
  is_operator: $IS_OPERATOR
  target_rhoai_version: "$TARGET_RHOAI_VERSION"
  delivery_repo_path: $DELIVERY_REPO_PATH
  delivery_repo_visibility: private
EOF
else
  # ODH
  cat > component_onboarding_details.yaml <<EOF
product_context: ODH
inputs:
  component_name: $COMPONENT_NAME
  repo_url: $REPO_URL
  repo_branch: $REPO_BRANCH
  context_path: $CONTEXT_PATH
  dockerfile_path: $DOCKERFILE_PATH
  quay_repo: $QUAY_REPO
  is_operator: $IS_OPERATOR
EOF
fi

# ── Validate YAML ─────────────────────────────────────────────────────────────

SCHEMA_PATH="$SCRIPTS_DIR/../.claude/skills/validate-component-onboarding-jira/assets/component_onboarding_details.schema.json"

if [[ -f "$SCHEMA_PATH" ]]; then
  echo "Validating YAML against schema..."
  uv run --script "$SCRIPTS_DIR/validate_yaml_schema.py" \
    component_onboarding_details.yaml \
    "$SCHEMA_PATH"
else
  echo "WARN: Schema not found at $SCHEMA_PATH. Skipping validation."
fi

# ── Create or identify Jira ticket ───────────────────────────────────────────

if [[ -z "$JIRA_URL" ]]; then
  echo "Creating new Jira ticket from template..."

  # Use Python helper to clone template and create new issue
  JIRA_URL=$(uv run --script "$SCRIPTS_DIR/generate_onboarding_yaml.py" \
    --create-jira-from-template \
    --product-context "$PRODUCT_CONTEXT" \
    --component-name "$COMPONENT_NAME")

  echo "Created Jira ticket: $JIRA_URL"
fi

JIRA_ID="${JIRA_URL##*/}"

# ── Upload YAML attachment ────────────────────────────────────────────────────

echo "Fetching existing attachments..."
ATTACHMENT_LIST=$(curl -s -u "$JIRA_USER_EMAIL:$JIRA_API_TOKEN" \
  "$JIRA_SERVER/rest/api/2/issue/$JIRA_ID" | jq -r '.fields.attachment[]? | select(.filename=="component_onboarding_details.yaml") | .id')

if [[ -n "$ATTACHMENT_LIST" ]]; then
  echo "Deleting old attachment..."
  for ATTACHMENT_ID in $ATTACHMENT_LIST; do
    curl -s -u "$JIRA_USER_EMAIL:$JIRA_API_TOKEN" \
      -X DELETE \
      "$JIRA_SERVER/rest/api/2/attachment/$ATTACHMENT_ID"
  done
fi

echo "Uploading component_onboarding_details.yaml..."
curl -s -u "$JIRA_USER_EMAIL:$JIRA_API_TOKEN" \
  -X POST \
  -H "X-Atlassian-Token: no-check" \
  -F "file=@component_onboarding_details.yaml" \
  "$JIRA_SERVER/rest/api/2/issue/$JIRA_ID/attachments" > /dev/null

# ── Post comment ──────────────────────────────────────────────────────────────

echo "Posting comment to Jira..."
curl -s -u "$JIRA_USER_EMAIL:$JIRA_API_TOKEN" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"body":"Component onboarding YAML has been attached. Ready for automation."}' \
  "$JIRA_SERVER/rest/api/2/issue/$JIRA_ID/comment" > /dev/null

echo "✓ Complete. Jira ticket: $JIRA_URL"
