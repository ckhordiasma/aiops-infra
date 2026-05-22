#!/usr/bin/env bash
# add-component-to-odh-konflux-central.sh — Add Tekton PipelineRun YAMLs to odh-konflux-central
#
# Usage:
#   ./scripts/add-component-to-odh-konflux-central.sh --jira-url <url> [--existing-pr-url <url>]
#
# Required env vars:
#   GITHUB_USER, GITHUB_TOKEN, JIRA_USER_EMAIL, JIRA_API_TOKEN
#
# Optional:
#   ODH_KONFLUX_CENTRAL_REPO_URL — override default repo URL

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
    *)
      if [[ -z "$JIRA_URL" && "$1" == *"/browse/"* ]]; then
        JIRA_URL="$1"; shift
      else
        echo "Unknown argument: $1" >&2; exit 1
      fi
      ;;
  esac
done

# Idempotency fast-path
if [[ -n "$EXISTING_PR_URL" ]]; then
  echo "PR already raised: $EXISTING_PR_URL"
  exit 0
fi

# Parse Jira URL
eval "$(bash "$SCRIPTS_DIR/parse_jira_url.sh" "${JIRA_URL:-}")"
[[ -z "$JIRA_URL" ]] && {
  echo "ERROR: Jira URL is required." >&2
  echo "  Usage: ./scripts/add-component-to-odh-konflux-central.sh --jira-url <jira-url>" >&2
  exit 1
}

# Resolve OKC_URL
OKC_URL="${ODH_KONFLUX_CENTRAL_REPO_URL:-https://github.com/opendatahub-io/odh-konflux-central.git}"
echo "OKC_URL resolved to: $OKC_URL"
OKC_PATH=$(echo "$OKC_URL" | sed 's|https://github.com/||;s|\.git$||')

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
    echo "ERROR: Could not fetch Jira issue details." >&2; exit 1
  }
fi

if [[ ! -f "$WORKDIR/component_onboarding_details.yaml" ]]; then
  cd "$WORKDIR"
  uv run --script "$SCRIPTS_DIR/download_jira_attachment.py" \
    "$JIRA_URL" component_onboarding_details.yaml || {
    echo "ERROR: Could not download 'component_onboarding_details.yaml'." >&2; exit 1
  }
fi

# ── Parse YAML ────────────────
eval "$(bash "$SCRIPTS_DIR/parse_component_details.sh" \
  --workdir     "$WORKDIR" \
  --jira-id     "$JIRA_ID" \
  --scripts-dir "$SCRIPTS_DIR")"

YAML_FILE="$WORKDIR/component_onboarding_details.yaml"
CONTEXT_PATH=$(grep -m1    'context_path:'    "$YAML_FILE" | awk '{print $2}')
DOCKERFILE_PATH=$(grep -m1 'dockerfile_path:' "$YAML_FILE" | awk '{print $2}')
BUILD_TYPE=$(grep -m1      'build_type:'      "$YAML_FILE" | awk '{print $2}')

for _field in COMPONENT_NAME REPO_URL REPO_BRANCH CONTEXT_PATH DOCKERFILE_PATH BUILD_TYPE; do
  [[ -z "${!_field:-}" ]] && {
    echo "ERROR: Missing required field '$_field' in component_onboarding_details.yaml." >&2
    exit 1
  }
done

# Compute derived variables
if [[ "$COMPONENT_NAME" == *-ci ]]; then
  KONFLUX_COMPONENT_NAME="$COMPONENT_NAME"
else
  KONFLUX_COMPONENT_NAME="${COMPONENT_NAME}-ci"
fi

REPO_NAME="${REPO_URL##*/}"
REPO_NAME="${REPO_NAME%.git}"
PUSH_RUN_NAME="${COMPONENT_NAME}-on-push"
PR_RUN_NAME="${COMPONENT_NAME}-on-pull-request"
PUSH_YAML_FILE="${COMPONENT_NAME}-push.yaml"
PR_YAML_FILE="${COMPONENT_NAME}-pull-request.yaml"
SERVICE_ACCOUNT_NAME="build-pipeline-${KONFLUX_COMPONENT_NAME}"

# Output image tags
if [[ "${BUILD_TYPE^^}" == "CI" ]]; then
  PUSH_OUTPUT_IMAGE_TAG="odh-stable"
  PR_OUTPUT_IMAGE_TAG="odh-pr"
elif [[ "${BUILD_TYPE^^}" == "RELEASE" ]]; then
  OUTPUT_IMAGE_TAG=$(grep -m1 'output_image_tag:' "$YAML_FILE" | awk '{print $2}')
  [[ -z "$OUTPUT_IMAGE_TAG" ]] && {
    echo "ERROR: BUILD_TYPE is RELEASE but 'output_image_tag' is not set." >&2; exit 1
  }
  PUSH_OUTPUT_IMAGE_TAG="$OUTPUT_IMAGE_TAG"
  PR_OUTPUT_IMAGE_TAG="$OUTPUT_IMAGE_TAG"
else
  echo "ERROR: Unknown BUILD_TYPE '${BUILD_TYPE}'." >&2; exit 1
fi

# ── Determine product context ──
if [[ "${PRODUCT_CONTEXT^^}" == "RHOAI" ]]; then
  NAMESPACE="rhoai-tenant"
  APPLICATION="rhoai-builds"
  QUAY_ORG="rhoai"
elif [[ "${PRODUCT_CONTEXT^^}" == "ODH" ]]; then
  NAMESPACE="open-data-hub-tenant"
  APPLICATION="opendatahub-builds"
  QUAY_ORG="opendatahub"
else
  echo "ERROR: Unknown PRODUCT_CONTEXT '${PRODUCT_CONTEXT}'." >&2; exit 1
fi

# ── Fast-path check ───────────
PUSH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/${OKC_PATH}/contents/pipelineruns/${REPO_NAME}/${PUSH_YAML_FILE}" 2>/dev/null || echo "000")

PR_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/${OKC_PATH}/contents/pipelineruns/${REPO_NAME}/${PR_YAML_FILE}" 2>/dev/null || echo "000")

if [[ "$PUSH_STATUS" == "200" && "$PR_STATUS" == "200" ]]; then
  echo "PipelineRuns already exist in OKC. Nothing to do."
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --add-label "okc-changes-done" \
    --comment "PipelineRun files for '$COMPONENT_NAME' already exist in OKC repo at 'pipelineruns/$REPO_NAME/'. No action needed."
  exit 0
fi

# ── Set up playpen ────────────
cd "$WORKDIR"
PLAYPEN_OUTPUT=$(bash "$SCRIPTS_DIR/setup_github_playpen.sh" \
  --src-url "$OKC_URL" \
  --src-branch main \
  --dest-branch "$JIRA_ID" \
  --sparse-files "pipelineruns/template pipelineruns/$REPO_NAME .github/workflows") || {
  echo "ERROR: Clone or push failed." >&2; exit 1
}

CLONE_DIR=$(echo "$PLAYPEN_OUTPUT" | head -1)
DEST_BRANCH=$(echo "$PLAYPEN_OUTPUT" | tail -1)

# ── Generate PipelineRun files ──
[[ -f "$CLONE_DIR/pipelineruns/template/odh-component-push.yaml" ]] || {
  echo "ERROR: Push template not found." >&2; exit 1
}
[[ -f "$CLONE_DIR/pipelineruns/template/odh-component-pull-request.yaml" ]] || {
  echo "ERROR: PR template not found." >&2; exit 1
}

mkdir -p "$CLONE_DIR/pipelineruns/$REPO_NAME"

# Push PipelineRun
cp "$CLONE_DIR/pipelineruns/template/odh-component-push.yaml" \
   "$CLONE_DIR/pipelineruns/$REPO_NAME/$PUSH_YAML_FILE"

PUSH_FILE="$CLONE_DIR/pipelineruns/$REPO_NAME/$PUSH_YAML_FILE"
sed -i '' \
  -e "s|component-git-url|${REPO_URL}|g" \
  -e "s|\$\$TARGET_BRANCH\$\$|${REPO_BRANCH}|g" \
  -e "s|odh-component-name-ci|${KONFLUX_COMPONENT_NAME}|g" \
  -e "s|odh-file-name-on-push|${PUSH_RUN_NAME}|g" \
  -e "s|quay.io/opendatahub/quayurl|quay.io/${QUAY_ORG}/${COMPONENT_NAME}|g" \
  -e "s|\$\$OUTPUT_IMAGE_TAG\$\$|${PUSH_OUTPUT_IMAGE_TAG}|g" \
  -e "s|dockerfilepath|${DOCKERFILE_PATH}|g" \
  -e "s|    value: \\.  |    value: ${CONTEXT_PATH}|g" \
  -e "s|build-pipeline-sa-namw|${SERVICE_ACCOUNT_NAME}|g" \
  -e "s|open-data-hub-tenant|${NAMESPACE}|g" \
  -e "s|opendatahub-builds|${APPLICATION}|g" \
  "$PUSH_FILE"

# PR PipelineRun
cp "$CLONE_DIR/pipelineruns/template/odh-component-pull-request.yaml" \
   "$CLONE_DIR/pipelineruns/$REPO_NAME/$PR_YAML_FILE"

PR_FILE="$CLONE_DIR/pipelineruns/$REPO_NAME/$PR_YAML_FILE"
sed -i '' \
  -e "s|build.appstudio.openshift.io/repo: #component-git-url?rev={{revision}}|build.appstudio.openshift.io/repo: ${REPO_URL}?rev={{revision}}|g" \
  -e "s|\$\$TARGET_BRANCH\$\$|${REPO_BRANCH}|g" \
  -e "s|odh-component-name-ci|${KONFLUX_COMPONENT_NAME}|g" \
  -e "s|  name: #odh-file-name-on-pull-request|  name: ${PR_RUN_NAME}|g" \
  -e "s|quay.io/opendatahub/quayurl|quay.io/${QUAY_ORG}/${COMPONENT_NAME}|g" \
  -e "s|\$\$OUTPUT_IMAGE_TAG\$\$|${PR_OUTPUT_IMAGE_TAG}|g" \
  -e "s|dockerfilepath|${DOCKERFILE_PATH}|g" \
  -e "s|    value: \.  |    value: ${CONTEXT_PATH}|g" \
  -e "s|    serviceAccountName: #build-pipeline-sa-name|    serviceAccountName: ${SERVICE_ACCOUNT_NAME}|g" \
  -e "s|  #add these additional params|  # additional params|g" \
  -e "s|open-data-hub-tenant|${NAMESPACE}|g" \
  -e "s|opendatahub-builds|${APPLICATION}|g" \
  "$PR_FILE"

# Update onboarder workflow
WORKFLOW_FILE="$CLONE_DIR/.github/workflows/odh-konflux-onboarder.yml"
if [[ -f "$WORKFLOW_FILE" ]] && ! grep -q "          - ${REPO_NAME}$" "$WORKFLOW_FILE" 2>/dev/null; then
  uv run --script "$SCRIPTS_DIR/edit_yaml.py" insert-list-item \
    "$WORKFLOW_FILE" \
    --list-key "on.workflow_dispatch.inputs.components.options" \
    --value "$REPO_NAME" || {
    echo "ERROR: Could not insert $REPO_NAME into workflow options." >&2; exit 1
  }
fi

# ── Commit and push ───────────
bash "$SCRIPTS_DIR/git_commit_push.sh" \
  --clone-dir "$CLONE_DIR" \
  --files     "." \
  --message   "Add $KONFLUX_COMPONENT_NAME PipelineRuns for $REPO_NAME" \
  --branch    "$DEST_BRANCH" || {
  echo "ERROR: Could not commit or push changes." >&2; exit 1
}

# ── Raise PR (up to 3 attempts) ──
MAX_ATTEMPTS=3
for attempt in $(seq 1 $MAX_ATTEMPTS); do
  PR_URL=$(uv run --script "$SCRIPTS_DIR/raise_github_pr.py" \
    --src-url "$OKC_URL" \
    --src-branch "$DEST_BRANCH" \
    --dest-url "$OKC_URL" \
    --dest-branch main \
    --title "Add $KONFLUX_COMPONENT_NAME PipelineRuns for $COMPONENT_NAME" \
    --description "Add Konflux CI PipelineRuns for '$COMPONENT_NAME' from repo '$REPO_NAME'.

Product: $PRODUCT_CONTEXT
Application: $APPLICATION
Source repo: $REPO_URL @ $REPO_BRANCH
Jira: $JIRA_URL

**Files changed:**
- \`pipelineruns/$REPO_NAME/$PUSH_YAML_FILE\` (new)
- \`pipelineruns/$REPO_NAME/$PR_YAML_FILE\` (new)
- \`.github/workflows/odh-konflux-onboarder.yml\` (updated)" 2>&1) && break

  echo "PR creation attempt $attempt failed: $PR_URL"
  if [[ $attempt -eq $MAX_ATTEMPTS ]]; then
    echo "ERROR: Could not create PR after $MAX_ATTEMPTS attempts." >&2; exit 1
  fi
  if echo "$PR_URL" | grep -qi "branch not found"; then
    cd "$CLONE_DIR" && git push origin "$DEST_BRANCH" 2>/dev/null || true
  fi
  sleep 5
done

# ── Jira update ───────────────
uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
  --add-label "okc-pr-raised" \
  --comment "[step:okc] GitHub PR raised to add Konflux PipelineRuns for '$COMPONENT_NAME' to odh-konflux-central.

PR URL: $PR_URL

CI builds will start for '$COMPONENT_NAME' once this PR is merged."

# ── Done ──────────────────────
echo ""
echo "Done."
echo "  PR raised: $PR_URL"
