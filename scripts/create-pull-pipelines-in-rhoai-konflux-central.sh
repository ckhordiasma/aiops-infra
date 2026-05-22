#!/usr/bin/env bash
# create-pull-pipelines-in-rhoai-konflux-central.sh — Creates pull request PipelineRun YAMLs
#
# Usage:
#   ./scripts/create-pull-pipelines-in-rhoai-konflux-central.sh <jira-url>
#
# Required env vars:
#   GITHUB_USER, GITHUB_TOKEN
#
# Optional (when jira-url is provided):
#   JIRA_USER_EMAIL, JIRA_API_TOKEN
#
# Optional env vars:
#   RHOAI_KONFLUX_CENTRAL_REPO_URL (default: https://github.com/red-hat-data-services/konflux-central)
#   JIRA_SERVER (default: https://redhat.atlassian.net)

set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parse inputs ──────────────────────────────────────────────────────────────

if [[ $# -lt 1 ]]; then
  echo "ERROR: Jira URL is required"
  echo "Usage: $0 <jira-url>"
  exit 1
fi

JIRA_URL="$1"
JIRA_ID="${JIRA_URL##*/}"

# Resolve RHOAI_KONFLUX_CENTRAL_URL
RHOAI_KONFLUX_CENTRAL_URL="${RHOAI_KONFLUX_CENTRAL_REPO_URL:-https://github.com/red-hat-data-services/konflux-central}"
echo "RHOAI_KONFLUX_CENTRAL_REPO_URL=${RHOAI_KONFLUX_CENTRAL_REPO_URL:-(not set, using default)}"
echo "RHOAI_KONFLUX_CENTRAL_URL resolved to: $RHOAI_KONFLUX_CENTRAL_URL"

echo "JIRA_URL: $JIRA_URL"
echo "JIRA_ID: $JIRA_ID"

# ── Check prerequisites ───────────────────────────────────────────────────────

bash "$SCRIPTS_DIR/check_prerequisites.sh" --env "GITHUB_USER GITHUB_TOKEN" --tools "uv git yamllint"

JIRA_ENABLED=false
if [[ -n "${JIRA_USER_EMAIL:-}" && -n "${JIRA_API_TOKEN:-}" ]]; then
  JIRA_ENABLED=true
fi

# ── Fetch component details from Jira ────────────────────────────────────────

WORKDIR=$(mktemp -d)
trap "rm -rf '$WORKDIR'" EXIT

cd "$WORKDIR"

echo "Fetching Jira issue details..."
uv run --script "$SCRIPTS_DIR/fetch_jira_details.py" --jira-url "$JIRA_URL" > jira_issue.json

echo "Downloading component_onboarding_details.yaml..."
uv run --script "$SCRIPTS_DIR/download_jira_attachment.py" \
  --jira-url "$JIRA_URL" \
  --filename "component_onboarding_details.yaml" \
  > component_onboarding_details.yaml

# Parse component details
COMPONENT_NAME=$(grep -m1 'component_name:' component_onboarding_details.yaml | awk '{print $2}')
REPO_URL=$(grep -m1 'repo_url:' component_onboarding_details.yaml | awk '{print $2}')
REPO_BRANCH=$(grep -m1 'repo_branch:' component_onboarding_details.yaml | awk '{print $2}')
CONTEXT_PATH=$(grep -m1 'context_path:' component_onboarding_details.yaml | awk '{print $2}')
DOCKERFILE_PATH=$(grep -m1 'dockerfile_path:' component_onboarding_details.yaml | awk '{print $2}')
TARGET_VERSION=$(grep -m1 'target_rhoai_version:' component_onboarding_details.yaml | awk '{print $2}')

echo "Component: $COMPONENT_NAME"
echo "Repo: $REPO_URL @ $REPO_BRANCH"
echo "Context: $CONTEXT_PATH / $DOCKERFILE_PATH"
echo "Target RHOAI version: $TARGET_VERSION"

# Derive target branch from version
if [[ "$TARGET_VERSION" =~ -ea-[0-9]+$ ]]; then
  # Version has EA suffix: convert "3.5-ea-1" to "rhoai-3.5-ea.1"
  BASE_VERSION="${TARGET_VERSION%-ea-*}"
  EA_NUM="${TARGET_VERSION##*-ea-}"
  TARGET_BRANCH="rhoai-${BASE_VERSION}-ea.${EA_NUM}"
else
  # No EA suffix: "3.5" becomes "rhoai-3.5"
  TARGET_BRANCH="rhoai-${TARGET_VERSION}"
fi

echo "Target branch: $TARGET_BRANCH"

# ── Fork and clone rhoai-konflux-central ─────────────────────────────────────

echo "Forking rhoai-konflux-central..."
FORK_URL=$(uv run --script "$SCRIPTS_DIR/setup_github_fork.py" --github-repo-url "$RHOAI_KONFLUX_CENTRAL_URL")
echo "Fork: $FORK_URL"

echo "Cloning fork..."
git clone "$FORK_URL" rhoai-konflux-central
cd rhoai-konflux-central

# Add upstream remote
UPSTREAM_URL="$RHOAI_KONFLUX_CENTRAL_URL"
git remote add upstream "$UPSTREAM_URL" 2>/dev/null || true

# ── Create feature branch ─────────────────────────────────────────────────────

BRANCH_NAME="add-${COMPONENT_NAME}-pull-pipeline"
echo "Creating branch: $BRANCH_NAME from upstream/$TARGET_BRANCH"

git fetch upstream
git checkout -b "$BRANCH_NAME" "upstream/$TARGET_BRANCH"

# ── Add pull pipeline YAML ────────────────────────────────────────────────────

echo "Creating pull-pipelines directory if needed..."
mkdir -p pull-pipelines

# Generate <component-name>.yaml
cat > "pull-pipelines/$COMPONENT_NAME.yaml" <<EOF
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  name: $COMPONENT_NAME-pull
spec:
  pipelineRef:
    name: docker-build-pull
  params:
    - name: git-url
      value: $REPO_URL
    - name: revision
      value: \$(params.pr-head-ref)
    - name: output-image
      value: \$(params.output-image)
    - name: path-context
      value: $CONTEXT_PATH
    - name: dockerfile
      value: $DOCKERFILE_PATH
EOF

echo "Validating YAML file..."
yamllint "pull-pipelines/$COMPONENT_NAME.yaml"

# ── Commit and push ───────────────────────────────────────────────────────────

bash "$SCRIPTS_DIR/git_commit_push.sh" \
  --clone-dir "$WORKDIR/rhoai-konflux-central" \
  --files "pull-pipelines/$COMPONENT_NAME.yaml" \
  --message "Add pull request pipeline for $COMPONENT_NAME" \
  --branch "$BRANCH_NAME" \
  --remote origin

# ── Raise GitHub PR ───────────────────────────────────────────────────────────

echo "Raising GitHub PR..."
PR_URL=$(uv run --script "$SCRIPTS_DIR/raise_github_pr.py" \
  --src-url "$FORK_URL" \
  --src-branch "$BRANCH_NAME" \
  --dest-url "$UPSTREAM_URL" \
  --dest-branch "$TARGET_BRANCH" \
  --title "Add pull request pipeline for $COMPONENT_NAME" \
  --description "Adds Tekton pull request PipelineRun configuration for $COMPONENT_NAME targeting RHOAI $TARGET_VERSION.

Related Jira: $JIRA_URL")

echo "PR raised: $PR_URL"

# ── Update Jira (if enabled) ──────────────────────────────────────────────────

if [[ "$JIRA_ENABLED" == "true" ]]; then
  echo "Updating Jira..."
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" \
    --jira-url "$JIRA_URL" \
    --add-labels "rkc-pull-pr-raised" \
    --comment "RHOAI Konflux Central pull pipeline PR raised: $PR_URL"
else
  echo "Jira credentials not provided. Skipping Jira update."
fi

echo "✓ Complete. PR: $PR_URL"
